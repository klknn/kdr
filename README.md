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

## History

- 29 Dec 2022: Add envtool
- 24 Sep 2022: Move from https://github.com/klknn/synth2 to https://github.com/klknn/kdr
- 15 Feb 2021: Fork [poly-alias-synth](https://github.com/AuburnSounds/Dplug/tree/v10.2.1/examples/poly-alias-synth) for synth2.
