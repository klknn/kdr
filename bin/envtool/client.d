// -*- mode: d; c-basic-offset: 2 -*-
import dplug.client;
import dplug.core;

import kdr.logging;

struct DynamicEnvelope {
 public:
  @nogc nothrow:

  float getY(float x) {
    assert(0 <= x && x <= 1);
    const nextIdx = newIndex(x);
    if (nextIdx == length) return ys[length - 1];
    return linmap(x, xs[nextIdx-1], xs[nextIdx], ys[nextIdx-1], ys[nextIdx]);
  }

  bool setXY(float x, float y) {
    assert(0 <= x && x <= 1);
    assert(0 <= y && y <= 1);

    // Cannot add x anymore.
    if (length >= N) return false;

    const idx = newIndex(x);
    xs[idx + 1 .. length + 1] = xs[idx .. length];
    ys[idx + 1 .. length + 1] = ys[idx .. length];
    xs[idx] = x;
    ys[idx] = y;
    ++length;
    return true;
  }

 private:
  // Returns a new index if newx will be added to xs.
  size_t newIndex(float newx) pure const {
    foreach (i, x; xs[0 .. length]) {
      if (newx < x) {
        return i;
      }
    }
    return length;
  }

  enum N = 8;
  int length = 2;
  float[N] xs = [0, 1];  // Sorted and normalized to [0.0 .. 1.0]
  float[N] ys = [0, 0];  // Normalized to [0.0 .. 1.0]
  // float[N + 1] interp;  // Interporation point between ys[i-1] and ys[i].
}

unittest {
  DynamicEnvelope env;
  logInfo("newIndex %d", env.newIndex(1.0));
  logInfo("Y %f", env.getY(1.0));
  // Initial start/end points.
  assert(env.getY(0.0) == 0.0);
  assert(env.getY(1.0) == 0.0);

  // Check interp.
  assert(env.getY(0.25) == 0.0);
  assert(env.getY(0.75) == 0.0);

  // Add a new point.
  assert(env.setXY(0.5, 1.0));
  assert(env.getY(0.5) == 1.0);

  // The added point changes the interp.
  assert(env.getY(0.25) == 0.5);
  assert(env.getY(0.75) == 0.5);
}

class ClientImpl : Client {
  public nothrow @nogc:

  this() {
    // env = mallocNew!DynamicEnvelope();
  }

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
