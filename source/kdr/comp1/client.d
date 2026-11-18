module kdr.comp1.client;

import dplug.client;
import dplug.core;
import dplug.core.math : convertDecibelToLinearGain;

import kdr.compressor;
import kdr.filter;
import kdr.logging : logInfo;
import kdr.comp1.gui : Comp1GUI;
import kdr.comp1.params;

enum Band {
  H,
  M,
  L,
}

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

    foreach (ref c; _comp) {
      c.setSampleRate(sampleRate, numInputs);
    }
    _comp[Band.H].attackMS = 13.5;
    _comp[Band.H].releaseMS = 132;
    _comp[Band.H].downwardRatio = 20;
    _comp[Band.H].upwardRatio = 4.17;

    _comp[Band.M].attackMS = 22.4;
    _comp[Band.M].releaseMS = 282;
    _comp[Band.M].downwardRatio = 66.7;
    _comp[Band.M].upwardRatio = 4.17;

    _comp[Band.L].attackMS = 47.8;
    _comp[Band.L].releaseMS = 282;
    _comp[Band.L].downwardRatio = 66.7;
    _comp[Band.L].upwardRatio = 4.17;
  }

  override void processAudio(
    const(float*)[] inputs, float*[] outputs, int frames, TimeInfo info) {
    float inGain = convertDecibelToLinearGain(this.gain(Params.inGain) + 5.2);
    float outGain = convertDecibelToLinearGain(this.gain(Params.outGain));
    float outGainH = outGain * convertDecibelToLinearGain(10.3);
    float outGainM = outGain * convertDecibelToLinearGain(5.7);
    float outGainL = outGain * convertDecibelToLinearGain(10.3);

    _comp[Band.H].downwardThreshold = this.gain(Params.aboveThresholdH);
    _comp[Band.H].upwardThreshold = this.gain(Params.belowThresholdH);
    _comp[Band.M].downwardThreshold = this.gain(Params.aboveThresholdM);
    _comp[Band.M].upwardThreshold = this.gain(Params.belowThresholdM);
    _comp[Band.L].downwardThreshold = this.gain(Params.aboveThresholdL);
    _comp[Band.L].upwardThreshold = this.gain(Params.belowThresholdL);

    foreach (c; 0 .. _numInputs) {
      _lpf[c].setParams(FilterKind.LP12, 88.3, 0);
      _hpf[c].setParams(FilterKind.HP12, 2500, 0);
    }

    foreach (f; 0 .. frames) {
      float x0 = inputs[0][f] * inGain;
      float x1 = inputs[1][f] * inGain;

      float l0 = _lpf[0].apply(x0);
      float l1 = _lpf[1].apply(x1);

      float h0 = _hpf[0].apply(x0);
      float h1 = _hpf[1].apply(x1);

      float m0 = x0 - l0 - h0;
      float m1 = x1 - l1 - h1;

      float gl = _comp[Band.L].gain(l0, l1) * outGainL;
      float gm = _comp[Band.M].gain(m0, m1) * outGainM;
      float gh = _comp[Band.H].gain(h0, h1) * outGainH;

      outputs[0][f] = gl * l0 + gm * m0 + gh * h0;
      outputs[1][f] = gl * l1 + gm * m1 + gh * h1;
    }
  }

private:

  double gain(Params pid) {
    return convertDecibelToLinearGain((cast(GainParameter) this.param(pid)).value);
  }

  float _sampleRate;
  Comp1GUI _gui;
  Vec!Filter _lpf, _hpf;
  Comp[3] _comp;
  int _numInputs = 2;
}
