# kdr: klknn dplug repo

[⬇️ DOWNLOAD FREE PLUGINS ⬇️](https://github.com/klknn/kdr/releases)

[![ci](https://github.com/klknn/kdr/actions/workflows/ci.yml/badge.svg)](https://github.com/klknn/kdr/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/klknn/kdr/branch/master/graph/badge.svg?token=4HMC5S2GER)](https://codecov.io/gh/klknn/kdr)

## How to build this plugin?

https://github.com/AuburnSounds/Dplug/wiki/Getting-Started

## synth2

virtual-analog synth like [synth1](https://www.kvraudio.com/product/synth1-by-daichi-laboratory-ichiro-toda) in D.

Features (TODO)

- [x] Multi-platform
  - [x] VST/VST3/AU CI build
  - [x] Windows/Linux CI test (macOS won't be tested because I don't have it)
- [x] Oscillators
  - [x] sin/saw/square/triangle/noise waves
  - [x] 2nd/sub osc
  - [x] detune
  - [x] sync
  - [x] FM
  - [x] AM (ring)
  - [x] master control (keyshift/tune/phase/mix/PW)
  - [x] mod envelope
- [x] Amplifier
  - [x] velocity sensitivity
  - [x] ADSR
- [x] Filter
  - [x] HP6/HP12/LP6/LP12/LP24/LPDL(TB303 like filter)
  - [x] ADSR
  - [x] Saturation
- [x] GUI
- [x] LFO
- [x] Effect (phaser is WIP)
- [x] Equalizer / Pan
- [x] Voice
- [x] Tempo Delay
- [x] Chorus / Flanger
- [ ] Unison
- [ ] Reverb
- [ ] Arpeggiator
- [ ] Presets
- [ ] MIDI
  - [x] Pitch bend
  - [ ] Mod wheel
  - [ ] Control change
  - [ ] Program change

## synth2p1

Synth2 with modern tabbed page-based GUI (Synth, Mod, FX) and theme switching.

- [x] Inherits full Synth2 virtual-analog DSP engine
- [x] Modern page-based interface (Synth / Mod / FX tabs)
- [x] Realtime interactive waveform, filter response, envelope & LFO scopes
- [x] Flat light theme / Cyberpunk dark theme toggle

## envtool

Envelope shaping effect for tremolo sidechain like kickstart or LFO tools.

- [x] WYSWIG envelope edit
- [x] Beat sync rate control
- [x] Depth control
- [x] LR offset control
- [x] Volume mod
- [ ] Filter mod
- [ ] Pan mod
- [ ] Presets

## reverb

TBA

## Hott

Yet another OTT clone

## khrm

Colour Bass harmonic sweetener and resonator effect inspired by Xynth Audio Chroma.

- [x] Simple yet versatile Color knob (dry/wet + resonant decay & harmonic saturation)
- [x] 12-note keyboard scale selector (C through B)
- [x] Central realtime spectro visualizer with harmonic guide pillars
- [x] Low latency / High quality dual engine modes
- [x] MIDI tracking mode
- [x] Spectral sweetening mode (transient preservation & sparkle harmonics)
- [x] Built-in presets: Lead, Drum, Bass, Vocal, Chromatic, MIDI Tracked
- [x] Purple cyberpunk theme GUI

## kdr-stutter

A production-grade audio effect plugin cloning iZotope Stutter Edit 2, built with [Dplug](https://github.com/AuburnSounds/Dplug) (~>13.0) and D (`@nogc nothrow`). Features gesture-based rhythmic audio buffer stuttering, multi-breakpoint Time-Variant Modifier (TVM) curve modulation, all 11 Stutter Edit 2 effect modules + master delay + brickwall limiter, and a custom interactive GUI faithfully matching the original Stutter Edit 2 layout and charcoal neon aesthetic.

- [x] Multi-platform & Plugin Formats
  - [x] VST3 / AU / VST2 / LV2 builds via `dplug-build`
  - [x] Real-time audio processing (@nogc nothrow pure)
  - [x] Multi-sample-rate support (44.1 kHz – 192 kHz)
- [x] Core Gesture, Stutter & Buffer Engine
  - [x] Continuous stereo circular capture buffer ($2^{19}$ samples / ~11.8s)
  - [x] 4-point 3rd-order Hermite cubic interpolation for alias-free pitch/rate shifting
  - [x] Slicing & repetition from 1/1 to 1/128 subdivisions and free Hz rate
  - [x] Dynamic rate ramping ($Rate_{start} \to Rate_{end}$) with quantized step locking vs. smooth sweeps
  - [x] Forward, Reverse, and Pendulum (alternating) playback directions
  - [x] L/R split stereo offset & buffer scrub position
  - [x] 64-sample click-free cosine equal-power crossfader
  - [x] MIDI Trigger Mode (individual gesture assignments per MIDI note)
  - [x] Auto Mode (instant continuous or rhythmic gesture playback without MIDI)
  - [x] Configurable Release Modes (`Instant`, `Latch`, `Full Gesture`, `On Grid`)
- [x] Time-Variant Modifier (TVM) Curve Sequencer
  - [x] Multi-node breakpoint curve editor modulating parameters over gesture phase ($p \in [0.0, 1.0]$)
  - [x] Tension, Linear, Exponential, Logarithmic, S-Curve, and Step/Hold interpolation types
  - [x] 12 one-click preset curve shapes (Flat Low/High, Ramp Up/Down, Exp Rise/Fall, Sine 1x/2x, Step Up/Down, Spike, Chaos)
  - [x] Per-parameter min/max modulation range sliders and visual value tracking
  - [x] Realtime animated gesture-phase playhead with module-matched glowing curve styling
- [x] Complete 11-Module FX Suite & Master Dynamics
  - [x] **Gate**: Rhythmic chopping synced to gesture subdivisions with Width (duty cycle) and release Tail de-click
  - [x] **Pan**: Constant-power stereo placement and M/S stereo field width modulation
  - [x] **Tape Stop**: Turntable/tape deceleration plunge, variable slowdown rate, and freeze mode
  - [x] **Filter**: Sweeping resonant LP12, LP24 (ladder), HP12, and BP12 with pre-drive soft saturation
  - [x] **Lo-Fi**: Digital degradation with bitcrushing (1-24 bit), sample-rate downsampling, and grit
  - [x] **Distort**: Linkwitz-Riley 4th-order 2-band distortion with independent low/high drive and tone
  - [x] **Comb**: Tuned fractional feedback comb filter with damping, bipolar feedback, and stereo detune
  - [x] **Chorus**: Multi-voice stereo chorus with quadrature LFO modulation, depth, feedback, and width
  - [x] **Flanger**: Sweeping jet comb modulation with short delay (0.1–5 ms), bipolar feedback, and phase
  - [x] **Phaser**: Multi-stage all-pass phase shifter (4–12 poles) with feedback, depth, and center sweep
  - [x] **Reverb**: Full stereo algorithmic Schroeder/Freeverb wash with damping, pre-delay, and freeze
  - [x] **Delay**: End-of-chain stereo tempo-synced delay with cross-feedback, ping-pong, and damping
  - [x] **Limiter**: Master zero-overs brickwall safety limiter with gain reduction metering
  - [x] Curated factory bank of musical gestures and multi-effect presets
- [x] Custom Interactive GUI (iZotope Stutter Edit 2 Style)
  - [x] Dark charcoal/slate panels (`#14171c` / `#1e222a`) with distinct neon accent colors per module
  - [x] Top Header: Mode toggle (Auto vs. MIDI), Bank/Preset selector, interactive mini MIDI keyboard strip, duration/release controls, master limiter & meters
  - [x] Left Module Rack: 14 module slots with color-coded accent bars, power toggles, and click-to-select focus
  - [x] Center/Right Workspace: Selected module parameter panel and large TVM curve editor with 12 preset shape bar

## History

- 18 Oct 2026: Add kdr-stutter (iZotope Stutter Edit 2 clone)
- 29 Dec 2022: Add envtool
- 24 Sep 2022: Move from https://github.com/klknn/synth2 to https://github.com/klknn/kdr
- 15 Feb 2021: Fork [poly-alias-synth](https://github.com/AuburnSounds/Dplug/tree/v10.2.1/examples/poly-alias-synth) for synth2.

