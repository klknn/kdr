module kdr.khrm.client;

import dplug.client : Client, IGraphics, LegalIO, Parameter, PluginInfo, TimeInfo;
import dplug.client.params : BoolParameter, LinearFloatParameter, EnumParameter;
import dplug.core : Vec, makeVec, mallocNew;

import kdr.khrm.dsp : KhrmDSP, SpectrumAnalyzer;
import kdr.khrm.params : Params, buildKhrmParameters, presets;

/// Khrm audio plugin client.
class KhrmClient : Client {
 public:
  nothrow @nogc:

  this() {
    super();
    _dsp = mallocNew!KhrmDSP();
  }

  ~this() {
    import dplug.core : destroyFree;
    destroyFree(_dsp);
  }

  override Parameter[] buildParameters() {
    return buildKhrmParameters();
  }

  @safe
  override PluginInfo buildPluginInfo() {
    return PluginInfo.init;
  }

  override IGraphics createGraphics() {
    if (!_gui) {
      import kdr.khrm.gui : KhrmGUI;
      _gui = mallocNew!KhrmGUI(this, params);
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

  const(SpectrumAnalyzer)* spectrum() const pure {
    return _dsp ? _dsp.spectrum() : null;
  }

  override void reset(double sampleRate, int maxFrames, int numInputs, int numOutputs) {
    _sampleRate = cast(float) sampleRate;
    _dsp.reset(_sampleRate);
    _midiNotes[] = false;
    _midiNoteCount = 0;
    _lastPreset = -1;
  }

  override void processAudio(const(float*)[] inputs, float*[] outputs, int frames, TimeInfo info) {
    // Process incoming MIDI events
    foreach (msg; getNextMidiMessages(frames)) {
      if (msg.isNoteOn) {
        int pitchClass = msg.noteNumber() % 12;
        if (!_midiNotes[pitchClass]) {
          _midiNotes[pitchClass] = true;
          _midiNoteCount++;
        }
      } else if (msg.isNoteOff) {
        int pitchClass = msg.noteNumber() % 12;
        if (_midiNotes[pitchClass]) {
          _midiNotes[pitchClass] = false;
          _midiNoteCount--;
          if (_midiNoteCount < 0) _midiNoteCount = 0;
        }
      }
    }

    // Read parameters
    const bool power = readParam!bool(Params.power);
    const float color = readParam!float(Params.color);
    const int quality = readParam!int(Params.quality);
    const bool midiMode = readParam!bool(Params.midiMode);
    const bool spectral = readParam!bool(Params.spectral);

    bool[12] scaleNotes;
    foreach (i; 0 .. 12) {
      scaleNotes[i] = readParam!bool(cast(Params)(Params.noteC + i));
    }

    // Handle preset selection changes
    const int currentPreset = readParam!int(Params.preset);
    if (_lastPreset != -1 && currentPreset != _lastPreset) {
      applyPreset(currentPreset);
    }
    _lastPreset = currentPreset;

    const float* inL = inputs[0];
    const float* inR = inputs.length > 1 ? inputs[1] : inputs[0];
    float* outL = outputs[0];
    float* outR = outputs.length > 1 ? outputs[1] : outputs[0];

    _dsp.process(
      inL, inR,
      outL, outR,
      frames,
      power,
      color,
      quality,
      midiMode,
      spectral,
      scaleNotes,
      _midiNotes
    );
  }

  void applyPreset(int index) {
    if (index < 0 || index >= presets.length) return;
    const auto p = presets[index];

    if (auto cp = cast(LinearFloatParameter) params[Params.color]) {
      cp.setFromHost(p.color);
    }
    if (auto qp = cast(EnumParameter) params[Params.quality]) {
      qp.setFromHost(p.quality);
    }
    if (auto mp = cast(BoolParameter) params[Params.midiMode]) {
      mp.setFromHost(p.midiMode);
    }
    if (auto sp = cast(BoolParameter) params[Params.spectral]) {
      sp.setFromHost(p.spectral);
    }

    foreach (i; 0 .. 12) {
      if (auto np = cast(BoolParameter) params[Params.noteC + i]) {
        np.setFromHost(p.notes[i]);
      }
    }
  }

 private:
  float _sampleRate = 44100.0f;
  KhrmDSP _dsp;
  IGraphics _gui;

  bool[12] _midiNotes = false;
  int _midiNoteCount = 0;
  int _lastPreset = -1;
}

unittest {
  import kdr.testing : benchmarkWithDefaultParams;
  benchmarkWithDefaultParams!KhrmClient();

  // Test GUI instantiation
  auto client = new KhrmClient();
  auto gui = client.createGraphics();
  assert(gui !is null);

  // Test preset switching
  client.applyPreset(1); // Sparkle Lead
  client.applyPreset(2); // Melodic Drum
  client.applyPreset(3); // Ethereal Vocal
  client.applyPreset(0); // Default
}
