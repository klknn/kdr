import dplug.client;
import dplug.core;

import kdr.envelope;

struct DynamicEnvelope {
  @nogc nothrow:

  float at(float x) {

  }

  bool set(float x, float y) {
    assert(0 <= x && x <= 1);
    assert(0 <= y && y <= 1);

    if (length >= N) return false;

    xs[length] = x;
    ys[length] = y;
    ++length;

    // Sort arrays.
  }

  enum N = 8;
  int length;

  float bias = 0; // Normalized to [0.0 .. 1.0]
  float[N] xs;  // Sorted and normalized to [0.0 .. 1.0]
  float[N] ys;  // Normalized to [0.0 .. 1.0]
  // float[N + 1] interp;  // Interporation point between ys[i-1] and ys[i].
}

class ClientImpl : Client {
  public nothrow @nogc:

  this() {}

  override PluginInfo buildPluginInfo() {
    static immutable info = parsePluginInfo(import("plugin.json"));
    return info;
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
}

mixin(pluginEntryPoints!ClientImpl);
