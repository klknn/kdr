module kdr.rezonizer.client;

import std.math : exp2, exp, cos, sin, sqrt, tanh;

import dplug.client : Client, IGraphics, LegalIO, Parameter, PluginInfo, TimeInfo;
import dplug.core : Vec, makeVec, mallocNew;

import kdr.rezonizer.dsp : Biquad, DCBlocker, FractionalCombFilter, HaasDelay, StereoReverb;
import kdr.rezonizer.params : Params, buildRezonizerParameters;

/// Rezonizer VST3 client.
class RezonizerClient : Client {
  public nothrow @nogc:

  this() {
    super();
  }

  override Parameter[] buildParameters() {
    return buildRezonizerParameters();
  }

  @safe
  override PluginInfo buildPluginInfo() {
    return PluginInfo.init;
  }

  override IGraphics createGraphics() {
    if (!_gui) {
      import kdr.rezonizer.gui : RezonizerGUI;
      _gui = mallocNew!RezonizerGUI(this, params);
    }
    return _gui;
  }

  override LegalIO[] buildLegalIO() {
    Vec!LegalIO io = makeVec!LegalIO();
    io ~= LegalIO(1, 1);
    io ~= LegalIO(2, 2);
    return io.releaseData();
  }

  override int maxFramesInProcess() {
    return 32;
  }

  float voiceLevel(int index) const pure {
    return _voiceLevels[index];
  }

  float outputLevel(int channel) const pure {
    return _outLevels[channel];
  }

  override void reset(double sampleRate, int maxFrames, int numInputs, int numOutputs) {
    _sampleRate = sampleRate;
    foreach (ref voice; _voices) {
      voice.reset();
    }
    _dcBlockerL.reset();
    _dcBlockerR.reset();

    _filterHPF_L.reset();
    _filterHPF_R.reset();
    _filterPeak_L.reset();
    _filterPeak_R.reset();
    _filterLPF_L.reset();
    _filterLPF_R.reset();

    _reverb.init(cast(float)sampleRate);
    _reverb.reset();
    _reverbHPF_L.reset();
    _reverbHPF_R.reset();

    _haasDelay.reset();

    _voiceGate[] = 0.0f;
    _voiceAmplitude[] = 0.0f;
    _voiceMidiNote[] = 60.0f;
    _voiceTriggerTime[] = 0;
    _currentPitch[] = 60.0f;
    _targetPitchChanged[] = true;
    _voiceLevels[] = 0.0f;
    _outLevels[] = 0.0f;

    _firstBlock = true;
  }

  override void processAudio(const(float*)[] inputs, float*[] outputs, int frames, TimeInfo info) {
    const bool midiInputEnabled = readParam!bool(Params.midiInput);

    if (midiInputEnabled) {
      const int midiMode = readParam!int(Params.midiMode); // 0 = Normal, 1 = Round-Robin

      foreach (msg; getNextMidiMessages(frames)) {
        if (msg.isNoteOn) {
          const int note = msg.noteNumber();
          int targetVoiceIdx = -1;

          // Check if this note is already playing on an active resonator
          foreach (i; 0 .. 6) {
            if (readParam!bool(Params.voice1Enable + i * 5) && _voiceGate[i] > 0.0f && _voiceMidiNote[i] == note) {
              targetVoiceIdx = cast(int) i;
              break;
            }
          }

          if (targetVoiceIdx == -1) {
            foreach (i; 0 .. 6) {
              if (readParam!bool(Params.voice1Enable + i * 5) && _voiceAmplitude[i] <= 0.0f) {
                targetVoiceIdx = cast(int) i;
                break;
              }
            }
          }

          if (targetVoiceIdx == -1) {
            if (midiMode == 0) { // Normal mode: steal oldest playing voice
              long oldestTime = 999999999;
              foreach (i; 0 .. 6) {
                if (readParam!bool(Params.voice1Enable + i * 5) && _voiceTriggerTime[i] < oldestTime) {
                  oldestTime = _voiceTriggerTime[i];
                  targetVoiceIdx = cast(int) i;
                }
              }
            } else { // Round-Robin mode: circular voice stealing
              int candidate = (_lastAssignedVoice + 1) % 6;
              foreach (step; 0 .. 6) {
                int idx = (candidate + step) % 6;
                if (readParam!bool(Params.voice1Enable + idx * 5)) {
                  targetVoiceIdx = idx;
                  break;
                }
              }
            }
          }

          if (targetVoiceIdx != -1) {
            _voiceMidiNote[targetVoiceIdx] = note;
            _voiceGate[targetVoiceIdx] = 1.0f;
            _voiceAmplitude[targetVoiceIdx] = 1.0f;
            _voiceTriggerTime[targetVoiceIdx] = _currentTriggerIndex++;
            _targetPitchChanged[targetVoiceIdx] = true;
            _lastAssignedVoice = targetVoiceIdx;
          }
        }
        else if (msg.isNoteOff) {
          if (midiMode == 0) {
            const int note = msg.noteNumber();
            foreach (i; 0 .. 6) {
              if (_voiceMidiNote[i] == note) {
                _voiceGate[i] = 0.0f;
              }
            }
          }
        }
      }
    }

    const float dryGainDb = readParam!float(Params.dryGain);
    const float wetGainDb = readParam!float(Params.wetGain);
    const float dryGain = exp(dryGainDb * 0.115129f); // 10^(dB/20)
    const float wetGain = exp(wetGainDb * 0.115129f);

    const int mode = readParam!int(Params.mode); // 0 = Saw, 1 = Square
    const float decayTime = readParam!float(Params.decay);
    const float damp = readParam!float(Params.damp);

    const bool filterBypassed = readParam!bool(Params.filterBypass);
    const float filterHPFVal = readParam!float(Params.filterHPF);
    const float filterLPFVal = readParam!float(Params.filterLPF);
    const float filterPeakFreqVal = readParam!float(Params.filterPeakFreq);
    const float filterPeakQVal = readParam!float(Params.filterPeakQ);
    const float filterPeakGainVal = readParam!float(Params.filterPeakGain);

    const int preset = readParam!int(Params.chordPreset);
    const float releaseTime = readParam!float(Params.releaseTime);

    const bool reverbEnabled = readParam!bool(Params.reverbEnable);
    const float reverbMixVal = readParam!float(Params.reverbMix);
    const float reverbLengthVal = readParam!float(Params.reverbLength);
    const float reverbLowsVal = readParam!float(Params.reverbLows);
    const float reverbHighsVal = readParam!float(Params.reverbHighs);

    const float portamentoTime = readParam!float(Params.portamento);
    const float haasWidthVal = readParam!float(Params.haasWidth);

    bool[6] voiceEnables;
    float[6] voicePitches;
    float[6] voiceFines;
    float[6] voiceGainsDb;
    float[6] voiceGains;
    float[6] voicePans;

    foreach (i; 0 .. 6) {
      voiceEnables[i] = readParam!bool(Params.voice1Enable + i * 5);
      voicePitches[i] = readParam!float(Params.voice1Pitch + i * 5);
      voiceFines[i] = readParam!float(Params.voice1Fine + i * 5);
      voiceGainsDb[i] = readParam!float(Params.voice1Gain + i * 5);
      voiceGains[i] = exp(voiceGainsDb[i] * 0.115129f);
      voicePans[i] = readParam!float(Params.voice1Pan + i * 5);
    }

    bool forceUpdate = _firstBlock;
    _firstBlock = false;

    if (decayTime != _prevDecay || damp != _prevDamp || mode != _prevMode || preset != _prevChordPreset || midiInputEnabled != _prevMidiInput) {
      forceUpdate = true;
      _prevDecay = decayTime;
      _prevDamp = damp;
      _prevMode = mode;
      _prevChordPreset = preset;
      _prevMidiInput = midiInputEnabled;
    }

    foreach (i; 0 .. 6) {
      if (voiceFines[i] != _prevVoiceFines[i] || voicePitches[i] != _prevVoicePitches[i] || voiceEnables[i] != _prevVoiceEnables[i]) {
        forceUpdate = true;
        _prevVoiceFines[i] = voiceFines[i];
        _prevVoicePitches[i] = voicePitches[i];
        _prevVoiceEnables[i] = voiceEnables[i];
      }
    }

    if (forceUpdate) {
      foreach (i; 0 .. 6) {
        _targetPitchChanged[i] = true;
      }
    }

    float[6] offsets = [0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f];
    if (!midiInputEnabled) {
      if (preset == 6) { // Custom
        offsets[0] = 0.0f;
        offsets[1] = voicePitches[1];
        offsets[2] = voicePitches[2];
        offsets[3] = voicePitches[3];
        offsets[4] = voicePitches[4];
        offsets[5] = voicePitches[5];
      } else {
        // Unison, Major, Minor, Major 7th, Minor 7th, Sus4
        static immutable float[6][6] presetOffsets = [
          [0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f],       // Unison
          [0.0f, 4.0f, 7.0f, 12.0f, 16.0f, 19.0f],    // Major
          [0.0f, 3.0f, 7.0f, 12.0f, 15.0f, 19.0f],    // Minor
          [0.0f, 4.0f, 7.0f, 11.0f, 12.0f, 16.0f],    // Major 7th
          [0.0f, 3.0f, 7.0f, 10.0f, 12.0f, 15.0f],    // Minor 7th
          [0.0f, 5.0f, 7.0f, 12.0f, 17.0f, 19.0f]     // Sus4
        ];
        offsets = presetOffsets[preset];
      }
    }

    if (!filterBypassed) {
      _filterHPF_L.setHPF(filterHPFVal, cast(float)_sampleRate);
      _filterHPF_R.setHPF(filterHPFVal, cast(float)_sampleRate);
      _filterPeak_L.setPeaking(filterPeakFreqVal, cast(float)_sampleRate, filterPeakQVal, filterPeakGainVal);
      _filterPeak_R.setPeaking(filterPeakFreqVal, cast(float)_sampleRate, filterPeakQVal, filterPeakGainVal);
      _filterLPF_L.setLPF(filterLPFVal, cast(float)_sampleRate);
      _filterLPF_R.setLPF(filterLPFVal, cast(float)_sampleRate);
    }

    const float reverbHPFFreq = (1.0f - reverbLowsVal) * 350.0f;
    _reverbHPF_L.setHPF(reverbHPFFreq, cast(float)_sampleRate);
    _reverbHPF_R.setHPF(reverbHPFFreq, cast(float)_sampleRate);

    float[6] targetPitches;
    foreach (i; 0 .. 6) {
      if (midiInputEnabled) {
        targetPitches[i] = _voiceMidiNote[i];
      } else {
        targetPitches[i] = voicePitches[0] + offsets[i];
      }
    }

    float[6] panL;
    float[6] panR;
    foreach (i; 0 .. 6) {
      float p = voicePans[i];
      float theta = (p + 1.0f) * 3.14159265f / 4.0f;
      panL[i] = cos(theta);
      panR[i] = sin(theta);
    }

    const float glideFactor = portamentoTime > 0.0f ? 1.0f - exp(-2.0f * 3.14159265f / (portamentoTime * cast(float)_sampleRate)) : 1.0f;
    const float releaseDecayFactor = exp(-6.907755f / (releaseTime * cast(float)_sampleRate));
    const float scaledDamp = damp * 0.95f;
    const bool isSquare = (mode == 1);

    float[6] delaySamples = 0.0f;
    float[6] feedbackGains = 0.0f;

    int numIn = cast(int) inputs.length;
    int numOut = cast(int) outputs.length;

    float[6] blockPeaks = 0.0f;
    float peakL = 0.0f;
    float peakR = 0.0f;

    foreach (t; 0 .. frames) {
      float inL = numIn > 0 ? inputs[0][t] : 0.0f;
      float inR = numIn > 1 ? inputs[1][t] : inL;

      float monoIn = (inL + inR) * 0.5f;

      foreach (i; 0 .. 6) {
        if (!voiceEnables[i]) {
          _voiceAmplitude[i] = 0.0f;
          continue;
        }

        if (midiInputEnabled) {
          if (_voiceGate[i] == 0.0f) {
            _voiceAmplitude[i] *= releaseDecayFactor;
            if (_voiceAmplitude[i] < 1e-4f) _voiceAmplitude[i] = 0.0f;
          }
        } else {
          _voiceAmplitude[i] = 1.0f;
        }

        const float targetPitch = targetPitches[i];
        if (portamentoTime > 0.0f) {
          _currentPitch[i] = _currentPitch[i] + (targetPitch - _currentPitch[i]) * glideFactor;
        } else {
          _currentPitch[i] = targetPitch;
        }

        float totalPitch = _currentPitch[i] + voiceFines[i] * 0.01f;
        float freq = 440.0f * exp2((totalPitch - 69.0f) / 12.0f);
        if (freq < 1.0f) freq = 1.0f;

        if (isSquare) {
          delaySamples[i] = cast(float)(_sampleRate / (2.0f * freq));
        } else {
          delaySamples[i] = cast(float)(_sampleRate / freq);
        }

        feedbackGains[i] = exp(-6.907755f * delaySamples[i] / (decayTime * cast(float)_sampleRate));
        if (feedbackGains[i] > 0.999f) feedbackGains[i] = 0.999f;
        if (feedbackGains[i] < 0.0f) feedbackGains[i] = 0.0f;
      }

      float wetL = 0.0f;
      float wetR = 0.0f;

      foreach (i; 0 .. 6) {
        if (!voiceEnables[i] || _voiceAmplitude[i] <= 0.0f) continue;

        float voiceRes = _voices[i].apply(monoIn, delaySamples[i], feedbackGains[i], scaledDamp, isSquare);
        float resAmp = voiceRes * voiceGains[i] * _voiceAmplitude[i];
        
        float absAmp = (resAmp < 0.0f) ? -resAmp : resAmp;
        if (absAmp > blockPeaks[i]) {
          blockPeaks[i] = absAmp;
        }

        wetL += resAmp * panL[i];
        wetR += resAmp * panR[i];
      }

      wetL = _dcBlockerL.apply(wetL);
      wetR = _dcBlockerR.apply(wetR);

      // Normalization scale factor to prevent clipping with multiple active resonators
      float activeCount = 0.0f;
      foreach (i; 0 .. 6) {
        if (voiceEnables[i] && _voiceAmplitude[i] > 0.0f) activeCount += 1.0f;
      }
      float scale = activeCount > 0.0f ? 1.0f / sqrt(activeCount) : 1.0f;
      wetL = tanh(wetL * scale);
      wetR = tanh(wetR * scale);

      wetL *= wetGain;
      wetR *= wetGain;

      if (!filterBypassed) {
        wetL = _filterHPF_L.apply(wetL);
        wetL = _filterPeak_L.apply(wetL);
        wetL = _filterLPF_L.apply(wetL);

        wetR = _filterHPF_R.apply(wetR);
        wetR = _filterPeak_R.apply(wetR);
        wetR = _filterLPF_R.apply(wetR);
      }

      if (reverbEnabled) {
        float revL, revR;
        const float revDamp = (1.0f - reverbHighsVal) * 0.5f;
        const float revLength = 0.7f + reverbLengthVal * 0.28f;
        _reverb.apply(wetL, wetR, revL, revR, reverbMixVal, revLength, revDamp);

        if (reverbHPFFreq > 20.0f) {
          revL = _reverbHPF_L.apply(revL);
          revR = _reverbHPF_R.apply(revR);
        }

        wetL = revL;
        wetR = revR;
      }

      if (haasWidthVal > 0.0f) {
        float delaySamps = haasWidthVal * 0.03f * cast(float)_sampleRate;
        wetR = _haasDelay.apply(wetR, delaySamps);
      }

      float outL = wetL + inL * dryGain;
      float outR = wetR + inR * dryGain;

      float absL = (outL < 0.0f) ? -outL : outL;
      float absR = (outR < 0.0f) ? -outR : outR;
      if (absL > peakL) peakL = absL;
      if (absR > peakR) peakR = absR;

      if (numOut > 0) outputs[0][t] = outL;
      if (numOut > 1) outputs[1][t] = outR;
    }

    foreach (i; 0 .. 6) {
      float current = _voiceLevels[i] * 0.9f;
      if (blockPeaks[i] > current) {
        current = blockPeaks[i];
      }
      _voiceLevels[i] = current;
    }

    float currentL = _outLevels[0] * 0.9f;
    if (peakL > currentL) currentL = peakL;
    _outLevels[0] = currentL;

    float currentR = _outLevels[1] * 0.9f;
    if (peakR > currentR) currentR = peakR;
    _outLevels[1] = currentR;
  }

 private:
  double _sampleRate = 44100.0;
  FractionalCombFilter[6] _voices;
  DCBlocker _dcBlockerL;
  DCBlocker _dcBlockerR;

  Biquad _filterHPF_L, _filterHPF_R;
  Biquad _filterPeak_L, _filterPeak_R;
  Biquad _filterLPF_L, _filterLPF_R;

  StereoReverb _reverb;
  Biquad _reverbHPF_L, _reverbHPF_R;

  HaasDelay _haasDelay;

  float[6] _voiceMidiNote = 60.0f;
  float[6] _voiceGate = 0.0f;
  float[6] _voiceAmplitude = 0.0f;
  long[6] _voiceTriggerTime = 0;
  long _currentTriggerIndex = 0;
  int _lastAssignedVoice = -1;

  float[6] _currentPitch = 60.0f;
  bool[6] _targetPitchChanged = true;

  bool _firstBlock = true;
  float _prevDecay = -1.0f;
  float _prevDamp = -1.0f;
  int _prevMode = -1;
  int _prevChordPreset = -1;
  bool _prevMidiInput = false;

  float[6] _prevVoiceFines = [-999.0f, -999.0f, -999.0f, -999.0f, -999.0f, -999.0f];
  float[6] _prevVoicePitches = [-999.0f, -999.0f, -999.0f, -999.0f, -999.0f, -999.0f];
  bool[6] _prevVoiceEnables = [false, false, false, false, false, false];

  float[6] _voiceLevels = 0.0f;
  float[2] _outLevels = 0.0f;

  import kdr.rezonizer.gui : RezonizerGUI;
  RezonizerGUI _gui;
}

unittest {
  import kdr.testing : benchmarkWithDefaultParams;
  benchmarkWithDefaultParams!RezonizerClient;
}

unittest {
  import kdr.testing : GenericTestHost;
  import dplug.client : LinearFloatParameter, LogFloatParameter, EnumParameter, BoolParameter, IntegerParameter, TimeInfo;
  import dplug.core : mallocNew, destroyFree, makeVec;

  alias TestHost = GenericTestHost!RezonizerClient;

  // Custom setParam helper for tests
  void setParam(int pid, T)(ref TestHost host, T val) {
    auto p = host.client.param(pid);
    static if (is(T == bool)) {
      p.setFromHost(val ? 1.0f : 0.0f);
    } else static if (is(T == int)) {
      if (auto ep = cast(EnumParameter) p) {
        p.setFromHost(ep.toNormalized(val));
      } else {
        p.setFromHost(cast(float) val);
      }
    } else {
      if (auto fp = cast(LinearFloatParameter) p) {
        p.setFromHost(fp.toNormalized(val));
      } else if (auto lp = cast(LogFloatParameter) p) {
        p.setFromHost(lp.toNormalized(val));
      } else {
        p.setFromHost(cast(float) val);
      }
    }
  }

  // Verify parameters mutation
  auto host = TestHost(new RezonizerClient());
  setParam!(Params.dryGain)(host, -6.0f);
  setParam!(Params.wetGain)(host, -3.0f);
  setParam!(Params.decay)(host, 2.5f);
  setParam!(Params.midiInput)(host, false);

  // Trigger audio processing and check output
  float[32] inL = 0.0f;
  float[32] inR = 0.0f;
  inL[0] = 1.0f; // Impulse excitation

  float[32] outL = 0.0f;
  float[32] outR = 0.0f;

  const(float*)[] inputs = [inL.ptr, inR.ptr];
  float*[] outputs = [outL.ptr, outR.ptr];

  TimeInfo info;
  host.client.processAudio(inputs, outputs, 32, info);

  // Output should contain resonance
  float energy = 0.0f;
  foreach (s; outL) {
    energy += s * s;
  }
  assert(energy > 0.0f);
}
