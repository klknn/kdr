/**
 * Stutter repetition and rate ramping engine (Stutter Edit 2 clone).
 *
 * Implements tempo-synced subdivisions (1/1 to 1/128), free Hz rates,
 * geometric rate ramping across gesture timelines, stepped quantization locking,
 * click-free 64-sample equal-power cosine crossfading, forward/reverse/pendulum
 * playback trajectories, and fractional pitch scaling integration.
 *
 * Copyright: kdr 2026.
 * License: Boost License 1.0.
 */
module kdr.stutter.stutter;

import std.math : isNaN, isInfinity, PI;
import core.math : cos, sin, fabs;

version (StandaloneTest) {
  enum BufferDirection : int { forward = 0, reverse = 1, pendulum = 2 }
  enum StutterQuantizeMode : int { freeSweep = 0, steppedRhythmic = 1, tripletsOnly = 2, dottedOnly = 3 }
  static immutable double[19] stutterSubdivisionBeats = [
    4.0, 2.0, 1.0, 0.5, 0.25, 0.125, 0.0625, 0.03125,
    4.0 / 3.0, 2.0 / 3.0, 1.0 / 3.0, 0.5 / 3.0, 0.25 / 3.0, 0.125 / 3.0,
    3.0, 1.5, 0.75, 0.375, 0.1875,
  ];
} else {
  import kdr.stutter.params : BufferDirection, StutterQuantizeMode, StutterSubdivision,
    stutterSubdivisionBeats;
}

// Optional import of StereoCaptureBuffer and TVMCurve with compile-time fallbacks for decoupled testing
static if (__traits(compiles, () { import kdr.stutter.buffer : StereoCaptureBuffer; })) {
  import kdr.stutter.buffer : StereoCaptureBuffer;
} else {
  /// Fallback minimal mock of StereoCaptureBuffer for independent testing
  struct StereoCaptureBuffer {
    @nogc nothrow pure:
    void writeSample(float inL, float inR) {}
    void readHermite(float posL, float posR, out float outL, out float outR) const {
      outL = 0.0f;
      outR = 0.0f;
    }
    void reset() {}
  }
}

static if (__traits(compiles, () { import kdr.stutter.tvm : TVMCurve; })) {
  import kdr.stutter.tvm : TVMCurve;
} else {
  /// Minimal contract for TVMCurve
  struct TVMCurve {
    @nogc nothrow pure @safe:
    float evaluate(float p) const {
      if (p < 0.0f) return 0.0f;
      if (p > 1.0f) return 1.0f;
      return p;
    }
  }
}

// =============================================================================
// Constants & Compile-Time Equal-Power Crossfade Tables
// =============================================================================

/// Fixed crossfade duration in samples (eliminates audio clicks at seams)
enum int XfadeLength = 64;

/// Compile-time precomputed cosine lookup table for equal-power crossfade (step 0 to 64)
static immutable float[XfadeLength + 1] cosXfadeTable = () {
  float[XfadeLength + 1] table;
  for (int i = 0; i <= XfadeLength; ++i) {
    const double theta = (cast(double) i / cast(double) XfadeLength) * (3.14159265358979323846 * 0.5);
    import core.math : cos;
    table[i] = cast(float) cos(theta);
  }
  return table;
}();

/// Compile-time precomputed sine lookup table for equal-power crossfade (step 0 to 64)
static immutable float[XfadeLength + 1] sinXfadeTable = () {
  float[XfadeLength + 1] table;
  for (int i = 0; i <= XfadeLength; ++i) {
    const double theta = (cast(double) i / cast(double) XfadeLength) * (3.14159265358979323846 * 0.5);
    import core.math : sin;
    table[i] = cast(float) sin(theta);
  }
  return table;
}();

/// 8 Standard straight subdivision beat values (1/1 down to 1/128)
static immutable double[8] straightSubdivisionBeats = [
  4.0,       // 1/1
  2.0,       // 1/2
  1.0,       // 1/4
  0.5,       // 1/8
  0.25,      // 1/16
  0.125,     // 1/32
  0.0625,    // 1/64
  0.03125,   // 1/128
];

/// 6 Triplet subdivision beat values (1/2T down to 1/64T)
static immutable double[6] tripletSubdivisionBeats = [
  4.0 / 3.0,     // 1/2T
  2.0 / 3.0,     // 1/4T
  1.0 / 3.0,     // 1/8T
  0.5 / 3.0,     // 1/16T
  0.25 / 3.0,    // 1/32T
  0.125 / 3.0,   // 1/64T
];

/// 5 Dotted subdivision beat values (1/2D down to 1/32D)
static immutable double[5] dottedSubdivisionBeats = [
  3.0,       // 1/2D
  1.5,       // 1/4D
  0.75,      // 1/8D
  0.375,     // 1/16D
  0.1875,    // 1/32D
];

// =============================================================================
// Pure Mathematical Helper Functions
// =============================================================================

/// Clamps host tempo to valid range [20.0, 999.0], falling back to default 120.0 BPM
@nogc nothrow pure @safe
double sanitizeTempo(double tempo, double fallbackBPM = 120.0) {
  if (tempo < 20.0 || tempo > 999.0 || isNaN(tempo) || isInfinity(tempo)) {
    return fallbackBPM;
  }
  return tempo;
}

/// Converts beat duration to sample count at the given tempo and sample rate
@nogc nothrow pure @safe
double beatsToSamples(double beats, double tempo, double sampleRate) {
  const double safeTempo = sanitizeTempo(tempo);
  const double safeSr = (sampleRate > 1000.0) ? sampleRate : 44100.0;
  return beats * (60.0 * safeSr / safeTempo);
}

/// Converts frequency in Hz to period in samples
@nogc nothrow pure @safe
double hzToSamples(double hz, double sampleRate) {
  const double safeSr = (sampleRate > 1000.0) ? sampleRate : 44100.0;
  const double safeHz = (hz > 0.05 && hz < 20000.0) ? hz : 10.0;
  return safeSr / safeHz;
}

/// Snaps target beat duration to the nearest value in a sorted subdivision table (logarithmic distance)
@nogc nothrow pure @safe
double snapToSubdivisionSet(double targetBeats, const(double)[] table) {
  if (table.length == 0) return targetBeats;
  if (targetBeats <= 0.0 || isNaN(targetBeats)) return table[table.length - 1];

  import std.math : log2;
  const double targetLog = log2(targetBeats);

  double bestDist = double.infinity;
  double bestBeats = table[0];

  foreach (b; table) {
    const double d = fabs(log2(b) - targetLog);
    if (d < bestDist) {
      bestDist = d;
      bestBeats = b;
    }
  }
  return bestBeats;
}

/// Quantizes beat duration according to the selected StutterQuantizeMode
@nogc nothrow pure @safe
double quantizeBeatDuration(double targetBeats, int quantizeMode) {
  switch (quantizeMode) {
    case StutterQuantizeMode.steppedRhythmic:
      return snapToSubdivisionSet(targetBeats, straightSubdivisionBeats[]);
    case StutterQuantizeMode.tripletsOnly:
      return snapToSubdivisionSet(targetBeats, tripletSubdivisionBeats[]);
    case StutterQuantizeMode.dottedOnly:
      return snapToSubdivisionSet(targetBeats, dottedSubdivisionBeats[]);
    case StutterQuantizeMode.freeSweep:
    default:
      return targetBeats;
  }
}

/// Computes the active stutter beat duration for a given rateStart, rateEnd, and curve progression
@nogc nothrow pure @safe
double evaluateRampedBeats(float rateStart, float rateEnd, float curveVal, int quantizeMode) {
  // Convert rateStart and rateEnd from subdivision enum or raw beats
  double bStart = 0.5;
  double bEnd = 0.0625;

  const int idxStart = cast(int) rateStart;
  if (idxStart >= 0 && idxStart < cast(int) stutterSubdivisionBeats.length) {
    bStart = stutterSubdivisionBeats[idxStart];
  } else if (rateStart > 0.0f) {
    bStart = rateStart;
  }

  const int idxEnd = cast(int) rateEnd;
  if (idxEnd >= 0 && idxEnd < cast(int) stutterSubdivisionBeats.length) {
    bEnd = stutterSubdivisionBeats[idxEnd];
  } else if (rateEnd > 0.0f) {
    bEnd = rateEnd;
  }

  // Geometric / logarithmic interpolation across gesture timeline
  import std.math : log2;
  const double logS = log2(bStart);
  const double logE = log2(bEnd);

  float c = curveVal;
  if (c < 0.0f) c = 0.0f;
  if (c > 1.0f) c = 1.0f;

  const double targetLog = logS + c * (logE - logS);
  const double continuousBeats = 2.0 ^^ targetLog;

  return quantizeBeatDuration(continuousBeats, quantizeMode);
}

// =============================================================================
// Equal-Power 64-Sample Cosine Crossfader
// =============================================================================

/// Internal state for a seamless 64-sample equal-power cosine crossfade
struct CosineCrossfader {
  bool active = false;
  int step = 0;
  int duration = XfadeLength;

  // Outgoing playhead state
  double outPosL = 0.0;
  double outPosR = 0.0;
  double outSpeed = 1.0;
  int outDir = 1;

  @nogc nothrow pure:

  /// Initiates a new crossfade transition from current outgoing position
  void start(double posL, double posR, double speed, int dir, int xfadeLen = XfadeLength) {
    active = true;
    step = 0;
    duration = (xfadeLen >= 2 && xfadeLen <= XfadeLength) ? xfadeLen : XfadeLength;
    outPosL = posL;
    outPosR = posR;
    outSpeed = (speed > 0.01 && speed < 32.0) ? speed : 1.0;
    outDir = (dir == -1) ? -1 : +1;
  }

  /// Cancels / completes active crossfade
  void stop() {
    active = false;
    step = 0;
  }

  /// Computes equal-power crossfade weights for current step
  void getWeights(out float gOut, out float gIn) const @safe {
    if (step <= 0) {
      gOut = 1.0f;
      gIn = 0.0f;
      return;
    }
    if (step >= duration) {
      gOut = 0.0f;
      gIn = 1.0f;
      return;
    }
    if (duration == XfadeLength && step >= 0 && step <= XfadeLength) {
      gOut = cosXfadeTable[step];
      gIn = sinXfadeTable[step];
      return;
    }
    // Arbitrary duration fallback
    const double theta = (cast(double) step / cast(double) duration) * (3.14159265358979323846 * 0.5);
    gOut = cast(float) cos(theta);
    gIn = cast(float) sin(theta);
  }

  /// Advances outgoing playhead and step counter
  void advance() {
    if (!active) return;
    outPosL += outSpeed * outDir;
    outPosR += outSpeed * outDir;
    step++;
    if (step >= duration) {
      active = false;
    }
  }
}

// =============================================================================
// StutterEngine Implementation
// =============================================================================

/// BT Stutter Edit 2 Quantize Step Modes (when Stutter Quantize is enabled).
enum StutterStepMode : int {
  free    = 0,
  closest = 1,
  walk    = 2,
  skip    = 3,
  stagger = 4,
  random  = 5,
}

/// BT Stutter Edit 2 Buffer Movement Modes.
enum BufferMovementMode : int {
  slider = 0,
  grid   = 1,
  random = 2,
}

/// BT Stutter Edit 2 Jitter Pitch Modes.
enum JitterPitchMode : int {
  octaves  = 0,
  octFifth = 1,
  free     = 2,
}

/// Top-of-chain Stutter slice repetition and rate ramping engine
struct StutterEngine {
  @nogc nothrow:

  // Sample rate & transport
  double sampleRate = 44100.0;
  double tempo = 120.0;

  // Activation & latch state
  bool enabled = true;
  bool active = false;
  bool wasActive = false;

  // Gesture trigger anchor & scrub position
  double triggerWriteIndex = 0.0;
  float bufferPosition = 0.0f;
  double maxScrubSamples = 88200.0; // 2.0 seconds scrub range

  // BT Stutter Edit 2 Stutter Step Quantization
  bool quantizeEnabled = true;
  StutterStepMode stepMode = StutterStepMode.closest;
  float stepBeats = 0.25f;
  int currentStepIdx = 4; // index into straightSubdivisionBeats
  double stepTimerBeats = 0.0;
  uint rngState = 0x13572468u;

  // BT Stutter Edit 2 Buffer L/R Reverse, Link, Grid & Jitter
  bool reverseL = false;
  bool reverseR = false;
  bool bufferEnabled = true;
  BufferMovementMode bufferMovement = BufferMovementMode.slider;
  float bufferGridBeats = 0.25f;
  float bufferWidth = 1.0f;
  float bufferCenter = 0.0f;
  bool jitterEnabled = false;
  JitterPitchMode jitterPitchMode = JitterPitchMode.octaves;
  float jitterRhythmAmount = 0.0f;
  float jitterPitchAmount = 0.0f;
  float jitterRate = 0.25f;
  float jitterOffset = 0.0f;

  // Global Freeze locks target slice length & anchor
  bool freezeActive = false;
  float freezeBeats = 0.25f;

  // Slice playback tracking
  double slicePos = 0.0;           // Playhead progression in samples [0.0 .. sliceLength]
  double sliceLength = 22050.0;    // Active slice duration in samples
  double targetSliceLength = 22050.0; // Next target slice duration
  int sliceIteration = 0;          // Loop repetition counter
  int currentDirection = 1;        // +1 = forward, -1 = reverse

  // Crossfade engines
  CosineCrossfader sliceCrossfader; // Loop wrap and direction reversal crossfader
  CosineCrossfader gateCrossfader;  // Activation / de-activation dry-wet crossfader
  bool fadingToDry = false;

  private uint nextRand() pure @safe {
    rngState = rngState * 1664525u + 1013904223u;
    return rngState;
  }

  /// Resets engine state for a new sample rate
  void reset(double sr) pure {
    sampleRate = (sr > 1000.0) ? sr : 44100.0;
    tempo = 120.0;
    enabled = true;
    active = false;
    wasActive = false;
    triggerWriteIndex = 0.0;
    bufferPosition = 0.0f;
    maxScrubSamples = sampleRate * 2.0;

    currentStepIdx = 4;
    stepTimerBeats = 0.0;
    rngState = 0x13572468u;

    slicePos = 0.0;
    sliceLength = sampleRate * 0.5; // Default 1/8 note
    targetSliceLength = sliceLength;
    sliceIteration = 0;
    currentDirection = 1;

    sliceCrossfader.stop();
    gateCrossfader.stop();
    fadingToDry = false;
  }

  /// Updates host tempo (or internal fallback)
  void setTempo(double bpm) pure @safe {
    tempo = sanitizeTempo(bpm);
  }

  /// Manually triggers stuttering anchored to the specified capture buffer write position
  void trigger(size_t captureWriteIndex, float scrubPos = 0.0f) pure {
    active = true;
    wasActive = true;
    triggerWriteIndex = cast(double) captureWriteIndex;
    bufferPosition = scrubPos;
    slicePos = 0.0;
    sliceIteration = 0;
    stepTimerBeats = 0.0;
    currentDirection = 1;
    sliceCrossfader.stop();
    gateCrossfader.start(0.0, 0.0, 1.0, 1, XfadeLength);
    fadingToDry = false;
  }

  /// Releases stuttering, triggering an equal-power crossfade back to dry signal
  void release() pure {
    if (active) {
      active = false;
      fadingToDry = true;
      gateCrossfader.start(0.0, 0.0, 1.0, 1, XfadeLength);
    }
  }

  /// Returns whether stuttering is currently actively affecting audio
  bool isStuttering() const pure @safe {
    return active || gateCrossfader.active;
  }

  /// Returns current active slice duration in musical beats
  double currentSliceBeats() const pure @safe {
    const double spb = beatsToSamples(1.0, tempo, sampleRate);
    return (spb > 0.0) ? (sliceLength / spb) : 0.0;
  }

  /// Computes closest index in `straightSubdivisionBeats`.
  private static int closestSubdivisionIdx(double targetBeats) pure @safe {
    import std.math : log2;
    const double tLog = log2((targetBeats > 1e-4) ? targetBeats : 1e-4);
    int bestIdx = 0;
    double bestDist = double.infinity;
    foreach (i, b; straightSubdivisionBeats) {
      const double d = fabs(log2(b) - tLog);
      if (d < bestDist) {
        bestDist = d;
        bestIdx = cast(int) i;
      }
    }
    return bestIdx;
  }

  /// Processes a single stereo audio sample through the stutter engine
  void process(StereoCaptureBuffer* buf, float inL, float inR, out float outL, out float outR,
               float gesturePhase, float rateStart, float rateEnd, const TVMCurve* rateCurve,
               int quantizeMode, int directionMode, float pitchRatio, float stereoOffset) pure {
    // If disabled and fully idle, pass dry signal through
    if ((!enabled && !freezeActive) || (!active && !gateCrossfader.active && !freezeActive)) {
      outL = inL;
      outR = inR;
      wasActive = false;
      return;
    }

    // Auto-trigger on rising edge of active if not explicitly triggered
    if ((active || freezeActive) && !wasActive) {
      trigger(0, bufferPosition);
    }

    // 1. Evaluate rate ramping & BT Stutter Edit 2 step modes
    const float curveVal = (rateCurve !is null) ? rateCurve.evaluate(gesturePhase) : gesturePhase;
    const int effQuantize = quantizeEnabled ? quantizeMode : StutterQuantizeMode.freeSweep;
    double targetBeats = evaluateRampedBeats(rateStart, rateEnd, curveVal, effQuantize);

    if (freezeActive) {
      targetBeats = (freezeBeats > 0.01f) ? cast(double) freezeBeats : 0.25;
    } else if (quantizeEnabled && stepMode != StutterStepMode.closest && stepMode != StutterStepMode.free) {
      const int desiredIdx = closestSubdivisionIdx(targetBeats);
      final switch (stepMode) {
        case StutterStepMode.walk:
          targetBeats = straightSubdivisionBeats[currentStepIdx];
          break;
        case StutterStepMode.skip:
          targetBeats = straightSubdivisionBeats[currentStepIdx];
          break;
        case StutterStepMode.stagger:
          const int staggerOffset = (sliceIteration % 2 == 0) ? 0 : 1;
          int idx = currentStepIdx + staggerOffset;
          if (idx >= cast(int) straightSubdivisionBeats.length) idx = cast(int) straightSubdivisionBeats.length - 1;
          targetBeats = straightSubdivisionBeats[idx];
          break;
        case StutterStepMode.random:
          targetBeats = straightSubdivisionBeats[currentStepIdx];
          break;
        case StutterStepMode.free:
        case StutterStepMode.closest:
          break;
      }
      // On slice boundary update (handled below via desiredIdx)
      cast(void) desiredIdx;
    }

    if (jitterEnabled && jitterRhythmAmount > 0.01f) {
      const float rNorm = (cast(int)(sliceIteration * 7919) % 100) * 0.01f - 0.5f;
      targetBeats *= (1.0 + cast(double) rNorm * cast(double) jitterRhythmAmount * 0.5);
      if (targetBeats < 0.03125) targetBeats = 0.03125;
    }

    targetSliceLength = beatsToSamples(targetBeats, tempo, sampleRate);
    if (targetSliceLength < 16.0) targetSliceLength = 16.0;

    // 2. Playback speed & pitch scaling (with optional Jitter pitch modulation)
    double speed = (pitchRatio > 0.01f && pitchRatio < 16.0f) ? cast(double) pitchRatio : 1.0;
    if (jitterEnabled && jitterPitchAmount > 0.01f) {
      const int jitHash = (sliceIteration + cast(int)(jitterOffset * 16.0f)) & 3;
      if (jitterPitchMode == JitterPitchMode.octaves) {
        if (jitHash == 1) speed *= 2.0;
        else if (jitHash == 3 && jitterPitchAmount > 0.5f) speed *= 0.5;
      } else if (jitterPitchMode == JitterPitchMode.octFifth) {
        if (jitHash == 1) speed *= 1.4983; // perfect fifth
        else if (jitHash == 2) speed *= 2.0;
        else if (jitHash == 3 && jitterPitchAmount > 0.5f) speed *= 0.5;
      } else {
        const float semi = (jitHash - 1.5f) * 8.0f * jitterPitchAmount;
        import std.math : exp2;
        speed *= exp2(cast(double) semi / 12.0);
      }
    }

    // 3. Determine directional trajectory (with per-channel L/R Reverse support)
    int baseDir = 1;
    switch (directionMode) {
      case BufferDirection.reverse:
        baseDir = -1;
        break;
      case BufferDirection.pendulum:
        baseDir = (sliceIteration % 2 == 0) ? +1 : -1;
        break;
      case BufferDirection.forward:
      default:
        baseDir = +1;
        break;
    }
    currentDirection = baseDir;
    const int dirL = reverseL ? -baseDir : baseDir;
    const int dirR = reverseR ? -baseDir : baseDir;

    // 4. Compute current read positions within capture buffer
    double effBufPos = bufferEnabled ? cast(double) bufferPosition : 0.0;
    if (bufferEnabled && bufferMovement == BufferMovementMode.grid) {
      const double gridBeats = (bufferGridBeats > 0.005f) ? cast(double) bufferGridBeats : 0.25;
      const double stepFrac = (gridBeats / 4.0);
      if (stepFrac > 1e-4) {
        import core.math : fabs;
        const double snapped = cast(int)(effBufPos / stepFrac + 0.5) * stepFrac;
        effBufPos = snapped;
        cast(void) fabs(0.0);
      }
    } else if (bufferEnabled && bufferMovement == BufferMovementMode.random) {
      const uint h = (cast(uint) sliceIteration * 2654435761u) ^ 0x9e3779b9u;
      effBufPos = ((h & 0xFFu) / 255.0) * (0.2 + 0.8 * effBufPos);
    }
    effBufPos = (effBufPos < 0.0) ? 0.0 : ((effBufPos > 1.0) ? 1.0 : effBufPos);

    const double scrubOffset = effBufPos * maxScrubSamples;
    const double anchor = triggerWriteIndex - scrubOffset - sliceLength;

    double localOffsetL = (dirL == +1) ? slicePos : ((sliceLength - 1.0) - slicePos);
    if (localOffsetL < 0.0) localOffsetL = 0.0;
    double localOffsetR = (dirR == +1) ? slicePos : ((sliceLength - 1.0) - slicePos);
    if (localOffsetR < 0.0) localOffsetR = 0.0;

    const double stereoOffsetSamples = (stereoOffset * 0.001) * sampleRate;
    const double posL = anchor + localOffsetL;
    const double posR = anchor + localOffsetR + stereoOffsetSamples;

    // 5. Read stutter audio with Hermite cubic interpolation
    float stutterL = 0.0f;
    float stutterR = 0.0f;

    if (buf !is null) {
      if (sliceCrossfader.active) {
        // Read outgoing slice tail
        float tailL = 0.0f;
        float tailR = 0.0f;
        buf.readHermite(cast(float) sliceCrossfader.outPosL, cast(float) sliceCrossfader.outPosR, tailL, tailR);

        // Read incoming slice head
        float headL = 0.0f;
        float headR = 0.0f;
        buf.readHermite(cast(float) posL, cast(float) posR, headL, headR);

        // Blend using equal-power cosine crossfade
        float gOut, gIn;
        sliceCrossfader.getWeights(gOut, gIn);
        stutterL = tailL * gOut + headL * gIn;
        stutterR = tailR * gOut + headR * gIn;

        sliceCrossfader.advance();
      } else {
        buf.readHermite(cast(float) posL, cast(float) posR, stutterL, stutterR);
      }

      // Apply Buffer Width & Center stereo M/S positioning when Buffer module is enabled
      if (bufferEnabled && (fabs(bufferWidth - 1.0f) > 1e-3f || fabs(bufferCenter) > 1e-3f)) {
        const float mid = 0.5f * (stutterL + stutterR);
        const float side = 0.5f * (stutterL - stutterR) * bufferWidth;
        const float panBias = bufferCenter * 0.5f;
        stutterL = (mid + side) * (1.0f - panBias);
        stutterR = (mid - side) * (1.0f + panBias);
      }
    } else {
      stutterL = inL;
      stutterR = inR;
    }

    // 6. Handle dry/wet activation / release crossfades
    if (gateCrossfader.active) {
      float gOut, gIn;
      gateCrossfader.getWeights(gOut, gIn);
      if (fadingToDry) {
        // Fading from stuttered audio to dry input
        outL = stutterL * gOut + inL * gIn;
        outR = stutterR * gOut + inR * gIn;
      } else {
        // Fading from dry input to stuttered audio
        outL = inL * gOut + stutterL * gIn;
        outR = inR * gOut + stutterR * gIn;
      }
      gateCrossfader.advance();
    } else {
      outL = stutterL;
      outR = stutterR;
    }

    // 7. Advance playhead position
    slicePos += speed;

    // 8. Check for slice loop wrap
    if (slicePos >= sliceLength) {
      // Trigger 64-sample equal-power cosine crossfade for click-free loop wrap
      const int safeXfadeLen = (sliceLength / 2.0 < XfadeLength) ?
          (cast(int)(sliceLength / 2.0) >= 2 ? cast(int)(sliceLength / 2.0) : 2) : XfadeLength;

      sliceCrossfader.start(posL, posR, speed, currentDirection, safeXfadeLen);

      // Update stepped Stutter Quantize Mode index at slice boundaries
      if (quantizeEnabled && !freezeActive) {
        const int maxIdx = cast(int) straightSubdivisionBeats.length - 1;
        const double rawTargetBeats = evaluateRampedBeats(rateStart, rateEnd, curveVal, StutterQuantizeMode.freeSweep);
        const int goalIdx = closestSubdivisionIdx(rawTargetBeats);
        final switch (stepMode) {
          case StutterStepMode.walk:
            if (currentStepIdx < goalIdx) currentStepIdx++;
            else if (currentStepIdx > goalIdx) currentStepIdx--;
            break;
          case StutterStepMode.skip:
            if (currentStepIdx < goalIdx) currentStepIdx = (currentStepIdx + 2 <= goalIdx) ? currentStepIdx + 2 : goalIdx;
            else if (currentStepIdx > goalIdx) currentStepIdx = (currentStepIdx - 2 >= goalIdx) ? currentStepIdx - 2 : goalIdx;
            break;
          case StutterStepMode.stagger:
            if (currentStepIdx < goalIdx) currentStepIdx++;
            else if (currentStepIdx > goalIdx) currentStepIdx--;
            break;
          case StutterStepMode.random:
            currentStepIdx = cast(int)(nextRand() % cast(uint)(maxIdx + 1));
            break;
          case StutterStepMode.closest:
          case StutterStepMode.free:
            currentStepIdx = goalIdx;
            break;
        }
        if (currentStepIdx < 0) currentStepIdx = 0;
        if (currentStepIdx > maxIdx) currentStepIdx = maxIdx;
      }

      // Latch target slice duration for next repetition
      sliceLength = targetSliceLength;
      slicePos = 0.0;
      sliceIteration++;
    }
  }
}

// =============================================================================
// Comprehensive Unit Tests
// =============================================================================

@nogc nothrow pure
unittest {
  // 1. Equal-Power Cosine Crossfade Oracle & Table Verification
  {
    assert(cosXfadeTable.length == 65);
    assert(sinXfadeTable.length == 65);

    // Boundary conditions
    assert(fabs(cosXfadeTable[0] - 1.0f) < 1e-6f);
    assert(fabs(sinXfadeTable[0] - 0.0f) < 1e-6f);
    assert(fabs(cosXfadeTable[64] - 0.0f) < 1e-6f);
    assert(fabs(sinXfadeTable[64] - 1.0f) < 1e-6f);

    // Midpoint equal-power sum (cos^2 + sin^2 == 1.0)
    for (int i = 0; i <= 64; ++i) {
      const float c = cosXfadeTable[i];
      const float s = sinXfadeTable[i];
      const float powerSum = c * c + s * s;
      assert(fabs(powerSum - 1.0f) < 1e-5f);
    }

    // Midpoint amplitude ~ 0.7071
    assert(fabs(cosXfadeTable[32] - 0.707106f) < 1e-3f);
    assert(fabs(sinXfadeTable[32] - 0.707106f) < 1e-3f);
  }

  // 2. Tempo and Subdivision Conversion Tests
  {
    assert(sanitizeTempo(120.0) == 120.0);
    assert(sanitizeTempo(0.0) == 120.0);
    assert(sanitizeTempo(-10.0) == 120.0);
    assert(sanitizeTempo(1200.0) == 120.0);

    // 1/4 note at 120 BPM, 44.1 kHz = 22,050 samples
    const double s1_4 = beatsToSamples(1.0, 120.0, 44100.0);
    assert(fabs(s1_4 - 22050.0) < 1e-4);

    // 1/16 note = 5,512.5 samples
    const double s1_16 = beatsToSamples(0.25, 120.0, 44100.0);
    assert(fabs(s1_16 - 5512.5) < 1e-4);

    // 1/128 note = 689.0625 samples
    const double s1_128 = beatsToSamples(0.03125, 120.0, 44100.0);
    assert(fabs(s1_128 - 689.0625) < 1e-4);

    // Free Hz rate conversion (20 Hz at 44.1k = 2205 samples)
    const double s20Hz = hzToSamples(20.0, 44100.0);
    assert(fabs(s20Hz - 2205.0) < 1e-4);
  }

  // 3. Rate Ramping and Quantization Tests
  {
    // Stepped rhythmic quantize snaps continuous values to straight subdivisions
    assert(quantizeBeatDuration(0.48, StutterQuantizeMode.steppedRhythmic) == 0.5); // Snaps to 1/8
    assert(quantizeBeatDuration(0.24, StutterQuantizeMode.steppedRhythmic) == 0.25); // Snaps to 1/16
    assert(quantizeBeatDuration(0.07, StutterQuantizeMode.steppedRhythmic) == 0.0625); // Snaps to 1/64

    // Triplets only snapping
    const double tripSnap = quantizeBeatDuration(0.35, StutterQuantizeMode.tripletsOnly);
    assert(fabs(tripSnap - (1.0 / 3.0)) < 1e-4); // 1/8T

    // Free sweep mode preserves exact continuous beat values
    assert(quantizeBeatDuration(0.371, StutterQuantizeMode.freeSweep) == 0.371);

    // Geometric rate ramping between 1/8 (0.5) and 1/64 (0.0625)
    // At phase 0.0 -> 0.5
    assert(evaluateRampedBeats(3, 6, 0.0f, StutterQuantizeMode.freeSweep) == 0.5);
    // At phase 1.0 -> 0.0625
    assert(evaluateRampedBeats(3, 6, 1.0f, StutterQuantizeMode.freeSweep) == 0.0625);
    // At phase 0.5 -> 2^(-2.5) ~ 0.17677
    const double midBeats = evaluateRampedBeats(3, 6, 0.5f, StutterQuantizeMode.freeSweep);
    assert(midBeats > 0.0625 && midBeats < 0.5);
  }

  // 4. StutterEngine Lifecycle & Audio Processing Tests
  {
    StutterEngine engine;
    engine.reset(44100.0);
    assert(engine.sampleRate == 44100.0);
    assert(!engine.isStuttering());

    // Process dry pass-through when inactive
    float outL, outR;
    engine.process(null, 0.75f, -0.75f, outL, outR, 0.0f, 3, 6, null, 0, 0, 1.0f, 0.0f);
    assert(outL == 0.75f && outR == -0.75f);

    // Trigger stutter
    engine.trigger(10000, 0.0f);
    assert(engine.isStuttering());
    assert(engine.sliceIteration == 0);

    // Run 100 samples
    for (int i = 0; i < 100; ++i) {
      engine.process(null, 0.5f, 0.5f, outL, outR, 0.1f, 3, 6, null, 0, 0, 1.0f, 0.0f);
      assert(!isNaN(outL) && !isNaN(outR));
      assert(!isInfinity(outL) && !isInfinity(outR));
    }

    // Release stutter
    engine.release();
    // Run crossfade back to dry
    for (int i = 0; i < 70; ++i) {
      engine.process(null, 0.3f, 0.3f, outL, outR, 0.2f, 3, 6, null, 0, 0, 1.0f, 0.0f);
    }
    assert(!engine.isStuttering());
  }

  // 5. Direction Modes & Pendulum Alternation Tests
  {
    StutterEngine engine;
    engine.reset(44100.0);
    engine.sliceLength = 100.0;
    engine.targetSliceLength = 100.0;
    engine.trigger(50000, 0.0f);

    // Pendulum mode: iteration 0 forward, iteration 1 reverse
    float outL, outR;
    for (int i = 0; i < 99; ++i) {
      engine.process(null, 0.1f, 0.1f, outL, outR, 0.0f, 3, 6, null, 0, BufferDirection.pendulum, 1.0f, 0.0f);
    }
    assert(engine.sliceIteration == 0);
    assert(engine.currentDirection == +1);

    // Sample 100 triggers wrap and iteration 1
    engine.process(null, 0.1f, 0.1f, outL, outR, 0.0f, 3, 6, null, 0, BufferDirection.pendulum, 1.0f, 0.0f);
    engine.process(null, 0.1f, 0.1f, outL, outR, 0.0f, 3, 6, null, 0, BufferDirection.pendulum, 1.0f, 0.0f);
    assert(engine.sliceIteration == 1);
    assert(engine.currentDirection == -1);
  }

  // 6. Pitch Scaling Integration Tests
  {
    StutterEngine engine;
    engine.reset(44100.0);
    engine.sliceLength = 1000.0;
    engine.targetSliceLength = 1000.0;
    engine.trigger(10000, 0.0f);

    // Normal pitch (ratio 1.0) -> advances by 1.0 per sample
    float outL, outR;
    const double pStart = engine.slicePos;
    engine.process(null, 0.0f, 0.0f, outL, outR, 0.0f, 3, 6, null, 0, 0, 1.0f, 0.0f);
    assert(fabs((engine.slicePos - pStart) - 1.0) < 1e-4);

    // Double pitch (ratio 2.0 = +12 semitones) -> advances by 2.0 per sample
    const double pStart2 = engine.slicePos;
    engine.process(null, 0.0f, 0.0f, outL, outR, 0.0f, 3, 6, null, 0, 0, 2.0f, 0.0f);
    assert(fabs((engine.slicePos - pStart2) - 2.0) < 1e-4);

    // Half pitch (ratio 0.5 = -12 semitones) -> advances by 0.5 per sample
    const double pStart3 = engine.slicePos;
    engine.process(null, 0.0f, 0.0f, outL, outR, 0.0f, 3, 6, null, 0, 0, 0.5f, 0.0f);
    assert(fabs((engine.slicePos - pStart3) - 0.5) < 1e-4);
  }
}
