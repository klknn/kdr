/**
Ocillator module.

Copyright: klknn 2021.
Copyright: Elias Batek 2018.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module synth2.oscillator;

import std.math : isNaN;

import dplug.core.math : convertDecibelToLinearGain;
import dplug.client.midi : MidiMessage, MidiStatus;
import mir.math : log2, exp2, fastmath, PI;

import synth2.envelope : ADSR;
import synth2.waveform : Waveform, WaveformRange;

@safe nothrow @nogc:

struct VoiceStack {
  @nogc nothrow @safe:
  int[128] data;
  bool[128] on;
  int idx;

  bool empty() const pure { return idx < 0; }

  void push(int note) pure {
    if (idx == data.length - 1) return;
    data[++idx] = note;
    on[note] = true;
  }

  int front() const pure {
    // TODO: assert(!empty);
    return empty ? data[0] : data[idx];
  }

  void reset() pure {
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

/// Mono voice status (subosc).
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

/// Maps 0 to 127 into Decibel domain with affine transformation.
/// For example, velocities [0, 68, 127] will be mapped to
/// [-20, -0.9, 0] dB if sensitivity = 1.0, bias = 1e-3
/// [-11, -1.9, -1] if sensitivity = 0.5, bias = 1e-3
/// [-10, -10, -10] if sensitivity = 0.0, bias = 1e-3
float velocityToDB(int velocity, float sensitivity = 1.0, float bias = 1e-1) @fastmath pure {
  assert(0 <= velocity && velocity <= 127);
  auto scaled = (velocity / 127f - bias) * sensitivity + bias;
  return log2(scaled + 1e-6);
}

///
@system pure unittest {
  import std.math : approxEqual;
  auto sens = 1.0;
  assert(approxEqual(convertDecibelToLinearGain(velocityToDB(127, sens)), 1f));
  assert(approxEqual(convertDecibelToLinearGain(velocityToDB(68, sens)), 0.9f));
  assert(approxEqual(convertDecibelToLinearGain(velocityToDB(0, sens)), 0.1f));

  sens = 0.0;
  auto g = 0.682188;
  assert(approxEqual(convertDecibelToLinearGain(velocityToDB(127, sens)), g));
  assert(approxEqual(convertDecibelToLinearGain(velocityToDB(68, sens)), g));
  assert(approxEqual(convertDecibelToLinearGain(velocityToDB(0, sens)), g));
}

float convertMIDINoteToFrequency(float note) @fastmath pure
{
    return 440.0f * exp2((note - 69.0f) / 12.0f);
}

/// Polyphonic oscillator that generates WAV samples by given params and midi.
struct Oscillator
{
 public:
  @safe @nogc nothrow @fastmath:

  // Setters
  pure void setInitialPhase(float value) {
    this._initialPhase = value;
  }

  pure void setWaveform(Waveform value) {
    foreach (ref w; _waves) {
      w.waveform = value;
    }
  }

  pure void setPulseWidth(float value) {
    foreach (ref w; _waves) {
      w.pulseWidth = value;
    }
  }

  pure void setSampleRate(float sampleRate) {
    foreach (ref v; _voicesArr) {
      v.setSampleRate(sampleRate);
    }
    foreach (ref w; _wavesArr) {
      w.sampleRate = sampleRate;
      w.phase = 0;
    }
  }

  pure void setVelocitySense(float value) {
    this._velocitySense = value;
  }

  void setMidi(MidiMessage msg) @system {
    if (msg.isNoteOn) {
      markNoteOn(msg);
    }
    if (msg.isNoteOff) {
      markNoteOff(msg.noteNumber());
    }
    if (msg.isPitchBend) {
      _pitchBend = msg.pitchBend();
    }
  }

  pure void setNoteTrack(bool b) {
    _noteTrack = b;
  }

  pure void setNoteDiff(float note) {
    _noteDiff = note;
  }

  pure void setNoteDetune(float val) {
    _noteDiff = val;
  }

  pure float note(const ref VoiceStatus v) const {
    return (_noteTrack ? v.note : 69.0f) + _noteDiff + _noteDetune
        // TODO: fix pitch bend
        + _pitchBend * _pitchBendWidth;
  }

  pure void synchronize(const ref Oscillator src) {
    foreach (i, ref w; _waves) {
      if (src._waves[i].normalized) {
        w.phase = 0f;
      }
    }
  }

  void setFM(float scale, const ref Oscillator mod) {
    foreach (i, ref w; _waves) {
      w.phase += scale * mod._voices[i].front;
    }
  }

  pure void setADSR(float a, float d, float s, float r) {
    foreach (ref v; _voices) {
      v.envelope.attackTime = a;
      v.envelope.decayTime = d;
      v.envelope.sustainLevel = s;
      v.envelope.releaseTime = r;
    }
  }

  enum empty = false;

  /// Returns sum of amplitudes of _waves at the current phase.
  float front() const {
    float sample = 0;
    foreach (i, ref v; _voices) {
      sample += v.front * _waves[i].front;
    }
    return sample / _voicesArr.length;
  }

  /// Increments phase in _waves.
  pure void popFront() {
    foreach (ref v; _voices) {
      v.popFront();
    }
    foreach (ref w; _waves) {
      w.popFront();
    }
  }

  /// Updates frequency by MIDI and params.
  pure void updateFreq() @system {
    foreach (i, ref v; _voices) {
      if (v.isPlaying) {
        _waves[i].freq = convertMIDINoteToFrequency(this.note(v));
      }
    }
  }

  pure bool isPlaying() const {
    foreach (ref v; _voices) {
      if (v.isPlaying) return true;
    }
    return false;
  }

  pure WaveformRange lastUsedWave() const {
    return _waves[_lastUsedId];
  }

  void setVoice(int n, bool legato, float portament, bool autoPortament) {
    assert(n <= _voicesArr.length, "Exceeds allocated voices.");
    assert(0 <= n, "MaxVoices must be positive.");
    _maxVoices = n;
    foreach (ref v; _voices) {
      v.setParams(legato, portament, autoPortament);
    }
  }

 private:
  size_t getNewVoiceId() const pure {
    foreach (i, ref v; _voices) {
      if (!v.isPlaying) {
        return i;
      }
    }
    return (_lastUsedId + 1) % _voices.length;
  }

  pure void markNoteOn(MidiMessage midi) @system {
    const i = this.getNewVoiceId();
    const db =  velocityToDB(midi.noteVelocity(), this._velocitySense);
    _voices[i].play(midi.noteNumber(), convertDecibelToLinearGain(db));
    if (this._initialPhase != -PI)
      _waves[i].phase = this._initialPhase;
    _lastUsedId = i;
  }

  pure void markNoteOff(int note) {
    foreach (ref v; this._voices) {
      v.stop(note);
    }
  }

  inout(VoiceStatus)[] _voices() inout pure {
    return _voicesArr[0 .. _maxVoices];
  }

  inout(WaveformRange)[] _waves() inout pure {
    return _wavesArr[0 .. _maxVoices];
  }

  // voice global config
  float _initialPhase = 0.0;
  float _noteDiff = 0.0;
  float _noteDetune = 0.0;
  bool _noteTrack = true;
  float _velocitySense = 0.0;
  float _pitchBend = 0.0;
  float _pitchBendWidth = 2.0;
  size_t _lastUsedId = 0;
  size_t _maxVoices = _voicesArr.length;

  enum numVoices = 16;
  VoiceStatus[numVoices] _voicesArr;
  WaveformRange[numVoices] _wavesArr;
}
