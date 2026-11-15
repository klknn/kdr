/**
 * Stutter Edit 2 FX Module: Chorus (Multi-Voice Stereo Chorus).
 *
 * Implements multi-voice stereo modulated delay lines with quadrature LFOs,
 * feedback, and stereo width control.
 *
 * Copyright: kdr 2026.
 * License: Boost License 1.0.
 */
module kdr.stutter.fx.chorus;

import std.math : isNaN, isInfinity, PI;
import core.math : sin, cos, fabs;

struct ChorusFX {
  enum size_t BUFFER_SIZE = 4096;
  enum size_t BUFFER_MASK = BUFFER_SIZE - 1;

  float[BUFFER_SIZE] bufL = 0.0f;
  float[BUFFER_SIZE] bufR = 0.0f;
  size_t writePos = 0;
  double lfoPhase = 0.0;
  double sampleRate = 44_100.0;
  float fbLastL = 0.0f;
  float fbLastR = 0.0f;

  @nogc nothrow pure @safe:

  void reset(double sr) {
    sampleRate = (sr > 1000.0 && !isNaN(sr) && !isInfinity(sr)) ? sr : 44_100.0;
    bufL[] = 0.0f;
    bufR[] = 0.0f;
    writePos = 0;
    lfoPhase = 0.0;
    fbLastL = 0.0f;
    fbLastR = 0.0f;
  }

  private static float readLinear(const ref float[BUFFER_SIZE] buf, size_t wPos, float delaySamples) {
    if (delaySamples < 1.0f) delaySamples = 1.0f;
    if (delaySamples > cast(float)(BUFFER_SIZE - 4)) delaySamples = cast(float)(BUFFER_SIZE - 4);
    const float rPos = cast(float)(wPos + BUFFER_SIZE) - delaySamples;
    const size_t i0 = cast(size_t) rPos;
    const float frac = rPos - cast(float) i0;
    const float s0 = buf[i0 & BUFFER_MASK];
    const float s1 = buf[(i0 + 1) & BUFFER_MASK];
    return s0 + frac * (s1 - s0);
  }

  void process(
      float inL, float inR,
      out float outL, out float outR,
      float rateHz,
      float depth,
      float feedback,
      float width,
      float mix,
      bool enabled
  ) {
    if (isNaN(inL) || isInfinity(inL)) inL = 0.0f;
    if (isNaN(inR) || isInfinity(inR)) inR = 0.0f;

    if (!enabled) {
      outL = inL;
      outR = inR;
      return;
    }

    if (isNaN(rateHz) || isInfinity(rateHz)) rateHz = 0.6f;
    if (rateHz < 0.05f) rateHz = 0.05f;
    if (rateHz > 5.0f) rateHz = 5.0f;

    if (isNaN(depth) || isInfinity(depth)) depth = 0.5f;
    if (depth < 0.0f) depth = 0.0f;
    if (depth > 1.0f) depth = 1.0f;

    if (isNaN(feedback) || isInfinity(feedback)) feedback = 0.25f;
    if (feedback < 0.0f) feedback = 0.0f;
    if (feedback > 0.92f) feedback = 0.92f;

    if (isNaN(width) || isInfinity(width)) width = 1.0f;
    if (width < 0.0f) width = 0.0f;
    if (width > 1.0f) width = 1.0f;

    if (isNaN(mix) || isInfinity(mix)) mix = 0.5f;
    if (mix < 0.0f) mix = 0.0f;
    if (mix > 1.0f) mix = 1.0f;

    // Advance quadrature LFO
    lfoPhase += (2.0 * PI * cast(double) rateHz) / sampleRate;
    if (lfoPhase >= 2.0 * PI) lfoPhase -= 2.0 * PI;

    const float baseDelaySamples = cast(float)(0.012 * sampleRate); // 12 ms center
    const float modDepthSamples = cast(float)(0.008 * sampleRate) * depth; // up to 8 ms excursion

    // 2 quadrature voices per channel (0, 90, 180, 270 deg)
    const float lfo1 = cast(float) sin(lfoPhase);
    const float lfo2 = cast(float) cos(lfoPhase);
    const float lfo3 = -lfo1;
    const float lfo4 = -lfo2;

    const float v1 = readLinear(bufL, writePos, baseDelaySamples + lfo1 * modDepthSamples);
    const float v2 = readLinear(bufR, writePos, baseDelaySamples * 1.15f + lfo2 * modDepthSamples);
    const float v3 = readLinear(bufL, writePos, baseDelaySamples * 0.85f + lfo3 * modDepthSamples);
    const float v4 = readLinear(bufR, writePos, baseDelaySamples * 1.25f + lfo4 * modDepthSamples);

    const float rawWetL = 0.5f * (v1 + v3);
    const float rawWetR = 0.5f * (v2 + v4);

    fbLastL = rawWetL;
    fbLastR = rawWetR;

    bufL[writePos & BUFFER_MASK] = inL + feedback * fbLastL;
    bufR[writePos & BUFFER_MASK] = inR + feedback * fbLastR;
    writePos++;

    // Apply stereo width between wetL and wetR
    const float mid = 0.5f * (rawWetL + rawWetR);
    const float side = 0.5f * (rawWetL - rawWetR) * width;
    const float wetL = mid + side;
    const float wetR = mid - side;

    outL = inL * (1.0f - mix) + wetL * mix;
    outR = inR * (1.0f - mix) + wetR * mix;
  }
}

unittest {
  import core.math : sin;
  ChorusFX ch;
  ch.reset(44_100.0);

  float outL, outR;

  // 1. Bypass bit-identical check
  ch.process(0.5f, -0.5f, outL, outR, 1.0f, 0.8f, 0.3f, 1.0f, 0.6f, false);
  assert(outL == 0.5f && outR == -0.5f);

  // 2. Active multi-voice chorus modulates signal and widens mono input into stereo
  ch.reset(44_100.0);
  float diffSum = 0.0f;
  float stereoDiff = 0.0f;
  for (int i = 0; i < 2048; ++i) {
    const float sig = sin(cast(float) i * 0.1f) * 0.7f;
    ch.process(sig, sig, outL, outR, 1.5f, 0.8f, 0.3f, 1.0f, 0.7f, true);
    assert(!isNaN(outL) && !isInfinity(outL));
    assert(!isNaN(outR) && !isInfinity(outR));
    diffSum += fabs(outL - sig);
    stereoDiff += fabs(outL - outR);
  }
  assert(diffSum > 10.0f);
  assert(stereoDiff > 1.0f);
}
