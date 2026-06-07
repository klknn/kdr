module kdr.rezonizer.dsp;

import std.math : sin, cos, exp, exp2;

/// A simple one-pole DC blocker to prevent sub-audio rumble.
struct DCBlocker {
  float prevX = 0.0f;
  float prevY = 0.0f;
  float R = 0.995f;

  @nogc nothrow pure @safe:

  void reset() {
    prevX = 0.0f;
    prevY = 0.0f;
  }

  float apply(float x) {
    float y = x - prevX + R * prevY;
    prevX = x;
    prevY = y;
    return y;
  }
}

/// A fractional-delay feedback comb filter using linear interpolation.
struct FractionalCombFilter {
  enum BUFFER_SIZE = 16384;
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

  /// Applies the comb filter.
  /// Params:
  ///   x = input sample
  ///   delaySamples = fractional delay length in samples
  ///   feedback = feedback coefficient [0, 1)
  ///   damp = high-frequency damping coefficient [0, 1)
  ///   squareMode = if true, uses negative feedback for odd harmonics
  float apply(float x, float delaySamples, float feedback, float damp, bool squareMode) {
    // Clamp delay to safe buffer bounds
    if (delaySamples < 1.0f) delaySamples = 1.0f;
    if (delaySamples > BUFFER_SIZE - 2) delaySamples = BUFFER_SIZE - 2;

    // Calculate fractional read position
    float readPtr = (writePtr - delaySamples + BUFFER_SIZE);
    int idx1 = cast(int) readPtr;
    float frac = readPtr - idx1;

    idx1 = idx1 & BUFFER_MASK;
    int idx2 = (idx1 + 1) & BUFFER_MASK;

    // Linear interpolation of delayed buffer samples
    float delayedVal = (1.0f - frac) * buffer[idx1] + frac * buffer[idx2];

    // High frequency damping (one-pole lowpass filter in the feedback loop)
    feedbackLast = delayedVal * (1.0f - damp) + feedbackLast * damp;

    // Apply polarity inversion for Square mode
    float fbSignal = squareMode ? -feedbackLast : feedbackLast;

    // Write to delay buffer
    buffer[writePtr] = x + feedback * fbSignal;

    // Increment circular write pointer
    writePtr = (writePtr + 1) & BUFFER_MASK;

    return feedbackLast;
  }
}

/// Standard RBJ Biquad Filter supporting Low Pass, High Pass, and Peaking EQ
struct Biquad {
  float b0 = 1.0f, b1 = 0.0f, b2 = 0.0f;
  float a1 = 0.0f, a2 = 0.0f;
  float x1 = 0.0f, x2 = 0.0f;
  float y1 = 0.0f, y2 = 0.0f;

  @nogc nothrow pure @safe:

  void reset() {
    x1 = 0.0f;
    x2 = 0.0f;
    y1 = 0.0f;
    y2 = 0.0f;
  }

  void setHPF(float freq, float sampleRate, float q = 0.707f) {
    if (freq < 10.0f) freq = 10.0f;
    if (freq > sampleRate * 0.49f) freq = sampleRate * 0.49f;

    float w0 = 2.0f * 3.14159265f * freq / sampleRate;
    float alpha = sin(w0) / (2.0f * q);
    float cosw0 = cos(w0);
    float a0 = 1.0f + alpha;

    b0 = (1.0f + cosw0) / (2.0f * a0);
    b1 = -(1.0f + cosw0) / a0;
    b2 = (1.0f + cosw0) / (2.0f * a0);
    a1 = -2.0f * cosw0 / a0;
    a2 = (1.0f - alpha) / a0;
  }

  void setLPF(float freq, float sampleRate, float q = 0.707f) {
    if (freq < 10.0f) freq = 10.0f;
    if (freq > sampleRate * 0.49f) freq = sampleRate * 0.49f;

    float w0 = 2.0f * 3.14159265f * freq / sampleRate;
    float alpha = sin(w0) / (2.0f * q);
    float cosw0 = cos(w0);
    float a0 = 1.0f + alpha;

    b0 = (1.0f - cosw0) / (2.0f * a0);
    b1 = (1.0f - cosw0) / a0;
    b2 = (1.0f - cosw0) / (2.0f * a0);
    a1 = -2.0f * cosw0 / a0;
    a2 = (1.0f - alpha) / a0;
  }

  void setPeaking(float freq, float sampleRate, float q, float gainDb) {
    if (freq < 10.0f) freq = 10.0f;
    if (freq > sampleRate * 0.49f) freq = sampleRate * 0.49f;

    float w0 = 2.0f * 3.14159265f * freq / sampleRate;
    float alpha = sin(w0) / (2.0f * q);
    float cosw0 = cos(w0);
    float A = exp(gainDb * 0.0575646f); // 10^(gainDb/40) = exp(gainDb * ln(10)/40)
    float a0 = 1.0f + alpha / A;

    b0 = (1.0f + alpha * A) / a0;
    b1 = -2.0f * cosw0 / a0;
    b2 = (1.0f - alpha * A) / a0;
    a1 = -2.0f * cosw0 / a0;
    a2 = (1.0f - alpha / A) / a0;
  }

  float apply(float x) {
    float y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
    x2 = x1;
    x1 = x;
    y2 = y1;
    y1 = y;
    return y;
  }
}

/// A lightweight Schroeder Stereo Reverb
struct StereoReverb {
  struct Comb {
    float[8192] buffer = 0.0f;
    int writePtr = 0;
    float last = 0.0f;
    int size = 0;

    @nogc nothrow pure:

    void reset() {
      buffer[] = 0.0f;
      writePtr = 0;
      last = 0.0f;
    }

    void init(int delaySamples) {
      size = delaySamples;
    }

    float apply(float x, float damp, float feedback) {
      if (size <= 0) return x;
      int readPtr = (writePtr - size + 8192) & 8191;
      float dx = buffer[readPtr];
      last = dx * (1.0f - damp) + last * damp;
      buffer[writePtr] = x + feedback * last;
      writePtr = (writePtr + 1) & 8191;
      return dx;
    }
  }

  struct AllPass {
    float[2048] buffer = 0.0f;
    int writePtr = 0;
    int size = 0;
    float coeff = 0.5f;

    @nogc nothrow pure:

    void reset() {
      buffer[] = 0.0f;
      writePtr = 0;
    }

    void init(int delaySamples) {
      size = delaySamples;
    }

    float apply(float x) {
      if (size <= 0) return x;
      int readPtr = (writePtr - size + 2048) & 2047;
      float dx = buffer[readPtr];
      buffer[writePtr] = x + coeff * dx;
      writePtr = (writePtr + 1) & 2047;
      return dx - coeff * (x + coeff * dx);
    }
  }

  Comb[4] combsL;
  Comb[4] combsR;
  AllPass[2] allpassesL;
  AllPass[2] allpassesR;

  @nogc nothrow pure:

  void init(float sampleRate) {
    float scale = sampleRate / 44100.0f;
    combsL[0].init(cast(int)(1116 * scale));
    combsL[1].init(cast(int)(1188 * scale));
    combsL[2].init(cast(int)(1277 * scale));
    combsL[3].init(cast(int)(1356 * scale));

    combsR[0].init(cast(int)((1116 + 23) * scale));
    combsR[1].init(cast(int)((1188 + 23) * scale));
    combsR[2].init(cast(int)((1277 + 23) * scale));
    combsR[3].init(cast(int)((1356 + 23) * scale));

    allpassesL[0].init(cast(int)(556 * scale));
    allpassesL[1].init(cast(int)(441 * scale));

    allpassesR[0].init(cast(int)((556 + 23) * scale));
    allpassesR[1].init(cast(int)((441 + 23) * scale));
  }

  void reset() {
    foreach (ref c; combsL) c.reset();
    foreach (ref c; combsR) c.reset();
    foreach (ref a; allpassesL) a.reset();
    foreach (ref a; allpassesR) a.reset();
  }

  void apply(float inL, float inR, out float outL, out float outR, float wet, float feedback, float damp) {
    if (wet <= 0.0f) {
      outL = inL;
      outR = inR;
      return;
    }

    float yL = 0.0f;
    float yR = 0.0f;

    // Parallel Comb Filters
    foreach (ref c; combsL) yL += c.apply(inL, damp, feedback);
    foreach (ref c; combsR) yR += c.apply(inR, damp, feedback);

    // Serial Allpass Filters
    foreach (ref a; allpassesL) yL = a.apply(yL);
    foreach (ref a; allpassesR) yR = a.apply(yR);

    // Mix Dry & Wet
    outL = inL * (1.0f - wet) + yL * wet * 0.25f;
    outR = inR * (1.0f - wet) + yR * wet * 0.25f;
  }
}

/// Haas Delay line for stereo widening
struct HaasDelay {
  float[4096] buffer = 0.0f;
  int writePtr = 0;

  @nogc nothrow pure:

  void reset() {
    buffer[] = 0.0f;
    writePtr = 0;
  }

  float apply(float x, float delaySamples) {
    if (delaySamples <= 0.0f) return x;
    if (delaySamples > 4000.0f) delaySamples = 4000.0f;

    float readPtr = writePtr - delaySamples + 4096.0f;
    int idx1 = cast(int) readPtr;
    float frac = readPtr - idx1;

    idx1 = idx1 & 4095;
    int idx2 = (idx1 + 1) & 4095;

    float outVal = (1.0f - frac) * buffer[idx1] + frac * buffer[idx2];
    buffer[writePtr] = x;
    writePtr = (writePtr + 1) & 4095;

    return outVal;
  }
}
