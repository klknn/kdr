/**
 * Stutter Edit 2 FX Module: Gate (Rhythmic Chopper).
 *
 * Implements tempo-synced rhythmic chopping with modulated duty-cycle width
 * and cosine de-clicked release tail.
 *
 * Copyright: kdr 2026.
 * License: Boost License 1.0.
 */
module kdr.stutter.fx.gate;

import std.math : isNaN, isInfinity, PI;
import core.math : cos, fabs;
import kdr.stutter.params : GateSubdivision, gateSubdivisionBeats;

struct GateFX {
  double sampleRate = 44_100.0;
  double tempo = 120.0;
  double beatAccumulator = 0.0;
  float currentGain = 1.0f;

  @nogc nothrow pure @safe:

  void reset(double sr) {
    sampleRate = (sr > 1000.0 && !isNaN(sr) && !isInfinity(sr)) ? sr : 44_100.0;
    tempo = 120.0;
    beatAccumulator = 0.0;
    currentGain = 1.0f;
  }

  void setTempo(double bpm) {
    if (bpm > 10.0 && bpm < 1000.0 && !isNaN(bpm) && !isInfinity(bpm)) {
      tempo = bpm;
    } else {
      tempo = 120.0;
    }
  }

  void process(
      float inL, float inR,
      out float outL, out float outR,
      int subdivIdx,
      float width,
      float tailMs,
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

    if (isNaN(width) || isInfinity(width)) width = 0.5f;
    if (width < 0.05f) width = 0.05f;
    if (width > 0.95f) width = 0.95f;

    if (isNaN(tailMs) || isInfinity(tailMs)) tailMs = 5.0f;
    if (tailMs < 0.1f) tailMs = 0.1f;
    if (tailMs > 50.0f) tailMs = 50.0f;

    if (isNaN(mix) || isInfinity(mix)) mix = 1.0f;
    if (mix < 0.0f) mix = 0.0f;
    if (mix > 1.0f) mix = 1.0f;

    int idx = subdivIdx;
    if (idx < 0) idx = 0;
    if (idx >= cast(int) gateSubdivisionBeats.length) {
      idx = cast(int) gateSubdivisionBeats.length - 1;
    }
    const double periodBeats = gateSubdivisionBeats[idx];
    const double beatPerSample = tempo / (60.0 * sampleRate);

    beatAccumulator += beatPerSample;
    if (beatAccumulator >= periodBeats) {
      beatAccumulator -= periodBeats * cast(double)(cast(long)(beatAccumulator / periodBeats));
    }

    const float subPhase = cast(float)(beatAccumulator / periodBeats);
    const double periodMs = (periodBeats * 60.0 / tempo) * 1000.0;
    float tailFraction = (periodMs > 0.1) ? cast(float)(tailMs / periodMs) : 0.05f;
    if (tailFraction < 0.005f) tailFraction = 0.005f;
    if (tailFraction > 1.0f - width) tailFraction = 1.0f - width;

    enum float attackFraction = 0.01f;
    float env = 0.0f;
    if (subPhase < width) {
      if (subPhase < attackFraction && width > attackFraction * 2.0f) {
        const float t = subPhase / attackFraction;
        env = 0.5f * (1.0f - cos(t * cast(float) PI));
      } else {
        env = 1.0f;
      }
    } else if (subPhase < width + tailFraction && tailFraction > 1e-5f) {
      const float t = (subPhase - width) / tailFraction;
      env = 0.5f * (1.0f + cos(t * cast(float) PI));
    } else {
      env = 0.0f;
    }

    // Smooth gain slewing for click-free transitions
    currentGain += 0.25f * (env - currentGain);

    const float wetL = inL * currentGain;
    const float wetR = inR * currentGain;

    outL = inL * (1.0f - mix) + wetL * mix;
    outR = inR * (1.0f - mix) + wetR * mix;
  }
}

unittest {
  GateFX gate;
  gate.reset(44_100.0);
  gate.setTempo(120.0);

  // 1. Bypass bit-identical check
  float outL, outR;
  gate.process(0.75f, -0.5f, outL, outR, GateSubdivision.gate1_16, 0.5f, 5.0f, 1.0f, false);
  assert(outL == 0.75f && outR == -0.5f);

  // 2. Active chopping check across 1/16 note period (5512 samples at 120 BPM, 44.1kHz)
  gate.reset(44_100.0);
  float diffSum = 0.0f;
  float minEnvSeen = 1.0f;
  float maxEnvSeen = 0.0f;
  for (int i = 0; i < 6000; ++i) {
    gate.process(1.0f, 1.0f, outL, outR, GateSubdivision.gate1_16, 0.3f, 2.0f, 1.0f, true);
    assert(!isNaN(outL) && !isInfinity(outL));
    assert(outL >= 0.0f && outL <= 1.001f);
    diffSum += fabs(1.0f - outL);
    if (outL < minEnvSeen) minEnvSeen = outL;
    if (outL > maxEnvSeen) maxEnvSeen = outL;
  }
  assert(diffSum > 1000.0f);
  assert(minEnvSeen < 0.05f);
  assert(maxEnvSeen > 0.95f);
}
