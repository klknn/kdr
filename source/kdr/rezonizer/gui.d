module kdr.rezonizer.gui;

import dplug.core : mallocNew, destroyFree;
import dplug.client;
import dplug.math : box2i, rectangle;
import dplug.gui;
import dplug.graphics : RGBA, Font, ImageRef, L16, cropImageRef;
import dplug.core.math : convertLinearGainToDecibel;
import dplug.pbrwidgets : UILabel, UIKnob;
import dplug.flatwidgets : UIWindowResizer;

import kdr.simplegui : PBRSimpleGUI;
import kdr.rezonizer.params;
import kdr.rezonizer.client : RezonizerClient;

/// UI for RezonizerClient.
class RezonizerGUI : PBRSimpleGUI, IParameterListener {
 public:
  @nogc nothrow:

  this(RezonizerClient client, Parameter[] params) {
    static immutable float[] ratios = [1.0f, 1.25f, 1.5f, 1.75f, 2.0f];
    super(makeSizeConstraintsDiscrete(920, 560, ratios), RGBA(18, 16, 24, 255));

    _client = client;
    _params = params;
    _font = mallocNew!Font(cast(ubyte[]) import("FORCED SQUARE.ttf"));

    // Header Title
    _title = buildLabel("KDR REZONIZER");

    // Global Knobs
    _dryGainKnob = buildKnob(Params.dryGain);
    _dryGainLabel = buildLabel("DRY");

    _wetGainKnob = buildKnob(Params.wetGain);
    _wetGainLabel = buildLabel("WET");

    _modeKnob = buildKnob(Params.mode);
    _modeLabel = buildLabel("SAW");
    _params[Params.mode].addListener(this);

    _decayKnob = buildKnob(Params.decay);
    _decayLabel = buildLabel("DECAY");

    _dampKnob = buildKnob(Params.damp);
    _dampLabel = buildLabel("COLOR");

    _haasWidthKnob = buildKnob(Params.haasWidth);
    _haasWidthLabel = buildLabel("WIDTH");

    _portamentoKnob = buildKnob(Params.portamento);
    _portamentoLabel = buildLabel("GLIDE");

    _chordPresetKnob = buildKnob(Params.chordPreset);
    _chordPresetLabel = buildLabel("MAJOR");
    _params[Params.chordPreset].addListener(this);

    _midiInputKnob = buildKnob(Params.midiInput);
    _midiInputLabel = buildLabel("MIDI IN");

    _midiModeKnob = buildKnob(Params.midiMode);
    _midiModeLabel = buildLabel("NORMAL");
    _params[Params.midiMode].addListener(this);

    _releaseTimeKnob = buildKnob(Params.releaseTime);
    _releaseTimeLabel = buildLabel("RELEASE");

    // Resonators Header Labels
    _resEnableHeader = buildLabel("ON");
    _resPitchHeader = buildLabel("PITCH");
    _resFineHeader = buildLabel("FINE");
    _resGainHeader = buildLabel("GAIN");
    _resPanHeader = buildLabel("PAN");

    // Resonator Rows
    static immutable string[6] voiceNames = ["ROOT", "VOICE 2", "VOICE 3", "VOICE 4", "VOICE 5", "VOICE 6"];
    foreach (i; 0 .. 6) {
      _resLabels[i] = buildLabel(voiceNames[i]);
      _resEnableKnobs[i] = buildKnob(cast(Params)(Params.voice1Enable + i * 5));
      _resPitchKnobs[i] = buildKnob(cast(Params)(Params.voice1Pitch + i * 5));
      _resFineKnobs[i] = buildKnob(cast(Params)(Params.voice1Fine + i * 5));
      _resGainKnobs[i] = buildKnob(cast(Params)(Params.voice1Gain + i * 5));
      _resPanKnobs[i] = buildKnob(cast(Params)(Params.voice1Pan + i * 5));
    }

    // Gain Meters
    addChild(_meters = mallocNew!UIGainMeters(this.context, _client));

    // Wet Filter Section
    _filterHeader = buildLabel("FILTER");
    _filterHPFKnob = buildKnob(Params.filterHPF);
    _filterHPFLabel = buildLabel("HPF");

    _filterLPFKnob = buildKnob(Params.filterLPF);
    _filterLPFLabel = buildLabel("LPF");

    _filterPeakFreqKnob = buildKnob(Params.filterPeakFreq);
    _filterPeakFreqLabel = buildLabel("PEAK FRQ");

    _filterPeakQKnob = buildKnob(Params.filterPeakQ);
    _filterPeakQLabel = buildLabel("PEAK Q");

    _filterPeakGainKnob = buildKnob(Params.filterPeakGain);
    _filterPeakGainLabel = buildLabel("PEAK dB");

    _filterBypassKnob = buildKnob(Params.filterBypass);
    _filterBypassLabel = buildLabel("BYPASS");

    // Reverb Section
    _reverbHeader = buildLabel("REVERB");
    _reverbEnableKnob = buildKnob(Params.reverbEnable);
    _reverbEnableLabel = buildLabel("ENABLE");

    _reverbMixKnob = buildKnob(Params.reverbMix);
    _reverbMixLabel = buildLabel("MIX");

    _reverbLengthKnob = buildKnob(Params.reverbLength);
    _reverbLengthLabel = buildLabel("LENGTH");

    _reverbLowsKnob = buildKnob(Params.reverbLows);
    _reverbLowsLabel = buildLabel("LOWS");

    _reverbHighsKnob = buildKnob(Params.reverbHighs);
    _reverbHighsLabel = buildLabel("HIGHS");

    // Window Resizer
    addChild(_resizer = mallocNew!UIWindowResizer(context()));
  }

  ~this() {
    _params[Params.chordPreset].removeListener(this);
    _params[Params.mode].removeListener(this);
    _params[Params.midiMode].removeListener(this);
    destroyFree(_font);
  }

  override void onAnimate(double dt, double time) nothrow @nogc {
    _meters.setDirtyWhole();
  }

  override void reflow() {
    super.reflow();
    const int W = position.width;
    const int H = position.height;

    // Header size
    int labelSize = H / 42; // slightly smaller label size to prevent trimming (was H/35)
    int headerSize = H / 22;
    int labelH = H / 35;

    _title.textSize = H / 18;
    _title.position = rectangle(20, 15, 200, H / 14);

    // --- LEFT PANEL (Globals layout: 2 columns) ---
    int colAX = 25;
    int colBX = 140;
    int knobSize = H / 10; // larger knob box size (was H/12)

    // Helper lambda to position a knob and its label
    void positionKnobAndLabel(UIKnob knob, UILabel label, int x, int y) {
      knob.position = rectangle(x, y, knobSize, knobSize);
      label.textSize = labelSize;
      label.position = rectangle(x - 20, y + knobSize + 2, knobSize + 40, labelH);
    }

    positionKnobAndLabel(_dryGainKnob, _dryGainLabel, colAX, 70);
    positionKnobAndLabel(_wetGainKnob, _wetGainLabel, colBX, 70);

    positionKnobAndLabel(_modeKnob, _modeLabel, colAX, 150);
    positionKnobAndLabel(_decayKnob, _decayLabel, colBX, 150);

    positionKnobAndLabel(_dampKnob, _dampLabel, colAX, 230);
    positionKnobAndLabel(_portamentoKnob, _portamentoLabel, colBX, 230);

    positionKnobAndLabel(_haasWidthKnob, _haasWidthLabel, colAX, 310);
    positionKnobAndLabel(_chordPresetKnob, _chordPresetLabel, colBX, 310);

    positionKnobAndLabel(_midiInputKnob, _midiInputLabel, colAX, 390);
    positionKnobAndLabel(_midiModeKnob, _midiModeLabel, colBX, 390);

    positionKnobAndLabel(_releaseTimeKnob, _releaseTimeLabel, colAX, 470);

    // --- RIGHT PANEL (Resonators, Filters & Reverb) ---
    int rightX = 260;

    int resColWidth = 75;
    _resEnableHeader.textSize = labelSize;
    _resEnableHeader.position = rectangle(rightX + 110, 15, resColWidth, labelH * 2);

    _resPitchHeader.textSize = labelSize;
    _resPitchHeader.position = rectangle(rightX + 185, 15, resColWidth, labelH * 2);

    _resFineHeader.textSize = labelSize;
    _resFineHeader.position = rectangle(rightX + 260, 15, resColWidth, labelH * 2);

    _resGainHeader.textSize = labelSize;
    _resGainHeader.position = rectangle(rightX + 335, 15, resColWidth, labelH * 2);

    _resPanHeader.textSize = labelSize;
    _resPanHeader.position = rectangle(rightX + 410, 15, resColWidth, labelH * 2);

    // Resonator Rows
    int rowY = 50;
    int rowH = 43;
    foreach (i; 0 .. 6) {
      int y = rowY + i * rowH;

      _resLabels[i].textSize = labelSize;
      _resLabels[i].position = rectangle(rightX, y + 10, 100, labelH);

      _resEnableKnobs[i].position = rectangle(rightX + 110, y, 40, 40);
      _resPitchKnobs[i].position = rectangle(rightX + 185, y, 40, 40);
      _resFineKnobs[i].position = rectangle(rightX + 260, y, 40, 40);
      _resGainKnobs[i].position = rectangle(rightX + 335, y, 40, 40);
      _resPanKnobs[i].position = rectangle(rightX + 410, y, 40, 40);
    }

    // Gain meters position
    _meters.position = rectangle(rightX + 465, 50, 160, 258);

    // --- FILTER SECTION (Bottom Left) ---
    int filterY = 320;
    _filterHeader.textSize = headerSize;
    _filterHeader.position = rectangle(rightX, filterY, 200, labelH * 2);

    int filterColX = rightX;
    int filterColW = 95; // widened columns (was 65)
    positionKnobAndLabel(_filterHPFKnob, _filterHPFLabel, filterColX, filterY + 35);
    positionKnobAndLabel(_filterLPFKnob, _filterLPFLabel, filterColX + filterColW, filterY + 35);
    positionKnobAndLabel(_filterPeakFreqKnob, _filterPeakFreqLabel, filterColX + filterColW * 2, filterY + 35);
    positionKnobAndLabel(_filterPeakQKnob, _filterPeakQLabel, filterColX + filterColW * 3, filterY + 35);
    positionKnobAndLabel(_filterPeakGainKnob, _filterPeakGainLabel, filterColX + filterColW * 4, filterY + 35);
    positionKnobAndLabel(_filterBypassKnob, _filterBypassLabel, filterColX + filterColW * 5, filterY + 35);

    // --- REVERB SECTION (Bottom Right) ---
    int reverbY = 440;
    _reverbHeader.textSize = headerSize;
    _reverbHeader.position = rectangle(rightX, reverbY, 200, labelH * 2);

    positionKnobAndLabel(_reverbEnableKnob, _reverbEnableLabel, filterColX, reverbY + 35);
    positionKnobAndLabel(_reverbMixKnob, _reverbMixLabel, filterColX + filterColW, reverbY + 35);
    positionKnobAndLabel(_reverbLengthKnob, _reverbLengthLabel, filterColX + filterColW * 2, reverbY + 35);
    positionKnobAndLabel(_reverbLowsKnob, _reverbLowsLabel, filterColX + filterColW * 3, reverbY + 35);
    positionKnobAndLabel(_reverbHighsKnob, _reverbHighsLabel, filterColX + filterColW * 4, reverbY + 35);

    // Window Resizer
    int hintSize = H / 20;
    _resizer.position = rectangle(W - hintSize, H - hintSize, hintSize, hintSize);
  }

  override void onParameterChanged(Parameter sender) {
    if (sender.index == Params.chordPreset) {
      if (auto p = cast(EnumParameter) sender) {
        _chordPresetLabel.text(chordPresetLabels[p.value()]);
      }
    } else if (sender.index == Params.mode) {
      if (auto p = cast(EnumParameter) sender) {
        _modeLabel.text(modeLabels[p.value()]);
      }
    } else if (sender.index == Params.midiMode) {
      if (auto p = cast(EnumParameter) sender) {
        _midiModeLabel.text(midiModeLabels[p.value()]);
      }
    }
  }

  override void onBeginParameterEdit(Parameter sender) {}
  override void onEndParameterEdit(Parameter sender) {}
  override void onBeginParameterHover(Parameter sender) {}
  override void onEndParameterHover(Parameter sender) {}

 private:
  UIKnob buildKnob(Params pid) {
    UIKnob knob;
    addChild(knob = mallocNew!UIKnob(this.context, _params[pid]));
    knob.knobRadius = 0.65f; // reverted to 0.65f so neon trails are visible
    knob.knobDiffuse = knobColor;
    knob.knobMaterial = RGBA(255, 0, 0, 0);
    knob.numLEDs = 0;
    knob.litTrailDiffuse = litColor;
    knob.unlitTrailDiffuse = unlitColor;
    knob.trailRadiusMin = 0.1;
    knob.trailRadiusMax = 0.8;
    return knob;
  }

  UILabel buildLabel(string text) {
    UILabel label;
    addChild(label = mallocNew!UILabel(this.context, _font, text));
    label.textColor = textColor;
    return label;
  }

  Font _font;
  UILabel _title;
  Parameter[] _params;
  RezonizerClient _client;
  UIWindowResizer _resizer;
  UIGainMeters _meters;

  // Global Controls
  UIKnob _dryGainKnob, _wetGainKnob, _modeKnob, _decayKnob, _dampKnob, _haasWidthKnob,
         _portamentoKnob, _chordPresetKnob, _midiInputKnob, _midiModeKnob, _releaseTimeKnob;
  UILabel _dryGainLabel, _wetGainLabel, _modeLabel, _decayLabel, _dampLabel, _haasWidthLabel,
          _portamentoLabel, _chordPresetLabel, _midiInputLabel, _midiModeLabel, _releaseTimeLabel;

  // Resonator headers
  UILabel _resEnableHeader, _resPitchHeader, _resFineHeader, _resGainHeader, _resPanHeader;

  // Resonator Rows
  UILabel[6] _resLabels;
  UIKnob[6] _resEnableKnobs, _resPitchKnobs, _resFineKnobs, _resGainKnobs, _resPanKnobs;

  // Wet Filters
  UILabel _filterHeader;
  UIKnob _filterHPFKnob, _filterLPFKnob, _filterPeakFreqKnob, _filterPeakQKnob, _filterPeakGainKnob, _filterBypassKnob;
  UILabel _filterHPFLabel, _filterLPFLabel, _filterPeakFreqLabel, _filterPeakQLabel, _filterPeakGainLabel, _filterBypassLabel;

  // Reverb
  UILabel _reverbHeader;
  UIKnob _reverbEnableKnob, _reverbMixKnob, _reverbLengthKnob, _reverbLowsKnob, _reverbHighsKnob;
  UILabel _reverbEnableLabel, _reverbMixLabel, _reverbLengthLabel, _reverbLowsLabel, _reverbHighsLabel;

  // Cyber-Neon Palette styling tokens
  enum knobColor = RGBA(40, 36, 50, 255);
  enum litColor = RGBA(151, 119, 255, 255);
  enum unlitColor = RGBA(30, 26, 38, 255);
  enum textColor = RGBA(215, 210, 230, 255);
}

/// Custom PBR Level Meter component.
class UIGainMeters : UIElement {
public:
  @nogc nothrow:

  this(UIContext context, RezonizerClient client) {
    super(context, flagPBR);
    _client = client;
  }

  override void onDrawPBR(
      ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap,
      ImageRef!RGBA materialMap, box2i[] dirtyRects) const pure {

    bool isBoxEmpty(box2i b) const pure {
      return b.max.x <= b.min.x || b.max.y <= b.min.y;
    }

    foreach (dirtyRect; dirtyRects) {
      ImageRef!RGBA diff = diffuseMap.cropImageRef(dirtyRect);
      ImageRef!L16 depth = depthMap.cropImageRef(dirtyRect);
      ImageRef!RGBA mat = materialMap.cropImageRef(dirtyRect);

      void drawRect(int xLeft, int yTop, int xRight, int yBottom, RGBA color, L16 depVal, RGBA matVal) const pure {
        box2i r = box2i(xLeft, yTop, xRight, yBottom).intersection(dirtyRect);
        if (isBoxEmpty(r)) return;

        ImageRef!RGBA dSub = diff.cropImageRef(box2i(r.min - dirtyRect.min, r.max - dirtyRect.min));
        ImageRef!L16 dpSub = depth.cropImageRef(box2i(r.min - dirtyRect.min, r.max - dirtyRect.min));
        ImageRef!RGBA mSub = mat.cropImageRef(box2i(r.min - dirtyRect.min, r.max - dirtyRect.min));

        foreach (y; 0 .. dSub.h) {
          dSub.scanline(y)[0 .. $] = color;
          dpSub.scanline(y)[0 .. $] = depVal;
          mSub.scanline(y)[0 .. $] = matVal;
        }
      }

      float levelToNormal(float level) const pure {
        if (level <= 1e-5f) return 0.0f;
        float db = convertLinearGainToDecibel(level);
        const float minDb = -60.0f;
        const float maxDb = 6.0f;
        if (db < minDb) return 0.0f;
        if (db > maxDb) return 1.0f;
        return (db - minDb) / (maxDb - minDb);
      }

      // 1. Draw Voice level bars (horizontal, local coordinates)
      int rowH = 43;
      int barW = 120;
      int barH = 6;
      int barStartX = 0;

      foreach (i; 0 .. 6) {
        int yCenter = i * rowH + 20;
        int yTop = yCenter - barH / 2;
        int yBottom = yTop + barH;

        // Background bar
        drawRect(barStartX, yTop, barStartX + barW, yBottom, unlitColor, L16(0), RGBA(0, 0, 0, 0));

        // Active bar
        float norm = levelToNormal(_client.voiceLevel(i));
        if (norm > 0.0f) {
          int activeW = cast(int)(norm * barW);
          if (activeW > 0) {
            drawRect(barStartX, yTop, barStartX + activeW, yBottom, litColor, L16(0), RGBA(0, 0, 0, 0));
          }
        }
      }

      // 2. Draw Stereo Output level bars (vertical, local coordinates)
      int outStartX = 140;
      int outYTop = 0;
      int outYBottom = 6 * rowH - 3;
      int outH = outYBottom - outYTop;
      int outW = 8;

      // Left Channel
      drawRect(outStartX, outYTop, outStartX + outW, outYBottom, unlitColor, L16(0), RGBA(0, 0, 0, 0));
      float leftNorm = levelToNormal(_client.outputLevel(0));
      if (leftNorm > 0.0f) {
        int fillH = cast(int)(leftNorm * outH);
        if (fillH > 0) {
          drawRect(outStartX, outYBottom - fillH, outStartX + outW, outYBottom, litColor, L16(0), RGBA(0, 0, 0, 0));
        }
      }

      // Right Channel
      int outRStartX = outStartX + 12;
      drawRect(outRStartX, outYTop, outRStartX + outW, outYBottom, unlitColor, L16(0), RGBA(0, 0, 0, 0));
      float rightNorm = levelToNormal(_client.outputLevel(1));
      if (rightNorm > 0.0f) {
        int fillH = cast(int)(rightNorm * outH);
        if (fillH > 0) {
          drawRect(outRStartX, outYBottom - fillH, outRStartX + outW, outYBottom, litColor, L16(0), RGBA(0, 0, 0, 0));
        }
      }
    }
  }

private:
  RezonizerClient _client;
  enum litColor = RGBA(151, 119, 255, 255);
  enum unlitColor = RGBA(30, 26, 38, 255);
}
