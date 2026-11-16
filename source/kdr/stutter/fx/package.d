/**
 * Package module re-exporting all 11 Stutter Edit 2 FX modules, End-of-Chain Delay,
 * and Master Output Limiter.
 *
 * Copyright: kdr 2026.
 * License: Boost License 1.0.
 */
module kdr.stutter.fx;

public import kdr.stutter.fx.gate;
public import kdr.stutter.fx.pan;
public import kdr.stutter.fx.tapestop;
public import kdr.stutter.fx.filter;
public import kdr.stutter.fx.highpass;
public import kdr.stutter.fx.lofi;
public import kdr.stutter.fx.distort;
public import kdr.stutter.fx.comb;
public import kdr.stutter.fx.chorus;
public import kdr.stutter.fx.flanger;
public import kdr.stutter.fx.phaser;
public import kdr.stutter.fx.reverb;
public import kdr.stutter.fx.delay;
public import kdr.stutter.fx.limiter;

/// Identifiers for the 11 reorderable modules in Stutter Edit 2's Signal Chain.
enum ChainFXId : int {
  distort  = 0,
  lofi     = 1,
  chorus   = 2,
  comb     = 3,
  reverb   = 4,
  flanger  = 5,
  phaser   = 6,
  lowpass  = 7,
  tapestop = 8,
  highpass = 9,
  delay    = 10,
}

enum int NumChainFX = 11;

static immutable ChainFXId[NumChainFX] defaultSignalChainOrder = [
  ChainFXId.distort,
  ChainFXId.lofi,
  ChainFXId.chorus,
  ChainFXId.comb,
  ChainFXId.reverb,
  ChainFXId.flanger,
  ChainFXId.phaser,
  ChainFXId.lowpass,
  ChainFXId.tapestop,
  ChainFXId.highpass,
  ChainFXId.delay,
];

/// Unified container holding all Stutter Edit 2 FX modules + Global Filter + Master Limiter.
struct StutterFXRack {
  GateFX gate;
  PanFX pan;
  TapeStopFX tapeStop;
  FilterFX filter;
  HighpassFX highpass;
  FilterFX globalFilter;
  LoFiFX lofi;
  DistortFX distort;
  CombFX comb;
  ChorusFX chorus;
  FlangerFX flanger;
  PhaserFX phaser;
  ReverbFX reverb;
  DelayFX delay;
  MasterLimiter limiter;

  @nogc nothrow:

  void reset(double sampleRate) {
    gate.reset(sampleRate);
    pan.reset(sampleRate);
    tapeStop.reset(sampleRate);
    filter.reset(sampleRate);
    highpass.reset(sampleRate);
    globalFilter.reset(sampleRate);
    lofi.reset(sampleRate);
    distort.reset(sampleRate);
    comb.reset(sampleRate);
    chorus.reset(sampleRate);
    flanger.reset(sampleRate);
    phaser.reset(sampleRate);
    reverb.reset(sampleRate);
    delay.reset(sampleRate);
    limiter.reset(sampleRate);
  }

  void setTempo(double bpm) {
    gate.setTempo(bpm);
    delay.setTempo(bpm);
  }
}

unittest {
  StutterFXRack rack;
  rack.reset(48_000.0);
  rack.setTempo(128.0);
  assert(rack.gate.sampleRate == 48_000.0);
  assert(rack.delay.tempo == 128.0);
  assert(rack.highpass.sampleRate == 48_000.0);
  assert(defaultSignalChainOrder.length == NumChainFX);
}
