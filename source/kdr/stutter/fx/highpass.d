/**
 * Stutter Edit 2 FX Module: Highpass (12/24 dB/oct Resonant Highpass Filter).
 *
 * Wraps shared `kdr.filter.Filter` (`FilterKind.HP12`) with optional cascaded
 * second stage for 24 dB/oct slope, pre-saturation/drive, and wet/dry mix.
 *
 * Copyright: kdr 2026.
 * License: Boost License 1.0.
 */
module kdr.stutter.fx.highpass;

import std.math : isNaN, isInfinity;
import core.math : fabs;
import kdr.filter : Filter, FilterKind;

@nogc nothrow pure @safe
private float fastTanh(float x) {
  if (isNaN(x)) return 0.0f;
  if (x < -3.0f) return -1.0f;
  if (x > 3.0f) return 1.0f;
  const float x2 = x * x;
  return x * (27.0f + x2) / (27.0f + 9.0f * x2);
}

struct HighpassFX {
  Filter stage1L;
  Filter stage1R;
  Filter stage2L;
  Filter stage2R;
  double sampleRate = 44_100.0;
  int lastPoles = -1;
  float lastNormFreq = -1.0f;
  float lastRes = -1.0f;

  @nogc nothrow pure @safe:

  void reset(double sr) {
    sampleRate = (sr > 1000.0 && !isNaN(sr) && !isInfinity(sr)) ? sr : 44_100.0;
    stage1L.setSampleRate(cast(float) sampleRate);
    stage1R.setSampleRate(cast(float) sampleRate);
    stage2L.setSampleRate(cast(float) sampleRate);
    stage2R.setSampleRate(cast(float) sampleRate);
    lastPoles = -1;
    lastNormFreq = -1.0f;
    lastRes = -1.0f;
  }

  /// Process one stereo frame.
  /// `poles`: 0 = 12 dB/oct, 1 = 24 dB/oct (cascaded).
  void process(
      float inL, float inR,
      out float outL, out float outR,
      float cutoffHz,
      float resonance,
      float mix,
      bool enabled,
      int poles = 0
  ) {
    if (isNaN(inL) || isInfinity(inL)) inL = 0.0f;
    if (isNaN(inR) || isInfinity(inR)) inR = 0.0f;

    if (!enabled) {
      outL = inL;
      outR = inR;
      return;
    }

    if (isNaN(cutoffHz) || isInfinity(cutoffHz)) cutoffHz = 250.0f;
    if (cutoffHz < 20.0f) cutoffHz = 20.0f;
    const float maxCutoff = cast(float)(sampleRate * 0.45);
    if (cutoffHz > maxCutoff) cutoffHz = maxCutoff;

    if (isNaN(resonance) || isInfinity(resonance)) resonance = 0.25f;
    if (resonance < 0.0f) resonance = 0.0f;
    if (resonance > 0.92f) resonance = 0.92f;

    if (isNaN(mix) || isInfinity(mix)) mix = 1.0f;
    if (mix < 0.0f) mix = 0.0f;
    if (mix > 1.0f) mix = 1.0f;

    const int clampedPoles = (poles != 0) ? 1 : 0;

    float normFreq = cutoffHz / cast(float) sampleRate;
    if (normFreq < 0.0005f) normFreq = 0.0005f;
    if (normFreq > 0.45f) normFreq = 0.45f;

    if (clampedPoles != lastPoles ||
        fabs(normFreq - lastNormFreq) > 1e-5f ||
        fabs(resonance - lastRes) > 1e-4f) {
      const float stageRes = (clampedPoles == 1) ? resonance * 0.65f : resonance;
      stage1L.setParams(FilterKind.HP12, normFreq, stageRes);
      stage1R.setParams(FilterKind.HP12, normFreq, stageRes);
      if (clampedPoles == 1) {
        stage2L.setParams(FilterKind.HP12, normFreq, stageRes * 0.7f);
        stage2R.setParams(FilterKind.HP12, normFreq, stageRes * 0.7f);
      }
      lastPoles = clampedPoles;
      lastNormFreq = normFreq;
      lastRes = resonance;
    }

    float wetL = stage1L.apply(inL);
    float wetR = stage1R.apply(inR);
    if (clampedPoles == 1) {
      wetL = stage2L.apply(wetL);
      wetR = stage2R.apply(wetR);
    }

    if (isNaN(wetL) || isInfinity(wetL)) {
      stage1L.setSampleRate(cast(float) sampleRate);
      stage2L.setSampleRate(cast(float) sampleRate);
      wetL = 0.0f;
    }
    if (isNaN(wetR) || isInfinity(wetR)) {
      stage1R.setSampleRate(cast(float) sampleRate);
      stage2R.setSampleRate(cast(float) sampleRate);
      wetR = 0.0f;
    }

    wetL = fastTanh(wetL);
    wetR = fastTanh(wetR);

    outL = inL * (1.0f - mix) + wetL * mix;
    outR = inR * (1.0f - mix) + wetR * mix;
  }
}

unittest {
  import core.math : sin;
  HighpassFX hp;
  hp.reset(44_100.0);

  float outL, outR;

  // 1. Bypass is bit-identical
  hp.process(0.4f, -0.6f, outL, outR, 2000.0f, 0.3f, 1.0f, false, 0);
  assert(outL == 0.4f && outR == -0.6f);

  // 2. Active highpass attenuates low frequencies (100 Hz) when cutoff = 3000 Hz
  hp.reset(44_100.0);
  float lowEnergy12 = 0.0f;
  for (int i = 0; i < 1024; ++i) {
    const float sig = sin(cast(float) i * 0.0142f) * 0.7f; // ~100 Hz
    hp.process(sig, sig, outL, outR, 3000.0f, 0.2f, 1.0f, true, 0);
    assert(!isNaN(outL) && !isInfinity(outL));
    if (i > 256) lowEnergy12 += fabs(outL);
  }
  assert(lowEnergy12 < 35.0f);

  // 3. 24 dB/oct attenuates 100 Hz even more steeply than 12 dB/oct
  hp.reset(44_100.0);
  float lowEnergy24 = 0.0f;
  for (int i = 0; i < 1024; ++i) {
    const float sig = sin(cast(float) i * 0.0142f) * 0.7f;
    hp.process(sig, sig, outL, outR, 3000.0f, 0.2f, 1.0f, true, 1);
    assert(!isNaN(outL) && !isInfinity(outL));
    if (i > 256) lowEnergy24 += fabs(outL);
  }
  assert(lowEnergy24 < lowEnergy12);
}
