module kdr.envtool.client;

import std.algorithm.comparison : clamp;

import dplug.math : vec2f;
import dplug.client : Client, IGraphics, LegalIO, LinearFloatParameter, Parameter, PluginInfo, TimeInfo;
import dplug.core;

import kdr.envelope : Envelope;
import kdr.envtool.gui : EnvToolGUI;
import kdr.envtool.params;
import kdr.filter;
import kdr.logging : logInfo;
import kdr.testing : benchmarkWithDefaultParams;

/// Env tool client.
class EnvToolClient : Client {
  public nothrow @nogc:

  /// Ctor.
  this() {
    super();
    logInfo("Initialize %s", __FUNCTION__.ptr);
  }

  override IGraphics createGraphics() {
    if (!_gui) _gui = mallocNew!EnvToolGUI(params);
    return _gui;
  }

  override Parameter[] buildParameters() {
    return buildEnvelopeParameters();
  }

  @safe
  override PluginInfo buildPluginInfo() {
    return PluginInfo.init;
  }

  override LegalIO[] buildLegalIO() {
    Vec!LegalIO io = makeVec!LegalIO();
    io ~= LegalIO(1, 1);
    io ~= LegalIO(2, 2);
    return io.releaseData();
  }

  @safe
  override int maxFramesInProcess() {
    return 32;
  }

  @safe
  override void reset(
      double sampleRate, int maxFrames, int numInputs, int numOutputs) {
    _sampleRate = sampleRate;
    foreach (ref Filter f; _filter) f.setSampleRate(sampleRate);
  }

  override void processAudio(
      const(float*)[] inputs, float*[] outputs, int frames, TimeInfo info) {
    const Destination dst = readParam!Destination(Params.destination);

    // Setup rate.
    const Envelope env = buildEnvelope(params);
    const double beatScale = rateValues[readParam!int(Params.rate)] * 4;
    const float depth = readParam!float(Params.depth);
    const double beatPerSample = info.tempo / 60 / _sampleRate;

    // Setup filter.
    const fkind = readParam!FilterKind(Params.filterKind);
    const fcutoff = readParam!float(Params.filterCutoff);
    const fres = readParam!float(Params.filterRes);
    foreach (ref f; _filter) f.setParams(fkind, fcutoff, fres);

    foreach (c; 0 .. inputs.length) {
      float offset = c == 0 ? 0 : readParam!float(Params.stereoOffset);
      foreach (t; 0 .. frames) {
        float output = inputs[c][t];

        if (info.hostIsPlaying) {
          // Do envelope modutation.
          const double beats = (info.timeInSamples + t) * beatPerSample;
          const float e = env.getY((beats / beatScale + offset) % 1.0);

          final switch (dst) {
            case Destination.volume:
              output *= e;
              break;
            case Destination.cutoff:
              _filter[c].setParams(fkind, e * fcutoff, fres);
              break;
            case Destination.pan:
              float pan = c == 0 ? e : 1.0 - e;
              output *= pan;
              break;
          }
        }

        output = _filter[c].apply(output);
        // mix dry and wet signals.
        outputs[c][t] = depth * output + (1.0 - depth) * inputs[c][t];
      }
    }
  }

 private:
  EnvToolGUI _gui;
  double _sampleRate;
  Filter[2] _filter;
}

unittest {
  benchmarkWithDefaultParams!EnvToolClient;
}

// When host is not playing and filter is none.
nothrow unittest {
  auto client = new EnvToolClient;
  TimeInfo info = {tempo: 120,  timeInSamples: -1, hostIsPlaying: false};
  float[] inputs = [1, 2, 3, 4];
  float[][] outputs = new float[][](2, inputs.length);
  client.processAudio([&inputs[0], &inputs[0]], [&outputs[0][0], &outputs[1][0]],
                      cast(int) inputs.length, info);
  // Identity outputs.
  assert(outputs[0] == inputs);
  assert(outputs[1] == inputs);
}
