/**
   Synth2 ADSR envelope module.

   Copyright: klknn 2021.
   License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module kdr.envelope;

import std.math : isNaN;

import dplug.math.vector : vec2f;
import dplug.core.math : linmap;
import dplug.client.midi : MidiMessage;
import mir.math.common : fastmath;

/// Envelope stages.
enum Stage {
  attack,
  decay,
  sustain,
  release,
  done,
}

/// Attack, Decay, Sustain, Release.
struct ADSR {
  /// Attack time in #frames.
  float attackTime = 0;
  /// Decay time in #frames.
  float decayTime = 0;
  /// Sustain level within [0, 1].
  float sustainLevel = 1;
  /// Release time in #frames.
  float releaseTime = 0;

  @nogc nothrow @safe pure @fastmath:

  /// Triggers the atack stage.
  void attack() {
    _stage = Stage.attack;
    _stageTime = 0;
  }

  /// Triggers the release stage.
  void release() {
    _releaseLevel = this.front;
    _stage = Stage.release;
    _stageTime = 0;
  }

  void setSampleRate(float sampleRate) {
    _frameWidth = 1f / sampleRate;
    _stage = Stage.done;
    _stageTime = 0;
    _nplay = 0;
  }

  /// Returns: true if envelope was ended.
  bool empty() const { return _stage == Stage.done; }

  /// Returns: an amplitude of the linear envelope.
  float front() const {
    final switch (_stage) {
      case Stage.attack:
        return this.attackTime == 0 ? 1 : (_stageTime / this.attackTime);
      case Stage.decay:
        return this.decayTime == 0
            ? 1 : (_stageTime * (this.sustainLevel -  1f) /  this.decayTime + 1f);
      case Stage.sustain:
        return this.sustainLevel;
      case Stage.release:
        assert(!isNaN(_releaseLevel), "invalid release level.");
        return this.releaseTime == 0 ? 0f
            : (-_stageTime * _releaseLevel / this.releaseTime
               + _releaseLevel);
      case Stage.done:
        return 0f;
    }
  }

  /// Update status if the stage is in (attack, decay, release).
  void popFront() {
    final switch (_stage) {
      case Stage.attack:
        _stageTime += _frameWidth;
        if (_stageTime >= this.attackTime) {
          _stage = Stage.decay;
          _stageTime = 0;
        }
        return;
      case Stage.decay:
        _stageTime += _frameWidth;
        if (_stageTime >= this.decayTime) {
          _stage = Stage.sustain;
          _stageTime = 0;
        }
        return;
      case Stage.sustain:
        return; // do nothing.
      case Stage.release:
        _stageTime += _frameWidth;
        if (_stageTime >= this.releaseTime) {
          _stage = Stage.done;
          _stageTime = 0;
        }
        return;
      case Stage.done:
        return;  // do nothing.
    }
  }

  @system void setMidi(MidiMessage msg) {
    if (msg.isNoteOn) {
      if (_nplay == 0) this.attack();
      ++_nplay;
    }
    if (msg.isNoteOff) {
      --_nplay;
      if (_nplay == 0) this.release();
    }
  }

 private:
  Stage _stage = Stage.done;
  float _frameWidth = 1.0 / 44_100;
  float _stageTime = 0;
  float _releaseLevel;
  int _nplay = 0;
}

/// Test ADSR.
@nogc nothrow pure @safe
unittest {
  ADSR env;
  env.attackTime = 5;
  env.decayTime = 5;
  env.sustainLevel = 0.5;
  env.releaseTime = 20;
  env._frameWidth = 1;

  foreach (_; 0 .. 2) {
    env.attack();
    foreach (i; 0 .. env.attackTime) {
      assert(env._stage == Stage.attack);
      env.popFront();
    }
    foreach (i; 0 .. env.decayTime) {
      assert(env._stage == Stage.decay);
      env.popFront();
    }
    assert(env._stage == Stage.sustain);
    env.release();
    // foreach does not mutate `env`.N
    foreach (amp; env) {
      assert(env._stage == Stage.release);
    }
    foreach (i; 0 .. env.releaseTime) {
      assert(env._stage == Stage.release);
      env.popFront();
    }
    assert(env._stage == Stage.done);
    assert(env.empty);
    assert(env.front == 0);
  }
}


/// Dynamically adjustable envelope shaper.
struct DynamicEnvelope {
 public:
  @nogc nothrow:

  alias Point = vec2f;

  Point opIndex(size_t i) const pure @safe {
    assert(i < length);
    return Point(_xs[i], _ys[i]);
  }

  int opDollar(size_t pos)() const pure @safe {
    static assert(pos == 0);
    return length;
  }

  Point opIndexAssign(Point p, size_t i) pure @safe {
    assert(i < length);
    _xs[i] = p.x;
    _ys[i] = p.y;
    return p;
  }

  int opApply(scope int delegate(Point) @nogc nothrow dg) const {
    import dplug.core.nogc;
    foreach (i; 0 .. length) {
      if (int result = dg(this[i])) return result;
    }
    return 0;
  }

  float getY(float x) const pure @safe {
    assert(0 <= x && x <= 1);
    const nextIdx = newIndex(x);
    if (nextIdx == length) return _ys[length - 1];
    return linmap(x, _xs[nextIdx-1], _xs[nextIdx], _ys[nextIdx-1], _ys[nextIdx]);
  }

  bool add(float x, float y) pure @safe {
    assert(0 <= x && x <= 1);
    assert(0 <= y && y <= 1);

    // Cannot add x anymore.
    if (length >= _N) return false;

    const idx = newIndex(x);
    _xs[idx + 1 .. length + 1] = _xs[idx .. length];
    _ys[idx + 1 .. length + 1] = _ys[idx .. length];
    _xs[idx] = x;
    _ys[idx] = y;
    ++_length;
    return true;
  }

  int length() const pure @safe { return _length; }

 private:
  // Returns a new index if newx will be added to xs.
  size_t newIndex(float newx) const pure @safe {
    foreach (i, x; _xs[0 .. length]) {
      if (newx < x) {
        return i;
      }
    }
    return length;
  }

  enum _N = 8;
  int _length = 2;
  float[_N] _xs = [0, 1];  // Sorted and normalized to [0.0 .. 1.0]
  float[_N] _ys = [0, 0];  // Normalized to [0.0 .. 1.0]
  // float[N + 1] interp;  // Interporation point between ys[i-1] and ys[i].
}

@nogc nothrow pure @safe
unittest {
  DynamicEnvelope env;

  // Initial start/end points.
  assert(env.getY(0.0) == 0.0);
  assert(env.getY(1.0) == 0.0);
  assert(env[0] == DynamicEnvelope.Point(0, 0));
  assert(env[1] == DynamicEnvelope.Point(1, 0));
  assert(env[$-1] == DynamicEnvelope.Point(1, 0));

  // Check interp.
  assert(env.getY(0.25) == 0.0);
  assert(env.getY(0.75) == 0.0);

  // Add a new point.
  assert(env.add(0.5, 1.0));
  assert(env.getY(0.5) == 1.0);
  assert(env[1] == DynamicEnvelope.Point(0.5, 1.0));
  assert(env.length == 3);

  // The added point changes the interp.
  assert(env.getY(0.25) == 0.5);
  assert(env.getY(0.75) == 0.5);

  // Update the existing point.
  env[1] = DynamicEnvelope.Point(0, 0);
  assert(env[1] == DynamicEnvelope.Point(0, 0));
}
