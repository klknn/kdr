module kdr.envtool.gui;

import std.algorithm.comparison : clamp;
import std.math : isClose;

import dplug.core : mallocNew;
import dplug.math : vec2f, box2f, box2i, rectangle;
import dplug.gui : Click, flagRaw, flagAnimated, makeSizeConstraintsFixed,
  makeSizeConstraintsDiscrete, MouseState, GUIGraphics, UIContext, UIElement;
import dplug.graphics : cropImageRef, ImageRef, RGBA;
import dplug.canvas : Canvas;
import dplug.flatwidgets : UIWindowResizer;
import dplug.pbrwidgets : PBRBackgroundGUI;

import kdr.envelope : Envelope;
import kdr.logging : logDebug, logInfo;

private enum png1 = "114.png"; // "gray.png"; // "black.png"
private enum png2 = "black.png";
private enum png3 = "black.png";

/// UI for displaying/tweaking kdr.envelope.DynamicEnvelope.
class EnvelopeUI : UIElement {
 public:
  @nogc nothrow:

  /// Ctor.
  this(UIContext context, Envelope env) {
    logDebug("Initialize %s", __FUNCTION__.ptr);
    super(context, flagRaw | flagAnimated);
    _env = env;
  }

  override Click onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate) {
    // Initiate drag
    setDirtyWhole();

    _dragPoint = 0;
    foreach (p; _env) {
      vec2f center = point2position(p);
      box2f circleBox = box2f(center - pointRadius, center + pointRadius);
      if (circleBox.contains(x, y)) {
        logDebug("clicked %d-th point", _dragPoint);
        break;
      }
      ++_dragPoint;
    }
    return Click.startDrag;
  }

  override void onMouseDrag(int x, int y, int dx, int dy, MouseState mstate) {
    vec2f newp = position2point(x, y);  // is already clamped to [0, 1].
    if (_dragPoint == 0 || _dragPoint + 1 == _env.length) {
      // As bias, only y is changed.
      _env[0] = vec2f(0, newp.y);
      _env[$-1] = vec2f(1.00, newp.y);
    } else {
      // Clamp not to exceed neighbours.
      newp.x = clamp(newp.x, _env[_dragPoint - 1].x, _env[_dragPoint + 1].x);
      _env[_dragPoint] = newp;
    }
    logDebug("drag %d-th point to %f, %f", _dragPoint, newp.x, newp.y);
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
    foreach (ref rect; dirtyRects) {
      ImageRef!RGBA cropped = cropImageRef(rawMap, rect);
      _canvas.initialize(cropped);
      _canvas.fillStyle = _lineColor;
      _canvas.translate(-rect.min.x, -rect.min.y);

      foreach (p; _env) {
        _canvas.fillCircle(point2position(p), pointRadius);
      }

      _canvas.beginPath();
      _canvas.moveTo(point2position(vec2f(0, 0)));
      foreach (p; _env) {
        _canvas.lineTo(point2position(p));
      }
      _canvas.lineTo(point2position(vec2f(1, 0)));
      _canvas.fill();
    }
  }

  // Account for param changes.

  override void onBeginDrag() {
    setDirtyWhole();
  }

  override void onStopDrag() {
    setDirtyWhole();
  }

  override void onMouseEnter() {
    setDirtyWhole();
  }

  override void onMouseExit() {
    setDirtyWhole();
  }

 private:
  float pointRadius() { return position.width * _circleRadiusRatio; }

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
  Envelope _env;
  float _timeDisplayError = 0;
  int _dragPoint = -1;

  // Settings.
  enum RGBA _lineColor = RGBA(0, 255, 255, 96);
  enum float _circleRadiusRatio = 1.0 / 50;
}

unittest {
  GUIGraphics gui = new GUIGraphics(makeSizeConstraintsFixed(200, 100),
                                    flagRaw | flagAnimated);
  Envelope env = new Envelope;
  EnvelopeUI ui = new EnvelopeUI(gui.context, env);
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
  this(Envelope env) {
    logDebug("Initialize %s", __FUNCTION__.ptr);

    static immutable float[] ratios = [1.0f, 1.25f, 1.5f, 1.75f, 2.0f];
    super(makeSizeConstraintsDiscrete(400, 300, ratios));

    addChild(_resizer = mallocNew!UIWindowResizer(context()));
    addChild(_envui = mallocNew!EnvelopeUI(context(), env));
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
