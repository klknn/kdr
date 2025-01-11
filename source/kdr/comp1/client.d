module kdr.comp1.client;

import dplug.client;
import dplug.core;

import kdr.filter;
import kdr.logging : logInfo;
import kdr.comp1.gui : Comp1GUI;
import kdr.comp1.params;

/// Comp1 client.
/// See [root]/bin/comp1/comp1.d for its final class with plugin.json.
class Comp1Client : Client {
public nothrow @nogc:

  /// Ctor.
  this() {
    super();
    logInfo("Initialize %s", __FUNCTION__.ptr);
  }

  override IGraphics createGraphics() {
    if (!_gui) {
      _gui = mallocNew!Comp1GUI(params);
    }
    return _gui;
  }

  override Parameter[] buildParameters() {
    return buildParams();
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

  @safe
  override int maxFramesInProcess() {
    return 32;
  }

  override void reset(
    double sampleRate, int maxFrames, int numInputs, int numOutputs) {
    _numInputs = numInputs;
    _sampleRate = sampleRate;

    _lpf.resize(numInputs);
    foreach (ref f; _lpf) {
      f.setSampleRate(sampleRate);
    }
    _hpf.resize(numOutputs);
    foreach (ref f; _hpf) {
      f.setSampleRate(sampleRate);
    }
  }

  override void processAudio(
    const(float*)[] inputs, float*[] outputs, int frames, TimeInfo info) {
    foreach (c; 0 .. _numInputs) {
      _lpf[c].setParams(FilterKind.LP12, 88.3, 0);
      _hpf[c].setParams(FilterKind.HP12, 2500, 0);
      foreach (f; 0 .. frames) {
        float x = inputs[c][f];
        float l = _lpf[c].apply(x);
        float h = _hpf[c].apply(x);
        float m = x - l - h;

        outputs[c][f] = l + m + h;
      }
    }
  }

private:
  float _sampleRate;
  Comp1GUI _gui;
  Vec!Filter _lpf, _hpf;
  int _numInputs = 2;
}
