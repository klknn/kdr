/**
 * Empirical Challenge Harness for Milestone 3: Parameter Modulation & Client Lifecycle.
 *
 * Challenger: M3_2
 * Scope:
 * - Suite 1: mapLinear empirical challenge (standard & inverted ranges, out-of-bounds curve inputs, extreme bounds).
 * - Suite 2: mapLogarithmic empirical challenge (positive, zero, and negative bound combinations, geometric mean scaling).
 * - Suite 3: evaluateModulatedParam bypass logic (mod disabled, gesture inactive, degenerate min==max, active linear/log).
 * - Suite 4: TVMModulationEngine coordination across all 14 module slots and onGestureTriggered click-free smoother resets.
 * - Suite 5: StutterClient real-time audio processing stress harness (multi-sample rates 44.1k/96k/192k, block sizes 1/16/64/512,
 *            rapid note switches, transport stops/starts, and 100% @nogc zero-allocation verification).
 *
 * Placed in tests/ directory to run automatically under `dub test`.
 *
 * Copyright: kdr 2026.
 * License: Boost License 1.0.
 */
module tests.stutter_m3_modulation_client_challenge;

import core.memory : GC;
import core.math : fabs, cos;
import std.math : isNaN, isInfinity, isFinite, abs, exp, log, sqrt, PI, pow;
import std.stdio : writeln, writefln;

import dplug.client : LegalIO, MidiMessage, Parameter, TimeInfo,
  makeMidiMessageNoteOn, makeMidiMessageNoteOff;

import kdr.stutter.params;
import kdr.stutter.tvm;
import kdr.stutter.buffer;
import kdr.stutter.stutter;
import kdr.stutter.gesture;
import kdr.stutter.client;

// =============================================================================
// Helper Wrappers for @nogc Real-Time Invocations
// =============================================================================

@nogc nothrow void callProcessAudioNoGC(
    StutterClient client,
    const(float*)[] inputs,
    float*[] outputs,
    int frames,
    TimeInfo info
) {
  client.processAudio(inputs, outputs, frames, info);
}

@nogc nothrow void callResetNoGC(
    StutterClient client,
    double sampleRate,
    int maxFrames,
    int inChans,
    int outChans
) {
  client.reset(sampleRate, maxFrames, inChans, outChans);
}

// =============================================================================
// Suite 1: mapLinear Empirical Challenges
// =============================================================================

void testMapLinearEmpirical() {
  writeln("[CHALLENGE M3_2] Suite 1: mapLinear Empirical Challenge...");

  // 1.1: Standard ranges (P_min < P_max)
  {
    // [0.0, 1.0]
    assert(mapLinear(0.0f, 1.0f, 0.0f) == 0.0f);
    assert(mapLinear(0.0f, 1.0f, 1.0f) == 1.0f);
    assert(fabs(mapLinear(0.0f, 1.0f, 0.5f) - 0.5f) < 1e-6f);
    assert(fabs(mapLinear(0.0f, 1.0f, 0.25f) - 0.25f) < 1e-6f);
    assert(fabs(mapLinear(0.0f, 1.0f, 0.75f) - 0.75f) < 1e-6f);

    // Bipolar [-50.0, +50.0]
    assert(mapLinear(-50.0f, 50.0f, 0.0f) == -50.0f);
    assert(mapLinear(-50.0f, 50.0f, 1.0f) == 50.0f);
    assert(fabs(mapLinear(-50.0f, 50.0f, 0.5f) - 0.0f) < 1e-6f);

    // Audio frequency range [20.0, 20000.0]
    assert(mapLinear(20.0f, 20000.0f, 0.0f) == 20.0f);
    assert(mapLinear(20.0f, 20000.0f, 1.0f) == 20000.0f);
    assert(fabs(mapLinear(20.0f, 20000.0f, 0.5f) - 10010.0f) < 1e-5f);

    // Negative range [-500.0, -100.0]
    assert(mapLinear(-500.0f, -100.0f, 0.0f) == -500.0f);
    assert(mapLinear(-500.0f, -100.0f, 1.0f) == -100.0f);
    assert(fabs(mapLinear(-500.0f, -100.0f, 0.5f) - (-300.0f)) < 1e-5f);

    // Monotonicity check across 200 fine steps
    float prev = -50.0f;
    for (int i = 0; i <= 200; ++i) {
      const float c = cast(float) i / 200.0f;
      const float val = mapLinear(-50.0f, 50.0f, c);
      assert(!isNaN(val) && isFinite(val));
      assert(val >= prev - 1e-6f, "mapLinear lost monotonicity on standard range!");
      prev = val;
    }
  }

  // 1.2: Inverted ranges (P_min > P_max)
  {
    // [1.0, 0.0]
    assert(mapLinear(1.0f, 0.0f, 0.0f) == 1.0f);
    assert(mapLinear(1.0f, 0.0f, 1.0f) == 0.0f);
    assert(fabs(mapLinear(1.0f, 0.0f, 0.5f) - 0.5f) < 1e-6f);

    // Inverted bipolar [+50.0, -50.0]
    assert(mapLinear(50.0f, -50.0f, 0.0f) == 50.0f);
    assert(mapLinear(50.0f, -50.0f, 1.0f) == -50.0f);
    assert(fabs(mapLinear(50.0f, -50.0f, 0.5f) - 0.0f) < 1e-6f);

    // Inverted audio frequency [20000.0, 20.0]
    assert(mapLinear(20000.0f, 20.0f, 0.0f) == 20000.0f);
    assert(mapLinear(20000.0f, 20.0f, 1.0f) == 20.0f);
    assert(fabs(mapLinear(20000.0f, 20.0f, 0.5f) - 10010.0f) < 1e-5f);

    // Inverted negative [-100.0, -500.0]
    assert(mapLinear(-100.0f, -500.0f, 0.0f) == -100.0f);
    assert(mapLinear(-100.0f, -500.0f, 1.0f) == -500.0f);
    assert(fabs(mapLinear(-100.0f, -500.0f, 0.5f) - (-300.0f)) < 1e-5f);

    // Inverted monotonic decreasing check across 200 fine steps
    float prevInv = 50.0f;
    for (int i = 0; i <= 200; ++i) {
      const float c = cast(float) i / 200.0f;
      const float val = mapLinear(50.0f, -50.0f, c);
      assert(!isNaN(val) && isFinite(val));
      assert(val <= prevInv + 1e-6f, "mapLinear lost decreasing monotonicity on inverted range!");
      prevInv = val;
    }
  }

  // 1.3: Degenerate ranges (P_min == P_max)
  {
    assert(mapLinear(440.0f, 440.0f, 0.0f) == 440.0f);
    assert(mapLinear(440.0f, 440.0f, 0.5f) == 440.0f);
    assert(mapLinear(440.0f, 440.0f, 1.0f) == 440.0f);
    assert(mapLinear(440.0f, 440.0f, -10.0f) == 440.0f);
    assert(mapLinear(440.0f, 440.0f, 10.0f) == 440.0f);
    assert(mapLinear(0.0f, 0.0f, 0.5f) == 0.0f);
    assert(mapLinear(-42.0f, -42.0f, 0.5f) == -42.0f);
  }

  // 1.4: Out-of-bounds curve inputs & strict clamping
  {
    // Standard range [20.0, 20000.0]
    assert(mapLinear(20.0f, 20000.0f, -0.001f) == 20.0f);
    assert(mapLinear(20.0f, 20000.0f, -100.0f) == 20.0f);
    assert(mapLinear(20.0f, 20000.0f, -1e6f) == 20.0f);
    assert(mapLinear(20.0f, 20000.0f, 1.001f) == 20000.0f);
    assert(mapLinear(20.0f, 20000.0f, 100.0f) == 20000.0f);
    assert(mapLinear(20.0f, 20000.0f, 1e6f) == 20000.0f);

    // Inverted range [20000.0, 20.0]
    // Underflow curveVal (< 0) clamps to y=0 -> outputs P_min = 20000.0
    assert(mapLinear(20000.0f, 20.0f, -0.001f) == 20000.0f);
    assert(mapLinear(20000.0f, 20.0f, -100.0f) == 20000.0f);
    // Overflow curveVal (> 1) clamps to y=1 -> outputs P_max = 20.0
    assert(mapLinear(20000.0f, 20.0f, 1.001f) == 20.0f);
    assert(mapLinear(20000.0f, 20.0f, 100.0f) == 20.0f);

    // Non-finite curve inputs: NaN and Infs must produce finite safe outputs
    const float valNan = mapLinear(20.0f, 20000.0f, float.nan);
    assert(!isNaN(valNan) && isFinite(valNan));
    assert(valNan == 20.0f);

    const float valInfPos = mapLinear(20.0f, 20000.0f, float.infinity);
    assert(!isNaN(valInfPos) && isFinite(valInfPos));
    assert(valInfPos == 20.0f);

    const float valInfNeg = mapLinear(20.0f, 20000.0f, -float.infinity);
    assert(!isNaN(valInfNeg) && isFinite(valInfNeg));
    assert(valInfNeg == 20.0f);
  }

  // 1.5: Extreme boundary values
  {
    // Extremely large numbers
    const float bigVal = mapLinear(-1e30f, 1e30f, 0.5f);
    assert(!isNaN(bigVal) && isFinite(bigVal));
    assert(fabs(bigVal) < 1e20f);

    // Subnormals
    const float subVal = mapLinear(1e-35f, 1e-30f, 0.5f);
    assert(!isNaN(subVal) && isFinite(subVal));

    // NaN in P_min or P_max handled safely
    const float nanMin = mapLinear(float.nan, 100.0f, 0.5f);
    assert(!isNaN(nanMin) && isFinite(nanMin));

    const float nanMax = mapLinear(100.0f, float.nan, 0.5f);
    assert(!isNaN(nanMax) && isFinite(nanMax));

    const float infMin = mapLinear(float.infinity, 100.0f, 0.5f);
    assert(!isNaN(infMin) && isFinite(infMin));
  }

  writeln("[CHALLENGE M3_2] Suite 1 Passed Successfully.");
}

// =============================================================================
// Suite 2: mapLogarithmic Empirical Challenges
// =============================================================================

void testMapLogarithmicEmpirical() {
  writeln("[CHALLENGE M3_2] Suite 2: mapLogarithmic Empirical Challenge...");

  // 2.1: Positive standard range (0 < P_min < P_max)
  {
    // Audio frequency range [20.0, 20000.0]
    const float valAt0 = mapLogarithmic(20.0f, 20000.0f, 0.0f);
    const float valAt1 = mapLogarithmic(20.0f, 20000.0f, 1.0f);
    writefln("[DEBUG] valAt0 = %.9f, valAt1 = %.9f", valAt0, valAt1);
    assert(fabs(valAt0 - 20.0f) < 0.01f);
    assert(fabs(valAt1 - 20000.0f) < 0.1f);

    // Midpoint of log range must equal the geometric mean: sqrt(20 * 20000) = 632.4555 Hz
    const float logMid = mapLogarithmic(20.0f, 20000.0f, 0.5f);
    const float expectedGeoMean = sqrt(20.0f * 20000.0f);
    assert(fabs(logMid - expectedGeoMean) < 0.05f,
      "mapLogarithmic midpoint failed geometric mean property!");

    // Check powers of 2: [1.0, 1024.0]
    // At c = 0.5: sqrt(1 * 1024) = 32.0
    const float pow2Mid = mapLogarithmic(1.0f, 1024.0f, 0.5f);
    assert(fabs(pow2Mid - 32.0f) < 1e-4f);
    // At c = 0.25: 1024^0.25 = 5.656854f
    const float pow2Quarter = mapLogarithmic(1.0f, 1024.0f, 0.25f);
    assert(fabs(pow2Quarter - 5.656854f) < 1e-4f);

    // Monotonic increasing check across 200 steps
    float prev = 20.0f;
    for (int i = 0; i <= 200; ++i) {
      const float c = cast(float) i / 200.0f;
      const float val = mapLogarithmic(20.0f, 20000.0f, c);
      assert(!isNaN(val) && isFinite(val));
      assert(val >= prev - 1e-5f, "mapLogarithmic lost monotonicity!");
      prev = val;
    }
  }

  // 2.2: Positive inverted range (P_min > P_max > 0)
  {
    // Inverted audio frequency [20000.0, 20.0]
    assert(fabs(mapLogarithmic(20000.0f, 20.0f, 0.0f) - 20000.0f) < 0.05f);
    assert(fabs(mapLogarithmic(20000.0f, 20.0f, 1.0f) - 20.0f) < 0.05f);

    // Midpoint must still equal geometric mean: sqrt(20000 * 20) = 632.4555 Hz
    const float invLogMid = mapLogarithmic(20000.0f, 20.0f, 0.5f);
    assert(fabs(invLogMid - 632.4555f) < 0.05f);

    // Check powers of 2 inverted: [1024.0, 1.0]
    const float invPow2Mid = mapLogarithmic(1024.0f, 1.0f, 0.5f);
    assert(fabs(invPow2Mid - 32.0f) < 1e-4f);

    // Monotonic decreasing check across 200 steps
    float prevInv = 20000.0f;
    for (int i = 0; i <= 200; ++i) {
      const float c = cast(float) i / 200.0f;
      const float val = mapLogarithmic(20000.0f, 20.0f, c);
      assert(!isNaN(val) && isFinite(val));
      assert(val <= prevInv + 1e-4f, "mapLogarithmic lost decreasing monotonicity on inverted range!");
      prevInv = val;
    }
  }

  // 2.3: Degenerate positive range (P_min == P_max > 0)
  {
    assert(fabs(mapLogarithmic(440.0f, 440.0f, 0.0f) - 440.0f) < 0.01f);
    assert(fabs(mapLogarithmic(440.0f, 440.0f, 0.5f) - 440.0f) < 0.01f);
    assert(fabs(mapLogarithmic(440.0f, 440.0f, 1.0f) - 440.0f) < 0.01f);
  }

  // 2.4: Zero and Negative bound combinations (Linear Fallback Verification)
  {
    // P_min = 0, P_max > 0 -> falls back to mapLinear
    assert(mapLogarithmic(0.0f, 100.0f, 0.0f) == 0.0f);
    assert(mapLogarithmic(0.0f, 100.0f, 1.0f) == 100.0f);
    assert(fabs(mapLogarithmic(0.0f, 100.0f, 0.5f) - 50.0f) < 1e-5f);

    // P_min > 0, P_max = 0 -> falls back to mapLinear
    assert(mapLogarithmic(100.0f, 0.0f, 0.0f) == 100.0f);
    assert(mapLogarithmic(100.0f, 0.0f, 1.0f) == 0.0f);
    assert(fabs(mapLogarithmic(100.0f, 0.0f, 0.5f) - 50.0f) < 1e-5f);

    // P_min = 0, P_max = 0 -> returns 0.0
    assert(mapLogarithmic(0.0f, 0.0f, 0.5f) == 0.0f);

    // P_min < 0, P_max > 0 -> falls back to mapLinear
    assert(mapLogarithmic(-50.0f, 50.0f, 0.0f) == -50.0f);
    assert(mapLogarithmic(-50.0f, 50.0f, 1.0f) == 50.0f);
    assert(fabs(mapLogarithmic(-50.0f, 50.0f, 0.5f) - 0.0f) < 1e-5f);

    // P_min > 0, P_max < 0 -> falls back to mapLinear
    assert(mapLogarithmic(50.0f, -50.0f, 0.0f) == 50.0f);
    assert(mapLogarithmic(50.0f, -50.0f, 1.0f) == -50.0f);
    assert(fabs(mapLogarithmic(50.0f, -50.0f, 0.5f) - 0.0f) < 1e-5f);

    // P_min < 0, P_max < 0 -> falls back to mapLinear
    assert(mapLogarithmic(-500.0f, -100.0f, 0.0f) == -500.0f);
    assert(mapLogarithmic(-500.0f, -100.0f, 1.0f) == -100.0f);
    assert(fabs(mapLogarithmic(-500.0f, -100.0f, 0.5f) - (-300.0f)) < 1e-5f);
  }

  // 2.5: Out-of-bounds curve inputs & non-finite inputs
  {
    // Underflow & overflow curve inputs
    assert(fabs(mapLogarithmic(20.0f, 20000.0f, -0.5f) - 20.0f) < 0.01f);
    assert(fabs(mapLogarithmic(20.0f, 20000.0f, -100.0f) - 20.0f) < 0.01f);
    assert(fabs(mapLogarithmic(20.0f, 20000.0f, 1.5f) - 20000.0f) < 0.05f);
    assert(fabs(mapLogarithmic(20.0f, 20000.0f, 100.0f) - 20000.0f) < 0.05f);

    // Inverted underflow & overflow
    assert(fabs(mapLogarithmic(20000.0f, 20.0f, -0.5f) - 20000.0f) < 0.05f);
    assert(fabs(mapLogarithmic(20000.0f, 20.0f, 1.5f) - 20.0f) < 0.01f);

    // Non-finite curve inputs: NaN and Infs produce safe finite outputs
    const float nanCurve = mapLogarithmic(20.0f, 20000.0f, float.nan);
    assert(!isNaN(nanCurve) && isFinite(nanCurve));
    assert(fabs(nanCurve - 20.0f) < 0.01f);

    const float infCurve = mapLogarithmic(20.0f, 20000.0f, float.infinity);
    assert(!isNaN(infCurve) && isFinite(infCurve));
    assert(fabs(infCurve - 20.0f) < 0.01f);
  }

  writeln("[CHALLENGE M3_2] Suite 2 Passed Successfully.");
}

// =============================================================================
// Suite 3: evaluateModulatedParam Bypass Logic
// =============================================================================

void testEvaluateModulatedParamBypass() {
  writeln("[CHALLENGE M3_2] Suite 3: evaluateModulatedParam Bypass Logic...");

  static immutable float[8] testBases = [0.0f, 0.5f, 1.0f, 100.0f, 440.0f, 8000.0f, -24.0f, 12.0f];
  static immutable float[5] testMins = [20.0f, 100.0f, 0.0f, -50.0f, 1000.0f];
  static immutable float[5] testMaxs = [20000.0f, 5000.0f, 1.0f, 50.0f, 200.0f];
  static immutable float[5] testCurves = [0.0f, 0.25f, 0.5f, 0.75f, 1.0f];

  // 3.1: Bypass condition 1: Modulation disabled (!modEnabled)
  // Must return exact bitwise baseKnobValue regardless of other parameters
  for (int b = 0; b < 8; ++b) {
    for (int m = 0; m < 5; ++m) {
      for (int c = 0; c < 5; ++c) {
        const float base = testBases[b];
        const float pMin = testMins[m];
        const float pMax = testMaxs[m];
        const float curve = testCurves[c];

        // Linear
        const float outLin = evaluateModulatedParam(false, true, base, pMin, pMax, curve, false);
        assert(outLin == base, "evaluateModulatedParam failed bypass when modEnabled=false (linear)!");

        // Logarithmic
        const float outLog = evaluateModulatedParam(false, true, base, pMin, pMax, curve, true);
        assert(outLog == base, "evaluateModulatedParam failed bypass when modEnabled=false (log)!");
      }
    }
  }

  // 3.2: Bypass condition 2: Gesture inactive (!gestureActive)
  // Must return exact bitwise baseKnobValue even if modEnabled is true
  for (int b = 0; b < 8; ++b) {
    for (int m = 0; m < 5; ++m) {
      for (int c = 0; c < 5; ++c) {
        const float base = testBases[b];
        const float pMin = testMins[m];
        const float pMax = testMaxs[m];
        const float curve = testCurves[c];

        const float outLin = evaluateModulatedParam(true, false, base, pMin, pMax, curve, false);
        assert(outLin == base, "evaluateModulatedParam failed bypass when gestureActive=false (linear)!");

        const float outLog = evaluateModulatedParam(true, false, base, pMin, pMax, curve, true);
        assert(outLog == base, "evaluateModulatedParam failed bypass when gestureActive=false (log)!");
      }
    }
  }

  // 3.3: Bypass condition 3: Both modEnabled=false AND gestureActive=false
  for (int b = 0; b < 8; ++b) {
    const float base = testBases[b];
    const float outVal = evaluateModulatedParam(false, false, base, 20.0f, 20000.0f, 0.7f, false);
    assert(outVal == base);
  }

  // 3.4: Bypass condition 4: Degenerate bounds (|pMax - pMin| <= 1e-6f)
  // Even with modEnabled=true and gestureActive=true, returns baseKnobValue!
  for (int b = 0; b < 8; ++b) {
    const float base = testBases[b];

    // Identical bounds
    const float out1 = evaluateModulatedParam(true, true, base, 440.0f, 440.0f, 0.75f, false);
    assert(out1 == base, "evaluateModulatedParam failed bypass when pMin == pMax!");

    // Within 1e-6 epsilon
    const float out2 = evaluateModulatedParam(true, true, base, 440.0f, 440.0000005f, 0.75f, false);
    assert(out2 == base, "evaluateModulatedParam failed bypass within 1e-6 epsilon!");

    const float outLog = evaluateModulatedParam(true, true, base, 440.0f, 440.0f, 0.75f, true);
    assert(outLog == base, "evaluateModulatedParam failed bypass on log when pMin == pMax!");
  }

  // 3.5: Active modulation (modEnabled=true, gestureActive=true, |pMax - pMin| > 1e-6f)
  {
    // Linear modulation
    const float lin0 = evaluateModulatedParam(true, true, 500.0f, 200.0f, 8000.0f, 0.0f, false);
    assert(lin0 == 200.0f);
    const float lin1 = evaluateModulatedParam(true, true, 500.0f, 200.0f, 8000.0f, 1.0f, false);
    assert(lin1 == 8000.0f);
    const float linMid = evaluateModulatedParam(true, true, 500.0f, 200.0f, 8000.0f, 0.5f, false);
    assert(fabs(linMid - 4100.0f) < 1e-4f);

    // Inverted linear modulation
    const float linInv0 = evaluateModulatedParam(true, true, 500.0f, 8000.0f, 200.0f, 0.0f, false);
    assert(linInv0 == 8000.0f);
    const float linInv1 = evaluateModulatedParam(true, true, 500.0f, 8000.0f, 200.0f, 1.0f, false);
    assert(linInv1 == 200.0f);

    // Logarithmic modulation
    const float log0 = evaluateModulatedParam(true, true, 500.0f, 20.0f, 20000.0f, 0.0f, true);
    assert(fabs(log0 - 20.0f) < 0.01f);
    const float log1 = evaluateModulatedParam(true, true, 500.0f, 20.0f, 20000.0f, 1.0f, true);
    assert(fabs(log1 - 20000.0f) < 0.05f);
    const float logMid = evaluateModulatedParam(true, true, 500.0f, 20.0f, 20000.0f, 0.5f, true);
    assert(fabs(logMid - 632.4555f) < 0.05f);
  }

  writeln("[CHALLENGE M3_2] Suite 3 Passed Successfully.");
}

// =============================================================================
// Suite 4: TVMModulationEngine Coordination & onGestureTriggered Resets
// =============================================================================

void testTVMModulationEngineCoordination() {
  writeln("[CHALLENGE M3_2] Suite 4: TVMModulationEngine Coordination & Resets...");

  TVMModulationEngine engine;

  // 4.1: Verify coordination across all 14 module slots
  assert(NumTVMModuleSlots == 14);

  static immutable TVMModuleSlot[14] allSlots = [
    TVMModuleSlot.stutter,
    TVMModuleSlot.buffer,
    TVMModuleSlot.gate,
    TVMModuleSlot.pan,
    TVMModuleSlot.tapeStop,
    TVMModuleSlot.filter,
    TVMModuleSlot.lofi,
    TVMModuleSlot.distort,
    TVMModuleSlot.comb,
    TVMModuleSlot.chorus,
    TVMModuleSlot.flanger,
    TVMModuleSlot.phaser,
    TVMModuleSlot.reverb,
    TVMModuleSlot.delay,
  ];

  // Initialize engine at 44.1 kHz
  engine.reset(44100.0);

  // Load distinct presets into each slot and verify independence (no cross-talk)
  for (int i = 0; i < 14; ++i) {
    const int presetToLoad = i % 12; // Presets 0 to 11
    engine.curves[i].loadPreset(presetToLoad);
    assert(engine.curves[i].presetId == presetToLoad);
  }

  // Verify accessors and pointer integrity
  for (int i = 0; i < 14; ++i) {
    const TVMModuleSlot slot = allSlots[i];
    assert(engine.getCurve(slot).presetId == (i % 12));
    assert(engine.getCurve(i).presetId == (i % 12));
    const TVMCurve* ptr = engine.getCurvePtr(slot);
    assert(ptr !is null);
    assert(ptr.presetId == (i % 12));
  }

  // Boundary checks on getCurve(int)
  assert(engine.getCurve(-5).presetId == engine.curves[0].presetId);
  assert(engine.getCurve(100).presetId == engine.curves[13].presetId);

  // 4.2: Verify all 17 parameter smoothers after reset
  assert(engine.smoothBufferPos.isSettled());
  assert(engine.smoothBufferPos.value() == 0.0f);

  assert(engine.smoothBufferPitch.isSettled());
  assert(engine.smoothBufferPitch.value() == 0.0f);

  assert(engine.smoothGateWidth.isSettled());
  assert(engine.smoothGateWidth.value() == 0.5f);

  assert(engine.smoothPanCenter.isSettled());
  assert(engine.smoothPanCenter.value() == 0.0f);

  assert(engine.smoothPanWidth.isSettled());
  assert(engine.smoothPanWidth.value() == 1.0f);

  assert(engine.smoothTapeSlowdown.isSettled());
  assert(engine.smoothTapeSlowdown.value() == 0.0f);

  assert(engine.smoothFilterCutoff.isSettled());
  assert(engine.smoothFilterCutoff.value() == 8000.0f);

  assert(engine.smoothLofiBits.isSettled());
  assert(engine.smoothLofiBits.value() == 16.0f);

  assert(engine.smoothLofiDownsample.isSettled());
  assert(engine.smoothLofiDownsample.value() == 1.0f);

  assert(engine.smoothDistortDriveLow.isSettled());
  assert(engine.smoothDistortDriveLow.value() == 0.0f);

  assert(engine.smoothDistortDriveHigh.isSettled());
  assert(engine.smoothDistortDriveHigh.value() == 0.0f);

  assert(engine.smoothCombFreq.isSettled());
  assert(engine.smoothCombFreq.value() == 200.0f);

  assert(engine.smoothChorusDepth.isSettled());
  assert(engine.smoothChorusDepth.value() == 0.5f);

  assert(engine.smoothFlangerDepth.isSettled());
  assert(engine.smoothFlangerDepth.value() == 1.0f);

  assert(engine.smoothPhaserCenter.isSettled());
  assert(engine.smoothPhaserCenter.value() == 1000.0f);

  assert(engine.smoothReverbSize.isSettled());
  assert(engine.smoothReverbSize.value() == 0.5f);

  assert(engine.smoothDelayFeedback.isSettled());
  assert(engine.smoothDelayFeedback.value() == 0.4f);

  // 4.3: Verify smoother beta across multiple sample rates
  static immutable double[5] testRates = [8000.0, 44100.0, 48000.0, 96000.0, 192000.0];
  for (int r = 0; r < 5; ++r) {
    const double sr = testRates[r];
    engine.reset(sr);
    const float beta = engine.smoothBufferPos.beta;
    // beta = 1 - exp(-1 / (0.003 * sr))
    // Must be in (0, 1) and monotonically decreasing with sample rate
    assert(beta > 0.0f && beta < 1.0f);
    const double tauSamples = 0.003 * sr;
    const float expectedBeta = cast(float)(1.0 - exp(-1.0 / tauSamples));
    assert(fabs(beta - expectedBeta) < 1e-5f);
  }

  // 4.4: onGestureTriggered click-free smoother reset test
  // Stress-test: simulate active modulation running, followed by gesture trigger
  engine.reset(44100.0);

  // Run smoothers towards new target values for 50 samples (mid-slew)
  engine.smoothBufferPos.setTarget(0.8f);
  engine.smoothBufferPitch.setTarget(12.0f);
  engine.smoothFilterCutoff.setTarget(2000.0f);

  for (int s = 0; s < 50; ++s) {
    engine.smoothBufferPos.nextSample();
    engine.smoothBufferPitch.nextSample();
    engine.smoothFilterCutoff.nextSample();
  }

  // Ensure they are mid-slew
  assert(!engine.smoothBufferPos.isSettled());
  assert(!engine.smoothBufferPitch.isSettled());
  assert(!engine.smoothFilterCutoff.isSettled());

  const float preTriggerPos = engine.smoothBufferPos.value();
  const float preTriggerPitch = engine.smoothBufferPitch.value();
  const float preTriggerCutoff = engine.smoothFilterCutoff.value();

  // Fire onGestureTriggered at phase 0.0f
  engine.onGestureTriggered(0.0f);

  // Verify smoothers snapped cleanly without NaN, Inf, or negative rates
  assert(!isNaN(engine.smoothBufferPos.value()) && isFinite(engine.smoothBufferPos.value()));
  assert(!isNaN(engine.smoothBufferPitch.value()) && isFinite(engine.smoothBufferPitch.value()));
  assert(!isNaN(engine.smoothFilterCutoff.value()) && isFinite(engine.smoothFilterCutoff.value()));
  assert(engine.smoothBufferPos.value() >= 0.0f && engine.smoothBufferPos.value() <= 1.0f);

  // Now process next sample with new target on the freshly triggered gesture
  const float newTargetPos = 0.2f;
  const float postTriggerPos = engine.smoothBufferPos.nextSample(newTargetPos);
  const float posStepDelta = fabs(postTriggerPos - engine.smoothBufferPos.current);
  assert(posStepDelta <= engine.smoothBufferPos.beta * fabs(newTargetPos - engine.smoothBufferPos.current) + 1e-6f);

  // Repeated trigger cycles test: fire onGestureTriggered 100 times in rapid succession
  for (int cycle = 0; cycle < 100; ++cycle) {
    const float trigPhase = (cycle % 10) * 0.1f;
    engine.onGestureTriggered(trigPhase);

    // Verify all smoothers remain finite and settled/snapped
    assert(isFinite(engine.smoothBufferPos.value()));
    assert(isFinite(engine.smoothBufferPitch.value()));
    assert(isFinite(engine.smoothGateWidth.value()));
    assert(isFinite(engine.smoothPanCenter.value()));
    assert(isFinite(engine.smoothFilterCutoff.value()));
    assert(isFinite(engine.smoothDelayFeedback.value()));

    // Run 5 samples
    for (int k = 0; k < 5; ++k) {
      engine.smoothBufferPos.nextSample(0.5f);
      engine.smoothBufferPitch.nextSample(0.0f);
    }
  }

  writeln("[CHALLENGE M3_2] Suite 4 Passed Successfully.");
}

// =============================================================================
// Suite 5: StutterClient Real-Time Audio Processing Stress Harness
// =============================================================================

void testStutterClientRealTimeAudioStress() {
  writeln("[CHALLENGE M3_2] Suite 5: StutterClient Real-Time Audio Processing Stress Harness...");

  auto client = new StutterClient();
  assert(client !is null);

  // ---------------------------------------------------------------------------
  // 5.1: Multi-sample rates (44.1 kHz, 96 kHz, 192 kHz)
  // ---------------------------------------------------------------------------
  static immutable double[3] sampleRates = [44100.0, 96000.0, 192000.0];

  foreach (sr; sampleRates) {
    callResetNoGC(client, sr, 32, 2, 2);
    assert(client.captureBuffer().sampleRate() == sr);

    // Enable stutter & buffer modulation
    client.param(Params.autoMode).setFromHost(1.0); // Auto mode
    client.param(Params.stutterEnable).setFromHost(1.0);
    client.param(Params.stutterCurve).setFromHost(4.0); // Exp Rise preset
    client.param(Params.stutterCurveTension).setFromHost(0.5f);
    client.param(Params.bufferEnable).setFromHost(1.0);
    client.param(Params.bufferPitchMin).setFromHost(-12.0f);
    client.param(Params.bufferPitchMax).setFromHost(+12.0f);
    client.param(Params.bufferCurve).setFromHost(6.0); // Sine 1x preset

    TimeInfo info;
    info.tempo = 130.0;
    info.hostIsPlaying = true;
    info.timeInSamples = 0;

    float[32] inL = 0.0f;
    float[32] inR = 0.0f;
    float[32] outL = 0.0f;
    float[32] outR = 0.0f;

    // Fill with synthetic audio (sine wave)
    for (int i = 0; i < 32; ++i) {
      inL[i] = cast(float) cos(cast(double) i * 0.1);
      inR[i] = cast(float) -cos(cast(double) i * 0.1);
    }

    const(float)*[2] inPtrs = [inL.ptr, inR.ptr];
    float*[2] outPtrs = [outL.ptr, outR.ptr];

    // Process 64 blocks (2048 frames) at this sample rate
    for (int b = 0; b < 64; ++b) {
      info.timeInSamples = b * 32;
      callProcessAudioNoGC(client, inPtrs[], outPtrs[], 32, info);

      // Verify numerical stability on every block
      for (int f = 0; f < 32; ++f) {
        assert(!isNaN(outL[f]) && isFinite(outL[f]), "NaN/Inf detected in outL!");
        assert(!isNaN(outR[f]) && isFinite(outR[f]), "NaN/Inf detected in outR!");
        assert(fabs(outL[f]) <= 5.0f, "Output level exploded!");
        assert(fabs(outR[f]) <= 5.0f, "Output level exploded!");
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 5.2: Varying block sizes (1, 16, 64, 512 frames)
  // ---------------------------------------------------------------------------
  static immutable int[4] blockSizes = [1, 16, 64, 512];

  foreach (bs; blockSizes) {
    callResetNoGC(client, 44100.0, 32, 2, 2);
    client.param(Params.autoMode).setFromHost(1.0);
    client.param(Params.stutterEnable).setFromHost(1.0);
    client.param(Params.stutterCurve).setFromHost(2.0); // Ramp Up
    client.param(Params.bufferEnable).setFromHost(1.0);
    client.param(Params.bufferPitchMin).setFromHost(0.0f);
    client.param(Params.bufferPitchMax).setFromHost(7.0f);

    TimeInfo info;
    info.tempo = 120.0;
    info.hostIsPlaying = true;
    info.timeInSamples = 0;

    // Allocate stack buffer up to 512 frames
    float[512] inBufL;
    float[512] inBufR;
    float[512] outBufL;
    float[512] outBufR;

    for (int i = 0; i < bs; ++i) {
      inBufL[i] = cast(float) cos(cast(double) i * 0.05);
      inBufR[i] = cast(float) cos(cast(double) i * 0.05);
    }

    const(float)*[2] inPtrs = [inBufL.ptr, inBufR.ptr];
    float*[2] outPtrs = [outBufL.ptr, outBufR.ptr];

    // Process at least 1024 total samples
    const int numBlocks = 1024 / bs;
    for (int b = 0; b < numBlocks; ++b) {
      info.timeInSamples = b * bs;
      callProcessAudioNoGC(client, inPtrs[], outPtrs[], bs, info);

      for (int f = 0; f < bs; ++f) {
        assert(!isNaN(outBufL[f]) && isFinite(outBufL[f]));
        assert(!isNaN(outBufR[f]) && isFinite(outBufR[f]));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 5.3: Rapid Note Switches under active TVM rate ramping & pitch modulation
  // ---------------------------------------------------------------------------
  {
    callResetNoGC(client, 44100.0, 32, 2, 2);
    client.param(Params.autoMode).setFromHost(0.0); // MIDI mode
    client.param(Params.releaseMode).setFromHost(0.0); // Instant release
    client.param(Params.quantizeGrid).setFromHost(0.0); // Instant quantize
    client.param(Params.stutterEnable).setFromHost(1.0);
    client.param(Params.stutterCurve).setFromHost(7.0); // Sine 2x
    client.param(Params.bufferEnable).setFromHost(1.0);
    client.param(Params.bufferPitchMin).setFromHost(-24.0f);
    client.param(Params.bufferPitchMax).setFromHost(+24.0f);

    TimeInfo info;
    info.tempo = 140.0;
    info.hostIsPlaying = true;
    info.timeInSamples = 0;

    float[32] inL = 0.5f;
    float[32] inR = -0.5f;
    float[32] outL = 0.0f;
    float[32] outR = 0.0f;
    const(float)*[2] inPtrs = [inL.ptr, inR.ptr];
    float*[2] outPtrs = [outL.ptr, outR.ptr];

    // Rapidly switch MIDI notes every 2 blocks (64 samples) across 8 different gestures
    static immutable ubyte[8] notes = [36, 38, 40, 41, 43, 45, 47, 48];
    ubyte currentNote = 36;

    for (int step = 0; step < 32; ++step) {
      if ((step & 1) == 0) {
        // Send Note-Off for current note, Note-On for next note
        client.enqueueMIDIFromHost(makeMidiMessageNoteOff(0, 0, currentNote));
        currentNote = notes[(step >> 1) % 8];
        client.enqueueMIDIFromHost(makeMidiMessageNoteOn(0, 0, currentNote, 110));
      }

      info.timeInSamples = step * 32;
      callProcessAudioNoGC(client, inPtrs[], outPtrs[], 32, info);

      assert(client.gestureController().getIsActive());
      assert(client.stutterEngine().isStuttering());

      for (int f = 0; f < 32; ++f) {
        assert(!isNaN(outL[f]) && isFinite(outL[f]));
        assert(!isNaN(outR[f]) && isFinite(outR[f]));
      }
    }

    // Release final note
    client.enqueueMIDIFromHost(makeMidiMessageNoteOff(0, 0, currentNote));
    for (int b = 0; b < 5; ++b) {
      callProcessAudioNoGC(client, inPtrs[], outPtrs[], 32, info);
    }
    assert(!client.gestureController().getIsActive());
    assert(!client.stutterEngine().isStuttering());
  }

  // ---------------------------------------------------------------------------
  // 5.4: Transport stops and starts
  // ---------------------------------------------------------------------------
  {
    callResetNoGC(client, 44100.0, 32, 2, 2);
    client.param(Params.autoMode).setFromHost(1.0); // Auto mode
    client.param(Params.stutterEnable).setFromHost(1.0);
    client.param(Params.stutterCurve).setFromHost(11.0); // Chaos curve
    client.param(Params.bufferEnable).setFromHost(1.0);

    TimeInfo info;
    info.tempo = 120.0;
    info.timeInSamples = 0;

    float[32] inL = 0.707f;
    float[32] inR = -0.707f;
    float[32] outL = 0.0f;
    float[32] outR = 0.0f;
    const(float)*[2] inPtrs = [inL.ptr, inR.ptr];
    float*[2] outPtrs = [outL.ptr, outR.ptr];

    // 5.4.1: MIDI Mode transport stops and starts
    client.param(Params.autoMode).setFromHost(0.0); // MIDI Mode
    client.param(Params.releaseMode).setFromHost(0.0); // Instant release
    client.param(Params.quantizeGrid).setFromHost(0.0); // Instant quantize

    for (int cycle = 0; cycle < 5; ++cycle) {
      // 1. Host is Playing with active Note-On -> Active Stuttering
      info.hostIsPlaying = true;
      client.enqueueMIDIFromHost(makeMidiMessageNoteOn(0, 0, 36, 100));
      for (int b = 0; b < 4; ++b) {
        info.timeInSamples += 32;
        callProcessAudioNoGC(client, inPtrs[], outPtrs[], 32, info);
      }
      assert(client.gestureController().getIsActive());

      // 2. Note-Off and Host Stopped -> Idle Passthrough
      client.enqueueMIDIFromHost(makeMidiMessageNoteOff(0, 0, 36));
      info.hostIsPlaying = false;
      for (int b = 0; b < 4; ++b) {
        info.timeInSamples += 32;
        callProcessAudioNoGC(client, inPtrs[], outPtrs[], 32, info);
      }
      assert(!client.gestureController().getIsActive());

      // Verify bit-accurate passthrough when idle
      for (int f = 0; f < 32; ++f) {
        assert(outL[f] == inL[f], "Idle passthrough corrupted on L channel after transport stop!");
        assert(outR[f] == inR[f], "Idle passthrough corrupted on R channel after transport stop!");
      }
    }

    // 5.4.2: Auto Mode transport & toggle
    client.param(Params.autoMode).setFromHost(1.0); // Re-enable Auto Mode
    info.hostIsPlaying = true;
    for (int b = 0; b < 4; ++b) {
      info.timeInSamples += 32;
      callProcessAudioNoGC(client, inPtrs[], outPtrs[], 32, info);
    }
    assert(client.gestureController().getIsActive());

    // Disabling Auto Mode transitions back to idle
    client.param(Params.autoMode).setFromHost(0.0);
    info.hostIsPlaying = false;
    for (int b = 0; b < 4; ++b) {
      info.timeInSamples += 32;
      callProcessAudioNoGC(client, inPtrs[], outPtrs[], 32, info);
    }
    assert(!client.gestureController().getIsActive());
  }

  // ---------------------------------------------------------------------------
  // 5.5: Zero-GC Real-Time Safety (100,000 samples)
  // ---------------------------------------------------------------------------
  {
    callResetNoGC(client, 44100.0, 32, 2, 2);
    client.param(Params.autoMode).setFromHost(1.0);
    client.param(Params.stutterEnable).setFromHost(1.0);
    client.param(Params.stutterCurve).setFromHost(2.0); // Ramp Up
    client.param(Params.bufferEnable).setFromHost(1.0);
    client.param(Params.bufferPitchMin).setFromHost(-7.0f);
    client.param(Params.bufferPitchMax).setFromHost(+7.0f);

    TimeInfo info;
    info.tempo = 128.0;
    info.hostIsPlaying = true;
    info.timeInSamples = 0;

    float[32] inL = 0.4f;
    float[32] inR = 0.4f;
    float[32] outL = 0.0f;
    float[32] outR = 0.0f;
    const(float)*[2] inPtrs = [inL.ptr, inR.ptr];
    float*[2] outPtrs = [outL.ptr, outR.ptr];

    // Warm up and stabilize GC
    GC.collect();
    const auto gcStatsBefore = GC.stats();

    // 3,125 blocks x 32 frames = 100,000 real-time audio samples
    for (int i = 0; i < 3125; ++i) {
      info.timeInSamples = i * 32;
      callProcessAudioNoGC(client, inPtrs[], outPtrs[], 32, info);
    }

    const auto gcStatsAfter = GC.stats();
    assert(gcStatsAfter.usedSize == gcStatsBefore.usedSize,
      "GC allocation detected during real-time StutterClient audio processing!");
  }

  writeln("[CHALLENGE M3_2] Suite 5 Passed Successfully.");
}

// =============================================================================
// Top-Level Unittest Runner
// =============================================================================

unittest {
  writeln("=== [Challenger M3_2] Starting Empirical Verification of Milestone 3 ===");
  testMapLinearEmpirical();
  testMapLogarithmicEmpirical();
  testEvaluateModulatedParamBypass();
  testTVMModulationEngineCoordination();
  testStutterClientRealTimeAudioStress();
  writeln("=== [Challenger M3_2] All Milestone 3 Empirical Challenges PASSED ===");
}
