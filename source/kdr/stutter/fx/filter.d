/**
 * Stutter Edit 2 FX Module: Filter (Sweeping Resonant LP12/LP24/HP12/BP12 + Drive).
 *
 * Wraps shared `kdr.filter.Filter` with pre-drive soft saturation and TVM
 * cutoff modulation.
 *
 * Copyright: kdr 2026.
 * License: Boost License 1.0.
 */
module kdr.stutter.fx.filter;

import std.math : isNaN, isInfinity;
import core.math : fabs;
import dplug.core.math : convertDecibelToLinearGain;
import kdr.filter : Filter, FilterKind;
import kdr.stutter.params : FilterType;

@nogc nothrow pure @safe
private float fastTanh(float x) {
  if (isNaN(x)) return 0.0f;
  if (x < -3.0f) return -1.0f;
  if (x > 3.0f) return 1.0f;
  const float x2 = x * x;
  return x * (27.0f + x2) / (27.0f + 9.0f * x2);
}

struct FilterFX {
  Filter filterL;
  Filter filterR;
  double sampleRate = 44_100.0;
  int lastType = -1;
  float lastNormFreq = -1.0f;
  float lastRes = -1.0f;

  @nogc nothrow pure @safe:

  void reset(double sr) {
    sampleRate = (sr > 1000.0 && !isNaN(sr) && !isInfinity(sr)) ? sr : 44_100.0;
    filterL.setSampleRate(cast(float) sampleRate);
    filterR.setSampleRate(cast(float) sampleRate);
    lastType = -1;
    lastNormFreq = -1.0f;
    lastRes = -1.0f;
  }

  void process(
      float inL, float inR,
      out float outL, out float outR,
      int filterType,
      float cutoffHz,
      float resonance,
      float driveDb,
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

    if (isNaN(cutoffHz) || isInfinity(cutoffHz)) cutoffHz = 1000.0f;
    if (cutoffHz < 20.0f) cutoffHz = 20.0f;
    const float maxCutoff = cast(float)(sampleRate * 0.45);
    if (cutoffHz > maxCutoff) cutoffHz = maxCutoff;

    if (isNaN(resonance) || isInfinity(resonance)) resonance = 0.3f;
    if (resonance < 0.0f) resonance = 0.0f;
    if (resonance > 0.95f) resonance = 0.95f;

    if (isNaN(driveDb) || isInfinity(driveDb)) driveDb = 0.0f;
    if (driveDb < 0.0f) driveDb = 0.0f;
    if (driveDb > 24.0f) driveDb = 24.0f;

    if (isNaN(mix) || isInfinity(mix)) mix = 1.0f;
    if (mix < 0.0f) mix = 0.0f;
    if (mix > 1.0f) mix = 1.0f;

    FilterKind kind = FilterKind.LP24;
    switch (filterType) {
      case FilterType.lowpass12:
        kind = FilterKind.LP12;
        break;
      case FilterType.lowpass24Ladder:
        kind = FilterKind.LP24;
        break;
      case FilterType.highpass12:
        kind = FilterKind.HP12;
        break;
      case FilterType.bandpass12:
        kind = FilterKind.BP12;
        break;
      default:
        kind = FilterKind.LP24;
        break;
    }

    // Normalized frequency in [0.001, 0.45] for kdr.filter.Filter
    float normFreq = cutoffHz / cast(float) sampleRate;
    if (normFreq < 0.0005f) normFreq = 0.0005f;
    if (normFreq > 0.45f) normFreq = 0.45f;

    if (filterType != lastType ||
        fabs(normFreq - lastNormFreq) > 1e-5f ||
        fabs(resonance - lastRes) > 1e-4f) {
      filterL.setParams(kind, normFreq, resonance);
      filterR.setParams(kind, normFreq, resonance);
      lastType = filterType;
      lastNormFreq = normFreq;
      lastRes = resonance;
    }

    // Apply pre-drive soft saturation if driveDb > 0
    float dL = inL;
    float dR = inR;
    if (driveDb > 0.05f) {
      const float gain = convertDecibelToLinearGain(driveDb);
      dL = fastTanh(inL * gain);
      dR = fastTanh(inR * gain);
    }

    float wetL = filterL.apply(dL);
    float wetR = filterR.apply(dR);

    if (isNaN(wetL) || isInfinity(wetL)) {
      filterL.setSampleRate(cast(float) sampleRate);
      wetL = 0.0f;
    }
    if (isNaN(wetR) || isInfinity(wetR)) {
      filterR.setSampleRate(cast(float) sampleRate);
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
  FilterFX filt;
  filt.reset(44_100.0);

  float outL, outR;

  // 1. Bypass bit-identical check
  filt.process(0.5f, -0.5f, outL, outR, FilterType.lowpass24Ladder, 500.0f, 0.5f, 6.0f, 1.0f, false);
  assert(outL == 0.5f && outR == -0.5f);

  // 2. Active filtering attenuates high frequencies in LP24 mode
  filt.reset(44_100.0);
  float highFreqEnergy = 0.0f;
  float diffSum = 0.0f;
  for (int i = 0; i < 512; ++i) {
    // 8 kHz sine wave at 44.1 kHz
    const float sig = sin(cast(float) i * 1.14f) * 0.8f;
    filt.process(sig, sig, outL, outR, FilterType.lowpass24Ladder, 300.0f, 0.4f, 3.0f, 1.0f, true);
    assert(!isNaN(outL) && !isInfinity(outL));
    if (i > 64) {
      highFreqEnergy += fabs(outL);
      diffSum += fabs(outL - sig);
    }
  }
  assert(diffSum > 50.0f);
  assert(highFreqEnergy < 50.0f);
}
