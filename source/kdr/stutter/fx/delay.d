/**
 * Stutter Edit 2 FX Module: Delay (End-of-Chain Stereo Tempo-Synced Delay).
 *
 * Implements stereo tempo-synced delay with independent L/R beat subdivisions,
 * cross-feedback ping-pong blend, and high-frequency feedback damping.
 *
 * Copyright: kdr 2026.
 * License: Boost License 1.0.
 */
module kdr.stutter.fx.delay;

import std.math : isNaN, isInfinity;
import core.math : fabs;
import kdr.stutter.params : DelaySubdivision, delaySubdivisionBeats;

struct DelayFX {
  enum size_t BUFFER_SIZE = 262_144; // 2^18 samples (~5.9s at 44.1kHz)
  enum size_t BUFFER_MASK = BUFFER_SIZE - 1;

  float[BUFFER_SIZE] bufL = 0.0f;
  float[BUFFER_SIZE] bufR = 0.0f;
  size_t writePos = 0;
  double sampleRate = 44_100.0;
  double tempo = 120.0;
  float dampLastL = 0.0f;
  float dampLastR = 0.0f;

  @nogc nothrow pure @safe:

  void reset(double sr) {
    sampleRate = (sr > 1000.0 && !isNaN(sr) && !isInfinity(sr)) ? sr : 44_100.0;
    tempo = 120.0;
    bufL[] = 0.0f;
    bufR[] = 0.0f;
    writePos = 0;
    dampLastL = 0.0f;
    dampLastR = 0.0f;
  }

  void setTempo(double bpm) {
    if (bpm > 10.0 && bpm < 1000.0 && !isNaN(bpm) && !isInfinity(bpm)) {
      tempo = bpm;
    } else {
      tempo = 120.0;
    }
  }

  private static float readLinear(const ref float[BUFFER_SIZE] buf, size_t wPos, float delaySamples) {
    if (delaySamples < 1.0f) delaySamples = 1.0f;
    if (delaySamples > cast(float)(BUFFER_SIZE - 4)) delaySamples = cast(float)(BUFFER_SIZE - 4);
    const float rPos = cast(float)(wPos + BUFFER_SIZE) - delaySamples;
    const size_t i0 = cast(size_t) rPos;
    const float frac = rPos - cast(float) i0;
    const float s0 = buf[i0 & BUFFER_MASK];
    const float s1 = buf[(i0 + 1) & BUFFER_MASK];
    return s0 + frac * (s1 - s0);
  }

  void process(
      float inL, float inR,
      out float outL, out float outR,
      int timeLIdx,
      int timeRIdx,
      float feedback,
      float cross,
      float damp,
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

    if (isNaN(feedback) || isInfinity(feedback)) feedback = 0.4f;
    if (feedback < 0.0f) feedback = 0.0f;
    if (feedback > 0.95f) feedback = 0.95f;

    if (isNaN(cross) || isInfinity(cross)) cross = 0.5f;
    if (cross < 0.0f) cross = 0.0f;
    if (cross > 1.0f) cross = 1.0f;

    if (isNaN(damp) || isInfinity(damp)) damp = 0.25f;
    if (damp < 0.0f) damp = 0.0f;
    if (damp > 0.95f) damp = 0.95f;

    if (isNaN(mix) || isInfinity(mix)) mix = 0.4f;
    if (mix < 0.0f) mix = 0.0f;
    if (mix > 1.0f) mix = 1.0f;

    int idxL = timeLIdx;
    if (idxL < 0) idxL = 0;
    if (idxL >= cast(int) delaySubdivisionBeats.length) idxL = cast(int) delaySubdivisionBeats.length - 1;

    int idxR = timeRIdx;
    if (idxR < 0) idxR = 0;
    if (idxR >= cast(int) delaySubdivisionBeats.length) idxR = cast(int) delaySubdivisionBeats.length - 1;

    const double secPerBeat = 60.0 / tempo;
    const float delaySamplesL = cast(float)(delaySubdivisionBeats[idxL] * secPerBeat * sampleRate);
    const float delaySamplesR = cast(float)(delaySubdivisionBeats[idxR] * secPerBeat * sampleRate);

    const float tapL = readLinear(bufL, writePos, delaySamplesL);
    const float tapR = readLinear(bufR, writePos, delaySamplesR);

    // One-pole high-frequency damping in feedback path
    dampLastL = tapL * (1.0f - damp) + dampLastL * damp;
    dampLastR = tapR * (1.0f - damp) + dampLastR * damp;

    // Cross-feedback / Ping-pong blend
    const float fbFeedL = dampLastL * (1.0f - cross) + dampLastR * cross;
    const float fbFeedR = dampLastR * (1.0f - cross) + dampLastL * cross;

    float nextL = inL + feedback * fbFeedL;
    float nextR = inR + feedback * fbFeedR;
    if (nextL > 4.0f) nextL = 4.0f;
    if (nextL < -4.0f) nextL = -4.0f;
    if (nextR > 4.0f) nextR = 4.0f;
    if (nextR < -4.0f) nextR = -4.0f;

    bufL[writePos & BUFFER_MASK] = nextL;
    bufR[writePos & BUFFER_MASK] = nextR;
    writePos++;

    outL = inL * (1.0f - mix) + tapL * mix;
    outR = inR * (1.0f - mix) + tapR * mix;
  }
}

unittest {
  DelayFX del;
  del.reset(44_100.0);
  del.setTempo(120.0);

  float outL, outR;

  // 1. Bypass bit-identical check
  del.process(0.5f, -0.5f, outL, outR, DelaySubdivision.del1_32, DelaySubdivision.del1_16, 0.5f, 0.5f, 0.2f, 0.5f, false);
  assert(outL == 0.5f && outR == -0.5f);

  // 2. Active delay echoes pulse at 1/32 note (0.125 beat = 2756 samples at 120 BPM, 44.1kHz)
  del.reset(44_100.0);
  del.setTempo(120.0);
  float echoEnergy = 0.0f;
  for (int i = 0; i < 3200; ++i) {
    const float sig = (i < 32) ? 1.0f : 0.0f;
    del.process(sig, sig, outL, outR, DelaySubdivision.del1_32, DelaySubdivision.del1_16, 0.6f, 0.5f, 0.2f, 0.5f, true);
    assert(!isNaN(outL) && !isInfinity(outL));
    if (i >= 2740 && i <= 2800) {
      echoEnergy += fabs(outL);
    }
  }
  assert(echoEnergy > 5.0f);
}
