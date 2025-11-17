module kdr.fm6.client;

import dplug.client;
import dplug.core;
import kdr.fm6.gui;

///
class Fm6Client : Client {
public:
@nogc:
nothrow:
  override IGraphics createGraphics() {
    if (!_gui)
      _gui = mallocNew!Fm6GUI(params);
    return _gui;
  }

  override Parameter[] buildParameters() {
    return [];
  }

  @safe
  override PluginInfo buildPluginInfo() {
    return PluginInfo.init;
  }

  override LegalIO[] buildLegalIO() {
    Vec!LegalIO io = makeVec!LegalIO();
    io ~= LegalIO(0, 1);
    io ~= LegalIO(0, 2);
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
  }

  override void processAudio(
    const(float*)[] inputs, float*[] outputs, int frames, TimeInfo info) {
  }

private:
  Fm6GUI _gui;
  double _sampleRate;
}
