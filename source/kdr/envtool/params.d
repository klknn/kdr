module kdr.envtool.params;

import dplug.math : vec2f;
import dplug.core;
import dplug.client;

import kdr.envelope;

// import kdr.params : RegisterBuilder;

// @RegisterBuilder

/// Parameter for EnvToolClient.
enum Params {
  beatScale,
  depth,
  stereoOffset,
  // volumeMod,
  // filterMod,
  // filterMode,
  // filterCutoff,
  // filterRes,
  envelope,
}

immutable string[] beatScaleLabels = ["1/64", "1/48", "1/32", "1/24", "1/16", "1/12", "1/8", "1/6", "1/4"];
immutable double[] beatScaleValues = [1./64, 1./48, 1./32, 1./24, 1./16, 1./12, 1./8, 1./6, 1./4];
static assert(beatScaleLabels.length == beatScaleValues.length);

@nogc nothrow
Parameter[] buildEnvelopeParameters() {
  Vec!Parameter params;

  int n = 0;
  // General config.
  params.pushBack(mallocNew!EnumParameter(n++, "beatScale", beatScaleLabels,
                                          cast(int) beatScaleValues.length-1));
  params.pushBack(mallocNew!LinearFloatParameter(n++, "depth", "", 0.0, 1.0, 1.0));
  params.pushBack(mallocNew!LinearFloatParameter(n++, "stereoOffset", "", 0.0, 1.0, 0.0));

  // Envelope config.
  params.pushBack(mallocNew!LinearFloatParameter(n++, "bias", "", 0, 1, 0));
  // -2 for begin/end points.
  foreach (i; 0 .. Envelope.MAX_POINTS - 2) {
    if (i == 0) {
      params.pushBack(mallocNew!BoolParameter(n++, "enabled", true));
      params.pushBack(mallocNew!LinearFloatParameter(n++, "x", "", 0, 1, 0.5));
      params.pushBack(mallocNew!LinearFloatParameter(n++, "y", "", 0, 1, 1.0));
      params.pushBack(mallocNew!BoolParameter(n++, "curve", false));
      continue;
    }
    params.pushBack(mallocNew!BoolParameter(n++, "enabled", false));
    params.pushBack(mallocNew!LinearFloatParameter(n++, "x", "", 0, 1, 0));
    params.pushBack(mallocNew!LinearFloatParameter(n++, "y", "", 0, 1, 0));
    params.pushBack(mallocNew!BoolParameter(n++, "curve", false));
  }
  return params.releaseData();
}

@nogc nothrow
LinearFloatParameter envelopeBiasParam(Parameter[] params) {
  return cast(LinearFloatParameter) params[0];
}

struct EnvelopePointParams {
  BoolParameter enabled;
  LinearFloatParameter x, y;
  BoolParameter curve;
}

@nogc nothrow
EnvelopePointParams envelopePointParamsAt(int i, Parameter[] params) {
  assert(i > 0);
  assert(i + 1 < Envelope.MAX_POINTS);
  // +1 for bias.
  int n = 1 + (i - 1) * 4; // cast(int) EnvelopePointParams.tupleof.length;
  BoolParameter enabled = cast(BoolParameter) params[n++];
  LinearFloatParameter x = cast(LinearFloatParameter) params[n++];
  LinearFloatParameter y = cast(LinearFloatParameter) params[n++];
  BoolParameter curve = cast(BoolParameter) params[n++];
  return EnvelopePointParams(enabled, x, y, curve);
}

@nogc nothrow
Envelope buildEnvelope(Parameter[] params) {
  Envelope ret;
  LinearFloatParameter bias = envelopeBiasParam(params);
  ret[0].y = bias.value;
  ret[$-1].y = bias.value;

  // 1 .. $-1 for skipping begin/end points.
  foreach (i; 1 .. Envelope.MAX_POINTS - 1) {
    EnvelopePointParams point = envelopePointParamsAt(i, params);
    if (point.enabled.value) {
      ret.add(Envelope.Point(vec2f(point.x.value, point.y.value), point.curve.value));
    }
  }
  return ret;
}

// Envelope initializeEnvelope()
