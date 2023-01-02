module kdr.compressor;

import mir.math : sqrt;

import kdr.ringbuffer;

struct RmsSlidingWindow {
  @nogc nothrow:

  this(int frames) {
    _buffer.recalloc(frames);
  }

  void clear() {
    _buffer.clear();
  }

  float opCall(float x) {
    _buffer.enqueue(x * x);
    float sum = 0;
    foreach (sq; _buffer) {
      sum +=  sq;
    }
    return sqrt(sum / _buffer.length);
  }

 private:
  RingBuffer!float _buffer;
}

unittest {
  RmsSlidingWindow rms = 2;
  assert(rms(1) == sqrt(1f / 2));
  assert(rms(2) == sqrt((1f + 4f) / 2));
  assert(rms(3) == sqrt((4f + 9f) / 2));
}

struct Compressor {
  @nogc nothrow:

  bool rms = true;
  bool softKnee = true;
  float upwardRatio = 1;
  float downwardRatio = 1;
  float upwardThreshold = 1;
  float downwardThreshold = 1;
  float attackMS = 2;
  float releaseMS = 50;

  float compress(float x) {
    // TODO: softKnee using softplus.
    if (x > downwardThreshold) {
      return (x - downwardThreshold) / downwardRatio + downwardThreshold;
    }
    if (x < upwardThreshold) {
      return (x - upwardThreshold) / upwardRatio + upwardThreshold;
    }
    return x;
  }

 private:
  double _sampleRate = 44_100;
}
