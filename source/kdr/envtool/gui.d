module kdr.envtool.gui;

import dplug.gui.element;
import dplug.canvas;
import dplug.flatwidgets;
import dplug.pbrwidgets;

import kdr.envelope;
import kdr.logging;

private enum png1 = "114.png"; // "gray.png"; // "black.png"
private enum png2 = "black.png";
private enum png3 = "black.png";

class EnvelopeUI : UIElement {
 public:
  @nogc nothrow:

  this(UIContext context) {
    logInfo("Initialize %s", __FUNCTION__.ptr);
    super(context, flagRaw | flagAnimated);
    _env.setXY(0.25, 1.0);
    _env.setXY(0.50, 0.5);
    _env.setXY(0.75, 0.5);
  }

  override Click onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate) {
    // Initiate drag
    setDirtyWhole();

    int i;
    foreach (px, py; _env.points) {
      vec2f center = fromPoint(px, py);
      box2f circleBox = box2f(center - pointRadius, center + pointRadius);
      if (circleBox.contains(x, y)) {
        logDebug("clicked %d-th point", i);
      }
      ++i;
    }
    return Click.startDrag;
  }

  override void onDrawRaw(ImageRef!RGBA rawMap, box2i[] dirtyRects) {
    float w = position.width - pointRadius * 2;
    float h = position.height- pointRadius * 2;
    logInfo("position %f %f", w, h);

    foreach (ref rect; dirtyRects) {
      ImageRef!RGBA cropped = cropImageRef(rawMap, rect);
      _canvas.initialize(cropped);
      _canvas.fillStyle = _lineColor;
      _canvas.translate(-rect.min.x, -rect.min.y);

      foreach (x, y; _env.points) {
        _canvas.fillCircle(fromPoint(x, y), pointRadius);
      }

      _canvas.beginPath();
      _canvas.moveTo(fromPoint(0, 0));
      foreach (x, y; _env.points) {
        _canvas.lineTo(fromPoint(x, y));
      }
      _canvas.fill();
    }
  }

 private:
  float pointRadius() { return position.width * _circleRadiusRatio; }

  // Converts point in [0, 1] to dirty rect position in UI.
  vec2f fromPoint(float[2] p ...) {
    float w = position.width - pointRadius * 2;
    float h = position.height- pointRadius * 2;
    return vec2f(w * p[0] + pointRadius, h - h * p[1] + pointRadius);
  }

  RGBA _lineColor = RGBA(0, 255, 255, 96);
  Canvas _canvas;
  DynamicEnvelope _env;
  enum float _circleRadiusRatio = 1.0 / 50;
}


///
class EnvToolGUI : PBRBackgroundGUI!(png1, png2, png3, png3, png3, "") {
 public:
  @nogc nothrow:
  this() {
    logInfo("Initialize %s", __FUNCTION__.ptr);

    static immutable float[] ratios = [1.0f, 1.25f, 1.5f, 1.75f, 2.0f];
    super(makeSizeConstraintsDiscrete(400, 300, ratios));

    addChild(_resizer = mallocNew!UIWindowResizer(context()));
    addChild(_envui = mallocNew!EnvelopeUI(context()));
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
