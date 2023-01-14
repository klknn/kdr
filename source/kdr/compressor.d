/// Compressor module.
///
/// Reference:
/// [1] Digital Dynamic Range Compressor Design — A Tutorial and Analysis
/// https://www.eecs.qmul.ac.uk/%7Ejosh/documents/2012/GiannoulisMassbergReiss-dynamicrangecompression-JAES2012.pdf
module kdr.compressor;

import std.math : isClose, log1p;

import mir.math : exp, sqrt;

import kdr.ringbuffer;

struct RmsSlidingWindow {
  @nogc nothrow:

  this(int frames) {
    _buffer.recalloc(frames);
  }

  void clear() {
    _buffer.clear();
  }

  float opCall(float x) {
    _buffer.enqueue(x * x);
    float sum = 0;
    foreach (sq; _buffer) {
      sum +=  sq;
    }
    return sqrt(sum / _buffer.length);
  }

 private:
  RingBuffer!float _buffer;
}

unittest {
  RmsSlidingWindow rms = 2;
  assert(rms(1) == sqrt(1f / 2));
  assert(rms(2) == sqrt((1f + 4f) / 2));
  assert(rms(3) == sqrt((4f + 9f) / 2));
}

enum Knee {
  /// Hard knee without control vars.
  hard,
  /// Square curve knee with a width var.
  square,
  /// Soft-plus curve knee with a slope var.
  softplus,
}

struct GainCompressor {
  @nogc nothrow:

  Knee kneeKind = Knee.softplus;
  float kneeFactor = 0.5;  // Assume in [0, 1]. Smaller gets harder.
  float upwardRatio = 1;
  float downwardRatio = 1;
  float upwardThreshold = 0;
  float downwardThreshold = float.max;
  float eps = 1e-6;

  float compress(float x) const pure {
    final switch (kneeKind) {
      case Knee.hard: return compressHardUp(compressHardDown(x));
      case Knee.square: return compressSquareUp(compressSquareDown(x));
      case Knee.softplus: return compressSoftPlusUp(compressSoftPlusDown(x));
    }
  }

  float compressHardDown(float x) const pure {
    if (x > downwardThreshold) {
      return (x - downwardThreshold) / downwardRatio + downwardThreshold;
    }
    return x;
  }

  float compressHardUp(float x) const pure {
    if (x < upwardThreshold) {
      return (x - upwardThreshold) / upwardRatio + upwardThreshold;
    }
    return x;
  }

  /// Defined as Eq. (4) in [1].
  /// It can be derived by solving these diff eqs:
  /// dy/dx = 1 if x < t - w/2
  ///       = r if t + w/2
  ///       = 1 + (r - 1) / w * (x - t + w/2) otherwise.
  /// The last eq is a linear interp btw 1st and 2nd eqs,
  /// where w is the width hyperparameter of the interp.
  float compressSquareDown(float x) const pure {
    float r = downwardRatio;
    float t = downwardThreshold;
    float w = kneeFactor * 50;
    if (x < t - w / 2) return x;
    if (t + w / 2 < x) return r * (x - t) + t;
    return x + (r - 1) * (x - t + w / 2) ^^ 2 / (2 * w + eps);
  }

  /// The upward version of compressSquareDown.
  /// It can be derived by solving these diff eqs:
  /// dy/dx = r if x < t - w/2
  ///       = 1 if t + w/2
  ///       = r + (1 - r) / w * (x - t + w/2) otherwise.
  /// The last eq is a linear interp btw 1st and 2nd eqs,
  /// where w is the width hyperparameter of the interp.
  float compressSquareUp(float x) const pure {
    float r = upwardRatio;
    float t = upwardThreshold;
    float w = kneeFactor * 50;
    if (x < t - w / 2) return r * (x - t) + t;
    if (t + w / 2 < x) return x;
    return r * x + (1 - r) * (x - t + w/2) ^^ 2 / (2 * w + eps) + (1 - r) * t;
  }

  /// This compressor has this smooth derivative around threshold t:
  /// y' = (r - 1) * sigmoid(a * (x - t)) + 1,
  /// Therefore, its output function is linear x + softplus at t.
  float compressSoftPlusDown(float x) const pure {
    float r = downwardRatio;
    float t = downwardThreshold;
    float a = (1 - kneeFactor) * 1000 + 0.1;
    float c = (1 - r) / a * log1p(exp(-a * t));
    return (r - 1) / a * log1p(exp(a * (x - t))) + x + c;
  }

  /// This compressor has this smooth derivative around threshold t:
  /// y' = (1 - r) * sigmoid(a * (x - t)) + r,
  /// Therefore, its output function is linear x + softplus at t.
  float compressSoftPlusUp(float x) const pure {
    float r = upwardRatio;
    float t = upwardThreshold;
    float a = (1 - kneeFactor) * 1000 + 0.1;
    float c = (1 - r) * (t - log1p(exp(-a * t)) / a);
    return (1 - r) / a * log1p(exp(a * (x - t))) + r * x + c;
  }
}

// Check hard knee downward approx.
unittest {
  GainCompressor comp;
  comp.kneeFactor = 0;
  comp.downwardRatio = 0.1;
  comp.downwardThreshold = 60;
  assert(isClose(comp.compressHardDown(60), 60));
  assert(isClose(comp.compressSquareDown(60), 60));
  assert(isClose(comp.compressSoftPlusDown(60), 60));
}

// Check softknee smoothness.
unittest {
  GainCompressor comp;
  enum eps = 1e-6;
  comp.kneeFactor = eps;
  comp.downwardRatio = 0.1;
  comp.downwardThreshold = 60;
  assert(comp.compressSquareDown(60) < 60);
  assert(comp.compressSoftPlusDown(60) < 60);
  assert(isClose(comp.compressSquareDown(60 + eps), 60));
  assert(isClose(comp.compressSoftPlusDown(60 + eps), 60));
}

// Check hard knee upward approx.
unittest {
  GainCompressor comp;
  comp.kneeFactor = 0;
  comp.upwardRatio = 0.1;
  comp.upwardThreshold = 60;
  assert(isClose(comp.compressHardUp(60), 60));
  assert(isClose(comp.compressSquareUp(60), 60));
  assert(isClose(comp.compressSoftPlusUp(60), 60));
}

// Check softknee smoothness.
unittest {
  GainCompressor comp;
  enum eps = 1e-6;
  comp.kneeFactor = eps;
  comp.upwardRatio = 0.1;
  comp.upwardThreshold = 60;
  assert(comp.compressSquareUp(60) > 60);
  assert(comp.compressSoftPlusUp(60) > 60);
  assert(isClose(comp.compressSquareUp(60 + eps), 60));
  assert(isClose(comp.compressSoftPlusUp(60 + eps), 60));
}
