module kdr.comp1.gui;

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
enum RGBA knobColor = RGBA(96, 96, 96, 96);
enum RGBA litColor = RGBA(155, 255, 255, 0);
enum RGBA unlitColor = RGBA(0, 32, 32, 0);

// GUI for down/upward gain compressions.
class GainUI : UIElement {
 public:
  @nogc nothrow:

  this(UIContext context) {
    super(context, flagRaw);
  }

  override void onDrawRaw(ImageRef!RGBA rawMap, box2i[] dirtyRects) {
  }
}

/// GUI for comp1.
class Comp1GUI : PBRSimpleGUI {
 public:
  @nogc nothrow:
  ///
  this(Parameter[] params) {
    logDebug("Initialize %s", __FUNCTION__.ptr);

    static immutable float[] ratios = [1.0f, 1.25f, 1.5f, 1.75f, 2.0f];
    super(makeSizeConstraintsDiscrete(400, 600, ratios));

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
  UILabel _title, _date, _depthLabel, _timeLabel, _inGainLabel, _outGainLabel;
  UIWindowResizer _resizer;
  UIKnob _depth, _time, _inGain, _outGain;
  Parameter[] _params;
}
