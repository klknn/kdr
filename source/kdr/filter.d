/**
   Synth2 filters.

   Filter coeffs are generated by tools/filter_coeff.py
   For transfer function definitions,
   See_also https://www.discodsp.net/VAFilterDesign_2.1.0.pdf

   Copyright: klknn 2021.
   License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module kdr.filter;

import mir.math : approxEqual, PI, SQRT2, fmax;

@nogc nothrow @safe pure:

/// Kinds of filter implentations.
enum FilterKind {
  HP6,
  HP12,
  BP12,
  LP6,
  LP12,
  /// Moog ladder filter
  LP24,
  /// TB303 diode-ladder filter
  LPDL,
}

/// String names of filter implementations.
static immutable filterNames = [__traits(allMembers, FilterKind)];

///
struct Filter {
  @nogc nothrow @safe pure:

  /// Applies filtering.
  /// Params:
  ///   input = input wave frame.
  /// Returns: filtered wave frame.
  float apply(float input) {
    // TODO: use ring buffer
    foreach_reverse (i; 1 .. nFIR) {
      x[i] = x[i - 1];
    }
    x[0] = input;

    float output = 0;
    foreach (i; 0 .. nFIR) {
      output += b[i] * x[i];
    }
    foreach (i; 0 .. nIIR) {
      output -= a[i] * y[i];
    }

    foreach_reverse (i; 1 .. nIIR) {
      y[i] = y[i - 1];
    }
    y[0] = output;
    return output;
  }

  void setSampleRate(float sampleRate) {
    sampleRate = sampleRate;
    x[] = 0f;
    y[] = 0f;
  }

  /// Set filter parameters.
  /// Params:
  ///   kind = filter type.
  ///   freq = cutoff frequency [0, 1].
  ///   q = resonance, quality factor [0, 1].
  void setParams(FilterKind kind, float freq, float q) {
    if (this.kind != kind) {
      x[] = 0f;
      y[] = 0f;
    }
    this.kind = kind;

    // To prevent the filter gets unstable.
    float Q;
    if (kind == FilterKind.LPDL) {
      // unstable at Q = 16 (see VAFD sec 5.10)
      Q = q * 15;
      freq += 0.005;  // to prevent self osc.
    }
    else if (kind == FilterKind.LP24) {
      // unstable at Q = 4 (see VAFD sec 5.1, eq 5.2)
      Q = q * 3;
      freq += 0.005;  // to prevent self osc.
    }
    else {
      Q = q * 5 + 1 / SQRT2;
    }
    const T = 1 / sampleRate;
    const w0 = 2 * PI * freq * sampleRate;
    assert(T != float.nan);
    assert(w0 != float.nan);
    final switch (kind) {
      mixin(import("filter_coeff.d"));
    }
  }

 private:
  FilterKind kind = FilterKind.LP12;
  float sampleRate = 44_100;
  // filter and prev inputs
  float[5] b, x;
  // filter and prev outputs
  float[4] a, y;

  int nFIR = 3;
  int nIIR = 2;
}

unittest {
  Filter f;
  f.setSampleRate(20);
  f.setParams(FilterKind.LP12, 5, 2);

  // with padding
  auto y0 = f.apply(0.1);
  assert(approxEqual(y0, f.b[0] * 0.1));

  auto y1 = f.apply(0.2);
  assert(approxEqual(y1, f.b[0] * 0.2 + f.b[1] * 0.1 - f.a[0] * y0));

  auto y2 = f.apply(0.3);
  assert(approxEqual(y2,
                     f.b[0] * 0.3 + f.b[1] * 0.2 + f.b[0] * 0.1
                     -f.a[0] * y1 - f.a[1] * y0));

  // without padding
  auto y3 = f.apply(0.4);
  assert(approxEqual(y3,
                     f.b[0] * 0.4 + f.b[1] * 0.3 + f.b[0] * 0.2
                     -f.a[0] * y2 - f.a[1] * y1));
}

/// Single frame delayed all pass filter.
struct AllPassFilter {
  @nogc nothrow pure @safe:

  float g = 0.5, py = 0, px = 0;

  void setSampleRate(float) {
    py = 0;
    px = 0;
  }

  float apply(float x) {
    const y = g * x + px - g * py;
    px = x;
    py = y;
    return y;
  }
}