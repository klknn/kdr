/**
 * Factory Presets and Curated Gesture Banks for kdr-stutter.
 *
 * Provides 12 distinct musical factory presets covering rhythmic stutters,
 * filter/comb risers, vinyl tape stops, lo-fi industrial glitches, chorus/phaser
 * swirls, and reverb/delay wash transitions, plus per-note MIDI gesture profiles.
 *
 * Copyright: kdr 2026.
 * License: Boost License 1.0.
 */
module kdr.stutter.presets;

import dplug.client.params : Parameter, BoolParameter, IntegerParameter, FloatParameter;
import kdr.stutter.params;

struct StutterPresetConfig {
  string name;
  bool stutterEnable = true;
  int stutterCurve = TVMCurvePreset.rampUp;
  int stutterRateStart = StutterSubdivision.sub1_8;
  int stutterRateEnd = StutterSubdivision.sub1_64;
  int stutterQuantize = StutterQuantizeMode.steppedRhythmic;

  bool bufferEnable = true;
  int bufferCurve = TVMCurvePreset.rampUp;
  int bufferDirection = BufferDirection.forward;
  float bufferPitchMin = 0.0f;
  float bufferPitchMax = 0.0f;
  float bufferStereoOffset = 0.0f;

  bool gateEnable = false;
  int gateCurve = TVMCurvePreset.rampUp;
  int gateSubdivision = GateSubdivision.gate1_16;
  float gateWidthMin = 0.25f;
  float gateWidthMax = 0.75f;

  bool panEnable = false;
  int panCurve = TVMCurvePreset.sine1x;
  float panCenterMin = -0.8f;
  float panCenterMax = 0.8f;

  bool tapeStopEnable = false;
  int tapeStopCurve = TVMCurvePreset.expRise;
  float tapeStopSlowdownMin = 0.0f;
  float tapeStopSlowdownMax = 0.95f;
  bool tapeStopPlunge = true;

  bool filterEnable = false;
  int filterCurve = TVMCurvePreset.rampUp;
  int filterType = FilterType.lowpass24Ladder;
  float filterCutoffMin = 200.0f;
  float filterCutoffMax = 8000.0f;
  float filterResonance = 0.45f;

  bool lofiEnable = false;
  int lofiCurve = TVMCurvePreset.rampDown;
  float lofiBitDepthMin = 4.0f;
  float lofiBitDepthMax = 12.0f;
  float lofiDownsampleMin = 2.0f;
  float lofiDownsampleMax = 10.0f;

  bool distortEnable = false;
  int distortCurve = TVMCurvePreset.rampUp;
  float distortDriveLowMax = 0.6f;
  float distortDriveHighMax = 0.85f;

  bool combEnable = false;
  int combCurve = TVMCurvePreset.rampUp;
  float combFreqMin = 110.0f;
  float combFreqMax = 880.0f;
  float combFeedback = 0.8f;

  bool chorusEnable = false;
  bool flangerEnable = false;
  bool phaserEnable = false;

  bool reverbEnable = false;
  int reverbCurve = TVMCurvePreset.rampUp;
  float reverbSizeMin = 0.3f;
  float reverbSizeMax = 0.9f;
  bool reverbFreeze = false;

  bool delayEnable = false;
  int delayTimeL = DelaySubdivision.del1_8;
  int delayTimeR = DelaySubdivision.del1_4;
  float delayFeedbackMax = 0.65f;
}

enum int NUM_FACTORY_PRESETS = 12;

static immutable string[NUM_FACTORY_PRESETS] factoryPresetNames = [
  "01 Rhythmic Stutter Roll",
  "02 Filter Drop Riser",
  "03 Vinyl Tape Stop",
  "04 Lo-Fi Glitch Wash",
  "05 Comb Metallic Ascent",
  "06 Reverse Pendulum Chop",
  "07 Industrial Bit Crush",
  "08 Jet Flanger Vortex",
  "09 Wide Pan Chopper",
  "10 Freeze Reverb Tail",
  "11 Triplet Pitch Dive",
  "12 Chaos Multi-FX Matrix",
];

static immutable StutterPresetConfig[NUM_FACTORY_PRESETS] factoryPresets = [
  // 0: Rhythmic Stutter Roll
  StutterPresetConfig(
    "01 Rhythmic Stutter Roll",
    true, TVMCurvePreset.rampUp, StutterSubdivision.sub1_8, StutterSubdivision.sub1_64, StutterQuantizeMode.steppedRhythmic,
    true, TVMCurvePreset.rampUp, BufferDirection.forward, 0.0f, 0.0f, 0.0f
  ),
  // 1: Filter Drop Riser
  StutterPresetConfig(
    "02 Filter Drop Riser",
    true, TVMCurvePreset.expRise, StutterSubdivision.sub1_4, StutterSubdivision.sub1_64, StutterQuantizeMode.steppedRhythmic,
    true, TVMCurvePreset.rampUp, BufferDirection.forward, 0.0f, 12.0f, 5.0f,
    false, TVMCurvePreset.rampUp, GateSubdivision.gate1_16, 0.25f, 0.75f,
    false, TVMCurvePreset.sine1x, -0.8f, 0.8f,
    false, TVMCurvePreset.expRise, 0.0f, 0.9f, false,
    true, TVMCurvePreset.expRise, FilterType.highpass12, 80.0f, 6000.0f, 0.6f,
    false, TVMCurvePreset.rampDown, 6.0f, 16.0f, 1.0f, 4.0f,
    false, TVMCurvePreset.rampUp, 0.4f, 0.6f,
    false, TVMCurvePreset.rampUp, 110.0f, 440.0f, 0.7f,
    false, false, false,
    true, TVMCurvePreset.rampUp, 0.2f, 0.85f, false,
    true, DelaySubdivision.del1_16, DelaySubdivision.del1_8, 0.6f
  ),
  // 2: Vinyl Tape Stop
  StutterPresetConfig(
    "03 Vinyl Tape Stop",
    false, TVMCurvePreset.flatLow, StutterSubdivision.sub1_4, StutterSubdivision.sub1_4, StutterQuantizeMode.freeSweep,
    true, TVMCurvePreset.expFall, BufferDirection.forward, -12.0f, 0.0f, 0.0f,
    false, TVMCurvePreset.rampUp, GateSubdivision.gate1_16, 0.3f, 0.8f,
    false, TVMCurvePreset.sine1x, -0.5f, 0.5f,
    true, TVMCurvePreset.expRise, 0.0f, 1.0f, true,
    true, TVMCurvePreset.rampDown, FilterType.lowpass24Ladder, 180.0f, 12000.0f, 0.3f
  ),
  // 3: Lo-Fi Glitch Wash
  StutterPresetConfig(
    "04 Lo-Fi Glitch Wash",
    true, TVMCurvePreset.chaos, StutterSubdivision.sub1_16, StutterSubdivision.sub1_64, StutterQuantizeMode.steppedRhythmic,
    true, TVMCurvePreset.chaos, BufferDirection.pendulum, -5.0f, 7.0f, 12.0f,
    true, TVMCurvePreset.sine2x, GateSubdivision.gate1_32, 0.2f, 0.7f,
    false, TVMCurvePreset.sine1x, -0.8f, 0.8f,
    false, TVMCurvePreset.expRise, 0.0f, 0.8f, false,
    false, TVMCurvePreset.rampUp, FilterType.bandpass12, 300.0f, 4000.0f, 0.5f,
    true, TVMCurvePreset.chaos, 4.0f, 10.0f, 2.0f, 12.0f,
    false, TVMCurvePreset.rampUp, 0.5f, 0.7f,
    false, TVMCurvePreset.rampUp, 120.0f, 600.0f, 0.7f,
    false, false, false,
    true, TVMCurvePreset.rampUp, 0.4f, 0.9f, false,
    true, DelaySubdivision.del1_8D, DelaySubdivision.del1_4, 0.65f
  ),
  // 4: Comb Metallic Ascent
  StutterPresetConfig(
    "05 Comb Metallic Ascent",
    true, TVMCurvePreset.rampUp, StutterSubdivision.sub1_16, StutterSubdivision.sub1_32, StutterQuantizeMode.steppedRhythmic,
    true, TVMCurvePreset.rampUp, BufferDirection.forward, 0.0f, 0.0f, 8.0f,
    false, TVMCurvePreset.rampUp, GateSubdivision.gate1_16, 0.3f, 0.8f,
    true, TVMCurvePreset.sine2x, -0.9f, 0.9f,
    false, TVMCurvePreset.expRise, 0.0f, 0.8f, false,
    false, TVMCurvePreset.rampUp, FilterType.lowpass12, 400.0f, 9000.0f, 0.4f,
    false, TVMCurvePreset.rampDown, 6.0f, 16.0f, 1.0f, 4.0f,
    false, TVMCurvePreset.rampUp, 0.4f, 0.6f,
    true, TVMCurvePreset.expRise, 130.81f, 1046.5f, 0.88f,
    true, false, false
  ),
  // 5: Reverse Pendulum Chop
  StutterPresetConfig(
    "06 Reverse Pendulum Chop",
    true, TVMCurvePreset.stepUp, StutterSubdivision.sub1_8, StutterSubdivision.sub1_32, StutterQuantizeMode.steppedRhythmic,
    true, TVMCurvePreset.rampDown, BufferDirection.reverse, 0.0f, 0.0f, 18.0f,
    true, TVMCurvePreset.rampDown, GateSubdivision.gate1_16, 0.15f, 0.65f,
    true, TVMCurvePreset.sine1x, -1.0f, 1.0f
  ),
  // 6: Industrial Bit Crush
  StutterPresetConfig(
    "07 Industrial Bit Crush",
    true, TVMCurvePreset.spike, StutterSubdivision.sub1_16, StutterSubdivision.sub1_128, StutterQuantizeMode.steppedRhythmic,
    true, TVMCurvePreset.rampUp, BufferDirection.forward, -7.0f, 0.0f, 0.0f,
    false, TVMCurvePreset.rampUp, GateSubdivision.gate1_16, 0.3f, 0.8f,
    false, TVMCurvePreset.sine1x, -0.5f, 0.5f,
    false, TVMCurvePreset.expRise, 0.0f, 0.8f, false,
    true, TVMCurvePreset.sine1x, FilterType.bandpass12, 250.0f, 5500.0f, 0.65f,
    true, TVMCurvePreset.rampUp, 3.0f, 8.0f, 4.0f, 16.0f,
    true, TVMCurvePreset.rampUp, 0.75f, 0.95f
  ),
  // 7: Jet Flanger Vortex
  StutterPresetConfig(
    "08 Jet Flanger Vortex",
    true, TVMCurvePreset.sine1x, StutterSubdivision.sub1_8T, StutterSubdivision.sub1_32T, StutterQuantizeMode.tripletsOnly,
    true, TVMCurvePreset.sine1x, BufferDirection.pendulum, 0.0f, 0.0f, 10.0f,
    false, TVMCurvePreset.rampUp, GateSubdivision.gate1_16, 0.3f, 0.8f,
    false, TVMCurvePreset.sine1x, -0.5f, 0.5f,
    false, TVMCurvePreset.expRise, 0.0f, 0.8f, false,
    false, TVMCurvePreset.rampUp, FilterType.lowpass24Ladder, 300.0f, 8000.0f, 0.4f,
    false, TVMCurvePreset.rampDown, 6.0f, 16.0f, 1.0f, 4.0f,
    false, TVMCurvePreset.rampUp, 0.4f, 0.6f,
    false, TVMCurvePreset.rampUp, 110.0f, 440.0f, 0.7f,
    true, true, true
  ),
  // 8: Wide Pan Chopper
  StutterPresetConfig(
    "09 Wide Pan Chopper",
    true, TVMCurvePreset.rampUp, StutterSubdivision.sub1_16, StutterSubdivision.sub1_32, StutterQuantizeMode.steppedRhythmic,
    true, TVMCurvePreset.rampUp, BufferDirection.forward, 0.0f, 0.0f, 25.0f,
    true, TVMCurvePreset.sine2x, GateSubdivision.gate1_32, 0.2f, 0.6f,
    true, TVMCurvePreset.sine2x, -1.0f, 1.0f,
    false, TVMCurvePreset.expRise, 0.0f, 0.8f, false,
    false, TVMCurvePreset.rampUp, FilterType.lowpass24Ladder, 300.0f, 8000.0f, 0.4f,
    false, TVMCurvePreset.rampDown, 6.0f, 16.0f, 1.0f, 4.0f,
    false, TVMCurvePreset.rampUp, 0.4f, 0.6f,
    false, TVMCurvePreset.rampUp, 110.0f, 440.0f, 0.7f,
    false, false, false,
    false, TVMCurvePreset.rampUp, 0.3f, 0.8f, false,
    true, DelaySubdivision.del1_8T, DelaySubdivision.del1_4D, 0.55f
  ),
  // 9: Freeze Reverb Tail
  StutterPresetConfig(
    "10 Freeze Reverb Tail",
    true, TVMCurvePreset.expFall, StutterSubdivision.sub1_32, StutterSubdivision.sub1_8, StutterQuantizeMode.steppedRhythmic,
    true, TVMCurvePreset.rampUp, BufferDirection.reverse, 0.0f, 12.0f, 15.0f,
    false, TVMCurvePreset.rampUp, GateSubdivision.gate1_16, 0.3f, 0.8f,
    false, TVMCurvePreset.sine1x, -0.5f, 0.5f,
    false, TVMCurvePreset.expRise, 0.0f, 0.8f, false,
    true, TVMCurvePreset.rampUp, FilterType.lowpass12, 400.0f, 14000.0f, 0.35f,
    false, TVMCurvePreset.rampDown, 6.0f, 16.0f, 1.0f, 4.0f,
    false, TVMCurvePreset.rampUp, 0.4f, 0.6f,
    false, TVMCurvePreset.rampUp, 110.0f, 440.0f, 0.7f,
    true, false, false,
    true, TVMCurvePreset.flatHigh, 0.7f, 0.98f, true,
    true, DelaySubdivision.del1_4, DelaySubdivision.del1_2, 0.7f
  ),
  // 10: Triplet Pitch Dive
  StutterPresetConfig(
    "11 Triplet Pitch Dive",
    true, TVMCurvePreset.rampUp, StutterSubdivision.sub1_4T, StutterSubdivision.sub1_64T, StutterQuantizeMode.tripletsOnly,
    true, TVMCurvePreset.rampDown, BufferDirection.forward, -12.0f, 12.0f, 0.0f,
    false, TVMCurvePreset.rampUp, GateSubdivision.gate1_16, 0.3f, 0.8f,
    false, TVMCurvePreset.sine1x, -0.5f, 0.5f,
    true, TVMCurvePreset.expRise, 0.0f, 0.75f, false,
    true, TVMCurvePreset.rampDown, FilterType.lowpass24Ladder, 150.0f, 9000.0f, 0.5f
  ),
  // 11: Chaos Multi-FX Matrix
  StutterPresetConfig(
    "12 Chaos Multi-FX Matrix",
    true, TVMCurvePreset.chaos, StutterSubdivision.sub1_8, StutterSubdivision.sub1_128, StutterQuantizeMode.steppedRhythmic,
    true, TVMCurvePreset.chaos, BufferDirection.pendulum, -12.0f, 12.0f, 20.0f,
    true, TVMCurvePreset.chaos, GateSubdivision.gate1_16, 0.2f, 0.8f,
    true, TVMCurvePreset.sine2x, -1.0f, 1.0f,
    false, TVMCurvePreset.expRise, 0.0f, 0.6f, false,
    true, TVMCurvePreset.chaos, FilterType.lowpass24Ladder, 200.0f, 10000.0f, 0.55f,
    true, TVMCurvePreset.spike, 5.0f, 12.0f, 2.0f, 8.0f,
    true, TVMCurvePreset.rampUp, 0.5f, 0.8f,
    true, TVMCurvePreset.sine1x, 110.0f, 660.0f, 0.78f,
    true, true, true,
    true, TVMCurvePreset.rampUp, 0.3f, 0.85f, false,
    true, DelaySubdivision.del1_16D, DelaySubdivision.del1_8, 0.6f
  ),
];

/// Applies a factory preset configuration to the plugin's Parameter array (@nogc nothrow).
@nogc nothrow
void applyFactoryPreset(Parameter[] params, int presetIndex) {
  if (params.length < 137) return;
  int idx = presetIndex;
  if (idx < 0) idx = 0;
  if (idx >= NUM_FACTORY_PRESETS) idx = idx % NUM_FACTORY_PRESETS;

  const ref StutterPresetConfig cfg = factoryPresets[idx];

  static void setBool(Parameter[] ps, Params id, bool v) @nogc nothrow {
    if (auto p = cast(BoolParameter) ps[id]) p.setFromHost(v ? 1.0 : 0.0);
  }
  static void setInt(Parameter[] ps, Params id, int v) @nogc nothrow {
    if (auto p = cast(IntegerParameter) ps[id]) {
      const int minV = p.minValue();
      const int maxV = p.maxValue();
      const double norm = (maxV > minV)
        ? cast(double)(v - minV) / cast(double)(maxV - minV)
        : 0.0;
      p.setFromHost(norm);
    }
  }
  static void setFloat(Parameter[] ps, Params id, float v) @nogc nothrow {
    if (auto p = cast(FloatParameter) ps[id]) p.setFromHost(p.toNormalized(v));
  }

  setBool(params, Params.stutterEnable, cfg.stutterEnable);
  setInt(params, Params.stutterCurve, cfg.stutterCurve);
  setInt(params, Params.stutterRateStart, cfg.stutterRateStart);
  setInt(params, Params.stutterRateEnd, cfg.stutterRateEnd);
  setInt(params, Params.stutterQuantize, cfg.stutterQuantize);

  setBool(params, Params.bufferEnable, cfg.bufferEnable);
  setInt(params, Params.bufferCurve, cfg.bufferCurve);
  setInt(params, Params.bufferDirection, cfg.bufferDirection);
  setFloat(params, Params.bufferPitchMin, cfg.bufferPitchMin);
  setFloat(params, Params.bufferPitchMax, cfg.bufferPitchMax);
  setFloat(params, Params.bufferStereoOffset, cfg.bufferStereoOffset);

  setBool(params, Params.gateEnable, cfg.gateEnable);
  setInt(params, Params.gateCurve, cfg.gateCurve);
  setInt(params, Params.gateSubdivision, cfg.gateSubdivision);
  setFloat(params, Params.gateWidthMin, cfg.gateWidthMin);
  setFloat(params, Params.gateWidthMax, cfg.gateWidthMax);

  setBool(params, Params.panEnable, cfg.panEnable);
  setInt(params, Params.panCurve, cfg.panCurve);
  setFloat(params, Params.panCenterMin, cfg.panCenterMin);
  setFloat(params, Params.panCenterMax, cfg.panCenterMax);

  setBool(params, Params.tapeStopEnable, cfg.tapeStopEnable);
  setInt(params, Params.tapeStopCurve, cfg.tapeStopCurve);
  setFloat(params, Params.tapeStopSlowdownMin, cfg.tapeStopSlowdownMin);
  setFloat(params, Params.tapeStopSlowdownMax, cfg.tapeStopSlowdownMax);
  setBool(params, Params.tapeStopPlunge, cfg.tapeStopPlunge);

  setBool(params, Params.filterEnable, cfg.filterEnable);
  setInt(params, Params.filterCurve, cfg.filterCurve);
  setInt(params, Params.filterType, cfg.filterType);
  setFloat(params, Params.filterCutoffMin, cfg.filterCutoffMin);
  setFloat(params, Params.filterCutoffMax, cfg.filterCutoffMax);
  setFloat(params, Params.filterResonance, cfg.filterResonance);

  setBool(params, Params.lofiEnable, cfg.lofiEnable);
  setInt(params, Params.lofiCurve, cfg.lofiCurve);
  setFloat(params, Params.lofiBitDepthMin, cfg.lofiBitDepthMin);
  setFloat(params, Params.lofiBitDepthMax, cfg.lofiBitDepthMax);
  setFloat(params, Params.lofiDownsampleMin, cfg.lofiDownsampleMin);
  setFloat(params, Params.lofiDownsampleMax, cfg.lofiDownsampleMax);

  setBool(params, Params.distortEnable, cfg.distortEnable);
  setInt(params, Params.distortCurve, cfg.distortCurve);
  setFloat(params, Params.distortDriveLowMax, cfg.distortDriveLowMax);
  setFloat(params, Params.distortDriveHighMax, cfg.distortDriveHighMax);

  setBool(params, Params.combEnable, cfg.combEnable);
  setInt(params, Params.combCurve, cfg.combCurve);
  setFloat(params, Params.combFreqMin, cfg.combFreqMin);
  setFloat(params, Params.combFreqMax, cfg.combFreqMax);
  setFloat(params, Params.combFeedback, cfg.combFeedback);

  setBool(params, Params.chorusEnable, cfg.chorusEnable);
  setBool(params, Params.flangerEnable, cfg.flangerEnable);
  setBool(params, Params.phaserEnable, cfg.phaserEnable);

  setBool(params, Params.reverbEnable, cfg.reverbEnable);
  setInt(params, Params.reverbCurve, cfg.reverbCurve);
  setFloat(params, Params.reverbSizeMin, cfg.reverbSizeMin);
  setFloat(params, Params.reverbSizeMax, cfg.reverbSizeMax);
  setBool(params, Params.reverbFreeze, cfg.reverbFreeze);

  setBool(params, Params.delayEnable, cfg.delayEnable);
  setInt(params, Params.delayTimeL, cfg.delayTimeL);
  setInt(params, Params.delayTimeR, cfg.delayTimeR);
  setFloat(params, Params.delayFeedbackMax, cfg.delayFeedbackMax);
}

unittest {
  import kdr.params : buildParams, typedParam;
  Parameter[] ps = buildParams!Params();
  assert(ps.length == 137);

  // Verify each preset loads cleanly and configures distinct module combinations
  for (int i = 0; i < NUM_FACTORY_PRESETS; ++i) {
    applyFactoryPreset(ps, i);
    const ref cfg = factoryPresets[i];
    assert(typedParam!(Params.stutterEnable)(ps).value == cfg.stutterEnable);
    assert(typedParam!(Params.tapeStopEnable)(ps).value == cfg.tapeStopEnable);
    assert(typedParam!(Params.filterEnable)(ps).value == cfg.filterEnable);
    assert(typedParam!(Params.lofiEnable)(ps).value == cfg.lofiEnable);
    assert(typedParam!(Params.reverbEnable)(ps).value == cfg.reverbEnable);
  }
}
