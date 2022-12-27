module kdr.envtool.client;

import dplug.client;
import dplug.core;

import kdr.envelope;
import kdr.envtool.gui;
import kdr.logging;

/// Env tool client.
class EnvToolClient : Client {
  public nothrow @nogc:

  /// Ctor.
  this() {
    logInfo("Initialize %s", __FUNCTION__.ptr);

    _env = mallocNew!Envelope;
    _env.add(0.25, 1.0);
    _env.add(0.50, 0.5);
    _env.add(0.75, 0.5);

  }

  override IGraphics createGraphics() {
    if (!_gui) _gui = mallocNew!EnvToolGUI(_env);
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
  Envelope _env;
  EnvToolGUI _gui;
}
