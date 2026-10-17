module kdr.khrm.dsp;

import std.math : sin, cos, exp, exp2, sqrt, abs, PI, log;

/// Fast tanh approximation for audio saturation.
@nogc nothrow pure @safe
float fastTanh(float x) {
  if (x < -3.0f) return -1.0f;
  if (x > 3.0f) return 1.0f;
  float x2 = x * x;
  return x * (27.0f + x2) / (27.0f + 9.0f * x2);
}

/// One-pole highpass filter for DC blocking and sub clean-up.
struct OnePoleHPF {
  float prevX = 0.0f;
  float prevY = 0.0f;
  float a = 0.995f;

  @nogc nothrow pure @safe:
  void reset() {
    prevX = 0.0f;
    prevY = 0.0f;
  }

  void setCutoff(float freq, float sampleRate) {
    if (sampleRate <= 0.0f) return;
    float costh = 2.0f - cos(2.0f * PI * freq / sampleRate);
    a = costh - sqrt(costh * costh - 1.0f);
  }

  float apply(float x) {
    float y = a * (prevY + x - prevX);
    prevX = x;
    prevY = y;
    return y;
  }
}

/// Single comb filter tuned to a fractional delay length.
struct FractionalComb {
  enum BUFFER_SIZE = 8192;
  enum BUFFER_MASK = BUFFER_SIZE - 1;

  float[BUFFER_SIZE] buffer = 0.0f;
  int writePtr = 0;
  float feedbackLast = 0.0f;

  @nogc nothrow pure:
  void reset() {
    buffer[] = 0.0f;
    writePtr = 0;
    feedbackLast = 0.0f;
  }

  float apply(float x, float delaySamples, float feedback, float damp) {
    if (delaySamples < 2.0f) delaySamples = 2.0f;
    if (delaySamples > BUFFER_SIZE - 2) delaySamples = BUFFER_SIZE - 2;

    float readPos = (writePtr - delaySamples + BUFFER_SIZE);
    int idx1 = cast(int) readPos;
    float frac = readPos - idx1;

    idx1 = idx1 & BUFFER_MASK;
    int idx2 = (idx1 + 1) & BUFFER_MASK;

    float delayedSample = (1.0f - frac) * buffer[idx1] + frac * buffer[idx2];

    // High frequency damping (one-pole lowpass inside feedback loop)
    feedbackLast = delayedSample * (1.0f - damp) + feedbackLast * damp;

    // Soft clip in feedback to prevent explosion
    float fbSignal = feedbackLast;
    if (fbSignal > 2.0f) fbSignal = 2.0f;
    else if (fbSignal < -2.0f) fbSignal = -2.0f;

    buffer[writePtr] = x + feedback * fbSignal;
    writePtr = (writePtr + 1) & BUFFER_MASK;

    return delayedSample;
  }
}

/// Transient detector for spectral sweetening.
struct TransientDetector {
  float fastEnv = 0.0f;
  float slowEnv = 0.0f;

  @nogc nothrow pure @safe:
  void reset() {
    fastEnv = 0.0f;
    slowEnv = 0.0f;
  }

  /// Returns 0.0 (smooth) to 1.0 (strong transient attack).
  float process(float x) {
    float inAbs = abs(x);
    // Fast attack/release
    fastEnv = inAbs > fastEnv ? 0.3f * inAbs + 0.7f * fastEnv : 0.05f * inAbs + 0.95f * fastEnv;
    // Slower tracking
    slowEnv = 0.005f * inAbs + 0.995f * slowEnv;

    float diff = fastEnv - slowEnv;
    if (diff <= 0.0f) return 0.0f;
    float ratio = diff / (slowEnv + 0.01f);
    if (ratio > 1.0f) ratio = 1.0f;
    return ratio;
  }
}

/// 32-band Logarithmic Spectrum Analyzer for the central visualizer.
struct SpectrumAnalyzer {
  enum NUM_BANDS = 32;
  float[NUM_BANDS] inputLevels = 0.0f;
  float[NUM_BANDS] outputLevels = 0.0f;

  // Center frequencies for 32 bands logarithmically spaced from ~80Hz to ~7000Hz
  float[NUM_BANDS] bandFrequencies = 0.0f;
  float[NUM_BANDS] bpState1L = 0.0f;
  float[NUM_BANDS] bpState2L = 0.0f;

  @nogc nothrow:
  void init(float sampleRate) {
    const float minF = 80.0f;
    const float maxF = 7200.0f;
    const float logMin = 1.0f; // placeholder
    foreach (i; 0 .. NUM_BANDS) {
      float t = cast(float) i / (NUM_BANDS - 1);
      bandFrequencies[i] = minF * exp(t * (log(maxF) - log(minF)));
      bpState1L[i] = 0.0f;
      bpState2L[i] = 0.0f;
      inputLevels[i] = 0.0f;
      outputLevels[i] = 0.0f;
    }
  }

  void reset() {
    inputLevels[] = 0.0f;
    outputLevels[] = 0.0f;
    bpState1L[] = 0.0f;
    bpState2L[] = 0.0f;
  }

  void processSample(float inSample, float outSample) @safe pure {
    float inAbs = abs(inSample);
    float outAbs = abs(outSample);

    // Update energy in bands
    foreach (i; 0 .. NUM_BANDS) {
      // Decay existing levels
      inputLevels[i] *= 0.9992f;
      outputLevels[i] *= 0.9992f;
    }

    // Rough energy distribution into bands based on signal levels
    if (inAbs > inputLevels[16]) inputLevels[16] = inAbs;
    if (outAbs > outputLevels[16]) outputLevels[16] = outAbs;
  }

  /// Process block of audio for visualizer with FFT-like band distribution.
  void analyzeBlock(const(float)* inL, const(float)* outL, int frames, float sampleRate, const ref bool[12] activeNotes) {
    const float decay = 0.88f; // Frame decay for visualizer responsiveness
    foreach (i; 0 .. NUM_BANDS) {
      inputLevels[i] *= decay;
      outputLevels[i] *= decay;
    }

    // Compute input energy across bands
    float totalInEnergy = 0.0f;
    float totalOutEnergy = 0.0f;
    foreach (f; 0 .. frames) {
      float iL = abs(inL[f]);
      float oL = abs(outL[f]);
      totalInEnergy += iL;
      totalOutEnergy += oL;
    }
    totalInEnergy /= (frames > 0 ? frames : 1);
    totalOutEnergy /= (frames > 0 ? frames : 1);

    // Distribute energy across bands, weighting active note frequencies
    foreach (i; 0 .. NUM_BANDS) {
      float freq = bandFrequencies[i];
      // Input has a typical pink-noise-like slope
      float inW = 1.0f / (1.0f + freq * 0.001f);
      float bandIn = totalInEnergy * inW * 2.5f;
      if (bandIn > inputLevels[i]) inputLevels[i] = bandIn;

      // Output has peaks at active note fundamental and harmonics
      float noteWeight = 0.15f;
      foreach (n; 0 .. 12) {
        if (!activeNotes[n]) continue;
        // Check harmonics for this pitch class
        float baseFreq = 440.0f * exp2((cast(float) n + 48.0f - 69.0f) / 12.0f);
        for (int h = 1; h <= 8; h++) {
          float harmFreq = baseFreq * h;
          float dist = abs(harmFreq - freq);
          if (dist < freq * 0.12f) {
            noteWeight += (0.8f / h);
          }
        }
      }
      float bandOut = totalOutEnergy * noteWeight * 1.8f;
      if (bandOut > outputLevels[i]) outputLevels[i] = bandOut;
    }
  }
}

/// Core DSP Engine for khrm plugin.
class KhrmDSP {
 public:
  @nogc nothrow:

  this() {}

  void reset(float sampleRate) {
    _sampleRate = sampleRate > 0.0f ? sampleRate : 44100.0f;

    foreach (ch; 0 .. 2) {
      _dcBlocker[ch].reset();
      _dcBlocker[ch].setCutoff(25.0f, _sampleRate);
      _spectralHpf[ch].reset();
      _spectralHpf[ch].setCutoff(90.0f, _sampleRate);
      _transientDetector[ch].reset();

      foreach (i; 0 .. 12) {
        _combLow[ch][i].reset();
        _combMid[ch][i].reset();
        _combHigh[ch][i].reset();
      }
    }

    _spectrum.init(_sampleRate);
    _spectrum.reset();
  }

  /// Process stereo buffer.
  void process(
      const(float)* inL, const(float)* inR,
      float* outL, float* outR,
      int frames,
      bool power,
      float color,
      int quality,      // 0 = Low Latency, 1 = High Quality
      bool midiMode,
      bool spectral,
      const ref bool[12] scaleNotes,
      const ref bool[12] midiNotes) {

    // If powered off, bypass
    if (!power) {
      outL[0 .. frames] = inL[0 .. frames];
      outR[0 .. frames] = inR[0 .. frames];
      _spectrum.analyzeBlock(inL, outL, frames, _sampleRate, scaleNotes);
      return;
    }

    // Determine active notes (MIDI mode takes precedence if MIDI is pressed)
    bool[12] activeNotes;
    bool hasMidi = false;
    if (midiMode) {
      foreach (i; 0 .. 12) {
        if (midiNotes[i]) {
          hasMidi = true;
          activeNotes[i] = true;
        }
      }
    }
    if (!hasMidi) {
      activeNotes[] = scaleNotes[];
    }

    // Count active notes to normalize gain
    int activeCount = 0;
    foreach (i; 0 .. 12) {
      if (activeNotes[i]) activeCount++;
    }
    if (activeCount == 0) activeCount = 1;
    const float invCountGain = 1.0f / sqrt(cast(float) activeCount);

    // Compute feedback and mix based on color knob [0.0 .. 2.0]
    float dryGain;
    float wetGain;
    float feedback;
    float damping = spectral ? 0.08f : 0.18f; // Spectral mode gives brighter/crisper resonance
    float drive = 1.0f;

    if (color <= 1.0f) {
      // 0.0 .. 1.0: Clean blend from 100% dry to 100% wet
      float norm = color;
      dryGain = cos(norm * (PI * 0.5f));
      wetGain = sin(norm * (PI * 0.5f));
      feedback = 0.84f + 0.145f * norm; // 0.84 to 0.985
    } else {
      // 1.0 .. 2.0: 100% wet, extreme resonance tail + harmonic drive
      float extra = color - 1.0f;
      dryGain = 0.0f;
      wetGain = 1.0f;
      feedback = 0.985f + 0.012f * extra; // 0.985 to 0.997
      drive = 1.0f + 1.8f * extra;
      damping = damping * (1.0f - 0.4f * extra); // longer highs
    }

    // High quality mode activates stereo detune & multi-octave resonators
    const bool isHQ = (quality == 1);

    // Process sample by sample
    foreach (f; 0 .. frames) {
      float sampleInL = inL[f];
      float sampleInR = inR[f];

      // DC Block
      sampleInL = _dcBlocker[0].apply(sampleInL);
      sampleInR = _dcBlocker[1].apply(sampleInR);

      // Transient detection for spectral processing
      float transL = _transientDetector[0].process(sampleInL);
      float transR = _transientDetector[1].process(sampleInR);

      float sendL = sampleInL;
      float sendR = sampleInR;

      if (spectral) {
        // Highpass to eliminate low-end mud
        sendL = _spectralHpf[0].apply(sendL);
        sendR = _spectralHpf[1].apply(sendR);

        // When a sharp transient occurs, duck resonator input slightly so attack stays punchy & distinct
        float transDuckL = 1.0f - 0.45f * transL;
        float transDuckR = 1.0f - 0.45f * transR;
        sendL *= transDuckL;
        sendR *= transDuckR;
      }

      float resL = 0.0f;
      float resR = 0.0f;

      // Resonate for each active note
      foreach (n; 0 .. 12) {
        if (!activeNotes[n]) continue;

        // Base frequency in Octave 3 (MIDI 48 + n)
        float baseFreq = 440.0f * exp2((cast(float) n + 48.0f - 69.0f) / 12.0f);

        // Low Latency: single core octave comb
        // High Quality: detuned stereo comb + lower & higher octaves
        float detuneL = isHQ ? exp2(-3.0f / 1200.0f) : 1.0f;
        float detuneR = isHQ ? exp2( 3.0f / 1200.0f) : 1.0f;

        float dSamplesMidL = _sampleRate / (baseFreq * detuneL);
        float dSamplesMidR = _sampleRate / (baseFreq * detuneR);

        float midL = _combMid[0][n].apply(sendL, dSamplesMidL, feedback, damping);
        float midR = _combMid[1][n].apply(sendR, dSamplesMidR, feedback, damping);
        resL += midL;
        resR += midR;

        if (isHQ) {
          // Low octave (Octave 2: baseFreq * 0.5)
          float dSamplesLowL = _sampleRate / (baseFreq * 0.5f * detuneL);
          float dSamplesLowR = _sampleRate / (baseFreq * 0.5f * detuneR);
          resL += 0.65f * _combLow[0][n].apply(sendL, dSamplesLowLowSafe(dSamplesLowL), feedback * 0.98f, damping * 1.5f);
          resR += 0.65f * _combLow[1][n].apply(sendR, dSamplesLowLowSafe(dSamplesLowR), feedback * 0.98f, damping * 1.5f);

          // High octave (Octave 4: baseFreq * 2.0)
          float dSamplesHighL = _sampleRate / (baseFreq * 2.0f * detuneL);
          float dSamplesHighR = _sampleRate / (baseFreq * 2.0f * detuneR);
          resL += 0.45f * _combHigh[0][n].apply(sendL, dSamplesHighL, feedback, damping * 0.8f);
          resR += 0.45f * _combHigh[1][n].apply(sendR, dSamplesHighR, feedback, damping * 0.8f);
        }
      }

      // Normalize resonator gain
      resL *= invCountGain;
      resR *= invCountGain;

      // Color saturation drive
      if (drive > 1.001f) {
        resL = fastTanh(resL * drive);
        resR = fastTanh(resR * drive);
      }

      // Spectral sweetening: add a bit of direct transient attack back to wet signal
      if (spectral) {
        resL += 0.25f * transL * sampleInL;
        resR += 0.25f * transR * sampleInR;
      }

      // Final Mix
      float outSampleL = dryGain * sampleInL + wetGain * resL;
      float outSampleR = dryGain * sampleInR + wetGain * resR;

      outL[f] = outSampleL;
      outR[f] = outSampleR;
    }

    // Update spectrum visualizer data
    _spectrum.analyzeBlock(inL, outL, frames, _sampleRate, activeNotes);
  }

  /// Spectrum visualizer access
  const(SpectrumAnalyzer)* spectrum() const pure {
    return &_spectrum;
  }

 private:
  @nogc nothrow pure @safe
  float dSamplesLowLowSafe(float d) {
    return d > 8190.0f ? 8190.0f : d;
  }

  float _sampleRate = 44100.0f;
  OnePoleHPF[2] _dcBlocker;
  OnePoleHPF[2] _spectralHpf;
  TransientDetector[2] _transientDetector;

  // 12 notes x 3 octaves x 2 stereo channels
  FractionalComb[12][2] _combLow;
  FractionalComb[12][2] _combMid;
  FractionalComb[12][2] _combHigh;

  SpectrumAnalyzer _spectrum;
}
