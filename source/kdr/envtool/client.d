module kdr.envtool.client;

import std.algorithm.comparison : clamp;

import dplug.math : vec2f;
import dplug.client : Client, IGraphics, LegalIO, LinearFloatParameter, Parameter, TimeInfo;
import dplug.core;

import kdr.envelope : Envelope;
import kdr.envtool.gui : EnvToolGUI;
import kdr.envtool.params;
import kdr.logging : logInfo;

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
  }

  override void processAudio(
      const(float*)[] inputs, float*[] outputs, int frames, TimeInfo info) {
    const Envelope env = buildEnvelope(params[Params.envelope .. $]);
    const double beatScale = rateValues[readParam!int(Params.rate)] * 4;
    const float depth = readParam!float(Params.depth);
    const double beatPerSample = info.tempo / 60 / _sampleRate;
    foreach (c; 0 .. inputs.length) {
      float offset = c == 0 ? 0 : readParam!float(Params.stereoOffset);
      foreach (t; 0 .. frames) {
        const double beats = (info.timeInSamples + t) * beatPerSample;
        const float e = env.getY((beats / beatScale + offset) % 1.0);
        outputs[c][t] = (depth * e + 1.0 - depth) * inputs[c][t];
      }
    }
  }

 private:
  EnvToolGUI _gui;
  double _sampleRate;
}
