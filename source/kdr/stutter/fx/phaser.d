/**
 * Stutter Edit 2 FX Module: Phaser (Multi-Stage All-Pass Phase Shifter).
 *
 * Implements 4, 6, 8, or 12 cascaded 1st-order all-pass stages (`kdr.filter.AllPassFilter`)
 * with LFO modulation, center frequency sweep, and bipolar feedback.
 *
 * Copyright: kdr 2026.
 * License: Boost License 1.0.
 */
module kdr.stutter.fx.phaser;

import std.math : isNaN, isInfinity, tan, PI;
import core.math : sin, fabs;
import kdr.filter : AllPassFilter;
import kdr.stutter.params : PhaserStages;

struct PhaserFX {
  enum int MAX_POLES = 12;

  AllPassFilter[MAX_POLES] stagesL;
  AllPassFilter[MAX_POLES] stagesR;
  double sampleRate = 44_100.0;
  double lfoPhase = 0.0;
  float fbLastL = 0.0f;
  float fbLastR = 0.0f;

  @nogc nothrow pure @safe:

  void reset(double sr) {
    sampleRate = (sr > 1000.0 && !isNaN(sr) && !isInfinity(sr)) ? sr : 44_100.0;
    for (int i = 0; i < MAX_POLES; ++i) {
      stagesL[i].setSampleRate(cast(float) sampleRate);
      stagesR[i].setSampleRate(cast(float) sampleRate);
    }
    lfoPhase = 0.0;
    fbLastL = 0.0f;
    fbLastR = 0.0f;
  }

  void process(
      float inL, float inR,
      out float outL, out float outR,
      float rateHz,
      int stagesMode,
      float centerHz,
      float feedback,
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

    if (isNaN(rateHz) || isInfinity(rateHz)) rateHz = 0.35f;
    if (rateHz < 0.05f) rateHz = 0.05f;
    if (rateHz > 5.0f) rateHz = 5.0f;

    if (isNaN(centerHz) || isInfinity(centerHz)) centerHz = 1000.0f;
    if (centerHz < 80.0f) centerHz = 80.0f;
    const float maxCenter = cast(float)(sampleRate * 0.4);
    if (centerHz > maxCenter) centerHz = maxCenter;

    if (isNaN(feedback) || isInfinity(feedback)) feedback = 0.6f;
    if (feedback < -0.95f) feedback = -0.95f;
    if (feedback > 0.95f) feedback = 0.95f;

    if (isNaN(mix) || isInfinity(mix)) mix = 0.5f;
    if (mix < 0.0f) mix = 0.0f;
    if (mix > 1.0f) mix = 1.0f;

    int numPoles = 6;
    switch (stagesMode) {
      case PhaserStages.poles4:  numPoles = 4; break;
      case PhaserStages.poles6:  numPoles = 6; break;
      case PhaserStages.poles8:  numPoles = 8; break;
      case PhaserStages.poles12: numPoles = 12; break;
      default:                   numPoles = 6; break;
    }

    lfoPhase += (2.0 * PI * cast(double) rateHz) / sampleRate;
    if (lfoPhase >= 2.0 * PI) lfoPhase -= 2.0 * PI;

    const float modL = 1.0f + 0.35f * cast(float) sin(lfoPhase);
    const float modR = 1.0f + 0.35f * cast(float) sin(lfoPhase + PI * 0.5);

    float freqL = centerHz * modL;
    float freqR = centerHz * modR;
    if (freqL < 50.0f) freqL = 50.0f;
    if (freqL > maxCenter) freqL = maxCenter;
    if (freqR < 50.0f) freqR = 50.0f;
    if (freqR > maxCenter) freqR = maxCenter;

    const float tanL = cast(float) tan(PI * cast(double) freqL / sampleRate);
    const float tanR = cast(float) tan(PI * cast(double) freqR / sampleRate);
    float gL = (1.0f - tanL) / (1.0f + tanL);
    float gR = (1.0f - tanR) / (1.0f + tanR);
    if (gL < -0.98f) gL = -0.98f;
    if (gL > 0.98f) gL = 0.98f;
    if (gR < -0.98f) gR = -0.98f;
    if (gR > 0.98f) gR = 0.98f;

    float yL = inL + feedback * fbLastL;
    float yR = inR + feedback * fbLastR;
    if (yL > 4.0f) yL = 4.0f;
    if (yL < -4.0f) yL = -4.0f;
    if (yR > 4.0f) yR = 4.0f;
    if (yR < -4.0f) yR = -4.0f;

    for (int i = 0; i < numPoles; ++i) {
      stagesL[i].g = gL;
      stagesR[i].g = gR;
      yL = stagesL[i].apply(yL);
      yR = stagesR[i].apply(yR);
    }

    if (isNaN(yL) || isInfinity(yL)) yL = 0.0f;
    if (isNaN(yR) || isInfinity(yR)) yR = 0.0f;

    fbLastL = yL;
    fbLastR = yR;

    outL = inL * (1.0f - mix) + yL * mix;
    outR = inR * (1.0f - mix) + yR * mix;
  }
}

unittest {
  import core.math : sin;
  PhaserFX ph;
  ph.reset(44_100.0);

  float outL, outR;

  // 1. Bypass bit-identical check
  ph.process(0.5f, -0.5f, outL, outR, 0.5f, PhaserStages.poles8, 1000.0f, 0.6f, 0.5f, false);
  assert(outL == 0.5f && outR == -0.5f);

  // 2. Active multi-pole phaser shifts phase and creates notch filtering
  ph.reset(44_100.0);
  float diffSum = 0.0f;
  for (int i = 0; i < 1024; ++i) {
    const float sig = sin(cast(float) i * 0.15f) * 0.7f;
    ph.process(sig, sig, outL, outR, 0.8f, PhaserStages.poles8, 1200.0f, 0.7f, 0.6f, true);
    assert(!isNaN(outL) && !isInfinity(outL));
    assert(!isNaN(outR) && !isInfinity(outR));
    diffSum += fabs(outL - sig);
  }
  assert(diffSum > 10.0f);
}
