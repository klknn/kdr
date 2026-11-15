/**
 * Empirical Challenge Harness for Milestone 2: Core Stutter & Buffer Engine.
 *
 * Rigorously challenges:
 * 1. Hermite 3rd-order cubic interpolation accuracy against pure sinusoids across
 *    various frequencies and fractional steps, checking maximum error, SNR/SER,
 *    node exactness, polynomial reproduction (degree <= 2), and C1 slope continuity.
 * 2. Buffer wrap boundaries (0x7FFFF -> 0), verifying seamless circular playback
 *    without NaN/Inf, level spikes, or discontinuity across seams.
 * 3. Rate ramping, pendulum direction changes, and slice loop wraps, verifying
 *    equal-power energy conservation and bounded sample-to-sample delta |y[n] - y[n-1]|
 *    (preventing audio clicks and pops).
 * 4. Real-time @nogc nothrow safety under heavy audio load (150,000+ iterations),
 *    verifying zero GC allocations and robust performance.
 *
 * Copyright: kdr 2026.
 * License: Boost License 1.0.
 */
module tests.stutter_m2_challenge;

import std.stdio : writeln, writefln;
import std.math : isNaN, isInfinity, fabs, sin, cos, PI, floor, log2, sqrt, log10;
import core.memory : GC;

import dplug.client : MidiMessage, TimeInfo, makeMidiMessageNoteOn, makeMidiMessageNoteOff;
import kdr.stutter.params : Params, BufferDirection, StutterQuantizeMode, StutterSubdivision,
  stutterSubdivisionBeats;
import kdr.stutter.buffer : StereoCaptureBuffer, BufferPlayhead, hermiteInterpolate,
  CAPTURE_BUFFER_SIZE, CAPTURE_BUFFER_MASK;
import kdr.stutter.stutter : StutterEngine, CosineCrossfader, XfadeLength,
  cosXfadeTable, sinXfadeTable, evaluateRampedBeats;
import kdr.stutter.gesture : GestureController;
import kdr.stutter.client : StutterClient;

// =============================================================================
// Suite 1: Hermite Interpolation Precision, Frequency Response & C1 Continuity
// =============================================================================

void testHermiteInterpolationEmpirical() {
  writeln("[CHALLENGE M2] Running Suite 1: Hermite Interpolation Accuracy & C1 Continuity...");

  // 1. Exactness at integer nodes (frac = 0.0)
  for (int i = -100; i <= 100; ++i) {
    const float y0 = cast(float) i * 0.123f;
    const float ym1 = y0 - 0.5f;
    const float y1 = y0 + 0.7f;
    const float y2 = y1 + 0.3f;
    const float val = hermiteInterpolate(ym1, y0, y1, y2, 0.0f);
    assert(fabs(val - y0) < 1e-6f, "Hermite failed exactness at frac = 0.0");
  }

  // 2. Exact reproduction of quadratic and linear polynomials
  // Hermite interpolation with Catmull-Rom tangents reproduces all quadratic polynomials P(x) = a*x^2 + b*x + c
  {
    static immutable float[3][] quadCoeffs = [
      [1.0f, 0.0f, 0.0f],
      [0.5f, -1.2f, 3.4f],
      [-2.0f, 4.0f, -1.0f],
      [0.0f, 2.5f, -0.5f], // Linear
    ];

    foreach (coeffs; quadCoeffs) {
      const float a = coeffs[0];
      const float b = coeffs[1];
      const float c = coeffs[2];

      auto poly = (float x) => a * x * x + b * x + c;

      // Points at x = -1, 0, 1, 2
      const float ym1 = poly(-1.0f);
      const float y0  = poly(0.0f);
      const float y1  = poly(1.0f);
      const float y2  = poly(2.0f);

      // Evaluate at 100 fractional steps between 0 and 1
      for (int step = 0; step <= 100; ++step) {
        const float frac = cast(float) step / 100.0f;
        const float expected = poly(frac);
        const float actual = hermiteInterpolate(ym1, y0, y1, y2, frac);
        assert(fabs(actual - expected) < 1e-5f, "Hermite failed quadratic reproduction");
      }
    }
  }

  // 3. Accuracy against pure sinusoids across frequency spectrum at 48 kHz
  {
    const double sampleRate = 48000.0;
    static immutable double[] testFreqs = [
      50.0, 100.0, 220.0, 440.0, 1000.0, 2500.0, 5000.0, 10000.0, 15000.0, 20000.0
    ];

    static immutable float[] testFracs = [
      0.0f, 0.05f, 0.1f, 0.125f, 0.25f, 0.333333f, 0.5f, 0.666667f, 0.75f, 0.875f, 0.95f, 0.999f
    ];

    foreach (freq; testFreqs) {
      const double omega = 2.0 * PI * freq / sampleRate;

      double sumSqSignal = 0.0;
      double sumSqError = 0.0;
      double maxError = 0.0;

      // Test 500 consecutive sample windows
      for (int n = 10; n < 510; ++n) {
        const float ym1 = cast(float) sin(omega * (n - 1));
        const float y0  = cast(float) sin(omega * n);
        const float y1  = cast(float) sin(omega * (n + 1));
        const float y2  = cast(float) sin(omega * (n + 2));

        foreach (frac; testFracs) {
          const float exact = cast(float) sin(omega * (cast(double) n + cast(double) frac));
          const float approx = hermiteInterpolate(ym1, y0, y1, y2, frac);

          const double err = fabs(cast(double)(approx - exact));
          if (err > maxError) maxError = err;

          sumSqSignal += exact * exact;
          sumSqError += err * err;

          // Confirm output is strictly bounded within [-1.5, 1.5]
          assert(approx >= -1.5f && approx <= 1.5f, "Hermite output exceeded safe audio bounds");
          assert(!isNaN(approx) && !isInfinity(approx), "Hermite produced NaN or Inf");
        }
      }

      const double serDb = 10.0 * log10(sumSqSignal / (sumSqError + 1e-15));
      writefln("  [Hermite] Freq = %6.1f Hz | SER = %6.2f dB | MaxErr = %.6f", freq, serDb, maxError);

      // Assert accuracy constraints based on frequency
      if (freq <= 440.0) {
        // Low/mid frequency: extremely high fidelity (SER > 80 dB, max error < 0.0003)
        assert(serDb > 80.0, "Hermite SER too low for 440 Hz");
        assert(maxError < 3e-4, "Hermite max error too high for 440 Hz");
      } else if (freq <= 1000.0) {
        // 1 kHz: SER > 65 dB, max error < 0.002
        assert(serDb > 65.0, "Hermite SER too low for 1 kHz");
        assert(maxError < 2e-3, "Hermite max error too high for 1 kHz");
      } else if (freq <= 5000.0) {
        // 5 kHz: SER > 40 dB, max error < 0.04
        assert(serDb > 40.0, "Hermite SER too low for 5 kHz");
        assert(maxError < 0.04, "Hermite max error too high for 5 kHz");
      } else {
        // High frequency near Nyquist: stable and bounded without resonant explosion
        assert(serDb > 0.0, "Hermite high frequency degraded beyond stability");
        assert(maxError < 1.0, "Hermite high frequency error unbounded");
      }
    }
  }

  // 4. C1 First-Derivative Continuity Verification across adjacent sample boundaries
  // Tangent at frac = 1.0 of interval [n, n+1] must equal tangent at frac = 0.0 of interval [n+1, n+2]
  {
    // Tangent derivative formula: dH/d(frac) = 3*c3*frac^2 + 2*c2*frac + c1
    // At frac = 1.0: dH/d(frac) = 3*c3 + 2*c2 + c1 = 0.5 * (y2 - y0)
    // At frac = 0.0 of next cell: dH/d(frac) = c1' = 0.5 * (y1' - ym1') = 0.5 * (y2 - y0)
    for (int n = 0; n < 100; ++n) {
      const float y_m1 = cast(float) sin(0.07f * (n - 1));
      const float y_0  = cast(float) sin(0.07f * n);
      const float y_1  = cast(float) sin(0.07f * (n + 1));
      const float y_2  = cast(float) sin(0.07f * (n + 2));
      const float y_3  = cast(float) sin(0.07f * (n + 3));

      // Left cell derivatives approaching frac -> 1.0
      const float eps = 1e-4f;
      const float leftVal1 = hermiteInterpolate(y_m1, y_0, y_1, y_2, 1.0f - eps);
      const float leftVal2 = hermiteInterpolate(y_m1, y_0, y_1, y_2, 1.0f);
      const float leftSlope = (leftVal2 - leftVal1) / eps;

      // Right cell derivatives starting at frac = 0.0
      const float rightVal1 = hermiteInterpolate(y_0, y_1, y_2, y_3, 0.0f);
      const float rightVal2 = hermiteInterpolate(y_0, y_1, y_2, y_3, eps);
      const float rightSlope = (rightVal2 - rightVal1) / eps;

      // Continuity of value
      assert(fabs(leftVal2 - rightVal1) < 1e-6f, "Value discontinuous at sample boundary");
      // Continuity of slope (C1)
      assert(fabs(leftSlope - rightSlope) < 1e-3f, "Slope discontinuous across sample boundary");
    }
  }

  writeln("[CHALLENGE M2] Suite 1 Passed Successfully.");
}

// =============================================================================
// Suite 2: Buffer Wrap Boundaries (0x7FFFF -> 0), Continuity & Seam Stress
// =============================================================================

void testBufferWrapBoundariesEmpirical() {
  writeln("[CHALLENGE M2] Running Suite 2: Buffer Wrap Boundaries (0x7FFFF -> 0) Stress Tests...");

  StereoCaptureBuffer buf;
  buf.allocate(48000.0);
  assert(buf.isAllocated());

  // 1. Periodic Sinusoid across Seam
  // Exactly 1024 complete cycles in CAPTURE_BUFFER_SIZE (524,288 samples).
  // Period = 512 samples.
  // Sample 524,287 connects seamlessly to sample 0.
  const double cycleLength = 512.0;
  const double omega = 2.0 * PI / cycleLength;

  for (size_t i = 0; i < CAPTURE_BUFFER_SIZE; ++i) {
    const float s = cast(float) sin(omega * cast(double) i);
    buf.writeSample(s, -s);
  }

  // Verify writePos wrapped to 0
  assert(buf.writePos() == 0, "writePos did not wrap back to 0");

  // Read continuously across seam: 524,280.0 to 524,296.0 in 0.05 fractional increments
  // (320 test points spanning across boundary 524,287.95 -> 524,288.00 / 0.00)
  float prevOutL = 0.0f;
  bool isFirst = true;

  for (double pos = 524_280.0; pos <= 524_296.0; pos += 0.05) {
    float outL, outR;
    buf.readHermite(cast(float) pos, cast(float) pos, outL, outR);

    // Assert zero NaN/Inf
    assert(!isNaN(outL) && !isInfinity(outL), "NaN/Inf on boundary read (Left)");
    assert(!isNaN(outR) && !isInfinity(outR), "NaN/Inf on boundary read (Right)");
    assert(fabs(outL + outR) < 1e-5f, "Stereo symmetry violated across seam");

    // Theoretical expected value
    const double expectedPos = pos % cast(double) CAPTURE_BUFFER_SIZE;
    const float expected = cast(float) sin(omega * expectedPos);

    // Hermite accuracy across wrap boundary
    const float err = fabs(outL - expected);
    if (err >= 5e-4f) {
      writefln("  [Seam Error] pos=%f expectedPos=%f outL=%f expected=%f err=%f", pos, expectedPos, outL, expected, err);
    }
    assert(err < 5e-4f, "Seam error exceeds Hermite interpolation tolerance");

    // Assert bounded derivative: step is 0.05 samples, maximum expected delta is ~omega * 0.05 * 1.0 = 0.0006
    if (!isFirst) {
      const float delta = fabs(outL - prevOutL);
      assert(delta < 0.01f, "Discontinuity / level spike detected across buffer seam wrap!");
    }

    prevOutL = outL;
    isFirst = false;
  }

  // 2. Negative positions and circular reduction
  {
    static immutable double[] negPositions = [
      -0.0, -0.25, -0.5, -0.75, -1.0, -2.5, -100.33, -524_287.5, -524_288.0, -524_288.5, -1_048_576.0
    ];

    foreach (negPos; negPositions) {
      float outL, outR;
      buf.readHermite(cast(float) negPos, cast(float) negPos, outL, outR);
      assert(!isNaN(outL) && !isInfinity(outL), "NaN/Inf on negative position read");

      // Calculate equivalent wrapped positive position
      double equivPos = negPos % cast(double) CAPTURE_BUFFER_SIZE;
      if (equivPos < 0.0) equivPos += cast(double) CAPTURE_BUFFER_SIZE;

      float expL, expR;
      buf.readHermite(cast(float) equivPos, cast(float) equivPos, expL, expR);
      if (fabs(outL - expL) >= 1e-4f) {
        writefln("  [NegPos Mismatch] negPos=%f equivPos=%f outL=%f expL=%f diff=%f",
          negPos, equivPos, outL, expL, fabs(outL - expL));
      }
      assert(fabs(outL - expL) < 1e-4f, "Negative position circular wrap mismatch");
    }
  }

  // 3. Extreme Floats Immunity
  {
    static immutable float[] extremePositions = [
      1e6f, -1e6f, 1e9f, -1e9f, 1e15f, -1e15f, float.max * 0.5f, -float.max * 0.5f
    ];

    foreach (pos; extremePositions) {
      float outL, outR;
      buf.readHermite(pos, pos, outL, outR);
      assert(!isNaN(outL) && !isInfinity(outL), "NaN/Inf on extreme position read");
      assert(outL >= -1.5f && outL <= 1.5f, "Extreme position read exploded");
    }

    // Explicit NaN and Inf checks
    float outL, outR;
    buf.readHermite(float.nan, float.infinity, outL, outR);
    assert(outL == 0.0f && outR == 0.0f, "NaN/Inf positions must return safe silence");

    buf.readHermite(-float.infinity, float.nan, outL, outR);
    assert(outL == 0.0f && outR == 0.0f, "NaN/Inf positions must return safe silence");
  }

  // 4. Continuous Write Wrap Stress (2,000,000 samples = ~4 full buffer cycles)
  {
    for (size_t i = 0; i < 2_000_000; ++i) {
      const float valL = cast(float)(i & 0xFF) / 255.0f;
      const float valR = -valL;
      buf.writeSample(valL, valR);

      // Spot check write head
      assert(buf.writePos() == ((i + 1) & CAPTURE_BUFFER_MASK));
    }

    // Verify relative reads immediately behind write head across seam
    float rL, rR;
    buf.readRelativeHermite(0.0f, 0.0f, rL, rR);
    const float expectedLast = cast(float)((2_000_000 - 1) & 0xFF) / 255.0f;
    assert(fabs(rL - expectedLast) < 1e-5f, "readRelativeHermite failed after multiple wraps");

    buf.readRelativeHermite(1.0f, 1.0f, rL, rR);
    const float expectedPrev = cast(float)((2_000_000 - 2) & 0xFF) / 255.0f;
    assert(fabs(rL - expectedPrev) < 1e-5f, "readRelativeHermite prev failed after multiple wraps");
  }

  buf.free();
  writeln("[CHALLENGE M2] Suite 2 Passed Successfully.");
}

// =============================================================================
// Suite 3: Rate Ramping, Pendulum Direction Changes, and Slice Loop Wraps
// =============================================================================

void testStutterTransitionsAndContinuityEmpirical() {
  writeln("[CHALLENGE M2] Running Suite 3: Transitions, Crossfading & Energy Conservation...");

  // 1. Equal-Power Cosine / Sine Energy Conservation
  {
    for (int i = 0; i <= XfadeLength; ++i) {
      const float c = cosXfadeTable[i];
      const float s = sinXfadeTable[i];
      const float power = c * c + s * s;
      assert(fabs(power - 1.0f) < 1e-5f, "Crossfade table violates equal-power energy conservation");
    }

    // Midpoint attenuation (-3.01 dB)
    const float midCos = cosXfadeTable[XfadeLength / 2];
    const float midSin = sinXfadeTable[XfadeLength / 2];
    assert(fabs(midCos - midSin) < 1e-4f, "Crossfade midpoint asymmetry");
    assert(fabs(midCos - 0.70710678f) < 1e-4f, "Crossfade midpoint is not -3 dBFS");
  }

  // 2. Slice Loop Wrap Continuity Test on Continuous Audio
  // Feed a 150 Hz continuous sine wave into capture buffer and run stutter engine across 50 slice wraps
  {
    StereoCaptureBuffer buf;
    buf.allocate(44100.0);

    const double sampleRate = 44100.0;
    const double freq = 150.0;
    const double omega = 2.0 * PI * freq / sampleRate;

    // Fill buffer with 1 second of audio
    for (int i = 0; i < 44100; ++i) {
      const float s = cast(float) sin(omega * i);
      buf.writeSample(s, s);
    }

    StutterEngine stutter;
    stutter.reset(sampleRate);
    stutter.setTempo(120.0);
    stutter.trigger(buf.writePos(), 0.0f);

    float prevOutL = 0.0f;
    float maxDelta = 0.0f;

    // Run 80,000 samples (multiple slice repetitions of 1/16 note = 5512.5 samples)
    for (int n = 0; n < 80000; ++n) {
      const float inS = cast(float) sin(omega * (44100 + n));
      buf.writeSample(inS, inS);

      float outL, outR;
      stutter.process(
        &buf, inS, inS, outL, outR,
        0.5f, 4.0f, 4.0f, null, // 1/16 note fixed rate
        StutterQuantizeMode.freeSweep,
        BufferDirection.forward,
        1.0f, 0.0f
      );

      assert(!isNaN(outL) && !isInfinity(outL), "NaN/Inf during stutter loop");
      assert(!isNaN(outR) && !isInfinity(outR), "NaN/Inf during stutter loop");

      if (n > 64) { // Allow initial activation crossfade to settle
        const float delta = fabs(outL - prevOutL);
        if (delta > maxDelta) maxDelta = delta;

        // On a 150 Hz sine wave of amplitude 1.0, maximum normal delta is ~0.021.
        // A discontinuity/click would produce delta > 0.5.
        // The 64-sample cosine crossfader ensures transitions remain smooth and bounded (< 0.15).
        assert(delta < 0.15f, "Discontinuity / click detected during slice loop wrap!");
      }

      prevOutL = outL;
    }

    assert(stutter.sliceIteration >= 10, "Stutter did not complete enough slice iterations");
    buf.free();
  }

  // 3. Pendulum Direction Changes Continuity
  {
    StereoCaptureBuffer buf;
    buf.allocate(44100.0);

    const double sampleRate = 44100.0;
    const double freq = 200.0;
    const double omega = 2.0 * PI * freq / sampleRate;

    for (int i = 0; i < 44100; ++i) {
      const float s = cast(float) sin(omega * i);
      buf.writeSample(s, s);
    }

    StutterEngine stutter;
    stutter.reset(sampleRate);
    stutter.setTempo(120.0);
    stutter.trigger(buf.writePos(), 0.0f);

    float prevOutL = 0.0f;
    float maxDelta = 0.0f;

    // Run across 10+ pendulum direction flips (80,000 samples)
    for (int n = 0; n < 80000; ++n) {
      const float inS = cast(float) sin(omega * (44100 + n));
      buf.writeSample(inS, inS);

      float outL, outR;
      stutter.process(
        &buf, inS, inS, outL, outR,
        0.5f, 4.0f, 4.0f, null,
        StutterQuantizeMode.freeSweep,
        BufferDirection.pendulum,
        1.0f, 0.0f
      );

      assert(!isNaN(outL) && !isInfinity(outL));

      if (n > 64) {
        const float delta = fabs(outL - prevOutL);
        if (delta > maxDelta) maxDelta = delta;
        assert(delta < 0.15f, "Discontinuity detected during pendulum direction change!");
      }

      prevOutL = outL;
    }

    assert(stutter.sliceIteration >= 10, "Pendulum did not flip directions sufficient times");
    buf.free();
  }

  // 4. Rate Ramping & Quantization Stress
  {
    // Verify logarithmic rate progression
    // rateStart = 1/4 (index 2 = 1.0 beat), rateEnd = 1/64 (index 6 = 0.0625 beats)
    const double b0 = evaluateRampedBeats(2.0f, 6.0f, 0.0f, StutterQuantizeMode.freeSweep);
    const double bMid = evaluateRampedBeats(2.0f, 6.0f, 0.5f, StutterQuantizeMode.freeSweep);
    const double b1 = evaluateRampedBeats(2.0f, 6.0f, 1.0f, StutterQuantizeMode.freeSweep);

    assert(fabs(b0 - 1.0) < 1e-4);
    assert(fabs(b1 - 0.0625) < 1e-4);
    // Geometric mean of 1.0 and 0.0625 is sqrt(1.0 * 0.0625) = 0.25 (1/16 note)
    assert(fabs(bMid - 0.25) < 1e-4, "Rate ramping did not follow geometric progression");

    // Stepped Rhythmic quantization
    for (float p = 0.0f; p <= 1.0f; p += 0.01f) {
      const double bStepped = evaluateRampedBeats(2.0f, 6.0f, p, StutterQuantizeMode.steppedRhythmic);
      // Must be a valid straight subdivision beat
      bool valid = false;
      foreach (sb; [4.0, 2.0, 1.0, 0.5, 0.25, 0.125, 0.0625, 0.03125]) {
        if (fabs(bStepped - sb) < 1e-4) { valid = true; break; }
      }
      assert(valid, "Stepped quantization produced unaligned beat value");
    }

    // Triplets only quantization
    for (float p = 0.0f; p <= 1.0f; p += 0.01f) {
      const double bTrip = evaluateRampedBeats(2.0f, 6.0f, p, StutterQuantizeMode.tripletsOnly);
      bool valid = false;
      foreach (tb; [4.0/3.0, 2.0/3.0, 1.0/3.0, 0.5/3.0, 0.25/3.0, 0.125/3.0]) {
        if (fabs(bTrip - tb) < 1e-4) { valid = true; break; }
      }
      assert(valid, "Triplets quantization produced unaligned beat value");
    }
  }

  // 5. Activation & Release Crossfading
  {
    StereoCaptureBuffer buf;
    buf.allocate(44100.0);

    for (int i = 0; i < 44100; ++i) {
      buf.writeSample(0.5f, -0.5f);
    }

    StutterEngine stutter;
    stutter.reset(44100.0);

    // Initial idle state passes input through
    float oL, oR;
    stutter.process(&buf, 1.0f, 1.0f, oL, oR, 0.0f, 4.0f, 4.0f, null, 0, 0, 1.0f, 0.0f);
    assert(oL == 1.0f && oR == 1.0f);

    // Trigger stutter
    stutter.trigger(buf.writePos(), 0.0f);
    assert(stutter.isStuttering());

    // Step through activation crossfade (64 samples)
    for (int step = 0; step < XfadeLength; ++step) {
      stutter.process(&buf, 1.0f, 1.0f, oL, oR, 0.0f, 4.0f, 4.0f, null, 0, 0, 1.0f, 0.0f);
      assert(!isNaN(oL));
      // In equal-power crossfade, correlated signals have max amplitude <= sqrt(1^2 + 0.5^2) * sqrt(2) ~ 1.5
      assert(oL >= 0.4f && oL <= 1.5f, "Equal-power crossfade exceeded bounded audio range");
    }

    // Now fully wet
    stutter.process(&buf, 1.0f, 1.0f, oL, oR, 0.0f, 4.0f, 4.0f, null, 0, 0, 1.0f, 0.0f);
    assert(fabs(oL - 0.5f) < 1e-3f, "Failed to reach wet signal after crossfade");

    // Release stutter
    stutter.release();
    for (int step = 0; step < XfadeLength; ++step) {
      stutter.process(&buf, 1.0f, 1.0f, oL, oR, 0.0f, 4.0f, 4.0f, null, 0, 0, 1.0f, 0.0f);
      assert(!isNaN(oL));
      assert(oL >= 0.4f && oL <= 1.5f, "Release equal-power crossfade exceeded bounded audio range");
    }

    // Now fully dry
    stutter.process(&buf, 1.0f, 1.0f, oL, oR, 0.0f, 4.0f, 4.0f, null, 0, 0, 1.0f, 0.0f);
    assert(fabs(oL - 1.0f) < 1e-3f, "Failed to reach dry signal after release");
    assert(!stutter.isStuttering());

    buf.free();
  }

  writeln("[CHALLENGE M2] Suite 3 Passed Successfully.");
}

// =============================================================================
// Suite 4: Real-Time @nogc nothrow Safety Under Heavy Audio Load (150,000+ iters)
// =============================================================================

// Dedicated @nogc nothrow compile-time harness
@nogc nothrow void callNoGCStutterPipeline(
  StereoCaptureBuffer* buf,
  StutterEngine* stutter,
  GestureController* gesture,
  StutterClient client,
  const(float*)[] inAudio,
  float*[] outAudio,
  int frames)
{
  // 1. StereoCaptureBuffer primitives
  buf.writeSample(0.1f, -0.1f);
  float oL, oR;
  buf.readHermite(100.5f, 100.5f, oL, oR);
  buf.readRelativeHermite(10.0f, 10.0f, oL, oR);

  // 2. BufferPlayhead primitives
  float dirPhase = BufferPlayhead.calculateDirectionalPhase(0.5f, 1, BufferDirection.pendulum);
  float posL, posR;
  BufferPlayhead.calculateStereoReadPositions(
    1000, 0.5f, 256.0f, 0, BufferDirection.forward, 1.0f, 0.0f, posL, posR
  );

  // 3. StutterEngine primitives
  stutter.process(buf, 0.5f, 0.5f, oL, oR, 0.25f, 2.0f, 4.0f, null, 0, 0, 1.0f, 0.0f);

  // 4. StutterClient audio processing
  TimeInfo info;
  info.hostIsPlaying = true;
  info.tempo = 128.0;
  info.timeInSamples = 44100;
  client.processAudio(inAudio, outAudio, frames, info);
}

void testRealtimeNoGCSafetyUnderHeavyLoad() {
  writeln("[CHALLENGE M2] Running Suite 4: Real-time @nogc nothrow Safety (150,000 Iterations)...");

  auto client = new StutterClient();
  client.reset(44100.0, 32, 2, 2);

  StereoCaptureBuffer* buf = client.captureBuffer();
  StutterEngine* stutter = client.stutterEngine();
  GestureController* gesture = client.gestureController();

  assert(buf !is null);
  assert(stutter !is null);
  assert(gesture !is null);

  float[32] inL, inR, outL, outR;
  for (int i = 0; i < 32; ++i) {
    inL[i] = cast(float) sin(0.05f * i);
    inR[i] = -inL[i];
  }

  const(float*)[2] inputs = [inL.ptr, inR.ptr];
  float*[2] outputs = [outL.ptr, outR.ptr];

  // Warmup run
  callNoGCStutterPipeline(buf, stutter, gesture, client, inputs[], outputs[], 32);

  // Trigger GC collection before starting heavy iteration load
  GC.collect();
  const auto statsBefore = GC.stats();

  // Run 150,000 blocks under heavy dynamic parameter modulation and MIDI triggers
  // 150,000 * 32 samples = 4,800,000 frames (~108 seconds of full audio DSP)
  for (int iter = 0; iter < 150_000; ++iter) {
    // Send periodic MIDI note triggers to exercise gesture state transitions
    if (iter % 1000 == 0) {
      MidiMessage msg = makeMidiMessageNoteOn(0, 0, 60, 100);
      gesture.handleMidi(msg, cast(double) iter * 0.1);
    } else if (iter % 1000 == 500) {
      MidiMessage msg = makeMidiMessageNoteOff(0, 0, 60);
      gesture.handleMidi(msg, cast(double) iter * 0.1);
    }

    callNoGCStutterPipeline(buf, stutter, gesture, client, inputs[], outputs[], 32);
  }

  const auto statsAfter = GC.stats();

  // Strictly verify zero heap allocations during the 150,000 real-time iterations
  assert(statsAfter.usedSize == statsBefore.usedSize,
    "Heap memory was allocated inside real-time audio pipeline!");

  writeln("[CHALLENGE M2] Suite 4 Passed Successfully.");
}

// =============================================================================
// Master Entry Point for Milestone 2 Empirical Challenge
// =============================================================================

unittest {
  writeln("=== [Challenger M2_1] Starting Empirical Verification of Milestone 2 ===");
  testHermiteInterpolationEmpirical();
  testBufferWrapBoundariesEmpirical();
  testStutterTransitionsAndContinuityEmpirical();
  testRealtimeNoGCSafetyUnderHeavyLoad();
  writeln("=== [Challenger M2_1] All Milestone 2 Empirical Challenges PASSED ===");
}
