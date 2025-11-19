module kdr.fm6.client;

import core.stdc.stdio;
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
    Vec!Parameter ret;
    int opIdx = 0;
    foreach (x; 0 .. numOps) {
      foreach (y; 0 .. numOps) {
        char[] name = mallocSlice!char(10);
        int len = sprintf(name.ptr, "op%d/%d", x, y);
        ret.pushBack(mallocNew!LinearFloatParameter(opIdx, cast(string) name[0 .. len], "", -1, 1, 0));
        ++opIdx;
      }
    }
    return ret.releaseData;
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

unittest {
  auto client = new Fm6Client;
  auto gui = new Fm6GUI(client.params);
  gui.reflow();

  int w = 100, h = 100;
  auto dif = new OwnedImage!RGBA(w, h);
  auto dep = new OwnedImage!L16(w, h);
  auto mat = new OwnedImage!RGBA(w, h);
  gui.onDrawPBR(toRef(dif), toRef(dep), toRef(mat), [rectangle(0, 0, w, h)]);
  assert(false);
}
