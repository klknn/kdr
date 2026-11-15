/**
 * Stutter Edit 2 parameter definitions and RegisterBuilder bindings.
 *
 * Copyright: kdr 2026.
 * License: Boost License 1.0.
 */
module kdr.stutter.params;

import std.traits : EnumMembers;
import dplug.client.params : BoolParameter, EnumParameter, GainParameter,
  IntegerParameter, LinearFloatParameter, LogFloatParameter, Parameter;
import dplug.core.nogc : mallocNew;

import kdr.params : RegisterBuilder, buildParams, typedParam;

// =============================================================================
// Helper Enums & Labels
// =============================================================================

/// 12 TVM Preset Curve Shapes
enum TVMCurvePreset : int {
  flatLow = 0,
  flatHigh = 1,
  rampUp = 2,
  rampDown = 3,
  expRise = 4,
  expFall = 5,
  sine1x = 6,
  sine2x = 7,
  stepUp = 8,
  stepDown = 9,
  spike = 10,
  chaos = 11,
}

static immutable string[] tvmCurvePresetNames = [
  "Flat Low",
  "Flat High",
  "Ramp Up",
  "Ramp Down",
  "Exp Rise",
  "Exp Fall",
  "Sine 1x",
  "Sine 2x",
  "Step Up",
  "Step Down",
  "Spike",
  "Chaos",
];

/// Gesture Release Modes
enum ReleaseMode : int {
  instant = 0,
  latch = 1,
  fullGesture = 2,
  onGrid = 3,
}

static immutable string[] releaseModeNames = [
  "Instant",
  "Latch",
  "Full Gesture",
  "On Grid",
];

/// Quantize Grid Divisions
enum QuantizeGrid : int {
  instant = 0,
  grid1_16 = 1,
  grid1_8 = 2,
  grid1_4 = 3,
  grid1_2 = 4,
  grid1_1 = 5,
}

static immutable string[] quantizeGridNames = [
  "Instant / Off",
  "1/16",
  "1/8",
  "1/4",
  "1/2",
  "1 Bar",
];

static immutable double[] quantizeGridBeats = [
  0.0,
  0.25,
  0.5,
  1.0,
  2.0,
  4.0,
];

/// Gesture Length
enum GestureLength : int {
  len1_8 = 0,
  len1_4 = 1,
  len1_2 = 2,
  len1_1 = 3,
  len2_1 = 4,
  len4_1 = 5,
  len8_1 = 6,
}

static immutable string[] gestureLengthNames = [
  "1/8 Bar",
  "1/4 Bar",
  "1/2 Bar",
  "1 Bar",
  "2 Bars",
  "4 Bars",
  "8 Bars",
];

static immutable double[] gestureLengthBeats = [
  0.5,
  1.0,
  2.0,
  4.0,
  8.0,
  16.0,
  32.0,
];

/// Auto Mode Retrigger Rate
enum AutoRate : int {
  rate1_4Bar = 0,
  rate1_2Bar = 1,
  rate1Bar = 2,
  rate2Bars = 3,
  rate4Bars = 4,
  rate8Bars = 5,
}

static immutable string[] autoRateNames = [
  "1/4 Bar",
  "1/2 Bar",
  "1 Bar",
  "2 Bars",
  "4 Bars",
  "8 Bars",
];

static immutable double[] autoRateBeats = [
  1.0,
  2.0,
  4.0,
  8.0,
  16.0,
  32.0,
];

/// 19 Stutter Rhythmic Subdivisions (including triplets and dotted notes)
enum StutterSubdivision : int {
  sub1_1 = 0,
  sub1_2 = 1,
  sub1_4 = 2,
  sub1_8 = 3,
  sub1_16 = 4,
  sub1_32 = 5,
  sub1_64 = 6,
  sub1_128 = 7,
  sub1_2T = 8,
  sub1_4T = 9,
  sub1_8T = 10,
  sub1_16T = 11,
  sub1_32T = 12,
  sub1_64T = 13,
  sub1_2D = 14,
  sub1_4D = 15,
  sub1_8D = 16,
  sub1_16D = 17,
  sub1_32D = 18,
}

static immutable string[] stutterSubdivisionNames = [
  "1/1",
  "1/2",
  "1/4",
  "1/8",
  "1/16",
  "1/32",
  "1/64",
  "1/128",
  "1/2T",
  "1/4T",
  "1/8T",
  "1/16T",
  "1/32T",
  "1/64T",
  "1/2D",
  "1/4D",
  "1/8D",
  "1/16D",
  "1/32D",
];

static immutable double[] stutterSubdivisionBeats = [
  4.0,
  2.0,
  1.0,
  0.5,
  0.25,
  0.125,
  0.0625,
  0.03125,
  4.0 / 3.0,
  2.0 / 3.0,
  1.0 / 3.0,
  0.5 / 3.0,
  0.25 / 3.0,
  0.125 / 3.0,
  3.0,
  1.5,
  0.75,
  0.375,
  0.1875,
];

/// Stutter Rate Quantization Mode
enum StutterQuantizeMode : int {
  freeSweep = 0,
  steppedRhythmic = 1,
  tripletsOnly = 2,
  dottedOnly = 3,
}

static immutable string[] stutterQuantizeModeNames = [
  "Free Sweep",
  "Stepped Rhythmic",
  "Triplets Only",
  "Dotted Only",
];

/// Buffer Playback Direction
enum BufferDirection : int {
  forward = 0,
  reverse = 1,
  pendulum = 2,
}

static immutable string[] bufferDirectionNames = [
  "Forward",
  "Reverse",
  "Pendulum",
];

/// Gate Rhythmic Subdivisions
enum GateSubdivision : int {
  gate1_64 = 0,
  gate1_32 = 1,
  gate1_16 = 2,
  gate1_8 = 3,
  gate1_4 = 4,
  gate1_2 = 5,
  gate1_1 = 6,
}

static immutable string[] gateSubdivisionNames = [
  "1/64",
  "1/32",
  "1/16",
  "1/8",
  "1/4",
  "1/2",
  "1 Bar",
];

static immutable double[] gateSubdivisionBeats = [
  0.0625,
  0.125,
  0.25,
  0.5,
  1.0,
  2.0,
  4.0,
];

/// Filter Types
enum FilterType : int {
  lowpass12 = 0,
  lowpass24Ladder = 1,
  highpass12 = 2,
  bandpass12 = 3,
}

static immutable string[] filterTypeNames = [
  "Lowpass 12dB",
  "Lowpass 24dB Ladder",
  "Highpass 12dB",
  "Bandpass 12dB",
];

/// Phaser Pole Count Stages
enum PhaserStages : int {
  poles4 = 0,
  poles6 = 1,
  poles8 = 2,
  poles12 = 3,
}

static immutable string[] phaserStagesNames = [
  "4 Poles",
  "6 Poles",
  "8 Poles",
  "12 Poles",
];

/// Delay Rhythmic Subdivisions
enum DelaySubdivision : int {
  del1_32 = 0,
  del1_16D = 1,
  del1_16 = 2,
  del1_16T = 3,
  del1_8D = 4,
  del1_8 = 5,
  del1_8T = 6,
  del1_4D = 7,
  del1_4 = 8,
  del1_2 = 9,
}

static immutable string[] delaySubdivisionNames = [
  "1/32",
  "1/16D",
  "1/16",
  "1/16T",
  "1/8D",
  "1/8",
  "1/8T",
  "1/4D",
  "1/4",
  "1/2",
];

static immutable double[] delaySubdivisionBeats = [
  0.125,
  0.375,
  0.25,
  0.5 / 3.0,
  0.75,
  0.5,
  1.0 / 3.0,
  1.5,
  1.0,
  2.0,
];

/// 14 Rack Module Slot Identifiers + Master Limiter
enum ModuleSlot : int {
  stutter = 0,
  buffer = 1,
  gate = 2,
  pan = 3,
  tapeStop = 4,
  filter = 5,
  lofi = 6,
  distort = 7,
  comb = 8,
  chorus = 9,
  flanger = 10,
  phaser = 11,
  reverb = 12,
  delay = 13,
  limiter = 14,
}

static immutable string[] moduleSlotNames = [
  "STUTTER",
  "BUFFER",
  "GATE",
  "PAN",
  "TAPE STOP",
  "FILTER",
  "LO-FI",
  "DISTORT",
  "COMB",
  "CHORUS",
  "FLANGER",
  "PHASER",
  "REVERB",
  "DELAY",
  "LIMITER",
];

/// Color coding for left module rack and TVM curve displays
static immutable uint[] moduleColors = [
  0x00E5FF, // Stutter: Cyan
  0x00A3FF, // Buffer: Deep Sky Blue
  0x00F5D4, // Gate: Teal
  0x00F090, // Pan: Spring Green
  0x76FF03, // Tape Stop: Neon Lime
  0xFFD600, // Filter: Amber
  0xFF9100, // Lo-Fi: Bright Orange
  0xFF3D00, // Distort: Coral Red
  0xFF1493, // Comb: Hot Pink
  0xD500F9, // Chorus: Violet Magenta
  0x9D4EDD, // Flanger: Electric Purple
  0x651FFF, // Phaser: Neon Indigo
  0x00B4D8, // Reverb: Ocean Blue
  0x2EC4B6, // Delay: Aquamarine
  0xE2E8F0, // Limiter: Silver
];

// =============================================================================
// Complete Parameter Enum (137 Parameters)
// =============================================================================

@RegisterBuilder!ParamBuilder
enum Params : int {
  // --- 1. Global / Gesture / Auto Mode Controls (9) ---
  autoMode = 0,
  autoRate,
  gestureLength,
  quantizeGrid,
  releaseMode,
  activeGesture,
  bankPreset,
  masterDryWet,
  masterOutputGain,

  // --- 2. Stutter Module (8) ---
  stutterEnable,
  stutterCurve,
  stutterCurveTension,
  stutterRateStart,
  stutterRateEnd,
  stutterQuantize,
  stutterGate,
  stutterRelease,

  // --- 3. Buffer Module (10) ---
  bufferEnable,
  bufferCurve,
  bufferCurveTension,
  bufferPositionMin,
  bufferPositionMax,
  bufferDirection,
  bufferStereoOffset,
  bufferPitchMin,
  bufferPitchMax,
  bufferJitter,

  // --- 4. FX Gate Module (8) ---
  gateEnable,
  gateCurve,
  gateCurveTension,
  gateSubdivision,
  gateWidthMin,
  gateWidthMax,
  gateTail,
  gateMix,

  // --- 5. FX Pan Module (8) ---
  panEnable,
  panCurve,
  panCurveTension,
  panCenterMin,
  panCenterMax,
  panWidthMin,
  panWidthMax,
  panMix,

  // --- 6. FX Tape Stop Module (7) ---
  tapeStopEnable,
  tapeStopCurve,
  tapeStopCurveTension,
  tapeStopSlowdownMin,
  tapeStopSlowdownMax,
  tapeStopPlunge,
  tapeStopMix,

  // --- 7. FX Filter Module (9) ---
  filterEnable,
  filterCurve,
  filterCurveTension,
  filterType,
  filterCutoffMin,
  filterCutoffMax,
  filterResonance,
  filterDrive,
  filterMix,

  // --- 8. FX Lo-Fi Module (9) ---
  lofiEnable,
  lofiCurve,
  lofiCurveTension,
  lofiBitDepthMin,
  lofiBitDepthMax,
  lofiDownsampleMin,
  lofiDownsampleMax,
  lofiGrit,
  lofiMix,

  // --- 9. FX Distort Module (10) ---
  distortEnable,
  distortCurve,
  distortCurveTension,
  distortCrossover,
  distortDriveLowMin,
  distortDriveLowMax,
  distortDriveHighMin,
  distortDriveHighMax,
  distortTone,
  distortMix,

  // --- 10. FX Comb Module (9) ---
  combEnable,
  combCurve,
  combCurveTension,
  combFreqMin,
  combFreqMax,
  combFeedback,
  combDamping,
  combStereoPhase,
  combMix,

  // --- 11. FX Chorus Module (9) ---
  chorusEnable,
  chorusCurve,
  chorusCurveTension,
  chorusRate,
  chorusDepthMin,
  chorusDepthMax,
  chorusFeedback,
  chorusWidth,
  chorusMix,

  // --- 12. FX Flanger Module (9) ---
  flangerEnable,
  flangerCurve,
  flangerCurveTension,
  flangerRate,
  flangerDepthMin,
  flangerDepthMax,
  flangerFeedback,
  flangerStereoPhase,
  flangerMix,

  // --- 13. FX Phaser Module (9) ---
  phaserEnable,
  phaserCurve,
  phaserCurveTension,
  phaserRate,
  phaserStages,
  phaserCenterMin,
  phaserCenterMax,
  phaserFeedback,
  phaserMix,

  // --- 14. FX Reverb Module (9) ---
  reverbEnable,
  reverbCurve,
  reverbCurveTension,
  reverbSizeMin,
  reverbSizeMax,
  reverbDamping,
  reverbPreDelay,
  reverbFreeze,
  reverbMix,

  // --- 15. End-of-Chain Delay Module (10) ---
  delayEnable,
  delayCurve,
  delayCurveTension,
  delayTimeL,
  delayTimeR,
  delayFeedbackMin,
  delayFeedbackMax,
  delayCross,
  delayDamp,
  delayMix,

  // --- 16. Master Output Limiter (4) ---
  limiterEnable,
  limiterThreshold,
  limiterCeiling,
  limiterRelease,
}

// =============================================================================
// ParamBuilder Struct with Type-Safe Static Methods
// =============================================================================

struct ParamBuilder {
  static @nogc nothrow:

  // --- Global / Gesture Controls ---
  static auto autoMode() {
    return mallocNew!BoolParameter(Params.autoMode, "Auto Mode", true);
  }
  static auto autoRate() {
    return mallocNew!EnumParameter(Params.autoRate, "Auto Rate", autoRateNames, AutoRate.rate1Bar);
  }
  static auto gestureLength() {
    return mallocNew!EnumParameter(Params.gestureLength, "Gesture Length", gestureLengthNames, GestureLength.len1_1);
  }
  static auto quantizeGrid() {
    return mallocNew!EnumParameter(Params.quantizeGrid, "Quantize Grid", quantizeGridNames, QuantizeGrid.grid1_4);
  }
  static auto releaseMode() {
    return mallocNew!EnumParameter(Params.releaseMode, "Release Mode", releaseModeNames, ReleaseMode.fullGesture);
  }
  static auto activeGesture() {
    return mallocNew!IntegerParameter(Params.activeGesture, "Active Gesture", "note", 0, 23, 0);
  }
  static auto bankPreset() {
    return mallocNew!IntegerParameter(Params.bankPreset, "Preset Bank", "preset", 0, 15, 0);
  }
  static auto masterDryWet() {
    return mallocNew!LinearFloatParameter(Params.masterDryWet, "Master Dry/Wet", "%", 0.0f, 1.0f, 1.0f);
  }
  static auto masterOutputGain() {
    return mallocNew!LinearFloatParameter(Params.masterOutputGain, "Master Gain", "dB", -24.0f, 12.0f, 0.0f);
  }

  // --- Stutter Module ---
  static auto stutterEnable() {
    return mallocNew!BoolParameter(Params.stutterEnable, "Stutter Enable", true);
  }
  static auto stutterCurve() {
    return mallocNew!EnumParameter(Params.stutterCurve, "Stutter Curve", tvmCurvePresetNames, TVMCurvePreset.rampUp);
  }
  static auto stutterCurveTension() {
    return mallocNew!LinearFloatParameter(Params.stutterCurveTension, "Stutter Curve Tension", "", -1.0f, 1.0f, 0.0f);
  }
  static auto stutterRateStart() {
    return mallocNew!EnumParameter(Params.stutterRateStart, "Stutter Rate Start", stutterSubdivisionNames, StutterSubdivision.sub1_8);
  }
  static auto stutterRateEnd() {
    return mallocNew!EnumParameter(Params.stutterRateEnd, "Stutter Rate End", stutterSubdivisionNames, StutterSubdivision.sub1_64);
  }
  static auto stutterQuantize() {
    return mallocNew!EnumParameter(Params.stutterQuantize, "Stutter Quantize", stutterQuantizeModeNames, StutterQuantizeMode.steppedRhythmic);
  }
  static auto stutterGate() {
    return mallocNew!LinearFloatParameter(Params.stutterGate, "Stutter Gate", "%", 0.05f, 1.0f, 1.0f);
  }
  static auto stutterRelease() {
    return mallocNew!LinearFloatParameter(Params.stutterRelease, "Stutter Crossfade", "ms", 1.0f, 30.0f, 5.0f);
  }

  // --- Buffer Module ---
  static auto bufferEnable() {
    return mallocNew!BoolParameter(Params.bufferEnable, "Buffer Enable", true);
  }
  static auto bufferCurve() {
    return mallocNew!EnumParameter(Params.bufferCurve, "Buffer Curve", tvmCurvePresetNames, TVMCurvePreset.rampUp);
  }
  static auto bufferCurveTension() {
    return mallocNew!LinearFloatParameter(Params.bufferCurveTension, "Buffer Curve Tension", "", -1.0f, 1.0f, 0.0f);
  }
  static auto bufferPositionMin() {
    return mallocNew!LinearFloatParameter(Params.bufferPositionMin, "Buffer Pos Min", "%", 0.0f, 1.0f, 0.0f);
  }
  static auto bufferPositionMax() {
    return mallocNew!LinearFloatParameter(Params.bufferPositionMax, "Buffer Pos Max", "%", 0.0f, 1.0f, 1.0f);
  }
  static auto bufferDirection() {
    return mallocNew!EnumParameter(Params.bufferDirection, "Buffer Direction", bufferDirectionNames, BufferDirection.forward);
  }
  static auto bufferStereoOffset() {
    return mallocNew!LinearFloatParameter(Params.bufferStereoOffset, "Buffer Stereo Offset", "ms", -50.0f, 50.0f, 0.0f);
  }
  static auto bufferPitchMin() {
    return mallocNew!LinearFloatParameter(Params.bufferPitchMin, "Buffer Pitch Min", "st", -24.0f, 24.0f, 0.0f);
  }
  static auto bufferPitchMax() {
    return mallocNew!LinearFloatParameter(Params.bufferPitchMax, "Buffer Pitch Max", "st", -24.0f, 24.0f, 0.0f);
  }
  static auto bufferJitter() {
    return mallocNew!LinearFloatParameter(Params.bufferJitter, "Buffer Jitter", "%", 0.0f, 1.0f, 0.0f);
  }

  // --- FX Gate ---
  static auto gateEnable() {
    return mallocNew!BoolParameter(Params.gateEnable, "Gate Enable", false);
  }
  static auto gateCurve() {
    return mallocNew!EnumParameter(Params.gateCurve, "Gate Curve", tvmCurvePresetNames, TVMCurvePreset.rampUp);
  }
  static auto gateCurveTension() {
    return mallocNew!LinearFloatParameter(Params.gateCurveTension, "Gate Curve Tension", "", -1.0f, 1.0f, 0.0f);
  }
  static auto gateSubdivision() {
    return mallocNew!EnumParameter(Params.gateSubdivision, "Gate Subdivision", gateSubdivisionNames, GateSubdivision.gate1_16);
  }
  static auto gateWidthMin() {
    return mallocNew!LinearFloatParameter(Params.gateWidthMin, "Gate Width Min", "%", 0.05f, 0.95f, 0.2f);
  }
  static auto gateWidthMax() {
    return mallocNew!LinearFloatParameter(Params.gateWidthMax, "Gate Width Max", "%", 0.05f, 0.95f, 0.8f);
  }
  static auto gateTail() {
    return mallocNew!LinearFloatParameter(Params.gateTail, "Gate Tail", "ms", 0.1f, 50.0f, 5.0f);
  }
  static auto gateMix() {
    return mallocNew!LinearFloatParameter(Params.gateMix, "Gate Mix", "%", 0.0f, 1.0f, 1.0f);
  }

  // --- FX Pan ---
  static auto panEnable() {
    return mallocNew!BoolParameter(Params.panEnable, "Pan Enable", false);
  }
  static auto panCurve() {
    return mallocNew!EnumParameter(Params.panCurve, "Pan Curve", tvmCurvePresetNames, TVMCurvePreset.sine1x);
  }
  static auto panCurveTension() {
    return mallocNew!LinearFloatParameter(Params.panCurveTension, "Pan Curve Tension", "", -1.0f, 1.0f, 0.0f);
  }
  static auto panCenterMin() {
    return mallocNew!LinearFloatParameter(Params.panCenterMin, "Pan Center Min", "", -1.0f, 1.0f, -1.0f);
  }
  static auto panCenterMax() {
    return mallocNew!LinearFloatParameter(Params.panCenterMax, "Pan Center Max", "", -1.0f, 1.0f, 1.0f);
  }
  static auto panWidthMin() {
    return mallocNew!LinearFloatParameter(Params.panWidthMin, "Pan Width Min", "%", 0.0f, 2.0f, 1.0f);
  }
  static auto panWidthMax() {
    return mallocNew!LinearFloatParameter(Params.panWidthMax, "Pan Width Max", "%", 0.0f, 2.0f, 1.0f);
  }
  static auto panMix() {
    return mallocNew!LinearFloatParameter(Params.panMix, "Pan Mix", "%", 0.0f, 1.0f, 1.0f);
  }

  // --- FX Tape Stop ---
  static auto tapeStopEnable() {
    return mallocNew!BoolParameter(Params.tapeStopEnable, "Tape Stop Enable", false);
  }
  static auto tapeStopCurve() {
    return mallocNew!EnumParameter(Params.tapeStopCurve, "Tape Stop Curve", tvmCurvePresetNames, TVMCurvePreset.expFall);
  }
  static auto tapeStopCurveTension() {
    return mallocNew!LinearFloatParameter(Params.tapeStopCurveTension, "Tape Stop Curve Tension", "", -1.0f, 1.0f, 0.0f);
  }
  static auto tapeStopSlowdownMin() {
    return mallocNew!LinearFloatParameter(Params.tapeStopSlowdownMin, "Tape Slowdown Min", "%", 0.0f, 1.0f, 0.0f);
  }
  static auto tapeStopSlowdownMax() {
    return mallocNew!LinearFloatParameter(Params.tapeStopSlowdownMax, "Tape Slowdown Max", "%", 0.0f, 1.0f, 1.0f);
  }
  static auto tapeStopPlunge() {
    return mallocNew!BoolParameter(Params.tapeStopPlunge, "Tape Stop Plunge", false);
  }
  static auto tapeStopMix() {
    return mallocNew!LinearFloatParameter(Params.tapeStopMix, "Tape Stop Mix", "%", 0.0f, 1.0f, 1.0f);
  }

  // --- FX Filter ---
  static auto filterEnable() {
    return mallocNew!BoolParameter(Params.filterEnable, "Filter Enable", false);
  }
  static auto filterCurve() {
    return mallocNew!EnumParameter(Params.filterCurve, "Filter Curve", tvmCurvePresetNames, TVMCurvePreset.rampUp);
  }
  static auto filterCurveTension() {
    return mallocNew!LinearFloatParameter(Params.filterCurveTension, "Filter Curve Tension", "", -1.0f, 1.0f, 0.0f);
  }
  static auto filterType() {
    return mallocNew!EnumParameter(Params.filterType, "Filter Type", filterTypeNames, FilterType.lowpass24Ladder);
  }
  static auto filterCutoffMin() {
    return mallocNew!LogFloatParameter(Params.filterCutoffMin, "Filter Cutoff Min", "Hz", 20.0, 20000.0, 200.0);
  }
  static auto filterCutoffMax() {
    return mallocNew!LogFloatParameter(Params.filterCutoffMax, "Filter Cutoff Max", "Hz", 20.0, 20000.0, 8000.0);
  }
  static auto filterResonance() {
    return mallocNew!LinearFloatParameter(Params.filterResonance, "Filter Resonance", "", 0.0f, 1.0f, 0.4f);
  }
  static auto filterDrive() {
    return mallocNew!LinearFloatParameter(Params.filterDrive, "Filter Pre-Drive", "dB", 0.0f, 24.0f, 0.0f);
  }
  static auto filterMix() {
    return mallocNew!LinearFloatParameter(Params.filterMix, "Filter Mix", "%", 0.0f, 1.0f, 1.0f);
  }

  // --- FX Lo-Fi ---
  static auto lofiEnable() {
    return mallocNew!BoolParameter(Params.lofiEnable, "Lo-Fi Enable", false);
  }
  static auto lofiCurve() {
    return mallocNew!EnumParameter(Params.lofiCurve, "Lo-Fi Curve", tvmCurvePresetNames, TVMCurvePreset.rampDown);
  }
  static auto lofiCurveTension() {
    return mallocNew!LinearFloatParameter(Params.lofiCurveTension, "Lo-Fi Curve Tension", "", -1.0f, 1.0f, 0.0f);
  }
  static auto lofiBitDepthMin() {
    return mallocNew!LinearFloatParameter(Params.lofiBitDepthMin, "Lo-Fi Bits Min", "bits", 2.0f, 24.0f, 6.0f);
  }
  static auto lofiBitDepthMax() {
    return mallocNew!LinearFloatParameter(Params.lofiBitDepthMax, "Lo-Fi Bits Max", "bits", 2.0f, 24.0f, 16.0f);
  }
  static auto lofiDownsampleMin() {
    return mallocNew!LinearFloatParameter(Params.lofiDownsampleMin, "Lo-Fi Downsample Min", "x", 1.0f, 32.0f, 1.0f);
  }
  static auto lofiDownsampleMax() {
    return mallocNew!LinearFloatParameter(Params.lofiDownsampleMax, "Lo-Fi Downsample Max", "x", 1.0f, 32.0f, 8.0f);
  }
  static auto lofiGrit() {
    return mallocNew!LinearFloatParameter(Params.lofiGrit, "Lo-Fi Grit", "%", 0.0f, 1.0f, 0.0f);
  }
  static auto lofiMix() {
    return mallocNew!LinearFloatParameter(Params.lofiMix, "Lo-Fi Mix", "%", 0.0f, 1.0f, 1.0f);
  }

  // --- FX Distort ---
  static auto distortEnable() {
    return mallocNew!BoolParameter(Params.distortEnable, "Distort Enable", false);
  }
  static auto distortCurve() {
    return mallocNew!EnumParameter(Params.distortCurve, "Distort Curve", tvmCurvePresetNames, TVMCurvePreset.rampUp);
  }
  static auto distortCurveTension() {
    return mallocNew!LinearFloatParameter(Params.distortCurveTension, "Distort Curve Tension", "", -1.0f, 1.0f, 0.0f);
  }
  static auto distortCrossover() {
    return mallocNew!LogFloatParameter(Params.distortCrossover, "Distort X-Over", "Hz", 100.0, 6000.0, 800.0);
  }
  static auto distortDriveLowMin() {
    return mallocNew!LinearFloatParameter(Params.distortDriveLowMin, "Distort Low Drive Min", "%", 0.0f, 1.0f, 0.1f);
  }
  static auto distortDriveLowMax() {
    return mallocNew!LinearFloatParameter(Params.distortDriveLowMax, "Distort Low Drive Max", "%", 0.0f, 1.0f, 0.7f);
  }
  static auto distortDriveHighMin() {
    return mallocNew!LinearFloatParameter(Params.distortDriveHighMin, "Distort High Drive Min", "%", 0.0f, 1.0f, 0.2f);
  }
  static auto distortDriveHighMax() {
    return mallocNew!LinearFloatParameter(Params.distortDriveHighMax, "Distort High Drive Max", "%", 0.0f, 1.0f, 0.9f);
  }
  static auto distortTone() {
    return mallocNew!LinearFloatParameter(Params.distortTone, "Distort Tone", "", -1.0f, 1.0f, 0.0f);
  }
  static auto distortMix() {
    return mallocNew!LinearFloatParameter(Params.distortMix, "Distort Mix", "%", 0.0f, 1.0f, 1.0f);
  }

  // --- FX Comb ---
  static auto combEnable() {
    return mallocNew!BoolParameter(Params.combEnable, "Comb Enable", false);
  }
  static auto combCurve() {
    return mallocNew!EnumParameter(Params.combCurve, "Comb Curve", tvmCurvePresetNames, TVMCurvePreset.rampUp);
  }
  static auto combCurveTension() {
    return mallocNew!LinearFloatParameter(Params.combCurveTension, "Comb Curve Tension", "", -1.0f, 1.0f, 0.0f);
  }
  static auto combFreqMin() {
    return mallocNew!LogFloatParameter(Params.combFreqMin, "Comb Freq Min", "Hz", 20.0, 2000.0, 80.0);
  }
  static auto combFreqMax() {
    return mallocNew!LogFloatParameter(Params.combFreqMax, "Comb Freq Max", "Hz", 20.0, 2000.0, 800.0);
  }
  static auto combFeedback() {
    return mallocNew!LinearFloatParameter(Params.combFeedback, "Comb Feedback", "", -0.98f, 0.98f, 0.75f);
  }
  static auto combDamping() {
    return mallocNew!LinearFloatParameter(Params.combDamping, "Comb Damping", "%", 0.0f, 1.0f, 0.2f);
  }
  static auto combStereoPhase() {
    return mallocNew!LinearFloatParameter(Params.combStereoPhase, "Comb Stereo Phase", "deg", 0.0f, 180.0f, 45.0f);
  }
  static auto combMix() {
    return mallocNew!LinearFloatParameter(Params.combMix, "Comb Mix", "%", 0.0f, 1.0f, 0.5f);
  }

  // --- FX Chorus ---
  static auto chorusEnable() {
    return mallocNew!BoolParameter(Params.chorusEnable, "Chorus Enable", false);
  }
  static auto chorusCurve() {
    return mallocNew!EnumParameter(Params.chorusCurve, "Chorus Curve", tvmCurvePresetNames, TVMCurvePreset.sine1x);
  }
  static auto chorusCurveTension() {
    return mallocNew!LinearFloatParameter(Params.chorusCurveTension, "Chorus Curve Tension", "", -1.0f, 1.0f, 0.0f);
  }
  static auto chorusRate() {
    return mallocNew!LinearFloatParameter(Params.chorusRate, "Chorus Rate", "Hz", 0.05f, 5.0f, 0.6f);
  }
  static auto chorusDepthMin() {
    return mallocNew!LinearFloatParameter(Params.chorusDepthMin, "Chorus Depth Min", "%", 0.0f, 1.0f, 0.2f);
  }
  static auto chorusDepthMax() {
    return mallocNew!LinearFloatParameter(Params.chorusDepthMax, "Chorus Depth Max", "%", 0.0f, 1.0f, 0.8f);
  }
  static auto chorusFeedback() {
    return mallocNew!LinearFloatParameter(Params.chorusFeedback, "Chorus Feedback", "%", 0.0f, 0.95f, 0.25f);
  }
  static auto chorusWidth() {
    return mallocNew!LinearFloatParameter(Params.chorusWidth, "Chorus Width", "%", 0.0f, 1.0f, 1.0f);
  }
  static auto chorusMix() {
    return mallocNew!LinearFloatParameter(Params.chorusMix, "Chorus Mix", "%", 0.0f, 1.0f, 0.5f);
  }

  // --- FX Flanger ---
  static auto flangerEnable() {
    return mallocNew!BoolParameter(Params.flangerEnable, "Flanger Enable", false);
  }
  static auto flangerCurve() {
    return mallocNew!EnumParameter(Params.flangerCurve, "Flanger Curve", tvmCurvePresetNames, TVMCurvePreset.rampUp);
  }
  static auto flangerCurveTension() {
    return mallocNew!LinearFloatParameter(Params.flangerCurveTension, "Flanger Curve Tension", "", -1.0f, 1.0f, 0.0f);
  }
  static auto flangerRate() {
    return mallocNew!LinearFloatParameter(Params.flangerRate, "Flanger Rate", "Hz", 0.02f, 4.0f, 0.25f);
  }
  static auto flangerDepthMin() {
    return mallocNew!LinearFloatParameter(Params.flangerDepthMin, "Flanger Depth Min", "ms", 0.1f, 5.0f, 0.5f);
  }
  static auto flangerDepthMax() {
    return mallocNew!LinearFloatParameter(Params.flangerDepthMax, "Flanger Depth Max", "ms", 0.1f, 5.0f, 3.5f);
  }
  static auto flangerFeedback() {
    return mallocNew!LinearFloatParameter(Params.flangerFeedback, "Flanger Feedback", "", -0.95f, 0.95f, 0.7f);
  }
  static auto flangerStereoPhase() {
    return mallocNew!LinearFloatParameter(Params.flangerStereoPhase, "Flanger Stereo Phase", "deg", 0.0f, 180.0f, 90.0f);
  }
  static auto flangerMix() {
    return mallocNew!LinearFloatParameter(Params.flangerMix, "Flanger Mix", "%", 0.0f, 1.0f, 0.5f);
  }

  // --- FX Phaser ---
  static auto phaserEnable() {
    return mallocNew!BoolParameter(Params.phaserEnable, "Phaser Enable", false);
  }
  static auto phaserCurve() {
    return mallocNew!EnumParameter(Params.phaserCurve, "Phaser Curve", tvmCurvePresetNames, TVMCurvePreset.sine1x);
  }
  static auto phaserCurveTension() {
    return mallocNew!LinearFloatParameter(Params.phaserCurveTension, "Phaser Curve Tension", "", -1.0f, 1.0f, 0.0f);
  }
  static auto phaserRate() {
    return mallocNew!LinearFloatParameter(Params.phaserRate, "Phaser Rate", "Hz", 0.05f, 5.0f, 0.35f);
  }
  static auto phaserStages() {
    return mallocNew!EnumParameter(Params.phaserStages, "Phaser Stages", phaserStagesNames, PhaserStages.poles6);
  }
  static auto phaserCenterMin() {
    return mallocNew!LogFloatParameter(Params.phaserCenterMin, "Phaser Center Min", "Hz", 100.0, 8000.0, 250.0);
  }
  static auto phaserCenterMax() {
    return mallocNew!LogFloatParameter(Params.phaserCenterMax, "Phaser Center Max", "Hz", 100.0, 8000.0, 3200.0);
  }
  static auto phaserFeedback() {
    return mallocNew!LinearFloatParameter(Params.phaserFeedback, "Phaser Feedback", "", -0.95f, 0.95f, 0.6f);
  }
  static auto phaserMix() {
    return mallocNew!LinearFloatParameter(Params.phaserMix, "Phaser Mix", "%", 0.0f, 1.0f, 0.5f);
  }

  // --- FX Reverb ---
  static auto reverbEnable() {
    return mallocNew!BoolParameter(Params.reverbEnable, "Reverb Enable", false);
  }
  static auto reverbCurve() {
    return mallocNew!EnumParameter(Params.reverbCurve, "Reverb Curve", tvmCurvePresetNames, TVMCurvePreset.rampUp);
  }
  static auto reverbCurveTension() {
    return mallocNew!LinearFloatParameter(Params.reverbCurveTension, "Reverb Curve Tension", "", -1.0f, 1.0f, 0.0f);
  }
  static auto reverbSizeMin() {
    return mallocNew!LinearFloatParameter(Params.reverbSizeMin, "Reverb Size Min", "%", 0.0f, 1.0f, 0.3f);
  }
  static auto reverbSizeMax() {
    return mallocNew!LinearFloatParameter(Params.reverbSizeMax, "Reverb Size Max", "%", 0.0f, 1.0f, 0.9f);
  }
  static auto reverbDamping() {
    return mallocNew!LinearFloatParameter(Params.reverbDamping, "Reverb Damping", "%", 0.0f, 1.0f, 0.4f);
  }
  static auto reverbPreDelay() {
    return mallocNew!LinearFloatParameter(Params.reverbPreDelay, "Reverb Pre-Delay", "ms", 0.0f, 100.0f, 10.0f);
  }
  static auto reverbFreeze() {
    return mallocNew!BoolParameter(Params.reverbFreeze, "Reverb Freeze", false);
  }
  static auto reverbMix() {
    return mallocNew!LinearFloatParameter(Params.reverbMix, "Reverb Mix", "%", 0.0f, 1.0f, 0.35f);
  }

  // --- End-of-Chain Delay ---
  static auto delayEnable() {
    return mallocNew!BoolParameter(Params.delayEnable, "Delay Enable", false);
  }
  static auto delayCurve() {
    return mallocNew!EnumParameter(Params.delayCurve, "Delay Curve", tvmCurvePresetNames, TVMCurvePreset.rampUp);
  }
  static auto delayCurveTension() {
    return mallocNew!LinearFloatParameter(Params.delayCurveTension, "Delay Curve Tension", "", -1.0f, 1.0f, 0.0f);
  }
  static auto delayTimeL() {
    return mallocNew!EnumParameter(Params.delayTimeL, "Delay Time L", delaySubdivisionNames, DelaySubdivision.del1_8);
  }
  static auto delayTimeR() {
    return mallocNew!EnumParameter(Params.delayTimeR, "Delay Time R", delaySubdivisionNames, DelaySubdivision.del1_4);
  }
  static auto delayFeedbackMin() {
    return mallocNew!LinearFloatParameter(Params.delayFeedbackMin, "Delay Feedback Min", "%", 0.0f, 1.0f, 0.2f);
  }
  static auto delayFeedbackMax() {
    return mallocNew!LinearFloatParameter(Params.delayFeedbackMax, "Delay Feedback Max", "%", 0.0f, 1.0f, 0.65f);
  }
  static auto delayCross() {
    return mallocNew!LinearFloatParameter(Params.delayCross, "Delay Ping-Pong", "%", 0.0f, 1.0f, 0.5f);
  }
  static auto delayDamp() {
    return mallocNew!LinearFloatParameter(Params.delayDamp, "Delay Damp", "%", 0.0f, 1.0f, 0.25f);
  }
  static auto delayMix() {
    return mallocNew!LinearFloatParameter(Params.delayMix, "Delay Mix", "%", 0.0f, 1.0f, 0.4f);
  }

  // --- Master Limiter ---
  static auto limiterEnable() {
    return mallocNew!BoolParameter(Params.limiterEnable, "Limiter Enable", true);
  }
  static auto limiterThreshold() {
    return mallocNew!LinearFloatParameter(Params.limiterThreshold, "Limiter Threshold", "dB", -24.0f, 0.0f, -0.5f);
  }
  static auto limiterCeiling() {
    return mallocNew!LinearFloatParameter(Params.limiterCeiling, "Limiter Ceiling", "dB", -12.0f, 0.0f, -0.1f);
  }
  static auto limiterRelease() {
    return mallocNew!LinearFloatParameter(Params.limiterRelease, "Limiter Release", "ms", 1.0f, 500.0f, 50.0f);
  }
}

// =============================================================================
// Unit Tests
// =============================================================================

unittest {
  Parameter[] ps = buildParams!Params;
  assert(ps.length == EnumMembers!Params.length, "Parameter count mismatch");
  assert(ps.length == 137, "Expected 137 parameters");

  // Verify indices match sequential order
  foreach (i, p; ps) {
    assert(p.index == cast(int)i, "Parameter index does not match position");
  }

  // Verify typedParam bindings
  auto autoMode = typedParam!(Params.autoMode)(ps);
  assert(autoMode !is null);
  assert(autoMode.value == true);

  auto stutterStart = typedParam!(Params.stutterRateStart)(ps);
  assert(stutterStart !is null);
  assert(stutterStart.value == StutterSubdivision.sub1_8);

  import core.math : fabs;

  auto filterCutoffMin = typedParam!(Params.filterCutoffMin)(ps);
  assert(filterCutoffMin !is null);
  assert(fabs(filterCutoffMin.value - 200.0) < 1.0);

  auto limiterCeil = typedParam!(Params.limiterCeiling)(ps);
  assert(limiterCeil !is null);
  assert(fabs(limiterCeil.value - (-0.1f)) < 1e-4f);
}

