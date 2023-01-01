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

  override PluginInfo buildPluginInfo() {
    return PluginInfo.init;
  }

  override LegalIO[] buildLegalIO() {
    Vec!LegalIO io = makeVec!LegalIO();
    io ~= LegalIO(1, 1);
    io ~= LegalIO(2, 2);
    return io.releaseData();
  }

  override int maxFramesInProcess() {
    return 32;
  }

  override void reset(
      double sampleRate, int maxFrames, int numInputs, int numOutputs) {
    _sampleRate = sampleRate;
    foreach (ref f; _filter) f.setSampleRate(sampleRate);
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
        const double beats = (info.timeInSamples + t) * beatPerSample;
        float e = env.getY((beats / beatScale + offset) % 1.0);
        final switch (dst) {
          case Destination.volume:
            outputs[c][t] = e * inputs[c][t];
            break;
          case Destination.cutoff:
            _filter[c].setParams(fkind, e * fcutoff, fres);
            outputs[c][t] = inputs[c][t];
            break;
          case Destination.pan:
            float pan = c == 0 ? e : 1.0 - e;
            outputs[c][t] = pan * inputs[c][t];
            break;
        }
        outputs[c][t] = _filter[c].apply(outputs[c][t]);
        // mix dry and wet signals.
        outputs[c][t] = depth * outputs[c][t] + (1.0 - depth) * inputs[c][t];
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
