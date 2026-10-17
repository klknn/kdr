module kdr.khrm.params;

import dplug.client;
import dplug.core;

/// Parameter IDs for khrm plugin.
enum Params {
  power,        // Master On/Off (bypass)
  color,        // Color knob (0.0 to 2.0: 0% dry, 100% saturated color, 200% extreme resonance)
  quality,      // Latency/Quality (0 = Low Latency, 1 = High Quality)
  midiMode,     // MIDI input follow toggle
  spectral,     // Spectral sweetening mode toggle

  // 12 Note Scale keyboard buttons
  noteC,
  noteCSharp,
  noteD,
  noteDSharp,
  noteE,
  noteF,
  noteFSharp,
  noteG,
  noteGSharp,
  noteA,
  noteASharp,
  noteB,

  // Preset selector
  preset,
}

immutable string[12] noteNames = [
  "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"
];

immutable string[2] qualityLabels = [
  "LOW LATENCY",
  "HIGH QUALITY"
];

immutable string[6] presetNames = [
  "Colour Bass (E Minor)",
  "Sparkle Lead (C Major)",
  "Melodic Drum (Pentatonic)",
  "Ethereal Vocal (Dreamy 7th)",
  "Color Growl (Chromatic)",
  "MIDI Tracked (Dynamic)"
];

/// Preset definitions for 12 notes and parameters.
struct KhrmPresetData {
  string name;
  float color;
  int quality;
  bool midiMode;
  bool spectral;
  bool[12] notes; // C, C#, D, D#, E, F, F#, G, G#, A, A#, B
}

immutable KhrmPresetData[6] presets = [
  // 1. Colour Bass: Heavy bass in E Minor (E, G, A, B, D)
  KhrmPresetData(
    "Colour Bass (E Minor)",
    0.85f, 1, false, true,
    [false, false, true, false, true, false, false, true, false, true, false, true]
  ),
  // 2. Sparkle Lead: Bright C Major Pentatonic (C, D, E, G, A)
  KhrmPresetData(
    "Sparkle Lead (C Major)",
    0.95f, 1, false, true,
    [true, false, true, false, true, false, false, true, false, true, false, false]
  ),
  // 3. Melodic Drum: Punchy low-latency tuner for kicks & snares (A, C, E, G)
  KhrmPresetData(
    "Melodic Drum (Pentatonic)",
    0.60f, 0, false, true,
    [true, false, false, false, true, false, false, true, false, true, false, false]
  ),
  // 4. Ethereal Vocal: Dreamy 7th chords with long tails and spectral warmth (C, E, G, B, D, F#)
  KhrmPresetData(
    "Ethereal Vocal (Dreamy 7th)",
    1.15f, 1, false, false,
    [true, false, true, false, true, false, true, true, false, false, false, true]
  ),
  // 5. Color Growl: Chromatic all-note resonance with drive
  KhrmPresetData(
    "Color Growl (Chromatic)",
    0.70f, 1, false, true,
    [true, true, true, true, true, true, true, true, true, true, true, true]
  ),
  // 6. MIDI Tracked: Dynamic MIDI keyboard tracking
  KhrmPresetData(
    "MIDI Tracked (Dynamic)",
    0.90f, 0, true, true,
    [false, false, true, false, true, false, false, true, false, true, false, true]
  )
];

/// Build all parameters for khrm.
@nogc nothrow
Parameter[] buildKhrmParameters() {
  Vec!Parameter params;

  // Master Power / On-Off
  params.pushBack(mallocNew!BoolParameter(Params.power, "Power", true));

  // Color knob: 0% .. 200% (0.0 .. 2.0)
  params.pushBack(mallocNew!LinearFloatParameter(Params.color, "Color", "%", 0.0f, 2.0f, 0.85f));

  // Latency / Quality
  params.pushBack(mallocNew!EnumParameter(Params.quality, "Quality", qualityLabels, 1));

  // MIDI input mode
  params.pushBack(mallocNew!BoolParameter(Params.midiMode, "MIDI", false));

  // Spectral sweetening mode
  params.pushBack(mallocNew!BoolParameter(Params.spectral, "Spectral", true));

  // 12 Notes (Default to Preset 0: E Minor Pentatonic)
  const auto defNotes = presets[0].notes;
  foreach (i; 0 .. 12) {
    params.pushBack(mallocNew!BoolParameter(
      cast(Params)(Params.noteC + i),
      noteNames[i],
      defNotes[i]
    ));
  }

  // Preset selector
  params.pushBack(mallocNew!EnumParameter(Params.preset, "Preset", presetNames, 0));

  return params.releaseData();
}
