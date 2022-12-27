/**
   Synth2 ADSR envelope module.

   Copyright: klknn 2021.
   License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module kdr.envelope;

import std.algorithm : clamp;
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
struct Envelope {
 public:
  @nogc nothrow:

  enum MAX_POINTS = 32;

  float getY(float x) const pure @safe {
    assert(0 <= x && x <= 1);
    size_t nextIdx = newIndex(x);
    if (nextIdx == length) return _points[length - 1].y;

    size_t prevIdx = nextIdx - 1;
    Point prev = this[prevIdx];
    Point next = this[nextIdx];
    if (!prev.isCurve && !next.isCurve) {
      return linmap(x, prev.x, next.x, prev.y, next.y);
    }

    // ???
    while (this[prevIdx].isCurve) --prevIdx;
    while (this[nextIdx].isCurve) ++nextIdx;
    return interpolate(x, this[prevIdx .. nextIdx + 1]);
  }

  bool add(Point p) pure @safe {
    assert(0 <= p.x && p.x <= 1);
    assert(0 <= p.y && p.y <= 1);

    // Cannot add x anymore.
    if (length >= MAX_POINTS) return false;

    const idx = newIndex(p.x);
    foreach_reverse (i; idx .. length) {
      _points[i + 1] = _points[i];
    }
    _points[idx] = p;
    ++_length;
    return true;
  }

  bool del(int i) pure @safe {
    if (i <= 0 || length <= i) return false;

    foreach (j; i .. length) {
      _points[j] = _points[j + 1];
    }
    --_length;
    return true;
  }

  int length() const pure @safe { return _length; }

  /// Value of evelope points.
  struct Point {
    @nogc nothrow pure @safe:
    vec2f xy;
    alias xy this;
    bool isCurve;
  }

  inout(Point)[] points() inout pure @safe return {
    return _points[0 .. length];
  }

  /// For array-like (opIndex etc) overloading.
  alias points this;

 private:
  /// Params: newx = new x value to be added to points.
  /// Returns: a new index if newx will be added to xs.
  size_t newIndex(float newx) const pure @safe {
    foreach (i, p; _points[0 .. length]) {
      if (newx < p.x) {
        return i;
      }
    }
    return length - 1;
  }

  // Lagrange interpolation.
  float interpolate(float x, const Point[] ps) const pure @safe {
    float y = 0;
    foreach (i, p; ps) {
      float lx = 1;
      foreach (j, q; ps)  {
        if (i == j) continue;
        lx *= (x - q.x) / (p.x - q.x);
      }
      y += p.y * lx;
    }
    return clamp(y, 0, 1);
  }

  int _length = 2;
  Point[MAX_POINTS] _points = [Point(vec2f(0, 0)), Point(vec2f(1, 0))];
}

nothrow pure @safe
unittest {
  Envelope env;

  // Initial start/end points.
  assert(env.getY(0.0) == 0.0);
  assert(env.getY(1.0) == 0.0);
  assert(env[0] == vec2f(0, 0));
  assert(env[1] == vec2f(1, 0));
  assert(env[$-1] == vec2f(1, 0));

  // Check interp.
  assert(env.getY(0.25) == 0.0);
  assert(env.getY(0.75) == 0.0);

  // Add a new point.
  assert(env.add(Envelope.Point(vec2f(0.5, 1.0))));
  assert(env.getY(0.5) == 1.0);
  assert(env[1] == vec2f(0.5, 1.0));
  assert(env.length == 3);

  // The added point changes the interp.
  assert(env.getY(0.25) == 0.5);
  assert(env.getY(0.75) == 0.5);

  // Update the existing point.
  env[1] = Envelope.Point(vec2f(0, 0));
  assert(env[1] == vec2f(0, 0));

  assert(env.del(1));
  assert(env.length == 2);
}
