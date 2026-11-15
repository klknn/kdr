/**
 * Stutter Edit 2 FX Module: Lo-Fi (Bitcrusher, Sample-Rate Downsampler & Grit).
 *
 * Implements variable sample-rate hold decimation, uniform bit-depth quantization,
 * and harmonic grit saturation.
 *
 * Copyright: kdr 2026.
 * License: Boost License 1.0.
 */
module kdr.stutter.fx.lofi;

import std.math : isNaN, isInfinity, floor, exp2;
import core.math : fabs;

@nogc nothrow pure @safe
private float fastTanh(float x) {
  if (isNaN(x)) return 0.0f;
  if (x < -3.0f) return -1.0f;
  if (x > 3.0f) return 1.0f;
  const float x2 = x * x;
  return x * (27.0f + x2) / (27.0f + 9.0f * x2);
}

struct LoFiFX {
  double sampleRate = 44_100.0;
  float phaseAcc = 0.0f;
  float heldL = 0.0f;
  float heldR = 0.0f;

  @nogc nothrow pure @safe:

  void reset(double sr) {
    sampleRate = (sr > 1000.0 && !isNaN(sr) && !isInfinity(sr)) ? sr : 44_100.0;
    phaseAcc = 0.0f;
    heldL = 0.0f;
    heldR = 0.0f;
  }

  void process(
      float inL, float inR,
      out float outL, out float outR,
      float bitDepth,
      float downsampleFactor,
      float grit,
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

    if (isNaN(bitDepth) || isInfinity(bitDepth)) bitDepth = 12.0f;
    if (bitDepth < 2.0f) bitDepth = 2.0f;
    if (bitDepth > 24.0f) bitDepth = 24.0f;

    if (isNaN(downsampleFactor) || isInfinity(downsampleFactor)) downsampleFactor = 1.0f;
    if (downsampleFactor < 1.0f) downsampleFactor = 1.0f;
    if (downsampleFactor > 64.0f) downsampleFactor = 64.0f;

    if (isNaN(grit) || isInfinity(grit)) grit = 0.0f;
    if (grit < 0.0f) grit = 0.0f;
    if (grit > 1.0f) grit = 1.0f;

    if (isNaN(mix) || isInfinity(mix)) mix = 1.0f;
    if (mix < 0.0f) mix = 0.0f;
    if (mix > 1.0f) mix = 1.0f;

    // 1. Zero-order hold sample-rate reduction
    phaseAcc += 1.0f;
    if (phaseAcc >= downsampleFactor) {
      phaseAcc -= downsampleFactor;
      if (phaseAcc >= downsampleFactor) phaseAcc = 0.0f;
      heldL = inL;
      heldR = inR;
    }

    // 2. Bit-depth quantization
    const float steps = exp2(bitDepth - 1.0f);
    const float invSteps = 1.0f / steps;
    float wetL = floor(heldL * steps + 0.5f) * invSteps;
    float wetR = floor(heldR * steps + 0.5f) * invSteps;

    // 3. Nonlinear Grit waveshaping
    if (grit > 0.001f) {
      const float drive = 1.0f + grit * 5.0f;
      wetL = fastTanh(wetL * drive + grit * 0.15f * wetL * wetL);
      wetR = fastTanh(wetR * drive - grit * 0.15f * wetR * wetR);
    }

    outL = inL * (1.0f - mix) + wetL * mix;
    outR = inR * (1.0f - mix) + wetR * mix;
  }
}

unittest {
  import core.math : sin;
  LoFiFX lofi;
  lofi.reset(44_100.0);

  float outL, outR;

  // 1. Bypass bit-identical check
  lofi.process(0.37f, -0.63f, outL, outR, 4.0f, 8.0f, 0.5f, 1.0f, false);
  assert(outL == 0.37f && outR == -0.63f);

  // 2. Active bitcrushing + downsampling transforms smooth sine wave
  lofi.reset(44_100.0);
  float diffSum = 0.0f;
  for (int i = 0; i < 256; ++i) {
    const float sig = sin(cast(float) i * 0.08f) * 0.85f;
    lofi.process(sig, sig, outL, outR, 4.0f, 6.0f, 0.4f, 1.0f, true);
    assert(!isNaN(outL) && !isInfinity(outL));
    diffSum += fabs(outL - sig);
  }
  assert(diffSum > 15.0f);
}
