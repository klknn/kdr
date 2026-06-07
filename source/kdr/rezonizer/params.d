module kdr.rezonizer.params;

import dplug.client;
import dplug.core;

/// Full Parameter set for Rezonizer.
enum Params {
  dryGain,
  wetGain,
  mode,
  decay,
  damp,
  filterBypass,
  filterHPF,
  filterLPF,
  filterPeakFreq,
  filterPeakQ,
  filterPeakGain,
  chordPreset,
  midiInput,
  midiMode,
  releaseTime,
  reverbEnable,
  reverbMix,
  reverbLength,
  reverbLows,
  reverbHighs,
  portamento,
  haasWidth,

  // Resonator 1 (Root)
  voice1Enable,
  voice1Pitch, // Absolute Root Pitch (12 to 108)
  voice1Fine,
  voice1Gain,
  voice1Pan,

  // Resonator 2 (Relative Offset)
  voice2Enable,
  voice2Pitch,
  voice2Fine,
  voice2Gain,
  voice2Pan,

  // Resonator 3 (Relative Offset)
  voice3Enable,
  voice3Pitch,
  voice3Fine,
  voice3Gain,
  voice3Pan,

  // Resonator 4 (Relative Offset)
  voice4Enable,
  voice4Pitch,
  voice4Fine,
  voice4Gain,
  voice4Pan,

  // Resonator 5 (Relative Offset)
  voice5Enable,
  voice5Pitch,
  voice5Fine,
  voice5Gain,
  voice5Pan,

  // Resonator 6 (Relative Offset)
  voice6Enable,
  voice6Pitch,
  voice6Fine,
  voice6Gain,
  voice6Pan,
}

immutable string[] modeLabels = ["Saw", "Square"];
immutable string[] chordPresetLabels = [
  "Unison",
  "Major",
  "Minor",
  "Major 7th",
  "Minor 7th",
  "Sus4",
  "Custom"
];
immutable string[] midiModeLabels = ["Normal", "Round-Robin"];

/// Builds the 52 parameters required for the Rezonizer plugin.
@nogc nothrow
Parameter[] buildRezonizerParameters() {
  Vec!Parameter params;

  // Basic Controls
  params.pushBack(mallocNew!LinearFloatParameter(Params.dryGain, "Dry Gain", "dB", -60.0f, 12.0f, 0.0f));
  params.pushBack(mallocNew!LinearFloatParameter(Params.wetGain, "Wet Gain", "dB", -60.0f, 12.0f, 0.0f));

  // Global Comb Controls
  params.pushBack(mallocNew!EnumParameter(Params.mode, "Mode (Sound Type)", modeLabels, 0));
  params.pushBack(mallocNew!LinearFloatParameter(Params.decay, "Decay", "sec", 0.01f, 10.0f, 1.0f));
  params.pushBack(mallocNew!LinearFloatParameter(Params.damp, "Color", "", 0.0f, 1.0f, 0.1f));

  // Wet Filter Controls
  params.pushBack(mallocNew!BoolParameter(Params.filterBypass, "Filter Bypass", true));
  params.pushBack(mallocNew!LogFloatParameter(Params.filterHPF, "Filter HPF Freq", "Hz", 20.0f, 2000.0f, 20.0f));
  params.pushBack(mallocNew!LogFloatParameter(Params.filterLPF, "Filter LPF Freq", "Hz", 100.0f, 20000.0f, 20000.0f));
  params.pushBack(mallocNew!LogFloatParameter(Params.filterPeakFreq, "Filter Peak Freq", "Hz", 20.0f, 20000.0f, 1000.0f));
  params.pushBack(mallocNew!LinearFloatParameter(Params.filterPeakQ, "Filter Peak Q", "", 0.1f, 10.0f, 1.0f));
  params.pushBack(mallocNew!LinearFloatParameter(Params.filterPeakGain, "Filter Peak Gain", "dB", -15.0f, 15.0f, 0.0f));

  // Chord presets & MIDI Routing
  params.pushBack(mallocNew!EnumParameter(Params.chordPreset, "Chord Preset", chordPresetLabels, 1)); // Default: Major
  params.pushBack(mallocNew!BoolParameter(Params.midiInput, "MIDI Input Enable", false));
  params.pushBack(mallocNew!EnumParameter(Params.midiMode, "MIDI Mode", midiModeLabels, 0));
  params.pushBack(mallocNew!LinearFloatParameter(Params.releaseTime, "Release / Size", "sec", 0.01f, 10.0f, 1.0f));

  // Reverb Controls
  params.pushBack(mallocNew!BoolParameter(Params.reverbEnable, "Reverb Enable", false));
  params.pushBack(mallocNew!LinearFloatParameter(Params.reverbMix, "Reverb Mix", "", 0.0f, 1.0f, 0.3f));
  params.pushBack(mallocNew!LinearFloatParameter(Params.reverbLength, "Reverb Length", "", 0.0f, 1.0f, 0.5f));
  params.pushBack(mallocNew!LinearFloatParameter(Params.reverbLows, "Reverb Lows", "", 0.0f, 1.0f, 0.2f));
  params.pushBack(mallocNew!LinearFloatParameter(Params.reverbHighs, "Reverb Highs", "", 0.0f, 1.0f, 0.2f));

  // Portamento & Haas Width
  params.pushBack(mallocNew!LinearFloatParameter(Params.portamento, "Portamento", "sec", 0.0f, 2.0f, 0.0f));
  params.pushBack(mallocNew!LinearFloatParameter(Params.haasWidth, "Haas Width", "", 0.0f, 1.0f, 0.0f));

  // Per-resonator tuning parameters
  // Resonator 1 (Absolute)
  params.pushBack(mallocNew!BoolParameter(Params.voice1Enable, "Resonator 1 Enable", true));
  params.pushBack(mallocNew!LinearFloatParameter(Params.voice1Pitch, "Resonator 1 Pitch", "note", 12.0f, 108.0f, 60.0f));
  params.pushBack(mallocNew!LinearFloatParameter(Params.voice1Fine, "Resonator 1 Fine", "cents", -100.0f, 100.0f, 0.0f));
  params.pushBack(mallocNew!LinearFloatParameter(Params.voice1Gain, "Resonator 1 Gain", "dB", -60.0f, 12.0f, 0.0f));
  params.pushBack(mallocNew!LinearFloatParameter(Params.voice1Pan, "Resonator 1 Pan", "", -1.0f, 1.0f, -0.8f));

  // Resonator 2 (Relative)
  params.pushBack(mallocNew!BoolParameter(Params.voice2Enable, "Resonator 2 Enable", true));
  params.pushBack(mallocNew!LinearFloatParameter(Params.voice2Pitch, "Resonator 2 Pitch", "st", -36.0f, 36.0f, 4.0f));
  params.pushBack(mallocNew!LinearFloatParameter(Params.voice2Fine, "Resonator 2 Fine", "cents", -100.0f, 100.0f, 0.0f));
  params.pushBack(mallocNew!LinearFloatParameter(Params.voice2Gain, "Resonator 2 Gain", "dB", -60.0f, 12.0f, 0.0f));
  params.pushBack(mallocNew!LinearFloatParameter(Params.voice2Pan, "Resonator 2 Pan", "", -1.0f, 1.0f, 0.8f));

  // Resonator 3 (Relative)
  params.pushBack(mallocNew!BoolParameter(Params.voice3Enable, "Resonator 3 Enable", true));
  params.pushBack(mallocNew!LinearFloatParameter(Params.voice3Pitch, "Resonator 3 Pitch", "st", -36.0f, 36.0f, 7.0f));
  params.pushBack(mallocNew!LinearFloatParameter(Params.voice3Fine, "Resonator 3 Fine", "cents", -100.0f, 100.0f, 0.0f));
  params.pushBack(mallocNew!LinearFloatParameter(Params.voice3Gain, "Resonator 3 Gain", "dB", -60.0f, 12.0f, 0.0f));
  params.pushBack(mallocNew!LinearFloatParameter(Params.voice3Pan, "Resonator 3 Pan", "", -1.0f, 1.0f, -0.4f));

  // Resonator 4 (Relative)
  params.pushBack(mallocNew!BoolParameter(Params.voice4Enable, "Resonator 4 Enable", true));
  params.pushBack(mallocNew!LinearFloatParameter(Params.voice4Pitch, "Resonator 4 Pitch", "st", -36.0f, 36.0f, 12.0f));
  params.pushBack(mallocNew!LinearFloatParameter(Params.voice4Fine, "Resonator 4 Fine", "cents", -100.0f, 100.0f, 0.0f));
  params.pushBack(mallocNew!LinearFloatParameter(Params.voice4Gain, "Resonator 4 Gain", "dB", -60.0f, 12.0f, 0.0f));
  params.pushBack(mallocNew!LinearFloatParameter(Params.voice4Pan, "Resonator 4 Pan", "", -1.0f, 1.0f, 0.4f));

  // Resonator 5 (Relative)
  params.pushBack(mallocNew!BoolParameter(Params.voice5Enable, "Resonator 5 Enable", true));
  params.pushBack(mallocNew!LinearFloatParameter(Params.voice5Pitch, "Resonator 5 Pitch", "st", -36.0f, 36.0f, 16.0f));
  params.pushBack(mallocNew!LinearFloatParameter(Params.voice5Fine, "Resonator 5 Fine", "cents", -100.0f, 100.0f, 0.0f));
  params.pushBack(mallocNew!LinearFloatParameter(Params.voice5Gain, "Resonator 5 Gain", "dB", -60.0f, 12.0f, 0.0f));
  params.pushBack(mallocNew!LinearFloatParameter(Params.voice5Pan, "Resonator 5 Pan", "", -1.0f, 1.0f, -0.1f));

  // Resonator 6 (Relative)
  params.pushBack(mallocNew!BoolParameter(Params.voice6Enable, "Resonator 6 Enable", true));
  params.pushBack(mallocNew!LinearFloatParameter(Params.voice6Pitch, "Resonator 6 Pitch", "st", -36.0f, 36.0f, 19.0f));
  params.pushBack(mallocNew!LinearFloatParameter(Params.voice6Fine, "Resonator 6 Fine", "cents", -100.0f, 100.0f, 0.0f));
  params.pushBack(mallocNew!LinearFloatParameter(Params.voice6Gain, "Resonator 6 Gain", "dB", -60.0f, 12.0f, 0.0f));
  params.pushBack(mallocNew!LinearFloatParameter(Params.voice6Pan, "Resonator 6 Pan", "", -1.0f, 1.0f, 0.1f));

  return params.releaseData();
}
