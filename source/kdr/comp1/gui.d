module kdr.comp1.gui;

import dplug.client;
import dplug.gui;
import dplug.pbrwidgets;
import dplug.flatwidgets : UIWindowResizer;
import kdr.simplegui;
import kdr.logging : logDebug, logInfo;

enum RGBA TEXT_COLOR = RGBA(155, 255, 255, 0);

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
    super(makeSizeConstraintsDiscrete(600, 300, ratios));

    addChild(_resizer = mallocNew!UIWindowResizer(context()));

    _font = mallocNew!Font(cast(ubyte[]) import("FORCED SQUARE.ttf"));
    _title = buildLabel("kdr comp1");
    _date = buildLabel("build: " ~ __DATE__ ~ "");
  }

  ~this() {
    destroyFree(_font);
  }

  override void reflow() {
    super.reflow();
    const int W = position.width;
    const int H = position.height;
    const int margin = H / 50;

    // etc.
    const int titleSize = H / 10;
    _title.position = rectangle(0, margin,
                                W / 2,
                                titleSize);
    _title.textSize = titleSize;

    int dateLabelSize = cast(int) _title.textSize / 3;
    _date.position = rectangle(_title.position.max.x,
                               H - dateLabelSize,
                               W - _title.position.width,
                               dateLabelSize);
    _date.textSize = dateLabelSize;

    int hintSize = H / 20;
    _resizer.position = rectangle(W - hintSize, H - hintSize,
                                  hintSize, hintSize);
  }

 private:
  UILabel buildLabel(string text) {
    UILabel label;
    addChild(label = mallocNew!UILabel(this.context, _font, text));
    label.textColor = TEXT_COLOR;
    return label;
  }

  Font _font;
  UILabel _title, _date;
  UIWindowResizer _resizer;
}
