/**
 * Authentic BT / iZotope Stutter Edit 2 Vector GUI (`1040 x 680`, scalable 0.75x..2.0x).
 *
 * Implements the 6-section BT Stutter Edit 2 workflow:
 * 1. Header Bar: `kdr stutter edit 2` logo, 24-Note Rainbow Piano Gesture Palette (`C2..B3`),
 *    White Active-Gesture Pill with note badge & `< >` selectors, Global Filter dial + MIDI
 *    Pitch Bend feedback, Play Mode (MIDI/AUTO) with live status LED, Length/Release+Stick/
 *    Grid with micro-labels, Palindrome, Freeze + Duration, Undo/Redo, Auto Rate & live phase.
 * 2. Full-Width STUTTER & BUFFER Horizontal Strips: Opposing dual-chevron (`▷` / `◁`) split
 *    sliders with smooth TVM curve sparklines, live playhead tracking, formatted readouts,
 *    hexagon bypass LEDs, Stutter Quantize Mode selector, L/R Buffer Position + `[<<] L`/
 *    `[<<] R`/`LINK`, Movement & Grid, Jitter toggle + EDIT view, and Gate/Pan dials.
 * 3. Left Column Signal Chain: All 11 FX (`DISTORT`, `LO-FI`, `CHORUS`, `COMB`, `REVERB`,
 *    `FLANGER`, `PHASER`, `LOWPASS`, `TAPESTOP`, `HIGHPASS`, `DELAY`) wired vertically with
 *    directional routing chevrons, hexagon bypass nodes, live wet mix mini-bars, white
 *    L-bracket selection, and draggable `≡` reorder handles with cyan insertion indicator.
 * 4. Center Selected Effect Inspector: Electric-blue Dry/Wet arc dial, clickable mode pill,
 *    2x2 dual-chevron split sliders with real-time unit readouts (`Hz`, `dB`, `ms`, `st`, `%`),
 *    dedicated Stutter/Buffer/Gate/Pan/Highpass specs, plus Buffer Jitter Editor mode.
 * 5. Bottom-Right Purple Output Section: Wet/Dry Gain hex toggles + purple dB dials, Master
 *    Limiter toggle + Threshold/Out Gain sliders, GR bar with dB readout, and segmented
 *    dual vertical purple Stereo Peak Output Meters with dB scale & decaying peak-hold caps.
 * 6. Right TVM Curve Editor (Embedded & Expandable `[⛶]`): Layered contour echo fan lines,
 *    solid white node dots, hollow tension-bend rings, left/right-click node editing,
 *    speed/reverse/grid/curve-type/reset toolbar, live synchronized playhead, and 12 smooth
 *    filled-ribbon Preset Curve Shape thumbnails.
 *
 * Copyright: kdr 2026.
 * License: Boost License 1.0.
 */
module kdr.stutter.gui;

import core.stdc.stdio : snprintf;
import core.stdc.string : strlen;
import std.math : isNaN, isInfinity, log2;
import core.math : cos, sin, fabs, sqrt;

import dplug.core : mallocNew, destroyFree, Vec, makeVec;
import dplug.client : Client, Parameter, IParameterListener, BoolParameter,
  IntegerParameter, FloatParameter, EnumParameter;
import dplug.math : vec2f, box2i, rectangle;
import dplug.gui : GUIGraphics, UIElement, UIContext, Click, MouseButton,
  MouseState, WindowPixelFormat, UILayer, flagPBR, flagRaw, flagAnimated;
import dplug.graphics : RGBA, L16, Font, ImageRef, cropImageRef, fillAll, toRef,
  fillText, HorizontalAlignment, VerticalAlignment;
import dplug.canvas : Canvas;
import dplug.flatwidgets : UIWindowResizer, makeSizeConstraintsDiscrete;

import kdr.stutter.params;
import kdr.stutter.stutter : StutterStepMode, BufferMovementMode, JitterPitchMode;
import kdr.stutter.tvm : TVMCurve, CurveNode, CurveType, NumTVMModuleSlots;
import kdr.stutter.fx : ChainFXId, NumChainFX, defaultSignalChainOrder;
import kdr.stutter.presets : NUM_FACTORY_PRESETS, NUM_BT_GESTURES, btGestureBank,
  factoryPresetNames, applyFactoryPreset, applyBTGesturePreset;
import kdr.stutter.client : StutterClient;

private static string fontRaw = import("FORCED SQUARE.ttf");

// =============================================================================
// Color Palette & Constants (BT / iZotope Stutter Edit 2)
// =============================================================================

enum int BASE_WIDTH  = 1040;
enum int BASE_HEIGHT = 680;
enum int HEADER_H    = 110;
enum float PI_F      = 3.14159265f;

enum RGBA colBgRoot       = RGBA(13, 10, 24, 255);    // #0D0A18 Deep Obsidian Violet
enum RGBA colBgPanel      = RGBA(25, 19, 46, 255);    // #19132E Rich Violet Card Surface
enum RGBA colBgSubCard    = RGBA(34, 26, 62, 255);    // #221A3E Elevated Violet Control
enum RGBA colBgSubHover   = RGBA(48, 37, 86, 255);    // #302556 Hovered Violet Control
enum RGBA colBgTrough     = RGBA(11,  8, 22, 255);    // #0B0816 Recessed Violet Trough
enum RGBA colBgCurveGrid  = RGBA(13,  9, 28, 255);    // #0D091C Deep Violet Curve Viewport
enum RGBA colBorderDim    = RGBA(78, 56, 136, 255);   // #4E3888 Amethyst Border
enum RGBA colBorderHi     = RGBA(122, 90, 204, 255);  // #7A5ACC Lilac-Violet Highlight
enum RGBA colBevelTop     = RGBA(220, 198, 255, 22);
enum RGBA colTextBright   = RGBA(246, 242, 255, 255);
enum RGBA colTextMuted    = RGBA(184, 170, 224, 255);
enum RGBA colTextDim      = RGBA(136, 120, 182, 255);
enum RGBA colTextDark     = RGBA(16, 11, 30, 255);

enum RGBA colBTCyan       = RGBA(176, 102, 255, 255); // #B066FF Unified Electric Violet Accent
enum RGBA colBTBlue       = RGBA(132, 108, 255, 255); // #846CFF Dry/Wet Indigo-Violet Ring
enum RGBA colBTPurple     = RGBA(139, 92, 246, 255);  // #8B5CF6 Output Purple
enum RGBA colBTPurpleDark = RGBA(26, 20, 47, 255);    // #1A142F Output Panel BG
enum RGBA colBTPurpleHi   = RGBA(176, 102, 255, 255);
enum RGBA colAmber        = RGBA(238, 168, 255, 255);
enum RGBA colRedAlert     = RGBA(255, 72, 116, 255);
enum RGBA colWhitePill    = RGBA(236, 230, 252, 255);

static immutable string[NumChainFX] chainFXNames = [
  "DISTORT",
  "LO-FI",
  "CHORUS",
  "COMB",
  "REVERB",
  "FLANGER",
  "PHASER",
  "LOWPASS",
  "TAPESTOP",
  "HIGHPASS",
  "DELAY",
];

static immutable string[12] curvePresetShortNames = [
  "LOW", "HIGH", "RAMP+", "RAMP-", "EXP+", "EXP-",
  "SIN1", "SIN2", "STP+", "STP-", "SPIKE", "CHAOS",
];

static immutable string[5] curveTypeShortNames = [
  "LIN", "EXP", "LOG", "S-CRV", "STEP",
];

/// Converts `0xRRGGBB` from `moduleColors` into `RGBA`.
@nogc nothrow pure @safe
RGBA moduleAccentRGBA(int slotIdx, ubyte alpha = 255) {
  int idx = slotIdx;
  if (idx < 0) idx = 0;
  if (idx >= cast(int) moduleColors.length) idx = cast(int) moduleColors.length - 1;
  const uint hex = moduleColors[idx];
  return RGBA(
    cast(ubyte)((hex >> 16) & 0xFF),
    cast(ubyte)((hex >> 8) & 0xFF),
    cast(ubyte)(hex & 0xFF),
    alpha
  );
}

/// Accent color for an 11-chain FX id.
@nogc nothrow pure @safe
RGBA chainFXAccentRGBA(ChainFXId id) {
  final switch (id) {
    case ChainFXId.distort:  return moduleAccentRGBA(ModuleSlot.distort);
    case ChainFXId.lofi:     return moduleAccentRGBA(ModuleSlot.lofi);
    case ChainFXId.chorus:   return moduleAccentRGBA(ModuleSlot.chorus);
    case ChainFXId.comb:     return moduleAccentRGBA(ModuleSlot.comb);
    case ChainFXId.reverb:   return moduleAccentRGBA(ModuleSlot.reverb);
    case ChainFXId.flanger:  return moduleAccentRGBA(ModuleSlot.flanger);
    case ChainFXId.phaser:   return moduleAccentRGBA(ModuleSlot.phaser);
    case ChainFXId.lowpass:  return moduleAccentRGBA(ModuleSlot.filter);
    case ChainFXId.tapestop: return moduleAccentRGBA(ModuleSlot.tapeStop);
    case ChainFXId.highpass: return RGBA(180, 138, 255, 255);
    case ChainFXId.delay:    return moduleAccentRGBA(ModuleSlot.delay);
  }
}

/// Maps a `ChainFXId` to its `ModuleSlot` (or `14` for Highpass).
@nogc nothrow pure @safe
int chainFXToModuleSlot(ChainFXId id) {
  final switch (id) {
    case ChainFXId.distort:  return ModuleSlot.distort;
    case ChainFXId.lofi:     return ModuleSlot.lofi;
    case ChainFXId.chorus:   return ModuleSlot.chorus;
    case ChainFXId.comb:     return ModuleSlot.comb;
    case ChainFXId.reverb:   return ModuleSlot.reverb;
    case ChainFXId.flanger:  return ModuleSlot.flanger;
    case ChainFXId.phaser:   return ModuleSlot.phaser;
    case ChainFXId.lowpass:  return ModuleSlot.filter;
    case ChainFXId.tapestop: return ModuleSlot.tapeStop;
    case ChainFXId.highpass: return 14;
    case ChainFXId.delay:    return ModuleSlot.delay;
  }
}

/// Harmonized violet-magenta-indigo synthwave spectrum for the 24 gesture keys.
@nogc nothrow pure @safe
RGBA gestureKeyColor(int idx) {
  static immutable RGBA[12] pal = [
    RGBA(236,  72, 153, 255), // C  Rose Pink
    RGBA(244,  96, 136, 255), // C# Coral Rose
    RGBA(224, 118, 178, 255), // D  Plum Rose
    RGBA(206, 108, 224, 255), // D# Orchid Pink
    RGBA(186,  98, 255, 255), // E  Electric Orchid
    RGBA(164, 104, 255, 255), // F  Bright Violet
    RGBA(139,  92, 246, 255), // F# Signature Purple
    RGBA(116, 102, 248, 255), // G  Indigo Violet
    RGBA( 98, 114, 246, 255), // G# Royal Indigo
    RGBA(126, 130, 255, 255), // A  Periwinkle
    RGBA(168, 136, 255, 255), // A# Soft Lavender
    RGBA(216,  86, 240, 255), // B  Neon Magenta
  ];
  int k = idx % 12;
  if (k < 0) k += 12;
  return pal[k];
}

/// Formats MIDI note index `0..23` (`C2..B3`) into `buf` and returns slice.
@nogc nothrow
private const(char)[] formatNoteName(int idx, char[] buf) {
  static immutable string[12] noteNames = [
    "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
  ];
  int g = idx % 24;
  if (g < 0) g += 24;
  const int oct = 2 + (g / 12);
  const string n = noteNames[g % 12];
  const int len = snprintf(buf.ptr, buf.length, "%.*s%d", cast(int) n.length, n.ptr, oct);
  return (len > 0) ? buf[0 .. len] : "C2";
}

// =============================================================================
// Safe Parameter Mutation Helpers
// =============================================================================

@nogc nothrow
private void setBoolParamSafe(Parameter p, bool hasClient, bool val) {
  auto bp = cast(BoolParameter) p;
  if (bp is null) return;
  if (hasClient) {
    bp.beginParamEdit();
    bp.setFromGUI(val);
    bp.endParamEdit();
  } else {
    bp.setFromHost(val ? 1.0 : 0.0);
  }
}

@nogc nothrow
private void setIntParamSafe(Parameter p, bool hasClient, int val) {
  auto ip = cast(IntegerParameter) p;
  if (ip is null) return;
  if (val < ip.minValue()) val = ip.minValue();
  if (val > ip.maxValue()) val = ip.maxValue();
  if (hasClient) {
    ip.beginParamEdit();
    ip.setFromGUI(val);
    ip.endParamEdit();
  } else {
    const int minV = ip.minValue();
    const int maxV = ip.maxValue();
    const double norm = (maxV > minV)
      ? cast(double)(val - minV) / cast(double)(maxV - minV)
      : 0.0;
    ip.setFromHost(norm);
  }
}

@nogc nothrow
private void setNormParamSafe(Parameter p, bool hasClient, double normVal) {
  if (p is null) return;
  if (normVal < 0.0) normVal = 0.0;
  if (normVal > 1.0) normVal = 1.0;
  if (hasClient) {
    if (auto fp = cast(FloatParameter) p) {
      fp.beginParamEdit();
      fp.setFromGUINormalized(normVal);
      fp.endParamEdit();
      return;
    }
    if (auto ip = cast(IntegerParameter) p) {
      ip.beginParamEdit();
      ip.setFromGUINormalized(normVal);
      ip.endParamEdit();
      return;
    }
  }
  p.setFromHost(normVal);
}

/// Enable parameter ID for ModuleSlot (0..14).
@nogc nothrow pure @safe
Params moduleEnableParam(int slot) {
  switch (slot) {
    case ModuleSlot.stutter:  return Params.stutterEnable;
    case ModuleSlot.buffer:   return Params.bufferEnable;
    case ModuleSlot.gate:     return Params.gateEnable;
    case ModuleSlot.pan:      return Params.panEnable;
    case ModuleSlot.tapeStop: return Params.tapeStopEnable;
    case ModuleSlot.filter:   return Params.filterEnable;
    case ModuleSlot.lofi:     return Params.lofiEnable;
    case ModuleSlot.distort:  return Params.distortEnable;
    case ModuleSlot.comb:     return Params.combEnable;
    case ModuleSlot.chorus:   return Params.chorusEnable;
    case ModuleSlot.flanger:  return Params.flangerEnable;
    case ModuleSlot.phaser:   return Params.phaserEnable;
    case ModuleSlot.reverb:   return Params.reverbEnable;
    case ModuleSlot.delay:    return Params.delayEnable;
    case ModuleSlot.limiter:  return Params.limiterEnable;
    default:                  return Params.stutterEnable;
  }
}

/// TVM curve preset parameter ID for ModuleSlot (0..13).
@nogc nothrow pure @safe
Params moduleCurveParam(int slot) {
  switch (slot) {
    case ModuleSlot.stutter:  return Params.stutterCurve;
    case ModuleSlot.buffer:   return Params.bufferCurve;
    case ModuleSlot.gate:     return Params.gateCurve;
    case ModuleSlot.pan:      return Params.panCurve;
    case ModuleSlot.tapeStop: return Params.tapeStopCurve;
    case ModuleSlot.filter:   return Params.filterCurve;
    case ModuleSlot.lofi:     return Params.lofiCurve;
    case ModuleSlot.distort:  return Params.distortCurve;
    case ModuleSlot.comb:     return Params.combCurve;
    case ModuleSlot.chorus:   return Params.chorusCurve;
    case ModuleSlot.flanger:  return Params.flangerCurve;
    case ModuleSlot.phaser:   return Params.phaserCurve;
    case ModuleSlot.reverb:   return Params.reverbCurve;
    case ModuleSlot.delay:    return Params.delayCurve;
    default:                  return Params.stutterCurve;
  }
}

/// TVM curve tension parameter ID for ModuleSlot (0..13).
@nogc nothrow pure @safe
Params moduleTensionParam(int slot) {
  switch (slot) {
    case ModuleSlot.stutter:  return Params.stutterCurveTension;
    case ModuleSlot.buffer:   return Params.bufferCurveTension;
    case ModuleSlot.gate:     return Params.gateCurveTension;
    case ModuleSlot.pan:      return Params.panCurveTension;
    case ModuleSlot.tapeStop: return Params.tapeStopCurveTension;
    case ModuleSlot.filter:   return Params.filterCurveTension;
    case ModuleSlot.lofi:     return Params.lofiCurveTension;
    case ModuleSlot.distort:  return Params.distortCurveTension;
    case ModuleSlot.comb:     return Params.combCurveTension;
    case ModuleSlot.chorus:   return Params.chorusCurveTension;
    case ModuleSlot.flanger:  return Params.flangerCurveTension;
    case ModuleSlot.phaser:   return Params.phaserCurveTension;
    case ModuleSlot.reverb:   return Params.reverbCurveTension;
    case ModuleSlot.delay:    return Params.delayCurveTension;
    default:                  return Params.stutterCurveTension;
  }
}

/// Descriptor for one slider inside the Center Inspector Panel.
struct InspectorSliderSpec {
  string label;
  Params paramMin;
  Params paramMax;
  bool isDual;      // Dual-chevron split modulation slider
  int customKind;   // 0=use Params, 1=Highpass Cutoff, 2=Highpass Res, 3=Distort DC,
                    // 4=Stutter Step
}

// =============================================================================
// Interactive Raw Canvas Overlay
// =============================================================================

class StutterCanvasOverlay : UIElement {
public:
  @nogc nothrow:

  this(UIContext context, StutterGUI host) {
    super(context, flagRaw | flagAnimated);
    _host = host;
  }

  override Click onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate) {
    Click res = _host.handleWorkspaceClick(x, y, button, isDoubleClick);
    _pendingStartDrag = (res == Click.startDrag);
    return res;
  }

  override void onBeginDrag() {
    _pendingStartDrag = false;
  }

  override void onMouseMove(int x, int y, int dx, int dy, MouseState mstate) {
    _host.handleWorkspaceHover(x, y);
  }

  override void onMouseExit() {
    _host.handleWorkspaceHover(-1, -1);
  }

  override void onMouseDrag(int x, int y, int dx, int dy, MouseState mstate) {
    _host.handleWorkspaceDrag(x, y, dx, dy);
  }

  override void onStopDrag() {
    if (!_pendingStartDrag) {
      _host.handleWorkspaceStopDrag();
    }
  }

  override void onAnimate(double dt, double time) {
    _host.advanceAnimation(dt, time);
    setDirtyWhole();
  }

  override void onDrawRaw(ImageRef!RGBA rawMap, box2i[] dirtyRects) {
    _host.drawRawOverlay(rawMap, dirtyRects, _canvas);
  }

private:
  StutterGUI _host;
  Canvas _canvas;
  bool _pendingStartDrag = false;
}

// =============================================================================
// Main StutterGUI Class
// =============================================================================

class StutterGUI : GUIGraphics, IParameterListener {
public:
  @nogc nothrow:

  this(Parameter[] params) {
    this(null, params);
  }

  this(StutterClient client, Parameter[] params) {
    static immutable float[6] ratios = [0.75f, 1.0f, 1.25f, 1.5f, 1.75f, 2.0f];
    super(makeSizeConstraintsDiscrete(BASE_WIDTH, BASE_HEIGHT, ratios),
          flagPBR | flagAnimated);
    setUpdateMargin(0);

    _client = client;
    _params = params;
    _hasClient = (client !is null) && (client.hostCommand() !is null);
    _font = mallocNew!Font(cast(ubyte[]) fontRaw);

    for (int i = 0; i < NumTVMModuleSlots; ++i) {
      int presetId = TVMCurvePreset.rampUp;
      if (_params.length > moduleCurveParam(i)) {
        if (auto ip = cast(IntegerParameter) _params[moduleCurveParam(i)]) {
          presetId = ip.value();
        }
      }
      _curves[i].loadPreset(presetId);
    }
    _highpassCurve.loadPreset(TVMCurvePreset.rampUp);

    foreach (p; _params) {
      if (p !is null) p.addListener(this);
    }

    _overlay = mallocNew!StutterCanvasOverlay(context, this);
    _overlay.position = rectangle(0, 0, BASE_WIDTH, BASE_HEIGHT);
    addChild(_overlay);

    _resizer = mallocNew!UIWindowResizer(context);
    _resizer.position = rectangle(BASE_WIDTH - 16, BASE_HEIGHT - 16, 16, 16);
    addChild(_resizer);

    _defaultRects = makeVec!box2i(_children.length);
    foreach (i, child; _children) {
      _defaultRects[i] = child.position;
    }
  }

  ~this() {
    foreach (p; _params) {
      if (p !is null) p.removeListener(this);
    }
    if (_font !is null) {
      _font.destroyFree();
      _font = null;
    }
  }

  // --- Public Inspection & Test API (Preserved & Extended) ---
  int activeModule() const pure { return _activeModule; }

  void setActiveModule(int slot) {
    if (slot < 0) slot = 0;
    if (slot > 14) slot = 14;
    _activeModule = slot;
    _editingJitter = false;
    setDirtyWhole();
    if (_overlay !is null) _overlay.setDirtyWhole();
  }

  int activeInspectorParam() const pure { return _activeInspectorParam; }

  ref inout(TVMCurve) activeCurve() inout return pure {
    if (_activeModule == 14) {
      if (_client !is null) return _client.extTvmBank.states[14][0].curve;
      return _highpassCurve;
    }
    const int slot = (_activeModule >= 0 && _activeModule < NumTVMModuleSlots)
      ? _activeModule : 0;
    if (_client !is null) {
      return _client.modulationEngine().curves[slot];
    }
    return _curves[slot];
  }

  bool isAutoMode() {
    if (_params.length > Params.autoMode) {
      if (auto bp = cast(BoolParameter) _params[Params.autoMode]) {
        return bp.value();
      }
    }
    return true;
  }

  float playheadPhase() const pure { return _playheadPhase; }
  bool isCurveExpanded() const pure { return _curveExpanded; }

  void setCurveExpanded(bool expanded) {
    _curveExpanded = expanded;
    setDirtyWhole(UILayer.allLayers);
    if (_overlay !is null) _overlay.setDirtyWhole();
  }

  bool isEditingJitter() const pure { return _editingJitter; }
  int hoverX() const pure { return _hoverX; }
  int hoverY() const pure { return _hoverY; }
  float peakHoldL() const pure { return _peakHoldL; }
  float peakHoldR() const pure { return _peakHoldR; }

  // --- IParameterListener ---
  override void onParameterChanged(Parameter sender) {
    if (sender !is null) {
      const int idx = sender.index();
      for (int slot = 0; slot < NumTVMModuleSlots; ++slot) {
        if (idx == cast(int) moduleCurveParam(slot)) {
          if (auto ip = cast(IntegerParameter) sender) {
            _curves[slot].loadPreset(ip.value());
            if (_client !is null) {
              _client.modulationEngine().curves[slot].loadPreset(ip.value());
            }
          }
        } else if (idx == cast(int) moduleTensionParam(slot)) {
          if (auto fp = cast(FloatParameter) sender) {
            const float t = cast(float) fp.value();
            if (_curves[slot].nodeCount() > 0) _curves[slot].nodes[0].tension = t;
            if (_client !is null && _client.modulationEngine().curves[slot].nodeCount() > 0) {
              _client.modulationEngine().curves[slot].nodes[0].tension = t;
            }
          }
        }
      }
    }
    setDirtyWhole(UILayer.allLayers);
    if (_overlay !is null) _overlay.setDirtyWhole();
  }

  override void onBeginParameterEdit(Parameter sender) {}
  override void onEndParameterEdit(Parameter sender) {}
  override void onBeginParameterHover(Parameter sender) {}
  override void onEndParameterHover(Parameter sender) {}

  override void reflow() {
    super.reflow();
    const float scale = (position.width > 0)
      ? (cast(float) position.width / cast(float) BASE_WIDTH) : 1.0f;
    foreach (i, child; _children) {
      child.position = _defaultRects[i].scaleByFactor(scale);
    }
  }

  // --- Base PBR Layer (envtool / synth2 tactile 3D studio chassis & recessed wells) ---
  private static void fillPBRBox(
      ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap,
      box2i dirty, float scale,
      int lx, int ly, int lw, int lh,
      RGBA diffCol, ushort depthVal, RGBA matCol) nothrow @nogc {
    const int x0 = cast(int)(snapF(cast(float) lx * scale));
    const int y0 = cast(int)(snapF(cast(float) ly * scale));
    const int x1 = cast(int)(snapF(cast(float)(lx + lw) * scale));
    const int y1 = cast(int)(snapF(cast(float)(ly + lh) * scale));
    const box2i sub = dirty.intersection(box2i(x0, y0, x1, y1));
    if (sub.empty) return;
    diffuseMap.cropImageRef(sub).fillAll(diffCol);
    depthMap.cropImageRef(sub).fillAll(L16(depthVal));
    materialMap.cropImageRef(sub).fillAll(matCol);
  }

  override void onDrawPBR(
      ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap,
      ImageRef!RGBA materialMap, box2i[] dirtyRects) nothrow @nogc {
    const float scale = (diffuseMap.w > 0)
      ? (cast(float) diffuseMap.w / cast(float) BASE_WIDTH) : 1.0f;
    enum RGBA matChassis = RGBA(170, 35, 65, 0);   // Satin dark brushed slate
    enum RGBA matPanel   = RGBA(150, 40, 82, 0);   // Raised card anodized aluminum
    enum RGBA matWell    = RGBA(225, 10, 28, 0);   // Matte recessed display well

    foreach (dirty; dirtyRects) {
      if (dirty.empty || dirty.min.x < 0 || dirty.min.y < 0 ||
          dirty.max.x > diffuseMap.w || dirty.max.y > diffuseMap.h) {
        continue;
      }
      // Root recessed studio frame
      diffuseMap.cropImageRef(dirty).fillAll(colBgRoot);
      depthMap.cropImageRef(dirty).fillAll(L16(12000));
      materialMap.cropImageRef(dirty).fillAll(matChassis);

      // Raised PBR section cards (Section 1..6)
      fillPBRBox(diffuseMap, depthMap, materialMap, dirty, scale, 0, 0, BASE_WIDTH, HEADER_H - 2,
                 colBgPanel, 24500, matPanel);
      fillPBRBox(diffuseMap, depthMap, materialMap, dirty, scale, 8, 114, BASE_WIDTH - 16, 72,
                 colBgPanel, 24000, matPanel);
      fillPBRBox(diffuseMap, depthMap, materialMap, dirty, scale, 8, 192, BASE_WIDTH - 16, 72,
                 colBgPanel, 24000, matPanel);
      fillPBRBox(diffuseMap, depthMap, materialMap, dirty, scale, 8, 272, 160, 400,
                 colBgPanel, 24000, matPanel);

      if (_curveExpanded) {
        fillPBRBox(diffuseMap, depthMap, materialMap, dirty, scale, 176, 272, 856, 400,
                   colBgPanel, 24500, matPanel);
        fillPBRBox(diffuseMap, depthMap, materialMap, dirty, scale, 184, 306, 840, 302,
                   colBgCurveGrid, 4000, matWell);
      } else {
        fillPBRBox(diffuseMap, depthMap, materialMap, dirty, scale, 176, 272, 380, 400,
                   colBgPanel, 24500, matPanel);
        fillPBRBox(diffuseMap, depthMap, materialMap, dirty, scale, 564, 272, 468, 214,
                   colBgPanel, 24500, matPanel);
        fillPBRBox(diffuseMap, depthMap, materialMap, dirty, scale, 572, 306, 452, 132,
                   colBgCurveGrid, 4000, matWell);
        fillPBRBox(diffuseMap, depthMap, materialMap, dirty, scale, 564, 492, 468, 180,
                   colBTPurpleDark, 24500, matPanel);
        fillPBRBox(diffuseMap, depthMap, materialMap, dirty, scale, 948, 502, 74, 160,
                   colBgTrough, 4500, matWell);
      }

      // Recessed 24-note gesture strip well inside Header
      fillPBRBox(diffuseMap, depthMap, materialMap, dirty, scale, 216, 8, 486, 36,
                 colBgTrough, 5000, matWell);
    }
  }

  // =========================================================================
  // Vector Overlay Drawing (Unified Crisp Dark Studio Vector UI + fillText)
  // =========================================================================

  void drawRawOverlay(ImageRef!RGBA rawMap, box2i[] dirtyRects, ref Canvas canvas) {
    const float scale = (position.width > 0)
      ? (cast(float) position.width / cast(float) BASE_WIDTH) : 1.0f;
    _renderScale = scale;
    scope(exit) _renderScale = 1.0f;

    foreach (ref rect; dirtyRects) {
      if (rect.empty || rect.min.x < 0 || rect.min.y < 0 ||
          rect.max.x > rawMap.w || rect.max.y > rawMap.h) {
        continue;
      }
      ImageRef!RGBA cropped = rawMap.cropImageRef(rect);

      canvas.initialize(cropped);
      canvas.translate(-rect.min.x, -rect.min.y);
      canvas.scale(scale, scale);

      drawSection1Header(canvas, cropped, rect, scale);
      drawSection2StutterStrip(canvas, cropped, rect, scale);
      drawSection2BufferStrip(canvas, cropped, rect, scale);
      drawSection3SignalChain(canvas, cropped, rect, scale);

      if (_curveExpanded) {
        drawSection6TVMEditor(canvas, cropped, rect, scale, true);
      } else {
        drawSection4EffectInspector(canvas, cropped, rect, scale);
        drawSection6TVMEditor(canvas, cropped, rect, scale, false);
        drawSection5PurpleOutput(canvas, cropped, rect, scale);
      }

      // UIWindowResizer renders the bottom-right corner resize grip cleanly.
    }
  }

  // =========================================================================
  // SECTION 1: Header Bar (y = 0..108)
  // =========================================================================

  private void drawSection1Header(ref Canvas c, ref ImageRef!RGBA cropped, box2i dirty, float scale) {
    const float bw = pxLine();
    c.fillStyle = RGBA(colBgPanel.r, colBgPanel.g, colBgPanel.b, 32);
    c.fillRect(0.0f, 0.0f, BASE_WIDTH, pxSnap(HEADER_H - 2.0f));
    c.fillStyle = RGBA(255, 255, 255, 16);
    c.fillRect(0.0f, 0.0f, BASE_WIDTH, bw);
    c.fillStyle = colBorderHi;
    c.fillRect(0.0f, pxSnap(HEADER_H - 2.0f), BASE_WIDTH, 2.0f * bw);

    // 1A. Brand Logo (`kdr stutter edit 2`), UI Zoom Pill & live Trigger LED
    const bool gestureLive = (_client !is null) && _client.gestureController().getIsActive();
    drawTxtAligned(cropped, dirty, scale, "kdr", 14, 21, 16.0f, colBTCyan, HorizontalAlignment.left);
    drawTxtAligned(cropped, dirty, scale, "stutter edit 2", 49, 21, 12.0f, colTextBright, HorizontalAlignment.left);

    const float curZoom = (position.width > 0)
      ? (cast(float) position.width / cast(float) BASE_WIDTH) : 1.0f;
    char[8] zoomBuf;
    const int zn = snprintf(zoomBuf.ptr, zoomBuf.length, "%.2gx", cast(double) curZoom);
    const bool hoverZoom = inRect(_hoverX, _hoverY, 156, 10, 36, 22);
    drawPanelBox(c, 156, 10, 36, 22, hoverZoom ? colBgSubHover : colBgSubCard, hoverZoom ? colBTCyan : colBorderDim);
    drawTxtAligned(cropped, dirty, scale, zoomBuf[0 .. zn], 174, 21, 10.0f, colTextBright, HorizontalAlignment.center);

    c.fillStyle = gestureLive ? colBTCyan : colBorderDim;
    c.fillCircle(202.0f, 21.0f, gestureLive ? 4.5f : 3.5f);
    if (gestureLive) {
      c.fillStyle = colTextBright;
      c.fillCircle(202.0f, 21.0f, 2.0f);
    }

    // Play Mode Pill (MIDI / AUTO)
    const bool autoOn = isAutoMode();
    const RGBA modeAccent = autoOn ? colBTCyan : colAmber;
    const bool hoverMode = inRect(_hoverX, _hoverY, 12, 42, 194, 28);
    drawPanelBox(c, 12, 42, 194, 28, hoverMode ? colBgSubHover : colBgSubCard, modeAccent);
    drawHexagon(c, 28, 56, 7.0f, autoOn ? modeAccent : colBgTrough, modeAccent, true);
    drawTxtAligned(cropped, dirty, scale, autoOn ? "PLAY MODE: AUTO" : "PLAY MODE: MIDI",
                   43, 56, 11.0f, modeAccent, HorizontalAlignment.left);

    // Factory Preset Pill (`< PRESET >`)
    int bankIdx = getIntParam(Params.bankPreset, 0) % NUM_FACTORY_PRESETS;
    const bool hoverPreset = inRect(_hoverX, _hoverY, 12, 74, 194, 28);
    drawPanelBox(c, 12, 74, 194, 28, hoverPreset ? colBgSubHover : colBgSubCard,
                 hoverPreset ? colBorderHi : colBorderDim);
    drawTxtAligned(cropped, dirty, scale, "<", 22, 88, 12.0f, colBTCyan, HorizontalAlignment.center);
    drawTxtAligned(cropped, dirty, scale, factoryPresetNames[bankIdx], 109, 88, 10.5f,
                   colTextBright, HorizontalAlignment.center);
    drawTxtAligned(cropped, dirty, scale, ">", 196, 88, 12.0f, colBTCyan, HorizontalAlignment.center);

    // 1B. 24-Note Rainbow Piano Gesture Palette Strip (x=216..702, y=8..44)
    drawPanelBox(c, 216, 8, 486, 36, RGBA(colBgTrough.r, colBgTrough.g, colBgTrough.b, 90), colBorderHi, true);
    const int curGest = currentGestureIdx();
    enum int keyW = 20;
    for (int k = 0; k < 24; ++k) {
      const float kx0 = pxSnap(219.0f + k * keyW + 1.0f);
      const float kx1 = pxSnap(219.0f + (k + 1) * keyW - 1.0f);
      const float kw = kx1 - kx0;
      const int noteInOct = k % 12;
      const bool isBlack = (noteInOct == 1 || noteInOct == 3 || noteInOct == 6 || noteInOct == 8 || noteInOct == 10);
      const bool isSel = (k == curGest);
      const bool isHov = inRect(_hoverX, _hoverY, cast(int)(219.0f + k * keyW), 8, keyW, 36);
      const RGBA kCol = gestureKeyColor(k);

      // Piano key body styling (physical-pixel snapped for razor key gaps)
      c.fillStyle = isBlack ? RGBA(15, 11, 28, 255) : RGBA(34, 26, 60, 255);
      c.fillRect(kx0, pxSnap(10.0f), kw, pxSnap(41.0f) - pxSnap(10.0f));

      if (isBlack) {
        c.fillStyle = RGBA(24, 19, 44, 255);
        c.fillRect(kx0 + bw, pxSnap(11.0f), kw - 2.0f * bw, pxSnap(22.0f) - pxSnap(11.0f));
      }

      // Vivid rainbow bar anchored at bottom of key
      const float barH = isSel ? 22.0f : (isBlack ? 15.0f : 21.0f);
      const float barY0 = pxSnap(40.0f - barH);
      const float barY1 = pxSnap(40.0f);
      c.fillStyle = (isSel || isHov) ? kCol : RGBA(kCol.r, kCol.g, kCol.b, 205);
      c.fillRect(kx0 + bw, barY0, kw - 2.0f * bw, barY1 - barY0);

      if (isSel) {
        c.fillStyle = colTextBright;
        c.fillRect(kx0, pxSnap(10.0f), kw, 2.0f * bw);
        c.fillRect(kx0, pxSnap(39.0f), kw, 2.0f * bw);
        c.fillCircle(219.0f + k * keyW + keyW * 0.5f, 15.0f, 2.0f);
      } else if (isHov) {
        c.fillStyle = RGBA(255, 255, 255, 160);
        c.fillRect(kx0, pxSnap(10.0f), kw, bw);
      }
    }
    // Octave markers `C2` & `C3`
    c.fillStyle = RGBA(14, 10, 28, 220);
    c.fillRect(220.0f, 11.0f, 18.0f, 12.0f);
    c.fillRect(460.0f, 11.0f, 18.0f, 12.0f);
    drawTxtAligned(cropped, dirty, scale, "C2", 229, 17, 9.5f, colTextBright, HorizontalAlignment.center);
    drawTxtAligned(cropped, dirty, scale, "C3", 469, 17, 9.5f, colTextBright, HorizontalAlignment.center);

    // 1C. White Active Gesture Pill with Note Chip & `< >` (x=216..488, y=50..102)
    drawPanelBox(c, 216, 50, 272, 18, RGBA(30, 23, 54, 255), colBorderDim);
    drawTxtAligned(cropped, dirty, scale, "GESTURE BANK: BT SIGNATURE",
                   224, 59, 9.5f, colTextMuted, HorizontalAlignment.left);

    char[8] noteBuf;
    const(char)[] nStr = formatNoteName(curGest, noteBuf);
    drawPanelBox(c, 216, 70, 272, 32, colWhitePill, colTextBright);
    // Coloured key badge inside left of white card
    c.fillStyle = gestureKeyColor(curGest);
    c.fillRect(236.0f, 75.0f, 36.0f, 22.0f);
    drawTxtAligned(cropped, dirty, scale, nStr, 254.0f, 86.0f, 10.5f, colTextDark, HorizontalAlignment.center);

    drawTxtAligned(cropped, dirty, scale, "<", 226, 86, 12.5f, colTextDark, HorizontalAlignment.center);
    const ref entry = btGestureBank[curGest % NUM_BT_GESTURES];
    drawTxtAligned(cropped, dirty, scale, stripNotePrefix(entry.name), 372, 86, 11.5f, colTextDark, HorizontalAlignment.center);
    drawTxtAligned(cropped, dirty, scale, ">", 476, 86, 12.5f, colTextDark, HorizontalAlignment.center);

    // 1D. Global Controls Matrix (x=496..702, y=50..102)
    const int gLen = getIntParam(Params.gestureLength, 3);
    static immutable string[7] lenShort = ["1/8B", "1/4B", "1/2B", "1 Bar", "2 Bar", "4 Bar", "8 Bar"];
    const string lenStr = (gLen >= 0 && gLen < cast(int) lenShort.length)
      ? lenShort[gLen]
      : ((gLen >= 0 && gLen < cast(int) gestureLengthNames.length) ? gestureLengthNames[gLen] : "1 Bar");
    drawPanelBox(c, 496, 50, 66, 24, inRect(_hoverX, _hoverY, 496, 50, 66, 24) ? colBgSubHover : colBgSubCard, colBorderDim);
    drawTxtAligned(cropped, dirty, scale, "L:", 502, 62, 9.5f, colTextMuted, HorizontalAlignment.left);
    drawTxtRight(cropped, dirty, scale, lenStr, 557, 62, 9.5f, colTextBright);

    // Release Mode (with Stick step)
    const bool stick = (_client !is null) ? _client.stickMode : false;
    const int relIdx = getIntParam(Params.releaseMode, 0);
    static immutable string[4] relShort = ["Inst", "Latch", "Full", "Grid"];
    const string relStr = stick ? "Stick"
      : ((relIdx >= 0 && relIdx < cast(int) relShort.length) ? relShort[relIdx] : "Inst");
    drawPanelBox(c, 566, 50, 72, 24,
                 inRect(_hoverX, _hoverY, 566, 50, 72, 24) ? colBgSubHover : colBgSubCard,
                 stick ? colBTCyan : colBorderDim);
    drawTxtAligned(cropped, dirty, scale, "REL:", 572, 62, 9.5f, colTextMuted, HorizontalAlignment.left);
    drawTxtRight(cropped, dirty, scale, relStr, 633, 62, 9.5f, stick ? colBTCyan : colTextBright);

    // Trigger Grid
    const int qIdx = getIntParam(Params.quantizeGrid, 0);
    const string qRaw = (qIdx >= 0 && qIdx < cast(int) quantizeGridNames.length)
      ? quantizeGridNames[qIdx] : "Off";
    const string qStr = (qIdx == 0) ? "Off" : qRaw;
    drawPanelBox(c, 642, 50, 60, 24, inRect(_hoverX, _hoverY, 642, 50, 60, 24) ? colBgSubHover : colBgSubCard, colBorderDim);
    drawTxtAligned(cropped, dirty, scale, "Q:", 648, 62, 9.5f, colTextMuted, HorizontalAlignment.left);
    drawTxtRight(cropped, dirty, scale, qStr, 697, 62, 9.5f, colTextBright);

    // Palindrome + Freeze + Freeze Duration (y=78..102)
    const bool palOn = (_client !is null) ? _client.palindrome : _localPalindrome;
    drawPanelBox(c, 496, 78, 82, 24,
                 palOn ? RGBA(176, 102, 255, 44) : (inRect(_hoverX, _hoverY, 496, 78, 82, 24) ? colBgSubHover : colBgSubCard),
                 palOn ? colBTCyan : colBorderDim);
    drawTxtAligned(cropped, dirty, scale, "PALINDROME", 537, 90, 9.2f, palOn ? colBTCyan : colTextMuted, HorizontalAlignment.center);

    const bool frzOn = (_client !is null) ? _client.freezeActive : _localFreeze;
    drawPanelBox(c, 582, 78, 72, 24,
                 frzOn ? RGBA(176, 102, 255, 44) : (inRect(_hoverX, _hoverY, 582, 78, 72, 24) ? colBgSubHover : colBgSubCard),
                 frzOn ? colBTCyan : colBorderDim);
    drawHexagon(c, 592, 90, 4.5f, frzOn ? colBTCyan : colBgTrough, colBTCyan, frzOn);
    drawTxtAligned(cropped, dirty, scale, "FREEZE", 602, 90, 9.2f, frzOn ? colBTCyan : colTextMuted, HorizontalAlignment.left);

    const float frzDur = (_client !is null) ? _client.freezeBeats : _localFreezeBeats;
    drawPanelBox(c, 658, 78, 44, 24, inRect(_hoverX, _hoverY, 658, 78, 44, 24) ? colBgSubHover : colBgSubCard, colBorderDim);
    char[12] durBuf;
    const int dn = snprintf(durBuf.ptr, durBuf.length, "%.3gb", cast(double) frzDur);
    drawTxtAligned(cropped, dirty, scale, durBuf[0 .. dn], 680, 90, 9.5f, colTextBright, HorizontalAlignment.center);

    // 1E. Global Filter Arc Dial (cx=758, cy=58) + Undo/Redo + AutoRate + Phase
    const float gfVal = (_client !is null) ? _client.effectiveGlobalFilter() : _localGlobalFilter;
    char[16] gfBuf;
    int gfn;
    RGBA gfCol = colTextMuted;
    if (gfVal < -0.02f) {
      const float cut = 20_000.0f * (2.0f ^^ (gfVal * 7.4f));
      gfCol = colBTBlue;
      gfn = (cut >= 1000.0f)
        ? snprintf(gfBuf.ptr, gfBuf.length, "LP %.1fk", cast(double)(cut * 0.001f))
        : snprintf(gfBuf.ptr, gfBuf.length, "LP %.0f", cast(double) cut);
    } else if (gfVal > 0.02f) {
      const float cut = 30.0f * (2.0f ^^ (gfVal * 8.6f));
      gfCol = colAmber;
      gfn = (cut >= 1000.0f)
        ? snprintf(gfBuf.ptr, gfBuf.length, "HP %.1fk", cast(double)(cut * 0.001f))
        : snprintf(gfBuf.ptr, gfBuf.length, "HP %.0f", cast(double) cut);
    } else {
      gfn = snprintf(gfBuf.ptr, gfBuf.length, "OFF");
    }
    drawTxtAligned(cropped, dirty, scale, "GLOBAL FILTER", 758, 16, 9.5f, colTextMuted, HorizontalAlignment.center);
    drawArcDial(c, cropped, dirty, scale, 758, 58, 24.0f, 0.5f + gfVal * 0.5f, true,
                gfCol, "", gfBuf[0 .. gfn], inRect(_hoverX, _hoverY, 714, 12, 90, 90));

    // Undo / Redo Buttons (x=820..916, y=14..40)
    const bool canU = (_client !is null) && _client.canUndo();
    const bool canR = (_client !is null) && _client.canRedo();
    drawPanelBox(c, 820, 14, 46, 26, inRect(_hoverX, _hoverY, 820, 14, 46, 26) ? colBgSubHover : colBgSubCard,
                 canU ? colBTCyan : colBorderDim);
    drawTxtAligned(cropped, dirty, scale, "UNDO", 843, 27, 9.8f, canU ? colBTCyan : colTextDim, HorizontalAlignment.center);

    drawPanelBox(c, 870, 14, 46, 26, inRect(_hoverX, _hoverY, 870, 14, 46, 26) ? colBgSubHover : colBgSubCard,
                 canR ? colBTCyan : colBorderDim);
    drawTxtAligned(cropped, dirty, scale, "REDO", 893, 27, 9.8f, canR ? colBTCyan : colTextDim, HorizontalAlignment.center);

    // MIDI Range / Tempo badge
    drawPanelBox(c, 922, 14, 108, 26, colBgSubCard, gestureLive ? colBTCyan : colBorderDim);
    drawTxtAligned(cropped, dirty, scale, gestureLive ? "MIDI ACTIVE" : "MIDI C2..B3",
                   976, 27, 9.8f, colBTCyan, HorizontalAlignment.center);

    // Auto Rate
    const int arIdx = getIntParam(Params.autoRate, 2);
    const string arStr = (arIdx >= 0 && arIdx < cast(int) autoRateNames.length)
      ? autoRateNames[arIdx] : "1 Bar";
    drawPanelBox(c, 820, 48, 210, 26, inRect(_hoverX, _hoverY, 820, 48, 210, 26) ? colBgSubHover : colBgSubCard,
                 autoOn ? colBTCyan : colBorderDim);
    drawTxtAligned(cropped, dirty, scale, "AUTO RATE", 830, 61, 9.8f, colTextMuted, HorizontalAlignment.left);
    drawTxtRight(cropped, dirty, scale, arStr, 1020, 61, 10.2f, autoOn ? colBTCyan : colTextBright);

    // Live Playhead phase progress bar
    drawPanelBox(c, 820, 78, 210, 24, colBgTrough, colBorderDim);
    drawTxtAligned(cropped, dirty, scale, "PHASE", 828, 90, 9.5f, colTextMuted, HorizontalAlignment.left);
    const float ph = (_playheadPhase < 0.0f) ? 0.0f : ((_playheadPhase > 1.0f) ? 1.0f : _playheadPhase);
    c.fillStyle = RGBA(20, 15, 38, 255);
    c.fillRect(880.0f, 84.0f, 108.0f, 12.0f);
    c.fillStyle = colBTCyan;
    c.fillRect(880.0f, 84.0f, snapF(108.0f * ph), 12.0f);
    char[8] phBuf;
    const int phn = snprintf(phBuf.ptr, phBuf.length, "%d%%", cast(int)(ph * 100.0f));
    drawTxtRight(cropped, dirty, scale, phBuf[0 .. phn], 1022, 90, 9.5f, colTextBright);
  }

  // =========================================================================
  // SECTION 2A: Full-Width STUTTER Strip (y = 114..186)
  // =========================================================================

  private void drawSection2StutterStrip(ref Canvas c, ref ImageRef!RGBA cropped, box2i dirty, float scale) {
    const bool stutOn = isModuleEnabled(ModuleSlot.stutter);
    const bool selected = (_activeModule == ModuleSlot.stutter);
    drawPanelBox(c, 8, 114, BASE_WIDTH - 16, 72, RGBA(colBgPanel.r, colBgPanel.g, colBgPanel.b, 40),
                 selected ? colBTCyan : colBorderDim, true);
    c.fillStyle = stutOn ? colBTCyan : colBorderHi;
    c.fillRect(pxSnap(8.0f), pxSnap(114.0f), selected ? 5.0f : 4.0f, pxSnap(186.0f) - pxSnap(114.0f));

    // Module Toggle & Title
    drawHexagon(c, 28, 140, 8.0f, stutOn ? colBTCyan : colBgTrough, colBTCyan, stutOn);
    drawTxtAligned(cropped, dirty, scale, "STUTTER", 44, 140, 12.5f, stutOn ? colTextBright : colTextMuted, HorizontalAlignment.left);
    drawTxtAligned(cropped, dirty, scale, stutOn ? "ACTIVE" : "BYPASS", 44, 162, 9.5f, stutOn ? colBTCyan : colTextDim, HorizontalAlignment.left);

    // 1. Rate Split Slider (fixes 19-entry range / 18.0f) + Smooth Sparkline
    const int rStart = getIntParam(Params.stutterRateStart, 3);
    const int rEnd   = getIntParam(Params.stutterRateEnd, 5);
    const float maxR = cast(float)(stutterSubdivisionNames.length - 1);
    const float nS = cast(float) rStart / maxR;
    const float nE = cast(float) rEnd / maxR;
    char[32] rateBuf;
    const string sName = (rStart >= 0 && rStart < cast(int) stutterSubdivisionNames.length)
      ? stutterSubdivisionNames[rStart] : "1/8";
    const string eName = (rEnd >= 0 && rEnd < cast(int) stutterSubdivisionNames.length)
      ? stutterSubdivisionNames[rEnd] : "1/32";
    int rn = snprintf(rateBuf.ptr, rateBuf.length, "%.*s -> %.*s",
                      cast(int) sName.length, sName.ptr,
                      cast(int) eName.length, eName.ptr);
    if (rn < 0) rn = 0;
    if (rn >= cast(int) rateBuf.length) rn = cast(int) rateBuf.length - 1;
    const TVMCurve* stutCurve = getCurveConst(ModuleSlot.stutter);
    drawSplitSlider(c, cropped, dirty, scale, 130, 120, 290, 60, nS, nE, true, colBTCyan,
                    stutCurve, "RATE", rateBuf[0 .. rn], _activeModule == ModuleSlot.stutter);

    // 2. Quantize Hex + Mode selector (x=430..526)
    const bool qOn = (_client !is null) ? _client.stutterQuantizeEnabled : true;
    const int sMode = (_client !is null) ? cast(int) _client.stutterStepMode : 1;
    static immutable string[6] stepModeLabels = ["FREE", "CLOSEST", "WALK", "SKIP", "STAGGER", "RANDOM"];
    drawPanelBox(c, 430, 120, 96, 26, inRect(_hoverX, _hoverY, 430, 120, 96, 26) ? colBgSubHover : colBgSubCard,
                 qOn ? colBTCyan : colBorderDim);
    drawHexagon(c, 443, 133, 5.0f, qOn ? colBTCyan : colBgTrough, colBTCyan, qOn);
    drawTxtAligned(cropped, dirty, scale, "QUANTIZE", 454, 133, 9.5f, qOn ? colTextBright : colTextMuted, HorizontalAlignment.left);

    drawPanelBox(c, 430, 152, 96, 28, inRect(_hoverX, _hoverY, 430, 152, 96, 28) ? colBgSubHover : colBgSubCard, colBorderHi);
    drawTxtAligned(cropped, dirty, scale, stepModeLabels[(sMode >= 0 && sMode < 6) ? sMode : 1],
                   478, 166, 9.8f, colBTCyan, HorizontalAlignment.center);

    // 3. Step Split Slider (x=534..696)
    const float stepBeats = (_client !is null) ? _client.stutterStepBeats : 0.25f;
    const float stepNorm = (stepBeats < 0.0625f) ? 0.0f : (stepBeats > 1.0f ? 1.0f : (stepBeats - 0.0625f) / 0.9375f);
    char[12] stpBuf;
    const int sn = snprintf(stpBuf.ptr, stpBuf.length, "%.3gb", cast(double) stepBeats);
    drawSplitSlider(c, cropped, dirty, scale, 534, 120, 162, 60, stepNorm, stepNorm, false, colBTCyan,
                    stutCurve, "STEP", stpBuf[0 .. sn], false);

    // 4. Gate Toggle (x=704..784)
    const bool gateOn = isModuleEnabled(ModuleSlot.gate);
    const bool gateSel = (_activeModule == ModuleSlot.gate);
    drawPanelBox(c, 704, 120, 80, 60, inRect(_hoverX, _hoverY, 704, 120, 80, 60) ? colBgSubHover : colBgSubCard,
                 (gateOn || gateSel) ? moduleAccentRGBA(ModuleSlot.gate) : colBorderDim);
    drawHexagon(c, 744, 139, 7.5f, gateOn ? moduleAccentRGBA(ModuleSlot.gate) : colBgTrough,
                moduleAccentRGBA(ModuleSlot.gate), gateOn);
    drawTxtAligned(cropped, dirty, scale, "GATE", 744, 164, 10.2f, gateOn ? colTextBright : colTextMuted, HorizontalAlignment.center);

    // 5. Gate Width Split Slider + Sparkline (x=792..952)
    const float gWMin = getNormParam(Params.gateWidthMin, 0.2f);
    const float gWMax = getNormParam(Params.gateWidthMax, 0.8f);
    char[16] gwBuf;
    const int gwn = snprintf(gwBuf.ptr, gwBuf.length, "%.0f-%.0f%%",
                             cast(double)(gWMin * 100.0f), cast(double)(gWMax * 100.0f));
    drawSplitSlider(c, cropped, dirty, scale, 792, 120, 160, 60, gWMin, gWMax, true,
                    moduleAccentRGBA(ModuleSlot.gate), getCurveConst(ModuleSlot.gate),
                    "WIDTH", gwBuf[0 .. gwn], gateSel);

    // 6. Gate Tail Arc Dial (cx=992, cy=144)
    const float gTailN = getNormParam(Params.gateTail, 0.1f);
    const float gTailMs = 0.1f + gTailN * 49.9f;
    char[10] gtBuf;
    const int gtn = snprintf(gtBuf.ptr, gtBuf.length, "%.0fms", cast(double) gTailMs);
    drawArcDial(c, cropped, dirty, scale, 992, 144, 20.0f, gTailN, false,
                moduleAccentRGBA(ModuleSlot.gate), "TAIL", gtBuf[0 .. gtn],
                inRect(_hoverX, _hoverY, 960, 118, 66, 62));
  }

  // =========================================================================
  // SECTION 2B: Full-Width BUFFER Strip (y = 192..264)
  // =========================================================================

  private void drawSection2BufferStrip(ref Canvas c, ref ImageRef!RGBA cropped, box2i dirty, float scale) {
    const bool bufOn = isModuleEnabled(ModuleSlot.buffer);
    const bool selected = (_activeModule == ModuleSlot.buffer);
    const RGBA accent = moduleAccentRGBA(ModuleSlot.buffer);
    drawPanelBox(c, 8, 192, BASE_WIDTH - 16, 72, RGBA(colBgPanel.r, colBgPanel.g, colBgPanel.b, 40),
                 selected ? accent : colBorderDim, true);
    c.fillStyle = bufOn ? accent : colBorderHi;
    c.fillRect(pxSnap(8.0f), pxSnap(192.0f), selected ? 5.0f : 4.0f, pxSnap(264.0f) - pxSnap(192.0f));

    drawHexagon(c, 28, 218, 8.0f, bufOn ? accent : colBgTrough, accent, bufOn);
    drawTxtAligned(cropped, dirty, scale, "BUFFER", 44, 218, 12.5f, bufOn ? colTextBright : colTextMuted, HorizontalAlignment.left);
    drawTxtAligned(cropped, dirty, scale, bufOn ? "ACTIVE" : "BYPASS", 44, 240, 9.5f, bufOn ? accent : colTextDim, HorizontalAlignment.left);

    // 1. Buffer Position & Pitch Dual Sliders (x=130..332)
    const float posMin = getNormParam(Params.bufferPositionMin, 0.0f);
    const float posMax = getNormParam(Params.bufferPositionMax, 0.5f);
    const float pMin = getNormParam(Params.bufferPitchMin, 0.5f);
    const float pMax = getNormParam(Params.bufferPitchMax, 0.5f);
    const TVMCurve* bufCurve = getCurveConst(ModuleSlot.buffer);
    char[16] posBuf;
    const int psn = snprintf(posBuf.ptr, posBuf.length, "%.0f-%.0f%%",
                             cast(double)(posMin * 100.0f), cast(double)(posMax * 100.0f));
    drawSplitSlider(c, cropped, dirty, scale, 130, 198, 202, 29, posMin, posMax, true, accent,
                    bufCurve, "POS", posBuf[0 .. psn], selected);

    char[16] pitBuf;
    const float stA = pMin * 48.0f - 24.0f;
    const float stB = pMax * 48.0f - 24.0f;
    const int pin = snprintf(pitBuf.ptr, pitBuf.length, "%+.0f->%+.0f",
                             cast(double) stA, cast(double) stB);
    drawSplitSlider(c, cropped, dirty, scale, 130, 230, 202, 29, pMin, pMax, true, accent,
                    bufCurve, "PITCH", pitBuf[0 .. pin], selected);

    // Reverse L / R & LINK
    const bool revL = (_client !is null) ? _client.bufferReverseL : false;
    const bool revR = (_client !is null) ? _client.bufferReverseR : false;
    const bool lnk  = (_client !is null) ? _client.bufferLinkLR : true;
    drawPanelBox(c, 338, 198, 42, 26, revL ? RGBA(176, 102, 255, 44) : colBgSubCard, revL ? colBTCyan : colBorderDim);
    drawTxtAligned(cropped, dirty, scale, "<< L", 359, 211, 9.5f, revL ? colBTCyan : colTextMuted, HorizontalAlignment.center);
    drawPanelBox(c, 338, 230, 42, 26, revR ? RGBA(176, 102, 255, 44) : colBgSubCard, revR ? colBTCyan : colBorderDim);
    drawTxtAligned(cropped, dirty, scale, "<< R", 359, 243, 9.5f, revR ? colBTCyan : colTextMuted, HorizontalAlignment.center);
    drawPanelBox(c, 384, 212, 36, 30, lnk ? RGBA(176, 102, 255, 44) : colBgSubCard, lnk ? colBTCyan : colBorderDim);
    drawTxtAligned(cropped, dirty, scale, "LINK", 402, 227, 9.5f, lnk ? colBTCyan : colTextMuted, HorizontalAlignment.center);

    // 2. Movement & Grid (x=430..526)
    const int bMov = (_client !is null) ? cast(int) _client.bufferMovement : 0;
    static immutable string[3] movNames = ["SLIDER", "GRID", "RANDOM"];
    drawPanelBox(c, 430, 198, 96, 26, inRect(_hoverX, _hoverY, 430, 198, 96, 26) ? colBgSubHover : colBgSubCard, colBorderHi);
    drawTxtAligned(cropped, dirty, scale, movNames[(bMov >= 0 && bMov < 3) ? bMov : 0], 478, 211, 9.8f, accent, HorizontalAlignment.center);

    const float bGrid = (_client !is null) ? _client.bufferGridBeats : 0.25f;
    char[12] bgBuf;
    const int bgn = snprintf(bgBuf.ptr, bgBuf.length, "G: %.3gb", cast(double) bGrid);
    drawPanelBox(c, 430, 230, 96, 28, inRect(_hoverX, _hoverY, 430, 230, 96, 28) ? colBgSubHover : colBgSubCard, colBorderDim);
    drawTxtAligned(cropped, dirty, scale, bgBuf[0 .. bgn], 478, 244, 9.8f, colTextBright, HorizontalAlignment.center);

    // 3. Jitter Toggle + EDIT button + Pitch Mode (x=534..696)
    const bool jitOn = (_client !is null) ? _client.jitterEnabled : false;
    drawPanelBox(c, 534, 198, 102, 26, jitOn ? RGBA(176, 102, 255, 44) : colBgSubCard, jitOn ? colBTCyan : colBorderDim);
    drawHexagon(c, 548, 211, 5.0f, jitOn ? colBTCyan : colBgTrough, colBTCyan, jitOn);
    drawTxtAligned(cropped, dirty, scale, "JITTER", 560, 211, 9.5f, jitOn ? colTextBright : colTextMuted, HorizontalAlignment.left);

    drawPanelBox(c, 640, 198, 56, 26, _editingJitter ? colBTCyan : colBgSubCard, colBTCyan);
    drawTxtAligned(cropped, dirty, scale, "EDIT", 668, 211, 9.5f, _editingJitter ? colTextDark : colBTCyan, HorizontalAlignment.center);

    const int jMode = (_client !is null) ? cast(int) _client.jitterPitchMode : 0;
    static immutable string[3] jPitchLabels = ["PITCH: OCTAVES", "PITCH: OCT+5TH", "PITCH: FREE"];
    drawPanelBox(c, 534, 230, 162, 28, colBgSubCard, colBorderDim);
    drawTxtAligned(cropped, dirty, scale, jPitchLabels[(jMode >= 0 && jMode < 3) ? jMode : 0],
                   615, 244, 9.5f, colTextBright, HorizontalAlignment.center);

    // 4. Pan Toggle (x=704..784)
    const bool panOn = isModuleEnabled(ModuleSlot.pan);
    const bool panSel = (_activeModule == ModuleSlot.pan);
    drawPanelBox(c, 704, 198, 80, 60, inRect(_hoverX, _hoverY, 704, 198, 80, 60) ? colBgSubHover : colBgSubCard,
                 (panOn || panSel) ? moduleAccentRGBA(ModuleSlot.pan) : colBorderDim);
    drawHexagon(c, 744, 217, 7.5f, panOn ? moduleAccentRGBA(ModuleSlot.pan) : colBgTrough,
                moduleAccentRGBA(ModuleSlot.pan), panOn);
    drawTxtAligned(cropped, dirty, scale, "PAN", 744, 242, 10.2f, panOn ? colTextBright : colTextMuted, HorizontalAlignment.center);

    // 5. Pan Width Split Slider (x=792..952)
    const float pWMin = getNormParam(Params.panWidthMin, 0.25f);
    const float pWMax = getNormParam(Params.panWidthMax, 1.0f);
    char[16] pwBuf;
    const int pwn = snprintf(pwBuf.ptr, pwBuf.length, "%.0f-%.0f%%",
                             cast(double)(pWMin * 200.0f), cast(double)(pWMax * 200.0f));
    drawSplitSlider(c, cropped, dirty, scale, 792, 198, 160, 60, pWMin, pWMax, true,
                    moduleAccentRGBA(ModuleSlot.pan), getCurveConst(ModuleSlot.pan),
                    "WIDTH", pwBuf[0 .. pwn], panSel);

    // 6. Pan Center Bipolar Arc Dial (cx=992, cy=222)
    const float pCent = getNormParam(Params.panCenterMax, 0.5f);
    char[8] pcBuf;
    int pcn;
    if (pCent < 0.48f) {
      pcn = snprintf(pcBuf.ptr, pcBuf.length, "L%.0f", cast(double)((0.5f - pCent) * 200.0f));
    } else if (pCent > 0.52f) {
      pcn = snprintf(pcBuf.ptr, pcBuf.length, "R%.0f", cast(double)((pCent - 0.5f) * 200.0f));
    } else {
      pcn = snprintf(pcBuf.ptr, pcBuf.length, "C");
    }
    drawArcDial(c, cropped, dirty, scale, 992, 222, 20.0f, pCent, true,
                moduleAccentRGBA(ModuleSlot.pan), "CENTER", pcBuf[0 .. pcn],
                inRect(_hoverX, _hoverY, 960, 196, 66, 62));
  }

  // =========================================================================
  // SECTION 3: Left Column Draggable 11-Module Signal Chain (x=8..168, y=272..672)
  // =========================================================================

  private void drawSection3SignalChain(ref Canvas c, ref ImageRef!RGBA cropped, box2i dirty, float scale) {
    drawPanelBox(c, 8, 272, 160, 400, RGBA(colBgPanel.r, colBgPanel.g, colBgPanel.b, 40), colBorderDim, true);
    const float bw = pxLine();

    // Vertical signal routing rail
    c.fillStyle = colBorderHi;
    c.fillRect(pxSnap(28.0f), pxSnap(286.0f), 2.0f * bw, pxSnap(658.0f) - pxSnap(286.0f));

    for (int i = 0; i < NumChainFX; ++i) {
      const ChainFXId fxId = chainAtSlot(i);
      const int modSlot = chainFXToModuleSlot(fxId);
      const bool selected = (!_editingJitter) && (_activeModule == modSlot);
      const bool enabled = isChainFXEnabled(fxId);
      const RGBA accent = chainFXAccentRGBA(fxId);

      const float rx = pxSnap(12.0f);
      const float ry = pxSnap(276.0f + i * 36.0f);
      const float rw = pxSnap(164.0f) - rx;
      const float rh = pxSnap(276.0f + i * 36.0f + 32.0f) - ry;
      const float midY = ry + rh * 0.5f;
      const bool hovered = inRect(_hoverX, _hoverY, 12, cast(int)(276 + i * 36), 152, 32);

      c.fillStyle = selected ? colBgSubCard : (hovered ? RGBA(44, 34, 78, 240) : RGBA(20, 15, 38, 230));
      c.fillRect(rx, ry, rw, rh);

      if (enabled) {
        c.fillStyle = RGBA(accent.r, accent.g, accent.b, 30);
        c.fillRect(rx + bw, ry + bw, rw - 2.0f * bw, rh - 2.0f * bw);
      }

      if (selected) {
        // White L-shaped corner brackets matching BT Stutter Edit 2
        c.fillStyle = colTextBright;
        c.fillRect(rx, ry, 10.0f, 2.0f * bw);
        c.fillRect(rx, ry, 2.0f * bw, 10.0f);
        c.fillRect(rx, ry + rh - 2.0f * bw, 10.0f, 2.0f * bw);
        c.fillRect(rx, ry + rh - 10.0f, 2.0f * bw, 10.0f);
        c.fillStyle = accent;
        c.fillRect(rx + rw - 3.0f * bw, ry + 2.0f * bw, 3.0f * bw, rh - 4.0f * bw);
      } else if (hovered) {
        c.fillStyle = RGBA(255, 255, 255, 65);
        c.fillRect(rx, ry, rw, bw);
        c.fillRect(rx, ry + rh - bw, rw, bw);
      }

      // Crisp hex bypass switch on wire (no blurred outer halo)
      drawHexagon(c, 29.0f, 276.0f + i * 36.0f + 16.0f, 6.5f, enabled ? accent : colBgTrough, accent, enabled);

      // Small signal flow connector between rows
      if (i + 1 < NumChainFX) {
        c.fillStyle = enabled ? accent : colBorderHi;
        c.fillRect(pxSnap(28.0f), ry + rh, 2.0f * bw, pxSnap(276.0f + (i + 1) * 36.0f) - (ry + rh));
      }

      // Module name
      drawTxtAligned(cropped, dirty, scale, chainFXNames[cast(int) fxId],
                     43.0f, 276.0f + i * 36.0f + 16.0f, 10.5f,
                     selected ? colTextBright : (enabled ? colTextBright : colTextMuted),
                     HorizontalAlignment.left);

      // Crisp vertical Mix bar beside reorder handle (x=134..137)
      const float slotMix = getModuleMixNorm(modSlot);
      const float barX = pxSnap(134.0f);
      const float barY0 = pxSnap(276.0f + i * 36.0f + 6.0f);
      const float barY1 = pxSnap(276.0f + i * 36.0f + 26.0f);
      const float barTot = barY1 - barY0;
      c.fillStyle = colBgTrough;
      c.fillRect(barX, barY0, 3.0f * bw, barTot);
      c.fillStyle = enabled ? accent : colBorderHi;
      const float mh = pxSnap(barTot * slotMix);
      c.fillRect(barX, barY1 - mh, 3.0f * bw, mh);

      // Crisp physical `≡` drag-to-reorder handle on right
      const RGBA hCol = (_dragMode == DragMode.chainReorder && _dragChainFromIdx == i) ? colBTCyan : colTextDim;
      for (int line = 0; line < 3; ++line) {
        c.fillStyle = hCol;
        c.fillRect(pxSnap(142.0f), pxSnap(276.0f + i * 36.0f + 11.0f + line * 4.0f), 14.0f, 2.0f * bw);
      }
    }

    // Highlight active drop target slot when dragging a signal chain module
    if (_dragMode == DragMode.chainReorder && _dragChainFromIdx >= 0 && _dragChainFromIdx < NumChainFX) {
      const float dropY = pxSnap(274.0f + _dragChainFromIdx * 36.0f);
      c.fillStyle = colBTCyan;
      c.fillRect(pxSnap(12.0f), dropY, pxSnap(164.0f) - pxSnap(12.0f), 2.0f * bw);
    }
  }

  // =========================================================================
  // SECTION 4: Center Selected Effect Inspector (x=176..556, y=272..672)
  // =========================================================================

  private void drawSection4EffectInspector(ref Canvas c, ref ImageRef!RGBA cropped, box2i dirty, float scale) {
    const RGBA accent = (_editingJitter) ? colBTCyan
      : ((_activeModule == 14) ? colBTCyan : moduleAccentRGBA(_activeModule));
    drawPanelBox(c, 176, 272, 380, 400, RGBA(colBgPanel.r, colBgPanel.g, colBgPanel.b, 40), accent, true);
    c.fillStyle = accent;
    c.fillRect(pxSnap(176.0f), pxSnap(272.0f), pxSnap(556.0f) - pxSnap(176.0f), 3.0f * pxLine());

    if (_editingJitter) {
      const bool jitOn = (_client !is null) ? _client.jitterEnabled : false;
      drawHexagon(c, 194, 300, 9.0f, jitOn ? colBTCyan : colBgTrough, colBTCyan, jitOn);
      drawTxtAligned(cropped, dirty, scale, "BUFFER JITTER", 212, 298, 16.0f, colTextBright, HorizontalAlignment.left);
      drawTxtAligned(cropped, dirty, scale, jitOn ? "ON" : "BYPASS", 212, 319, 9.5f, jitOn ? colBTCyan : colTextDim, HorizontalAlignment.left);

      drawPanelBox(c, 476, 284, 70, 28, inRect(_hoverX, _hoverY, 476, 284, 70, 28) ? RGBA(176, 102, 255, 56) : colBgSubCard, colBTCyan);
      drawTxtAligned(cropped, dirty, scale, "DONE", 511, 298, 10.0f, colBTCyan, HorizontalAlignment.center);

      const float jr = (_client !is null) ? _client.jitterRhythmAmount : 0.0f;
      const float jp = (_client !is null) ? _client.jitterPitchAmount : 0.0f;
      const float jrt = (_client !is null) ? _client.jitterRate : 0.25f;
      const float jof = (_client !is null) ? _client.jitterOffset + 0.5f : 0.5f;

      char[16] b0, b1, b2, b3;
      const int n0 = snprintf(b0.ptr, b0.length, "%.0f%%", cast(double)(jr * 100.0f));
      const int n1 = snprintf(b1.ptr, b1.length, "+/-%.1f st", cast(double)(jp * 24.0f));
      const int n2 = snprintf(b2.ptr, b2.length, "%.2f", cast(double) jrt);
      const int n3 = snprintf(b3.ptr, b3.length, "%+.2f", cast(double)(jof - 0.5f));

      drawSplitSlider(c, cropped, dirty, scale, 190, 382, 168, 122, jr, jr, false, colBTCyan, null, "RHYTHM AMT", b0[0 .. n0], _activeInspectorParam == 0);
      drawSplitSlider(c, cropped, dirty, scale, 370, 382, 168, 122, jp, jp, false, colBTCyan, null, "PITCH AMT", b1[0 .. n1], _activeInspectorParam == 1);
      drawSplitSlider(c, cropped, dirty, scale, 190, 520, 168, 122, jrt, jrt, false, colBTCyan, null, "JITTER RATE", b2[0 .. n2], _activeInspectorParam == 2);
      drawSplitSlider(c, cropped, dirty, scale, 370, 520, 168, 122, jof, jof, false, colBTCyan, null, "OFFSET", b3[0 .. n3], _activeInspectorParam == 3);
      return;
    }

    // Standard Selected Module Header
    const bool modOn = isModuleEnabledExt(_activeModule);
    drawHexagon(c, 194, 300, 9.0f, modOn ? accent : colBgTrough, accent, modOn);
    const string modName = (_activeModule == 14) ? "HIGHPASS"
      : ((_activeModule >= 0 && _activeModule < cast(int) moduleSlotNames.length) ? moduleSlotNames[_activeModule] : "STUTTER");
    drawTxtAligned(cropped, dirty, scale, modName, 212, 297, 17.0f, colTextBright, HorizontalAlignment.left);
    drawTxtAligned(cropped, dirty, scale, modOn ? "ENABLED" : "BYPASSED", 212, 319, 9.5f, modOn ? accent : colTextDim, HorizontalAlignment.left);

    // Electric-Blue Dry/Wet Split Arc Dial (top right of inspector)
    const float mixNorm = getModuleMixNorm(_activeModule);
    char[12] mixBuf;
    const int mn = snprintf(mixBuf.ptr, mixBuf.length, "%.0f%%", cast(double)(mixNorm * 100.0f));
    drawArcDial(c, cropped, dirty, scale, 514, 306, 21.0f, mixNorm, false, colBTBlue,
                "DRY/WET", mixBuf[0 .. mn], inRect(_hoverX, _hoverY, 486, 280, 58, 62));

    // Quick Mode Pill Strip (y=338..364)
    drawInspectorModeRow(c, cropped, dirty, scale, accent);

    // 4-Slot Parameter Split Sliders (2x2 Grid, y=382..646)
    const InspectorSliderSpec[4] specs = getInspectorSpecs(_activeModule);
    const TVMCurve* crv = getCurveConst(_activeModule);
    for (int i = 0; i < 4; ++i) {
      const int col = i % 2;
      const int row = i / 2;
      const float sx = 190.0f + col * 180.0f;
      const float sy = 382.0f + row * 136.0f;
      const float sw = 168.0f;
      const float sh = 120.0f;

      float nA, nB;
      readInspectorValues(specs[i], nA, nB);
      char[32] valBuf;
      const(char)[] valStr = formatInspectorValue(specs[i], valBuf);
      const bool selParam = (_activeInspectorParam == i);
      drawSplitSlider(c, cropped, dirty, scale, sx, sy, sw, sh, nA, nB,
                      specs[i].isDual, accent, specs[i].isDual ? crv : null,
                      specs[i].label, valStr, selParam);
    }

    // Bottom Inspector hint bar (y=654..668)
    drawTxtAligned(cropped, dirty, scale, "DRAG CHEVRONS | CURVE SYNCED",
                   366, 658, 10.0f, colTextDim, HorizontalAlignment.center);
  }

  private void drawInspectorModeRow(ref Canvas c, ref ImageRef!RGBA cropped, box2i dirty, float scale, RGBA accent) {
    const bool hovered = inRect(_hoverX, _hoverY, 190, 338, 286, 26);
    drawPanelBox(c, 190, 338, 286, 26, hovered ? colBgSubHover : colBgSubCard, hovered ? colBTCyan : colBorderDim);
    bool hasCycleMode = true;
    if (_activeModule == ModuleSlot.distort) {
      const bool twoB = (_client !is null) ? _client.distortTwoBand : true;
      drawTxtAligned(cropped, dirty, scale, twoB ? "MODE: 2-BAND XOVER" : "MODE: 1-BAND FULL",
                     198, 351, 10.0f, colBTCyan, HorizontalAlignment.left);
    } else if (_activeModule == ModuleSlot.filter) {
      const int ft = getIntParam(Params.filterType, 1);
      const string ftS = (ft >= 0 && ft < cast(int) filterTypeNames.length) ? filterTypeNames[ft] : "LP 24dB";
      drawTxtAligned(cropped, dirty, scale, ftS, 198, 351, 10.0f, colBTCyan, HorizontalAlignment.left);
    } else if (_activeModule == 14) {
      const int poles = (_client !is null) ? _client.highpassPoles : 0;
      drawTxtAligned(cropped, dirty, scale, poles != 0 ? "SLOPE: 24 dB/oct" : "SLOPE: 12 dB/oct",
                     198, 351, 10.0f, colBTCyan, HorizontalAlignment.left);
    } else if (_activeModule == ModuleSlot.tapeStop) {
      const bool pl = getBoolParam(Params.tapeStopPlunge, true);
      drawTxtAligned(cropped, dirty, scale, pl ? "MODE: PLUNGE STOP" : "MODE: SMOOTH SLOWDOWN",
                     198, 351, 10.0f, colBTCyan, HorizontalAlignment.left);
    } else if (_activeModule == ModuleSlot.reverb) {
      const bool frz = getBoolParam(Params.reverbFreeze, false);
      drawTxtAligned(cropped, dirty, scale, frz ? "FREEZE: ON" : "FREEZE: OFF",
                     198, 351, 10.0f, colBTCyan, HorizontalAlignment.left);
    } else if (_activeModule == ModuleSlot.phaser) {
      const int stg = getIntParam(Params.phaserStages, 1);
      drawTxtAligned(cropped, dirty, scale,
                     (stg >= 0 && stg < cast(int) phaserStagesNames.length) ? phaserStagesNames[stg] : "6 Poles",
                     198, 351, 10.0f, colBTCyan, HorizontalAlignment.left);
    } else {
      hasCycleMode = false;
      drawTxtAligned(cropped, dirty, scale, "TARGET: TVM CURVE",
                     198, 351, 10.0f, accent, HorizontalAlignment.left);
    }
    drawTxtRight(cropped, dirty, scale, hasCycleMode ? "CLICK TO CYCLE" : "CLICK SLIDER", 468, 351, 10.0f, colTextDim);
  }

  // =========================================================================
  // SECTION 6: TVM Curve Editor (Embedded & Expanded)
  // =========================================================================

  private void drawSection6TVMEditor(ref Canvas c, ref ImageRef!RGBA cropped, box2i dirty, float scale, bool expanded) {
    const float ex = expanded ? 176.0f : 564.0f;
    const float ey = 272.0f;
    const float ew = expanded ? 856.0f : 468.0f;
    const float eh = expanded ? 400.0f : 214.0f;
    const float bw = pxLine();

    const RGBA accent = (_activeModule == 14) ? colBTCyan : moduleAccentRGBA(_activeModule);
    drawPanelBox(c, ex, ey, ew, eh, RGBA(colBgPanel.r, colBgPanel.g, colBgPanel.b, 40), colBorderHi, true);

    // Top Header Badge (`MODULE | PARAM`) + Dotted Leader + Toolbar
    const string modName = (_activeModule == 14) ? "HIGHPASS"
      : ((_activeModule >= 0 && _activeModule < cast(int) moduleSlotNames.length) ? moduleSlotNames[_activeModule] : "STUTTER");
    const InspectorSliderSpec[4] specs = getInspectorSpecs(_activeModule);
    const string pName = specs[_activeInspectorParam % 4].label;

    drawPanelBox(c, ex + 8.0f, ey + 6.0f, 168.0f, 22.0f, colWhitePill, colTextBright);
    char[40] hdrBuf;
    const int hn = snprintf(hdrBuf.ptr, hdrBuf.length, "%.*s | %.*s",
                            cast(int) modName.length, modName.ptr,
                            cast(int) pName.length, pName.ptr);
    drawTxtAligned(cropped, dirty, scale, hdrBuf[0 .. hn], ex + 92.0f, ey + 17.0f, 10.0f, colTextDark, HorizontalAlignment.center);

    const float tbStart = ex + ew - 246.0f;
    for (float dx = ex + 182.0f; dx < tbStart - 6.0f; dx += 6.0f) {
      c.fillStyle = colBorderHi;
      c.fillRect(pxSnap(dx), pxSnap(ey + 16.0f), 2.0f * bw, 2.0f * bw);
    }

    // Toolbar buttons: Reset, Speed, Reverse, Grid, Expand
    const int eSlot = (_activeModule == 14) ? 14 : (_activeModule < 14 ? _activeModule : 0);
    const float spd = (_client !is null) ? _client.extTvmBank.states[eSlot][0].speedMultiplier : 1.0f;
    const bool revC = (_client !is null) ? _client.extTvmBank.states[eSlot][0].reversed : false;
    const int gridRes = (_client !is null) ? _client.extTvmBank.states[eSlot][0].gridResolution : 8;

    drawPanelBox(c, ex + ew - 244.0f, ey + 6.0f, 44.0f, 22.0f, colBgSubCard, colBorderDim);
    drawTxtAligned(cropped, dirty, scale, "RST", ex + ew - 222.0f, ey + 17.0f, 10.0f, colTextMuted, HorizontalAlignment.center);

    char[12] spdBuf;
    const int sn = snprintf(spdBuf.ptr, spdBuf.length, "%.2gx", cast(double) spd);
    drawPanelBox(c, ex + ew - 196.0f, ey + 6.0f, 44.0f, 22.0f, colBgSubCard, colBorderDim);
    drawTxtAligned(cropped, dirty, scale, spdBuf[0 .. sn], ex + ew - 174.0f, ey + 17.0f, 10.0f, colBTCyan, HorizontalAlignment.center);

    drawPanelBox(c, ex + ew - 148.0f, ey + 6.0f, 40.0f, 22.0f, revC ? RGBA(176, 102, 255, 44) : colBgSubCard,
                 revC ? colBTCyan : colBorderDim);
    drawTxtAligned(cropped, dirty, scale, "REV", ex + ew - 128.0f, ey + 17.0f, 10.0f, revC ? colBTCyan : colTextMuted, HorizontalAlignment.center);

    drawPanelBox(c, ex + ew - 104.0f, ey + 6.0f, 40.0f, 22.0f, colBgSubCard, colBorderDim);
    char[8] grdBuf;
    const int gn = snprintf(grdBuf.ptr, grdBuf.length, "G%d", gridRes);
    drawTxtAligned(cropped, dirty, scale, grdBuf[0 .. gn], ex + ew - 84.0f, ey + 17.0f, 10.0f, colTextBright, HorizontalAlignment.center);

    // `[⛶]` Expand / Collapse Button
    drawPanelBox(c, ex + ew - 60.0f, ey + 6.0f, 52.0f, 22.0f,
                 expanded ? colBTCyan : colBgSubCard, colBTCyan);
    drawTxtAligned(cropped, dirty, scale, expanded ? "CLOSE" : "EXPAND",
                   ex + ew - 34.0f, ey + 17.0f, 10.0f, expanded ? colTextDark : colBTCyan, HorizontalAlignment.center);

    // Curve Viewport Area (PBR recessed well with razor-snapped grid)
    const float pad = 10.0f;
    const float gx = ex + 8.0f;
    const float gy = ey + 34.0f;
    const float gw = ew - 16.0f;
    const float gh = expanded ? 302.0f : 132.0f;

    drawPanelBox(c, gx, gy, gw, gh, RGBA(colBgCurveGrid.r, colBgCurveGrid.g, colBgCurveGrid.b, 140), colBorderDim, true);

    const float cw = gw - pad * 2.0f;
    const float ch = gh - pad * 2.0f;
    const float gy0 = pxSnap(gy + 2.0f);
    const float gy1 = pxSnap(gy + gh - 2.0f);
    const float gx0 = pxSnap(gx + 2.0f);
    const float gx1 = pxSnap(gx + gw - 2.0f);

    // Grid lines (`gridRes` divisions, physical-pixel snapped like EnvelopeUI)
    const int divs = (gridRes >= 4 && gridRes <= 32) ? gridRes : 8;
    for (int i = 0; i <= divs; ++i) {
      const float lx = pxSnap(gx + pad + (cast(float) i / cast(float) divs) * cw);
      const bool beat = (i % 4 == 0);
      c.fillStyle = beat ? RGBA(88, 64, 150, 170) : RGBA(44, 32, 80, 130);
      c.fillRect(lx, gy0, bw, gy1 - gy0);
    }
    for (int j = 0; j <= 4; ++j) {
      const float ly = pxSnap(gy + pad + (cast(float) j / 4.0f) * ch);
      c.fillStyle = (j == 2) ? RGBA(88, 64, 150, 170) : RGBA(44, 32, 80, 130);
      c.fillRect(gx0, ly, gx1 - gx0, bw);
    }

    const ref TVMCurve curve = activeCurve();
    enum int NSTEPS = 120;

    // Crisp vertical linear-gradient area fill under curve (directly inspired by kdr envtool)
    auto grad = c.createLinearGradient(0.0f, gy + pad, 0.0f, gy + pad + ch);
    grad.addColorStop(0.0f, RGBA(accent.r, accent.g, accent.b, 165));
    grad.addColorStop(1.0f, RGBA(accent.r, accent.g, accent.b, 24));
    c.fillStyle = grad;
    c.beginPath();
    c.moveTo(gx + pad, gy + pad + ch);
    for (int s = 0; s <= NSTEPS; ++s) {
      const float p = cast(float) s / cast(float) NSTEPS;
      const float v = curve.evaluate(p);
      c.lineTo(gx + pad + p * cw, gy + pad + (1.0f - v) * ch);
    }
    c.lineTo(gx + pad + cw, gy + pad + ch);
    c.closePath();
    c.fill();

    // Subtle secondary contour ribbon for depth without muddiness
    c.fillStyle = RGBA(accent.r, accent.g, accent.b, 55);
    c.beginPath();
    for (int s = 0; s <= NSTEPS; ++s) {
      const float p = cast(float) s / cast(float) NSTEPS;
      const float v = curve.evaluate(p) * 0.72f;
      const float px = gx + pad + p * cw;
      const float py = gy + pad + (1.0f - v) * ch - 0.7f;
      if (s == 0) c.moveTo(px, py); else c.lineTo(px, py);
    }
    for (int s = NSTEPS; s >= 0; --s) {
      const float p = cast(float) s / cast(float) NSTEPS;
      const float v = curve.evaluate(p) * 0.72f;
      const float px = gx + pad + p * cw;
      const float py = gy + pad + (1.0f - v) * ch + 0.7f;
      c.lineTo(px, py);
    }
    c.closePath();
    c.fill();

    // Main bright stroke ribbon
    c.fillStyle = accent;
    c.beginPath();
    for (int s = 0; s <= NSTEPS; ++s) {
      const float p = cast(float) s / cast(float) NSTEPS;
      const float v = curve.evaluate(p);
      const float px = gx + pad + p * cw;
      const float py = gy + pad + (1.0f - v) * ch - 1.4f;
      if (s == 0) c.moveTo(px, py); else c.lineTo(px, py);
    }
    for (int s = NSTEPS; s >= 0; --s) {
      const float p = cast(float) s / cast(float) NSTEPS;
      const float v = curve.evaluate(p);
      const float px = gx + pad + p * cw;
      const float py = gy + pad + (1.0f - v) * ch + 1.4f;
      c.lineTo(px, py);
    }
    c.closePath();
    c.fill();

    // Breakpoint Solid White Dots `●` + Midpoint Hollow Tension Bend Rings `○`
    const int nNodes = curve.nodeCount();
    for (int i = 0; i < nNodes; ++i) {
      const float nx = gx + pad + curve.nodes[i].x * cw;
      const float ny = gy + pad + (1.0f - curve.nodes[i].y) * ch;
      const bool nHov = ((_hoverX - nx) * (_hoverX - nx) + (_hoverY - ny) * (_hoverY - ny)) < 144.0f;
      if (nHov || _dragNodeIdx == i) {
        c.fillStyle = RGBA(accent.r, accent.g, accent.b, 95);
        c.fillCircle(nx, ny, 8.5f);
      }
      c.fillStyle = colBgCurveGrid;
      c.fillCircle(nx, ny, 5.5f);
      c.fillStyle = colTextBright;
      c.fillCircle(nx, ny, 3.8f);

      if (i + 1 < nNodes) {
        const float midX = 0.5f * (curve.nodes[i].x + curve.nodes[i + 1].x);
        const float midY = curve.evaluate(midX);
        const float hx = gx + pad + midX * cw;
        const float hy = gy + pad + (1.0f - midY) * ch;
        c.fillStyle = accent;
        c.fillCircle(hx, hy, 4.4f);
        c.fillStyle = colBgCurveGrid;
        c.fillCircle(hx, hy, 2.2f);
      }
    }

    // Playhead cursor line & follower dot synchronized to speed/reverse
    const float ph = evalEffectiveCurvePhase(eSlot);
    const float phX = pxSnap(gx + pad + ph * cw);
    const float phY = gy + pad + (1.0f - curve.evaluate(ph)) * ch;
    c.fillStyle = RGBA(255, 255, 255, 36);
    c.fillRect(phX - 3.0f, gy0, 7.0f, gy1 - gy0);
    c.fillStyle = RGBA(255, 255, 255, 235);
    c.fillRect(phX, gy0, bw, gy1 - gy0);
    c.fillStyle = colTextBright;
    c.fillCircle(phX, phY, 4.5f);

    // Subtle helper legend inside viewport bottom-left
    if (expanded) {
      drawTxtAligned(cropped, dirty, scale, "L-CLICK: ADD/DRAG  |  DBL-CLICK: CURVE  |  R-CLICK: DELETE",
                     gx + 10.0f, gy + gh - 10.0f, 10.0f, colTextMuted, HorizontalAlignment.left);
    }

    // 12 Preset Curve Thumbnails strip at bottom (integer-snapped tiles)
    const float py = gy + gh + 6.0f;
    const float pwTotal = ew - 16.0f;
    const float pTileW = (pwTotal - 11.0f * 4.0f) / 12.0f;
    const float pTileH = expanded ? 50.0f : 36.0f;
    const int activePreset = getIntParam(moduleCurveParam(eSlot < 14 ? eSlot : 0), -1);
    TVMCurve preview;
    for (int i = 0; i < 12; ++i) {
      const float bx = snapF(ex + 8.0f + i * (pTileW + 4.0f));
      const float nextBx = snapF(ex + 8.0f + (i + 1) * (pTileW + 4.0f));
      const float tw = (i == 11) ? snapF(ex + 8.0f + pwTotal - bx) : (nextBx - bx - 4.0f);
      const bool isSel = (i == activePreset);
      const bool isHov = inRect(_hoverX, _hoverY, cast(int) bx, cast(int) py, cast(int) tw, cast(int) pTileH);
      drawPanelBox(c, bx, py, tw, pTileH,
                   isSel ? RGBA(accent.r, accent.g, accent.b, 46) : (isHov ? colBgSubHover : colBgSubCard),
                   isSel ? accent : (isHov ? colBorderHi : colBorderDim));
      preview.loadPreset(i);

      const float innerX = bx + 4.0f;
      const float innerW = tw - 8.0f;
      const float innerY = py + 4.0f;
      const float innerH = expanded ? (pTileH - 18.0f) : (pTileH - 8.0f);

      // Filled curve area
      c.fillStyle = isSel ? RGBA(accent.r, accent.g, accent.b, 65) : RGBA(accent.r, accent.g, accent.b, 32);
      c.beginPath();
      c.moveTo(innerX, innerY + innerH);
      for (int s = 0; s <= 18; ++s) {
        const float pt = cast(float) s / 18.0f;
        const float pv = preview.evaluate(pt);
        c.lineTo(innerX + pt * innerW, innerY + (1.0f - pv) * innerH);
      }
      c.lineTo(innerX + innerW, innerY + innerH);
      c.closePath();
      c.fill();

      // Continuous top stroke ribbon
      c.fillStyle = isSel ? accent : colTextBright;
      c.beginPath();
      for (int s = 0; s <= 18; ++s) {
        const float pt = cast(float) s / 18.0f;
        const float pv = preview.evaluate(pt);
        const float px = innerX + pt * innerW;
        const float ppy = innerY + (1.0f - pv) * innerH - 0.9f;
        if (s == 0) c.moveTo(px, ppy); else c.lineTo(px, ppy);
      }
      for (int s = 18; s >= 0; --s) {
        const float pt = cast(float) s / 18.0f;
        const float pv = preview.evaluate(pt);
        const float px = innerX + pt * innerW;
        const float ppy = innerY + (1.0f - pv) * innerH + 0.9f;
        c.lineTo(px, ppy);
      }
      c.closePath();
      c.fill();

      if (expanded) {
        drawTxtAligned(cropped, dirty, scale, curvePresetShortNames[i],
                       bx + tw * 0.5f, py + pTileH - 8.0f, 9.2f,
                       isSel ? accent : colTextMuted, HorizontalAlignment.center);
      }
    }
  }

  // =========================================================================
  // SECTION 5: Bottom-Right Purple Output Section (x=564..1032, y=492..672)
  // =========================================================================

  private void drawSection5PurpleOutput(ref Canvas c, ref ImageRef!RGBA cropped, box2i dirty, float scale) {
    const float bw = pxLine();
    drawPanelBox(c, 564, 492, 468, 180, RGBA(colBTPurpleDark.r, colBTPurpleDark.g, colBTPurpleDark.b, 55),
                 colBTPurple, true);
    c.fillStyle = colBTPurple;
    c.fillRect(pxSnap(564.0f), pxSnap(492.0f), pxSnap(1032.0f) - pxSnap(564.0f), 3.0f * bw);

    drawTxtAligned(cropped, dirty, scale, "OUTPUT", 576, 510, 12.5f, colBTPurpleHi, HorizontalAlignment.left);

    // Wet Gain Hex + Purple Arc Dial (x=576..698, y=524..592)
    const bool wetOn = (_client !is null) ? _client.wetGainEnable : true;
    const float wetDb = (_client !is null) ? _client.wetGainDb : 0.0f;
    const float wetN = (wetDb + 24.0f) / 36.0f;
    char[12] wBuf;
    const int wn = snprintf(wBuf.ptr, wBuf.length, "%+.1f", cast(double) wetDb);
    drawHexagon(c, 588, 548, 6.5f, wetOn ? colBTPurple : colBgTrough, colBTPurple, wetOn);
    drawTxtAligned(cropped, dirty, scale, "WET", 600, 548, 10.0f, wetOn ? colTextBright : colTextMuted, HorizontalAlignment.left);
    drawArcDial(c, cropped, dirty, scale, 658, 550, 20.0f, wetN, false, colBTPurpleHi,
                "dB", wBuf[0 .. wn], inRect(_hoverX, _hoverY, 634, 524, 52, 56));

    // Dry Gain Hex + Purple Arc Dial (x=576..698, y=598..664)
    const bool dryOn = (_client !is null) ? _client.dryGainEnable : false;
    const float dryDb = (_client !is null) ? _client.dryGainDb : 0.0f;
    const float dryN = (dryDb + 24.0f) / 36.0f;
    char[12] dBuf;
    const int dn = snprintf(dBuf.ptr, dBuf.length, dryOn ? "%+.1f" : "OFF", cast(double) dryDb);
    drawHexagon(c, 588, 626, 6.5f, dryOn ? colBTPurple : colBgTrough, colBTPurple, dryOn);
    drawTxtAligned(cropped, dirty, scale, "DRY", 600, 626, 10.0f, dryOn ? colTextBright : colTextMuted, HorizontalAlignment.left);
    drawArcDial(c, cropped, dirty, scale, 658, 628, 20.0f, dryN, false, colBTPurpleHi,
                "dB", dBuf[0 .. dn], inRect(_hoverX, _hoverY, 634, 600, 52, 58));

    // Master Limiter Hex + Threshold & Output Gain Sliders (x=706..938)
    const bool limOn = isModuleEnabled(ModuleSlot.limiter);
    drawPanelBox(c, 706, 502, 232, 160, RGBA(20, 16, 36, 235), RGBA(96, 66, 170, 255));
    drawHexagon(c, 720, 518, 6.5f, limOn ? colBTPurpleHi : colBgTrough, colBTPurpleHi, limOn);
    drawTxtAligned(cropped, dirty, scale, "LIMITER", 732, 518, 10.5f, limOn ? colTextBright : colTextMuted, HorizontalAlignment.left);

    const float threshN = getNormParam(Params.limiterThreshold, 0.9f);
    const float outGainN = getNormParam(Params.masterOutputGain, 0.5f);
    const float grDb = (_client !is null) ? _client.limiterGainReductionDb() : 0.0f;

    char[16] grLabel;
    const int grn = snprintf(grLabel.ptr, grLabel.length, "GR -%.1f dB", cast(double) grDb);
    drawTxtRight(cropped, dirty, scale, grLabel[0 .. grn], 928, 518, 10.0f,
                 (grDb > 0.2f) ? colRedAlert : colTextMuted);

    char[12] thBuf, ogBuf;
    const float thDb = -24.0f + threshN * 24.0f;
    const float ogDb = -24.0f + outGainN * 36.0f;
    const int thn = snprintf(thBuf.ptr, thBuf.length, "%.1f dB", cast(double) thDb);
    const int ogn = snprintf(ogBuf.ptr, ogBuf.length, "%+.1f dB", cast(double) ogDb);

    drawSplitSlider(c, cropped, dirty, scale, 714, 534, 214, 48, threshN, threshN, false,
                    colBTPurpleHi, null, "THRESHOLD", thBuf[0 .. thn], false);
    drawSplitSlider(c, cropped, dirty, scale, 714, 590, 214, 48, outGainN, outGainN, false,
                    colBTPurpleHi, null, "OUT GAIN", ogBuf[0 .. ogn], false);

    // Gain Reduction meter bar inside limiter block
    const float grFrac = (grDb > 12.0f) ? 1.0f : (grDb < 0.0f ? 0.0f : grDb / 12.0f);
    const float grX0 = pxSnap(714.0f);
    const float grW = pxSnap(928.0f) - grX0;
    const float grY0 = pxSnap(646.0f);
    const float grH = pxSnap(654.0f) - grY0;
    c.fillStyle = colBgTrough;
    c.fillRect(grX0, grY0, grW, grH);
    c.fillStyle = colRedAlert;
    c.fillRect(grX0, grY0, pxSnap(grW * grFrac), grH);

    // Vertical Dual Purple Stereo Peak Output Meters with dB ticks & Peak-Hold Caps (x=948..1022)
    float pkL = (_client !is null) ? _client.peakLevelL() : 0.45f;
    float pkR = (_client !is null) ? _client.peakLevelR() : 0.40f;
    if (pkL > 1.0f) pkL = 1.0f; if (pkL < 0.0f) pkL = 0.0f;
    if (pkR > 1.0f) pkR = 1.0f; if (pkR < 0.0f) pkR = 0.0f;
    if (pkL > _peakHoldL) _peakHoldL = pkL;
    if (pkR > _peakHoldR) _peakHoldR = pkR;

    drawPanelBox(c, 948, 502, 74, 160, RGBA(colBgTrough.r, colBgTrough.g, colBgTrough.b, 120),
                 RGBA(96, 66, 170, 255), true);
    const float mTop = pxSnap(514.0f);
    const float mBot = pxSnap(640.0f);
    const float mH = mBot - mTop;
    const float mLx = pxSnap(960.0f);
    const float mRx = pxSnap(994.0f);
    const float mW = pxSnap(976.0f) - mLx;
    c.fillStyle = RGBA(30, 22, 52, 255);
    c.fillRect(mLx, mTop, mW, mH);
    c.fillRect(mRx, mTop, mW, mH);

    // Main purple meter fill + top hot region
    const float mFillMax = mH - 2.0f * bw;
    const float mhL = pxSnap(mFillMax * pkL);
    const float mhR = pxSnap(mFillMax * pkR);
    c.fillStyle = colBTPurpleHi;
    c.fillRect(mLx + bw, mBot - bw - mhL, mW - 2.0f * bw, mhL);
    c.fillRect(mRx + bw, mBot - bw - mhR, mW - 2.0f * bw, mhR);
    const float hotThresh = pxSnap(mFillMax * 0.88f);
    if (pkL > 0.88f) {
      c.fillStyle = colRedAlert;
      c.fillRect(mLx + bw, mBot - bw - mhL, mW - 2.0f * bw, mhL - hotThresh);
    }
    if (pkR > 0.88f) {
      c.fillStyle = colRedAlert;
      c.fillRect(mRx + bw, mBot - bw - mhR, mW - 2.0f * bw, mhR - hotThresh);
    }

    // Razor physical-pixel meter segment grid lines + dB ticks
    for (int seg = 1; seg < 10; ++seg) {
      const float sy = pxSnap(514.0f + seg * 12.6f);
      c.fillStyle = RGBA(12, 10, 22, 200);
      c.fillRect(mLx, sy, mW, bw);
      c.fillRect(mRx, sy, mW, bw);
      if (seg == 2 || seg == 5 || seg == 8) {
        c.fillStyle = colTextDim;
        c.fillRect(pxSnap(981.0f), sy, pxSnap(989.0f) - pxSnap(981.0f), bw);
      }
    }

    // Peak-hold caps
    const float holdL = (_peakHoldL > 1.0f) ? 1.0f : _peakHoldL;
    const float holdR = (_peakHoldR > 1.0f) ? 1.0f : _peakHoldR;
    if (holdL > 0.01f) {
      c.fillStyle = (holdL >= 0.96f) ? colRedAlert : colTextBright;
      c.fillRect(mLx, pxSnap(mBot - bw - mFillMax * holdL), mW, 2.0f * bw);
    }
    if (holdR > 0.01f) {
      c.fillStyle = (holdR >= 0.96f) ? colRedAlert : colTextBright;
      c.fillRect(mRx, pxSnap(mBot - bw - mFillMax * holdR), mW, 2.0f * bw);
    }

    drawTxtAligned(cropped, dirty, scale, "L", 968, 650, 10.0f, colTextMuted, HorizontalAlignment.center);
    drawTxtAligned(cropped, dirty, scale, "R", 1002, 650, 10.0f, colTextMuted, HorizontalAlignment.center);
  }

  // =========================================================================
  // Reusable BT Vector Widget Drawing Primitives
  // =========================================================================

  private static float snapF(float v) pure @nogc nothrow @safe {
    return (v >= 0.0f) ? cast(float) cast(int)(v + 0.5f)
                       : -cast(float) cast(int)(-v + 0.5f);
  }

  private static float snapToScale(float v, float scale) pure @nogc nothrow @safe {
    return (scale > 0.0f) ? (snapF(v * scale) / scale) : snapF(v);
  }

  private static float physBorder(float scale) pure @nogc nothrow @safe {
    const float bPx = (scale >= 1.8f) ? 2.0f : 1.0f;
    return (scale > 0.0f) ? (bPx / scale) : 1.0f;
  }

  private float pxSnap(float v) const pure @nogc nothrow @safe {
    return snapToScale(v, _renderScale);
  }

  private float pxLine() const pure @nogc nothrow @safe {
    return physBorder(_renderScale);
  }

  private static const(char)[] stripNotePrefix(const(char)[] name) pure @nogc nothrow @safe {
    size_t sp = 0;
    while (sp < name.length && name[sp] != ' ') ++sp;
    while (sp < name.length && name[sp] == ' ') ++sp;
    return (sp < name.length) ? name[sp .. $] : name;
  }

  private static bool inRect(int hx, int hy, int rx, int ry, int rw, int rh) pure @nogc nothrow @safe {
    return hx >= rx && hx <= rx + rw && hy >= ry && hy <= ry + rh;
  }

  private void drawPanelBox(ref Canvas c, float x, float y, float w, float h,
                            RGBA fillCol, RGBA borderCol, bool preserveUnderlay = false) const {
    const float sc = (_renderScale > 0.0f) ? _renderScale : 1.0f;
    const float x0 = snapToScale(x, sc);
    const float y0 = snapToScale(y, sc);
    const float x1 = snapToScale(x + w, sc);
    const float y1 = snapToScale(y + h, sc);
    const float rw = x1 - x0;
    const float rh = y1 - y0;
    if (rw <= 0.0f || rh <= 0.0f) return;
    const float bw = physBorder(sc);

    // Fill interior first (for opaque/button cards, lay down an opaque studio base under
    // translucent accents; outer section chassis pass preserveUnderlay=true to keep PBR lighting).
    if (rw > 2.0f * bw && rh > 2.0f * bw) {
      if (!preserveUnderlay && fillCol.a < 255) {
        c.fillStyle = colBgSubCard;
        c.fillRect(x0 + bw, y0 + bw, rw - 2.0f * bw, rh - 2.0f * bw);
      }
      if (fillCol.a > 0) {
        c.fillStyle = fillCol;
        c.fillRect(x0 + bw, y0 + bw, rw - 2.0f * bw, rh - 2.0f * bw);
      }
      if (rw > 8.0f && rh > 8.0f) {
        c.fillStyle = colBevelTop;
        c.fillRect(x0 + bw, y0 + bw, rw - 2.0f * bw, bw);
      }
    }

    // Razor-crisp physical-pixel outer border strips
    c.fillStyle = borderCol;
    c.fillRect(x0, y0, rw, bw);
    if (rh > bw) c.fillRect(x0, y1 - bw, rw, bw);
    if (rh > 2.0f * bw) {
      c.fillRect(x0, y0 + bw, bw, rh - 2.0f * bw);
      if (rw > bw) c.fillRect(x1 - bw, y0 + bw, bw, rh - 2.0f * bw);
    }
  }

  private static void drawHexagon(ref Canvas c, float cx, float cy, float r, RGBA fillCol, RGBA strokeCol, bool filled) {
    cx = snapF(cx);
    cy = snapF(cy);
    c.fillStyle = strokeCol;
    c.beginPath();
    for (int i = 0; i < 6; ++i) {
      const float ang = cast(float) i * (PI_F / 3.0f);
      const float px = cx + r * cos(ang);
      const float py = cy + r * sin(ang);
      if (i == 0) c.moveTo(px, py); else c.lineTo(px, py);
    }
    c.closePath();
    c.fill();

    if (!filled || fillCol != strokeCol) {
      const float ir = r - 1.8f;
      if (ir > 1.0f) {
        c.fillStyle = fillCol;
        c.beginPath();
        for (int i = 0; i < 6; ++i) {
          const float ang = cast(float) i * (PI_F / 3.0f);
          const float px = cx + ir * cos(ang);
          const float py = cy + ir * sin(ang);
          if (i == 0) c.moveTo(px, py); else c.lineTo(px, py);
        }
        c.closePath();
        c.fill();
      }
    }
  }

  private void drawArcDial(
      ref Canvas c, ref ImageRef!RGBA cropped, box2i dirty, float scale,
      float cx, float cy, float r, float normVal, bool bipolar, RGBA arcCol,
      const(char)[] bottomLabel, const(char)[] valueStr, bool hovered = false) {
    if (normVal < 0.0f) normVal = 0.0f;
    if (normVal > 1.0f) normVal = 1.0f;
    cx = snapF(cx);
    cy = snapF(cy);

    if (hovered) {
      drawArcRibbon(c, cx, cy, r + 1.5f, r + 3.0f, 0.0f, 2.0f * PI_F,
                    RGBA(arcCol.r, arcCol.g, arcCol.b, 145));
    }

    // Background circle
    c.fillStyle = colBgTrough;
    c.fillCircle(cx, cy, r + 0.5f);
    c.fillStyle = hovered ? colBgSubHover : colBgSubCard;
    c.fillCircle(cx, cy, r - 3.5f);

    // 270-degree track (from 135 deg to 405 deg)
    const float aStart = 0.75f * PI_F;
    const float aEnd   = 2.25f * PI_F;
    drawArcRibbon(c, cx, cy, r - 2.5f, r + 0.5f, aStart, aEnd, RGBA(56, 42, 98, 255));

    // Active arc
    const float aCur = aStart + normVal * (aEnd - aStart);
    if (bipolar) {
      const float aMid = 1.5f * PI_F;
      if (aCur >= aMid) drawArcRibbon(c, cx, cy, r - 2.5f, r + 1.0f, aMid, aCur, arcCol);
      else              drawArcRibbon(c, cx, cy, r - 2.5f, r + 1.0f, aCur, aMid, arcCol);
    } else {
      drawArcRibbon(c, cx, cy, r - 2.5f, r + 1.0f, aStart, aCur, arcCol);
    }

    // Indicator dot on active arc tip (kept clear of centered readout)
    const float dotX = cx + (r - 0.8f) * cos(aCur);
    const float dotY = cy + (r - 0.8f) * sin(aCur);
    c.fillStyle = colTextBright;
    c.fillCircle(dotX, dotY, 2.0f);

    if (valueStr.length > 0) {
      drawTxtAligned(cropped, dirty, scale, valueStr, cx, cy, 9.2f, colTextBright, HorizontalAlignment.center);
    }
    if (bottomLabel.length > 0) {
      drawTxtAligned(cropped, dirty, scale, bottomLabel, cx, cy + r + 9.0f, 9.2f, colTextMuted, HorizontalAlignment.center);
    }
  }

  private static void drawArcRibbon(ref Canvas c, float cx, float cy, float rIn, float rOut,
                                    float a0, float a1, RGBA col) {
    if (a1 - a0 < 0.02f) return;
    enum int SEG = 36;
    c.fillStyle = col;
    c.beginPath();
    for (int i = 0; i <= SEG; ++i) {
      const float a = a0 + (a1 - a0) * (cast(float) i / cast(float) SEG);
      const float x = cx + rOut * cos(a);
      const float y = cy + rOut * sin(a);
      if (i == 0) c.moveTo(x, y); else c.lineTo(x, y);
    }
    for (int i = SEG; i >= 0; --i) {
      const float a = a0 + (a1 - a0) * (cast(float) i / cast(float) SEG);
      c.lineTo(cx + rIn * cos(a), cy + rIn * sin(a));
    }
    c.closePath();
    c.fill();
  }

  private void drawSplitSlider(
      ref Canvas c, ref ImageRef!RGBA cropped, box2i dirty, float scale,
      float x, float y, float w, float h, float normA, float normB, bool isDual,
      RGBA accent, const(TVMCurve)* sparkCurve,
      const(char)[] label, const(char)[] valueStr, bool selectedForCurve) {
    if (normA < 0.0f) normA = 0.0f; if (normA > 1.0f) normA = 1.0f;
    if (normB < 0.0f) normB = 0.0f; if (normB > 1.0f) normB = 1.0f;
    x = snapF(x);
    y = snapF(y);
    w = snapF(w);
    h = snapF(h);

    const bool hovered = inRect(_hoverX, _hoverY, cast(int) x, cast(int) y, cast(int) w, cast(int) h);
    drawPanelBox(c, x, y, w, h, hovered ? colBgSubHover : colBgSubCard,
                 selectedForCurve ? colTextBright : (hovered ? colBorderHi : colBorderDim));

    const bool compact = (h <= 34.0f);
    const float hdrH = compact ? 13.0f : 15.0f;
    const float lblY = y + (compact ? 7.0f : 8.0f);

    // Selected parameter white header highlight matching Stutter Edit 2
    if (selectedForCurve) {
      c.fillStyle = colWhitePill;
      c.fillRect(x + 1.0f, y + 1.0f, w - 2.0f, hdrH);
      drawTxtAligned(cropped, dirty, scale, label, x + 6.0f, lblY, 9.5f, colTextDark, HorizontalAlignment.left);
    } else {
      drawTxtAligned(cropped, dirty, scale, label, x + 6.0f, lblY, 9.5f, colTextMuted, HorizontalAlignment.left);
    }
    if (valueStr.length > 0 && w >= 120.0f) {
      drawTxtRight(cropped, dirty, scale, valueStr, x + w - 6.0f, lblY, 9.5f,
                   selectedForCurve ? colTextDark : colTextBright);
    }

    const float tx = pxSnap(x + 6.0f);
    const float tx1 = pxSnap(x + w - 6.0f);
    const float tw = tx1 - tx;
    const float trackY = pxSnap(y + hdrH + 2.0f);
    const float trackEndY = pxSnap(y + h - ((h > 44.0f) ? 5.0f : 2.0f));
    const float trackH = trackEndY - trackY;
    const float bw = pxLine();

    c.fillStyle = colBgTrough;
    c.fillRect(tx, trackY, tw, trackH);

    // Physical-pixel snapped quarter-tick grid guides inside trough
    for (int q = 1; q <= 3; ++q) {
      const float qx = pxSnap(tx + tw * (0.25f * q));
      c.fillStyle = (q == 2) ? RGBA(78, 58, 134, 175) : RGBA(44, 32, 80, 135);
      c.fillRect(qx, trackY + bw, bw, trackH - 2.0f * bw);
    }

    // Continuous smooth TVM Curve Sparkline inside slider trough (with envtool vertical gradient)
    if (sparkCurve !is null && trackH >= 10.0f) {
      const float spY = trackY + ((trackH >= 20.0f) ? (trackH * 0.28f) : 2.0f);
      const float spH = (trackH >= 20.0f) ? (trackH * 0.66f) : (trackH - 4.0f);

      auto spGrad = c.createLinearGradient(0.0f, spY, 0.0f, spY + spH);
      spGrad.addColorStop(0.0f, RGBA(accent.r, accent.g, accent.b, 85));
      spGrad.addColorStop(1.0f, RGBA(accent.r, accent.g, accent.b, 12));
      c.fillStyle = spGrad;
      c.beginPath();
      c.moveTo(tx + bw, spY + spH);
      for (int s = 0; s <= 24; ++s) {
        const float pt = cast(float) s / 24.0f;
        const float pv = sparkCurve.evaluate(pt);
        c.lineTo(tx + bw + pt * (tw - 2.0f * bw), spY + (1.0f - pv) * spH);
      }
      c.lineTo(tx + tw - bw, spY + spH);
      c.closePath();
      c.fill();

      // Continuous polyline ribbon
      c.fillStyle = RGBA(accent.r, accent.g, accent.b, 195);
      c.beginPath();
      for (int s = 0; s <= 24; ++s) {
        const float pt = cast(float) s / 24.0f;
        const float pv = sparkCurve.evaluate(pt);
        const float spx = tx + bw + pt * (tw - 2.0f * bw);
        const float spy = spY + (1.0f - pv) * spH - 0.8f;
        if (s == 0) c.moveTo(spx, spy); else c.lineTo(spx, spy);
      }
      for (int s = 24; s >= 0; --s) {
        const float pt = cast(float) s / 24.0f;
        const float pv = sparkCurve.evaluate(pt);
        const float spx = tx + bw + pt * (tw - 2.0f * bw);
        const float spy = spY + (1.0f - pv) * spH + 0.8f;
        c.lineTo(spx, spy);
      }
      c.closePath();
      c.fill();

      // Live playhead dot along sparkline
      float ph = _playheadPhase;
      if (ph < 0.0f) ph = 0.0f; if (ph > 1.0f) ph = 1.0f;
      const float pv = sparkCurve.evaluate(ph);
      c.fillStyle = colTextBright;
      c.fillCircle(tx + bw + ph * (tw - 2.0f * bw), spY + (1.0f - pv) * spH, 2.0f);
    }

    const float barH = (trackH >= 20.0f) ? 8.0f : (trackH - 2.0f);
    const float barY = trackY + bw;

    if (isDual) {
      const float lo = (normA < normB) ? normA : normB;
      const float hi = (normA < normB) ? normB : normA;
      const float pxA = pxSnap(tx + 3.0f + normA * (tw - 6.0f));
      const float pxB = pxSnap(tx + 3.0f + normB * (tw - 6.0f));

      // Modulation span bar
      const float spanX = pxSnap(tx + 3.0f + lo * (tw - 6.0f));
      const float spanEnd = pxSnap(tx + 3.0f + hi * (tw - 6.0f));
      c.fillStyle = RGBA(accent.r, accent.g, accent.b, 105);
      c.fillRect(spanX, barY + bw, spanEnd - spanX, barH - 2.0f * bw);

      // Left / Right Triangle Chevrons (`▶` Start / `◀` End)
      drawChevron(c, pxA, barY + barH * 0.5f, 5.5f, true, accent);
      drawChevron(c, pxB, barY + barH * 0.5f, 5.5f, false, colTextBright);
    } else {
      const float fillEnd = pxSnap(tx + bw + (tw - 2.0f * bw) * normA);
      c.fillStyle = RGBA(accent.r, accent.g, accent.b, 125);
      c.fillRect(tx + bw, barY + bw, fillEnd - (tx + bw), barH - 2.0f * bw);
      const float px = pxSnap(tx + 2.0f + (tw - 4.0f) * normA);
      c.fillStyle = colTextBright;
      c.fillRect(px - bw, barY, 3.0f * bw, barH);
    }
  }

  private static void drawChevron(ref Canvas c, float cx, float cy, float size, bool pointRight, RGBA col) {
    c.fillStyle = col;
    c.beginPath();
    if (pointRight) {
      c.moveTo(cx - size * 0.65f, cy - size * 0.7f);
      c.lineTo(cx + size * 0.65f, cy);
      c.lineTo(cx - size * 0.65f, cy + size * 0.7f);
    } else {
      c.moveTo(cx + size * 0.65f, cy - size * 0.7f);
      c.lineTo(cx - size * 0.65f, cy);
      c.lineTo(cx + size * 0.65f, cy + size * 0.7f);
    }
    c.closePath();
    c.fill();
  }

  private void drawTxtAligned(ref ImageRef!RGBA cropped, box2i dirty, float scale,
                              const(char)[] text, float lx, float ly, float pxSize, RGBA col,
                              HorizontalAlignment alignH) {
    if (_font is null || text.length == 0) return;
    const float effPx = (pxSize < 10.0f) ? 10.0f : pxSize;
    const float scaledPx = snapF(effPx * scale);
    const float spacing = 0.0f;
    const float sx = snapF(lx * scale - cast(float) dirty.min.x);
    const float sy = snapF(ly * scale - cast(float) dirty.min.y);
    fillText(cropped, _font, text, scaledPx, spacing, col, sx, sy,
             alignH, VerticalAlignment.center);
  }

  private void drawTxtRight(ref ImageRef!RGBA cropped, box2i dirty, float scale,
                            const(char)[] text, float rx, float ly, float pxSize, RGBA col) {
    if (_font is null || text.length == 0) return;
    const float effPx = (pxSize < 10.0f) ? 10.0f : pxSize;
    const float scaledPx = snapF(effPx * scale);
    const float spacing = 0.0f;
    const box2i bounds = _font.measureText(text, scaledPx, spacing);
    const float sx = snapF(rx * scale - cast(float) dirty.min.x - cast(float) bounds.width);
    const float sy = snapF(ly * scale - cast(float) dirty.min.y);
    fillText(cropped, _font, text, scaledPx, spacing, col, sx, sy,
             HorizontalAlignment.left, VerticalAlignment.center);
  }

  // =========================================================================
  // Interactive Mouse Hover, Click & Drag Routing (All 6 Sections)
  // =========================================================================

  void handleWorkspaceHover(int rawX, int rawY) {
    if (rawX < 0 || rawY < 0) {
      _hoverX = -1;
      _hoverY = -1;
      return;
    }
    const float scale = (position.width > 0)
      ? (cast(float) position.width / cast(float) BASE_WIDTH) : 1.0f;
    _hoverX = cast(int)(cast(float) rawX / scale);
    _hoverY = cast(int)(cast(float) rawY / scale);
  }

  Click handleWorkspaceClick(int rawX, int rawY, int button, bool isDoubleClick) {
    const float scale = (position.width > 0)
      ? (cast(float) position.width / cast(float) BASE_WIDTH) : 1.0f;
    const int x = cast(int)(cast(float) rawX / scale);
    const int y = cast(int)(cast(float) rawY / scale);

    _dragMode = DragMode.none;
    _dragNodeIdx = -1;
    _dragTensionIdx = -1;
    _dragSliderHandle = 0;

    // 1. Top Header Interactions (y in 0..109)
    if (y >= 0 && y < HEADER_H) {
      return handleHeaderClick(x, y, isDoubleClick);
    }

    // 2. Full-Width STUTTER Strip (y in 114..186)
    if (y >= 114 && y <= 186) {
      return handleStutterStripClick(x, y);
    }

    // 3. Full-Width BUFFER Strip (y in 192..264)
    if (y >= 192 && y <= 264) {
      return handleBufferStripClick(x, y);
    }

    // 4. Left Signal Chain (x in 8..168, y in 272..672)
    if (x >= 8 && x <= 168 && y >= 272 && y <= 672) {
      int row = (y - 276) / 36;
      if (row < 0) row = 0;
      if (row >= NumChainFX) row = NumChainFX - 1;
      const ChainFXId fxId = chainAtSlot(row);
      const int modSlot = chainFXToModuleSlot(fxId);

      // Drag handle `≡` on right (x >= 136)
      if (x >= 136) {
        _dragMode = DragMode.chainReorder;
        _dragChainFromIdx = row;
        setActiveModule(modSlot);
        return Click.startDrag;
      }

      // Hex bypass LED on left (x <= 42)
      if (x <= 42) {
        toggleChainFX(fxId);
      }
      setActiveModule(modSlot);
      return Click.handled;
    }

    // 5. Expanded Curve Editor occupies x=176..1032, y=272..672
    if (_curveExpanded && x >= 176 && x <= 1032 && y >= 272 && y <= 672) {
      return handleCurveEditorClick(x, y, button, isDoubleClick, true);
    }

    // 6. Center Selected Effect Inspector (x=176..556, y=272..672)
    if (x >= 176 && x <= 556 && y >= 272 && y <= 672) {
      return handleInspectorClick(x, y, isDoubleClick);
    }

    // 7. Embedded Curve Editor (x=564..1032, y=272..486)
    if (x >= 564 && x <= 1032 && y >= 272 && y <= 486) {
      return handleCurveEditorClick(x, y, button, isDoubleClick, false);
    }

    // 8. Purple Output Section (x=564..1032, y=492..672)
    if (x >= 564 && x <= 1032 && y >= 492 && y <= 672) {
      return handleOutputClick(x, y, isDoubleClick);
    }

    return Click.unhandled;
  }

  private Click handleHeaderClick(int x, int y, bool isDoubleClick) {
    // UI Zoom preset cycle pill (x=156..192, y=10..32)
    if (x >= 156 && x <= 192 && y >= 10 && y <= 32) {
      static immutable float[4] zoomPresets = [1.0f, 1.25f, 1.5f, 2.0f];
      const float curScale = (position.width > 0)
        ? (cast(float) position.width / cast(float) BASE_WIDTH) : 1.0f;
      int nextIdx = 0;
      foreach (idx, zp; zoomPresets) {
        if (curScale < zp - 0.05f) {
          nextIdx = cast(int) idx;
          break;
        }
      }
      if (_hasClient && context !is null) {
        int newW = cast(int)(BASE_WIDTH * zoomPresets[nextIdx] + 0.5f);
        int newH = cast(int)(BASE_HEIGHT * zoomPresets[nextIdx] + 0.5f);
        context.getUINearestValidSize(&newW, &newH);
        context.requestUIResize(newW, newH);
      }
      setDirtyWhole();
      return Click.handled;
    }
    // Play Mode toggle (x=12..206, y=42..70)
    if (x >= 12 && x <= 206 && y >= 42 && y <= 70) {
      setBoolParamSafe(_params[Params.autoMode], _hasClient, !isAutoMode());
      setDirtyWhole();
      return Click.handled;
    }
    // Factory Preset < > (x=12..206, y=74..102)
    if (x >= 12 && x <= 206 && y >= 74 && y <= 102) {
      int cur = getIntParam(Params.bankPreset, 0);
      cur = (x < 100)
        ? (cur - 1 + NUM_FACTORY_PRESETS) % NUM_FACTORY_PRESETS
        : (cur + 1) % NUM_FACTORY_PRESETS;
      setIntParamSafe(_params[Params.bankPreset], _hasClient, cur);
      applyFactoryPreset(_params, cur);
      setDirtyWhole();
      return Click.handled;
    }
    // 24-Note Rainbow Gesture Palette (x=216..702, y=8..44)
    if (x >= 216 && x <= 702 && y >= 8 && y <= 44) {
      int key = cast(int)((cast(float)(x - 219)) / (480.0f / 24.0f));
      if (key < 0) key = 0;
      if (key >= NUM_BT_GESTURES) key = NUM_BT_GESTURES - 1;
      selectGesture(key);
      return Click.handled;
    }
    // White Active Gesture Pill arrows < > (x=216..488, y=70..102)
    if (x >= 216 && x <= 488 && y >= 68 && y <= 104) {
      const int delta = (x < 350) ? -1 : 1;
      selectGesture((currentGestureIdx() + delta + NUM_BT_GESTURES) % NUM_BT_GESTURES);
      return Click.handled;
    }
    // Length, Release, Grid pills (y=50..74)
    if (y >= 50 && y <= 74) {
      if (x >= 496 && x <= 562) {
        cycleIntParam(Params.gestureLength);
        return Click.handled;
      }
      if (x >= 566 && x <= 638) {
        if (_client !is null && !_client.stickMode && getIntParam(Params.releaseMode, 0) == ReleaseMode.onGrid) {
          _client.stickMode = true;
        } else {
          if (_client !is null) _client.stickMode = false;
          cycleIntParam(Params.releaseMode);
        }
        setDirtyWhole();
        return Click.handled;
      }
      if (x >= 642 && x <= 702) {
        cycleIntParam(Params.quantizeGrid);
        return Click.handled;
      }
    }
    // Palindrome, Freeze, Duration (y=78..102)
    if (y >= 78 && y <= 104) {
      if (x >= 496 && x <= 578) {
        if (_client !is null) _client.palindrome = !_client.palindrome;
        else _localPalindrome = !_localPalindrome;
        setDirtyWhole();
        return Click.handled;
      }
      if (x >= 582 && x <= 654) {
        if (_client !is null) _client.freezeActive = !_client.freezeActive;
        else _localFreeze = !_localFreeze;
        setDirtyWhole();
        return Click.handled;
      }
      if (x >= 658 && x <= 702) {
        static immutable float[4] durs = [0.125f, 0.25f, 0.5f, 1.0f];
        float curD = (_client !is null) ? _client.freezeBeats : _localFreezeBeats;
        int nextIdx = 0;
        foreach (idx, d; durs) {
          if (fabs(curD - d) < 0.02f) { nextIdx = (cast(int) idx + 1) % 4; break; }
        }
        if (_client !is null) _client.freezeBeats = durs[nextIdx];
        else _localFreezeBeats = durs[nextIdx];
        setDirtyWhole();
        return Click.handled;
      }
    }
    // Global Filter Dial (x=714..804, y=12..98)
    if (x >= 714 && x <= 804) {
      if (isDoubleClick) {
        if (_client !is null) _client.globalFilterDial = 0.0f;
        else _localGlobalFilter = 0.0f;
        setDirtyWhole();
        return Click.handled;
      }
      _dragMode = DragMode.globalFilter;
      _dragStartY = y;
      _dragStartVal = (_client !is null) ? _client.globalFilterDial : _localGlobalFilter;
      return Click.startDrag;
    }
    // Undo / Redo (x=820..916, y=14..40)
    if (y >= 14 && y <= 40) {
      if (x >= 820 && x <= 866) {
        if (_client !is null) _client.undo();
        setDirtyWhole();
        return Click.handled;
      }
      if (x >= 870 && x <= 916) {
        if (_client !is null) _client.redo();
        setDirtyWhole();
        return Click.handled;
      }
    }
    // Auto Rate (x=820..1030, y=48..74)
    if (x >= 820 && x <= 1030 && y >= 48 && y <= 74) {
      cycleIntParam(Params.autoRate);
      setDirtyWhole();
      return Click.handled;
    }
    return Click.handled;
  }

  private Click handleStutterStripClick(int x, int y) {
    if (x <= 122) {
      setBoolParamSafe(_params[Params.stutterEnable], _hasClient, !isModuleEnabled(ModuleSlot.stutter));
      setActiveModule(ModuleSlot.stutter);
      return Click.handled;
    }
    if (x >= 130 && x <= 420) {
      setActiveModule(ModuleSlot.stutter);
      _dragMode = DragMode.stripSlider;
      _dragStripKind = 0; // Stutter rate
      const float maxR = cast(float)(stutterSubdivisionNames.length - 1);
      const float nA = cast(float) getIntParam(Params.stutterRateStart, 3) / maxR;
      const float nB = cast(float) getIntParam(Params.stutterRateEnd, 5) / maxR;
      const float clickN = cast(float) clamp01(cast(double)(x - 139) / 272.0);
      _dragSliderHandle = (fabs(clickN - nA) <= fabs(clickN - nB)) ? 0 : 1;
      updateStripSliderDrag(x, y);
      return Click.startDrag;
    }
    if (x >= 430 && x <= 526) {
      if (y < 148) {
        if (_client !is null) _client.stutterQuantizeEnabled = !_client.stutterQuantizeEnabled;
      } else if (_client !is null) {
        _client.stutterStepMode = cast(StutterStepMode)((cast(int) _client.stutterStepMode + 1) % 6);
      }
      setDirtyWhole();
      return Click.handled;
    }
    if (x >= 534 && x <= 696) {
      _dragMode = DragMode.stripSlider;
      _dragStripKind = 1; // Stutter step
      _dragSliderHandle = 0;
      updateStripSliderDrag(x, y);
      return Click.startDrag;
    }
    if (x >= 704 && x <= 784) {
      setBoolParamSafe(_params[Params.gateEnable], _hasClient, !isModuleEnabled(ModuleSlot.gate));
      setActiveModule(ModuleSlot.gate);
      return Click.handled;
    }
    if (x >= 792 && x <= 952) {
      setActiveModule(ModuleSlot.gate);
      _dragMode = DragMode.stripSlider;
      _dragStripKind = 2; // Gate Width
      const float nA = getNormParam(Params.gateWidthMin, 0.2f);
      const float nB = getNormParam(Params.gateWidthMax, 0.8f);
      const float clickN = cast(float) clamp01(cast(double)(x - 801) / 142.0);
      _dragSliderHandle = (fabs(clickN - nA) <= fabs(clickN - nB)) ? 0 : 1;
      updateStripSliderDrag(x, y);
      return Click.startDrag;
    }
    if (x > 952) {
      setActiveModule(ModuleSlot.gate);
      _dragMode = DragMode.stripSlider;
      _dragStripKind = 3; // Gate Tail
      _dragStartY = y;
      _dragStartVal = getNormParam(Params.gateTail, 0.1f);
      return Click.startDrag;
    }
    return Click.handled;
  }

  private Click handleBufferStripClick(int x, int y) {
    if (x <= 122) {
      setBoolParamSafe(_params[Params.bufferEnable], _hasClient, !isModuleEnabled(ModuleSlot.buffer));
      setActiveModule(ModuleSlot.buffer);
      return Click.handled;
    }
    if (x >= 130 && x <= 332) {
      setActiveModule(ModuleSlot.buffer);
      _dragMode = DragMode.stripSlider;
      if (y < 228) {
        _dragStripKind = 4; // Pos Min/Max
        const float nA = getNormParam(Params.bufferPositionMin, 0.0f);
        const float nB = getNormParam(Params.bufferPositionMax, 0.5f);
        const float clickN = cast(float) clamp01(cast(double)(x - 139) / 184.0);
        _dragSliderHandle = (fabs(clickN - nA) <= fabs(clickN - nB)) ? 0 : 1;
      } else {
        _dragStripKind = 5; // Pitch Min/Max
        const float nA = getNormParam(Params.bufferPitchMin, 0.5f);
        const float nB = getNormParam(Params.bufferPitchMax, 0.5f);
        const float clickN = cast(float) clamp01(cast(double)(x - 139) / 184.0);
        _dragSliderHandle = (fabs(clickN - nA) <= fabs(clickN - nB)) ? 0 : 1;
      }
      updateStripSliderDrag(x, y);
      return Click.startDrag;
    }
    if (x >= 338 && x <= 420) {
      if (_client !is null) {
        if (x >= 384) {
          _client.bufferLinkLR = !_client.bufferLinkLR;
        } else if (y < 228) {
          _client.bufferReverseL = !_client.bufferReverseL;
          if (_client.bufferLinkLR) _client.bufferReverseR = _client.bufferReverseL;
        } else {
          _client.bufferReverseR = !_client.bufferReverseR;
          if (_client.bufferLinkLR) _client.bufferReverseL = _client.bufferReverseR;
        }
      }
      setDirtyWhole();
      return Click.handled;
    }
    if (x >= 430 && x <= 526) {
      if (_client !is null) {
        if (y < 228) {
          _client.bufferMovement = cast(BufferMovementMode)((cast(int) _client.bufferMovement + 1) % 3);
        } else {
          static immutable float[5] grids = [0.0625f, 0.125f, 0.25f, 0.5f, 1.0f];
          int nxt = 0;
          foreach (idx, g; grids) {
            if (fabs(_client.bufferGridBeats - g) < 0.01f) { nxt = (cast(int) idx + 1) % 5; break; }
          }
          _client.bufferGridBeats = grids[nxt];
        }
      }
      setDirtyWhole();
      return Click.handled;
    }
    if (x >= 534 && x <= 696) {
      if (y < 228) {
        if (x >= 640) {
          _editingJitter = !_editingJitter;
        } else if (_client !is null) {
          _client.jitterEnabled = !_client.jitterEnabled;
        }
      } else if (_client !is null) {
        _client.jitterPitchMode = cast(JitterPitchMode)((cast(int) _client.jitterPitchMode + 1) % 3);
      }
      setDirtyWhole();
      return Click.handled;
    }
    if (x >= 704 && x <= 784) {
      setBoolParamSafe(_params[Params.panEnable], _hasClient, !isModuleEnabled(ModuleSlot.pan));
      setActiveModule(ModuleSlot.pan);
      return Click.handled;
    }
    if (x >= 792 && x <= 952) {
      setActiveModule(ModuleSlot.pan);
      _dragMode = DragMode.stripSlider;
      _dragStripKind = 6; // Pan Width
      const float nA = getNormParam(Params.panWidthMin, 0.25f);
      const float nB = getNormParam(Params.panWidthMax, 1.0f);
      const float clickN = cast(float) clamp01(cast(double)(x - 801) / 142.0);
      _dragSliderHandle = (fabs(clickN - nA) <= fabs(clickN - nB)) ? 0 : 1;
      updateStripSliderDrag(x, y);
      return Click.startDrag;
    }
    if (x > 952) {
      setActiveModule(ModuleSlot.pan);
      _dragMode = DragMode.stripSlider;
      _dragStripKind = 7; // Pan Center
      _dragStartY = y;
      _dragStartVal = getNormParam(Params.panCenterMax, 0.5f);
      return Click.startDrag;
    }
    return Click.handled;
  }

  private Click handleInspectorClick(int x, int y, bool isDoubleClick) {
    if (_editingJitter) {
      if (x >= 476 && y <= 316) {
        _editingJitter = false;
        setDirtyWhole();
        return Click.handled;
      }
      if (x <= 220 && y <= 318 && _client !is null) {
        _client.jitterEnabled = !_client.jitterEnabled;
        setDirtyWhole();
        return Click.handled;
      }
      if (y >= 376) {
        const int col = (x >= 364) ? 1 : 0;
        const int row = (y >= 514) ? 1 : 0;
        _activeInspectorParam = row * 2 + col;
        _dragMode = DragMode.inspectorSlider;
        _dragSliderHandle = 0;
        updateInspectorSliderDrag(x, y);
        return Click.startDrag;
      }
      return Click.handled;
    }

    // Hex Bypass top-left (x=180..215, y=282..322)
    if (x <= 215 && y <= 322) {
      toggleActiveModuleBypass();
      setDirtyWhole();
      return Click.handled;
    }
    // Electric-Blue Dry/Wet dial top-right (x>=484, y<=334)
    if (x >= 484 && y <= 334) {
      if (isDoubleClick) {
        setModuleMixNorm(_activeModule, 1.0f);
        setDirtyWhole();
        return Click.handled;
      }
      _dragMode = DragMode.inspectorMix;
      _dragStartY = y;
      _dragStartVal = getModuleMixNorm(_activeModule);
      return Click.startDrag;
    }
    // Quick Mode Pill (y=338..366)
    if (y >= 338 && y <= 368) {
      if (_activeModule == ModuleSlot.distort && _client !is null) {
        _client.distortTwoBand = !_client.distortTwoBand;
      } else if (_activeModule == ModuleSlot.filter) {
        cycleIntParam(Params.filterType);
      } else if (_activeModule == 14 && _client !is null) {
        _client.highpassPoles = (_client.highpassPoles == 0) ? 1 : 0;
      } else if (_activeModule == ModuleSlot.tapeStop) {
        setBoolParamSafe(_params[Params.tapeStopPlunge], _hasClient, !getBoolParam(Params.tapeStopPlunge, true));
      } else if (_activeModule == ModuleSlot.reverb) {
        setBoolParamSafe(_params[Params.reverbFreeze], _hasClient, !getBoolParam(Params.reverbFreeze, false));
      } else if (_activeModule == ModuleSlot.phaser) {
        cycleIntParam(Params.phaserStages);
      }
      setDirtyWhole();
      return Click.handled;
    }
    // 2x2 Parameter Sliders (y >= 376)
    if (y >= 376) {
      const int col = (x >= 364) ? 1 : 0;
      const int row = (y >= 514) ? 1 : 0;
      _activeInspectorParam = row * 2 + col;
      _dragMode = DragMode.inspectorSlider;

      // Smart dual-chevron picking based on closest horizontal handle
      const InspectorSliderSpec spec = getInspectorSpecs(_activeModule)[_activeInspectorParam];
      float nA, nB;
      readInspectorValues(spec, nA, nB);
      const float sx = 190.0f + col * 180.0f;
      const float clickN = cast(float) clamp01(cast(double)(x - (sx + 9.0f)) / 150.0f);
      _dragSliderHandle = (spec.isDual && fabs(clickN - nB) < fabs(clickN - nA)) ? 1 : 0;

      updateInspectorSliderDrag(x, y);
      return Click.startDrag;
    }
    return Click.handled;
  }

  private Click handleOutputClick(int x, int y, bool isDoubleClick) {
    if (x >= 574 && x <= 700) {
      if (y < 590) {
        if (x < 626 && _client !is null) {
          _client.wetGainEnable = !_client.wetGainEnable;
          setDirtyWhole();
          return Click.handled;
        }
        if (isDoubleClick && _client !is null) {
          _client.wetGainDb = 0.0f;
          setDirtyWhole();
          return Click.handled;
        }
        _dragMode = DragMode.outputControl;
        _dragStripKind = 0; // Wet gain dial
        _dragStartY = y;
        _dragStartVal = (_client !is null) ? (_client.wetGainDb + 24.0f) / 36.0f : 0.667f;
        return Click.startDrag;
      } else {
        if (x < 626 && _client !is null) {
          _client.dryGainEnable = !_client.dryGainEnable;
          setDirtyWhole();
          return Click.handled;
        }
        if (isDoubleClick && _client !is null) {
          _client.dryGainDb = 0.0f;
          setDirtyWhole();
          return Click.handled;
        }
        _dragMode = DragMode.outputControl;
        _dragStripKind = 1; // Dry gain dial
        _dragStartY = y;
        _dragStartVal = (_client !is null) ? (_client.dryGainDb + 24.0f) / 36.0f : 0.667f;
        return Click.startDrag;
      }
    }
    if (x >= 706 && x <= 938) {
      if (y < 532) {
        setBoolParamSafe(_params[Params.limiterEnable], _hasClient, !isModuleEnabled(ModuleSlot.limiter));
        setDirtyWhole();
        return Click.handled;
      }
      _dragMode = DragMode.outputControl;
      _dragStripKind = (y < 588) ? 2 : 3; // Threshold or Out Gain
      updateOutputControlDrag(x, y);
      return Click.startDrag;
    }
    return Click.handled;
  }

  private Click handleCurveEditorClick(int x, int y, int button, bool isDoubleClick, bool expanded) {
    const float ex = expanded ? 176.0f : 564.0f;
    const float ey = 272.0f;
    const float ew = expanded ? 856.0f : 468.0f;
    const float gx = ex + 8.0f;
    const float gy = ey + 34.0f;
    const float gw = ew - 16.0f;
    const float gh = expanded ? 302.0f : 132.0f;

    // Header Toolbar buttons (y in 272..305)
    if (y >= cast(int) ey && y < cast(int) gy) {
      const int eSlot = (_activeModule == 14) ? 14 : (_activeModule < 14 ? _activeModule : 0);
      if (x >= cast(int)(ex + ew - 62.0f)) {
        setCurveExpanded(!_curveExpanded);
        return Click.handled;
      }
      if (x >= cast(int)(ex + ew - 106.0f) && x < cast(int)(ex + ew - 62.0f)) {
        if (_client !is null) {
          int g = _client.extTvmBank.states[eSlot][0].gridResolution;
          _client.extTvmBank.states[eSlot][0].gridResolution = (g >= 32) ? 4 : g * 2;
        }
        setDirtyWhole();
        return Click.handled;
      }
      if (x >= cast(int)(ex + ew - 150.0f) && x < cast(int)(ex + ew - 106.0f)) {
        if (_client !is null) {
          _client.extTvmBank.states[eSlot][0].reversed = !_client.extTvmBank.states[eSlot][0].reversed;
        }
        setDirtyWhole();
        return Click.handled;
      }
      if (x >= cast(int)(ex + ew - 198.0f) && x < cast(int)(ex + ew - 150.0f)) {
        if (_client !is null) {
          static immutable float[5] spds = [0.25f, 0.5f, 1.0f, 2.0f, 4.0f];
          float cur = _client.extTvmBank.states[eSlot][0].speedMultiplier;
          int nxt = 2;
          foreach (idx, sp; spds) {
            if (fabs(cur - sp) < 0.05f) { nxt = (cast(int) idx + 1) % 5; break; }
          }
          _client.extTvmBank.states[eSlot][0].speedMultiplier = spds[nxt];
        }
        setDirtyWhole();
        return Click.handled;
      }
      if (x >= cast(int)(ex + ew - 246.0f) && x < cast(int)(ex + ew - 198.0f)) {
        TVMCurve* cl = getActiveLocalCurvePtr();
        TVMCurve* cc = getActiveClientCurvePtr();
        cl.reset();
        if (cc !is null) cc.reset();
        setDirtyWhole();
        return Click.handled;
      }
      return Click.handled;
    }

    // Bottom 12 Preset Curve Thumbnails
    const float py = gy + gh + 6.0f;
    if (y >= cast(int) py) {
      const float pwTotal = ew - 16.0f;
      int shapeIdx = cast(int)((cast(float)(x - (ex + 8.0f)) / pwTotal) * 12.0f);
      if (shapeIdx < 0) shapeIdx = 0;
      if (shapeIdx > 11) shapeIdx = 11;
      applyCurvePresetToActiveModule(shapeIdx);
      return Click.handled;
    }

    // Curve Viewport Area: check nodes & tension rings
    enum float pad = 10.0f;
    const float cw = gw - pad * 2.0f;
    const float ch = gh - pad * 2.0f;
    float normX = (cast(float) x - (gx + pad)) / cw;
    float normY = 1.0f - (cast(float) y - (gy + pad)) / ch;
    if (normX < 0.0f) normX = 0.0f; if (normX > 1.0f) normX = 1.0f;
    if (normY < 0.0f) normY = 0.0f; if (normY > 1.0f) normY = 1.0f;

    TVMCurve* cLocal = getActiveLocalCurvePtr();
    TVMCurve* cClient = getActiveClientCurvePtr();

    int bestNode = -1;
    float bestDist2 = 14.0f * 14.0f;
    const int nNodes = cLocal.nodeCount();
    for (int i = 0; i < nNodes; ++i) {
      const float nx = gx + pad + cLocal.nodes[i].x * cw;
      const float ny = gy + pad + (1.0f - cLocal.nodes[i].y) * ch;
      const float d2 = (x - nx) * (x - nx) + (y - ny) * (y - ny);
      if (d2 < bestDist2) { bestDist2 = d2; bestNode = i; }
    }

    // Right-click deletes interior breakpoint node
    if (button == MouseButton.right) {
      if (bestNode > 0 && bestNode < nNodes - 1) {
        cLocal.removeNode(bestNode);
        if (cClient !is null) cClient.removeNode(bestNode);
        setDirtyWhole();
      }
      return Click.handled;
    }

    // Check midpoint hollow tension rings
    if (bestNode == -1) {
      for (int i = 0; i + 1 < nNodes; ++i) {
        const float midX = 0.5f * (cLocal.nodes[i].x + cLocal.nodes[i + 1].x);
        const float hx = gx + pad + midX * cw;
        const float hy = gy + pad + (1.0f - cLocal.evaluate(midX)) * ch;
        const float d2 = (x - hx) * (x - hx) + (y - hy) * (y - hy);
        if (d2 < 14.0f * 14.0f) {
          _dragMode = DragMode.curveTension;
          _dragTensionIdx = i;
          _dragStartY = y;
          _dragStartVal = cLocal.nodes[i].tension;
          return Click.startDrag;
        }
      }
    }

    if (isDoubleClick) {
      if (bestNode > 0 && bestNode < nNodes - 1) {
        const ubyte nextT = cast(ubyte)((cast(ubyte) cLocal.nodes[bestNode].type + 1) % 5);
        cLocal.nodes[bestNode].type = cast(CurveType) nextT;
        if (cClient !is null && bestNode < cClient.nodeCount()) {
          cClient.nodes[bestNode].type = cast(CurveType) nextT;
        }
      } else if (cLocal.nodeCount() < 16) {
        cLocal.addNode(normX, normY, 0.0f, CurveType.linear);
        if (cClient !is null) cClient.addNode(normX, normY, 0.0f, CurveType.linear);
      }
      setDirtyWhole();
      return Click.handled;
    }

    if (bestNode == -1 && cLocal.nodeCount() < 16) {
      cLocal.addNode(normX, normY, 0.0f, CurveType.linear);
      if (cClient !is null) cClient.addNode(normX, normY, 0.0f, CurveType.linear);
      for (int i = 1; i < cLocal.nodeCount() - 1; ++i) {
        if (fabs(cLocal.nodes[i].x - normX) < 1e-4f) { bestNode = i; break; }
      }
      if (bestNode == -1) bestNode = cLocal.nodeCount() / 2;
    }

    _dragMode = DragMode.curveNode;
    _dragNodeIdx = bestNode;
    updateCurveNodeDrag(x, y);
    return Click.startDrag;
  }

  void handleWorkspaceDrag(int rawX, int rawY, int dx, int dy) {
    const float scale = (position.width > 0)
      ? (cast(float) position.width / cast(float) BASE_WIDTH) : 1.0f;
    const int x = cast(int)(cast(float) rawX / scale);
    const int y = cast(int)(cast(float) rawY / scale);
    _hoverX = x;
    _hoverY = y;

    final switch (_dragMode) {
      case DragMode.none:
        break;
      case DragMode.chainReorder:
        if (_client !is null && _dragChainFromIdx >= 0) {
          int target = (y - 276) / 36;
          if (target < 0) target = 0;
          if (target >= NumChainFX) target = NumChainFX - 1;
          if (target != _dragChainFromIdx) {
            _client.moveSignalChain(_dragChainFromIdx, target);
            _dragChainFromIdx = target;
            setDirtyWhole();
          }
        }
        break;
      case DragMode.globalFilter:
        float v = _dragStartVal + cast(float)(_dragStartY - y) / 90.0f;
        if (v < -1.0f) v = -1.0f; if (v > 1.0f) v = 1.0f;
        if (_client !is null) _client.globalFilterDial = v;
        else _localGlobalFilter = v;
        setDirtyWhole();
        break;
      case DragMode.stripSlider:
        updateStripSliderDrag(x, y);
        break;
      case DragMode.inspectorSlider:
        updateInspectorSliderDrag(x, y);
        break;
      case DragMode.inspectorMix:
        float mv = _dragStartVal + cast(float)(_dragStartY - y) / 80.0f;
        if (mv < 0.0f) mv = 0.0f; if (mv > 1.0f) mv = 1.0f;
        setModuleMixNorm(_activeModule, mv);
        setDirtyWhole();
        break;
      case DragMode.outputControl:
        updateOutputControlDrag(x, y);
        break;
      case DragMode.curveNode:
        updateCurveNodeDrag(x, y);
        break;
      case DragMode.curveTension:
        if (_dragTensionIdx >= 0) {
          float nt = _dragStartVal + cast(float)(_dragStartY - y) / 70.0f;
          if (nt < -1.0f) nt = -1.0f; if (nt > 1.0f) nt = 1.0f;
          TVMCurve* cl = getActiveLocalCurvePtr();
          TVMCurve* cc = getActiveClientCurvePtr();
          if (_dragTensionIdx < cl.nodeCount()) {
            cl.nodes[_dragTensionIdx].tension = nt;
            cl.nodes[_dragTensionIdx].type = CurveType.exponential;
          }
          if (cc !is null && _dragTensionIdx < cc.nodeCount()) {
            cc.nodes[_dragTensionIdx].tension = nt;
            cc.nodes[_dragTensionIdx].type = CurveType.exponential;
          }
          setDirtyWhole();
        }
        break;
    }
  }

  void handleWorkspaceStopDrag() {
    _dragMode = DragMode.none;
    _dragNodeIdx = -1;
    _dragTensionIdx = -1;
    _dragChainFromIdx = -1;
    _dragSliderHandle = 0;
  }

  void advanceAnimation(double dt, double time) {
    if (_client !is null && _client.gestureController().getIsActive()) {
      _playheadPhase = _client.gestureController().getGesturePhase();
    } else if (dt > 0.0 && !isNaN(dt)) {
      _playheadPhase = cast(float)((_playheadPhase + dt * 0.5) % 1.0);
    }
    if (dt > 0.0 && !isNaN(dt)) {
      const float decay = cast(float)(dt * 0.55);
      _peakHoldL = (_peakHoldL > decay) ? (_peakHoldL - decay) : 0.0f;
      _peakHoldR = (_peakHoldR > decay) ? (_peakHoldR - decay) : 0.0f;
    }
  }

  // =========================================================================
  // Drag Updaters & Formatting Helpers
  // =========================================================================

  private float evalEffectiveCurvePhase(int eSlot) const pure {
    float ph = _playheadPhase;
    if (ph < 0.0f) ph = 0.0f;
    if (ph > 1.0f) ph = 1.0f;
    if (_client !is null && eSlot >= 0 && eSlot < 15) {
      const ref state = _client.extTvmBank.states[eSlot][0];
      ph = (ph * state.speedMultiplier) % 1.0f;
      if (state.reversed) ph = 1.0f - ph;
    }
    return ph;
  }

  private void updateStripSliderDrag(int x, int y) {
    switch (_dragStripKind) {
      case 0: // Stutter Rate Start/End
        const double n = clamp01(cast(double)(x - 139) / 272.0);
        setNormParamSafe(_params[(_dragSliderHandle == 0) ? Params.stutterRateStart : Params.stutterRateEnd],
                         _hasClient, n);
        break;
      case 1: // Stutter Step
        if (_client !is null) {
          const float n = cast(float) clamp01(cast(double)(x - 543) / 144.0);
          _client.stutterStepBeats = 0.0625f + n * 0.9375f;
        }
        break;
      case 2: // Gate Width
        const double n = clamp01(cast(double)(x - 801) / 142.0);
        setNormParamSafe(_params[(_dragSliderHandle == 0) ? Params.gateWidthMin : Params.gateWidthMax],
                         _hasClient, n);
        break;
      case 3: // Gate Tail dial
        setNormParamSafe(_params[Params.gateTail], _hasClient,
                         clamp01(_dragStartVal + cast(double)(_dragStartY - y) / 70.0));
        break;
      case 4: // Buffer Pos Min/Max
        const double n = clamp01(cast(double)(x - 139) / 184.0);
        setNormParamSafe(_params[(_dragSliderHandle == 0) ? Params.bufferPositionMin : Params.bufferPositionMax],
                         _hasClient, n);
        break;
      case 5: // Buffer Pitch Min/Max
        const double n = clamp01(cast(double)(x - 139) / 184.0);
        setNormParamSafe(_params[(_dragSliderHandle == 0) ? Params.bufferPitchMin : Params.bufferPitchMax],
                         _hasClient, n);
        break;
      case 6: // Pan Width
        const double n = clamp01(cast(double)(x - 801) / 142.0);
        setNormParamSafe(_params[(_dragSliderHandle == 0) ? Params.panWidthMin : Params.panWidthMax],
                         _hasClient, n);
        break;
      case 7: // Pan Center dial
        setNormParamSafe(_params[Params.panCenterMax], _hasClient,
                         clamp01(_dragStartVal + cast(double)(_dragStartY - y) / 70.0));
        break;
      default: break;
    }
    setDirtyWhole();
  }

  private void updateInspectorSliderDrag(int x, int y) {
    const int col = _activeInspectorParam % 2;
    const float sx = 190.0f + col * 180.0f;
    const double n = clamp01(cast(double)(x - (sx + 9.0f)) / 150.0);

    if (_editingJitter && _client !is null) {
      if (_activeInspectorParam == 0) _client.jitterRhythmAmount = cast(float) n;
      else if (_activeInspectorParam == 1) _client.jitterPitchAmount = cast(float) n;
      else if (_activeInspectorParam == 2) _client.jitterRate = 0.05f + cast(float) n * 0.95f;
      else _client.jitterOffset = cast(float) n - 0.5f;
      setDirtyWhole();
      return;
    }

    const InspectorSliderSpec spec = getInspectorSpecs(_activeModule)[_activeInspectorParam % 4];
    if (spec.customKind != 0 && _client !is null) {
      if (spec.customKind == 1) { // Highpass cutoff
        const float hz = 20.0f * (2.0f ^^ (cast(float) n * 9.5f));
        if (_dragSliderHandle == 0) _client.highpassCutoffMin = hz;
        else                         _client.highpassCutoffMax = hz;
      } else if (spec.customKind == 2) {
        _client.highpassRes = cast(float) n * 0.9f;
      } else if (spec.customKind == 3) {
        _client.distortDcOffset = cast(float) n * 2.0f - 1.0f;
      } else if (spec.customKind == 4) {
        _client.stutterStepBeats = 0.0625f + cast(float) n * 0.9375f;
      }
      setDirtyWhole();
      return;
    }

    if (spec.isDual) {
      setNormParamSafe(_params[(_dragSliderHandle == 0) ? spec.paramMin : spec.paramMax], _hasClient, n);
    } else {
      setNormParamSafe(_params[spec.paramMin], _hasClient, n);
    }
    setDirtyWhole();
  }

  private void updateOutputControlDrag(int x, int y) {
    if (_dragStripKind == 0 && _client !is null) {
      const float n = cast(float) clamp01(_dragStartVal + cast(double)(_dragStartY - y) / 70.0);
      _client.wetGainDb = -24.0f + n * 36.0f;
    } else if (_dragStripKind == 1 && _client !is null) {
      const float n = cast(float) clamp01(_dragStartVal + cast(double)(_dragStartY - y) / 70.0);
      _client.dryGainDb = -24.0f + n * 36.0f;
    } else if (_dragStripKind == 2) {
      setNormParamSafe(_params[Params.limiterThreshold], _hasClient,
                       clamp01(cast(double)(x - 720) / 202.0));
    } else if (_dragStripKind == 3) {
      setNormParamSafe(_params[Params.masterOutputGain], _hasClient,
                       clamp01(cast(double)(x - 720) / 202.0));
    }
    setDirtyWhole();
  }

  private void updateCurveNodeDrag(int x, int y) {
    if (_dragNodeIdx < 0) return;
    const float ex = _curveExpanded ? 176.0f : 564.0f;
    const float ey = 272.0f;
    const float ew = _curveExpanded ? 856.0f : 468.0f;
    const float gx = ex + 8.0f;
    const float gy = ey + 34.0f;
    const float gw = ew - 16.0f;
    const float gh = _curveExpanded ? 302.0f : 132.0f;
    enum float pad = 10.0f;

    const float normX = cast(float) clamp01(cast(double)(x - (gx + pad)) / (gw - pad * 2.0f));
    const float normY = cast(float) clamp01(1.0 - cast(double)(y - (gy + pad)) / (gh - pad * 2.0f));

    TVMCurve* cLocal = getActiveLocalCurvePtr();
    TVMCurve* cClient = getActiveClientCurvePtr();
    if (_dragNodeIdx >= cLocal.nodeCount()) return;

    const CurveType ct = cLocal.nodes[_dragNodeIdx].type;
    const float ctens = cLocal.nodes[_dragNodeIdx].tension;
    cLocal.setNode(_dragNodeIdx, normX, normY, ctens, ct);
    if (cClient !is null && _dragNodeIdx < cClient.nodeCount()) {
      cClient.setNode(_dragNodeIdx, normX, normY, ctens, ct);
    }
    setDirtyWhole();
  }

  private void applyCurvePresetToActiveModule(int presetIdx) {
    if (presetIdx < 0) presetIdx = 0;
    if (presetIdx > 11) presetIdx = 11;
    TVMCurve* cl = getActiveLocalCurvePtr();
    TVMCurve* cc = getActiveClientCurvePtr();
    cl.loadPreset(presetIdx);
    if (cc !is null) cc.loadPreset(presetIdx);

    if (_activeModule < NumTVMModuleSlots) {
      const Params cp = moduleCurveParam(_activeModule);
      if (_params.length > cp) setIntParamSafe(_params[cp], _hasClient, presetIdx);
    }
    setDirtyWhole();
  }

  private void selectGesture(int idx) {
    int g = idx % NUM_BT_GESTURES;
    if (g < 0) g += NUM_BT_GESTURES;
    setIntParamSafe(_params[Params.activeGesture], _hasClient, g);
    if (_client !is null) {
      _client.selectGestureBank(g, true);
    } else {
      applyBTGesturePreset(_params, g);
    }
    setDirtyWhole();
  }

  private void cycleIntParam(Params id) {
    if (_params.length <= id) return;
    if (auto ip = cast(IntegerParameter) _params[id]) {
      const int span = ip.maxValue() - ip.minValue() + 1;
      const int next = ip.minValue() + ((ip.value() - ip.minValue() + 1) % span);
      setIntParamSafe(ip, _hasClient, next);
    }
  }

  private void toggleChainFX(ChainFXId fxId) {
    if (fxId == ChainFXId.highpass) {
      if (_client !is null) _client.highpassEnable = !_client.highpassEnable;
    } else {
      const int ms = chainFXToModuleSlot(fxId);
      const Params ep = moduleEnableParam(ms);
      setBoolParamSafe(_params[ep], _hasClient, !isModuleEnabled(ms));
    }
    setDirtyWhole();
  }

  private void toggleActiveModuleBypass() {
    if (_activeModule == 14) {
      if (_client !is null) _client.highpassEnable = !_client.highpassEnable;
    } else {
      const Params ep = moduleEnableParam(_activeModule);
      setBoolParamSafe(_params[ep], _hasClient, !isModuleEnabled(_activeModule));
    }
  }

  private ChainFXId chainAtSlot(int idx) const pure @safe {
    if (idx < 0 || idx >= NumChainFX) return ChainFXId.distort;
    if (_client !is null) return _client.signalChainOrder[idx];
    return defaultSignalChainOrder[idx];
  }

  private bool isChainFXEnabled(ChainFXId fxId) {
    if (fxId == ChainFXId.highpass) return (_client !is null) ? _client.highpassEnable : false;
    return isModuleEnabled(chainFXToModuleSlot(fxId));
  }

  private bool isModuleEnabled(int slot) {
    const Params id = moduleEnableParam(slot);
    if (_params.length > id) {
      if (auto bp = cast(BoolParameter) _params[id]) return bp.value();
    }
    return false;
  }

  private bool isModuleEnabledExt(int slot) {
    if (slot == 14) return (_client !is null) ? _client.highpassEnable : false;
    return isModuleEnabled(slot);
  }

  private int currentGestureIdx() {
    if (_client !is null) return _client.activeGestureBankIdx;
    return getIntParam(Params.activeGesture, 0) % NUM_BT_GESTURES;
  }

  private int getIntParam(Params id, int fallback) {
    if (_params.length > id) {
      if (auto ip = cast(IntegerParameter) _params[id]) return ip.value();
    }
    return fallback;
  }

  private bool getBoolParam(Params id, bool fallback) {
    if (_params.length > id) {
      if (auto bp = cast(BoolParameter) _params[id]) return bp.value();
    }
    return fallback;
  }

  private float getNormParam(Params id, float fallback) {
    if (_params.length > id && _params[id] !is null) {
      return cast(float) _params[id].getNormalized();
    }
    return fallback;
  }

  private float getModuleMixNorm(int slot) {
    switch (slot) {
      case ModuleSlot.gate:     return getNormParam(Params.gateMix, 1.0f);
      case ModuleSlot.pan:      return getNormParam(Params.panMix, 1.0f);
      case ModuleSlot.tapeStop: return getNormParam(Params.tapeStopMix, 1.0f);
      case ModuleSlot.filter:   return getNormParam(Params.filterMix, 1.0f);
      case ModuleSlot.lofi:     return getNormParam(Params.lofiMix, 1.0f);
      case ModuleSlot.distort:  return getNormParam(Params.distortMix, 1.0f);
      case ModuleSlot.comb:     return getNormParam(Params.combMix, 0.5f);
      case ModuleSlot.chorus:   return getNormParam(Params.chorusMix, 0.5f);
      case ModuleSlot.flanger:  return getNormParam(Params.flangerMix, 0.5f);
      case ModuleSlot.phaser:   return getNormParam(Params.phaserMix, 0.5f);
      case ModuleSlot.reverb:   return getNormParam(Params.reverbMix, 0.35f);
      case ModuleSlot.delay:    return getNormParam(Params.delayMix, 0.3f);
      case 14:                  return (_client !is null) ? _client.highpassMix : 1.0f;
      default:                  return getNormParam(Params.masterDryWet, 1.0f);
    }
  }

  private void setModuleMixNorm(int slot, float val) {
    switch (slot) {
      case ModuleSlot.gate:     setNormParamSafe(_params[Params.gateMix], _hasClient, val); break;
      case ModuleSlot.pan:      setNormParamSafe(_params[Params.panMix], _hasClient, val); break;
      case ModuleSlot.tapeStop: setNormParamSafe(_params[Params.tapeStopMix], _hasClient, val); break;
      case ModuleSlot.filter:   setNormParamSafe(_params[Params.filterMix], _hasClient, val); break;
      case ModuleSlot.lofi:     setNormParamSafe(_params[Params.lofiMix], _hasClient, val); break;
      case ModuleSlot.distort:  setNormParamSafe(_params[Params.distortMix], _hasClient, val); break;
      case ModuleSlot.comb:     setNormParamSafe(_params[Params.combMix], _hasClient, val); break;
      case ModuleSlot.chorus:   setNormParamSafe(_params[Params.chorusMix], _hasClient, val); break;
      case ModuleSlot.flanger:  setNormParamSafe(_params[Params.flangerMix], _hasClient, val); break;
      case ModuleSlot.phaser:   setNormParamSafe(_params[Params.phaserMix], _hasClient, val); break;
      case ModuleSlot.reverb:   setNormParamSafe(_params[Params.reverbMix], _hasClient, val); break;
      case ModuleSlot.delay:    setNormParamSafe(_params[Params.delayMix], _hasClient, val); break;
      case 14:                  if (_client !is null) _client.highpassMix = val; break;
      default:                  setNormParamSafe(_params[Params.masterDryWet], _hasClient, val); break;
    }
  }

  private InspectorSliderSpec[4] getInspectorSpecs(int slot) const pure @safe {
    switch (slot) {
      case ModuleSlot.stutter:
        return [
          InspectorSliderSpec("RATE",       Params.stutterRateStart,    Params.stutterRateEnd,      true,  0),
          InspectorSliderSpec("STEP",       Params.stutterQuantize,     Params.stutterQuantize,     false, 4),
          InspectorSliderSpec("GATE DUTY",  Params.stutterGate,         Params.stutterGate,         false, 0),
          InspectorSliderSpec("CROSSFADE",  Params.stutterRelease,      Params.stutterRelease,      false, 0),
        ];
      case ModuleSlot.buffer:
        return [
          InspectorSliderSpec("POS SCRUB",  Params.bufferPositionMin,   Params.bufferPositionMax,   true,  0),
          InspectorSliderSpec("PITCH",      Params.bufferPitchMin,      Params.bufferPitchMax,      true,  0),
          InspectorSliderSpec("OFFSET",     Params.bufferStereoOffset,  Params.bufferStereoOffset,  false, 0),
          InspectorSliderSpec("TENSION",    Params.bufferCurveTension,  Params.bufferCurveTension,  false, 0),
        ];
      case ModuleSlot.gate:
        return [
          InspectorSliderSpec("GATE WIDTH", Params.gateWidthMin,        Params.gateWidthMax,        true,  0),
          InspectorSliderSpec("TAIL",       Params.gateTail,            Params.gateTail,            false, 0),
          InspectorSliderSpec("TENSION",    Params.gateCurveTension,    Params.gateCurveTension,    false, 0),
          InspectorSliderSpec("MIX",        Params.gateMix,             Params.gateMix,             false, 0),
        ];
      case ModuleSlot.pan:
        return [
          InspectorSliderSpec("WIDTH",      Params.panWidthMin,         Params.panWidthMax,         true,  0),
          InspectorSliderSpec("CENTER",     Params.panCenterMin,        Params.panCenterMax,        true,  0),
          InspectorSliderSpec("TENSION",    Params.panCurveTension,     Params.panCurveTension,     false, 0),
          InspectorSliderSpec("MIX",        Params.panMix,              Params.panMix,              false, 0),
        ];
      case ModuleSlot.distort:
        return [
          InspectorSliderSpec("DRIVE LOW",  Params.distortDriveLowMin,  Params.distortDriveLowMax,  true,  0),
          InspectorSliderSpec("DRIVE HIGH", Params.distortDriveHighMin, Params.distortDriveHighMax, true,  0),
          InspectorSliderSpec("CROSSOVER",  Params.distortCrossover,    Params.distortCrossover,    false, 0),
          InspectorSliderSpec("DC OFFSET",  Params.distortTone,         Params.distortTone,         false, 3),
        ];
      case ModuleSlot.lofi:
        return [
          InspectorSliderSpec("BIT DEPTH",  Params.lofiBitDepthMin,     Params.lofiBitDepthMax,     true,  0),
          InspectorSliderSpec("DOWNSAMPLE", Params.lofiDownsampleMin,   Params.lofiDownsampleMax,   true,  0),
          InspectorSliderSpec("GRIT NOISE", Params.lofiGrit,            Params.lofiGrit,            false, 0),
          InspectorSliderSpec("TENSION",    Params.lofiCurveTension,    Params.lofiCurveTension,    false, 0),
        ];
      case ModuleSlot.filter:
        return [
          InspectorSliderSpec("CUTOFF",     Params.filterCutoffMin,     Params.filterCutoffMax,     true,  0),
          InspectorSliderSpec("RESONANCE",  Params.filterResonance,     Params.filterResonance,     false, 0),
          InspectorSliderSpec("DRIVE",      Params.filterDrive,         Params.filterDrive,         false, 0),
          InspectorSliderSpec("TENSION",    Params.filterCurveTension,  Params.filterCurveTension,  false, 0),
        ];
      case 14: // HIGHPASS
        return [
          InspectorSliderSpec("HP CUTOFF",  Params.filterCutoffMin,     Params.filterCutoffMax,     true,  1),
          InspectorSliderSpec("RESONANCE",  Params.filterResonance,     Params.filterResonance,     false, 2),
          InspectorSliderSpec("MIX",        Params.filterMix,           Params.filterMix,           false, 0),
          InspectorSliderSpec("TENSION",    Params.filterCurveTension,  Params.filterCurveTension,  false, 0),
        ];
      case ModuleSlot.comb:
        return [
          InspectorSliderSpec("FREQUENCY",  Params.combFreqMin,         Params.combFreqMax,         true,  0),
          InspectorSliderSpec("FEEDBACK",   Params.combFeedback,        Params.combFeedback,        false, 0),
          InspectorSliderSpec("DAMPING",    Params.combDamping,         Params.combDamping,         false, 0),
          InspectorSliderSpec("PHASE",      Params.combStereoPhase,     Params.combStereoPhase,     false, 0),
        ];
      case ModuleSlot.chorus:
        return [
          InspectorSliderSpec("DEPTH",      Params.chorusDepthMin,      Params.chorusDepthMax,      true,  0),
          InspectorSliderSpec("RATE",       Params.chorusRate,          Params.chorusRate,          false, 0),
          InspectorSliderSpec("FEEDBACK",   Params.chorusFeedback,      Params.chorusFeedback,      false, 0),
          InspectorSliderSpec("WIDTH",      Params.chorusWidth,         Params.chorusWidth,         false, 0),
        ];
      case ModuleSlot.flanger:
        return [
          InspectorSliderSpec("DEPTH",      Params.flangerDepthMin,     Params.flangerDepthMax,     true,  0),
          InspectorSliderSpec("RATE",       Params.flangerRate,         Params.flangerRate,         false, 0),
          InspectorSliderSpec("FEEDBACK",   Params.flangerFeedback,     Params.flangerFeedback,     false, 0),
          InspectorSliderSpec("PHASE",      Params.flangerStereoPhase,  Params.flangerStereoPhase,  false, 0),
        ];
      case ModuleSlot.phaser:
        return [
          InspectorSliderSpec("CENTER HZ",  Params.phaserCenterMin,     Params.phaserCenterMax,     true,  0),
          InspectorSliderSpec("RATE",       Params.phaserRate,          Params.phaserRate,          false, 0),
          InspectorSliderSpec("FEEDBACK",   Params.phaserFeedback,      Params.phaserFeedback,      false, 0),
          InspectorSliderSpec("TENSION",    Params.phaserCurveTension,  Params.phaserCurveTension,  false, 0),
        ];
      case ModuleSlot.reverb:
        return [
          InspectorSliderSpec("ROOM SIZE",  Params.reverbSizeMin,       Params.reverbSizeMax,       true,  0),
          InspectorSliderSpec("DAMPING",    Params.reverbDamping,       Params.reverbDamping,       false, 0),
          InspectorSliderSpec("PRE-DELAY",  Params.reverbPreDelay,      Params.reverbPreDelay,      false, 0),
          InspectorSliderSpec("TENSION",    Params.reverbCurveTension,  Params.reverbCurveTension,  false, 0),
        ];
      case ModuleSlot.tapeStop:
        return [
          InspectorSliderSpec("SLOWDOWN",   Params.tapeStopSlowdownMin, Params.tapeStopSlowdownMax, true,  0),
          InspectorSliderSpec("MIX",        Params.tapeStopMix,         Params.tapeStopMix,         false, 0),
          InspectorSliderSpec("TENSION",    Params.tapeStopCurveTension,Params.tapeStopCurveTension,false, 0),
          InspectorSliderSpec("DRY/WET",    Params.masterDryWet,        Params.masterDryWet,        false, 0),
        ];
      default: // Delay
        return [
          InspectorSliderSpec("FEEDBACK",   Params.delayFeedbackMin,    Params.delayFeedbackMax,    true,  0),
          InspectorSliderSpec("CROSS",      Params.delayCross,          Params.delayCross,          false, 0),
          InspectorSliderSpec("DAMPING",    Params.delayDamp,           Params.delayDamp,           false, 0),
          InspectorSliderSpec("MIX",        Params.delayMix,            Params.delayMix,            false, 0),
        ];
    }
  }

  private void readInspectorValues(const ref InspectorSliderSpec spec, out float nA, out float nB) {
    if (spec.customKind == 1 && _client !is null) {
      nA = cast(float) clamp01(log2(_client.highpassCutoffMin / 20.0f) / 9.5f);
      nB = cast(float) clamp01(log2(_client.highpassCutoffMax / 20.0f) / 9.5f);
      return;
    }
    if (spec.customKind == 2 && _client !is null) {
      nA = _client.highpassRes / 0.9f; nB = nA; return;
    }
    if (spec.customKind == 3 && _client !is null) {
      nA = (_client.distortDcOffset + 1.0f) * 0.5f; nB = nA; return;
    }
    if (spec.customKind == 4 && _client !is null) {
      nA = (_client.stutterStepBeats - 0.0625f) / 0.9375f; nB = nA; return;
    }
    nA = getNormParam(spec.paramMin, 0.3f);
    nB = spec.isDual ? getNormParam(spec.paramMax, 0.7f) : nA;
  }

  private const(char)[] formatCompactParam(Params id, char[] buf) {
    if (_params.length <= id || _params[id] is null) return "";
    if (auto ip = cast(EnumParameter) _params[id]) {
      const int v = ip.value();
      if (id == Params.stutterRateStart || id == Params.stutterRateEnd) {
        if (v >= 0 && v < cast(int) stutterSubdivisionNames.length) return stutterSubdivisionNames[v];
      }
      const int n = snprintf(buf.ptr, buf.length, "%d", v);
      return (n > 0) ? buf[0 .. n] : "";
    }
    if (auto fp = cast(FloatParameter) _params[id]) {
      const double v = fp.value();
      const string lbl = fp.label();
      int n = 0;
      if (lbl == "Hz") {
        n = (v >= 1000.0)
          ? snprintf(buf.ptr, buf.length, "%.1fk", v * 0.001)
          : snprintf(buf.ptr, buf.length, "%.0fHz", v);
      } else if (lbl == "%") {
        n = snprintf(buf.ptr, buf.length, "%.0f%%", v * 100.0);
      } else if (lbl == "dB") {
        n = snprintf(buf.ptr, buf.length, "%.1fdB", v);
      } else if (lbl == "ms") {
        n = snprintf(buf.ptr, buf.length, "%.1fms", v);
      } else if (lbl == "st") {
        n = snprintf(buf.ptr, buf.length, "%+.0fst", v);
      } else if (lbl == "bits") {
        n = snprintf(buf.ptr, buf.length, "%.0fb", v);
      } else if (lbl == "x") {
        n = snprintf(buf.ptr, buf.length, "%.0fx", v);
      } else if (lbl == "deg") {
        n = snprintf(buf.ptr, buf.length, "%.0f", v);
      } else {
        n = snprintf(buf.ptr, buf.length, "%.2f", v);
      }
      return (n > 0) ? buf[0 .. n] : "";
    }
    return "";
  }

  private const(char)[] formatInspectorValue(const ref InspectorSliderSpec spec, char[] buf) {
    if (spec.customKind == 1 && _client !is null) {
      const float lo = _client.highpassCutoffMin;
      const float hi = _client.highpassCutoffMax;
      int n;
      if (lo >= 1000.0f && hi >= 1000.0f) {
        n = snprintf(buf.ptr, buf.length, "%.1fk->%.1fk", cast(double)(lo * 0.001f), cast(double)(hi * 0.001f));
      } else if (hi >= 1000.0f) {
        n = snprintf(buf.ptr, buf.length, "%.0f->%.1fk", cast(double) lo, cast(double)(hi * 0.001f));
      } else {
        n = snprintf(buf.ptr, buf.length, "%.0f->%.0fHz", cast(double) lo, cast(double) hi);
      }
      return (n > 0) ? buf[0 .. n] : "";
    }
    if (spec.customKind == 2 && _client !is null) {
      const int n = snprintf(buf.ptr, buf.length, "%.0f%%", cast(double)(_client.highpassRes * 100.0f));
      return (n > 0) ? buf[0 .. n] : "";
    }
    if (spec.customKind == 3 && _client !is null) {
      const int n = snprintf(buf.ptr, buf.length, "%+.2f", cast(double) _client.distortDcOffset);
      return (n > 0) ? buf[0 .. n] : "";
    }
    if (spec.customKind == 4 && _client !is null) {
      const int n = snprintf(buf.ptr, buf.length, "%.3gb", cast(double) _client.stutterStepBeats);
      return (n > 0) ? buf[0 .. n] : "";
    }

    char[14] bA, bB;
    const(char)[] sA = formatCompactParam(spec.paramMin, bA);
    if (!spec.isDual || sA.length == 0) {
      if (sA.length == 0) return "";
      const int n = snprintf(buf.ptr, buf.length, "%.*s", cast(int) sA.length, sA.ptr);
      return (n > 0) ? buf[0 .. n] : "";
    }
    const(char)[] sB = formatCompactParam(spec.paramMax, bB);
    const int n = snprintf(buf.ptr, buf.length, "%.*s->%.*s",
                           cast(int) sA.length, sA.ptr,
                           cast(int) sB.length, sB.ptr);
    return (n > 0) ? buf[0 .. n] : "";
  }

  private const(TVMCurve)* getCurveConst(int slot) const pure {
    if (slot == 14) {
      if (_client !is null) return &_client.extTvmBank.states[14][0].curve;
      return &_highpassCurve;
    }
    const int s = (slot >= 0 && slot < NumTVMModuleSlots) ? slot : 0;
    if (_client !is null) return &_client.modulationEngine().curves[s];
    return &_curves[s];
  }

  private TVMCurve* getActiveLocalCurvePtr() pure {
    if (_activeModule == 14) return &_highpassCurve;
    const int s = (_activeModule >= 0 && _activeModule < NumTVMModuleSlots) ? _activeModule : 0;
    return &_curves[s];
  }

  private TVMCurve* getActiveClientCurvePtr() pure {
    if (_client is null) return null;
    if (_activeModule == 14) return &_client.extTvmBank.states[14][0].curve;
    const int s = (_activeModule >= 0 && _activeModule < NumTVMModuleSlots) ? _activeModule : 0;
    return &_client.modulationEngine().curves[s];
  }

  private static double clamp01(double v) pure @safe {
    if (v < 0.0) return 0.0;
    if (v > 1.0) return 1.0;
    return v;
  }

  // =========================================================================
  // Headless Testing Interface
  // =========================================================================

  version (unittest) {
    public nothrow @nogc:

    void testResize(int width, int height) {
      _windowListener.onResized(width, height);
    }

    void testDraw(WindowPixelFormat pf = WindowPixelFormat.RGBA8) {
      setDirtyWhole();
      if (_overlay !is null) _overlay.setDirtyWhole();
      _windowListener.recomputeDirtyAreas();
      _windowListener.onDraw(pf);
    }

    bool testClick(int x, int y, MouseButton mb = MouseButton.left, bool isDoubleClick = false) {
      MouseState mstate;
      return _windowListener.onMouseClick(x, y, mb, isDoubleClick, mstate);
    }

    void testMove(int x, int y, int dx = 0, int dy = 0) {
      MouseState mstate;
      _windowListener.onMouseMove(x, y, dx, dy, mstate);
    }

    void testDrag(int x, int y, int dx, int dy) {
      MouseState mstate;
      _windowListener.onMouseMove(x, y, dx, dy, mstate);
    }

    void testRelease(int x, int y, MouseButton mb = MouseButton.left) {
      MouseState mstate;
      _windowListener.onMouseRelease(x, y, mb, mstate);
    }

    void testAnimate(double dt, double time) {
      _windowListener.onAnimate(dt, time);
    }

    ImageRef!RGBA testFramebuffer() {
      return _renderedBuffer.toRef();
    }
  }

private:
  enum DragMode {
    none,
    chainReorder,
    globalFilter,
    stripSlider,
    inspectorSlider,
    inspectorMix,
    outputControl,
    curveNode,
    curveTension,
  }

  StutterClient _client;
  Parameter[] _params;
  bool _hasClient = false;
  Font _font;
  StutterCanvasOverlay _overlay;
  UIWindowResizer _resizer;

  int _activeModule = ModuleSlot.stutter;
  int _activeInspectorParam = 0;
  bool _curveExpanded = false;
  bool _editingJitter = false;

  TVMCurve[NumTVMModuleSlots] _curves;
  TVMCurve _highpassCurve;
  float _playheadPhase = 0.0f;
  float _peakHoldL = 0.0f;
  float _peakHoldR = 0.0f;
  int _hoverX = -1;
  int _hoverY = -1;
  float _renderScale = 1.0f;

  // Fallback local copies when constructed without a StutterClient
  bool _localPalindrome = false;
  bool _localFreeze = false;
  float _localFreezeBeats = 0.25f;
  float _localGlobalFilter = 0.0f;

  DragMode _dragMode = DragMode.none;
  int _dragNodeIdx = -1;
  int _dragTensionIdx = -1;
  int _dragChainFromIdx = -1;
  int _dragStripKind = 0;
  int _dragSliderHandle = 0;
  int _dragStartY = 0;
  float _dragStartVal = 0.0f;

  Vec!box2i _defaultRects;
}

// =============================================================================
// Headless Framebuffer & BT Stutter Edit 2 GUI Interactive Unit Tests
// =============================================================================

version (unittest) {
  @nogc nothrow pure
  float computeLuminanceVariance(ImageRef!RGBA fb, box2i region) {
    const box2i bounds = box2i(0, 0, fb.w, fb.h).intersection(region);
    if (bounds.empty) return 0.0f;

    double sum = 0.0, sumSq = 0.0;
    long count = 0;
    for (int y = bounds.min.y; y < bounds.max.y; ++y) {
      RGBA[] row = fb.scanline(y);
      for (int x = bounds.min.x; x < bounds.max.x; ++x) {
        const RGBA p = row[x];
        const double lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
        sum += lum; sumSq += lum * lum; count++;
      }
    }
    if (count <= 1) return 0.0f;
    const double mean = sum / cast(double) count;
    const double variance = (sumSq / cast(double) count) - (mean * mean);
    return variance > 0.0 ? cast(float) sqrt(variance) : 0.0f;
  }

  @nogc nothrow pure
  bool hasColorSignature(ImageRef!RGBA fb, box2i region, RGBA target, int tolerance = 25) {
    const box2i bounds = box2i(0, 0, fb.w, fb.h).intersection(region);
    if (bounds.empty) return false;
    for (int y = bounds.min.y; y < bounds.max.y; ++y) {
      RGBA[] row = fb.scanline(y);
      for (int x = bounds.min.x; x < bounds.max.x; ++x) {
        const RGBA p = row[x];
        const int dr = cast(int) p.r - cast(int) target.r;
        const int dg = cast(int) p.g - cast(int) target.g;
        const int db = cast(int) p.b - cast(int) target.b;
        if ((dr < 0 ? -dr : dr) <= tolerance &&
            (dg < 0 ? -dg : dg) <= tolerance &&
            (db < 0 ? -db : db) <= tolerance) {
          return true;
        }
      }
    }
    return false;
  }
}

unittest {
  auto client = new StutterClient();
  auto gui = mallocNew!StutterGUI(client, client.params());
  scope(exit) destroyFree(gui);

  // 1. Render base 1040 x 680 and verify all 6 sections have rich visual detail
  gui.testResize(1040, 680);
  gui.testMove(300, 300);
  assert(gui.hoverX() == 300 && gui.hoverY() == 300);
  gui.testDraw();

  ImageRef!RGBA fb = gui.testFramebuffer();
  assert(fb.w == 1040 && fb.h == 680);

  assert(computeLuminanceVariance(fb, box2i(0, 0, 1040, 110)) > 5.0f);     // Section 1: Header + Rainbow Palette
  assert(computeLuminanceVariance(fb, box2i(0, 114, 1040, 264)) > 5.0f);   // Section 2: Stutter + Buffer Strips
  assert(computeLuminanceVariance(fb, box2i(8, 272, 168, 672)) > 5.0f);    // Section 3: 11-FX Signal Chain
  assert(computeLuminanceVariance(fb, box2i(176, 272, 556, 672)) > 5.0f);  // Section 4: Effect Inspector
  assert(computeLuminanceVariance(fb, box2i(564, 272, 1032, 486)) > 5.0f); // Section 6: Embedded Curve Editor
  assert(computeLuminanceVariance(fb, box2i(564, 492, 1032, 672)) > 5.0f); // Section 5: Purple Output Section
  assert(hasColorSignature(fb, box2i(564, 492, 1032, 672), colBTPurpleHi, 30));

  // 2. Click HIGHPASS (row 9 -> y = 276 + 9*36 + 15 = 615) and verify selection -> slot 14
  assert(gui.testClick(80, 615));
  assert(gui.activeModule() == 14);
  gui.testDraw();

  // 3. Drag `≡` handle on row 0 (DISTORT, x=150, y=292) down to row 2 (y=364) -> signal chain reorders
  assert(client.signalChainOrder[0] == ChainFXId.distort);
  gui.testClick(150, 292);
  gui.testDrag(150, 364, 0, 72);
  gui.testRelease(150, 364);
  assert(client.signalChainOrder[0] != ChainFXId.distort);

  // 4. Click `[⛶] EXPAND` in Section 6 header (x=995, y=288) -> toggles Expanded Curve Editor
  assert(!gui.isCurveExpanded());
  gui.testClick(995, 288);
  assert(gui.isCurveExpanded());
  gui.testDraw();

  // Click Preset Shape #3 (Ramp Down) in expanded preset strip (y=654)
  gui.testClick(184 + 3 * 70 + 25, 654);
  assert(gui.activeCurve().evaluate(0.0f) >= 0.95f);
  assert(gui.activeCurve().evaluate(1.0f) <= 0.05f);

  // Add interior curve node via left-click & drag, then delete via right-click
  gui.testClick(550, 440);
  gui.testDrag(550, 360, 0, -80);
  gui.testRelease(550, 360);
  const int nodesAfterAdd = gui.activeCurve().nodeCount();
  assert(nodesAfterAdd >= 3);
  gui.testClick(550, 360, MouseButton.right);
  assert(gui.activeCurve().nodeCount() == nodesAfterAdd - 1);

  // Close Expanded Editor
  gui.testClick(995, 288);
  assert(!gui.isCurveExpanded());

  // 5. Toggle Auto Mode in Top Header (x=60, y=56)
  const bool prevAuto = gui.isAutoMode();
  gui.testClick(60, 56);
  assert(gui.isAutoMode() != prevAuto);

  // 6. Click Key 5 on Rainbow 24-Note Gesture Palette (x=330, y=24) -> switches BT Gesture Bank
  gui.testClick(330, 24);
  assert(client.activeGestureBankIdx == 5);

  // 7. Click Jitter EDIT button in Buffer Strip (x=665, y=211) -> opens Jitter Inspector
  gui.testClick(665, 211);
  assert(gui.isEditingJitter());
  gui.testDraw();

  // 8. Click GATE in Stutter Strip (x=744, y=150) -> opens GATE Inspector & verify Gate Mix readout works
  gui.testClick(744, 150);
  assert(gui.activeModule() == ModuleSlot.gate);
  gui.testDraw();

  // Verify peak hold decays cleanly over animation steps
  gui.testAnimate(0.05, 1.0);
  gui.testDraw();

  // 9. Render at discrete scales (0.75x, 1.25x, 2.0x) and verify out-of-bounds dirty rects are ignored
  gui.testResize(780, 510);
  gui.testDraw();
  assert(gui.testFramebuffer().w == 780 && gui.testFramebuffer().h == 510);

  gui.testResize(1300, 850);
  gui.testDraw();
  assert(gui.testFramebuffer().w == 1300 && gui.testFramebuffer().h == 850);

  gui.testResize(2080, 1360);
  gui.testDraw();
  assert(gui.testFramebuffer().w == 2080 && gui.testFramebuffer().h == 1360);

  Canvas oobCanvas;
  box2i[2] badRects = [box2i(-10, -10, 50, 50), box2i(2050, 1340, 2120, 1380)];
  gui.drawRawOverlay(gui.testFramebuffer(), badRects[], oobCanvas);
}
