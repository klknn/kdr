/**
 * Stutter Edit 2 FX Module: Pan (Constant-Power Pan & M/S Stereo Width).
 *
 * Implements constant-power stereo panning and Mid/Side stereo field width
 * modulation with dry/wet mix blending.
 *
 * Copyright: kdr 2026.
 * License: Boost License 1.0.
 */
module kdr.stutter.fx.pan;

import std.math : isNaN, isInfinity, PI;
import core.math : cos, sin, fabs, sqrt;

struct PanFX {
  double sampleRate = 44_100.0;

  @nogc nothrow pure @safe:

  void reset(double sr) {
    sampleRate = (sr > 1000.0 && !isNaN(sr) && !isInfinity(sr)) ? sr : 44_100.0;
  }

  void process(
      float inL, float inR,
      out float outL, out float outR,
      float center,
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

    if (isNaN(center) || isInfinity(center)) center = 0.0f;
    if (center < -1.0f) center = -1.0f;
    if (center > 1.0f) center = 1.0f;

    if (isNaN(width) || isInfinity(width)) width = 1.0f;
    if (width < 0.0f) width = 0.0f;
    if (width > 2.0f) width = 2.0f;

    if (isNaN(mix) || isInfinity(mix)) mix = 1.0f;
    if (mix < 0.0f) mix = 0.0f;
    if (mix > 1.0f) mix = 1.0f;

    // 1. Mid/Side Stereo Width Processing
    const float mid = 0.5f * (inL + inR);
    const float side = 0.5f * (inL - inR) * width;
    const float wL = mid + side;
    const float wR = mid - side;

    // 2. Constant-Power Stereo Balance / Panning
    // At center = 0.0: angle = PI/4 -> cos(PI/4)*sqrt(2) = 1.0, sin(PI/4)*sqrt(2) = 1.0
    const float norm = (center + 1.0f) * 0.5f;
    const float angle = norm * cast(float)(PI * 0.5);
    enum float sqrt2 = 1.41421356f;
    const float gainL = cos(angle) * sqrt2;
    const float gainR = sin(angle) * sqrt2;

    const float wetL = wL * gainL;
    const float wetR = wR * gainR;

    outL = inL * (1.0f - mix) + wetL * mix;
    outR = inR * (1.0f - mix) + wetR * mix;
  }
}

unittest {
  PanFX pan;
  pan.reset(44_100.0);

  float outL, outR;

  // 1. Bypass bit-identical check
  pan.process(0.6f, -0.4f, outL, outR, -1.0f, 0.0f, 1.0f, false);
  assert(outL == 0.6f && outR == -0.4f);

  // 2. Hard Left (-1.0) silences right channel
  pan.process(0.5f, 0.5f, outL, outR, -1.0f, 1.0f, 1.0f, true);
  assert(outL > 0.7f && fabs(outR) < 1e-5f);

  // 3. Hard Right (+1.0) silences left channel
  pan.process(0.5f, 0.5f, outL, outR, 1.0f, 1.0f, 1.0f, true);
  assert(outR > 0.7f && fabs(outL) < 1e-5f);

  // 4. Stereo Width = 0.0 collapses stereo difference to mono
  pan.process(1.0f, -1.0f, outL, outR, 0.0f, 0.0f, 1.0f, true);
  assert(fabs(outL) < 1e-5f && fabs(outR) < 1e-5f);
}
