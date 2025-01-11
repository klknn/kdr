module kdr.comp1.gui;

import std.algorithm : max;
import dplug.canvas;
import dplug.client;
import dplug.gui;
import dplug.pbrwidgets;
import dplug.flatwidgets : UIWindowResizer;
import kdr.simplegui;
import kdr.logging : logDebug, logInfo;
import kdr.comp1.params;

enum RGBA TEXT_COLOR = RGBA(155, 255, 255, 0);
enum RGBA lineColor = RGBA(0, 255, 255, 96);
enum RGBA gradColor = RGBA(0, 64, 64, 96);
enum RGBA gridColor = RGBA(100, 200, 200, 32);
enum RGBA darkColor = RGBA(128, 128, 128, 128);
enum RGBA lightColor = RGBA(100, 200, 200, 100);
enum RGBA textColor = RGBA(155, 255, 255, 0);
enum RGBA knobColor = RGBA(96, 96, 96, 0);
enum RGBA litColor = RGBA(155, 255, 255, 0);
enum RGBA unlitColor = RGBA(0, 32, 32, 0);

// GUI for down/upward gain compressions.
class CompUI : UIElement {
public:
@nogc nothrow:

  this(UIContext context, Parameter above, Parameter below) {
    super(context, flagRaw);
    _above_param = above;
    _below_param = below;
  }

  override void onDrawRaw(ImageRef!RGBA rawMap, box2i[] dirtyRects) {
    double aboveThresholdH = thresholdWidth(_above_param);
    double belowThresholdH = thresholdWidth(_below_param);

    foreach (ref rect; dirtyRects) {
      ImageRef!RGBA cropped = cropImageRef(rawMap, rect);
      _canvas.initialize(cropped);
      _canvas.translate(-rect.min.x, -rect.min.y);

      // Draw background.
      // _canvas.fillStyle =  RGBA(0, 32, 32, 200);
      // _canvas.fillRect(0, 0, position.width, position.height);

      // Draw gain compression ranges.
      _canvas.fillStyle = belowColor;
      _canvas.fillRect(0, 0, (1 - belowThresholdH) * position.width, position.height);
      _canvas.fillStyle = aboveColor;
      _canvas.fillRect(position.width * (1 - aboveThresholdH), 0,
        aboveThresholdH * position.width, position.height);
    }
  }

private:
  double thresholdWidth(Parameter p) {
    return max(minThreshold, (cast(GainParameter) p).value) / minThreshold;
  }

  Canvas _canvas;
  Parameter _above_param, _below_param;
  enum minThreshold = -80;
  enum belowColor = RGBA(100, 150, 150, 200); //lightColor;
  enum aboveColor = RGBA(150, 100, 100, 200);
}

enum BackgroundStart = RGBA(0, 255, 255, 32);
enum BackgroundEnd = RGBA(0, 64, 64, 64);
enum compBGColor = RGBA(0, 32, 32, 32);

class CompBackgroundUI : UIElement {
public:
@nogc nothrow:

  this(UIContext context) {
    super(context, flagRaw);
  }

  override void onDrawRaw(ImageRef!RGBA rawMap, box2i[] dirtyRects) {
    foreach (ref rect; dirtyRects) {
      ImageRef!RGBA cropped = cropImageRef(rawMap, rect);
      _canvas.initialize(cropped);
      _canvas.translate(-rect.min.x, -rect.min.y);

      // Draw background.
      // auto grad = _canvas.createLinearGradient(0, 0, 0, position.height);
      // grad.addColorStop(0, BackgroundStart);
      // grad.addColorStop(position.height, BackgroundEnd);
      _canvas.fillStyle = compBGColor;
      _canvas.fillRect(0, 0, position.width, position.height);

      // Draw grid.
      // auto linegrad = _canvas.createLinearGradient(0, 0, 0, position.height);
      // linegrad.addColorStop(0, gridColor);
      // linegrad.addColorStop(position.height, RGBA(0, 100, 100, 100));
      _canvas.fillStyle = gridColor;
      float dh = cast(float) position.height / 8;
      float dw = cast(float) position.width / 8;
      foreach (float i; 1 .. 9) {
        _canvas.fillRect(dw * i - 2, 0, 2, position.height);
      }

    }
  }

private:
  Canvas _canvas;
}

class CompKnobsBackgroundUI : UIElement {
public:
@nogc nothrow:

  this(UIContext context) {
    super(context, flagRaw);
  }

  override void onDrawRaw(ImageRef!RGBA rawMap, box2i[] dirtyRects) {
    foreach (ref rect; dirtyRects) {
      ImageRef!RGBA cropped = cropImageRef(rawMap, rect);
      _canvas.initialize(cropped);
      _canvas.translate(-rect.min.x, -rect.min.y);

      // Draw background.
      auto grad = _canvas.createLinearGradient(0, 0, 0, position.height);
      grad.addColorStop(0, BackgroundStart);
      grad.addColorStop(position.height, BackgroundEnd);
      _canvas.fillStyle = compBGColor;
      _canvas.fillRect(0, 0, position.width, position.height);
    }
  }

private:
  Canvas _canvas;
}

/// GUI for comp1.
class Comp1GUI : PBRSimpleGUI {
public:
@nogc nothrow:
  ///
  this(Parameter[] params) {
    logDebug("Initialize %s", __FUNCTION__.ptr);

    static immutable float[] ratios = [1.0f, 1.25f, 1.5f, 1.75f, 2.0f];
    super(makeSizeConstraintsDiscrete(400, 580, ratios));

    addChild(_resizer = mallocNew!UIWindowResizer(context()));

    _params = params;
    _font = mallocNew!Font(cast(ubyte[]) import("FORCED SQUARE.ttf"));
    _title = buildLabel("kdr comp1");
    _date = buildLabel("" ~ __DATE__ ~ "" ~ __TIME__);

    _depth = buildKnob(Params.depth);
    _depthLabel = buildLabel("DEPTH");
    _time = buildKnob(Params.time);
    _timeLabel = buildLabel("TIME");
    _inGain = buildKnob(Params.inGain);
    _inGainLabel = buildLabel("IN GAIN");
    _outGain = buildKnob(Params.outGain);
    _outGainLabel = buildLabel("OUT GAIN");

    this.addChild(_compBackground = mallocNew!CompBackgroundUI(this.context));
    this.addChild(_highComp = mallocNew!CompUI(
        this.context, params[Params.aboveThresholdH], params[Params.belowThresholdH]));
    _gainH = buildKnob(Params.gainH);
    _gainHLabel = buildLabel("H");
    this.addChild(_midComp = mallocNew!CompUI(
        this.context, params[Params.aboveThresholdM], params[Params.belowThresholdM]));
    _gainM = buildKnob(Params.gainH);
    _gainMLabel = buildLabel("M");
    this.addChild(_lowComp = mallocNew!CompUI(
        this.context, params[Params.aboveThresholdL], params[Params.belowThresholdL]));
    _gainL = buildKnob(Params.gainL);
    _gainLLabel = buildLabel("L");

    this.addChild(_compKnobsBG = mallocNew!CompKnobsBackgroundUI(this.context));

    _upwardStrength = buildKnob(Params.upwardStrength);
    _upwardStrengthLabel = buildLabel("UPWARD");
    _downwardStrength = buildKnob(Params.downwardStrength);
    _downwardStrengthLabel = buildLabel("DOWNWARD");
  }

  ~this() {
    destroyFree(_font);
  }

  override void reflow() {
    super.reflow();
    const int W = position.width;
    const float S = W / cast(float)(context.getDefaultUIWidth());

    // Header.
    int headerY = 10;
    _title.position = rect(0, headerY, 250, 40);
    _title.textSize = 40 * S;
    _date.position = rect(250, headerY, 150, 15);
    _date.textSize = 15 * S;

    // Top knobs.
    int knobSize = 100;
    int knobLabelSize = 15;
    int knobY = 50;
    _depth.position = rect(0, knobY, knobSize, knobSize);
    _depthLabel.position = rect(0, knobY + knobSize, knobSize, knobLabelSize);
    _depthLabel.textSize = knobLabelSize * S;
    _time.position = rect(knobSize, knobY, knobSize, knobSize);
    _timeLabel.position = rect(knobSize, knobY + knobSize, knobSize, knobLabelSize);
    _timeLabel.textSize = knobLabelSize * S;
    _inGain.position = rect(knobSize * 2, knobY, knobSize, knobSize);
    _inGainLabel.position = rect(knobSize * 2, knobY + knobSize, knobSize, knobLabelSize);
    _inGainLabel.textSize = knobLabelSize * S;
    _outGain.position = rect(knobSize * 3, knobY, knobSize, knobSize);
    _outGainLabel.position = rect(knobSize * 3, knobY + knobSize, knobSize, knobLabelSize);
    _outGainLabel.textSize = knobLabelSize * S;

    // Multi-band compressor.
    int compHeight = 70;
    int compWidth = 350;
    int compKnobSize = 50;
    _highComp.position = rect(0, 200, compWidth, compHeight);
    _midComp.position = rect(0, 200 + compHeight + 10, compWidth, compHeight);
    _lowComp.position = rect(0, 200 + (compHeight + 10) * 2, compWidth, compHeight);

    int compTotalHeight = compHeight * 3 + 10 * 4;
    _compBackground.position = rect(0, 200 - 10, compWidth, compTotalHeight);
    _compKnobsBG.position = rect(350, 200 - 10, 50, compTotalHeight);
    // _gainH.knobDiffuse = RGBA(200, 200, 200, 0);
    int compKnobY = 200;
    _gainH.position = rect(350, compKnobY, compKnobSize, compKnobSize);
    compKnobY += compKnobSize;
    _gainHLabel.position = rect(350, compKnobY, compKnobSize, 20);

    compKnobY += 20 + 10;
    _gainM.position = rect(350, compKnobY, compKnobSize, compKnobSize);
    compKnobY += compKnobSize;
    _gainMLabel.position = rect(350, compKnobY, compKnobSize, 20);

    compKnobY += 20 + 10;
    _gainL.position = rect(350, compKnobY, compKnobSize, compKnobSize);
    compKnobY += compKnobSize;
    _gainLLabel.position = rect(350, compKnobY, compKnobSize, 20);

    int bottomKnobY = compKnobY + 20 + 10;
    _upwardStrength.position = rect(knobSize, bottomKnobY, knobSize, knobSize);
    _upwardStrengthLabel.position = rect(knobSize, bottomKnobY + knobSize, knobSize, 20);
    _upwardStrengthLabel.textSize = knobLabelSize * S;
    _downwardStrength.position = rect(knobSize * 2, bottomKnobY, knobSize, knobSize);
    _downwardStrengthLabel.position = rect(knobSize * 2, bottomKnobY + knobSize, knobSize, 20);
    _downwardStrengthLabel.textSize = knobLabelSize * S;

    // Footer.
    int hintSize = 20;
    _resizer.position = rect(400 - hintSize, 600 - hintSize, hintSize, hintSize);
  }

private:
  box2i rect(int x, int y, int w, int h) {
    const int W = position.width;
    const float S = W / cast(float)(context.getDefaultUIWidth());
    return rectangle(x, y, w, h).scaleByFactor(S);
  }

  UIKnob buildKnob(Params pid) {
    UIKnob knob;
    addChild(knob = mallocNew!UIKnob(this.context, _params[pid]));
    knob.knobRadius = 0.65f;
    knob.knobDiffuse = knobColor;
    // NOTE: material [R(smooth), G(metal), B(shiny), A(phisycal)]
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
    label.textColor = TEXT_COLOR;
    return label;
  }

  Font _font;
  UILabel _title, _date, _depthLabel, _timeLabel, _inGainLabel, _outGainLabel,
  _gainHLabel, _gainMLabel, _gainLLabel,
  _upwardStrengthLabel, _downwardStrengthLabel;
  UIWindowResizer _resizer;
  UIKnob _depth, _time, _inGain, _outGain,
  _gainH, _gainM, _gainL,
  _upwardStrength, _downwardStrength;
  Parameter[] _params;
  CompUI _highComp, _midComp, _lowComp;
  CompBackgroundUI _compBackground;
  CompKnobsBackgroundUI _compKnobsBG;
}
