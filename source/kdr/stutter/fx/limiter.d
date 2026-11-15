/**
 * Stutter Edit 2 Master Output Limiter (`MasterLimiter`).
 *
 * Implements a zero-overs brickwall safety limiter with threshold makeup,
 * smooth release recovery, strict ceiling clamping, and gain-reduction metering.
 *
 * Copyright: kdr 2026.
 * License: Boost License 1.0.
 */
module kdr.stutter.fx.limiter;

import std.math : isNaN, isInfinity, exp, log10;
import core.math : fabs;
import dplug.core.math : convertDecibelToLinearGain;

struct MasterLimiter {
  double sampleRate = 44_100.0;
  float envelope = 0.0f;
  float lastGrDb = 0.0f;
  float peakOutL = 0.0f;
  float peakOutR = 0.0f;

  @nogc nothrow pure @safe:

  void reset(double sr) {
    sampleRate = (sr > 1000.0 && !isNaN(sr) && !isInfinity(sr)) ? sr : 44_100.0;
    envelope = 0.0f;
    lastGrDb = 0.0f;
    peakOutL = 0.0f;
    peakOutR = 0.0f;
  }

  float gainReductionDb() const pure {
    return lastGrDb;
  }

  void process(
      float inL, float inR,
      out float outL, out float outR,
      float thresholdDb,
      float ceilingDb,
      float releaseMs,
      bool enabled
  ) {
    if (isNaN(inL) || isInfinity(inL)) inL = 0.0f;
    if (isNaN(inR) || isInfinity(inR)) inR = 0.0f;

    if (!enabled) {
      lastGrDb = 0.0f;
      outL = inL;
      outR = inR;
      peakOutL = fabs(outL) > peakOutL * 0.999f ? fabs(outL) : peakOutL * 0.999f;
      peakOutR = fabs(outR) > peakOutR * 0.999f ? fabs(outR) : peakOutR * 0.999f;
      return;
    }

    if (isNaN(thresholdDb) || isInfinity(thresholdDb)) thresholdDb = -0.5f;
    if (thresholdDb < -24.0f) thresholdDb = -24.0f;
    if (thresholdDb > 0.0f) thresholdDb = 0.0f;

    if (isNaN(ceilingDb) || isInfinity(ceilingDb)) ceilingDb = -0.1f;
    if (ceilingDb < -12.0f) ceilingDb = -12.0f;
    if (ceilingDb > 0.0f) ceilingDb = 0.0f;

    if (isNaN(releaseMs) || isInfinity(releaseMs)) releaseMs = 50.0f;
    if (releaseMs < 1.0f) releaseMs = 1.0f;
    if (releaseMs > 500.0f) releaseMs = 500.0f;

    const float ceilingLin = convertDecibelToLinearGain(ceilingDb);
    const float threshLin  = convertDecibelToLinearGain(thresholdDb);
    const float limitLevel = (threshLin < ceilingLin) ? threshLin : ceilingLin;

    const float absL = fabs(inL);
    const float absR = fabs(inR);
    const float peak = (absL > absR) ? absL : absR;

    const double releaseSamples = (cast(double) releaseMs * 0.001) * sampleRate;
    const float releaseAlpha = (releaseSamples > 1.0)
      ? cast(float) exp(-1.0 / releaseSamples)
      : 0.0f;

    if (peak > envelope) {
      envelope = peak; // Instantaneous brickwall attack
    } else {
      envelope = peak + releaseAlpha * (envelope - peak);
      if (envelope < 1e-6f) envelope = 0.0f;
    }

    float gain = 1.0f;
    if (envelope > limitLevel && envelope > 1e-6f) {
      gain = ceilingLin / envelope;
      if (gain > 1.0f) gain = 1.0f;
      lastGrDb = -20.0f * cast(float) log10(gain);
      if (lastGrDb < 0.0f) lastGrDb = 0.0f;
    } else {
      lastGrDb = 0.0f;
    }

    outL = inL * gain;
    outR = inR * gain;

    // Hard safety clamp guaranteeing zero overs above ceilingLin
    if (outL > ceilingLin) outL = ceilingLin;
    if (outL < -ceilingLin) outL = -ceilingLin;
    if (outR > ceilingLin) outR = ceilingLin;
    if (outR < -ceilingLin) outR = -ceilingLin;

    peakOutL = fabs(outL) > peakOutL * 0.999f ? fabs(outL) : peakOutL * 0.999f;
    peakOutR = fabs(outR) > peakOutR * 0.999f ? fabs(outR) : peakOutR * 0.999f;
  }
}

unittest {
  MasterLimiter lim;
  lim.reset(44_100.0);

  float outL, outR;

  // 1. Bypass bit-identical check
  lim.process(1.5f, -1.5f, outL, outR, -0.5f, -0.1f, 50.0f, false);
  assert(outL == 1.5f && outR == -1.5f);
  assert(lim.gainReductionDb() == 0.0f);

  // 2. Brickwall ceiling clamp on +12 dBFS signal
  lim.reset(44_100.0);
  const float ceilingLin = convertDecibelToLinearGain(-0.5f);
  lim.process(4.0f, -4.0f, outL, outR, -1.0f, -0.5f, 50.0f, true);
  assert(!isNaN(outL) && !isInfinity(outL));
  assert(fabs(outL) <= ceilingLin + 1e-5f);
  assert(fabs(outR) <= ceilingLin + 1e-5f);
  assert(lim.gainReductionDb() > 6.0f);
}
