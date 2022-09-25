module kdr.hibiki.client;

import std.math;
import dplug.core;
import dplug.client;
import kdr.params;

/// Plugin parameter IDs.
@RegisterBuilder!ParamBuilder
enum Params {
  onOff,
}

/// Plugin parameter definitions.
struct ParamBuilder {
  /// Returns: bool on/off switch.
  static onOff() {
    return mallocNew!BoolParameter(Params.onOff, "onOff", true);
  }
}


/// Reverb effect client.
class HibikiClient : Client {
public:
  nothrow:
  @nogc:

  /// ctor.
  this()
  {
  }

  override PluginInfo buildPluginInfo()
  {
    return PluginInfo.init;
  }

  override Parameter[] buildParameters()
  {
    return buildParams!Params;
  }

  override LegalIO[] buildLegalIO()
  {
    auto io = makeVec!LegalIO();
    io ~= LegalIO(2, 2);
    return io.releaseData();
  }

  override void reset(double sampleRate, int maxFrames, int numInputs, int numOutputs) nothrow @nogc
  {
  }

  override void processAudio(const(float*)[] inputs, float*[]outputs, int frames, TimeInfo info) nothrow @nogc
  {
    if (readParam!bool(Params.onOff)) {
      outputs[0][0..frames] = (inputs[0][0..frames] + inputs[1][0..frames]) * SQRT1_2;
      outputs[1][0..frames] = (inputs[0][0..frames] - inputs[1][0..frames]) * SQRT1_2;
    } else {
      outputs[0][0..frames] = inputs[0][0..frames];
      outputs[1][0..frames] = inputs[1][0..frames];
    }
  }
}
