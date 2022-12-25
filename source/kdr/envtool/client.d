module kdr.envtool.client;

import dplug.client;
import dplug.core;

import kdr.envelope;
import kdr.envtool.gui;
import kdr.logging;

/// Env tool client.
class EnvToolClient : Client {
  public nothrow @nogc:

  this() {
    logInfo("Initialize %s", __FUNCTION__.ptr);
  }

  override IGraphics createGraphics() {
    if (!_gui) _gui = mallocNew!EnvToolGUI;
    return _gui;
  }

  override LegalIO[] buildLegalIO() {
    Vec!LegalIO io = makeVec!LegalIO();
    io ~= LegalIO(1, 1);
    io ~= LegalIO(2, 2);
    return io.releaseData();
  }

  override int maxFramesInProcess() { return 32; }

  override void reset(double sampleRate, int maxFrames, int numInputs, int numOutputs) {
  }

  override void processAudio(const(float*)[] inputs, float*[] outputs, int frames, TimeInfo info) {
  }

private:
  DynamicEnvelope env;
  EnvToolGUI _gui;
}
