module kdr.envtool.params;

import dplug.math : vec2f;
import dplug.core;
import dplug.client;

import kdr.envelope;
import kdr.filter;

/// Envelope mod destination.
enum Destination {
  volume,
  pan,
  filterCutoff,
}

/// String names of destinations.
static immutable destinationNames = [__traits(allMembers, Destination)];


/// Parameter for EnvToolClient.
enum Params {
  envelope,
  bias = 4 * (Envelope.MAX_POINTS - 2),  // -2 as begin/end uses bias.
  rate,
  depth,
  stereoOffset,
  destination,
  filterKind,
  filterCutoff,
  filterRes,
}

/// Used by the "rate" param.
immutable string[] rateLabels = ["1/64", "1/48", "1/32", "1/24", "1/16", "1/12", "1/8", "1/6", "1/4", "1/3", "1/2", "1/1", "2/1", "4/1", "8/1"];
/// ditto.
immutable double[] rateValues = [1./64, 1./48, 1./32, 1./24, 1./16, 1./12, 1./8, 1./6, 1./4, 1./3., 1./2, 1., 2., 4., 8.];
static assert(rateLabels.length == rateValues.length);

/// Returns:
///   Envelope parameters.
@nogc nothrow
Parameter[] buildEnvelopeParameters() {
  Vec!Parameter params;

  int n = 0;
  // Envelope config.
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
  assert(n == Params.bias);
  params.pushBack(mallocNew!LinearFloatParameter(n++, "bias", "", 0, 1, 0));

  // General config.
  assert(n == Params.rate);
  params.pushBack(mallocNew!EnumParameter(n++, "rate", rateLabels, 8));
  assert(n == Params.depth);
  params.pushBack(mallocNew!LinearFloatParameter(n++, "depth", "", 0.0, 1.0, 1.0));
  assert(n == Params.stereoOffset);
  params.pushBack(mallocNew!LinearFloatParameter(n++, "stereoOffset", "", -1, 1, 0.0));
  assert(n == Params.destination);
  params.pushBack(mallocNew!EnumParameter(n++, "destination", destinationNames, Destination.volume));
  assert(n == Params.filterKind);
  params.pushBack(mallocNew!EnumParameter(n++, "filterKind", filterNames, FilterKind.none));
  assert(n == Params.filterCutoff);
  params.pushBack(mallocNew!LinearFloatParameter(n++, "filterCutoff", "",  0, 1, 0.5));
  assert(n == Params.filterRes);
  params.pushBack(mallocNew!LinearFloatParameter(n++, "filterRes", "",  0, 1, 0.5));

  return params.releaseData();
}

/// Params:
///   params = type-erased parameters.
/// Returns:
///   a bias parameter of envelope.
@nogc nothrow
LinearFloatParameter envelopeBiasParam(Parameter[] params) {
  return cast(LinearFloatParameter) params[Params.bias];
}

/// Value represents envelope point parameters. See also kdr.envelope.Envelope.Point.
struct EnvelopePointParams {
  ///
  BoolParameter enabled;
  ///
  LinearFloatParameter x, y;
  ///
  BoolParameter curve;
}

/// Params:
///   i = index of querying envelope point.
///   params = type-erased parameters, which starts with the bias parameter.
/// Returns:
///   EnvelopePointParams at the given index i in mixed params.
@nogc nothrow
EnvelopePointParams envelopePointParamsAt(int i, Parameter[] params) {
  assert(i > 0);
  assert(i + 1 < Envelope.MAX_POINTS);
  int n = (i - 1) * 4; // cast(int) EnvelopePointParams.tupleof.length;
  BoolParameter enabled = cast(BoolParameter) params[n++];
  LinearFloatParameter x = cast(LinearFloatParameter) params[n++];
  LinearFloatParameter y = cast(LinearFloatParameter) params[n++];
  BoolParameter curve = cast(BoolParameter) params[n++];
  return EnvelopePointParams(enabled, x, y, curve);
}

/// Params:
///   params = type-erased parameters, which starts with the bias parameter.
/// Returns:
///   Instantiated Envelope object.
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
