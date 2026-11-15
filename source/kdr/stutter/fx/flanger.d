/**
 * Stutter Edit 2 FX Module: Flanger (Sweeping Jet Comb Modulation).
 *
 * Implements short fractional-delay jet flanging (0.1 - 5.0 ms) with Hermite
 * interpolation, bipolar feedback, and stereo LFO phase offset.
 *
 * Copyright: kdr 2026.
 * License: Boost License 1.0.
 */
module kdr.stutter.fx.flanger;

import std.math : isNaN, isInfinity, PI;
import core.math : sin, fabs;

struct FlangerFX {
  enum size_t BUFFER_SIZE = 2048;
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

  private static float readHermite(const ref float[BUFFER_SIZE] buf, size_t wPos, float delaySamples) {
    if (delaySamples < 1.0f) delaySamples = 1.0f;
    if (delaySamples > cast(float)(BUFFER_SIZE - 4)) delaySamples = cast(float)(BUFFER_SIZE - 4);
    const float rPos = cast(float)(wPos + BUFFER_SIZE) - delaySamples;
    const size_t i0 = cast(size_t) rPos;
    const float frac = rPos - cast(float) i0;

    const float ym1 = buf[(i0 - 1) & BUFFER_MASK];
    const float y0  = buf[i0       & BUFFER_MASK];
    const float y1  = buf[(i0 + 1) & BUFFER_MASK];
    const float y2  = buf[(i0 + 2) & BUFFER_MASK];

    const float c0 = y0;
    const float c1 = 0.5f * (y1 - ym1);
    const float c2 = ym1 - 2.5f * y0 + 2.0f * y1 - 0.5f * y2;
    const float c3 = 0.5f * (y2 - ym1) + 1.5f * (y0 - y1);
    return ((c3 * frac + c2) * frac + c1) * frac + c0;
  }

  void process(
      float inL, float inR,
      out float outL, out float outR,
      float rateHz,
      float depthMs,
      float feedback,
      float stereoPhaseDeg,
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

    if (isNaN(rateHz) || isInfinity(rateHz)) rateHz = 0.25f;
    if (rateHz < 0.02f) rateHz = 0.02f;
    if (rateHz > 4.0f) rateHz = 4.0f;

    if (isNaN(depthMs) || isInfinity(depthMs)) depthMs = 2.0f;
    if (depthMs < 0.1f) depthMs = 0.1f;
    if (depthMs > 5.0f) depthMs = 5.0f;

    if (isNaN(feedback) || isInfinity(feedback)) feedback = 0.7f;
    if (feedback < -0.95f) feedback = -0.95f;
    if (feedback > 0.95f) feedback = 0.95f;

    if (isNaN(stereoPhaseDeg) || isInfinity(stereoPhaseDeg)) stereoPhaseDeg = 90.0f;
    if (stereoPhaseDeg < 0.0f) stereoPhaseDeg = 0.0f;
    if (stereoPhaseDeg > 180.0f) stereoPhaseDeg = 180.0f;

    if (isNaN(mix) || isInfinity(mix)) mix = 0.5f;
    if (mix < 0.0f) mix = 0.0f;
    if (mix > 1.0f) mix = 1.0f;

    lfoPhase += (2.0 * PI * cast(double) rateHz) / sampleRate;
    if (lfoPhase >= 2.0 * PI) lfoPhase -= 2.0 * PI;

    const double phaseOffsetRad = cast(double) stereoPhaseDeg * (PI / 180.0);
    const float lfoL = 0.5f * (1.0f + cast(float) sin(lfoPhase));
    const float lfoR = 0.5f * (1.0f + cast(float) sin(lfoPhase + phaseOffsetRad));

    const float minDelaySamples = cast(float)(0.00015 * sampleRate);
    const float maxExcursionSamples = cast(float)(depthMs * 0.001 * sampleRate);

    const float delayL = minDelaySamples + lfoL * maxExcursionSamples;
    const float delayR = minDelaySamples + lfoR * maxExcursionSamples;

    const float wetL = readHermite(bufL, writePos, delayL);
    const float wetR = readHermite(bufR, writePos, delayR);

    fbLastL = wetL;
    fbLastR = wetR;

    float nextBufL = inL + feedback * fbLastL;
    float nextBufR = inR + feedback * fbLastR;
    if (nextBufL > 4.0f) nextBufL = 4.0f;
    if (nextBufL < -4.0f) nextBufL = -4.0f;
    if (nextBufR > 4.0f) nextBufR = 4.0f;
    if (nextBufR < -4.0f) nextBufR = -4.0f;

    bufL[writePos & BUFFER_MASK] = nextBufL;
    bufR[writePos & BUFFER_MASK] = nextBufR;
    writePos++;

    outL = inL * (1.0f - mix) + wetL * mix;
    outR = inR * (1.0f - mix) + wetR * mix;
  }
}

unittest {
  import core.math : sin;
  FlangerFX fl;
  fl.reset(44_100.0);

  float outL, outR;

  // 1. Bypass bit-identical check
  fl.process(0.5f, -0.5f, outL, outR, 0.5f, 2.5f, 0.7f, 90.0f, 0.5f, false);
  assert(outL == 0.5f && outR == -0.5f);

  // 2. Active jet flanger sweeps comb notches and stereo phase
  fl.reset(44_100.0);
  float diffSum = 0.0f;
  float stereoDiff = 0.0f;
  for (int i = 0; i < 1024; ++i) {
    const float sig = sin(cast(float) i * 0.2f) * 0.6f;
    fl.process(sig, sig, outL, outR, 1.0f, 3.0f, 0.75f, 90.0f, 0.6f, true);
    assert(!isNaN(outL) && !isInfinity(outL));
    assert(!isNaN(outR) && !isInfinity(outR));
    diffSum += fabs(outL - sig);
    stereoDiff += fabs(outL - outR);
  }
  assert(diffSum > 10.0f);
  assert(stereoDiff > 0.5f);
}
