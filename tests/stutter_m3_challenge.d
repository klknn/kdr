/**
 * Empirical Challenge Harness for Milestone 3: TVM Spline Curves & Tension DSP.
 *
 * Rigorously challenges:
 * 1. Stress test TVMCurve.evaluate(p) and evaluatePreset across extreme inputs:
 *    p in [-1000.0, 1000.0], NaN, +/-infinity, and positive/negative denormals.
 * 2. Monotonic behavior of tension parameter in [-1.0, 1.0] across all 5 curve types
 *    (linear, exponential, logarithmic, sCurve, stepHold).
 * 3. Coincident nodes (dx = 0, dx = 10^-7) and near-coincident geometries ensuring
 *    zero division-by-zero crashes, zero NaN/Inf outputs, and bounded values.
 * 4. All 12 preset shapes for strict range bounds [0.0, 1.0] and exact boundary endpoints.
 * 5. ParameterSmoother stability, pole location, step response, settling time, and
 *    denormal/stall immunity across various sample rates (8k, 44.1k, 48k, 96k, 192k, 384k).
 * 6. 100% @nogc nothrow pure @safe execution under heavy stress (150,000+ iterations)
 *    with verified zero GC heap allocations.
 *
 * Copyright: kdr 2026.
 * License: Boost License 1.0.
 */
module tests.stutter_m3_challenge;

import std.stdio : writeln, writefln;
import std.math : isNaN, isInfinity, fabs, sin, cos, PI, exp, log, pow;
import core.memory : GC;

import kdr.stutter.params : TVMCurvePreset;
import kdr.stutter.tvm : TVMCurve, CurveNode, CurveType, MaxCurveNodes,
  evaluatePreset, fclamp, mapLinear, mapLogarithmic, evaluateModulatedParam,
  TVMModulator, ParameterSmoother, TVMModuleSlot, NumTVMModuleSlots,
  TVMModulationEngine;

// =============================================================================
// Suite 1: TVMCurve.evaluate(p) Extreme Inputs ([-1000, 1000], NaN, +/-Inf, Denormals)
// =============================================================================

void testTVMCurveExtremeInputsEmpirical() {
  writeln("[CHALLENGE M3] Running Suite 1: Extreme Inputs Stress Tests ([-1000, 1000], NaN, +/-Inf, Denormals)...");

  TVMCurve curve;
  curve.reset(); // default: (0,0) -> (1,1) linear

  // 1. Extreme range p in [-1000.0, 1000.0]
  // Coarse sweep outside [0, 1]
  for (float p = -1000.0f; p <= -1.0f; p += 10.0f) {
    const float y = curve.evaluate(p);
    assert(!isNaN(y) && !isInfinity(y), "NaN/Inf on negative extreme p");
    assert(y == 0.0f, "Out-of-bounds negative p did not clamp to nodes[0].y");
  }

  for (float p = 2.0f; p <= 1000.0f; p += 10.0f) {
    const float y = curve.evaluate(p);
    assert(!isNaN(y) && !isInfinity(y), "NaN/Inf on positive extreme p");
    assert(y == 1.0f, "Out-of-bounds positive p did not clamp to nodes[last].y");
  }

  // Fine boundary sweep around 0.0 and 1.0
  static immutable float[] boundaryPoints = [
    -1000.0f, -500.0f, -100.0f, -10.0f, -1.0f, -0.5f, -0.1f, -0.01f, -0.0001f, -1e-6f, -1e-12f,
    0.0f, 1e-12f, 1e-6f, 0.0001f, 0.01f, 0.1f, 0.5f, 0.9f, 0.99f, 0.9999f, 1.0f - 1e-6f,
    1.0f, 1.0f + 1e-6f, 1.0001f, 1.01f, 1.1f, 1.5f, 2.0f, 10.0f, 100.0f, 500.0f, 1000.0f
  ];

  foreach (p; boundaryPoints) {
    const float y = curve.evaluate(p);
    assert(!isNaN(y) && !isInfinity(y), "NaN/Inf on boundary test point");
    if (p <= 0.0f) {
      assert(y == 0.0f, "p <= 0 did not yield nodes[0].y");
    } else if (p >= 1.0f) {
      assert(y == 1.0f, "p >= 1 did not yield nodes[last].y");
    } else {
      assert(y >= 0.0f && y <= 1.0f, "Interior evaluation out of bounds");
    }
  }

  // 2. Non-finite values: NaN and +/- Infinity
  {
    // Default curve
    assert(curve.evaluate(float.nan) == 0.0f, "NaN must return nodes[0].y");
    assert(curve.evaluate(-float.infinity) == 0.0f, "-Inf must return nodes[0].y");
    assert(curve.evaluate(float.infinity) == 1.0f, "+Inf must return nodes[last].y");

    // Inverted curve (1, 0)
    TVMCurve invCurve;
    invCurve.nodes[0] = CurveNode(0.0f, 1.0f, 0.0f, CurveType.linear);
    invCurve.nodes[1] = CurveNode(1.0f, 0.0f, 0.0f, CurveType.linear);
    assert(invCurve.evaluate(float.nan) == 1.0f, "Inverted curve NaN must return nodes[0].y");
    assert(invCurve.evaluate(-float.infinity) == 1.0f, "Inverted curve -Inf must return nodes[0].y");
    assert(invCurve.evaluate(float.infinity) == 0.0f, "Inverted curve +Inf must return nodes[last].y");
  }

  // 3. Denormals / Subnormals (IEEE-754 single precision float)
  {
    // float.min_normal is ~1.17549435e-38f.
    // Subnormals lie between 0 and float.min_normal.
    const float smallestSubnormal = float.min_normal * float.epsilon;
    const float midSubnormal = float.min_normal * 1e-3f;
    const float highSubnormal = float.min_normal * 0.5f;

    const float[8] denormals = [
      smallestSubnormal,
      -smallestSubnormal,
      midSubnormal,
      -midSubnormal,
      highSubnormal,
      -highSubnormal,
      float.min_normal * 0.1f,
      -float.min_normal * 0.1f
    ];

    foreach (denorm; denormals) {
      const float y = curve.evaluate(denorm);
      assert(!isNaN(y) && !isInfinity(y), "Denormal produced NaN/Inf in TVMCurve");
      if (denorm <= 0.0f) {
        assert(y == 0.0f);
      } else {
        assert(y >= 0.0f && y <= 1.0f);
      }
    }
  }

  // 4. Test all 12 analytical presets with extreme inputs
  for (int id = 0; id < 12; ++id) {
    // Extreme values
    assert(!isNaN(evaluatePreset(id, -1000.0f)));
    assert(!isNaN(evaluatePreset(id, 1000.0f)));
    assert(!isNaN(evaluatePreset(id, float.nan)));
    assert(!isNaN(evaluatePreset(id, -float.infinity)));
    assert(!isNaN(evaluatePreset(id, float.infinity)));
    assert(!isNaN(evaluatePreset(id, float.min_normal * float.epsilon)));
    assert(!isNaN(evaluatePreset(id, -float.min_normal * float.epsilon)));

    // Ensure all outputs strictly bounded in [0.0, 1.0]
    foreach (p; boundaryPoints) {
      const float y = evaluatePreset(id, p);
      assert(!isNaN(y) && !isInfinity(y));
      assert(y >= 0.0f && y <= 1.0f, "evaluatePreset produced out-of-range value");
    }
  }

  writeln("[CHALLENGE M3] Suite 1 Passed Successfully.");
}

// =============================================================================
// Suite 2: Monotonic Behavior of Tension Parameter across all 5 Curve Types
// =============================================================================

void testTensionMonotonicityEmpirical() {
  writeln("[CHALLENGE M3] Running Suite 2: Monotonic Behavior of Tension across 5 Curve Types...");

  static immutable CurveType[] allTypes = [
    CurveType.linear,
    CurveType.exponential,
    CurveType.logarithmic,
    CurveType.sCurve,
    CurveType.stepHold
  ];

  // Part A: For every tension T in [-1.0, 1.0], verify that the curve s(t, T)
  // is monotonically non-decreasing with respect to local phase t in [0.0, 1.0].
  foreach (type; allTypes) {
    TVMCurve curve;
    curve.reset();
    curve.nodes[0].type = type;

    // Test 41 tension values from -1.0 to +1.0 in 0.05 increments
    for (int tStep = -20; tStep <= 20; ++tStep) {
      const float tension = cast(float) tStep / 20.0f;
      curve.nodes[0].tension = tension;

      float prevY = 0.0f;
      // Sweep 500 points in [0.0, 1.0]
      for (int step = 0; step <= 500; ++step) {
        const float p = cast(float) step / 500.0f;
        const float y = curve.evaluate(p);

        assert(!isNaN(y) && !isInfinity(y), "NaN/Inf during tension monotonicity test");
        assert(y >= 0.0f && y <= 1.0f, "Output outside [0.0, 1.0]");

        // Verify monotonic non-decreasing in p (allowing 1e-6 float epsilon)
        assert(y >= prevY - 1e-6f,
          "Curve violated monotonic progression in phase t!");

        prevY = y;
      }

      // Verify exact boundary endpoints for all curve types
      assert(curve.evaluate(0.0f) == 0.0f, "s(0) must equal 0.0");
      assert(curve.evaluate(1.0f) == 1.0f, "s(1) must equal 1.0");
    }
  }

  // Part B: Monotonic behavior with respect to tension T itself.
  // For fixed interior phase t in (0, 1), varying tension T from -1.0 to +1.0
  // must produce monotonic curvature variation without erratic oscillations.
  {
    static immutable float[] testPhases = [0.1f, 0.25f, 0.5f, 0.75f, 0.9f];

    foreach (t; testPhases) {
      // 1. Linear: higher tension bends curve downwards (t^k where k = 1 + 4T),
      // so s(t, T) is monotonically non-increasing as T increases from -1 to +1.
      {
        TVMCurve cLinear;
        cLinear.reset();
        cLinear.nodes[0].type = CurveType.linear;

        float prevVal = 1e6f;
        for (int tStep = -20; tStep <= 20; ++tStep) {
          const float tension = cast(float) tStep / 20.0f;
          cLinear.nodes[0].tension = tension;
          const float val = cLinear.evaluate(t);

          assert(val <= prevVal + 1e-6f, "Linear tension parameter not monotonic in T");
          prevVal = val;
        }
      }

      // 2. Exponential: higher tension increases exponent k,
      // so s(t, T) = t^k is monotonically non-increasing as T increases from -1 to +1.
      {
        TVMCurve cExp;
        cExp.reset();
        cExp.nodes[0].type = CurveType.exponential;

        float prevVal = 1e6f;
        for (int tStep = -20; tStep <= 20; ++tStep) {
          const float tension = cast(float) tStep / 20.0f;
          cExp.nodes[0].tension = tension;
          const float val = cExp.evaluate(t);

          assert(val <= prevVal + 1e-6f, "Exponential tension parameter not monotonic in T");
          prevVal = val;
        }
      }

      // 3. Logarithmic: higher tension increases exponent k of (1-t)^k,
      // so s(t, T) = 1 - (1-t)^k is monotonically non-decreasing as T increases from -1 to +1.
      {
        TVMCurve cLog;
        cLog.reset();
        cLog.nodes[0].type = CurveType.logarithmic;

        float prevVal = -1e6f;
        for (int tStep = -20; tStep <= 20; ++tStep) {
          const float tension = cast(float) tStep / 20.0f;
          cLog.nodes[0].tension = tension;
          const float val = cLog.evaluate(t);

          assert(val >= prevVal - 1e-6f, "Logarithmic tension parameter not monotonic in T");
          prevVal = val;
        }
      }

      // 4. StepHold: threshold = clamp(1 - (T + 1) * 0.5) = clamp(0.5 - 0.5*T).
      // When T != 0, thresh varies from 1.0 (at T = -1) down to 0.0 (at T = +1).
      // However, line 225 of tvm.d has: if (tension == 0.0f) return (t < 1.0f) ? 0.0f : 1.0f;
      // This causes thresh to jump to 1.0 at T = 0.0, producing a severe non-monotonic notch glitch!
      {
        TVMCurve cStep;
        cStep.reset();
        cStep.nodes[0].type = CurveType.stepHold;

        bool stepHoldMonotonic = true;
        float prevVal = -1e6f;
        float failT1 = 0.0f, failT2 = 0.0f;
        float failV1 = 0.0f, failV2 = 0.0f;

        for (int tStep = -20; tStep <= 20; ++tStep) {
          const float tension = cast(float) tStep / 20.0f;
          cStep.nodes[0].tension = tension;
          const float val = cStep.evaluate(t);

          if (val < prevVal - 1e-6f) {
            stepHoldMonotonic = false;
            failT1 = cast(float)(tStep - 1) / 20.0f;
            failV1 = prevVal;
            failT2 = tension;
            failV2 = val;
          }
          prevVal = val;
        }

        if (!stepHoldMonotonic) {
          writefln("  [EMPIRICAL BUG CONFIRMED] StepHold tension is NOT monotonic in T at t=%.2f: T=%.2f -> %.1f, but T=%.2f -> %.1f!",
            t, failT1, failV1, failT2, failV2);
        }
        assert(stepHoldMonotonic, "StepHold tension must be monotonic in T across [-1.0, 1.0]");
      }

      // 5. S-Curve: symmetric transition around t = 0.5.
      // For t < 0.5, tension sharpens the curve (lower values), so val is non-increasing.
      // For t > 0.5, tension sharpens the curve (higher values), so val is non-decreasing.
      // At t = 0.5, val remains exactly 0.5 for all tensions.
      {
        TVMCurve cSCurve;
        cSCurve.reset();
        cSCurve.nodes[0].type = CurveType.sCurve;

        if (t < 0.5f) {
          float prevVal = 1e6f;
          for (int tStep = -20; tStep <= 20; ++tStep) {
            const float tension = cast(float) tStep / 20.0f;
            cSCurve.nodes[0].tension = tension;
            const float val = cSCurve.evaluate(t);

            assert(val <= prevVal + 1e-6f, "S-Curve tension (t < 0.5) not monotonic in T");
            prevVal = val;
          }
        } else if (t > 0.5f) {
          float prevVal = -1e6f;
          for (int tStep = -20; tStep <= 20; ++tStep) {
            const float tension = cast(float) tStep / 20.0f;
            cSCurve.nodes[0].tension = tension;
            const float val = cSCurve.evaluate(t);

            assert(val >= prevVal - 1e-6f, "S-Curve tension (t > 0.5) not monotonic in T");
            prevVal = val;
          }
        } else {
          // Exactly at t = 0.5
          for (int tStep = -20; tStep <= 20; ++tStep) {
            const float tension = cast(float) tStep / 20.0f;
            cSCurve.nodes[0].tension = tension;
            const float val = cSCurve.evaluate(0.5f);
            assert(fabs(val - 0.5f) < 1e-5f, "S-Curve inflection point at t=0.5 drifted");
          }
        }
      }
    }
  }

  // Part C: Verify falling segments (y0 > y1) are monotonic non-increasing
  {
    TVMCurve fallingCurve;
    fallingCurve.nodes[0] = CurveNode(0.0f, 1.0f, 0.0f, CurveType.linear);
    fallingCurve.nodes[1] = CurveNode(1.0f, 0.0f, 0.0f, CurveType.linear);

    foreach (type; allTypes) {
      fallingCurve.nodes[0].type = type;
      for (float tens = -1.0f; tens <= 1.0f; tens += 0.5f) {
        fallingCurve.nodes[0].tension = tens;
        float prevY = 1.0f;
        for (float p = 0.0f; p <= 1.0f; p += 0.02f) {
          const float y = fallingCurve.evaluate(p);
          assert(!isNaN(y) && !isInfinity(y));
          assert(y <= prevY + 1e-6f, "Falling segment violated monotonic descent");
          prevY = y;
        }
      }
    }
  }

  // Part D: Empirical verification of mapLogarithmic endpoint precision
  {
    assert(mapLogarithmic(20.0f, 20000.0f, 0.0f) == 20.0f, "mapLogarithmic at 0.0 must exactly match pMin");
    assert(mapLogarithmic(20.0f, 20000.0f, 1.0f) == 20000.0f, "mapLogarithmic at 1.0 must exactly match pMax");
    assert(mapLogarithmic(20000.0f, 20.0f, 0.0f) == 20000.0f, "Inverted mapLogarithmic at 0.0 must exactly match pMin");
    assert(mapLogarithmic(20000.0f, 20.0f, 1.0f) == 20.0f, "Inverted mapLogarithmic at 1.0 must exactly match pMax");
    assert(mapLogarithmic(20.0f, 20000.0f, -1.0f) == 20.0f, "Underflow mapLogarithmic must exactly match pMin");
    assert(mapLogarithmic(20.0f, 20000.0f, 2.0f) == 20000.0f, "Overflow mapLogarithmic must exactly match pMax");
  }

  writeln("[CHALLENGE M3] Suite 2 Passed Successfully.");
}

// =============================================================================
// Suite 3: Coincident Nodes (dx = 0, dx = 10^-7) & Near-Coincident Geometries
// =============================================================================

void testCoincidentNodesEmpirical() {
  writeln("[CHALLENGE M3] Running Suite 3: Coincident Nodes (dx = 0, dx = 10^-7) Stress Tests...");

  // 1. Exact coincident nodes dx = 0.0 at various timeline positions
  // Case A: dx = 0.0 at midpoint (x = 0.5)
  {
    TVMCurve c;
    c.numNodes = 4;
    c.nodes[0] = CurveNode(0.0f, 0.1f, 0.0f, CurveType.linear);
    c.nodes[1] = CurveNode(0.5f, 0.4f, 0.0f, CurveType.linear);
    c.nodes[2] = CurveNode(0.5f, 0.9f, 0.0f, CurveType.linear); // dx = 0
    c.nodes[3] = CurveNode(1.0f, 1.0f, 0.0f, CurveType.linear);

    // Evaluate across and directly on the coincident junction
    static immutable float[] testP = [
      0.0f, 0.25f, 0.4999f, 0.499999f, 0.5f, 0.500001f, 0.5001f, 0.75f, 1.0f
    ];

    foreach (p; testP) {
      const float y = c.evaluate(p);
      assert(!isNaN(y), "Coincident node produced NaN");
      assert(!isInfinity(y), "Coincident node produced Infinity");
      assert(y >= 0.1f && y <= 1.0f, "Coincident node output out of bounds");
    }
  }

  // Case B: Triple coincident nodes at x = 0.5
  {
    TVMCurve c;
    c.numNodes = 5;
    c.nodes[0] = CurveNode(0.0f, 0.0f, 0.0f, CurveType.linear);
    c.nodes[1] = CurveNode(0.5f, 0.3f, 0.0f, CurveType.linear);
    c.nodes[2] = CurveNode(0.5f, 0.6f, 0.0f, CurveType.linear);
    c.nodes[3] = CurveNode(0.5f, 0.9f, 0.0f, CurveType.linear);
    c.nodes[4] = CurveNode(1.0f, 1.0f, 0.0f, CurveType.linear);

    for (float p = 0.0f; p <= 1.0f; p += 0.01f) {
      const float y = c.evaluate(p);
      assert(!isNaN(y) && !isInfinity(y), "Triple coincident nodes produced NaN/Inf");
      assert(y >= 0.0f && y <= 1.0f);
    }
  }

  // 2. Near-coincident nodes with dx = 10^-7, 10^-8, and 10^-6
  {
    static immutable float[] dxValues = [
      0.0f, 1e-9f, 1e-8f, 1e-7f, 5e-7f, 1e-6f, 1.001e-6f, 2e-6f, 1e-5f
    ];

    foreach (dx; dxValues) {
      TVMCurve c;
      c.numNodes = 4;
      c.nodes[0] = CurveNode(0.0f, 0.0f, 0.0f, CurveType.linear);
      c.nodes[1] = CurveNode(0.5f, 0.25f, 0.0f, CurveType.linear);
      c.nodes[2] = CurveNode(0.5f + dx, 0.75f, 0.0f, CurveType.linear);
      c.nodes[3] = CurveNode(1.0f, 1.0f, 0.0f, CurveType.linear);

      // Probe around 0.5 with high resolution
      for (float offset = -1e-5f; offset <= dx + 1e-5f; offset += 1e-7f) {
        const float p = 0.5f + offset;
        const float y = c.evaluate(p);
        assert(!isNaN(y), "Near-coincident node produced NaN");
        assert(!isInfinity(y), "Near-coincident node produced Infinity");
        assert(y >= 0.0f && y <= 1.0f, "Near-coincident node output out of bounds");
      }
    }
  }

  // 3. Maximum node capacity (16 nodes) with dense spacing
  {
    TVMCurve fullCurve;
    fullCurve.numNodes = MaxCurveNodes;
    for (int i = 0; i < MaxCurveNodes; ++i) {
      const float x = cast(float) i / cast(float)(MaxCurveNodes - 1);
      const float y = (i % 2 == 0) ? 0.1f : 0.9f;
      fullCurve.nodes[i] = CurveNode(x, y, 0.0f, CurveType.linear);
    }

    // Dense evaluation across all 15 segments
    for (int step = 0; step <= 1500; ++step) {
      const float p = cast(float) step / 1500.0f;
      const float y = fullCurve.evaluate(p);
      assert(!isNaN(y) && !isInfinity(y));
      assert(y >= 0.1f && y <= 0.9f);
    }
  }

  writeln("[CHALLENGE M3] Suite 3 Passed Successfully.");
}

// =============================================================================
// Suite 4: All 12 Preset Shapes Range Bounds [0.0, 1.0] and Exact Endpoints
// =============================================================================

void testAll12PresetsBoundsAndEndpointsEmpirical() {
  writeln("[CHALLENGE M3] Running Suite 4: All 12 Preset Shapes Bounds & Endpoints...");

  struct PresetExpectation {
    int id;
    string name;
    float startY;
    float endY;
  }

  static immutable PresetExpectation[12] expectations = [
    PresetExpectation(0,  "Flat Low",   0.0f, 0.0f),
    PresetExpectation(1,  "Flat High",  1.0f, 1.0f),
    PresetExpectation(2,  "Ramp Up",    0.0f, 1.0f),
    PresetExpectation(3,  "Ramp Down",  1.0f, 0.0f),
    PresetExpectation(4,  "Exp Rise",   0.0f, 1.0f),
    PresetExpectation(5,  "Exp Fall",   1.0f, 0.0f),
    PresetExpectation(6,  "Sine 1x",    0.0f, 0.0f),
    PresetExpectation(7,  "Sine 2x",    0.0f, 0.0f),
    PresetExpectation(8,  "Step Up",    0.0f, 1.0f),
    PresetExpectation(9,  "Step Down",  1.0f, 0.0f),
    PresetExpectation(10, "Spike",      0.0f, 0.0f),
    PresetExpectation(11, "Chaos",      0.2f, 1.0f)
  ];

  TVMCurve curve;

  foreach (exp; expectations) {
    curve.loadPreset(exp.id);

    // 1. Exact boundary endpoints in TVMCurve
    const float yStart = curve.evaluate(0.0f);
    const float yEnd = curve.evaluate(1.0f);

    assert(fabs(yStart - exp.startY) < 1e-5f,
      "Preset start endpoint mismatch: " ~ exp.name);
    assert(fabs(yEnd - exp.endY) < 1e-5f,
      "Preset end endpoint mismatch: " ~ exp.name);

    // 2. Exact boundary endpoints in evaluatePreset
    const float yStartAna = evaluatePreset(exp.id, 0.0f);
    const float yEndAna = evaluatePreset(exp.id, 1.0f);

    assert(fabs(yStartAna - exp.startY) < 1e-5f,
      "evaluatePreset start endpoint mismatch: " ~ exp.name);
    assert(fabs(yEndAna - exp.endY) < 1e-5f,
      "evaluatePreset end endpoint mismatch: " ~ exp.name);

    // 3. Dense sweep across 2000 points verifying strict range bounds [0.0, 1.0]
    for (int step = 0; step <= 2000; ++step) {
      const float p = cast(float) step / 2000.0f;
      const float ySpline = curve.evaluate(p);
      const float yAna = evaluatePreset(exp.id, p);

      assert(!isNaN(ySpline) && !isInfinity(ySpline), "Preset produced NaN/Inf: " ~ exp.name);
      assert(!isNaN(yAna) && !isInfinity(yAna), "evaluatePreset produced NaN/Inf: " ~ exp.name);

      assert(ySpline >= 0.0f && ySpline <= 1.0f,
        "Preset spline exceeded [0.0, 1.0]: " ~ exp.name);
      assert(yAna >= 0.0f && yAna <= 1.0f,
        "Preset analytical exceeded [0.0, 1.0]: " ~ exp.name);
    }

    // 4. Verification of characteristic features per preset
    switch (exp.id) {
      case 0: // Flat Low
        assert(curve.evaluate(0.5f) == 0.0f);
        break;
      case 1: // Flat High
        assert(curve.evaluate(0.5f) == 1.0f);
        break;
      case 2: // Ramp Up
        assert(fabs(curve.evaluate(0.5f) - 0.5f) < 1e-5f);
        break;
      case 3: // Ramp Down
        assert(fabs(curve.evaluate(0.5f) - 0.5f) < 1e-5f);
        break;
      case 4: // Exp Rise
        assert(fabs(curve.evaluate(0.5f) - 0.125f) < 1e-5f);
        break;
      case 5: // Exp Fall
        assert(fabs(curve.evaluate(0.5f) - 0.125f) < 1e-5f);
        break;
      case 6: // Sine 1x peak at 0.5
        assert(fabs(curve.evaluate(0.5f) - 1.0f) < 1e-4f);
        assert(fabs(evaluatePreset(6, 0.5f) - 1.0f) < 1e-4f);
        break;
      case 7: // Sine 2x peaks at 0.25 and 0.75, trough at 0.5
        assert(fabs(curve.evaluate(0.25f) - 1.0f) < 1e-4f);
        assert(fabs(curve.evaluate(0.5f) - 0.0f) < 1e-4f);
        assert(fabs(curve.evaluate(0.75f) - 1.0f) < 1e-4f);
        break;
      case 8: // Step Up transition at 0.5
        assert(curve.evaluate(0.49f) == 0.0f);
        assert(curve.evaluate(0.51f) == 1.0f);
        break;
      case 9: // Step Down transition at 0.5
        assert(curve.evaluate(0.49f) == 1.0f);
        assert(curve.evaluate(0.51f) == 0.0f);
        break;
      case 10: // Spike peak at 0.5
        assert(fabs(curve.evaluate(0.5f) - 1.0f) < 1e-4f);
        break;
      case 11: // Chaos
        // Verify all 8 glitch levels in [0.05, 1.0]
        for (float p = 0.05f; p < 1.0f; p += 0.125f) {
          const float val = curve.evaluate(p);
          assert(val >= 0.05f && val <= 1.0f);
        }
        break;
      default:
        break;
    }
  }

  // 5. Test invalid preset IDs (out of bounds)
  curve.loadPreset(-1);
  assert(curve.presetId == cast(int) TVMCurvePreset.rampUp, "Invalid preset ID did not fallback");
  curve.loadPreset(99);
  assert(curve.presetId == cast(int) TVMCurvePreset.rampUp, "Invalid preset ID did not fallback");

  writeln("[CHALLENGE M3] Suite 4 Passed Successfully.");
}

// =============================================================================
// Suite 5: ParameterSmoother Stability Across Sample Rates (8k, 44.1k, 96k, 192k)
// =============================================================================

void testParameterSmootherStabilityEmpirical() {
  writeln("[CHALLENGE M3] Running Suite 5: ParameterSmoother Multi-Sample-Rate Stability...");

  static immutable double[] sampleRates = [
    8000.0, 44100.0, 48000.0, 88200.0, 96000.0, 192000.0, 384000.0
  ];

  foreach (sr; sampleRates) {
    ParameterSmoother sm;
    sm.reset(sr, 0.0f, 0.003f); // 3 ms tau

    // 1. Verify filter coefficient beta bounds and pole location
    // beta = 1 - exp(-1 / (tau * fs))
    // Pole is at z = 1 - beta. For stability: 0 < beta <= 1 => 0 <= pole < 1.
    assert(sm.beta > 0.0f, "Beta must be strictly positive");
    assert(sm.beta <= 1.0f, "Beta must not exceed 1.0");
    const float pole = 1.0f - sm.beta;
    assert(pole >= 0.0f && pole < 1.0f, "Filter pole outside stable unit circle region");

    // 2. Step response to unit step (0.0 -> 1.0)
    sm.setTarget(1.0f);
    assert(sm.value() == 0.0f);

    const int tauSamples = cast(int)(0.003 * sr);
    float prevVal = 0.0f;

    // Run to 1 tau
    for (int n = 0; n < tauSamples; ++n) {
      const float v = sm.nextSample();
      assert(!isNaN(v) && !isInfinity(v), "NaN/Inf in smoother nextSample");
      assert(v >= prevVal, "Smoother step response violated monotonic ascent (ringing/overshoot)");
      assert(v <= 1.0f, "Smoother overshot target 1.0");
      prevVal = v;
    }

    // At t = tau, step response should reach 1 - 1/e ~ 0.63212
    const float valAtTau = sm.value();
    assert(fabs(valAtTau - 0.63212f) < 0.025f,
      "Smoother response at tau deviated from theoretical 1 - 1/e");

    // Run to 5 tau (should reach ~0.993)
    for (int n = 0; n < 4 * tauSamples; ++n) {
      const float v = sm.nextSample();
      assert(v >= prevVal);
      prevVal = v;
    }
    assert(sm.value() >= 0.985f, "Smoother did not reach ~99% after 5 tau");

    // Run to 15 tau: verify complete settling and stall/denormal immunity
    // (Needs > 6*ln(10) ~ 13.8 tau for diff to drop below 1e-6f threshold)
    for (int n = 0; n < 10 * tauSamples; ++n) {
      sm.nextSample();
    }
    assert(sm.value() == 1.0f, "Smoother did not settle to exact target (subnormal stall)");
    assert(sm.isSettled(), "isSettled() returned false after 15 tau");

    // 3. Step response to downward step (1.0 -> 0.0)
    sm.setTarget(0.0f);
    prevVal = 1.0f;
    for (int n = 0; n < tauSamples; ++n) {
      const float v = sm.nextSample();
      assert(v <= prevVal, "Downward step violated monotonic descent");
      assert(v >= 0.0f, "Downward step undershot 0.0");
      prevVal = v;
    }
    // At t = tau, downward step should reach 1/e ~ 0.36788
    assert(fabs(sm.value() - 0.36788f) < 0.025f,
      "Downward response at tau deviated from theoretical 1/e");

    for (int n = 0; n < 15 * tauSamples; ++n) {
      sm.nextSample();
    }
    assert(sm.value() == 0.0f, "Downward step did not settle to exact 0.0");
    assert(sm.isSettled());

    // 4. Large step stress: [-100,000 to +100,000]
    sm.snapTo(-100_000.0f);
    assert(sm.value() == -100_000.0f);
    sm.setTarget(100_000.0f);
    for (int n = 0; n < 15 * tauSamples; ++n) {
      sm.nextSample();
    }
    assert(sm.value() == 100_000.0f, "Large step did not settle to exact target");

    // 5. Denormal target stress (target = subnormal float)
    sm.snapTo(0.0f);
    sm.setTarget(float.min_normal * 0.1f);
    for (int n = 0; n < 100; ++n) {
      const float v = sm.nextSample();
      assert(!isNaN(v) && !isInfinity(v));
    }
    assert(sm.isSettled());

    // 6. SnapTo behavior
    sm.snapTo(777.0f);
    assert(sm.value() == 777.0f);
    assert(sm.isSettled());
    // nextSample without new target stays at 777
    assert(sm.nextSample() == 777.0f);

    // 7. Robustness against NaN and Inf inputs
    sm.snapTo(10.0f);
    sm.setTarget(float.nan); // Must be ignored
    assert(sm.target == 10.0f);
    sm.setTarget(float.infinity); // Must be ignored
    assert(sm.target == 10.0f);

    sm.snapTo(float.nan); // Sanitized to 0.0
    assert(sm.value() == 0.0f);
    sm.snapTo(float.infinity); // Sanitized to 0.0
    assert(sm.value() == 0.0f);
  }

  writeln("[CHALLENGE M3] Suite 5 Passed Successfully.");
}

// =============================================================================
// Suite 6: 100% @nogc nothrow pure @safe Execution Under Heavy Stress (150k iters)
// =============================================================================

// Compile-time statically verified pure @nogc nothrow @safe test pipeline
@nogc nothrow pure @safe float runNoGCTVMStressPipeline(
  ref TVMCurve curve,
  ref ParameterSmoother smoother,
  ref TVMModulator modulator,
  ref TVMModulationEngine engine,
  float phase,
  float target
) {
  // 1. TVMCurve evaluation
  const float cVal = curve.evaluate(phase);

  // 2. Analytical preset evaluation
  const float pVal = evaluatePreset(cast(int)(phase * 11.0f), phase);

  // 3. Modulation mapping functions
  const float linVal = mapLinear(200.0f, 8000.0f, cVal);
  const float logVal = mapLogarithmic(20.0f, 20000.0f, cVal);
  const float modVal = evaluateModulatedParam(true, true, 1000.0f, 100.0f, 10000.0f, cVal, true);

  // 4. ParameterSmoother advancement
  const float smVal = smoother.nextSample(target);

  // 5. TVMModulator process
  const float modInst = modulator.evaluateInstant(curve, phase);
  const float modProc = modulator.process(curve, phase);

  // 6. TVMModulationEngine access and evaluation
  const float engCurveVal = engine.getCurve(TVMModuleSlot.stutter).evaluate(phase);

  return cVal + pVal + linVal + logVal + modVal + smVal + modInst + modProc + engCurveVal;
}

void testRealtimeNoGCUnderHeavyStress() {
  writeln("[CHALLENGE M3] Running Suite 6: Real-time @nogc nothrow pure @safe (150,000 Iterations)...");

  TVMCurve curve;
  curve.loadPreset(TVMCurvePreset.expRise);

  ParameterSmoother smoother;
  smoother.reset(48000.0, 0.0f, 0.003f);

  TVMModulator modulator;
  modulator.minVal = 100.0f;
  modulator.maxVal = 10000.0f;
  modulator.reset(100.0f);

  TVMModulationEngine engine;
  engine.reset(48000.0);

  // Warmup run
  const float warmup = runNoGCTVMStressPipeline(curve, smoother, modulator, engine, 0.5f, 1.0f);
  assert(!isNaN(warmup));

  // Collect garbage before benchmark to measure pure delta
  GC.collect();
  const auto statsBefore = GC.stats();

  float accum = 0.0f;

  // Execute 150,000 iterations under varying phase, presets, and target levels
  for (int iter = 0; iter < 150_000; ++iter) {
    const float phase = cast(float)(iter & 1023) / 1023.0f;
    const float target = (iter & 2048) ? 1.0f : 0.0f;

    // Switch presets periodically
    if ((iter & 0x1FFF) == 0) {
      const int presetId = (iter >> 13) % 12;
      curve.loadPreset(presetId);
    }

    // Trigger gesture periodically
    if ((iter & 0x3FFF) == 0) {
      engine.onGestureTriggered(phase);
    }

    accum += runNoGCTVMStressPipeline(curve, smoother, modulator, engine, phase, target);
  }

  const auto statsAfter = GC.stats();

  // Assert accumulator is finite
  assert(!isNaN(accum) && !isInfinity(accum), "Stress test accumulated non-finite value");

  // Strictly assert zero heap allocations during the 150,000 real-time iterations
  assert(statsAfter.usedSize == statsBefore.usedSize,
    "Heap memory was allocated inside TVM @nogc real-time audio pipeline!");

  writefln("  [Stress Test] 150,000 iterations completed successfully | GC Delta = %d bytes | Accum = %.2f",
    statsAfter.usedSize - statsBefore.usedSize, accum);

  writeln("[CHALLENGE M3] Suite 6 Passed Successfully.");
}

// =============================================================================
// Master Entry Point for Milestone 3 Empirical Challenge
// =============================================================================

unittest {
  writeln("=== [Challenger M3_1] Starting Empirical Verification of Milestone 3 ===");
  testTVMCurveExtremeInputsEmpirical();
  testTensionMonotonicityEmpirical();
  testCoincidentNodesEmpirical();
  testAll12PresetsBoundsAndEndpointsEmpirical();
  testParameterSmootherStabilityEmpirical();
  testRealtimeNoGCUnderHeavyStress();
  writeln("=== [Challenger M3_1] All Milestone 3 Empirical Challenges PASSED ===");
}
