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
import dplug.pbrwidgets : PBRBackgroundGUI;

import kdr.envelope : Envelope;
import kdr.envtool.params;
import kdr.logging : logDebug, logInfo;

private enum png1 = "114.png"; // "gray.png"; // "black.png"
private enum png2 = "black.png";
private enum png3 = "black.png";

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
      float srcx = point.x.value;
      float prev = 0, next = 1;
      foreach (i; 1 .. Envelope.MAX_POINTS - 1) {
        float px = envelopePointParamsAt(i, _params).x.value;
        if (prev < px && px < srcx) prev = px;
        if (srcx < px && px < next) next = px;
      }
      logDebug("newp.x %f, prev %f next %f", newp.x, prev, next);
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
    enum RGBA lineColor = RGBA(0, 255, 255, 96);
    enum RGBA gradColor = RGBA(0, 32, 32, 96);
    enum RGBA gridColor = RGBA(96, 96, 96, 96);
    enum RGBA darkColor = RGBA(128, 128, 128, 128);
    enum RGBA lightColor = RGBA(100, 200, 200, 200);

    Envelope env = buildEnvelope(_params);
    foreach (ref rect; dirtyRects) {
      ImageRef!RGBA cropped = cropImageRef(rawMap, rect);
      _canvas.initialize(cropped);
      _canvas.translate(-rect.min.x, -rect.min.y);

      // Draw grid.
      enum float gridWidth = 0.002;
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
      enum numLine = 1000;
      _canvas.fillStyle = lineColor;
      foreach (float n; 0 .. numLine) {
        float x = n / numLine;
        float y = env.getY(x);
        _canvas.fillCircle(point2position(vec2f(x, y)), position.width * 0.003);
      }

      auto grad = _canvas.createLinearGradient(0, 0, 0, position.height);
      grad.addColorStop(0, lineColor);
      grad.addColorStop(position.height, gradColor);
      _canvas.fillStyle = grad;

      _canvas.beginPath();
      _canvas.moveTo(point2position(vec2f(0, 0)));
      foreach (float n; 0 .. numLine) {
        float x = n / numLine;
        float y = env.getY(x);
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
  this(Parameter[] envParams) {
    logDebug("Initialize %s", __FUNCTION__.ptr);

    static immutable float[] ratios = [1.0f, 1.25f, 1.5f, 1.75f, 2.0f];
    super(makeSizeConstraintsDiscrete(400, 300, ratios));

    addChild(_resizer = mallocNew!UIWindowResizer(context()));
    addChild(_envui = mallocNew!EnvelopeUI(context(), envParams));
  }

  override void reflow() {
    super.reflow();
    const int W = position.width;
    const int H = position.height;

    enum hintSize = 10;
    _resizer.position = rectangle(W - hintSize, H - hintSize,
                                  hintSize, hintSize);
    _envui.position = rectangle(0, 0, W - hintSize, H - hintSize);
  }

 private:
  UIWindowResizer _resizer;
  EnvelopeUI _envui;
}
