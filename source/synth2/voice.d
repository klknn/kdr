/**
Synth2 voice module.

Copyright: klknn 2021.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module synth2.voice;

import mir.math.common : fastmath;

import synth2.envelope : ADSR;

/// Voice stack for storing previous voices for legato.
struct VoiceStack {
  @nogc nothrow @safe pure:
  int[128] data;
  bool[128] on;
  int idx;

  bool empty() const { return idx < 0; }

  void push(int note) {
    if (idx == data.length - 1) return;
    data[++idx] = note;
    on[note] = true;
  }

  int front() const {
    // TODO: assert(!empty);
    return empty ? data[0] : data[idx];
  }

  void reset() {
    idx = -1;
    on[] = false;
  }

  void popFront() pure {
    while (!empty) {
      --idx;
      if (on[this.front]) return;
    }
  }
}

/// Mono voice status.
struct VoiceStatus {
  @nogc nothrow @safe @fastmath:

  bool isPlaying() const pure {
    return !this.envelope.empty;
  }

  float front() const {
    if (!this.isPlaying) return 0f;
    return this._gain * this.envelope.front;
  }

  void popFront() pure {
    this.envelope.popFront();
    if (_legatoFrames < _portamentFrames) ++_legatoFrames;
  }

  void setSampleRate(float sampleRate) pure {
    _sampleRate = sampleRate;
    this.envelope.setSampleRate(sampleRate);
    _legatoFrames = 0;
    _notePrev = -1;
  }

  void setParams(bool legato, float portament, bool autoPortament) pure {
    _legato = legato;
    _portamentFrames = portament * _sampleRate;
    _autoPortament = autoPortament;
  }

  void play(int note, float gain) pure {
    this._notePrev = (_autoPortament && !this.isPlaying) ? -1 : _stack.front;
    this._gain = gain;
    this._legatoFrames = 0;
    _stack.push(note);
    if (_legato && this.isPlaying) return;
    this.envelope.attack();
  }

  void stop(int note) pure {
    if (this.isPlaying) {
      _stack.on[note] = false;
      if (_stack.front == note) {
        _stack.popFront();
        _legatoFrames = 0;
        _notePrev = note;
        if (_legato && !_stack.empty) return;
        this.envelope.release();
        _stack.reset();
      }
    }
  }

  float note() const pure {
    if (!_legato || _legatoFrames >= _portamentFrames
        || _notePrev == -1) return _stack.front;

    auto diff = (_stack.front - _notePrev) * _legatoFrames / _portamentFrames;
    return _notePrev + diff;
  }

  void setADSR(float a, float d, float s, float r) pure {
    envelope.attackTime = a;
    envelope.decayTime = d;
    envelope.sustainLevel = s;
    envelope.releaseTime = r;
  }

 private:
  float _sampleRate = 44100;
  float _notePrev = -1;
  float _gain = 1f;

  bool _legato = false;
  bool _autoPortament = false;
  float _portamentFrames = 0;
  float _legatoFrames = 0;

  ADSR envelope;
  VoiceStack _stack;
}

/// Test stacked previous notes used in legato.
unittest {
  VoiceStatus v;
  v._legato = true;
  v.play(23, 1);
  assert(v.note == 23);
  v.play(24, 1);
  assert(v.note == 24);
  v.stop(24);
  assert(v.note == 23);
}