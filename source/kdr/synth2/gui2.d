/**
Modern, page-based graphical user interface for Synth2.

Copyright: kdr contributors, 2026.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module kdr.synth2.gui2;

import core.stdc.stdio : snprintf;
import mir.math : cos, exp, log, sin, PI;

import dplug.canvas : Canvas;
import dplug.client.params : BoolParameter, FloatParameter, IntegerParameter,
  Parameter, IParameterListener;
import dplug.core : mallocNew, destroyFree, makeVec, Vec;
import dplug.flatwidgets : makeSizeConstraintsDiscrete, UIWindowResizer;
import dplug.graphics : Font, ImageRef, L16, RGBA, cropImageRef, fillAll;
import dplug.gui : Click, GUIGraphics, MouseState, UIContext, UIElement,
  flagAnimated, flagPBR, flagRaw;
import dplug.math : box2i, rectangle;
import dplug.pbrwidgets : KnobStyle, UILabel, UIKnob, UIOnOffSwitch;

import kdr.filter : Filter, FilterKind;
import kdr.synth2.params : Params;
import kdr.waveform : Waveform;

private static string fontRaw = import("FORCED SQUARE.ttf");

private enum int baseWidth = 960;
private enum int baseHeight = 600;
private enum int headerHeight = 54;

private enum RGBA bg = RGBA(218, 224, 228, 0);
private enum RGBA headerBg = RGBA(247, 249, 250, 0);
private enum RGBA cardBg = RGBA(244, 247, 249, 0);
private enum RGBA cardEdge = RGBA(184, 195, 202, 0);
private enum RGBA textPrimary = RGBA(30, 42, 50, 0);
private enum RGBA textMuted = RGBA(77, 94, 104, 0);
private enum RGBA cyan = RGBA(0, 151, 174, 100);
private enum RGBA cyanBright = RGBA(0, 151, 174, 0);
private enum RGBA orange = RGBA(231, 119, 32, 100);
private enum RGBA magenta = RGBA(202, 62, 124, 100);

private enum RGBA darkBg = RGBA(9, 13, 20, 0);
private enum RGBA darkHeaderBg = RGBA(15, 21, 31, 0);
private enum RGBA darkCardBg = RGBA(20, 28, 39, 0);
private enum RGBA darkCardEdge = RGBA(45, 61, 78, 0);
private enum RGBA darkTextPrimary = RGBA(224, 235, 242, 0);
private enum RGBA darkTextMuted = RGBA(120, 145, 160, 0);

private enum Page : int { synth, mod, fx }
private enum Theme : int { light, dark, envtool }

private interface IPageHost {
  nothrow @nogc:
  void setPage(Page page);
  Page activePage() const;
}

private interface IThemeHost {
  nothrow @nogc:
  Theme theme() const;
  void cycleTheme();
}

/// Clickable page tab; its text is a separate UILabel layered above it.
private class PageTabUI : UIElement {
 public:
  nothrow @nogc:

  this(UIContext context, IPageHost host, IThemeHost themeHost, Page page) {
    super(context, flagPBR);
    _host = host;
    _themeHost = themeHost;
    _page = page;
  }

  override Click onMouseClick(int, int, int, bool, MouseState) {
    _host.setPage(_page);
    return Click.handled;
  }

  override void onDrawPBR(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap,
                          ImageRef!RGBA materialMap, box2i[] dirtyRects) {
    const active = _host.activePage == _page;
    const dark = _themeHost.theme == Theme.dark;
    foreach (rect; dirtyRects) {
      diffuseMap.cropImageRef(rect).fillAll(
        dark ? (active ? RGBA(27, 43, 57, 0) : darkHeaderBg)
             : (active ? RGBA(218, 235, 239, 0) : headerBg));
      depthMap.cropImageRef(rect).fillAll(L16(0));
      materialMap.cropImageRef(rect).fillAll(RGBA(0, 0, 0, 0));
      if (active) {
        auto underline = rectangle(0, position.height - 3, position.width, 3)
          .intersection(rect);
        if (!underline.empty)
          diffuseMap.cropImageRef(underline).fillAll(cyanBright);
      }
    }
  }

 private:
  IPageHost _host;
  IThemeHost _themeHost;
  Page _page;
}

/// Header selector for switching the three visual themes.
private class ThemeSelectorUI : UIElement {
 public:
  nothrow @nogc:

  this(UIContext context, Font font, IThemeHost host) {
    super(context, flagPBR);
    _host = host;
    addChild(_label = mallocNew!UILabel(context, font, ""));
    themeChanged();
  }

  override void reflow() {
    _label.position = rectangle(position.min.x + 2, position.min.y + 1,
                                position.width - 4, position.height - 2);
    _label.textSize = position.height * 0.34f;
  }

  override Click onMouseClick(int, int, int, bool, MouseState) {
    _host.cycleTheme();
    return Click.handled;
  }

  void themeChanged() {
    final switch (_host.theme) {
      case Theme.light: _label.text = "THEME  LIGHT"; break;
      case Theme.dark: _label.text = "THEME  DARK"; break;
      case Theme.envtool: _label.text = "THEME  ENVTOOL"; break;
    }
    _label.textColor = _host.theme == Theme.dark ? darkTextPrimary : textPrimary;
    setDirtyWhole();
  }

  override void onDrawPBR(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap,
                          ImageRef!RGBA materialMap, box2i[] dirtyRects) {
    RGBA color;
    final switch (_host.theme) {
      case Theme.light: color = RGBA(231, 237, 240, 0); break;
      case Theme.dark: color = RGBA(29, 42, 54, 0); break;
      case Theme.envtool: color = RGBA(214, 235, 235, 0); break;
    }
    foreach (rect; dirtyRects) {
      diffuseMap.cropImageRef(rect).fillAll(color);
      depthMap.cropImageRef(rect).fillAll(L16(4000));
      materialMap.cropImageRef(rect).fillAll(RGBA(220, 10, 30, 0));
    }
  }

 private:
  IThemeHost _host;
  UILabel _label;
}

/// Flat 2D knob with a high-contrast value arc. This avoids PBR lighting and
/// stays legible at every supported UI scale.
private class FlatKnobUI : UIElement, IParameterListener {
 public:
  nothrow @nogc:

  this(UIContext context, Parameter param, IThemeHost host) {
    super(context, flagRaw);
    _param = param;
    _host = host;
    _param.addListener(this);
  }

  ~this() { _param.removeListener(this); }

  override Click onMouseClick(int, int, int, bool isDoubleClick, MouseState) {
    if (isDoubleClick) {
      _param.beginParamEdit();
      setNormalized(cast(float)_param.getNormalizedDefault());
      _param.endParamEdit();
      return Click.handled;
    }
    _dragValue = cast(float)_param.getNormalized();
    _param.beginParamEdit();
    _editing = true;
    return Click.startDrag;
  }

  override void onMouseDrag(int, int, int dx, int dy, MouseState) {
    _dragValue += (dx - dy) * 0.006f;
    if (_dragValue < 0) _dragValue = 0;
    if (_dragValue > 1) _dragValue = 1;
    setNormalized(_dragValue);
  }

  override void onStopDrag() {
    if (_editing) {
      _param.endParamEdit();
      _editing = false;
    }
  }

  override void onDrawRaw(ImageRef!RGBA rawMap, box2i[] dirtyRects) {
    const float cx = position.width * 0.5f;
    const float cy = position.height * 0.5f;
    const float radius = (position.width < position.height ? position.width
                                                           : position.height) * 0.32f;
    const float value = cast(float)_param.getNormalized();
    foreach (rect; dirtyRects) {
      auto cropped = rawMap.cropImageRef(rect);
      _canvas.initialize(cropped);
      _canvas.translate(-rect.min.x, -rect.min.y);
      _canvas.fillStyle = RGBA(0, 0, 0, 0);
      _canvas.fillRect(0, 0, position.width, position.height);

      _canvas.fillStyle = RGBA(151, 164, 172, 255);
      foreach (i; 0 .. 35) {
        const float angle = -PI * 0.75f + PI * 1.5f * i / 34f;
        _canvas.fillCircle(cx + cos(angle) * radius,
                           cy + sin(angle) * radius, 1.4f);
      }
      _canvas.fillStyle = _host.theme == Theme.envtool
        ? RGBA(0, 190, 198, 255) : RGBA(0, 151, 174, 255);
      const int litPoints = cast(int)(value * 34f + 0.5f);
      foreach (i; 0 .. litPoints + 1) {
        const float angle = -PI * 0.75f + PI * 1.5f * i / 34f;
        _canvas.fillCircle(cx + cos(angle) * radius,
                           cy + sin(angle) * radius, 2.0f);
      }

      _canvas.fillStyle = isMouseOver ? RGBA(255, 255, 255, 255)
                                      : RGBA(235, 239, 241, 255);
      _canvas.fillCircle(cx, cy, radius - 4);
      _canvas.fillStyle = RGBA(71, 86, 95, 255);
      const float indicator = -PI * 0.75f + PI * 1.5f * value;
      _canvas.fillCircle(cx + cos(indicator) * (radius - 8),
                         cy + sin(indicator) * (radius - 8), 2.2f);
    }
  }

  override void onParameterChanged(Parameter) { setDirtyWhole(); }
  override void onBeginParameterEdit(Parameter) {}
  override void onEndParameterEdit(Parameter) {}
  override void onBeginParameterHover(Parameter) {}
  override void onEndParameterHover(Parameter) {}

 private:
  void setNormalized(float value) {
    if (auto fp = cast(FloatParameter)_param) fp.setFromGUINormalized(value);
    else if (auto ip = cast(IntegerParameter)_param) ip.setFromGUINormalized(value);
  }

  Canvas _canvas;
  Parameter _param;
  IThemeHost _host;
  float _dragValue;
  bool _editing;
}

/// Compact discrete selector. Clicking advances to the next parameter value.
private class SelectorUI : UIElement, IParameterListener {
 public:
  nothrow @nogc:

  this(UIContext context, Font font, IntegerParameter param, IThemeHost host) {
    super(context, flagPBR);
    _param = param;
    _host = host;
    _param.addListener(this);
    addChild(_valueLabel = mallocNew!UILabel(context, font, ""));
    themeChanged();
    updateText();
  }

  ~this() { _param.removeListener(this); }

  override void reflow() {
    _valueLabel.position = rectangle(position.min.x + 2, position.min.y + 1,
                                     position.width - 4, position.height - 2);
    _valueLabel.textSize = position.height * 0.42f;
  }

  override Click onMouseClick(int, int, int button, bool, MouseState) {
    int value = _param.value;
    if (button == 1) {
      value--;
      if (value < _param.minValue) value = _param.maxValue;
    } else {
      value++;
      if (value > _param.maxValue) value = _param.minValue;
    }
    _param.beginParamEdit();
    _param.setFromGUI(value);
    _param.endParamEdit();
    return Click.handled;
  }

  override void onDrawPBR(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap,
                          ImageRef!RGBA materialMap, box2i[] dirtyRects) {
    const dark = _host.theme == Theme.dark;
    foreach (rect; dirtyRects) {
      diffuseMap.cropImageRef(rect).fillAll(
        dark ? (isMouseOver ? RGBA(40, 62, 75, 0) : RGBA(29, 42, 54, 0))
             : (isMouseOver ? RGBA(218, 231, 235, 0) : RGBA(231, 237, 240, 0)));
      depthMap.cropImageRef(rect).fillAll(L16(5000));
      materialMap.cropImageRef(rect).fillAll(RGBA(220, 10, 30, 0));
    }
  }

  override void onParameterChanged(Parameter) { updateText(); setDirtyWhole(); }
  override void onBeginParameterEdit(Parameter) {}
  override void onEndParameterEdit(Parameter) {}
  override void onBeginParameterHover(Parameter) {}
  override void onEndParameterHover(Parameter) {}

  void themeChanged() {
    _valueLabel.textColor = _host.theme == Theme.dark
      ? darkTextPrimary : textPrimary;
    setDirtyWhole();
  }

 private:
  void updateText() {
    _param.toStringN(_text.ptr, _text.length);
    size_t length;
    while (length < _text.length && _text[length] != '\0') length++;
    _valueLabel.text(cast(string) _text[0 .. length]);
  }

  IntegerParameter _param;
  IThemeHost _host;
  UILabel _valueLabel;
  char[48] _text;
}

/// Parameter-driven graph. It has a fixed rectangle and never participates in
/// layout calculation, avoiding the coupling that broke the legacy GUI.
private class ScopeUI : UIElement, IParameterListener {
 public:
  enum Kind { waveform, envelope, filter, modEnvelope }

  nothrow @nogc:

  this(UIContext context, Kind kind, Parameter[] params, IThemeHost host,
       Params p0, Params p1, Params p2, Params p3, Params p4, Params p5,
       int count) {
    super(context, flagRaw | flagAnimated);
    _kind = kind;
    _params = params;
    _host = host;
    _ids = [p0, p1, p2, p3, p4, p5];
    _count = count;
    foreach (i; 0 .. _count) _params[_ids[i]].addListener(this);
  }

  ~this() {
    foreach (i; 0 .. _count) _params[_ids[i]].removeListener(this);
  }

  override void onDrawRaw(ImageRef!RGBA rawMap, box2i[] dirtyRects) {
    foreach (rect; dirtyRects) {
      auto cropped = rawMap.cropImageRef(rect);
      _canvas.initialize(cropped);
      _canvas.translate(-rect.min.x, -rect.min.y);
      _canvas.fillStyle = scopeBackground();
      _canvas.fillRect(0, 0, position.width, position.height);
      drawGrid();
      final switch (_kind) {
        case Kind.waveform: drawWaveform(); break;
        case Kind.envelope: drawEnvelope(); break;
        case Kind.filter: drawFilter(); break;
        case Kind.modEnvelope: drawModEnvelope(); break;
      }
      _canvas.fillStyle = scopeFrame();
      _canvas.fillRect(0, 0, position.width, 1);
      _canvas.fillRect(0, position.height - 1, position.width, 1);
      _canvas.fillRect(0, 0, 1, position.height);
      _canvas.fillRect(position.width - 1, 0, 1, position.height);
    }
  }

  override void onParameterChanged(Parameter) { setDirtyWhole(); }
  override void onBeginParameterEdit(Parameter) {}
  override void onEndParameterEdit(Parameter) {}
  override void onBeginParameterHover(Parameter) {}
  override void onEndParameterHover(Parameter) {}

 private:
  enum int pad = 7;

  float norm(int index) {
    auto p = _params[_ids[index]];
    if (auto fp = cast(FloatParameter) p) return cast(float) fp.getNormalized();
    if (auto ip = cast(IntegerParameter) p) return cast(float) ip.getNormalized();
    return 0;
  }

  RGBA scopeBackground() {
    final switch (_host.theme) {
      case Theme.light: return RGBA(250, 252, 253, 250);
      case Theme.dark: return RGBA(8, 19, 28, 245);
      case Theme.envtool: return RGBA(0, 32, 32, 235);
    }
  }

  RGBA scopeFrame() {
    final switch (_host.theme) {
      case Theme.light: return RGBA(160, 176, 185, 220);
      case Theme.dark: return RGBA(54, 99, 117, 210);
      case Theme.envtool: return RGBA(70, 150, 150, 210);
    }
  }

  RGBA gridColor() {
    final switch (_host.theme) {
      case Theme.light: return RGBA(134, 154, 165, 65);
      case Theme.dark: return RGBA(48, 87, 104, 52);
      case Theme.envtool: return RGBA(100, 200, 200, 42);
    }
  }

  RGBA scopeArea() {
    final switch (_host.theme) {
      case Theme.light: return RGBA(45, 174, 193, 92);
      case Theme.dark: return RGBA(15, 94, 120, 128);
      case Theme.envtool: return RGBA(0, 96, 104, 125);
    }
  }

  RGBA scopeLine() {
    final switch (_host.theme) {
      case Theme.light: return RGBA(0, 137, 161, 255);
      case Theme.dark: return RGBA(89, 236, 245, 255);
      case Theme.envtool: return RGBA(0, 255, 255, 255);
    }
  }

  RGBA scopePoint() {
    final switch (_host.theme) {
      case Theme.light: return RGBA(221, 103, 28, 255);
      case Theme.dark: return RGBA(255, 171, 68, 255);
      case Theme.envtool: return RGBA(100, 220, 220, 255);
    }
  }

  RGBA modLine() {
    final switch (_host.theme) {
      case Theme.light: return RGBA(190, 48, 112, 255);
      case Theme.dark: return RGBA(245, 110, 182, 255);
      case Theme.envtool: return RGBA(0, 255, 255, 255);
    }
  }

  void drawGrid() {
    _canvas.fillStyle = gridColor();
    if (_kind == Kind.filter) {
      // 20 Hz .. 20 kHz logarithmic X axis and +12 .. -48 dB Y axis.
      foreach (i; 1 .. 4)
        _canvas.fillRect(pad + (position.width - pad * 2) * i / 3, pad, 1,
                         position.height - pad * 2);
      foreach (i; 0 .. 6)
        _canvas.fillRect(pad, pad + (position.height - pad * 2) * i / 5,
                         position.width - pad * 2, 1);
      return;
    }
    const int divisions = _host.theme == Theme.envtool ? 8 : 4;
    foreach (i; 1 .. divisions) {
      _canvas.fillRect(position.width * i / divisions, pad, 1,
                       position.height - pad * 2);
      _canvas.fillRect(pad, position.height * i / divisions,
                       position.width - pad * 2, 1);
    }
  }

  float waveValue(Waveform wave, float phase, float pulseWidth) {
    final switch (wave) {
      case Waveform.sine: return sin(phase * 2f * PI);
      case Waveform.saw: return 1f - phase * 2f;
      case Waveform.pulse: return phase < pulseWidth ? 1f : -1f;
      case Waveform.triangle:
        return phase < 0.5f ? phase * 4f - 1f : 3f - phase * 4f;
      case Waveform.noise:
        return cast(float) ((cast(int)(phase * 997) * 67) % 113) / 56f - 1f;
    }
  }

  void drawWaveLane(Waveform wave, float pw, int centerY, float amplitude,
                    RGBA line, RGBA area) {
    const int innerW = position.width - pad * 2;
    int previousY = centerY;
    foreach (x; pad .. position.width - pad) {
      const float phase = cast(float)(x - pad) / (innerW - 1);
      const int y = cast(int)(centerY - waveValue(wave, phase, pw) * amplitude);
      const int fillTop = y < centerY ? y : centerY;
      const int fillBottom = y > centerY ? y : centerY;
      _canvas.fillStyle = area;
      _canvas.fillRect(x, fillTop, 1, fillBottom - fillTop + 1);
      _canvas.fillStyle = line;
      const int top = y < previousY ? y : previousY;
      const int bottom = y > previousY ? y : previousY;
      _canvas.fillRect(x, top, 2, bottom - top + 2);
      previousY = y;
    }
  }

  void drawWaveTrace(Waveform wave, float pw, int centerY, float amplitude,
                     float frequencyRatio, RGBA color) {
    const int innerW = position.width - pad * 2;
    int previousY = centerY;
    foreach (x; pad .. position.width - pad) {
      const float basePhase = cast(float)(x - pad) / (innerW - 1);
      float phase = basePhase * frequencyRatio;
      if (phase > 1f) phase -= 1f;
      const int y = cast(int)(centerY - waveValue(wave, phase, pw) * amplitude);
      const int top = y < previousY ? y : previousY;
      const int bottom = y > previousY ? y : previousY;
      _canvas.fillStyle = color;
      _canvas.fillRect(x, top, 1, bottom - top + 1);
      previousY = y;
    }
  }

  void drawWaveform() {
    const float pw = _count > 1 ? norm(1) : 0.5f;
    const wave1 = cast(Waveform)(cast(IntegerParameter)_params[_ids[0]]).value;
    if (_count < 4) {
      drawWaveLane(wave1, pw, position.height / 2,
                   (position.height - pad * 2) * 0.42f,
                   scopeLine(), scopeArea());
      return;
    }

    const wave2 = cast(Waveform)(cast(IntegerParameter)_params[_ids[2]]).value;
    const sub = cast(Waveform)(cast(IntegerParameter)_params[_ids[3]]).value;
    const float detune = _count > 4 ? norm(4) : 0;
    const int unison = _count > 5
      ? (cast(IntegerParameter)_params[_ids[5]]).value : 1;
    if (detune > 0 && unison > 1) {
      auto ghost = scopeLine();
      ghost.a = cast(ubyte)(45f + detune * 75f);
      foreach (voice; 1 .. unison) {
        const float semitones = log(detune + 1f) * 2f *
          log(voice + 1f) / log(8f);
        const float frequencyRatio = exp(log(2f) * semitones / 12f);
        drawWaveTrace(wave1, pw, cast(int)(position.height * 0.24f),
                      position.height * 0.17f, frequencyRatio, ghost);
      }
    }
    // Separate lanes keep all three sources readable. SUB is intentionally
    // smallest because it is a supporting oscillator.
    drawWaveLane(wave1, pw, cast(int)(position.height * 0.24f),
                 position.height * 0.17f, scopeLine(), scopeArea());
    drawWaveLane(wave2, pw, cast(int)(position.height * 0.58f),
                 position.height * 0.13f, RGBA(238, 126, 36, 255),
                 RGBA(238, 126, 36, 55));
    drawWaveLane(sub, pw, cast(int)(position.height * 0.84f),
                 position.height * 0.065f, RGBA(211, 68, 137, 255),
                 RGBA(211, 68, 137, 48));
  }

  void lineArea(int x0, int y0, int x1, int y1, RGBA color) {
    const int floor = position.height - pad;
    const int span = x1 - x0;
    foreach (offset; 0 .. span + 1) {
      const int y = y0 + (y1 - y0) * offset / (span == 0 ? 1 : span);
      _canvas.fillStyle = scopeArea();
      _canvas.fillRect(x0 + offset, y, 1, floor - y);
      _canvas.fillStyle = color;
      _canvas.fillRect(x0 + offset, y - 1, 2, 3);
    }
  }

  void drawEnvelope() {
    const int w = position.width;
    const int h = position.height;
    const int floor = h - pad;
    const int innerW = w - pad * 2;
    const int ax = pad + cast(int)(innerW * (0.08f + norm(0) * 0.22f));
    const int dx = ax + cast(int)(innerW * (0.08f + norm(1) * 0.20f));
    const int rx = w - pad - cast(int)(innerW * (0.08f + norm(3) * 0.20f));
    const int sy = floor - cast(int)((h - pad * 2) * norm(2) * 0.86f);
    lineArea(pad, floor, ax, pad, scopeLine());
    lineArea(ax, pad, dx, sy, scopeLine());
    lineArea(dx, sy, rx, sy, scopeLine());
    lineArea(rx, sy, w - pad, floor, scopeLine());
    _canvas.fillStyle = scopePoint();
    _canvas.fillCircle(ax, pad, 3);
    _canvas.fillCircle(dx, sy, 3);
    _canvas.fillCircle(rx, sy, 3);
  }

  void drawModEnvelope() {
    const int w = position.width;
    const int floor = position.height - pad;
    const int ax = pad + cast(int)((w - pad * 2) * (0.10f + norm(0) * 0.32f));
    const int dx = ax + cast(int)((w - pad * 2) * (0.15f + norm(1) * 0.35f));
    lineArea(pad, floor, ax, pad, modLine());
    lineArea(ax, pad, dx, floor, modLine());
    lineArea(dx, floor, w - pad, floor, modLine());
  }

  void drawFilter() {
    const int innerW = position.width - pad * 2;
    const int innerH = position.height - pad * 2;
    const kind = cast(FilterKind)(cast(IntegerParameter)_params[_ids[0]]).value;
    const float cutoff = cast(float)(cast(FloatParameter)_params[_ids[1]]).value;
    const float resonance = cast(float)(cast(FloatParameter)_params[_ids[2]]).value;
    _responseFilter.setParams(kind, cutoff, resonance);
    const int zeroY = pad + cast(int)(12f / 60f * innerH);
    int previousY = zeroY;
    foreach (x; pad .. position.width - pad) {
      const float axis = cast(float)(x - pad) / (innerW - 1);
      const float frequency = 20f * exp(log(1000f) * axis);
      float magnitude = _responseFilter.responseMagnitude(frequency);
      // Guard the display against cancellation at extreme cutoff/Q values.
      if (!(magnitude > 0)) magnitude = 0.000001f;
      if (magnitude > 4f) magnitude = 4f;
      float dB = 20f * log(magnitude) / log(10f);
      if (dB > 12f) dB = 12f;
      if (dB < -48f) dB = -48f;
      const int y = pad + cast(int)((12f - dB) / 60f * innerH);
      const int fillTop = y < zeroY ? y : zeroY;
      const int fillBottom = y > zeroY ? y : zeroY;
      _canvas.fillStyle = scopeArea();
      _canvas.fillRect(x, fillTop, 1, fillBottom - fillTop + 1);
      _canvas.fillStyle = scopeLine();
      const int lineTop = y < previousY ? y : previousY;
      const int lineBottom = y > previousY ? y : previousY;
      _canvas.fillRect(x, lineTop - 1, 2, lineBottom - lineTop + 3);
      previousY = y;
    }
  }

  Canvas _canvas;
  Kind _kind;
  Parameter[] _params;
  IThemeHost _host;
  Filter _responseFilter;
  Params[6] _ids;
  int _count;
}

/// New Synth2 GUI. The legacy GUI remains intact in gui.d.
class Synth2GUI2 : GUIGraphics, IPageHost, IThemeHost {
 public:
  nothrow @nogc:

  this(Parameter[] params) {
    static immutable float[] ratios = [0.75f, 1f, 1.25f, 1.5f, 1.75f, 2f];
    super(makeSizeConstraintsDiscrete(baseWidth, baseHeight, ratios),
          flagPBR | flagAnimated);
    setUpdateMargin(0);
    _params = params;
    _font = mallocNew!Font(cast(ubyte[])fontRaw);
    foreach (page; 0 .. 3) _pageChildren[page] = makeVec!UIElement();
    _cards = makeVec!Card();
    _themedLabels = makeVec!ThemedLabel();
    _themeControls = makeVec!ThemeControl();

    buildHeader();
    buildSynthPage();
    buildModPage();
    buildFXPage();
    addChild(_resizer = mallocNew!UIWindowResizer(context));
    setPage(Page.synth);

    _defaultRects = makeVec!box2i(_children.length);
    _defaultTextSize = makeVec!float(_children.length);
    foreach (i, child; _children) {
      _defaultRects[i] = child.position;
      if (auto label = cast(UILabel)child) _defaultTextSize[i] = label.textSize;
    }
  }

  ~this() { _font.destroyFree(); }

  override void reflow() {
    super.reflow();
    const float scale = position.width / cast(float)baseWidth;
    foreach (i, child; _children) {
      child.position = _defaultRects[i].scaleByFactor(scale);
      if (auto label = cast(UILabel)child)
        label.textSize = _defaultTextSize[i] * scale;
    }
    const int hint = cast(int)(18 * scale);
    _resizer.position = rectangle(position.width - hint, position.height - hint,
                                  hint, hint);
  }

  override void onDrawPBR(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap,
                          ImageRef!RGBA materialMap, box2i[] dirtyRects) {
    const float scale = position.width / cast(float)baseWidth;
    foreach (dirty; dirtyRects) {
      diffuseMap.cropImageRef(dirty).fillAll(currentBackground());
      depthMap.cropImageRef(dirty).fillAll(L16(0));
      materialMap.cropImageRef(dirty).fillAll(RGBA(0, 0, 0, 0));

      auto header = rectangle(0, 0, position.width,
                              cast(int)(headerHeight * scale)).intersection(dirty);
      if (!header.empty)
        diffuseMap.cropImageRef(header).fillAll(currentHeaderBackground());

      auto headerEdge = rectangle(0, cast(int)(headerHeight * scale) - 1,
                                  position.width, 1).intersection(dirty);
      if (!headerEdge.empty)
        diffuseMap.cropImageRef(headerEdge).fillAll(currentCardEdge());

      foreach (card; _cards[]) {
        if (card.page != _activePage) continue;
        const scaledCard = card.rect.scaleByFactor(scale);
        auto rect = scaledCard.intersection(dirty);
        if (rect.empty) continue;
        diffuseMap.cropImageRef(rect).fillAll(currentCardBackground());

        auto left = rectangle(scaledCard.min.x, scaledCard.min.y, 1,
                              scaledCard.height).intersection(dirty);
        auto right = rectangle(scaledCard.max.x - 1, scaledCard.min.y, 1,
                               scaledCard.height).intersection(dirty);
        auto bottom = rectangle(scaledCard.min.x, scaledCard.max.y - 1,
                                scaledCard.width, 1).intersection(dirty);
        if (!left.empty) diffuseMap.cropImageRef(left).fillAll(currentCardEdge());
        if (!right.empty) diffuseMap.cropImageRef(right).fillAll(currentCardEdge());
        if (!bottom.empty) diffuseMap.cropImageRef(bottom).fillAll(currentCardEdge());

        auto top = rectangle(card.rect.min.x, card.rect.min.y, card.rect.width, 3)
          .scaleByFactor(scale).intersection(dirty);
        if (!top.empty)
          diffuseMap.cropImageRef(top).fillAll(themeAccent(card.accent));
      }
    }
  }

  void setTempo(double tempo) {
    if (_tempoValue == tempo) return;
    int length = snprintf(_tempoText.ptr, _tempoText.length, "%.1f BPM", tempo);
    if (length > 0) _tempo.text(cast(string)_tempoText[0 .. length]);
    _tempoValue = tempo;
  }

  override void setPage(Page page) {
    _activePage = page;
    foreach (p; 0 .. 3)
      foreach (child; _pageChildren[p][]) child.visibility = p == page;
    applyTheme();
  }

  override Page activePage() const { return _activePage; }
  override Theme theme() const { return _theme; }

  override void cycleTheme() {
    _theme = cast(Theme)((cast(int)_theme + 1) % 3);
    applyTheme();
  }

 private:
  struct Card { box2i rect; Page page; RGBA accent; }
  struct ThemedLabel { UILabel label; RGBA lightColor; }
  struct ThemeControl { UIElement element; Page page; bool darkOnly; }

  RGBA currentBackground() const {
    return _theme == Theme.dark ? darkBg : bg;
  }

  RGBA currentHeaderBackground() const {
    return _theme == Theme.dark ? darkHeaderBg : headerBg;
  }

  RGBA currentCardBackground() const {
    return _theme == Theme.dark ? darkCardBg : cardBg;
  }

  RGBA currentCardEdge() const {
    return _theme == Theme.dark ? darkCardEdge : cardEdge;
  }

  RGBA themeAccent(RGBA color) const {
    if (_theme != Theme.dark) return color;
    if (color == cyan) return RGBA(47, 211, 227, 100);
    if (color == orange) return RGBA(255, 151, 49, 100);
    if (color == magenta) return RGBA(230, 82, 158, 100);
    return color;
  }

  RGBA themeTextColor(RGBA color) const {
    if (_theme != Theme.dark) return color;
    if (color == textPrimary) return darkTextPrimary;
    if (color == textMuted) return darkTextMuted;
    if (color == cyanBright) return RGBA(89, 236, 245, 0);
    return color;
  }

  void applyTheme() {
    foreach (entry; _themedLabels[])
      entry.label.textColor = themeTextColor(entry.lightColor);
    foreach (entry; _themeControls[])
      entry.element.visibility = entry.page == _activePage &&
        (entry.darkOnly == (_theme == Theme.dark));
    foreach (child; _children) {
      if (auto selector = cast(SelectorUI) child) selector.themeChanged();
      if (auto scopeWidget = cast(ScopeUI) child) scopeWidget.setDirtyWhole();
      if (auto flat = cast(FlatKnobUI) child) flat.setDirtyWhole();
      if (auto toggle = cast(UIOnOffSwitch) child) {
        toggle.diffuseOn = _theme == Theme.dark
          ? RGBA(89, 236, 245, 0) : cyanBright;
        toggle.diffuseOff = _theme == Theme.dark
          ? RGBA(37, 49, 59, 0) : RGBA(192, 202, 208, 0);
        toggle.setDirtyWhole();
      }
    }
    if (_themeSelector !is null) _themeSelector.themeChanged();
    foreach (tab; _tabs[]) tab.setDirtyWhole();
    setDirtyWhole();
  }

  void buildHeader() {
    // Keep the same lowercase "kdr product" wordmark used by envtool.
    addAlwaysLabel("kdr", rectangle(18, 8, 54, 36), 17, cyanBright);
    addAlwaysLabel("synth2", rectangle(70, 8, 120, 36), 25, textPrimary);
    addAlwaysLabel("visual polysynth", rectangle(194, 8, 160, 20), 10, textMuted);
    addAlwaysLabel("build: " ~ __DATE__ ~ " " ~ __TIME__,
                   rectangle(194, 28, 162, 14), 7, cyanBright);

    static immutable string[3] names = ["SYNTH", "MOD", "FX"];
    foreach (i; 0 .. 3) {
      auto tab = mallocNew!PageTabUI(context, this, this, cast(Page)i);
      tab.position = rectangle(374 + i * 104, 8, 96, 38);
      addChild(tab);
      _tabs[i] = tab;
      addAlwaysLabel(names[i], tab.position, 12, textPrimary);
    }
    _themeSelector = mallocNew!ThemeSelectorUI(context, _font, this);
    _themeSelector.position = rectangle(686, 12, 96, 30);
    addChild(_themeSelector);
    _tempo = addAlwaysLabel("120.0 BPM", rectangle(790, 14, 145, 24), 12,
                            textMuted);
  }

  void buildSynthPage() {
    addCard(Page.synth, rectangle(14, 64, 420, 334), cyan);
    section(Page.synth, "OSCILLATORS", 26, 73, 180);
    graph(Page.synth, ScopeUI.Kind.waveform, rectangle(26, 99, 396, 105),
          Params.osc1Waveform, Params.oscPulseWidth,
          Params.osc2Waveform, Params.oscSubWaveform, 6,
          Params.osc1Det, Params.osc1Unison);

    selector(Page.synth, Params.osc1Waveform, 26, 220, 82, "OSC 1");
    knob(Page.synth, Params.osc1Det, 116, 214, "DET");
    knob(Page.synth, Params.osc1FM, 168, 214, "FM");
    selector(Page.synth, Params.osc2Waveform, 226, 220, 82, "OSC 2");
    knob(Page.synth, Params.osc2Pitch, 316, 214, "PITCH");
    knob(Page.synth, Params.osc2Fine, 368, 214, "FINE");

    knob(Page.synth, Params.oscMix, 26, 280, "MIX");
    knob(Page.synth, Params.oscPulseWidth, 78, 280, "WIDTH");
    knob(Page.synth, Params.oscKeyShift, 130, 280, "KEY");
    knob(Page.synth, Params.oscTune, 182, 280, "TUNE");
    knob(Page.synth, Params.oscPhase, 234, 280, "PHASE");
    knob(Page.synth, Params.osc1Unison, 286, 280, "UNISON");

    selector(Page.synth, Params.oscSubWaveform, 26, 352, 82, "SUB");
    knob(Page.synth, Params.oscSubVol, 116, 342, "LEVEL");
    toggle(Page.synth, Params.oscSubOct, 174, 350, "-1 OCT");
    toggle(Page.synth, Params.osc2Ring, 232, 350, "RING");
    toggle(Page.synth, Params.osc2Sync, 282, 350, "SYNC");
    toggle(Page.synth, Params.osc2Track, 332, 350, "TRACK");

    addCard(Page.synth, rectangle(444, 64, 245, 334), orange);
    section(Page.synth, "FILTER", 456, 73, 100);
    graph(Page.synth, ScopeUI.Kind.filter, rectangle(456, 99, 221, 105),
          Params.filterKind, Params.filterCutoff, Params.filterQ,
          Params.filterKind, 3);
    selector(Page.synth, Params.filterKind, 456, 220, 95, "TYPE");
    knob(Page.synth, Params.filterCutoff, 559, 214, "CUTOFF");
    knob(Page.synth, Params.filterQ, 611, 214, "RESO");
    knob(Page.synth, Params.filterEnvAmount, 456, 280, "ENV");
    knob(Page.synth, Params.filterTrack, 508, 280, "TRACK");
    knob(Page.synth, Params.saturation, 560, 280, "DRIVE");
    toggle(Page.synth, Params.filterUseVelocity, 620, 288, "VELOCITY");

    envelopeCard(Page.synth, rectangle(699, 64, 247, 160), "AMP ENVELOPE",
                 Params.ampAttack, cyan);
    envelopeCard(Page.synth, rectangle(699, 234, 247, 164), "FILTER ENVELOPE",
                 Params.filterAttack, orange);

    addCard(Page.synth, rectangle(14, 408, 300, 178), magenta);
    section(Page.synth, "MASTER / VOICE", 26, 417, 190);
    knob(Page.synth, Params.ampGain, 26, 450, "GAIN");
    knob(Page.synth, Params.ampVel, 78, 450, "VELOCITY");
    selector(Page.synth, Params.voiceKind, 136, 456, 88, "MODE");
    knob(Page.synth, Params.voicePoly, 232, 450, "VOICES");
    knob(Page.synth, Params.voicePortament, 26, 516, "PORTA");
    toggle(Page.synth, Params.voicePortamentAuto, 84, 524, "AUTO");

    addCard(Page.synth, rectangle(324, 408, 300, 178), cyan);
    section(Page.synth, "MOD ENVELOPE", 336, 417, 170);
    graph(Page.synth, ScopeUI.Kind.modEnvelope, rectangle(336, 446, 174, 124),
          Params.menvAttack, Params.menvDecay, Params.menvAmount,
          Params.menvDest, 3);
    knob(Page.synth, Params.menvAttack, 520, 448, "ATTACK");
    knob(Page.synth, Params.menvDecay, 572, 448, "DECAY");
    knob(Page.synth, Params.menvAmount, 520, 514, "AMOUNT");
    selector(Page.synth, Params.menvDest, 572, 520, 42, "DEST");

    addCard(Page.synth, rectangle(634, 408, 312, 178), orange);
    section(Page.synth, "PERFORMANCE", 646, 417, 150);
    addPageLabel(Page.synth, "Signal flow", rectangle(646, 454, 100, 18),
                 10, textMuted);
    addPageLabel(Page.synth, "OSC  >  FILTER  >  AMP", rectangle(646, 477, 270, 22),
                 14, textPrimary);
    addPageLabel(Page.synth, "Use MOD and FX pages for routing and processing",
                 rectangle(646, 515, 280, 30), 9, textMuted);
  }

  void buildModPage() {
    lfoCard(Page.mod, rectangle(14, 64, 300, 522), "LFO 1", Params.lfo1Wave,
            Params.lfo1Dest, Params.lfo1Sync, Params.lfo1Speed,
            Params.lfo1Mul, Params.lfo1Amount, Params.lfo1Trigger, cyan);
    lfoCard(Page.mod, rectangle(324, 64, 300, 522), "LFO 2", Params.lfo2Wave,
            Params.lfo2Dest, Params.lfo2Sync, Params.lfo2Speed,
            Params.lfo2Mul, Params.lfo2Amount, Params.lfo2Trigger, magenta);

    addCard(Page.mod, rectangle(634, 64, 312, 522), orange);
    section(Page.mod, "MODULATION ENVELOPE", 646, 73, 240);
    graph(Page.mod, ScopeUI.Kind.modEnvelope, rectangle(646, 105, 288, 175),
          Params.menvAttack, Params.menvDecay, Params.menvAmount,
          Params.menvDest, 3);
    knob(Page.mod, Params.menvAttack, 646, 300, "ATTACK");
    knob(Page.mod, Params.menvDecay, 706, 300, "DECAY");
    knob(Page.mod, Params.menvAmount, 766, 300, "AMOUNT");
    selector(Page.mod, Params.menvDest, 826, 306, 96, "DESTINATION");
    addPageLabel(Page.mod, "MOD SOURCES", rectangle(646, 390, 150, 18), 11,
                 textMuted);
    addPageLabel(Page.mod, "LFO 1", rectangle(646, 420, 80, 20), 13, cyanBright);
    addPageLabel(Page.mod, "LFO 2", rectangle(646, 450, 80, 20), 13,
                 RGBA(245, 110, 182, 0));
    addPageLabel(Page.mod, "ENV", rectangle(646, 480, 80, 20), 13,
                 RGBA(255, 171, 68, 0));
    addPageLabel(Page.mod, "Destination and amount are edited directly in each source.",
                 rectangle(646, 525, 278, 34), 9, textMuted);
  }

  void buildFXPage() {
    addCard(Page.fx, rectangle(14, 64, 220, 522), magenta);
    section(Page.fx, "EFFECT", 26, 73, 100);
    selector(Page.fx, Params.effectKind, 26, 112, 196, "ALGORITHM");
    knob(Page.fx, Params.effectCtrl1, 34, 170, "CONTROL 1");
    knob(Page.fx, Params.effectCtrl2, 94, 170, "CONTROL 2");
    knob(Page.fx, Params.effectMix, 154, 170, "MIX");
    addPageLabel(Page.fx, "MULTI EFFECT", rectangle(26, 290, 196, 24), 14,
                 textPrimary);
    addPageLabel(Page.fx, "Algorithm-dependent macro controls",
                 rectangle(26, 324, 196, 30), 9, textMuted);

    addCard(Page.fx, rectangle(244, 64, 220, 522), cyan);
    section(Page.fx, "EQ / PAN", 256, 73, 110);
    knob(Page.fx, Params.eqFreq, 264, 120, "FREQ");
    knob(Page.fx, Params.eqLevel, 324, 120, "GAIN");
    knob(Page.fx, Params.eqQ, 384, 120, "Q");
    knob(Page.fx, Params.eqTone, 294, 200, "TONE");
    knob(Page.fx, Params.eqPan, 354, 200, "PAN");
    addPageLabel(Page.fx, "TONE SHAPING", rectangle(256, 310, 196, 24), 14,
                 textPrimary);

    addCard(Page.fx, rectangle(474, 64, 250, 522), orange);
    section(Page.fx, "DELAY", 486, 73, 90);
    selector(Page.fx, Params.delayKind, 486, 112, 100, "TYPE");
    selector(Page.fx, Params.delayMul, 596, 112, 116, "SYNC NOTE");
    knob(Page.fx, Params.delayTime, 486, 170, "TIME");
    knob(Page.fx, Params.delaySpread, 544, 170, "SPREAD");
    knob(Page.fx, Params.delayFeedback, 602, 170, "FEEDBACK");
    knob(Page.fx, Params.delayTone, 515, 250, "TONE");
    knob(Page.fx, Params.delayMix, 573, 250, "MIX");
    addPageLabel(Page.fx, "STEREO DELAY", rectangle(486, 350, 226, 24), 14,
                 textPrimary);

    addCard(Page.fx, rectangle(734, 64, 212, 522), cyan);
    section(Page.fx, "CHORUS", 746, 73, 100);
    toggle(Page.fx, Params.chorusOn, 746, 112, "ENABLED");
    knob(Page.fx, Params.chorusMulti, 796, 104, "VOICES");
    knob(Page.fx, Params.chorusTime, 854, 104, "TIME");
    knob(Page.fx, Params.chorusDepth, 746, 180, "DEPTH");
    knob(Page.fx, Params.chorusRate, 804, 180, "RATE");
    knob(Page.fx, Params.chorusFeedback, 862, 180, "FEEDBACK");
    knob(Page.fx, Params.chorusLevel, 775, 260, "LEVEL");
    knob(Page.fx, Params.chorusWidth, 833, 260, "WIDTH");
    addPageLabel(Page.fx, "ENSEMBLE", rectangle(746, 370, 188, 24), 14,
                 textPrimary);
  }

  void envelopeCard(Page page, box2i rect, string title, Params attack,
                    RGBA accent) {
    addCard(page, rect, accent);
    section(page, title, rect.min.x + 12, rect.min.y + 9, rect.width - 24);
    graph(page, ScopeUI.Kind.envelope,
          rectangle(rect.min.x + 12, rect.min.y + 36, rect.width - 24, 62),
          attack, cast(Params)(attack + 1), cast(Params)(attack + 2),
          cast(Params)(attack + 3), 4);
    foreach (i; 0 .. 4) {
      static immutable string[4] names = ["A", "D", "S", "R"];
      knob(page, cast(Params)(attack + i), rect.min.x + 15 + i * 56,
           rect.min.y + 104, names[i]);
    }
  }

  void lfoCard(Page page, box2i rect, string title, Params wave, Params dest,
               Params sync, Params speed, Params mul, Params amount,
               Params trigger, RGBA accent) {
    addCard(page, rect, accent);
    section(page, title, rect.min.x + 12, rect.min.y + 9, 100);
    graph(page, ScopeUI.Kind.waveform,
          rectangle(rect.min.x + 12, rect.min.y + 40, rect.width - 24, 190),
          wave, Params.oscPulseWidth, wave, wave, 1);
    selector(page, wave, rect.min.x + 12, rect.min.y + 254, 126, "WAVEFORM");
    selector(page, dest, rect.min.x + 150, rect.min.y + 254, 126, "DESTINATION");
    knob(page, speed, rect.min.x + 24, rect.min.y + 322, "SPEED");
    knob(page, amount, rect.min.x + 92, rect.min.y + 322, "AMOUNT");
    selector(page, mul, rect.min.x + 160, rect.min.y + 328, 116, "SYNC NOTE");
    toggle(page, sync, rect.min.x + 42, rect.min.y + 410, "SYNC");
    toggle(page, trigger, rect.min.x + 154, rect.min.y + 410, "TRIGGER");
  }

  void addCard(Page page, box2i rect, RGBA accent) {
    _cards ~= Card(rect, page, accent);
  }

  void section(Page page, string text, int x, int y, int width) {
    addPageLabel(page, text, rectangle(x, y, width, 19), 12, textPrimary);
  }

  UILabel addAlwaysLabel(string text, box2i rect, float size, RGBA color) {
    auto label = mallocNew!UILabel(context, _font, text);
    label.position = rect;
    label.textSize = size;
    label.textColor = color;
    addChild(label);
    _themedLabels ~= ThemedLabel(label, color);
    return label;
  }

  UILabel addPageLabel(Page page, string text, box2i rect, float size,
                       RGBA color) {
    auto label = mallocNew!UILabel(context, _font, text);
    label.position = rect;
    label.textSize = size;
    label.textColor = color;
    addPageChild(page, label);
    _themedLabels ~= ThemedLabel(label, color);
    return label;
  }

  UIElement knob(Page page, Params id, int x, int y, string caption) {
    auto flatControl = mallocNew!FlatKnobUI(context, _params[id], this);
    flatControl.position = rectangle(x, y, 46, 46);
    addPageChild(page, flatControl);
    _themeControls ~= ThemeControl(flatControl, page, false);

    auto darkControl = mallocNew!UIKnob(context, _params[id]);
    darkControl.position = rectangle(x, y, 46, 46);
    darkControl.style = KnobStyle.cylinder;
    darkControl.knobRadius = 0.62f;
    darkControl.knobDiffuse = RGBA(48, 60, 70, 0);
    darkControl.knobMaterial = RGBA(80, 60, 100, 0);
    darkControl.numLEDs = 0;
    darkControl.LEDDepth = 0;
    darkControl.litTrailDiffuse = RGBA(47, 211, 227, 100);
    darkControl.litTrailDiffuseAlt = RGBA(255, 151, 49, 100);
    darkControl.hasAlternateTrail = true;
    darkControl.unlitTrailDiffuse = RGBA(34, 47, 58, 0);
    darkControl.trailRadiusMin = 0.80f;
    darkControl.trailRadiusMax = 0.94f;
    addPageChild(page, darkControl);
    _themeControls ~= ThemeControl(darkControl, page, true);

    addPageLabel(page, caption, rectangle(x - 3, y + 45, 52, 15), 8, textMuted);
    return flatControl;
  }

  SelectorUI selector(Page page, Params id, int x, int y, int width,
                      string caption) {
    auto control = mallocNew!SelectorUI(context, _font,
                                        cast(IntegerParameter)_params[id], this);
    control.position = rectangle(x, y, width, 28);
    addPageChild(page, control);
    addPageLabel(page, caption, rectangle(x, y + 28, width, 14), 8, textMuted);
    return control;
  }

  UIOnOffSwitch toggle(Page page, Params id, int x, int y, string caption) {
    auto control = mallocNew!UIOnOffSwitch(context,
                                           cast(BoolParameter)_params[id]);
    control.position = rectangle(x, y, 28, 28);
    control.diffuseOn = cyanBright;
    control.diffuseOff = RGBA(192, 202, 208, 0);
    addPageChild(page, control);
    addPageLabel(page, caption, rectangle(x - 8, y + 29, 44, 14), 8, textMuted);
    return control;
  }

  ScopeUI graph(Page page, ScopeUI.Kind kind, box2i rect,
                Params p0, Params p1, Params p2, Params p3, int count,
                Params p4 = Params.osc1Det,
                Params p5 = Params.osc1Unison) {
    auto display = mallocNew!ScopeUI(context, kind, _params,
                                     this, p0, p1, p2, p3, p4, p5, count);
    display.position = rect;
    addPageChild(page, display);
    return display;
  }

  void addPageChild(Page page, UIElement child) {
    addChild(child);
    _pageChildren[page] ~= child;
  }

  Parameter[] _params;
  Font _font;
  UILabel _tempo;
  double _tempoValue = -1;
  char[32] _tempoText;
  Page _activePage;
  Theme _theme = Theme.light;
  PageTabUI[3] _tabs;
  Vec!UIElement[3] _pageChildren;
  Vec!Card _cards;
  Vec!ThemedLabel _themedLabels;
  Vec!ThemeControl _themeControls;
  ThemeSelectorUI _themeSelector;
  UIWindowResizer _resizer;
  Vec!box2i _defaultRects;
  Vec!float _defaultTextSize;
}
