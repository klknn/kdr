/**
 * Stutter Edit 2 FX Module: Comb (Tuned Fractional Feedback Comb Filter).
 *
 * Implements stereo fractional-delay feedback comb filtering with one-pole
 * high-frequency damping, bipolar feedback, and stereo phase offset.
 *
 * Copyright: kdr 2026.
 * License: Boost License 1.0.
 */
module kdr.stutter.fx.comb;

import std.math : isNaN, isInfinity;
import core.math : fabs;
import kdr.rezonizer.dsp : FractionalCombFilter;

struct CombFX {
  FractionalCombFilter combL;
  FractionalCombFilter combR;
  double sampleRate = 44_100.0;

  @nogc nothrow pure:

  void reset(double sr) {
    sampleRate = (sr > 1000.0 && !isNaN(sr) && !isInfinity(sr)) ? sr : 44_100.0;
    combL.reset();
    combR.reset();
  }

  void process(
      float inL, float inR,
      out float outL, out float outR,
      float freqHz,
      float feedback,
      float damping,
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

    if (isNaN(freqHz) || isInfinity(freqHz)) freqHz = 200.0f;
    if (freqHz < 20.0f) freqHz = 20.0f;
    if (freqHz > 2000.0f) freqHz = 2000.0f;

    if (isNaN(feedback) || isInfinity(feedback)) feedback = 0.7f;
    if (feedback < -0.98f) feedback = -0.98f;
    if (feedback > 0.98f) feedback = 0.98f;

    if (isNaN(damping) || isInfinity(damping)) damping = 0.2f;
    if (damping < 0.0f) damping = 0.0f;
    if (damping > 0.95f) damping = 0.95f;

    if (isNaN(stereoPhaseDeg) || isInfinity(stereoPhaseDeg)) stereoPhaseDeg = 45.0f;
    if (stereoPhaseDeg < 0.0f) stereoPhaseDeg = 0.0f;
    if (stereoPhaseDeg > 180.0f) stereoPhaseDeg = 180.0f;

    if (isNaN(mix) || isInfinity(mix)) mix = 0.5f;
    if (mix < 0.0f) mix = 0.0f;
    if (mix > 1.0f) mix = 1.0f;

    const float baseDelayL = cast(float)(sampleRate / cast(double) freqHz);
    const float phaseOffsetSamples = baseDelayL * (stereoPhaseDeg / 360.0f) * 0.25f;
    const float baseDelayR = baseDelayL + phaseOffsetSamples;

    const bool negFb = (feedback < 0.0f);
    const float absFb = fabs(feedback);

    float wetL = combL.apply(inL, baseDelayL, absFb, damping, negFb);
    float wetR = combR.apply(inR, baseDelayR, absFb, damping, negFb);

    if (isNaN(wetL) || isInfinity(wetL)) {
      combL.reset();
      wetL = 0.0f;
    }
    if (isNaN(wetR) || isInfinity(wetR)) {
      combR.reset();
      wetR = 0.0f;
    }

    outL = inL * (1.0f - mix) + wetL * mix;
    outR = inR * (1.0f - mix) + wetR * mix;
  }
}

unittest {
  import core.math : sin;
  CombFX comb;
  comb.reset(44_100.0);

  float outL, outR;

  // 1. Bypass bit-identical check
  comb.process(0.6f, -0.3f, outL, outR, 220.0f, 0.8f, 0.2f, 45.0f, 0.8f, false);
  assert(outL == 0.6f && outR == -0.3f);

  // 2. Active comb resonance transforms signal and creates stereo difference
  comb.reset(44_100.0);
  float diffSum = 0.0f;
  float stereoDiff = 0.0f;
  for (int i = 0; i < 1024; ++i) {
    const float sig = (i < 64) ? sin(cast(float) i * 0.3f) : 0.0f;
    comb.process(sig, sig, outL, outR, 220.0f, 0.85f, 0.15f, 90.0f, 0.8f, true);
    assert(!isNaN(outL) && !isInfinity(outL));
    assert(!isNaN(outR) && !isInfinity(outR));
    diffSum += fabs(outL - sig);
    stereoDiff += fabs(outL - outR);
  }
  assert(diffSum > 5.0f);
  assert(stereoDiff > 0.5f);
}
