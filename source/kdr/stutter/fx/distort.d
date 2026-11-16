/**
 * Stutter Edit 2 FX Module: Distort (2-Band Linkwitz-Riley Distortion).
 *
 * Uses `kdr.hott.dsp.LinkwitzRiley4` 4th-order stereo crossover with independent
 * low-band and high-band nonlinear saturation and post-tilt tone shaping.
 *
 * Copyright: kdr 2026.
 * License: Boost License 1.0.
 */
module kdr.stutter.fx.distort;

import std.math : isNaN, isInfinity;
import core.math : fabs;
import kdr.hott.dsp : LinkwitzRiley4;

@nogc nothrow pure @safe
private float fastTanh(float x) {
  if (isNaN(x)) return 0.0f;
  if (x < -3.0f) return -1.0f;
  if (x > 3.0f) return 1.0f;
  const float x2 = x * x;
  return x * (27.0f + x2) / (27.0f + 9.0f * x2);
}

struct DistortFX {
  LinkwitzRiley4 crossover;
  double sampleRate = 44_100.0;
  float lastCrossoverHz = -1.0f;

  @nogc nothrow @safe:

  void reset(double sr) {
    sampleRate = (sr > 1000.0 && !isNaN(sr) && !isInfinity(sr)) ? sr : 44_100.0;
    crossover.reset();
    lastCrossoverHz = -1.0f;
  }

  void process(
      float inL, float inR,
      out float outL, out float outR,
      float crossoverHz,
      float driveLow,
      float driveHigh,
      float tone,
      float mix,
      bool enabled,
      float dcOffset = 0.0f,
      bool twoBand = true
  ) {
    if (isNaN(inL) || isInfinity(inL)) inL = 0.0f;
    if (isNaN(inR) || isInfinity(inR)) inR = 0.0f;

    if (!enabled) {
      outL = inL;
      outR = inR;
      return;
    }

    if (isNaN(crossoverHz) || isInfinity(crossoverHz)) crossoverHz = 800.0f;
    if (crossoverHz < 80.0f) crossoverHz = 80.0f;
    const float maxXover = cast(float)(sampleRate * 0.4);
    if (crossoverHz > maxXover) crossoverHz = maxXover;

    if (isNaN(driveLow) || isInfinity(driveLow)) driveLow = 0.2f;
    if (driveLow < 0.0f) driveLow = 0.0f;
    if (driveLow > 1.0f) driveLow = 1.0f;

    if (isNaN(driveHigh) || isInfinity(driveHigh)) driveHigh = 0.4f;
    if (driveHigh < 0.0f) driveHigh = 0.0f;
    if (driveHigh > 1.0f) driveHigh = 1.0f;

    if (isNaN(tone) || isInfinity(tone)) tone = 0.0f;
    if (tone < -1.0f) tone = -1.0f;
    if (tone > 1.0f) tone = 1.0f;

    if (isNaN(mix) || isInfinity(mix)) mix = 1.0f;
    if (mix < 0.0f) mix = 0.0f;
    if (mix > 1.0f) mix = 1.0f;

    if (isNaN(dcOffset) || isInfinity(dcOffset)) dcOffset = 0.0f;
    if (dcOffset < -1.0f) dcOffset = -1.0f;
    if (dcOffset > 1.0f) dcOffset = 1.0f;

    const float bias = dcOffset * 0.45f;
    const float biasComp = fastTanh(bias);

    float wetL, wetR;
    if (!twoBand) {
      // 1-Band Broadband Saturation (even harmonics from asymmetric bias)
      const float gain = 1.0f + 0.5f * (driveLow + driveHigh) * 14.0f;
      wetL = fastTanh(inL * gain + bias) - biasComp;
      wetR = fastTanh(inR * gain + bias) - biasComp;
      if (tone > 0.0f) {
        wetL *= (1.0f - 0.15f * tone) + 0.15f * tone * (1.0f + 0.25f * fabs(wetL));
        wetR *= (1.0f - 0.15f * tone) + 0.15f * tone * (1.0f + 0.25f * fabs(wetR));
      }
    } else {
      if (fabs(crossoverHz - lastCrossoverHz) > 0.5f) {
        crossover.setFrequency(crossoverHz, cast(float) sampleRate);
        lastCrossoverHz = crossoverHz;
      }

      float lpL, lpR, hpL, hpR;
      crossover.process(inL, inR, lpL, lpR, hpL, hpR);

      // Low band warm saturation with optional asymmetric bias
      const float gainLow = 1.0f + driveLow * 11.0f;
      const float satLowL = fastTanh(lpL * gainLow + bias * 0.5f) - fastTanh(bias * 0.5f);
      const float satLowR = fastTanh(lpR * gainLow + bias * 0.5f) - fastTanh(bias * 0.5f);

      // High band aggressive harmonic saturation with optional asymmetric bias
      const float gainHigh = 1.0f + driveHigh * 15.0f;
      const float satHighL = fastTanh(hpL * gainHigh + 0.1f * driveHigh * hpL * hpL + bias) - biasComp;
      const float satHighR = fastTanh(hpR * gainHigh - 0.1f * driveHigh * hpR * hpR + bias) - biasComp;

      // Tilt tone balance between low and high bands
      const float lowWeight  = (tone <= 0.0f) ? 1.0f : (1.0f - 0.5f * tone);
      const float highWeight = (tone >= 0.0f) ? 1.0f : (1.0f + 0.5f * tone);

      wetL = fastTanh(satLowL * lowWeight + satHighL * highWeight);
      wetR = fastTanh(satLowR * lowWeight + satHighR * highWeight);
    }

    outL = inL * (1.0f - mix) + wetL * mix;
    outR = inR * (1.0f - mix) + wetR * mix;
  }
}

unittest {
  import core.math : sin;
  DistortFX dist;
  dist.reset(44_100.0);

  float outL, outR;

  // 1. Bypass bit-identical check
  dist.process(0.5f, -0.5f, outL, outR, 800.0f, 0.8f, 0.9f, 0.0f, 1.0f, false);
  assert(outL == 0.5f && outR == -0.5f);

  // 2. Active 2-band saturation transforms audio and stays bounded
  dist.reset(44_100.0);
  float diffSum = 0.0f;
  for (int i = 0; i < 256; ++i) {
    const float sig = sin(cast(float) i * 0.15f) * 0.7f;
    dist.process(sig, sig, outL, outR, 800.0f, 0.7f, 0.9f, 0.2f, 1.0f, true);
    assert(!isNaN(outL) && !isInfinity(outL));
    assert(fabs(outL) <= 1.05f);
    diffSum += fabs(outL - sig);
  }
  assert(diffSum > 10.0f);
}
