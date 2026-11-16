/**
 * Time-Variant Modifier (TVM) Curve Sequencer & Interpolation Engine.
 *
 * Implements multi-node breakpoint spline curve interpolation and parameter
 * modulation for kdr-stutter (iZotope Stutter Edit 2 clone).
 *
 * Features:
 * - Up to 16 breakpoint nodes (`CurveNode[16]`) with (x, y) in [0.0, 1.0].
 * - 5 segment curve types: linear, exponential, logarithmic, sCurve (smoothstep), stepHold.
 * - Continuous curvature tension parameter in [-1.0, +1.0].
 * - Bounded binary segment search (<= 4 iterations), strict boundary clamping,
 *   zero-divide protection, and NaN immunity.
 * - 12 preset curve shapes mapping 1-to-1 to `enum TVMCurvePreset` from `kdr.stutter.params`:
 *   Flat Low/High, Ramp Up/Down, Exp Rise/Fall, Sine 1x/2x, Step Up/Down, Spike, Chaos.
 * - Parameter modulation range scaling (`fclamp`, `mapLinear`, `mapLogarithmic`, `evaluateModulatedParam`).
 * - Single-pole parameter smoothing filter (`ParameterSmoother`, tau = 3 ms, subnormal flushing, `snapTo`).
 * - Coordinated `TVMModulationEngine` for all 14 Stutter Edit 2 module slots.
 * - 100% `@nogc nothrow pure @safe` real-time implementation with zero GC allocation.
 *
 * Copyright: kdr 2026.
 * License: Boost License 1.0.
 */
module kdr.stutter.tvm;

import core.math : fabs, cos;
import std.math : isNaN, isInfinity, PI, exp, log, pow;

import kdr.stutter.params : TVMCurvePreset;

/// Maximum number of breakpoint nodes in a TVM curve
enum int MaxCurveNodes = 16;

/// Supported curve segment interpolation types
enum CurveType : ubyte {
  linear = 0,
  exponential = 1,
  logarithmic = 2,
  sCurve = 3,
  stepHold = 4,
}

/// A single breakpoint node defining timeline position, target value, curvature tension, and segment type.
struct CurveNode {
  float x = 0.0f;       /// Timeline phase position in [0.0 .. 1.0]
  float y = 0.0f;       /// Target output value in [0.0 .. 1.0]
  float tension = 0.0f; /// Curvature tension parameter in [-1.0 .. +1.0]
  CurveType type = CurveType.linear; /// Interpolation method for segment starting at this node
}

// =============================================================================
// Standalone Analytical Preset Evaluators
// =============================================================================

/// Evaluates any of the 12 TVM presets analytically with zero allocation and NaN immunity.
@nogc nothrow pure @safe
float evaluatePreset(int presetId, float phase) {
  if (isNaN(phase)) return 0.0f;
  float p = phase;
  if (p < 0.0f) p = 0.0f;
  if (p > 1.0f) p = 1.0f;

  switch (presetId) {
    case TVMCurvePreset.flatLow: // 0: Flat Low
      return 0.0f;

    case TVMCurvePreset.flatHigh: // 1: Flat High
      return 1.0f;

    case TVMCurvePreset.rampUp: // 2: Ramp Up
      return p;

    case TVMCurvePreset.rampDown: // 3: Ramp Down
      return 1.0f - p;

    case TVMCurvePreset.expRise: // 4: Exp Rise (p^3)
      return p * p * p;

    case TVMCurvePreset.expFall: // 5: Exp Fall ((1-p)^3)
      const float inv = 1.0f - p;
      return inv * inv * inv;

    case TVMCurvePreset.sine1x: // 6: Sine 1x (1 full crest)
      return 0.5f - 0.5f * cos(p * (2.0f * PI));

    case TVMCurvePreset.sine2x: // 7: Sine 2x (2 full crests)
      return 0.5f - 0.5f * cos(p * (4.0f * PI));

    case TVMCurvePreset.stepUp: // 8: Step Up
      return (p < 0.5f) ? 0.0f : 1.0f;

    case TVMCurvePreset.stepDown: // 9: Step Down
      return (p < 0.5f) ? 1.0f : 0.0f;

    case TVMCurvePreset.spike: // 10: Spike (Impulse at 0.5)
      return (p < 0.5f) ? (2.0f * p) : (2.0f * (1.0f - p));

    case TVMCurvePreset.chaos: // 11: Chaos (8 glitch steps)
      const int step = cast(int)(p * 8.0f);
      static immutable float[8] glitch = [0.2f, 0.85f, 0.1f, 0.95f, 0.3f, 0.7f, 0.05f, 1.0f];
      const int idx = (step < 8) ? (step >= 0 ? step : 0) : 7;
      return glitch[idx];

    default:
      return p;
  }
}

/// Overload accepting TVMCurvePreset enum directly
@nogc nothrow pure @safe
float evaluatePreset(TVMCurvePreset preset, float phase) {
  return evaluatePreset(cast(int) preset, phase);
}

// =============================================================================
// TVMCurve Multi-Node Spline Sequencer
// =============================================================================

/// Multi-node spline curve sequencer with up to 16 breakpoints.
struct TVMCurve {
  int presetId = cast(int) TVMCurvePreset.rampUp;
  int numNodes = 2;
  CurveNode[MaxCurveNodes] nodes = [
    CurveNode(0.0f, 0.0f, 0.0f, CurveType.linear),
    CurveNode(1.0f, 1.0f, 0.0f, CurveType.linear),
  ];

  @nogc nothrow pure @safe:

  /// Evaluates curve output at normalized gesture phase p in [0.0 .. 1.0].
  /// Guarantees boundary clamping, NaN immunity, zero-divide protection, and finite bounds.
  float evaluate(float p) const {
    // 1. NaN and non-finite protection
    if (isNaN(p)) return nodes[0].y;

    // 2. Boundary clamping: p <= x0 -> y0; p >= xn-1 -> yn-1
    if (p <= nodes[0].x) return nodes[0].y;
    if (p >= nodes[numNodes - 1].x) return nodes[numNodes - 1].y;

    // 3. Fast binary search for active segment [idx, idx + 1] such that nodes[idx].x <= p <= nodes[idx + 1].x
    int low = 0;
    int high = numNodes - 1;
    while (low < high - 1) {
      const int mid = (low + high) >> 1;
      if (p >= nodes[mid].x) {
        low = mid;
      } else {
        high = mid;
      }
    }
    const int idx = low;

    const float x0 = nodes[idx].x;
    const float x1 = nodes[idx + 1].x;
    const float y0 = nodes[idx].y;
    const float y1 = nodes[idx + 1].y;
    const float dx = x1 - x0;

    // 4. Zero-divide protection for coincident or near-coincident breakpoint nodes
    if (dx <= 1e-6f) {
      return y0;
    }

    // 5. Normalized segment local phase t in [0.0 .. 1.0]
    float t = (p - x0) / dx;
    if (t < 0.0f) t = 0.0f;
    if (t > 1.0f) t = 1.0f;

    // 6. Evaluate segment interpolation according to CurveType and tension [-1.0 .. +1.0]
    const float s = evalSegment(nodes[idx].type, t, nodes[idx].tension);

    return y0 + s * (y1 - y0);
  }

  /// Evaluates segment progress s in [0.0 .. 1.0] given local phase t and tension T.
  private static float evalSegment(CurveType type, float t, float tension) {
    if (t <= 0.0f) return 0.0f;
    if (t >= 1.0f) return 1.0f;

    final switch (type) {
      case CurveType.linear:
        if (tension == 0.0f) {
          return t;
        } else if (tension > 0.0f) {
          const float k = 1.0f + 4.0f * tension;
          return t ^^ k;
        } else {
          const float k = 1.0f - 4.0f * tension;
          return 1.0f - ((1.0f - t) ^^ k);
        }

      case CurveType.exponential:
        if (tension == 0.0f) {
          return t * t * t;
        } else {
          const float k = (tension > 0.0f)
            ? (3.0f + 5.0f * tension)
            : (3.0f + 2.0f * tension);
          return t ^^ k;
        }

      case CurveType.logarithmic:
        if (tension == 0.0f) {
          const float inv = 1.0f - t;
          return 1.0f - (inv * inv * inv);
        } else {
          const float k = (tension > 0.0f)
            ? (3.0f + 5.0f * tension)
            : (3.0f + 2.0f * tension);
          const float inv = 1.0f - t;
          return 1.0f - (inv ^^ k);
        }

      case CurveType.sCurve:
        const float s0 = t * t * (3.0f - 2.0f * t);
        if (tension == 0.0f) {
          return s0;
        } else if (tension > 0.0f) {
          const float s1 = s0 * s0 * (3.0f - 2.0f * s0);
          return (1.0f - tension) * s0 + tension * s1;
        } else {
          return (1.0f + tension) * s0 + (-tension) * t;
        }

      case CurveType.stepHold:
        // Continuous, monotonic threshold placement across [-1.0, +1.0]:
        const float thresh = fclamp(0.5f - 0.5f * tension, 0.001f, 0.999f);
        return (t < thresh) ? 0.0f : 1.0f;
    }
  }

  /// Sets node attributes at index with strict boundary validation and coordinate ordering.
  bool setNode(int index, float x, float y, float tension, CurveType type) {
    if (index < 0 || index >= numNodes) return false;

    float cx = fclamp(x, 0.0f, 1.0f);
    const float cy = fclamp(y, 0.0f, 1.0f);
    const float ct = fclamp(tension, -1.0f, 1.0f);

    // Endpoints must remain pinned at x=0.0 and x=1.0
    if (index == 0) {
      cx = 0.0f;
    } else if (index == numNodes - 1) {
      cx = 1.0f;
    } else {
      // Intermediate nodes are constrained between neighboring nodes
      const float minX = nodes[index - 1].x;
      const float maxX = nodes[index + 1].x;
      cx = fclamp(cx, minX, maxX);
    }

    nodes[index] = CurveNode(cx, cy, ct, type);
    presetId = -1; // Marked custom
    return true;
  }

  /// Inserts a new node while keeping nodes sorted by ascending x coordinate.
  bool addNode(float x, float y, float tension = 0.0f, CurveType type = CurveType.linear) {
    if (numNodes >= MaxCurveNodes) return false;

    const float cx = fclamp(x, 0.0f, 1.0f);
    const float cy = fclamp(y, 0.0f, 1.0f);
    const float ct = fclamp(tension, -1.0f, 1.0f);

    // Find insertion index
    int insertIdx = 0;
    while (insertIdx < numNodes && nodes[insertIdx].x <= cx) {
      insertIdx++;
    }

    // Shift subsequent elements
    for (int i = numNodes; i > insertIdx; --i) {
      nodes[i] = nodes[i - 1];
    }

    nodes[insertIdx] = CurveNode(cx, cy, ct, type);
    numNodes++;
    presetId = -1; // Marked custom
    return true;
  }

  /// Removes node at specified index (retaining at least 2 endpoints).
  bool removeNode(int index) {
    if (numNodes <= 2) return false;
    if (index <= 0 || index >= numNodes - 1) return false;

    for (int i = index; i < numNodes - 1; ++i) {
      nodes[i] = nodes[i + 1];
    }
    numNodes--;
    presetId = -1; // Marked custom
    return true;
  }

  /// Resets curve to default linear rise: (0, 0) -> (1, 1).
  void reset() {
    numNodes = 2;
    presetId = cast(int) TVMCurvePreset.rampUp;
    nodes[0] = CurveNode(0.0f, 0.0f, 0.0f, CurveType.linear);
    nodes[1] = CurveNode(1.0f, 1.0f, 0.0f, CurveType.linear);
    for (int i = 2; i < MaxCurveNodes; ++i) {
      nodes[i] = CurveNode(1.0f, 1.0f, 0.0f, CurveType.linear);
    }
  }

  /// Sorts all nodes by ascending x coordinate and ensures endpoints are at 0.0 and 1.0.
  void sortNodes() {
    for (int i = 1; i < numNodes; ++i) {
      CurveNode key = nodes[i];
      int j = i - 1;
      while (j >= 0 && nodes[j].x > key.x) {
        nodes[j + 1] = nodes[j];
        j--;
      }
      nodes[j + 1] = key;
    }
    if (numNodes >= 2) {
      nodes[0].x = 0.0f;
      nodes[numNodes - 1].x = 1.0f;
    }
    presetId = -1;
  }

  /// Number of active breakpoint nodes.
  int nodeCount() const { return numNodes; }

  /// Read-only slice of active breakpoint nodes.
  const(CurveNode)[] activeNodes() const return { return nodes[0 .. numNodes]; }

  /// Loads one of the 12 preset curve shapes mapping 1-to-1 to TVMCurvePreset.
  void loadPreset(int id) {
    reset();
    if (id < 0 || id > 11) {
      id = cast(int) TVMCurvePreset.rampUp;
    }
    presetId = id;

    switch (id) {
      case TVMCurvePreset.flatLow: // 0: Flat Low
        numNodes = 2;
        nodes[0] = CurveNode(0.0f, 0.0f, 0.0f, CurveType.linear);
        nodes[1] = CurveNode(1.0f, 0.0f, 0.0f, CurveType.linear);
        break;

      case TVMCurvePreset.flatHigh: // 1: Flat High
        numNodes = 2;
        nodes[0] = CurveNode(0.0f, 1.0f, 0.0f, CurveType.linear);
        nodes[1] = CurveNode(1.0f, 1.0f, 0.0f, CurveType.linear);
        break;

      case TVMCurvePreset.rampUp: // 2: Ramp Up
        numNodes = 2;
        nodes[0] = CurveNode(0.0f, 0.0f, 0.0f, CurveType.linear);
        nodes[1] = CurveNode(1.0f, 1.0f, 0.0f, CurveType.linear);
        break;

      case TVMCurvePreset.rampDown: // 3: Ramp Down
        numNodes = 2;
        nodes[0] = CurveNode(0.0f, 1.0f, 0.0f, CurveType.linear);
        nodes[1] = CurveNode(1.0f, 0.0f, 0.0f, CurveType.linear);
        break;

      case TVMCurvePreset.expRise: // 4: Exp Rise (p^3)
        numNodes = 2;
        nodes[0] = CurveNode(0.0f, 0.0f, 0.0f, CurveType.exponential);
        nodes[1] = CurveNode(1.0f, 1.0f, 0.0f, CurveType.exponential);
        break;

      case TVMCurvePreset.expFall: // 5: Exp Fall ((1-p)^3)
        numNodes = 2;
        nodes[0] = CurveNode(0.0f, 1.0f, 0.0f, CurveType.logarithmic);
        nodes[1] = CurveNode(1.0f, 0.0f, 0.0f, CurveType.logarithmic);
        break;

      case TVMCurvePreset.sine1x: // 6: Sine 1x (1 full crest)
        numNodes = 3;
        nodes[0] = CurveNode(0.0f, 0.0f, 0.0f, CurveType.sCurve);
        nodes[1] = CurveNode(0.5f, 1.0f, 0.0f, CurveType.sCurve);
        nodes[2] = CurveNode(1.0f, 0.0f, 0.0f, CurveType.sCurve);
        break;

      case TVMCurvePreset.sine2x: // 7: Sine 2x (2 full crests)
        numNodes = 5;
        nodes[0] = CurveNode(0.0f,  0.0f, 0.0f, CurveType.sCurve);
        nodes[1] = CurveNode(0.25f, 1.0f, 0.0f, CurveType.sCurve);
        nodes[2] = CurveNode(0.5f,  0.0f, 0.0f, CurveType.sCurve);
        nodes[3] = CurveNode(0.75f, 1.0f, 0.0f, CurveType.sCurve);
        nodes[4] = CurveNode(1.0f,  0.0f, 0.0f, CurveType.sCurve);
        break;

      case TVMCurvePreset.stepUp: // 8: Step Up
        numNodes = 2;
        nodes[0] = CurveNode(0.0f, 0.0f, 0.0f, CurveType.stepHold);
        nodes[1] = CurveNode(1.0f, 1.0f, 0.0f, CurveType.stepHold);
        break;

      case TVMCurvePreset.stepDown: // 9: Step Down
        numNodes = 2;
        nodes[0] = CurveNode(0.0f, 1.0f, 0.0f, CurveType.stepHold);
        nodes[1] = CurveNode(1.0f, 0.0f, 0.0f, CurveType.stepHold);
        break;

      case TVMCurvePreset.spike: // 10: Spike
        numNodes = 3;
        nodes[0] = CurveNode(0.0f, 0.0f, 0.0f, CurveType.linear);
        nodes[1] = CurveNode(0.5f, 1.0f, 0.0f, CurveType.linear);
        nodes[2] = CurveNode(1.0f, 0.0f, 0.0f, CurveType.linear);
        break;

      case TVMCurvePreset.chaos: // 11: Chaos (8 glitch steps)
        numNodes = 9;
        static immutable float[8] glitch = [0.2f, 0.85f, 0.1f, 0.95f, 0.3f, 0.7f, 0.05f, 1.0f];
        for (int i = 0; i < 8; ++i) {
          nodes[i] = CurveNode(cast(float) i * 0.125f, glitch[i], 0.0f, CurveType.stepHold);
        }
        nodes[8] = CurveNode(1.0f, glitch[7], 0.0f, CurveType.stepHold);
        break;

      default:
        break;
    }
  }

  /// Overload accepting TVMCurvePreset enum directly
  void loadPreset(TVMCurvePreset preset) {
    loadPreset(cast(int) preset);
  }
}

// =============================================================================
// Parameter Modulation Mapping Functions
// =============================================================================

/// Clamps a float value between specified lower and upper bounds
@nogc nothrow pure @safe
float fclamp(float v, float lo, float hi) {
  return (v < lo) ? lo : ((v > hi) ? hi : v);
}

/// Evaluates linear range scaling: P_eff = P_min + curveVal * (P_max - P_min)
/// Supports inverted sweeps (P_min > P_max) and clamps output strictly within range bounds.
@nogc nothrow pure @safe
float mapLinear(float pMin, float pMax, float curveVal) {
  if (isNaN(curveVal) || isInfinity(curveVal)) curveVal = 0.0f;
  if (isNaN(pMin) || isInfinity(pMin)) pMin = 0.0f;
  if (isNaN(pMax) || isInfinity(pMax)) pMax = 0.0f;

  float y = curveVal;
  if (y < 0.0f) y = 0.0f;
  if (y > 1.0f) y = 1.0f;

  const float pEff = pMin + y * (pMax - pMin);
  const float lo = (pMin < pMax) ? pMin : pMax;
  const float hi = (pMin < pMax) ? pMax : pMin;
  return fclamp(pEff, lo, hi);
}

/// Evaluates logarithmic range scaling for frequency/pitch domains
/// Falls back to linear mapping if either bound is non-positive.
@nogc nothrow pure @safe
float mapLogarithmic(float pMin, float pMax, float curveVal) {
  if (pMin <= 0.0f || pMax <= 0.0f) {
    return mapLinear(pMin, pMax, curveVal);
  }

  if (isNaN(curveVal) || isInfinity(curveVal)) curveVal = 0.0f;
  float y = curveVal;
  if (y < 0.0f) y = 0.0f;
  if (y > 1.0f) y = 1.0f;

  // Exact endpoint checks to avoid transcendental float roundoff at y=0 and y=1
  if (y <= 0.0f) return pMin;
  if (y >= 1.0f) return pMax;

  const float logMin = log(pMin);
  const float logMax = log(pMax);
  const float pEff = exp(logMin + y * (logMax - logMin));
  const float lo = (pMin < pMax) ? pMin : pMax;
  const float hi = (pMin < pMax) ? pMax : pMin;
  return fclamp(pEff, lo, hi);
}

/// Evaluates parameter modulation with full bypass logic:
/// Returns static base knob value when:
/// 1. Modulation is disabled (!modEnabled)
/// 2. Gesture is inactive (!gestureActive)
/// 3. Min equals Max (|pMax - pMin| <= 1e-6f)
@nogc nothrow pure @safe
float evaluateModulatedParam(
    bool modEnabled,
    bool gestureActive,
    float baseKnobValue,
    float pMin,
    float pMax,
    float curveVal,
    bool isLogarithmic = false
) {
  if (!modEnabled || !gestureActive) {
    return baseKnobValue;
  }

  if (fabs(pMax - pMin) <= 1e-6f) {
    return baseKnobValue;
  }

  return isLogarithmic ? mapLogarithmic(pMin, pMax, curveVal)
                       : mapLinear(pMin, pMax, curveVal);
}

// =============================================================================
// TVM Modulator Struct (Encapsulated Range + Smoothing)
// =============================================================================

/// TVM Parameter Modulator for mapping curve output to arbitrary parameter min/max ranges with smoothing.
struct TVMModulator {
  float minVal = 0.0f;
  float maxVal = 1.0f;
  float currentVal = 0.0f;
  float smoothingCoeff = 0.05f; /// Single-pole smoothing factor alpha in (0, 1]
  bool enabled = true;

  @nogc nothrow pure @safe:

  /// Resets smoothed value state.
  void reset(float initialVal) {
    currentVal = initialVal;
  }

  /// Evaluates modulation at gesture phase and advances smoothed state.
  float process(const ref TVMCurve curve, float phase) {
    if (!enabled) return currentVal;
    const float curveVal = curve.evaluate(phase);
    const float targetVal = minVal + curveVal * (maxVal - minVal);
    currentVal += smoothingCoeff * (targetVal - currentVal);
    return currentVal;
  }

  /// Instantaneous modulation evaluation without state mutation.
  float evaluateInstant(const ref TVMCurve curve, float phase) const {
    if (!enabled) return currentVal;
    const float curveVal = curve.evaluate(phase);
    return minVal + curveVal * (maxVal - minVal);
  }
}

// =============================================================================
// Single-Pole Parameter Smoothing Filter
// =============================================================================

/// Single-pole parameter smoothing filter:
///   beta = 1 - exp(-1 / (tau * fs))
/// Eliminates zipper noise on fast automation sweeps and parameter step jumps.
struct ParameterSmoother {
  float current = 0.0f;
  float target = 0.0f;
  float beta = 0.05f;
  double sampleRate = 44_100.0;
  float timeConstant = 0.003f; // Default 3 ms tau

  @nogc nothrow pure @safe:

  /// Resets smoother to sample rate and initial value
  void reset(double sr, float initialVal = 0.0f, float tau = 0.003f) {
    sampleRate = (sr > 1000.0) ? sr : 44_100.0;
    timeConstant = (tau > 0.0001f) ? tau : 0.003f;
    computeBeta();
    current = initialVal;
    target = initialVal;
  }

  /// Sets filter time constant in seconds (e.g. 0.002 to 0.005 s)
  void setTimeConstant(float tau) {
    timeConstant = (tau > 0.0001f) ? tau : 0.0001f;
    computeBeta();
  }

  /// Sets audio sample rate and updates beta
  void setSampleRate(double sr) {
    sampleRate = (sr > 1000.0) ? sr : 44_100.0;
    computeBeta();
  }

  /// Instantly snaps smoother state to val without slewing (used on gesture trigger)
  void snapTo(float val) {
    if (isNaN(val) || isInfinity(val)) val = 0.0f;
    current = val;
    target = val;
  }

  /// Updates target value
  void setTarget(float val) {
    if (isNaN(val) || isInfinity(val)) return;
    target = val;
  }

  /// Advances smoother by one sample towards new target and returns current smoothed value
  float nextSample(float newTarget) {
    setTarget(newTarget);
    return nextSample();
  }

  /// Advances smoother by one sample towards current target and returns smoothed value
  float nextSample() {
    const float diff = target - current;
    const float nextVal = current + beta * diff;
    // Subnormal / denormal and floating-point stall protection:
    // If the step is too small to change the float representation, or difference is negligible
    if (nextVal == current || fabs(diff) < 1e-6f) {
      current = target;
    } else {
      current = nextVal;
    }
    return current;
  }

  /// Returns current smoothed value
  float value() const {
    return current;
  }

  /// Returns true if smoother has settled within eps of target
  bool isSettled(float eps = 1e-5f) const {
    return fabs(target - current) < eps;
  }

private:
  void computeBeta() {
    const double tauSamples = timeConstant * sampleRate;
    if (tauSamples <= 0.01) {
      beta = 1.0f;
    } else {
      beta = cast(float)(1.0 - exp(-1.0 / tauSamples));
      if (beta > 1.0f) beta = 1.0f;
      if (beta < 0.0f) beta = 0.0f;
    }
  }
}

// =============================================================================
// TVM Modulation Engine (Multi-Module Coordinator)
// =============================================================================

enum TVMModuleSlot : int {
  stutter   = 0,
  buffer    = 1,
  gate      = 2,
  pan       = 3,
  tapeStop  = 4,
  filter    = 5,
  lofi      = 6,
  distort   = 7,
  comb      = 8,
  chorus    = 9,
  flanger   = 10,
  phaser    = 11,
  reverb    = 12,
  delay     = 13,
}

enum int NumTVMModuleSlots = 14;

/// Coordinated parameter modulation engine holding curves and smoothers
/// for all 14 Stutter Edit 2 modules.
struct TVMModulationEngine {
  TVMCurve[NumTVMModuleSlots] curves;

  // Dedicated single-pole parameter smoothers (tau = 3 ms)
  ParameterSmoother smoothBufferPos;
  ParameterSmoother smoothBufferPitch;
  ParameterSmoother smoothGateWidth;
  ParameterSmoother smoothPanCenter;
  ParameterSmoother smoothPanWidth;
  ParameterSmoother smoothTapeSlowdown;
  ParameterSmoother smoothFilterCutoff;
  ParameterSmoother smoothLofiBits;
  ParameterSmoother smoothLofiDownsample;
  ParameterSmoother smoothDistortDriveLow;
  ParameterSmoother smoothDistortDriveHigh;
  ParameterSmoother smoothCombFreq;
  ParameterSmoother smoothChorusDepth;
  ParameterSmoother smoothFlangerDepth;
  ParameterSmoother smoothPhaserCenter;
  ParameterSmoother smoothReverbSize;
  ParameterSmoother smoothDelayFeedback;

  @nogc nothrow pure @safe:

  void reset(double sampleRate) {
    // Reset all smoothers to audio sample rate with 3 ms time constant
    smoothBufferPos.reset(sampleRate, 0.0f, 0.003f);
    smoothBufferPitch.reset(sampleRate, 0.0f, 0.003f);
    smoothGateWidth.reset(sampleRate, 0.5f, 0.003f);
    smoothPanCenter.reset(sampleRate, 0.0f, 0.003f);
    smoothPanWidth.reset(sampleRate, 1.0f, 0.003f);
    smoothTapeSlowdown.reset(sampleRate, 0.0f, 0.003f);
    smoothFilterCutoff.reset(sampleRate, 8000.0f, 0.003f);
    smoothLofiBits.reset(sampleRate, 16.0f, 0.003f);
    smoothLofiDownsample.reset(sampleRate, 1.0f, 0.003f);
    smoothDistortDriveLow.reset(sampleRate, 0.0f, 0.003f);
    smoothDistortDriveHigh.reset(sampleRate, 0.0f, 0.003f);
    smoothCombFreq.reset(sampleRate, 200.0f, 0.003f);
    smoothChorusDepth.reset(sampleRate, 0.5f, 0.003f);
    smoothFlangerDepth.reset(sampleRate, 1.0f, 0.003f);
    smoothPhaserCenter.reset(sampleRate, 1000.0f, 0.003f);
    smoothReverbSize.reset(sampleRate, 0.5f, 0.003f);
    smoothDelayFeedback.reset(sampleRate, 0.4f, 0.003f);

    // Initialize default curves
    for (int i = 0; i < NumTVMModuleSlots; ++i) {
      curves[i].loadPreset(TVMCurvePreset.rampUp);
    }
  }

  /// Snaps all active smoothers to their initial evaluated values on gesture trigger
  void onGestureTriggered(float phase) {
    const float yBuf = curves[TVMModuleSlot.buffer].evaluate(phase);
    smoothBufferPos.snapTo(mapLinear(smoothBufferPos.target, smoothBufferPos.target, yBuf));
    smoothBufferPitch.snapTo(smoothBufferPitch.target);
    smoothGateWidth.snapTo(smoothGateWidth.target);
    smoothPanCenter.snapTo(smoothPanCenter.target);
    smoothPanWidth.snapTo(smoothPanWidth.target);
    smoothTapeSlowdown.snapTo(smoothTapeSlowdown.target);
    smoothFilterCutoff.snapTo(smoothFilterCutoff.target);
    smoothLofiBits.snapTo(smoothLofiBits.target);
    smoothLofiDownsample.snapTo(smoothLofiDownsample.target);
    smoothDistortDriveLow.snapTo(smoothDistortDriveLow.target);
    smoothDistortDriveHigh.snapTo(smoothDistortDriveHigh.target);
    smoothCombFreq.snapTo(smoothCombFreq.target);
    smoothChorusDepth.snapTo(smoothChorusDepth.target);
    smoothFlangerDepth.snapTo(smoothFlangerDepth.target);
    smoothPhaserCenter.snapTo(smoothPhaserCenter.target);
    smoothReverbSize.snapTo(smoothReverbSize.target);
    smoothDelayFeedback.snapTo(smoothDelayFeedback.target);
  }

  /// Accessor for module curve
  ref inout(TVMCurve) getCurve(TVMModuleSlot slot) inout return {
    return curves[cast(int) slot];
  }

  /// Accessor for module curve by integer index
  ref inout(TVMCurve) getCurve(int slot) inout return {
    if (slot < 0) slot = 0;
    if (slot >= NumTVMModuleSlots) slot = NumTVMModuleSlots - 1;
    return curves[slot];
  }

  /// Accessor for module curve pointer
  const(TVMCurve)* getCurvePtr(TVMModuleSlot slot) const pure return {
    return &curves[cast(int) slot];
  }
}

/// Per-parameter TVM curve configuration in BT Stutter Edit 2 (speed, direction, grid, lock).
struct TVMParamState {
  TVMCurve curve;
  float speedMultiplier = 1.0f; // 0.25x, 0.5x, 1.0x, 2.0x, 4.0x
  bool reversed = false;
  int gridResolution = 8;       // 2..32 divisions shown on curve editor grid
  bool lockRange = false;       // Lock start & end handles together

  @nogc nothrow pure @safe:

  void reset(TVMCurvePreset preset = TVMCurvePreset.rampUp) {
    curve.loadPreset(preset);
    speedMultiplier = 1.0f;
    reversed = false;
    gridResolution = 8;
    lockRange = false;
  }

  /// Evaluates curve accounting for speed multiplier (wrapping in [0,1]) and reverse toggle.
  float evaluateModulated(float gesturePhase) const {
    float p = (isNaN(gesturePhase) || isInfinity(gesturePhase)) ? 0.0f : gesturePhase;
    if (p < 0.0f) p = 0.0f;
    if (p > 1.0f) p = 1.0f;
    const float spd = (speedMultiplier > 0.05f && speedMultiplier <= 8.0f) ? speedMultiplier : 1.0f;
    float scaled = p * spd;
    // Wrap scaled phase within [0, 1] cleanly even at p == 1.0
    if (spd > 1.001f) {
      const int whole = cast(int) scaled;
      scaled = (p >= 1.0f) ? 1.0f : (scaled - cast(float) whole);
    } else if (scaled > 1.0f) {
      scaled = 1.0f;
    }
    if (reversed) scaled = 1.0f - scaled;
    return curve.evaluate(scaled);
  }
}

enum int MaxTVMParamsPerSlot = 6;
enum int NumExtendedTVMSlots = 16; // 0..13 match TVMModuleSlot, 14 = Highpass, 15 = Output

/// Fixed-size @nogc per-parameter TVM curve bank for BT Stutter Edit 2 modules.
struct ExtendedTVMBank {
  TVMParamState[MaxTVMParamsPerSlot][NumExtendedTVMSlots] states;

  @nogc nothrow pure @safe:

  void resetAll() {
    foreach (s; 0 .. NumExtendedTVMSlots) {
      foreach (p; 0 .. MaxTVMParamsPerSlot) {
        states[s][p].reset(TVMCurvePreset.rampUp);
      }
    }
  }

  ref inout(TVMParamState) getParamState(int slotIdx, int paramIdx) inout return {
    int s = slotIdx;
    if (s < 0) s = 0;
    if (s >= NumExtendedTVMSlots) s = NumExtendedTVMSlots - 1;
    int p = paramIdx;
    if (p < 0) p = 0;
    if (p >= MaxTVMParamsPerSlot) p = MaxTVMParamsPerSlot - 1;
    return states[s][p];
  }

  float evaluateParam(int slotIdx, int paramIdx, float gesturePhase) const {
    int s = (slotIdx < 0) ? 0 : ((slotIdx >= NumExtendedTVMSlots) ? NumExtendedTVMSlots - 1 : slotIdx);
    int p = (paramIdx < 0) ? 0 : ((paramIdx >= MaxTVMParamsPerSlot) ? MaxTVMParamsPerSlot - 1 : paramIdx);
    return states[s][p].evaluateModulated(gesturePhase);
  }
}

// =============================================================================
// Comprehensive Unit Tests
// =============================================================================

unittest {
  TVMCurve curve;

  // 1. Default state: linear ramp (0,0) -> (1,1)
  assert(curve.nodeCount() == 2);
  assert(curve.evaluate(0.0f) == 0.0f);
  assert(curve.evaluate(1.0f) == 1.0f);
  assert(fabs(curve.evaluate(0.5f) - 0.5f) < 1e-5f);

  // 2. Boundary clamping & NaN safety
  assert(curve.evaluate(-10.0f) == 0.0f);
  assert(curve.evaluate(10.0f) == 1.0f);
  assert(curve.evaluate(float.nan) == 0.0f);
  assert(curve.evaluate(-float.infinity) == 0.0f);
  assert(curve.evaluate(float.infinity) == 1.0f);

  // 3. Zero-divide protection on coincident nodes
  TVMCurve coincidentCurve;
  coincidentCurve.numNodes = 3;
  coincidentCurve.nodes[0] = CurveNode(0.0f, 0.2f, 0.0f, CurveType.linear);
  coincidentCurve.nodes[1] = CurveNode(0.5f, 0.8f, 0.0f, CurveType.linear);
  coincidentCurve.nodes[2] = CurveNode(0.5f, 0.8f, 0.0f, CurveType.linear); // dx = 0
  const float coinVal = coincidentCurve.evaluate(0.5f);
  assert(!isNaN(coinVal));
  assert(coinVal == 0.8f);

  // 4. Curve Types verification
  // Exponential
  TVMCurve expCurve;
  expCurve.nodes[0].type = CurveType.exponential;
  assert(fabs(expCurve.evaluate(0.5f) - 0.125f) < 1e-5f);

  // Logarithmic
  TVMCurve logCurve;
  logCurve.nodes[0].type = CurveType.logarithmic;
  assert(fabs(logCurve.evaluate(0.5f) - 0.875f) < 1e-5f);

  // S-Curve (smoothstep 3t^2 - 2t^3)
  TVMCurve sCurve;
  sCurve.nodes[0].type = CurveType.sCurve;
  assert(fabs(sCurve.evaluate(0.5f) - 0.5f) < 1e-5f);
  assert(sCurve.evaluate(0.1f) < 0.1f);
  assert(fabs(sCurve.evaluate(0.1f) - 0.028f) < 1e-4f);

  // Step Hold
  TVMCurve stepCurve;
  stepCurve.nodes[0].type = CurveType.stepHold;
  assert(stepCurve.evaluate(0.0f) == 0.0f);
  assert(stepCurve.evaluate(0.49f) == 0.0f);
  assert(stepCurve.evaluate(0.51f) == 1.0f);
  assert(stepCurve.evaluate(1.0f) == 1.0f);

  // Step Hold tension sensitivity and monotonicity
  stepCurve.nodes[0].tension = -1.0f; // Hold until end (thresh = 0.999)
  assert(stepCurve.evaluate(0.99f) == 0.0f);
  assert(stepCurve.evaluate(1.0f) == 1.0f);

  stepCurve.nodes[0].tension = 1.0f; // Immediate step (thresh = 0.001)
  assert(stepCurve.evaluate(0.0005f) == 0.0f);
  assert(stepCurve.evaluate(0.01f) == 1.0f);
  assert(stepCurve.evaluate(1.0f) == 1.0f);

  // Step Hold tension monotonicity across [-1.0, 1.0]
  for (float phase = 0.1f; phase <= 0.9f; phase += 0.1f) {
    float prevVal = -1.0f;
    for (float tens = -1.0f; tens <= 1.0f; tens += 0.05f) {
      stepCurve.nodes[0].tension = tens;
      const float val = stepCurve.evaluate(phase);
      assert(val >= prevVal - 1e-6f, "StepHold must be monotonic in tension");
      prevVal = val;
    }
  }

  // 5. Tension parameter [-1.0 .. +1.0] monotonicity
  TVMCurve tensionCurve;
  for (float tens = -1.0f; tens <= 1.0f; tens += 0.5f) {
    tensionCurve.nodes[0].tension = tens;
    float prevY = 0.0f;
    for (float p = 0.0f; p <= 1.0f; p += 0.05f) {
      const float y = tensionCurve.evaluate(p);
      assert(!isNaN(y));
      assert(y >= prevY - 1e-6f); // Monotonic
      assert(y >= 0.0f && y <= 1.0f);
      prevY = y;
    }
  }

  // 6. Verification of all 12 presets
  // Preset 0: Flat Low
  curve.loadPreset(0);
  assert(curve.evaluate(0.0f) == 0.0f);
  assert(curve.evaluate(0.5f) == 0.0f);
  assert(curve.evaluate(1.0f) == 0.0f);

  // Preset 1: Flat High
  curve.loadPreset(1);
  assert(curve.evaluate(0.0f) == 1.0f);
  assert(curve.evaluate(0.5f) == 1.0f);
  assert(curve.evaluate(1.0f) == 1.0f);

  // Preset 2: Ramp Up
  curve.loadPreset(2);
  assert(curve.evaluate(0.0f) == 0.0f);
  assert(curve.evaluate(1.0f) == 1.0f);
  assert(fabs(curve.evaluate(0.5f) - 0.5f) < 1e-5f);

  // Preset 3: Ramp Down
  curve.loadPreset(3);
  assert(curve.evaluate(0.0f) == 1.0f);
  assert(curve.evaluate(1.0f) == 0.0f);
  assert(fabs(curve.evaluate(0.5f) - 0.5f) < 1e-5f);

  // Preset 4: Exp Rise
  curve.loadPreset(4);
  assert(curve.evaluate(0.0f) == 0.0f);
  assert(curve.evaluate(1.0f) == 1.0f);
  assert(fabs(curve.evaluate(0.5f) - 0.125f) < 1e-5f);

  // Preset 5: Exp Fall
  curve.loadPreset(5);
  assert(curve.evaluate(0.0f) == 1.0f);
  assert(curve.evaluate(1.0f) == 0.0f);
  assert(fabs(curve.evaluate(0.5f) - 0.125f) < 1e-5f);

  // Preset 6: Sine 1x
  curve.loadPreset(6);
  assert(curve.evaluate(0.0f) == 0.0f);
  assert(fabs(curve.evaluate(0.5f) - 1.0f) < 1e-4f);
  assert(curve.evaluate(1.0f) == 0.0f);

  // Preset 7: Sine 2x
  curve.loadPreset(7);
  assert(curve.evaluate(0.0f) == 0.0f);
  assert(fabs(curve.evaluate(0.25f) - 1.0f) < 1e-4f);
  assert(fabs(curve.evaluate(0.5f) - 0.0f) < 1e-4f);
  assert(fabs(curve.evaluate(0.75f) - 1.0f) < 1e-4f);
  assert(curve.evaluate(1.0f) == 0.0f);

  // Preset 8: Step Up
  curve.loadPreset(8);
  assert(curve.evaluate(0.0f) == 0.0f);
  assert(curve.evaluate(0.49f) == 0.0f);
  assert(curve.evaluate(0.51f) == 1.0f);
  assert(curve.evaluate(1.0f) == 1.0f);

  // Preset 9: Step Down
  curve.loadPreset(9);
  assert(curve.evaluate(0.0f) == 1.0f);
  assert(curve.evaluate(0.49f) == 1.0f);
  assert(curve.evaluate(0.51f) == 0.0f);
  assert(curve.evaluate(1.0f) == 0.0f);

  // Preset 10: Spike
  curve.loadPreset(10);
  assert(curve.evaluate(0.0f) == 0.0f);
  assert(fabs(curve.evaluate(0.5f) - 1.0f) < 1e-4f);
  assert(curve.evaluate(1.0f) == 0.0f);

  // Preset 11: Chaos
  curve.loadPreset(11);
  for (float p = 0.0f; p <= 1.0f; p += 0.125f) {
    const float y = curve.evaluate(p);
    assert(!isNaN(y));
    assert(y >= 0.0f && y <= 1.0f);
  }

  // Also verify evaluatePreset analytical functions
  for (int id = 0; id < 12; ++id) {
    for (float p = -0.5f; p <= 1.5f; p += 0.05f) {
      const float y = evaluatePreset(id, p);
      assert(!isNaN(y));
      assert(y >= 0.0f && y <= 1.0f);
    }
  }

  // 7. Node manipulation (addNode, setNode, removeNode, sortNodes)
  curve.reset();
  assert(curve.addNode(0.25f, 0.7f, 0.2f, CurveType.exponential));
  assert(curve.addNode(0.75f, 0.3f, -0.4f, CurveType.sCurve));
  assert(curve.nodeCount() == 4);
  assert(curve.activeNodes()[1].x == 0.25f);
  assert(curve.activeNodes()[2].x == 0.75f);

  // Node editing
  assert(curve.setNode(1, 0.3f, 0.8f, 0.1f, CurveType.linear));
  assert(curve.activeNodes()[1].x == 0.3f);
  assert(curve.activeNodes()[1].y == 0.8f);

  // Node removal
  assert(curve.removeNode(1));
  assert(curve.nodeCount() == 3);
  assert(!curve.removeNode(0)); // cannot remove endpoint 0
  assert(!curve.removeNode(2)); // cannot remove endpoint last

  // Max nodes limit
  while (curve.nodeCount() < MaxCurveNodes) {
    assert(curve.addNode(0.5f, 0.5f));
  }
  assert(!curve.addNode(0.5f, 0.5f)); // exceeded capacity

  // 8. Parameter Modulator verification
  TVMModulator mod;
  mod.minVal = 200.0f;
  mod.maxVal = 8000.0f;
  mod.reset(200.0f);

  curve.loadPreset(2); // Ramp Up
  assert(mod.evaluateInstant(curve, 0.0f) == 200.0f);
  assert(mod.evaluateInstant(curve, 1.0f) == 8000.0f);
  assert(fabs(mod.evaluateInstant(curve, 0.5f) - 4100.0f) < 1e-4f);

  // Smoothing state advance
  const float sVal = mod.process(curve, 1.0f);
  assert(sVal > 200.0f && sVal < 8000.0f);

  // 9. Parameter Modulation Mapping Functions
  // mapLinear normal & inverted
  assert(mapLinear(200.0f, 8000.0f, 0.0f) == 200.0f);
  assert(mapLinear(200.0f, 8000.0f, 1.0f) == 8000.0f);
  assert(mapLinear(200.0f, 8000.0f, 0.5f) == 4100.0f);
  assert(mapLinear(8000.0f, 200.0f, 0.0f) == 8000.0f);
  assert(mapLinear(8000.0f, 200.0f, 1.0f) == 200.0f);
  assert(mapLinear(8000.0f, 200.0f, 0.5f) == 4100.0f);

  // mapLinear clamping
  assert(mapLinear(200.0f, 8000.0f, -0.5f) == 200.0f);
  assert(mapLinear(200.0f, 8000.0f, 1.5f) == 8000.0f);

  // mapLogarithmic
  const float logMid = mapLogarithmic(100.0f, 10000.0f, 0.5f);
  assert(fabs(logMid - 1000.0f) < 1.0f);
  // Boundary endpoint exactness
  assert(mapLogarithmic(20.0f, 20000.0f, 0.0f) == 20.0f);
  assert(mapLogarithmic(20.0f, 20000.0f, 1.0f) == 20000.0f);
  assert(mapLogarithmic(20000.0f, 20.0f, 0.0f) == 20000.0f);
  assert(mapLogarithmic(20000.0f, 20.0f, 1.0f) == 20.0f);
  assert(mapLogarithmic(20.0f, 20000.0f, -0.5f) == 20.0f);
  assert(mapLogarithmic(20.0f, 20000.0f, 1.5f) == 20000.0f);
  assert(mapLogarithmic(20.0f, 20000.0f, float.nan) == 20.0f);

  // evaluateModulatedParam bypass
  assert(evaluateModulatedParam(false, true, 500.0f, 200.0f, 8000.0f, 0.8f) == 500.0f);
  assert(evaluateModulatedParam(true, false, 500.0f, 200.0f, 8000.0f, 0.8f) == 500.0f);
  assert(evaluateModulatedParam(true, true, 500.0f, 400.0f, 400.0f, 0.8f) == 500.0f);
  assert(evaluateModulatedParam(true, true, 500.0f, 200.0f, 8000.0f, 1.0f) == 8000.0f);

  // 10. Single-pole ParameterSmoother verification
  ParameterSmoother sm;
  sm.reset(44_100.0, 0.0f, 0.003f); // 3 ms tau
  assert(sm.beta > 0.007f && sm.beta < 0.008f);

  sm.setTarget(100.0f);
  float prev = 0.0f;
  for (int i = 0; i < 132; ++i) {
    const float v = sm.nextSample();
    assert(v >= prev);
    prev = v;
  }
  assert(fabs(sm.value() - 63.2f) < 2.0f);

  for (int i = 0; i < 600; ++i) sm.nextSample();
  assert(sm.value() > 99.0f);

  for (int i = 0; i < 2000; ++i) sm.nextSample();
  assert(sm.value() == 100.0f);
  assert(sm.isSettled());

  sm.snapTo(42.0f);
  assert(sm.value() == 42.0f);

  // 11. TVMModulationEngine verification
  TVMModulationEngine engine;
  engine.reset(48_000.0);
  engine.onGestureTriggered(0.0f);
  assert(engine.getCurve(TVMModuleSlot.stutter).nodeCount() == 2);
  assert(engine.getCurve(TVMModuleSlot.buffer).nodeCount() == 2);
  assert(engine.getCurvePtr(TVMModuleSlot.gate) !is null);

  // 12. Real-time @nogc stress benchmark (100,000 evaluations)
  import core.memory : GC;
  const size_t gcBefore = GC.stats().usedSize;
  float accum = 0.0f;
  for (int i = 0; i < 100_000; ++i) {
    const float p = (i & 1023) * (1.0f / 1023.0f);
    accum += curve.evaluate(p);
  }
  const size_t gcAfter = GC.stats().usedSize;
  assert(!isNaN(accum));
  assert(gcBefore == gcAfter, "TVM operations caused GC allocation!");
}
