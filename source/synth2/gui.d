/**
Synth2 graphical user interface.

Copyright: klknn, 2021.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module synth2.gui;

import core.stdc.stdio : snprintf;
import std.algorithm : max;

import dplug.core : mallocNew, destroyFree;
import dplug.graphics.color : RGBA;
import dplug.graphics.font : Font;
import dplug.client.params : BoolParameter, FloatParameter, Parameter;
import dplug.pbrwidgets : PBRBackgroundGUI, UILabel, UIOnOffSwitch, UIKnob, UISlider, KnobStyle, HandleStyle;
import dplug.math : box2i, rectangle;

import synth2.lfo : multiplierNames, mulToFloat, Multiplier;
import synth2.delay : delayNames;
import synth2.effect : effectNames;
import synth2.filter : filterNames;
import synth2.params : typedParam, Params, menvDestNames, lfoDestNames, voiceKindNames;

// TODO: CTFE formatted names from enum values.
static immutable mulNames = {
  import std.traits : EnumMembers;
  import std.format : format;
  import std.conv : to;
  string[] ret;
  foreach (mul; mulToFloat) {
    ret ~= format!"%d.%d"(cast(int) mul, cast(int) ((mul % 1) * 10));
  }
  return ret;
}();

nothrow @nogc pure @safe
unittest {
  assert(mulNames[Multiplier.none] == "1.0");
  assert(mulNames[Multiplier.dot] == "1.5");
  assert(mulNames[Multiplier.tri] == "0.3");
}

enum png1 = "114.png"; // "gray.png"; // "black.png"
enum png2 = "black.png";
enum png3 = "black.png";


// https://all-free-download.com/font/download/display_free_tfb_10784.html
// static string _fontRaw = import("TFB.ttf");
// http://www.publicdomainfiles.com/show_file.php?id=13502494517207
// static string _fontRaw = import("LeroyLetteringLightBeta01.ttf");
// https://www.google.com/get/noto/#mono-mono
// static string _fontRaw = import("NotoMono-Regular.ttf");
// https://all-free-download.com/font/download/forced_square_14817.html
static string _fontRaw = import("FORCED SQUARE.ttf");

/// Expands box to include all positions.
box2i expand(box2i[] positions...) nothrow @nogc pure @safe {
  box2i ret = positions[0];
  foreach (p; positions) {
    ret = ret.expand(p);
  }
  return ret;
}

nothrow @nogc pure
unittest {
  auto a = rectangle(1, 10, 3, 4);
  auto b = rectangle(100, 2, 3, 4);
  assert(expand(a, a, b) == box2i(1, 2, 103, 14));
}

version (unittest) {} else:;

class Synth2GUI : PBRBackgroundGUI!(png1, png2, png3, png3, png3, "") {
 public:
  nothrow @nogc:

  enum marginW = 5;
  enum marginH = 5;
  enum screenWidth = 680;
  enum screenHeight = 300;

  enum fontLarge = 16;
  enum fontMedium = 12;
  enum fontMediumW = cast(int) (fontMedium * 0.8);
  enum fontSmall = 9;
  enum fontSmallW = cast(int) (fontSmall * 0.8);

  enum knobRad = 25;
  enum slideWidth = 40;
  enum slideHeight = 100;

  enum litTrailDiffuse = RGBA(99, 61, 24, 20);
  enum handleDiffuse = RGBA(240, 127, 17, 40);
  enum unlitTrailDiffuse = RGBA(29, 29, 29, 20);
  enum fontColor = RGBA(253, 250, 243, 0);
  enum knobDiffuse = RGBA(65, 65, 65, 0); // RGBA(216, 216, 216, 0);
  enum litSwitchOn = 40;

  static immutable pitchLabels = ["-12", "-6", "0", "6", "12"];
  static immutable waveNames = ["sin", "saw", "pls", "tri", "rnd"];

  this(Parameter[] parameters) {
    _params = parameters;
    _font = mallocNew!Font(cast(ubyte[])(_fontRaw));
    super(screenWidth, screenHeight);
    int x, y;

    // header
    y = marginH;
    auto synth2 = _addLabel("Synth2");
    synth2.textSize(fontLarge);
    synth2.position(rectangle(0, y, 80, fontLarge));

    auto date = _addLabel("v0.00 " ~ __DATE__);
    const dateWidth = fontMediumW * cast(int) date.text.length;
    date.position(rectangle(screenWidth - dateWidth, y, dateWidth, fontMedium));
    date.textSize(fontMedium);

    _tempo = _addLabel("BPM000.0");
    _tempo.textSize(fontMedium);
    const tempoWidth = fontMediumW * cast(int) _tempo.text.length;
    _tempo.position(rectangle(date.position.min.x - tempoWidth,
                              synth2.position.min.y,
                              80, fontMedium));

    auto osc = _buildOsc(marginW, synth2.position.max.y + marginH);

    auto master = _buildMaster(osc.max.x + marginW, osc.min.y);

    auto menv = _buildModEnv(master.min.x, master.max.y + marginH);

    auto ampEnv = _buildADSR(master.max.x + marginW, osc.min.y, "AmpEnv",
                             Params.ampAttack);

    auto filterEnv = _buildADSR(ampEnv.min.x, ampEnv.max.y,
                                "FilterEnv", Params.filterAttack);

    auto filter = _buildFilter(menv.max.x + marginW, menv.min.y);

    auto effect = _buildEffect(ampEnv.max.x + marginW, ampEnv.min.y);

    auto eq = _buildEQ(effect.max.x + marginW, effect.min.y);

    auto delay = _buildDelay(filter.max.x + marginW, effect.max.y + marginH);

    auto voice = _buildVoice(delay.max.x + marginW, delay.min.y);

    auto lfo2 = _buildLFO!(Params.lfo2Dest - Params.lfo1Dest)(
        "LFO2", voice.max.x + marginW, voice.min.y);
    auto lfo1 = _buildLFO!(cast(Params) 0)(
        "LFO1", lfo2.min.x, eq.min.y);
  }

  ~this() {
    _font.destroyFree();
  }

  void setTempo(double tempo) {
    snprintf(_tempoStr.ptr, _tempoStr.length, "BPM%3.1lf", tempo);
    _tempo.text(cast(string) _tempoStr[]);
  }

  void setPoly(int poly) {
    snprintf(_polyStr.ptr, _polyStr.length, "%02d", poly);
    _poly.text(cast(string) _polyStr[]);
  }

private:

  auto _param(Params id)() { return typedParam!id(_params); }

  box2i _buildDelay(int x, int y) {
    auto label = _addLabel("Delay");
    label.textSize(fontMedium);
    label.position(rectangle(
        x, y, cast(int) label.text.length * fontMediumW, fontMedium));

    auto kind = _buildSlider(
        _param!(Params.delayKind),
        rectangle(x, label.position.max.y + marginW, slideWidth, slideHeight * 3 / 5),
        "kind", delayNames);
    auto mul = _buildSlider(
        _param!(Params.delayMul),
        rectangle(kind.max.x + marginW, kind.min.y, slideWidth, slideHeight * 3 / 5),
        "note", mulNames);

    auto spread = _buildKnob(
        _param!(Params.delaySpread),
        rectangle(mul.max.x + marginW, mul.min.y, knobRad, knobRad), "sprd");
    auto feedback = _buildKnob(
        _param!(Params.delayFeedback),
        rectangle(spread.min.x, spread.max.y + marginH, knobRad, knobRad), "fdbk");
    auto tone = _buildKnob(
        _param!(Params.delayTone),
        rectangle(spread.min.x, feedback.max.y + marginH, knobRad, knobRad), "tone");

    auto mix = _buildKnob(
        _param!(Params.delayMix),
        rectangle(x, tone.min.y, knobRad, knobRad), "mix");
    auto time = _buildKnob(
        _param!(Params.delayTime),
        rectangle(mul.min.x, tone.min.y, knobRad, knobRad), "time");

    return expand(label.position, kind, time, mul, mix, spread, feedback, tone);
  }

  /// Builds the Voice section.
  box2i _buildVoice(int x, int y) {
    auto label = _addLabel("Voice");
    label.textSize(fontMedium);
    label.position(rectangle(
        x, y, cast(int) label.text.length * fontMediumW, fontMedium));
    auto kind = _buildSlider(
        _params[Params.voiceKind],
        rectangle(x, label.position.max.y + marginH, slideWidth, slideHeight / 3),
        "", voiceKindNames);
    auto poly = _buildSlider(
        _param!(Params.voicePoly),
        rectangle(x, kind.max.y + marginH, slideWidth, slideHeight / 3),
        "", []);
    _poly = _addLabel("16");
    _poly.textSize(fontLarge);
    _poly.position(rectangle(
        poly.max.x + marginW, poly.min.y + marginH, 2 * fontMediumW, fontLarge));
    auto polyLabel = _addLabel("poly");
    polyLabel.textSize(fontSmall);
    polyLabel.position(rectangle(
        poly.max.x, poly.min.y + fontLarge + marginH, 4 * fontSmallW, fontSmall));
    auto port = _buildKnob(
        typedParam!(Params.voicePortament)(_params),
        rectangle(x, poly.max.y + marginH, knobRad, knobRad), "port");
    auto portAuto = _buildSwitch(
        _param!(Params.voicePortamentAuto),
        rectangle(port.max.x + marginW, port.min.y, knobRad, knobRad),
        "auto");
    return expand(label.position, kind, port, _poly.position);
  }

  /// Builds the Master section.
  box2i _buildMaster(int x, int y) {
    auto oscMaster = this._addLabel("Master");
    oscMaster.textSize(fontMedium);
    oscMaster.position(rectangle(x, y, fontMediumW * 6, fontMedium));
    auto oscKeyShift = this._buildSlider(
        _params[Params.oscKeyShift],
        rectangle(oscMaster.position.min.x, oscMaster.position.max.y + marginH,
                  slideWidth, slideHeight),
        "pitch", pitchLabels);
    auto oscMasterMix = this._buildKnob(
        typedParam!(Params.oscMix)(_params),
        rectangle(oscKeyShift.max.x + marginW, oscKeyShift.min.y,
                  knobRad, knobRad),
        "mix",
    );
    auto oscMasterPhase = this._buildKnob(
        typedParam!(Params.oscPhase)(_params),
        rectangle(oscMasterMix.min.x, oscMasterMix.max.y + marginH, knobRad, knobRad),
        "phase",
    );
    auto oscMasterPW = this._buildKnob(
        typedParam!(Params.oscPulseWidth)(_params),
        rectangle(oscMasterMix.max.x + marginW, oscMasterMix.min.y, knobRad, knobRad),
        "p/w",
    );
    auto oscMasterTune = this._buildKnob(
        typedParam!(Params.oscTune)(_params),
        rectangle(oscMasterPW.min.x, oscMasterPhase.min.y, knobRad, knobRad),
        "tune",
    );

    // Amplifier
    auto ampGain = this._buildKnob(
        typedParam!(Params.ampGain)(_params),
        rectangle(oscMasterPhase.min.x, oscMasterPhase.max.y + marginH,
                  knobRad, knobRad),
        "gain",
    );
    auto ampVel = this._buildKnob(
        typedParam!(Params.ampVel)(_params),
        rectangle(oscMasterTune.min.x, oscMasterTune.max.y + marginH,
                  knobRad, knobRad),
        "vel",
    );
    return expand(oscMaster.position, oscMasterMix,
                  oscKeyShift, oscMasterPhase,
                  oscMasterPW, oscMasterTune,
                  ampGain, ampVel);
  }

  /// Builds the Osc section.
  box2i _buildOsc(int x, int y) {
    // osc1
    auto osc1lab = this._addLabel("Osc1");
    osc1lab.textSize(fontMedium);
    osc1lab.position(rectangle(x, y, fontMediumW * 4, fontMedium));
    auto osc1wave = this._buildSlider(
        _params[Params.osc1Waveform],
        rectangle(osc1lab.position.min.x, osc1lab.position.max.y + marginH,
                  slideWidth, slideHeight),
        "wave",
        waveNames,
    );
    auto osc1det = this._buildKnob(
        cast(FloatParameter) _params[Params.osc1Det],
        rectangle(osc1wave.max.x + marginW, osc1wave.min.y, knobRad, knobRad),
        "det");
    auto osc1fm = this._buildKnob(
          cast(FloatParameter) _params[Params.osc1FM],
          rectangle(osc1det.min.x, osc1det.max.y + marginH,
                    knobRad, knobRad),
          "fm");

    // oscSub
    auto oscSublab = this._addLabel("OscSub");
    oscSublab.textSize(fontMedium);
    oscSublab.position(rectangle(
        osc1det.max.x, osc1lab.position.min.y,
        fontMediumW * 6, fontMedium));
    auto oscSubwave = this._buildSlider(
        _params[Params.oscSubWaveform],
        rectangle(oscSublab.position.min.x + marginW, osc1wave.min.y,
                  slideWidth, slideHeight),
        "wave", waveNames);
    auto oscSubVol = this._buildKnob(
        cast(FloatParameter) _params[Params.oscSubVol],
        rectangle(oscSubwave.max.x + marginW, oscSubwave.min.y, knobRad, knobRad),
        "vol  ");
    auto oscSubOct = this._buildSwitch(
        typedParam!(Params.oscSubOct)(_params),
        rectangle(oscSubVol.min.x, osc1fm.min.y, knobRad, knobRad),
        "-1oct"
    );

    // osc2
    auto osc2lab = this._addLabel("Osc2");
    osc2lab.textSize(fontMedium);
    osc2lab.position(rectangle(osc1lab.position.min.x, osc1wave.max.y + marginH,
                               fontMediumW * 4, fontMedium));
    auto osc2wave = this._buildSlider(
        _params[Params.osc2Waveform],
        rectangle(osc1wave.min.x, osc2lab.position.max.y + marginW,
                  slideWidth, slideHeight),
        "wave",
        waveNames,
    );
    auto osc2ring = this._buildSwitch(
        typedParam!(Params.osc2Ring)(_params),
        rectangle(osc1det.min.x, osc2wave.min.y, knobRad, knobRad),
        "ring"
    );
    auto osc2sync = this._buildSwitch(
        typedParam!(Params.osc2Sync)(_params),
        rectangle(osc2ring.min.x, osc2ring.max.y + marginH, knobRad, knobRad),
        "sync"
    );
    auto osc2pitch = this._buildSlider(
        _params[Params.osc2Pitch],
        rectangle(oscSubwave.min.x, osc2ring.min.y, slideWidth, slideHeight),
        "pitch", pitchLabels);
    auto osc2tune = this._buildKnob(
        cast(FloatParameter) _params[Params.osc2Fine],
        rectangle(oscSubVol.min.x, osc2ring.min.y, knobRad, knobRad),
        "tune");
    auto osc2track = this._buildSwitch(
        typedParam!(Params.osc2Track)(_params),
        rectangle(osc2tune.min.x, osc2sync.min.y, knobRad, knobRad),
        "track"
    );
    return expand(osc1lab.position, osc1wave, osc1det, osc1fm,
                  osc2lab.position, osc2wave, osc2ring, osc2sync,
                  osc2pitch, osc2tune, osc2track,
                  oscSublab.position, oscSubwave, oscSubVol, oscSubOct);
  }

  /// Builds the Filter section.
  box2i _buildFilter(int x, int y) {
    auto filterLab = this._addLabel("Filter");
    filterLab.textSize(fontMedium);
    filterLab.position(rectangle(x, y, fontMediumW * 6, fontMedium));
    auto filterKind = this._buildSlider(
        _params[Params.filterKind],
        rectangle(x, y + fontMedium + marginH, slideWidth, slideHeight),
        "type", filterNames);
    auto filterCutoff = this._buildKnob(
        typedParam!(Params.filterCutoff)(_params),
        rectangle(filterKind.max.x + marginW, filterKind.min.y,
                  knobRad, knobRad),
        "frq");
    auto filterQ = this._buildKnob(
        typedParam!(Params.filterQ)(_params),
        rectangle(filterCutoff.min.x, filterCutoff.max.y + marginH,
                  knobRad, knobRad),
        "res");
    auto saturation = this._buildKnob(
        typedParam!(Params.saturation)(_params),
        rectangle(filterCutoff.min.x, filterQ.max.y + marginH,
                  knobRad, knobRad),
        "sat");
    auto filterEnvAmount = this._buildKnob(
        typedParam!(Params.filterEnvAmount)(_params),
        rectangle(filterCutoff.max.x + marginW, filterKind.min.y,
                  knobRad, knobRad),
        "amt");
    auto filterTrack = this._buildKnob(
        typedParam!(Params.filterTrack)(_params),
        rectangle(filterEnvAmount.min.x, filterQ.min.y,
                  knobRad, knobRad),
        "track");
    auto filterVel = this._buildSwitch(
        typedParam!(Params.filterUseVelocity)(_params),
        rectangle(filterTrack.min.x, filterTrack.max.y + marginH,
                  knobRad, knobRad),
        "vel"
    );
    return expand(filterLab.position, filterKind, filterCutoff, filterQ,
                  saturation, filterEnvAmount, filterTrack, filterVel);
  }

  /// Builds a ADSR section. Assumes params for ADSR are contiguous.
  box2i _buildADSR(int x, int y, string label, Params attack) {
    auto EnvLab = this._addLabel(label);
    EnvLab.textSize(fontMedium);
    EnvLab.position(rectangle(
        x, y, fontMediumW * cast(int) label.length, fontMedium));
    enum height = cast(int) (slideHeight * 2f / 5);
    auto A = this._buildSlider(
        _params[attack],
        rectangle(x, EnvLab.position.max.y + marginH, slideWidth, height),
        "A", []
    );
    auto D = this._buildSlider(
        _params[attack + 1],
        rectangle(A.max.x + marginW, A.min.y, slideWidth, height),
        "D", []
    );
    auto S = this._buildSlider(
        _params[attack + 2],
        rectangle(D.max.x + marginW, A.min.y, slideWidth, height),
        "S", []
    );
    auto R = this._buildSlider(
        _params[attack + 3],
        rectangle(S.max.x + marginW, A.min.y, slideWidth, height),
        "R", []
    );
    return expand(EnvLab.position, A, D, S, R);
  }

  /// Build "ModEnv" section.
  box2i _buildModEnv(int x, int y) {
    auto menvLabel = this._addLabel("ModEnv");
    menvLabel.textSize(fontMedium);
    menvLabel.position(rectangle(x, y, fontMediumW * 6, fontMedium));
    auto menvDest = this._buildSlider(
        _params[Params.menvDest],
        rectangle(
            menvLabel.position.min.x,
            menvLabel.position.max.y + marginH,
            slideWidth, slideHeight,
        ), "dst", menvDestNames);
    auto menvAmount = this._buildKnob(
        typedParam!(Params.menvAmount)(_params),
        rectangle(menvDest.max.x + marginW, menvDest.min.y, knobRad, knobRad),
        "amt");
    auto menvAttack = this._buildKnob(
        typedParam!(Params.menvAttack)(_params),
        rectangle(menvAmount.min.x, menvAmount.max.y + marginH, knobRad, knobRad),
        "A");
    auto menvDecay = this._buildKnob(
        typedParam!(Params.menvDecay)(_params),
        rectangle(menvAmount.min.x, menvAttack.max.y + marginH,
                  knobRad, knobRad),
        "D");
    return expand(menvLabel.position, menvDest,
                  menvAmount, menvAttack, menvDecay);
  }

  /// Build "Effect" section.
  box2i _buildEffect(int x, int y) {
    auto effectLabel = this._addLabel("Effect");
    effectLabel.textSize = fontMedium;
    effectLabel.position = rectangle(x, y, fontMediumW * 6, fontMedium);
    auto effectKind = this._buildSlider(
        _params[Params.effectKind],
        rectangle(effectLabel.position.min.x, effectLabel.position.max.y + marginH,
                  slideWidth, slideHeight),
        "kind", effectNames);
    auto effectCtrl1 = this._buildKnob(
        typedParam!(Params.effectCtrl1)(_params),
        rectangle(effectKind.max.x + marginW, effectKind.min.y, knobRad, knobRad),
        "ctrl1");
    auto effectCtrl2 = this._buildKnob(
        typedParam!(Params.effectCtrl2)(_params),
        rectangle(effectCtrl1.min.x, effectCtrl1.max.y + marginH, knobRad, knobRad),
        "ctrl2");
    auto effectMix = this._buildKnob(
        typedParam!(Params.effectMix)(_params),
        rectangle(effectCtrl2.min.x, effectCtrl2.max.y + marginH, knobRad, knobRad),
        "mix");
    return expand(effectLabel.position, effectKind,
                  effectCtrl1, effectCtrl2, effectMix);
  }

  /// Builds the "EQ" section.
  box2i _buildEQ(int x, int y) {
    auto label = _addLabel("EQ/Pan");
    label.textSize(fontMedium);
    label.position(rectangle(x, y, fontMediumW * cast(int) label.text.length,
                             fontMedium));
    auto freq = _buildKnob(
        typedParam!(Params.eqFreq)(_params),
        rectangle(x, label.position.max.y + marginH, knobRad, knobRad), "freq");
    auto level = _buildKnob(
        typedParam!(Params.eqLevel)(_params),
        rectangle(x, freq.max.y + marginH, knobRad, knobRad), "gain");
    auto q = _buildKnob(
        typedParam!(Params.eqQ)(_params),
        rectangle(x, level.max.y + marginH, knobRad, knobRad), "Q");
    auto tone = _buildKnob(
        typedParam!(Params.eqTone)(_params),
        rectangle(freq.max.x + marginW, freq.min.y, knobRad, knobRad), "tone");
    auto pan = _buildKnob(
        typedParam!(Params.eqPan)(_params),
        rectangle(tone.min.x, tone.max.y + marginH, knobRad, knobRad), "L-R");
    return expand(label.position, freq, level, q, tone, pan);
  }

  /// Build "LFO" section.
  box2i _buildLFO(Params offset)(string label, int x, int y) {
    auto lfo1Label = this._addLabel(label);
    lfo1Label.textSize(fontMedium);
    lfo1Label.position(rectangle(x, y, fontMediumW * 4, fontMedium));
    auto lfo1Wave = this._buildSlider(
        _params[Params.lfo1Wave + offset],
        rectangle(lfo1Label.position.min.x,  lfo1Label.position.max.y + marginH,
                  slideWidth, slideHeight), "wave", waveNames);
    auto lfo1Amount = this._buildKnob(
        typedParam!(Params.lfo1Amount + offset)(_params),
        rectangle(lfo1Wave.max.x + marginW, lfo1Wave.min.y, knobRad, knobRad),
        "amt");
    auto lfo1Speed = this._buildKnob(
        typedParam!(Params.lfo1Speed + offset)(_params),
        rectangle(lfo1Amount.min.x, lfo1Amount.max.y + marginH, knobRad, knobRad),
        "spd");
    auto lfo1Sync = this._buildSwitch(
        typedParam!(Params.lfo1Sync + offset)(_params),
        rectangle(lfo1Speed.min.x, lfo1Speed.max.y + marginH, knobRad, knobRad),
        "sync");
    auto lfo1Trigger = this._buildSwitch(
        typedParam!(Params.lfo1Trigger + offset)(_params),
        rectangle(lfo1Sync.max.x + marginW, lfo1Sync.min.y, knobRad, knobRad),
        "trig");
    auto lfo1Mul= this._buildSlider(
        _params[Params.lfo1Mul + offset],
        rectangle(lfo1Amount.max.x, lfo1Amount.min.y,
                  slideWidth, knobRad * 2 + fontSmall + marginH),
        "note", mulNames);
    auto lfo1Dest = this._buildSlider(
        _params[Params.lfo1Dest + offset],
        rectangle(lfo1Mul.max.x + marginW, lfo1Mul.min.y, slideWidth, slideHeight),
        "dst", lfoDestNames);
    return expand(lfo1Label.position, lfo1Wave, lfo1Amount,
                  lfo1Speed, lfo1Sync, lfo1Trigger, lfo1Mul, lfo1Dest);
  }

  box2i _buildSlider(Parameter p, box2i pos, string label, const string[] vlabels) {
    UISlider ui = mallocNew!UISlider(this.context, p);
    pos.width(pos.width / 2);
    ui.position = pos;
    ui.trailWidth = 0.5;
    ui.handleWidthRatio = 0.5;
    ui.handleHeightRatio = cast(float) fontSmall / pos.height;
    ui.handleStyle = HandleStyle.shapeBlock;
    ui.handleMaterial = RGBA(0, 0, 0, 0);  // smooth, metal, shiny, phisycal
    ui.handleDiffuse = handleDiffuse; // RGBA(255, 255, 255, 0);
    ui.litTrailDiffuse = litTrailDiffuse;
    ui.litTrailDiffuseAlt = litTrailDiffuse;
    ui.unlitTrailDiffuse = unlitTrailDiffuse;
    this.addChild(ui);

    box2i ret = ui.position;
    if (vlabels.length > 0) {
      uint labelHeight = pos.height / cast(uint) vlabels.length;
      int maxlen = 0;
      foreach (lab; vlabels) {
        maxlen = max(maxlen, cast(int) lab.length);
      }
      foreach (i, lab; vlabels) {
        UILabel l = _addLabel(lab);
        const width = maxlen * fontSmallW;
        const box = rectangle(
            pos.max.x - marginW,
            cast(uint) (pos.min.y + (vlabels.length - i - 1) * labelHeight),
            width, labelHeight);
        l.position(box);
        ret = ret.expand(box);
        l.textSize(fontSmall);
      }
    }

    if (label == "") {
      return ret;
    }
    auto lab = this._addLabel(label);
    lab.textSize(fontSmall);
    const width = fontSmallW * cast(int) label.length;
    lab.position(rectangle(pos.min.x, pos.max.y, max(slideWidth/2, width), fontSmall));
    return ret.expand(lab.position);
  }

  box2i _buildKnob(FloatParameter p, box2i pos, string label) {
    UIKnob knob = mallocNew!UIKnob(this.context, p);
    this.addChild(knob);
    knob.position(pos);
    knob.knobDiffuse = knobDiffuse; // RGBA(70, 70, 70, 0);
    knob.style = KnobStyle.ball;
    knob.knobMaterial = RGBA(255, 0, 0, 0);  // smooth, metal, shiny, phisycal
    knob.LEDDepth = 0;
    knob.numLEDs = 0;
    knob.knobRadius = 0.5;
    knob.trailRadiusMin = 0.4;
    knob.trailRadiusMax = 1;
    knob.LEDDiffuseLit = RGBA(0, 0, 0, 0);
    knob.LEDDiffuseUnlit = RGBA(0, 0, 0, 0);
    knob.LEDRadiusMin = 0f;
    knob.LEDRadiusMax = 0f;

    knob.litTrailDiffuse = handleDiffuse; // litTrailDiffuse;
    knob.unlitTrailDiffuse = unlitTrailDiffuse;
    auto lab = this._addLabel(label);
    lab.textSize(fontSmall);
    lab.position(rectangle(knob.position.min.x, knob.position.max.y,
                           knob.position.width, fontSmall));
    // fontSmallW * cast(int) label.length, fontSmall));
    return expand(knob.position, lab.position);
  }

  box2i _buildSwitch(BoolParameter p, box2i pos, string label) {
    UIOnOffSwitch ui = mallocNew!UIOnOffSwitch(this.context, p);
    ui.position = pos;
    ui.diffuseOn = handleDiffuse;
    ui.diffuseOff = litTrailDiffuse;
    this.addChild(ui);
    auto lab = this._addLabel(label);
    lab.textSize(fontSmall);
    const width = fontSmallW * cast(int) label.length;
    lab.position(rectangle(pos.min.x, pos.max.y,
                           width, fontSmall));
    return expand(ui.position, lab.position);
  }

  UILabel _addLabel(string text) {
    UILabel label;
    this.addChild(label = mallocNew!UILabel(context(), _font, text));
    label.textColor(fontColor);
    return label;
  }

  Font _font;
  UILabel _tempo;
  char[10] _tempoStr;
  UILabel _poly;
  char[3] _polyStr;
  Parameter[] _params;
}
