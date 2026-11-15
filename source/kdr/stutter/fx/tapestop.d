/**
 * Stutter Edit 2 FX Module: Tape Stop (Turntable / Tape Deceleration & Freeze).
 *
 * Implements motor-off tape slowdown and pitch-plunge effect using a circular
 * stereo capture buffer and 4-point 3rd-order Hermite cubic interpolation.
 *
 * Copyright: kdr 2026.
 * License: Boost License 1.0.
 */
module kdr.stutter.fx.tapestop;

import std.math : isNaN, isInfinity, floor;
import core.math : fabs;

struct TapeStopFX {
  enum size_t BUFFER_SIZE = 65_536;
  enum size_t BUFFER_MASK = BUFFER_SIZE - 1;

  float[BUFFER_SIZE] bufL = 0.0f;
  float[BUFFER_SIZE] bufR = 0.0f;
  size_t writePos = 0;
  double readLag = 0.0;
  double sampleRate = 44_100.0;
  bool wasBraking = false;

  @nogc nothrow pure @safe:

  void reset(double sr) {
    sampleRate = (sr > 1000.0 && !isNaN(sr) && !isInfinity(sr)) ? sr : 44_100.0;
    bufL[] = 0.0f;
    bufR[] = 0.0f;
    writePos = 0;
    readLag = 0.0;
    wasBraking = false;
  }

  private static float readHermiteChannel(const ref float[BUFFER_SIZE] buf, double absReadPos) {
    const long i0 = cast(long) floor(absReadPos);
    const float frac = cast(float)(absReadPos - cast(double) i0);

    const float ym1 = buf[cast(size_t)(i0 - 1) & BUFFER_MASK];
    const float y0  = buf[cast(size_t)(i0)     & BUFFER_MASK];
    const float y1  = buf[cast(size_t)(i0 + 1) & BUFFER_MASK];
    const float y2  = buf[cast(size_t)(i0 + 2) & BUFFER_MASK];

    const float c0 = y0;
    const float c1 = 0.5f * (y1 - ym1);
    const float c2 = ym1 - 2.5f * y0 + 2.0f * y1 - 0.5f * y2;
    const float c3 = 0.5f * (y2 - ym1) + 1.5f * (y0 - y1);
    return ((c3 * frac + c2) * frac + c1) * frac + c0;
  }

  void process(
      float inL, float inR,
      out float outL, out float outR,
      float slowdown,
      bool plunge,
      float mix,
      bool enabled
  ) {
    if (isNaN(inL) || isInfinity(inL)) inL = 0.0f;
    if (isNaN(inR) || isInfinity(inR)) inR = 0.0f;

    // Always write incoming audio into circular buffer
    bufL[writePos & BUFFER_MASK] = inL;
    bufR[writePos & BUFFER_MASK] = inR;
    const size_t curWrite = writePos;
    writePos++;

    if (!enabled) {
      readLag = 0.0;
      wasBraking = false;
      outL = inL;
      outR = inR;
      return;
    }

    if (isNaN(slowdown) || isInfinity(slowdown)) slowdown = 0.0f;
    if (slowdown < 0.0f) slowdown = 0.0f;
    if (slowdown > 1.0f) slowdown = 1.0f;

    if (isNaN(mix) || isInfinity(mix)) mix = 1.0f;
    if (mix < 0.0f) mix = 0.0f;
    if (mix > 1.0f) mix = 1.0f;

    // Effective tape playback rate: 1.0 = normal speed, 0.0 = stopped/frozen
    const float effSlow = plunge ? (slowdown * (2.0f - slowdown)) : slowdown;
    float tapeSpeed = 1.0f - effSlow;
    if (tapeSpeed < 0.0f) tapeSpeed = 0.0f;
    if (tapeSpeed > 1.0f) tapeSpeed = 1.0f;

    if (effSlow <= 0.001f) {
      // Smoothly recover lag back to live input
      readLag *= 0.99;
      if (readLag < 0.01) readLag = 0.0;
      wasBraking = false;
    } else {
      wasBraking = true;
      // Each sample, write head advances by 1.0 while read head advances by tapeSpeed,
      // so lag increases by (1.0 - tapeSpeed).
      readLag += cast(double)(1.0f - tapeSpeed);
      enum double maxLag = cast(double)(BUFFER_SIZE - 8);
      if (readLag > maxLag) readLag = maxLag;
    }

    // Read from circular buffer at (curWrite - readLag)
    const double absReadPos = cast(double)(curWrite + BUFFER_SIZE) - readLag;
    float wetL = readHermiteChannel(bufL, absReadPos);
    float wetR = readHermiteChannel(bufR, absReadPos);

    // Subtle motor-halt amplitude attenuation when speed approaches 0
    const float speedAmp = (tapeSpeed < 0.05f) ? (tapeSpeed / 0.05f) : 1.0f;
    if (plunge) {
      wetL *= speedAmp;
      wetR *= speedAmp;
    }

    outL = inL * (1.0f - mix) + wetL * mix;
    outR = inR * (1.0f - mix) + wetR * mix;
  }
}

unittest {
  import core.math : sin;
  TapeStopFX ts;
  ts.reset(44_100.0);

  float outL, outR;

  // 1. Bypass bit-identical check
  ts.process(0.4f, -0.4f, outL, outR, 0.8f, true, 1.0f, false);
  assert(outL == 0.4f && outR == -0.4f);

  // 2. Active slowdown diverges from live input as tape decelerates
  ts.reset(44_100.0);
  float diffSum = 0.0f;
  for (int i = 0; i < 1024; ++i) {
    const float sig = sin(cast(float) i * 0.1f);
    const float slow = cast(float) i / 1024.0f;
    ts.process(sig, sig, outL, outR, slow, false, 1.0f, true);
    assert(!isNaN(outL) && !isInfinity(outL));
    diffSum += fabs(outL - sig);
  }
  assert(diffSum > 10.0f);
  assert(ts.readLag > 100.0);
}
