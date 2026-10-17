module kdr.khrm.gui;

import dplug.core : mallocNew, destroyFree;
import dplug.client;
import dplug.client.params : BoolParameter, LinearFloatParameter, EnumParameter;
import dplug.math : box2i, rectangle;
import dplug.gui;
import dplug.graphics : RGBA, Font, ImageRef, L16, cropImageRef;
import dplug.pbrwidgets : UILabel, UIKnob;
import dplug.flatwidgets : UIWindowResizer;

import kdr.simplegui : PBRSimpleGUI;
import kdr.khrm.params : Params, noteNames, qualityLabels, presetNames, presets;
import kdr.khrm.client : KhrmClient;
import kdr.khrm.dsp : SpectrumAnalyzer;

import std.math : log, exp, abs, exp2;

// Purple Theme Color Tokens
enum RGBA bgDark          = RGBA(14, 10, 24, 255);
enum RGBA panelSurface    = RGBA(24, 18, 38, 255);
enum RGBA panelInset      = RGBA(10, 8, 18, 255);
enum RGBA borderPurple    = RGBA(60, 42, 90, 255);
enum RGBA neonPurple      = RGBA(175, 75, 255, 255);
enum RGBA glowPurple      = RGBA(215, 140, 255, 255);
enum RGBA dimPurple       = RGBA(45, 32, 65, 255);
enum RGBA whiteKeyOff     = RGBA(75, 68, 90, 255);
enum RGBA whiteKeyOn      = RGBA(210, 160, 255, 255);
enum RGBA blackKeyOff     = RGBA(26, 20, 36, 255);
enum RGBA blackKeyOn      = RGBA(185, 80, 255, 255);
enum RGBA textBright      = RGBA(240, 230, 255, 255);
enum RGBA textDim         = RGBA(155, 135, 185, 255);

/// Compile-time precomputed percentage strings (0% to 200%) for @nogc display.
immutable string[201] percentStrings = () {
  string[201] res;
  foreach (i; 0 .. 201) {
    import std.conv : to;
    res[i] = to!string(i) ~ "%";
  }
  return res;
}();

/// Helper to fill a subrectangle inside a dirtyRect safely.
@nogc nothrow pure
void fillRect(
    ImageRef!RGBA diff, ImageRef!L16 depth, ImageRef!RGBA mat,
    box2i target, box2i dirtyRect,
    RGBA color, L16 depVal = L16(0), RGBA matVal = RGBA(0, 0, 0, 0)) {
  box2i r = target.intersection(dirtyRect);
  if (r.max.x <= r.min.x || r.max.y <= r.min.y) return;

  ImageRef!RGBA dSub = diff.cropImageRef(box2i(r.min - dirtyRect.min, r.max - dirtyRect.min));
  ImageRef!L16 dpSub = depth.cropImageRef(box2i(r.min - dirtyRect.min, r.max - dirtyRect.min));
  ImageRef!RGBA mSub = mat.cropImageRef(box2i(r.min - dirtyRect.min, r.max - dirtyRect.min));

  foreach (y; 0 .. dSub.h) {
    dSub.scanline(y)[0 .. $] = color;
    dpSub.scanline(y)[0 .. $] = depVal;
    mSub.scanline(y)[0 .. $] = matVal;
  }
}

/// Helper to draw a bordered box.
@nogc nothrow pure
void drawBoxWithBorder(
    ImageRef!RGBA diff, ImageRef!L16 depth, ImageRef!RGBA mat,
    box2i target, box2i dirtyRect,
    RGBA fillColor, RGBA borderColor, int borderWidth = 1) {
  // Border
  fillRect(diff, depth, mat, target, dirtyRect, borderColor);
  // Interior
  box2i inner = box2i(
    target.min.x + borderWidth, target.min.y + borderWidth,
    target.max.x - borderWidth, target.max.y - borderWidth
  );
  fillRect(diff, depth, mat, inner, dirtyRect, fillColor);
}

// ----------------------------------------------------------------------------
// Custom Visualizer Widget: SPECTRO VISUALIZER
// ----------------------------------------------------------------------------
class UIKhrmSpectro : UIElement {
 public:
  @nogc nothrow:

  this(UIContext context, KhrmClient client, Parameter[] params) {
    super(context, flagPBR | flagAnimated);
    _client = client;
    _params = params;
  }

  override void onAnimate(double dt, double time) {
    setDirtyWhole();
  }

  override void onDrawPBR(
      ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap,
      ImageRef!RGBA materialMap, box2i[] dirtyRects) nothrow @nogc {

    const int W = _position.width;
    const int H = _position.height;

    foreach (dirtyRect; dirtyRects) {
      ImageRef!RGBA diff = diffuseMap.cropImageRef(dirtyRect);
      ImageRef!L16 depth = depthMap.cropImageRef(dirtyRect);
      ImageRef!RGBA mat = materialMap.cropImageRef(dirtyRect);

      // 1. Background Frame and Screen
      box2i screenBox = box2i(0, 0, W, H);
      drawBoxWithBorder(diff, depth, mat, screenBox, dirtyRect, panelInset, borderPurple, 2);

      // 2. Frequency Grid Lines (e.g. 100Hz, 250Hz, 500Hz, 1kHz, 2kHz, 4kHz)
      static immutable float[6] guideFreqs = [100.0f, 250.0f, 500.0f, 1000.0f, 2000.0f, 4000.0f];
      const float minLog = log(80.0f);
      const float maxLog = log(7200.0f);

      foreach (gf; guideFreqs) {
        float normX = (log(gf) - minLog) / (maxLog - minLog);
        int lineX = cast(int)(normX * W);
        if (lineX > 2 && lineX < W - 2) {
          // Vertical dotted grid
          for (int gy = 4; gy < H - 4; gy += 4) {
            fillRect(diff, depth, mat, box2i(lineX, gy, lineX + 1, gy + 2), dirtyRect, RGBA(35, 25, 55, 255));
          }
        }
      }

      // Horizontal dB Grid Lines
      for (int dbStep = 1; dbStep < 4; dbStep++) {
        int lineY = H * dbStep / 4;
        for (int gx = 4; gx < W - 4; gx += 6) {
          fillRect(diff, depth, mat, box2i(gx, lineY, gx + 3, lineY + 1), dirtyRect, RGBA(30, 20, 48, 255));
        }
      }

      // 3. Musical Scale Harmonic Markers (Active Notes)
      foreach (n; 0 .. 12) {
        auto noteP = cast(BoolParameter) _params[Params.noteC + n];
        if (!noteP || !noteP.value()) continue;

        // Base frequency in Octave 3 (MIDI 48 + n)
        float baseFreq = 440.0f * exp2((cast(float) n + 48.0f - 69.0f) / 12.0f);

        // Draw harmonic vertical pillars
        for (int h = 1; h <= 6; h++) {
          float harmF = baseFreq * h;
          if (harmF < 80.0f || harmF > 7200.0f) continue;
          float normX = (log(harmF) - minLog) / (maxLog - minLog);
          int markX = cast(int)(normX * W);
          if (markX > 2 && markX < W - 2) {
            // Glow pillar with alpha fading near top and bottom
            RGBA pillarColor = (h == 1) ? RGBA(90, 45, 140, 255) : RGBA(55, 30, 85, 255);
            fillRect(diff, depth, mat, box2i(markX, 4, markX + 1, H - 4), dirtyRect, pillarColor);
          }
        }
      }

      // 4. Spectrum Analyzer Bars / Curves
      const SpectrumAnalyzer* spec = _client.spectrum();
      if (spec) {
        enum NUM_BANDS = SpectrumAnalyzer.NUM_BANDS;
        const int bandW = (W - 8) / NUM_BANDS;

        foreach (b; 0 .. NUM_BANDS) {
          int bx = 4 + b * bandW;
          int bw = bandW > 2 ? bandW - 1 : 1;

          // Input level (subtle purplish background line)
          float inVal = spec.inputLevels[b];
          if (inVal > 1.0f) inVal = 1.0f;
          int inH = cast(int)(inVal * (H - 12));
          if (inH > 0) {
            int topY = (H - 6) - inH;
            fillRect(diff, depth, mat, box2i(bx, topY, bx + bw, H - 6), dirtyRect, RGBA(60, 40, 80, 255));
          }

          // Output (Harmonized / Colored) level
          float outVal = spec.outputLevels[b];
          if (outVal > 1.0f) outVal = 1.0f;
          int outH = cast(int)(outVal * (H - 12));
          if (outH > 0) {
            int topY = (H - 6) - outH;
            // Draw gradient-like purple fill
            fillRect(diff, depth, mat, box2i(bx, topY, bx + bw, H - 6), dirtyRect, neonPurple);
            // Bright cap at the peak
            int capH = outH > 3 ? 3 : outH;
            fillRect(diff, depth, mat, box2i(bx, topY, bx + bw, topY + capH), dirtyRect, glowPurple);
          }
        }
      }
    }
  }

 private:
  KhrmClient _client;
  Parameter[] _params;
}

// ----------------------------------------------------------------------------
// Custom 12-Note Keyboard Widget
// ----------------------------------------------------------------------------
class UI12KeySelector : UIElement {
 public:
  @nogc nothrow:

  this(UIContext context, Parameter[] params, Font font) {
    super(context, flagPBR);
    _params = params;
    _font = font;
  }

  override Click onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate) {
    const int W = _position.width;
    const int H = _position.height;

    int whiteW = W / 7;
    int blackH = cast(int)(H * 0.62f);
    int blackW = cast(int)(whiteW * 0.62f);

    // Map: 7 white keys => note index [0:C, 2:D, 4:E, 5:F, 7:G, 9:A, 11:B]
    static immutable int[7] whiteNotes = [0, 2, 4, 5, 7, 9, 11];

    // Black keys between white keys:
    // C#(1) between C(0) and D(1) => after white 0
    // D#(3) between D(1) and E(2) => after white 1
    // F#(6) between F(3) and G(4) => after white 3
    // G#(8) between G(4) and A(5) => after white 4
    // A#(10) between A(5) and B(6) => after white 5
    static immutable int[5] blackWhiteIdx = [0, 1, 3, 4, 5];
    static immutable int[5] blackNotes = [1, 3, 6, 8, 10];

    int targetNote = -1;

    // Check black keys first (if y is in upper portion)
    if (y < blackH) {
      foreach (bi; 0 .. 5) {
        int wIdx = blackWhiteIdx[bi];
        int bx = (wIdx + 1) * whiteW - blackW / 2;
        if (x >= bx && x < bx + blackW) {
          targetNote = blackNotes[bi];
          break;
        }
      }
    }

    // If not clicked on a black key, check white keys
    if (targetNote == -1) {
      int wIdx = x / whiteW;
      if (wIdx < 0) wIdx = 0;
      if (wIdx > 6) wIdx = 6;
      targetNote = whiteNotes[wIdx];
    }

    // Toggle note parameter
    if (targetNote >= 0 && targetNote < 12) {
      auto bp = cast(BoolParameter) _params[Params.noteC + targetNote];
      if (bp) {
        bp.beginParamEdit();
        bp.setFromGUI(!bp.value());
        bp.endParamEdit();
        setDirtyWhole();
        return Click.handled;
      }
    }

    return Click.unhandled;
  }

  override void onDrawPBR(
      ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap,
      ImageRef!RGBA materialMap, box2i[] dirtyRects) nothrow @nogc {

    const int W = _position.width;
    const int H = _position.height;

    int whiteW = W / 7;
    int blackH = cast(int)(H * 0.62f);
    int blackW = cast(int)(whiteW * 0.62f);

    static immutable int[7] whiteNotes = [0, 2, 4, 5, 7, 9, 11];
    static immutable int[5] blackWhiteIdx = [0, 1, 3, 4, 5];
    static immutable int[5] blackNotes = [1, 3, 6, 8, 10];

    foreach (dirtyRect; dirtyRects) {
      ImageRef!RGBA diff = diffuseMap.cropImageRef(dirtyRect);
      ImageRef!L16 depth = depthMap.cropImageRef(dirtyRect);
      ImageRef!RGBA mat = materialMap.cropImageRef(dirtyRect);

      // Outer bezel
      drawBoxWithBorder(diff, depth, mat, box2i(0, 0, W, H), dirtyRect, bgDark, borderPurple, 1);

      // 1. Draw 7 White Keys
      foreach (i; 0 .. 7) {
        int wx = i * whiteW;
        int nextWx = (i == 6) ? W : (i + 1) * whiteW;
        box2i keyBox = box2i(wx, 0, nextWx, H);

        int noteIdx = whiteNotes[i];
        bool isOn = false;
        if (auto bp = cast(BoolParameter) _params[Params.noteC + noteIdx]) {
          isOn = bp.value();
        }

        RGBA keyColor = isOn ? whiteKeyOn : whiteKeyOff;
        RGBA keyBorder = isOn ? neonPurple : RGBA(30, 25, 40, 255);
        drawBoxWithBorder(diff, depth, mat, keyBox, dirtyRect, keyColor, keyBorder, 1);

        // Bottom LED accent if active
        if (isOn) {
          fillRect(diff, depth, mat, box2i(wx + 2, H - 7, nextWx - 2, H - 2), dirtyRect, neonPurple);
        }
      }

      // 2. Draw 5 Black Keys
      foreach (bi; 0 .. 5) {
        int wIdx = blackWhiteIdx[bi];
        int bx = (wIdx + 1) * whiteW - blackW / 2;
        box2i keyBox = box2i(bx, 0, bx + blackW, blackH);

        int noteIdx = blackNotes[bi];
        bool isOn = false;
        if (auto bp = cast(BoolParameter) _params[Params.noteC + noteIdx]) {
          isOn = bp.value();
        }

        RGBA keyColor = isOn ? blackKeyOn : blackKeyOff;
        RGBA keyBorder = isOn ? glowPurple : RGBA(15, 10, 22, 255);
        drawBoxWithBorder(diff, depth, mat, keyBox, dirtyRect, keyColor, keyBorder, 1);

        // Center glow indicator for black key if active
        if (isOn) {
          fillRect(diff, depth, mat, box2i(bx + 2, blackH - 6, bx + blackW - 2, blackH - 2), dirtyRect, glowPurple);
        }
      }
    }
  }

 private:
  Parameter[] _params;
  Font _font;
}

// ----------------------------------------------------------------------------
// Custom Latency / Quality Bar Widget
// ----------------------------------------------------------------------------
class UIQualityBar : UIElement {
 public:
  @nogc nothrow:

  this(UIContext context, Parameter param, Font font) {
    super(context, flagPBR);
    _param = cast(EnumParameter) param;
    _font = font;
  }

  override Click onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate) {
    if (!_param) return Click.unhandled;

    int newIdx = (x < _position.width / 2) ? 0 : 1;
    _param.beginParamEdit();
    _param.setFromGUI(newIdx);
    _param.endParamEdit();
    setDirtyWhole();
    return Click.handled;
  }

  override void onDrawPBR(
      ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap,
      ImageRef!RGBA materialMap, box2i[] dirtyRects) nothrow @nogc {

    const int W = _position.width;
    const int H = _position.height;
    int halfW = W / 2;

    int curVal = _param ? _param.value() : 0;

    foreach (dirtyRect; dirtyRects) {
      ImageRef!RGBA diff = diffuseMap.cropImageRef(dirtyRect);
      ImageRef!L16 depth = depthMap.cropImageRef(dirtyRect);
      ImageRef!RGBA mat = materialMap.cropImageRef(dirtyRect);

      // Frame
      drawBoxWithBorder(diff, depth, mat, box2i(0, 0, W, H), dirtyRect, panelSurface, borderPurple, 1);

      // Left Segment: LOW LATENCY
      box2i leftBox = box2i(1, 1, halfW, H - 1);
      RGBA leftColor = (curVal == 0) ? neonPurple : panelSurface;
      fillRect(diff, depth, mat, leftBox, dirtyRect, leftColor);

      // Right Segment: HIGH QUALITY
      box2i rightBox = box2i(halfW, 1, W - 1, H - 1);
      RGBA rightColor = (curVal == 1) ? neonPurple : panelSurface;
      fillRect(diff, depth, mat, rightBox, dirtyRect, rightColor);

      // Divider line
      fillRect(diff, depth, mat, box2i(halfW - 1, 1, halfW + 1, H - 1), dirtyRect, borderPurple);
    }
  }

 private:
  EnumParameter _param;
  Font _font;
}

// ----------------------------------------------------------------------------
// Custom Toggle Button Widget
// ----------------------------------------------------------------------------
class UIToggleButton : UIElement {
 public:
  @nogc nothrow:

  this(UIContext context, Parameter param, string labelText) {
    super(context, flagPBR);
    _param = cast(BoolParameter) param;
    _labelText = labelText;
  }

  override Click onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate) {
    if (!_param) return Click.unhandled;

    _param.beginParamEdit();
    _param.setFromGUI(!_param.value());
    _param.endParamEdit();
    setDirtyWhole();
    return Click.handled;
  }

  override void onDrawPBR(
      ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap,
      ImageRef!RGBA materialMap, box2i[] dirtyRects) nothrow @nogc {

    const int W = _position.width;
    const int H = _position.height;
    bool isOn = _param ? _param.value() : false;

    foreach (dirtyRect; dirtyRects) {
      ImageRef!RGBA diff = diffuseMap.cropImageRef(dirtyRect);
      ImageRef!L16 depth = depthMap.cropImageRef(dirtyRect);
      ImageRef!RGBA mat = materialMap.cropImageRef(dirtyRect);

      RGBA bg = isOn ? neonPurple : panelSurface;
      RGBA border = isOn ? glowPurple : borderPurple;
      drawBoxWithBorder(diff, depth, mat, box2i(0, 0, W, H), dirtyRect, bg, border, 1);

      // Light bar indicator inside button
      if (isOn) {
        fillRect(diff, depth, mat, box2i(3, H - 4, W - 3, H - 2), dirtyRect, glowPurple);
      }
    }
  }

 private:
  BoolParameter _param;
  string _labelText;
}

// ----------------------------------------------------------------------------
// Main Khrm GUI
// ----------------------------------------------------------------------------
class KhrmGUI : PBRSimpleGUI, IParameterListener {
 public:
  @nogc nothrow:

  this(KhrmClient client, Parameter[] params) {
    static immutable float[] ratios = [1.0f, 1.25f, 1.5f, 1.75f, 2.0f];
    super(makeSizeConstraintsDiscrete(880, 560, ratios), bgDark);

    _client = client;
    _params = params;
    _font = mallocNew!Font(cast(ubyte[]) import("FORCED SQUARE.ttf"));

    // 1. Header Elements
    _title = buildLabel("khrm");
    _subTitle = buildLabel("COLOUR BASS HARMONIZER");

    // Master Power Toggle
    addChild(_powerBtn = mallocNew!UIToggleButton(context(), _params[Params.power], "POWER"));
    _powerLabel = buildLabel("POWER");

    // Preset Selector
    _presetLabel = buildLabel(presetNames[0]);
    _presetTitle = buildLabel("PRESET");
    _params[Params.preset].addListener(this);

    // 2. Central Spectro Visualizer
    addChild(_spectro = mallocNew!UIKhrmSpectro(context(), _client, _params));

    // 3. Main Color Knob
    addChild(_colorKnob = mallocNew!UIKnob(context(), _params[Params.color]));
    _colorKnob.knobRadius = 0.68f;
    _colorKnob.knobDiffuse = RGBA(32, 22, 48, 255);
    _colorKnob.knobMaterial = RGBA(255, 0, 0, 0);
    _colorKnob.numLEDs = 0;
    _colorKnob.litTrailDiffuse = neonPurple;
    _colorKnob.unlitTrailDiffuse = dimPurple;
    _colorKnob.trailRadiusMin = 0.12f;
    _colorKnob.trailRadiusMax = 0.85f;

    _colorLabel = buildLabel("COLOR");
    _colorValueLabel = buildLabel("85%");
    _params[Params.color].addListener(this);

    // 4. 12-Note Keyboard / Scale Selector
    addChild(_keySelector = mallocNew!UI12KeySelector(context(), _params, _font));
    _keyboardLabel = buildLabel("SCALE NOTES (12-TONE SELECTOR)");

    // 5. Latency / Quality Bar
    addChild(_qualityBar = mallocNew!UIQualityBar(context(), _params[Params.quality], _font));
    _qualityLeftLabel = buildLabel("LOW LATENCY");
    _qualityRightLabel = buildLabel("HIGH QUALITY");
    _qualityHeaderLabel = buildLabel("PROCESSING MODE");

    // 6. Action Buttons: MIDI & SPECTRAL
    addChild(_midiBtn = mallocNew!UIToggleButton(context(), _params[Params.midiMode], "MIDI"));
    _midiLabel = buildLabel("MIDI TRACK");

    addChild(_spectralBtn = mallocNew!UIToggleButton(context(), _params[Params.spectral], "SPECTRAL"));
    _spectralLabel = buildLabel("SPECTRAL");

    // Window Resizer
    addChild(_resizer = mallocNew!UIWindowResizer(context()));
  }

  ~this() {
    _params[Params.preset].removeListener(this);
    _params[Params.color].removeListener(this);
    destroyFree(_font);
  }

  override void onParameterChanged(Parameter sender) {
    if (sender.index == Params.preset) {
      if (auto ep = cast(EnumParameter) sender) {
        _presetLabel.text(presetNames[ep.value()]);
        _client.applyPreset(ep.value());
      }
    } else if (sender.index == Params.color) {
      if (auto cp = cast(LinearFloatParameter) sender) {
        int pct = cast(int)(cp.value() * 100.0f + 0.5f);
        if (pct < 0) pct = 0;
        if (pct > 200) pct = 200;
        _colorValueLabel.text(percentStrings[pct]);
      }
    }
  }

  override void onBeginParameterEdit(Parameter sender) {}
  override void onEndParameterEdit(Parameter sender) {}
  override void onBeginParameterHover(Parameter sender) {}
  override void onEndParameterHover(Parameter sender) {}

  override void reflow() {
    super.reflow();
    const int W = position.width;
    const int H = position.height;

    // Fonts sizing
    int titleSize = H / 14;
    int subTitleSize = H / 44;
    int headerSize = H / 36;
    int labelSize = H / 42;

    // Header Layout
    _title.textSize = titleSize;
    _title.position = rectangle(30, 16, 140, H / 12);

    _subTitle.textSize = subTitleSize;
    _subTitle.textColor = textDim;
    _subTitle.position = rectangle(175, 26, 260, 20);

    // Power Toggle (Header Right)
    int pBtnW = 75;
    int pBtnH = 26;
    _powerBtn.position = rectangle(W - 110, 20, pBtnW, pBtnH);
    _powerLabel.textSize = labelSize;
    _powerLabel.position = rectangle(W - 110, 24, pBtnW, 18);

    // Preset Selector (Header Center-Right)
    int presetX = W - 370;
    _presetTitle.textSize = subTitleSize;
    _presetTitle.textColor = textDim;
    _presetTitle.position = rectangle(presetX, 14, 220, 14);

    _presetLabel.textSize = headerSize;
    _presetLabel.position = rectangle(presetX, 28, 240, 22);

    // 2. Central Spectro Visualizer
    int spectroX = 30;
    int spectroY = 70;
    int spectroW = W - 60;
    int spectroH = cast(int)(H * 0.40f);
    _spectro.position = rectangle(spectroX, spectroY, spectroW, spectroH);

    // 3. Bottom Controls Panel
    int botY = spectroY + spectroH + 20;

    // Left: Big COLOR Knob
    int knobBoxSize = cast(int)(H * 0.24f);
    int knobX = 35;
    _colorKnob.position = rectangle(knobX, botY + 10, knobBoxSize, knobBoxSize);

    _colorLabel.textSize = headerSize;
    _colorLabel.position = rectangle(knobX, botY + knobBoxSize + 14, knobBoxSize, 20);

    _colorValueLabel.textSize = labelSize;
    _colorValueLabel.textColor = glowPurple;
    _colorValueLabel.position = rectangle(knobX, botY + knobBoxSize + 34, knobBoxSize, 18);

    // Center: 12-Note Keyboard
    int keyX = knobX + knobBoxSize + 30;
    int keyW = cast(int)(W * 0.40f);
    int keyH = cast(int)(H * 0.20f);

    _keyboardLabel.textSize = headerSize;
    _keyboardLabel.position = rectangle(keyX, botY - 2, keyW, 20);

    _keySelector.position = rectangle(keyX, botY + 22, keyW, keyH);

    // Right: Quality Bar & Buttons
    int rightX = keyX + keyW + 30;
    int rightW = W - rightX - 30;

    // Quality Bar
    _qualityHeaderLabel.textSize = headerSize;
    _qualityHeaderLabel.position = rectangle(rightX, botY - 2, rightW, 20);

    int qBarH = 34;
    _qualityBar.position = rectangle(rightX, botY + 22, rightW, qBarH);

    _qualityLeftLabel.textSize = labelSize;
    _qualityLeftLabel.position = rectangle(rightX + 6, botY + 28, rightW / 2 - 10, 20);

    _qualityRightLabel.textSize = labelSize;
    _qualityRightLabel.position = rectangle(rightX + rightW / 2 + 6, botY + 28, rightW / 2 - 10, 20);

    // MIDI & SPECTRAL Buttons
    int btnY = botY + 22 + qBarH + 18;
    int btnW = (rightW - 12) / 2;
    int btnH = 38;

    _midiBtn.position = rectangle(rightX, btnY, btnW, btnH);
    _midiLabel.textSize = labelSize;
    _midiLabel.position = rectangle(rightX, btnY + 10, btnW, 18);

    _spectralBtn.position = rectangle(rightX + btnW + 12, btnY, btnW, btnH);
    _spectralLabel.textSize = labelSize;
    _spectralLabel.position = rectangle(rightX + btnW + 12, btnY + 10, btnW, 18);

    // Resizer Hint
    int hintSize = H / 20;
    _resizer.position = rectangle(W - hintSize, H - hintSize, hintSize, hintSize);
  }

 private:
  UILabel buildLabel(string text) {
    UILabel label;
    addChild(label = mallocNew!UILabel(context(), _font, text));
    label.textColor = textBright;
    return label;
  }

  Font _font;
  Parameter[] _params;
  KhrmClient _client;
  UIWindowResizer _resizer;

  // Header
  UILabel _title;
  UILabel _subTitle;
  UIToggleButton _powerBtn;
  UILabel _powerLabel;
  UILabel _presetTitle;
  UILabel _presetLabel;

  // Center Spectro
  UIKhrmSpectro _spectro;

  // Left Controls
  UIKnob _colorKnob;
  UILabel _colorLabel;
  UILabel _colorValueLabel;

  // Center Keyboard
  UI12KeySelector _keySelector;
  UILabel _keyboardLabel;

  // Right Controls
  UIQualityBar _qualityBar;
  UILabel _qualityHeaderLabel;
  UILabel _qualityLeftLabel;
  UILabel _qualityRightLabel;

  UIToggleButton _midiBtn;
  UILabel _midiLabel;

  UIToggleButton _spectralBtn;
  UILabel _spectralLabel;
}
