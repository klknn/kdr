module kdr.envtool.gui;

import std.algorithm.comparison : clamp;
import std.math : isClose;

import dplug.core : mallocNew;
import dplug.client;
import dplug.math : vec2f, box2f, box2i, rectangle;
import dplug.gui : Click, flagRaw, flagAnimated, makeSizeConstraintsFixed,
  makeSizeConstraintsDiscrete, MouseState, GUIGraphics, UIContext, UIElement;
import dplug.graphics : cropImageRef, ImageRef, RGBA;
import dplug.canvas : Canvas;
import dplug.flatwidgets : UIWindowResizer;
import dplug.pbrwidgets; // : PBRBackgroundGUI;

import kdr.envelope : Envelope;
import kdr.envtool.params;
import kdr.logging : logDebug, logInfo;

private enum png1 = "114.png"; // "gray.png"; // "black.png"
private enum png2 = "black.png";
private enum png3 = "black.png";

enum RGBA lineColor = RGBA(0, 255, 255, 96);
enum RGBA gradColor = RGBA(0, 32, 32, 96);
enum RGBA gridColor = RGBA(100, 200, 200, 32);
// enum RGBA gridColor = RGBA(64, 64, 64, 64);
enum RGBA darkColor = RGBA(128, 128, 128, 128);
enum RGBA lightColor = RGBA(100, 200, 200, 200);
enum RGBA textColor = RGBA(155, 255, 255, 0);
enum RGBA knobColor = RGBA(96, 96, 96, 96);
enum RGBA litColor = RGBA(155, 255, 255, 0);
enum RGBA unlitColor = RGBA(0, 32, 32, 0);

/// UI for displaying/tweaking kdr.envelope.Envelope.
class EnvelopeUI : UIElement, IParameterListener {
 public:
  @nogc nothrow:

  /// Ctor.
  this(UIContext context, Parameter[] params) {
    logDebug("Initialize %s", __FUNCTION__.ptr);
    super(context, flagRaw | flagAnimated);
    _params = params;
    foreach (Parameter p; _params) p.addListener(this);
  }

  /// Dtor.
  ~this() { foreach (Parameter p; _params) p.removeListener(this); }

  override Click onMouseClick(
      int x, int y, int button, bool isDoubleClick, MouseState mstate) {
    // Initiate drag
    setDirtyWhole();

    _dragPoint = -1;
    float bias = envelopeBiasParam(_params).value;
    foreach (i; 0 .. Envelope.MAX_POINTS) {
      vec2f centerPoint;
      if (i == 0 || i + 1 == Envelope.MAX_POINTS) {
        centerPoint = vec2f(i == 0 ? 0 : 1, bias);
      } else {
        EnvelopePointParams point = envelopePointParamsAt(i, _params);
        if (!point.enabled.value) continue;
        centerPoint = vec2f(point.x.value, point.y.value);
      }

      vec2f center = point2position(centerPoint);
      box2f circleBox = box2f(center - pointRadius, center + pointRadius);
      if (circleBox.contains(x, y)) {
        _dragPoint = cast(int) i;
        logDebug("clicked %d-th point", _dragPoint);
        break;
      }
    }

    if (isDoubleClick) {
      if (_dragPoint != -1 && _dragPoint != 0 && _dragPoint + 1!= Envelope.MAX_POINTS) {
        // Found but not begin/end.
        EnvelopePointParams point = envelopePointParamsAt(_dragPoint, _params);
        if (point.curve.value) {
          point.enabled.beginParamEdit();
          point.enabled.setFromGUI(false);
          point.enabled.endParamEdit();
        } else {
          point.curve.beginParamEdit();
          point.curve.setFromGUI(true);
          point.curve.endParamEdit();
        }
      } else {
        // If not found, add a new point.
        foreach (i; 1 .. Envelope.MAX_POINTS - 1) {
          EnvelopePointParams point = envelopePointParamsAt(i, _params);
          // Find a disabled point.
          if (!point.enabled.value) {
            // Add the position.
            vec2f p = position2point(x, y);
            point.enabled.beginParamEdit();
            point.enabled.setFromGUI(true);
            point.enabled.endParamEdit();

            point.x.beginParamEdit();
            point.x.setFromGUI(p.x);
            point.x.endParamEdit();

            point.y.beginParamEdit();
            point.y.setFromGUI(p.y);
            point.y.endParamEdit();

            point.curve.beginParamEdit();
            point.curve.setFromGUI(false);
            point.curve.endParamEdit();

            break;
          }
        }
      }
      _dragPoint = -1;
      return Click.handled;
    }

    return Click.startDrag;
  }

  override void onMouseDrag(int x, int y, int dx, int dy, MouseState mstate) {
    if (_dragPoint == -1) return; // But no point is selected.

    vec2f newp = position2point(x, y);  // is already clamped to [0, 1].

    if (_dragPoint == 0 || _dragPoint + 1 == Envelope.MAX_POINTS) {
      // As bias, only y is changed.
      LinearFloatParameter bias = envelopeBiasParam(_params);
      bias.beginParamEdit();
      bias.setFromGUI(newp.y);
      bias.endParamEdit();
    } else {
      // Clamp not to exceed neighbours.
      EnvelopePointParams point = envelopePointParamsAt(_dragPoint, _params);
      const float srcx = point.x.value;
      float prev = 0, next = 1;
      foreach (i; 1 .. Envelope.MAX_POINTS - 1) {
        const float px = envelopePointParamsAt(i, _params).x.value;
        if (prev < px && px < srcx) prev = px;
        if (srcx < px && px < next) next = px;
      }
      newp.x = clamp(newp.x, prev, next);

      point.x.beginParamEdit();
      point.x.setFromGUI(newp.x);
      point.x.endParamEdit();

      point.y.beginParamEdit();
      point.y.setFromGUI(newp.y);
      point.y.endParamEdit();
    }

    setDirtyWhole();
  }

  override void onAnimate(double dt, double time) nothrow @nogc {
    if (_timeDisplayError > 0.0f) {
      _timeDisplayError = _timeDisplayError - dt;
      if (_timeDisplayError < 0) _timeDisplayError = 0;
      setDirtyWhole();
    }
  }

  override void onDrawRaw(ImageRef!RGBA rawMap, box2i[] dirtyRects) {
    Envelope env = buildEnvelope(_params);
    foreach (ref rect; dirtyRects) {
      ImageRef!RGBA cropped = cropImageRef(rawMap, rect);
      _canvas.initialize(cropped);
      _canvas.translate(-rect.min.x, -rect.min.y);

      // Draw grid.
      enum float gridWidth = 0.0015;
      int numGrid = 8;
      foreach (float i; 0 .. numGrid + 1) {
        _canvas.fillStyle = gridColor;
        _canvas.beginPath();
        _canvas.moveTo(point2position(vec2f(i / numGrid - gridWidth, 0)));
        _canvas.lineTo(point2position(vec2f(i / numGrid + gridWidth, 0)));
        _canvas.lineTo(point2position(vec2f(i / numGrid + gridWidth, 1)));
        _canvas.lineTo(point2position(vec2f(i / numGrid - gridWidth, 1)));
        _canvas.fill();

        _canvas.beginPath();
        _canvas.moveTo(point2position(vec2f(0, i / numGrid - gridWidth)));
        _canvas.lineTo(point2position(vec2f(0, i / numGrid + gridWidth)));
        _canvas.lineTo(point2position(vec2f(1, i / numGrid + gridWidth)));
        _canvas.lineTo(point2position(vec2f(1, i / numGrid - gridWidth)));
        _canvas.fill();
      }

      // Draw points.
      foreach (Envelope.Point p; env) {
        _canvas.fillStyle = p.isCurve ? darkColor : lightColor;
        _canvas.fillCircle(point2position(p), pointRadius);
      }

      // Draw envelope lines.
      auto grad = _canvas.createLinearGradient(0, 0, 0, position.height);
      grad.addColorStop(0, lineColor);
      grad.addColorStop(position.height, gradColor);
      _canvas.fillStyle = grad;
      _canvas.beginPath();
      _canvas.moveTo(point2position(vec2f(0, 0)));
      enum numLine = 1000;
      foreach (float n; 0 .. numLine) {
        const float x = n / numLine;
        const float y = env.getY(x);
        _canvas.lineTo(point2position(vec2f(x, y)));
      }
      _canvas.lineTo(point2position(vec2f(1, 0)));
      _canvas.fill();
    }
  }

  // Account for param changes.

  override void onParameterChanged(Parameter sender) {
    setDirtyWhole();
  }

  override void onBeginParameterEdit(Parameter sender) {}

  override void onEndParameterEdit(Parameter sender) {}

  override void onBeginParameterHover(Parameter sender) {}

  override void onEndParameterHover(Parameter sender) {}

 private:
  float pointRadius() { return position.width / 50; }

  // Converts point in [0, 1] to dirty rect position in UI.
  vec2f point2position(vec2f p) {
    const float w = position.width - pointRadius * 2;
    const float h = position.height- pointRadius * 2;
    return vec2f(w * p.x + pointRadius, h - h * p.y + pointRadius);
  }

  vec2f position2point(float[2] pos ...) {
    const float w = position.width - pointRadius * 2;
    const float h = position.height- pointRadius * 2;
    return vec2f(clamp((pos[0] - pointRadius) / w, 0, 1),
                 clamp((h - pos[1] + pointRadius) / h, 0, 1));
  }

  // States.
  Canvas _canvas;
  float _timeDisplayError = 0;
  int _dragPoint = -1;
  Parameter[] _params;
}

unittest {
  GUIGraphics gui = new GUIGraphics(makeSizeConstraintsFixed(200, 100),
                                    flagRaw | flagAnimated);
  EnvelopeUI ui = new EnvelopeUI(gui.context, []);
  ui.position = rectangle(0, 0, 200, 100);

  vec2f pos = ui.point2position(vec2f(0.1, 0.2));
  vec2f point = ui.position2point(pos.x, pos.y);
  assert(isClose(point.x, 0.1));
  assert(isClose(point.y, 0.2));
}

///
class EnvToolGUI : PBRBackgroundGUI!(png1, png2, png3, png3, png3, "") {
 public:
  @nogc nothrow:
  this(Parameter[] params) {
    logDebug("Initialize %s", __FUNCTION__.ptr);

    static immutable float[] ratios = [1.0f, 1.25f, 1.5f, 1.75f, 2.0f];
    super(makeSizeConstraintsDiscrete(500, 300, ratios));

    _params = params;
    _font = mallocNew!Font(cast(ubyte[]) import("FORCED SQUARE.ttf"));

    _title = buildLabel("kdr envtool");
    _date = buildLabel("build: " ~ __DATE__ ~ "");

    addChild(_resizer = mallocNew!UIWindowResizer(context()));
    addChild(_envui = mallocNew!EnvelopeUI(context(), params));

    _rateKnob = buildKnob(Params.rate);
    _rateLabel = buildLabel("rate");

    _depthKnob = buildKnob(Params.depth);
    _depthLabel = buildLabel("depth");

    _stereoOffsetKnob = buildKnob(Params.stereoOffset);
    _stereoOffsetLabel = buildLabel("offset");
  }

  override void reflow() {
    super.reflow();
    const int W = position.width;
    const int H = position.height;

    // Main.
    _envui.position = rectangle(0, 0, cast(int) (W * 0.8), cast(int) (H * 0.9));

    _title.position = rectangle(0, _envui.position.max.y, _envui.position.width / 2,
                                cast(int) (H * 0.1));
    _title.textSize = _title.position.height;

    _date.position = rectangle(_title.position.max.x,
                               _title.position.min.y + _title.position.height / 2,
                               _envui.position.width - _title.position.width,
                               _title.position.height / 2);
    _date.textSize = _title.textSize / 2;

    // Knobs.
    int knobSize = cast(int) (W * 0.15);
    int knobX = cast(int) (W * 0.825);
    int labelSize = knobSize / 4;
    int labelMargin = labelSize / 4;

    _rateKnob.position = rectangle(
        knobX, cast(int) (H * 0.025), knobSize, knobSize);
    _rateLabel.textSize = labelSize;
    _rateLabel.position = rectangle(
        knobX, _rateKnob.position.max.y, knobSize, labelSize);

    _depthKnob.position = rectangle(
        knobX, _rateLabel.position.max.y, knobSize, knobSize);
    _depthLabel.textSize = labelSize;
    _depthLabel.position = rectangle(
        knobX,  _depthKnob.position.max.y, knobSize, labelSize);

    _stereoOffsetKnob.position = rectangle(
        knobX, _depthLabel.position.max.y, knobSize, knobSize);
    _stereoOffsetLabel.textSize = labelSize;
    _stereoOffsetLabel.position = rectangle(
        knobX, _stereoOffsetKnob.position.max.y, knobSize, labelSize);

    int hintSize = 10;
    _resizer.position = rectangle(W - hintSize, H - hintSize,
                                  hintSize, hintSize);
  }

 private:
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
    label.textColor = textColor;
    return label;
  }

  Font _font;
  UILabel _title, _date;
  Parameter[] _params;
  UIWindowResizer _resizer;
  EnvelopeUI _envui;
  UIKnob _rateKnob, _depthKnob, _stereoOffsetKnob;
  UILabel _rateLabel, _depthLabel, _stereoOffsetLabel;

  enum litTrailDiffuse = RGBA(151, 119, 255, 100);
  enum unlitTrailDiffuse = RGBA(81, 54, 108, 0);
}

unittest {
  Parameter[] ps = buildEnvelopeParameters();
  auto gui = new EnvToolGUI(ps);
  gui.reflow();
}
