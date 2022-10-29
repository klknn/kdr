/// Freeverb client based on faust implementation: https://github.com/grame-cncm/faustlibraries/blob/4cd48b91f1170498c1cf5d8ee5b87cda6cd797df/old/effect.lib#L1075
import std.algorithm;
import dplug.core;
import dplug.client;
import kdr.ringbuffer;

struct AllPassFilter {
  @nogc nothrow pure
  float apply(const float x) {
    const float dx = _buffer.front;
    _buffer.enqueue(x + _coeff * dx);
    return dx - _coeff * (x + _coeff * dx);
  }

private:
  float _coeff = 0.5;
  RingBuffer!float _buffer;
  alias _buffer this;
}

struct CombFilter {
  @nogc nothrow pure
  float apply(const float x, const float damp, const float feedback) {
    const float dx = _buffer.front;
    _last = dx * (1f - damp) + _last * damp;
    _buffer.enqueue(x + feedback * _last);
    return dx;
  }

private:
  float _last = 0;
  RingBuffer!float _buffer;
  alias _buffer this;
}

class FreeverbClient : Client {
  public nothrow @nogc:

  this() {}

  override PluginInfo buildPluginInfo() {
    static immutable info = parsePluginInfo(import("plugin.json"));
    return info;
  }

  enum Params { damp, roomSize, wet, width, freeze }

  override Parameter[] buildParameters() {
    Vec!Parameter params = makeVec!Parameter();
    params ~= mallocNew!LinearFloatParameter(Params.damp, "Damp", "", 0, 1, 0.5);
    params ~= mallocNew!LinearFloatParameter(Params.roomSize, "RoomSize", "", 0, 1, 0.5);
    params ~= mallocNew!LinearFloatParameter(Params.wet, "Wet", "", 0, 1, 0.3333);
    params ~= mallocNew!LinearFloatParameter(Params.width, "Width", "", 0, 1, 0.5);
    params ~= mallocNew!BoolParameter(Params.freeze, "Freeze", false);
    return params.releaseData();
  }

  override LegalIO[] buildLegalIO() {
    Vec!LegalIO io = makeVec!LegalIO();
    io ~= LegalIO(1, 1);
    io ~= LegalIO(2, 2);
    return io.releaseData();
  }

  override int maxFramesInProcess() { return 32; }

  override void reset(double sampleRate, int maxFrames, int numInputs, int numOutputs) {
    _sampleRate = sampleRate;

    const int maxSpread = _widthToDelay(1.0);
    const maxCombDelay = cast(int) (combTunings[$ - 1] * sampleRate / _origSampleRate + maxSpread);
    foreach (int ch; 0 .. numInputs) {
      foreach (ref CombFilter f; _comb[ch]) {
        f.recalloc(maxCombDelay);
      }
      foreach (ref AllPassFilter f; _allPass[ch]) {
        f.recalloc(_maxAllPassDelay);
      }
    }
  }

  override void processAudio(const(float*)[] inputs, float*[] outputs, int frames, TimeInfo info) {
    _setFilterDelay();

    const bool freeze = readParam!bool(Params.freeze);
    const float damp = freeze ? 0 : readParam!float(Params.damp) * 0.4 * _origSampleRate / _sampleRate;
    const float roomSize = freeze ? 1 : readParam!float(Params.roomSize) * 0.28 * _origSampleRate / _sampleRate + 0.7;
    const float wet = readParam!float(Params.wet);

    foreach (ch; 0 .. outputs.length) {
      foreach (t; 0 .. frames) {
        float x = freeze ? 0 : wet * 0.1 * (inputs[0][t] + inputs[1][t]);
        float y = 0;
        foreach (ref CombFilter f; _comb[ch]) {
          y += f.apply(x, damp, roomSize);
        }
        foreach (ref AllPassFilter f; _allPass[ch]) {
          y = f.apply(y);
        }
        outputs[ch][t] = y + (1 - wet) * inputs[ch][t];
      }
    }
  }

private:
  int _widthToDelay(const float width) const {
    return cast(int) (width * 46 * _sampleRate / _origSampleRate);
  }

  void _setFilterDelay() {
    const int width = _widthToDelay(readParam!float(Params.width));

    foreach (ch; 0 .. 2) {
      const int spread = ch == 0 ? 0 : width;
      foreach (i, ref CombFilter f; _comb[ch]) {
        f.resize(cast(int) (combTunings[i] * _sampleRate / _origSampleRate) + spread);
      }
      foreach (i, ref AllPassFilter f; _allPass[ch]) {
        const int delay = cast(int) (allPassTunings[i] * _sampleRate / _origSampleRate);
        f.resize(min(_maxAllPassDelay, max(0, delay + spread - 1)));
      }
    }
  }

  AllPassFilter[2][4] _allPass;
  CombFilter[2][8] _comb;
  double _sampleRate = _origSampleRate;

  static immutable combTunings = [ 1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617 ];
  static immutable allPassTunings = [ 556, 441, 341, 225 ];
  enum _origSampleRate = 44_100;
  enum _maxAllPassDelay = 1024;
}

mixin(pluginEntryPoints!FreeverbClient);
