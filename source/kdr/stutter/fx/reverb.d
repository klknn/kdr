/**
 * Stutter Edit 2 FX Module: Reverb (Stereo Algorithmic Reverb with Pre-Delay & Freeze).
 *
 * Wraps `kdr.rezonizer.dsp.StereoReverb` with a circular stereo pre-delay line
 * (0 - 100 ms) and infinite freeze wash mode.
 *
 * Copyright: kdr 2026.
 * License: Boost License 1.0.
 */
module kdr.stutter.fx.reverb;

import std.math : isNaN, isInfinity;
import core.math : fabs;
import kdr.rezonizer.dsp : StereoReverb;

struct ReverbFX {
  enum size_t PREDELAY_SIZE = 16_384;
  enum size_t PREDELAY_MASK = PREDELAY_SIZE - 1;

  StereoReverb coreReverb;
  float[PREDELAY_SIZE] preBufL = 0.0f;
  float[PREDELAY_SIZE] preBufR = 0.0f;
  size_t writePos = 0;
  double sampleRate = 44_100.0;

  @nogc nothrow pure:

  void reset(double sr) {
    sampleRate = (sr > 1000.0 && !isNaN(sr) && !isInfinity(sr)) ? sr : 44_100.0;
    coreReverb.init(cast(float) sampleRate);
    coreReverb.reset();
    preBufL[] = 0.0f;
    preBufR[] = 0.0f;
    writePos = 0;
  }

  void process(
      float inL, float inR,
      out float outL, out float outR,
      float size,
      float damping,
      float preDelayMs,
      bool freeze,
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

    if (isNaN(size) || isInfinity(size)) size = 0.6f;
    if (size < 0.0f) size = 0.0f;
    if (size > 1.0f) size = 1.0f;

    if (isNaN(damping) || isInfinity(damping)) damping = 0.3f;
    if (damping < 0.0f) damping = 0.0f;
    if (damping > 0.95f) damping = 0.95f;

    if (isNaN(preDelayMs) || isInfinity(preDelayMs)) preDelayMs = 10.0f;
    if (preDelayMs < 0.0f) preDelayMs = 0.0f;
    if (preDelayMs > 100.0f) preDelayMs = 100.0f;

    if (isNaN(mix) || isInfinity(mix)) mix = 0.35f;
    if (mix < 0.0f) mix = 0.0f;
    if (mix > 1.0f) mix = 1.0f;

    // 1. Pre-delay buffer lookup
    int delaySamples = cast(int)(preDelayMs * 0.001f * cast(float) sampleRate);
    if (delaySamples < 0) delaySamples = 0;
    if (delaySamples > cast(int)(PREDELAY_SIZE - 2)) delaySamples = cast(int)(PREDELAY_SIZE - 2);

    preBufL[writePos & PREDELAY_MASK] = inL;
    preBufR[writePos & PREDELAY_MASK] = inR;

    const size_t readIdx = (writePos + PREDELAY_SIZE - cast(size_t) delaySamples) & PREDELAY_MASK;
    const float delayedL = preBufL[readIdx];
    const float delayedR = preBufR[readIdx];
    writePos++;

    // 2. Freeze mode: feedback = 0.999f, damping = 0.0f, new input attenuated
    const float feedback = freeze ? 0.998f : (0.55f + 0.42f * size);
    const float effDamp  = freeze ? 0.0f   : damping;
    const float feedInL  = freeze ? 0.0f   : delayedL;
    const float feedInR  = freeze ? 0.0f   : delayedR;

    float wetOnlyL, wetOnlyR;
    coreReverb.apply(feedInL, feedInR, wetOnlyL, wetOnlyR, 1.0f, feedback, effDamp);

    if (isNaN(wetOnlyL) || isInfinity(wetOnlyL)) {
      coreReverb.reset();
      wetOnlyL = 0.0f;
    }
    if (isNaN(wetOnlyR) || isInfinity(wetOnlyR)) {
      coreReverb.reset();
      wetOnlyR = 0.0f;
    }

    outL = inL * (1.0f - mix) + wetOnlyL * mix;
    outR = inR * (1.0f - mix) + wetOnlyR * mix;
  }
}

unittest {
  ReverbFX rev;
  rev.reset(44_100.0);

  float outL, outR;

  // 1. Bypass bit-identical check
  rev.process(0.5f, -0.5f, outL, outR, 0.8f, 0.3f, 10.0f, false, 0.5f, false);
  assert(outL == 0.5f && outR == -0.5f);

  // 2. Impulse burst produces reverberant tail after dry input ceases
  rev.reset(44_100.0);
  float tailEnergy = 0.0f;
  for (int i = 0; i < 4000; ++i) {
    const float sig = (i < 100) ? 0.8f : 0.0f;
    rev.process(sig, sig, outL, outR, 0.85f, 0.2f, 2.0f, false, 0.8f, true);
    assert(!isNaN(outL) && !isInfinity(outL));
    if (i > 1500) {
      tailEnergy += fabs(outL) + fabs(outR);
    }
  }
  assert(tailEnergy > 1.0f);
}
