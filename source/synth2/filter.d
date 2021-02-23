/// Filter coeffs are generated by tools/filter_coeff.py
///
/// For transfer function definitions,
/// See_also https://www.discodsp.net/VAFilterDesign_2.1.0.pdf
module synth2.filter;

import mir.math : approxEqual, PI, SQRT2;

@nogc nothrow @safe pure:

enum FilterKind {
  HP6,
  HP12,
  BP12,
  LP6,
  LP12,
  LP24,
  LPDL,
}

static immutable filterNames = [__traits(allMembers, FilterKind)];

struct Filter {
  @nogc nothrow @safe pure:
  
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

  void setParams(FilterKind kind, float freqPercent, float q) {
    if (this.kind != kind) {
      x[] = 0f;
      y[] = 0f;
    }
    this.kind = kind;
    float Q = kind == FilterKind.LPDL
              ? q * 0.17
              : q / 10 + 1 / SQRT2;
    float T = 1 / sampleRate;
    float w0 = 2 * PI * freqPercent / 100f * sampleRate;
    float den = Q * T * T * w0 * w0 + 4 * Q + 2 * T * w0;
    final switch (kind) {
      mixin(import("filter_coeff.d"));
    }
  }

 private:
  FilterKind kind = FilterKind.LP12;
  float sampleRate = 44100;
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
