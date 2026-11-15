/**
 * Custom Interactive GUI for kdr-stutter closely matching iZotope Stutter Edit 2.
 *
 * Implements the 3-zone dark-slate iZotope interface (`1040 x 680` base resolution):
 * - Top Header & Gesture Bar: Logo, Auto/MIDI Mode toggle, Bank/Preset selector,
 *   12-Key Mini MIDI Keyboard / Gesture Strip, Grid/Duration & Release selectors,
 *   Master Dry/Wet Mix, Limiter toggle + Gain Reduction meter, and Stereo Peak Meters.
 * - Left Column Signal-Chain Module Rack: Fixed STUTTER & BUFFER slots, 11 FX module
 *   slots (GATE, PAN, TAPE STOP, FILTER, LO-FI, DISTORT, COMB, CHORUS, FLANGER,
 *   PHASER, REVERB), fixed DELAY slot, and LIMITER summary bar, each with glowing
 *   color-coded accent bars, power toggles, titles, and click-to-select focus.
 * - Center/Right Workspace: Selected Module Parameter Sub-Panel (min/max modulation
 *   range bars, secondary controls, curve tension) and Large Central TVM Curve Editor
 *   with beat-subdivision grid, glowing module-colored curve & shaded fill, draggable
 *   breakpoint nodes, live animated gesture playhead, and 12 Preset Curve Shape buttons.
 *
 * Copyright: kdr 2026.
 * License: Boost License 1.0.
 */
module kdr.stutter.gui;

import std.math : isNaN, isInfinity;
import core.math : cos, sin, fabs, sqrt;

import dplug.core : mallocNew, destroyFree, Vec, makeVec;
import dplug.client : Client, Parameter, IParameterListener, BoolParameter,
  IntegerParameter, FloatParameter, EnumParameter;
import dplug.math : vec2f, box2i, rectangle;
import dplug.gui : GUIGraphics, UIElement, UIContext, Click, MouseButton,
  MouseState, WindowPixelFormat, flagPBR, flagRaw, flagAnimated;
import dplug.graphics : RGBA, L16, Font, ImageRef, cropImageRef, fillAll, toRef;
import dplug.canvas : Canvas;
import dplug.pbrwidgets : UILabel;
import dplug.flatwidgets : UIWindowResizer, makeSizeConstraintsDiscrete;

import kdr.stutter.params;
import kdr.stutter.tvm : TVMCurve, CurveNode, CurveType, NumTVMModuleSlots;
import kdr.stutter.presets : NUM_FACTORY_PRESETS, factoryPresetNames, applyFactoryPreset;
import kdr.stutter.client : StutterClient;

private static string fontRaw = import("FORCED SQUARE.ttf");

// =============================================================================
// Visual Style & Palette (iZotope Stutter Edit 2 Dark Charcoal & Neon Accents)
// =============================================================================

enum int BASE_WIDTH  = 1040;
enum int BASE_HEIGHT = 680;
enum int HEADER_H    = 72;
enum int RACK_W      = 230;

enum RGBA bgRoot         = RGBA(18, 21, 27, 255);    // #12151b
enum RGBA bgHeader       = RGBA(22, 26, 34, 255);    // #161a22
enum RGBA bgRackSlot     = RGBA(25, 30, 40, 255);    // #191e28
enum RGBA bgRackSelected = RGBA(36, 45, 62, 255);    // #242d3e
enum RGBA bgWorkspace    = RGBA(20, 24, 32, 255);    // #141820
enum RGBA bgTVMGrid      = RGBA(14, 17, 23, 255);    // #0e1117
enum RGBA borderDim      = RGBA(45, 53, 68, 255);    // #2d3544
enum RGBA borderBright   = RGBA(80, 95, 120, 255);   // #505f78
enum RGBA textBright     = RGBA(240, 244, 250, 255);
enum RGBA textMuted      = RGBA(135, 150, 170, 255);
enum RGBA playheadColor  = RGBA(255, 255, 255, 230);

/// Converts 24-bit hex RGB color (`0xRRGGBB`) from `moduleColors` to `RGBA`.
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

/// Safe parameter mutation helper that works both with a live Client and standalone Parameter[]
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

/// Returns the enable parameter ID for a given ModuleSlot (0..14).
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

/// Returns the TVM curve preset parameter ID for a given ModuleSlot (0..13).
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

/// Returns the TVM curve tension parameter ID for a given ModuleSlot (0..13).
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

/// Returns the Min and Max range parameter IDs for a given ModuleSlot.
@nogc nothrow pure @safe
void moduleRangeParams(int slot, out Params minParam, out Params maxParam, out Params auxParam) {
  switch (slot) {
    case ModuleSlot.stutter:
      minParam = Params.stutterRateStart;
      maxParam = Params.stutterRateEnd;
      auxParam = Params.stutterQuantize;
      break;
    case ModuleSlot.buffer:
      minParam = Params.bufferPositionMin;
      maxParam = Params.bufferPositionMax;
      auxParam = Params.bufferDirection;
      break;
    case ModuleSlot.gate:
      minParam = Params.gateWidthMin;
      maxParam = Params.gateWidthMax;
      auxParam = Params.gateSubdivision;
      break;
    case ModuleSlot.pan:
      minParam = Params.panCenterMin;
      maxParam = Params.panCenterMax;
      auxParam = Params.panMix;
      break;
    case ModuleSlot.tapeStop:
      minParam = Params.tapeStopSlowdownMin;
      maxParam = Params.tapeStopSlowdownMax;
      auxParam = Params.tapeStopMix;
      break;
    case ModuleSlot.filter:
      minParam = Params.filterCutoffMin;
      maxParam = Params.filterCutoffMax;
      auxParam = Params.filterResonance;
      break;
    case ModuleSlot.lofi:
      minParam = Params.lofiBitDepthMin;
      maxParam = Params.lofiBitDepthMax;
      auxParam = Params.lofiGrit;
      break;
    case ModuleSlot.distort:
      minParam = Params.distortDriveLowMax;
      maxParam = Params.distortDriveHighMax;
      auxParam = Params.distortCrossover;
      break;
    case ModuleSlot.comb:
      minParam = Params.combFreqMin;
      maxParam = Params.combFreqMax;
      auxParam = Params.combFeedback;
      break;
    case ModuleSlot.chorus:
      minParam = Params.chorusDepthMin;
      maxParam = Params.chorusDepthMax;
      auxParam = Params.chorusRate;
      break;
    case ModuleSlot.flanger:
      minParam = Params.flangerDepthMin;
      maxParam = Params.flangerDepthMax;
      auxParam = Params.flangerFeedback;
      break;
    case ModuleSlot.phaser:
      minParam = Params.phaserCenterMin;
      maxParam = Params.phaserCenterMax;
      auxParam = Params.phaserFeedback;
      break;
    case ModuleSlot.reverb:
      minParam = Params.reverbSizeMin;
      maxParam = Params.reverbSizeMax;
      auxParam = Params.reverbDamping;
      break;
    case ModuleSlot.delay:
      minParam = Params.delayFeedbackMin;
      maxParam = Params.delayFeedbackMax;
      auxParam = Params.delayMix;
      break;
    default:
      minParam = Params.limiterThreshold;
      maxParam = Params.limiterCeiling;
      auxParam = Params.limiterRelease;
      break;
  }
}

// =============================================================================
// Interactive Workspace & TVM Curve Editor Overlay (Raw Canvas Layer)
// =============================================================================

class StutterCanvasOverlay : UIElement {
public:
  @nogc nothrow:

  this(UIContext context, StutterGUI host) {
    super(context, flagRaw | flagAnimated);
    _host = host;
  }

  override Click onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate) {
    return _host.handleWorkspaceClick(x, y, button, isDoubleClick);
  }

  override void onMouseDrag(int x, int y, int dx, int dy, MouseState mstate) {
    _host.handleWorkspaceDrag(x, y, dx, dy);
  }

  override void onStopDrag() {
    _host.handleWorkspaceStopDrag();
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

    // Initialize local TVM curves for all 14 module slots
    for (int i = 0; i < NumTVMModuleSlots; ++i) {
      int presetId = TVMCurvePreset.rampUp;
      if (_params.length > moduleCurveParam(i)) {
        if (auto ip = cast(IntegerParameter) _params[moduleCurveParam(i)]) {
          presetId = ip.value();
        }
      }
      _curves[i].loadPreset(presetId);
    }

    foreach (p; _params) {
      if (p !is null) p.addListener(this);
    }

    buildLabelsAndWidgets();

    // Add full-screen interactive Canvas overlay for TVM curve editor, meters, and controls
    _overlay = mallocNew!StutterCanvasOverlay(context, this);
    _overlay.position = rectangle(0, 0, BASE_WIDTH, BASE_HEIGHT);
    addChild(_overlay);

    // Add corner window resizer
    _resizer = mallocNew!UIWindowResizer(context);
    _resizer.position = rectangle(BASE_WIDTH - 18, BASE_HEIGHT - 18, 18, 18);
    addChild(_resizer);

    // Record default rects and text sizes for DPI scaling
    _defaultRects = makeVec!box2i(_children.length);
    _defaultTextSizes = makeVec!float(_children.length);
    foreach (i, child; _children) {
      _defaultRects[i] = child.position;
      if (auto lbl = cast(UILabel) child) {
        _defaultTextSizes[i] = lbl.textSize;
      }
    }

    syncLabels();
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

  // --- Public State Accessors for Inspection & Unit Tests ---
  int activeModule() const pure { return _activeModule; }

  void setActiveModule(int slot) {
    if (slot < 0) slot = 0;
    if (slot > ModuleSlot.limiter) slot = ModuleSlot.limiter;
    _activeModule = slot;
    syncLabels();
    setDirtyWhole();
    if (_overlay !is null) _overlay.setDirtyWhole();
  }

  ref inout(TVMCurve) activeCurve() inout return pure {
    const int slot = (_activeModule >= 0 && _activeModule < NumTVMModuleSlots)
      ? _activeModule
      : 0;
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

  // --- IParameterListener overrides ---
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
    syncLabels();
    setDirtyWhole();
    if (_overlay !is null) _overlay.setDirtyWhole();
  }

  override void onBeginParameterEdit(Parameter sender) {}
  override void onEndParameterEdit(Parameter sender) {}
  override void onBeginParameterHover(Parameter sender) {}
  override void onEndParameterHover(Parameter sender) {}

  // --- Layout Reflow ---
  override void reflow() {
    super.reflow();
    const float scale = (position.width > 0)
      ? (cast(float) position.width / cast(float) BASE_WIDTH)
      : 1.0f;
    foreach (i, child; _children) {
      child.position = _defaultRects[i].scaleByFactor(scale);
      if (auto lbl = cast(UILabel) child) {
        lbl.textSize = _defaultTextSizes[i] * scale;
      }
    }
  }

  // --- PBR Layer Drawing (Panels, Borders, Rack Slots, Keyboard & Header) ---
  override void onDrawPBR(
      ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap,
      ImageRef!RGBA materialMap, box2i[] dirtyRects) nothrow @nogc {
    const float scale = (position.width > 0)
      ? (cast(float) position.width / cast(float) BASE_WIDTH)
      : 1.0f;

    foreach (dirty; dirtyRects) {
      ImageRef!RGBA diff = diffuseMap.cropImageRef(dirty);
      ImageRef!L16 dep   = depthMap.cropImageRef(dirty);
      ImageRef!RGBA mat  = materialMap.cropImageRef(dirty);

      // 1. Root dark background
      diff.fillAll(bgRoot);
      dep.fillAll(L16(0));
      mat.fillAll(RGBA(0, 0, 0, 0));

      // 2. Top Header Bar (0, 0, 1040, 72)
      fillScaledBox(diff, dirty, scale, rectangle(0, 0, BASE_WIDTH, HEADER_H), bgHeader);
      fillScaledBox(diff, dirty, scale, rectangle(0, HEADER_H - 2, BASE_WIDTH, 2), borderDim);

      // Header Auto/MIDI Box (12, 10, 180, 52)
      const bool autoOn = isAutoMode();
      const RGBA autoAccent = autoOn ? RGBA(0, 229, 255, 255) : RGBA(255, 170, 0, 255);
      drawScaledBorderedBox(diff, dirty, scale, rectangle(12, 10, 180, 52),
                            RGBA(28, 34, 46, 255), autoAccent, 2);
      fillScaledBox(diff, dirty, scale, rectangle(16, 14, 6, 44), autoAccent);

      // Header Bank / Preset Selector Box (200, 12, 160, 48)
      drawScaledBorderedBox(diff, dirty, scale, rectangle(200, 12, 160, 48),
                            RGBA(26, 31, 42, 255), borderBright, 1);
      fillScaledBox(diff, dirty, scale, rectangle(202, 14, 24, 44), RGBA(36, 44, 58, 255));
      fillScaledBox(diff, dirty, scale, rectangle(334, 14, 24, 44), RGBA(36, 44, 58, 255));

      // Header 12-Key Mini Keyboard / Gesture Strip (370, 14, 240, 44)
      drawScaledBorderedBox(diff, dirty, scale, rectangle(370, 14, 240, 44),
                            RGBA(14, 17, 23, 255), borderBright, 1);
      int activeGest = 0;
      if (_params.length > Params.activeGesture) {
        if (auto ip = cast(IntegerParameter) _params[Params.activeGesture]) {
          activeGest = ip.value() % 12;
        }
      }
      for (int k = 0; k < 12; ++k) {
        const int kx = 372 + k * 20;
        const bool isBlack = (k == 1 || k == 3 || k == 6 || k == 8 || k == 10);
        const bool isSel = (k == activeGest);
        const RGBA keyCol = isSel
          ? moduleAccentRGBA(k % 14)
          : (isBlack ? RGBA(28, 33, 44, 255) : RGBA(62, 72, 90, 255));
        fillScaledBox(diff, dirty, scale, rectangle(kx, 16, 18, 40), keyCol);
        fillScaledBox(diff, dirty, scale, rectangle(kx + 2, 50, 14, 4), moduleAccentRGBA(k % 14));
      }

      // Header Timing Grid & Release Selector Box (620, 12, 170, 48)
      drawScaledBorderedBox(diff, dirty, scale, rectangle(620, 12, 170, 22),
                            RGBA(26, 31, 42, 255), borderDim, 1);
      drawScaledBorderedBox(diff, dirty, scale, rectangle(620, 38, 170, 22),
                            RGBA(26, 31, 42, 255), borderDim, 1);

      // Header Master Mix, Limiter & Meters Box (800, 8, 230, 56)
      drawScaledBorderedBox(diff, dirty, scale, rectangle(800, 10, 228, 52),
                            RGBA(24, 29, 39, 255), borderDim, 1);

      // 3. Left Column Signal-Chain Module Rack (0, 72, 230, 608)
      fillScaledBox(diff, dirty, scale, rectangle(0, HEADER_H, RACK_W, BASE_HEIGHT - HEADER_H),
                    RGBA(16, 19, 25, 255));
      fillScaledBox(diff, dirty, scale, rectangle(RACK_W - 1, HEADER_H, 1, BASE_HEIGHT - HEADER_H),
                    borderDim);

      for (int slot = 0; slot <= ModuleSlot.limiter; ++slot) {
        const box2i sRect = slotRect(slot);
        const bool selected = (_activeModule == slot);
        const bool enabled  = isModuleEnabled(slot);
        const RGBA accent   = moduleAccentRGBA(slot);
        const RGBA slotBg   = selected ? bgRackSelected : bgRackSlot;
        const RGBA borderC  = selected ? accent : borderDim;

        drawScaledBorderedBox(diff, dirty, scale, sRect, slotBg, borderC, selected ? 2 : 1);
        // Left color-coded accent bar
        fillScaledBox(diff, dirty, scale,
                      rectangle(sRect.min.x + 2, sRect.min.y + 2, 5, sRect.height - 4),
                      accent);
        // Power toggle LED button
        const RGBA pwrCol = enabled ? accent : RGBA(45, 52, 65, 255);
        drawScaledBorderedBox(diff, dirty, scale,
                              rectangle(sRect.min.x + 12, sRect.min.y + (sRect.height - 16) / 2, 16, 16),
                              pwrCol, borderBright, 1);
      }

      // 4. Center/Right Workspace Containers
      // Parameter Sub-Panel (236, 76, 800, 134)
      const RGBA activeAccent = moduleAccentRGBA(_activeModule);
      drawScaledBorderedBox(diff, dirty, scale, rectangle(236, 76, 796, 134),
                            bgWorkspace, activeAccent, 1);
      fillScaledBox(diff, dirty, scale, rectangle(236, 76, 796, 4), activeAccent);

      // TVM Curve Editor Frame (236, 216, 796, 414)
      drawScaledBorderedBox(diff, dirty, scale, rectangle(236, 216, 796, 414),
                            bgTVMGrid, borderBright, 1);

      // 12 Preset Curve Shape Bar (236, 634, 796, 40)
      drawScaledBorderedBox(diff, dirty, scale, rectangle(236, 634, 796, 40),
                            bgHeader, borderDim, 1);
    }
  }

  // ===========================================================================
  // Raw Canvas Overlay Drawing (TVM Curve, Grid, Nodes, Preset Icons, Sliders)
  // ===========================================================================

  void drawRawOverlay(ImageRef!RGBA rawMap, box2i[] dirtyRects, ref Canvas canvas) {
    const float scale = (position.width > 0)
      ? (cast(float) position.width / cast(float) BASE_WIDTH)
      : 1.0f;
    const RGBA accent = moduleAccentRGBA(_activeModule);
    const RGBA accentFill = moduleAccentRGBA(_activeModule, 75);

    foreach (ref rect; dirtyRects) {
      ImageRef!RGBA cropped = rawMap.cropImageRef(rect);
      canvas.initialize(cropped);
      canvas.translate(-rect.min.x, -rect.min.y);
      canvas.scale(scale, scale);

      // --- 1. Header Right: Master Mix Bar, Limiter GR & Stereo Meters ---
      drawHeaderMetersAndMix(canvas);

      // --- 2. Parameter Sub-Panel (236, 76, 796, 134): Interactive Range & Value Bars ---
      drawParameterSubPanelBars(canvas, accent);

      // --- 3. Large TVM Curve Editor (236, 216, 796, 414) ---
      drawTVMCurveEditor(canvas, accent, accentFill);

      // --- 4. 12 Curve Preset Shape Bar (236, 634, 796, 40) ---
      drawPresetShapeBar(canvas, accent);
    }
  }

  // ===========================================================================
  // Interactive Mouse & Animation Handlers
  // ===========================================================================

  Click handleWorkspaceClick(int rawX, int rawY, int button, bool isDoubleClick) {
    const float scale = (position.width > 0)
      ? (cast(float) position.width / cast(float) BASE_WIDTH)
      : 1.0f;
    const int x = cast(int)(cast(float) rawX / scale);
    const int y = cast(int)(cast(float) rawY / scale);

    _dragMode = DragMode.none;
    _dragNodeIdx = -1;

    // 1. Top Header Interactions (y in 0..72)
    if (y >= 0 && y < HEADER_H) {
      // A. Auto/MIDI Mode Toggle (x in 12..192)
      if (x >= 12 && x <= 192) {
        if (_params.length > Params.autoMode) {
          setBoolParamSafe(_params[Params.autoMode], _hasClient, !isAutoMode());
          syncLabels();
          setDirtyWhole();
          return Click.handled;
        }
      }
      // B. Bank / Preset Selector (x in 200..360)
      if (x >= 200 && x <= 360) {
        if (_params.length > Params.bankPreset) {
          if (auto ip = cast(IntegerParameter) _params[Params.bankPreset]) {
            int cur = ip.value();
            if (x < 240) {
              cur = (cur - 1 + NUM_FACTORY_PRESETS) % NUM_FACTORY_PRESETS;
            } else {
              cur = (cur + 1) % NUM_FACTORY_PRESETS;
            }
            setIntParamSafe(ip, _hasClient, cur);
            applyFactoryPreset(_params, cur);
            syncLabels();
            setDirtyWhole();
            return Click.handled;
          }
        }
      }
      // C. 12-Key Mini Keyboard / Gesture Strip (x in 370..610)
      if (x >= 370 && x <= 610) {
        int keyIdx = (x - 370) / 20;
        if (keyIdx < 0) keyIdx = 0;
        if (keyIdx > 11) keyIdx = 11;
        if (_params.length > Params.activeGesture) {
          setIntParamSafe(_params[Params.activeGesture], _hasClient, keyIdx);
          syncLabels();
          setDirtyWhole();
          return Click.handled;
        }
      }
      // D. Timing Grid / Gesture Length & Release Mode (x in 620..790)
      if (x >= 620 && x <= 790) {
        if (y < 36) {
          if (auto ip = cast(IntegerParameter) _params[Params.gestureLength]) {
            int next = (ip.value() + 1) % (ip.maxValue() + 1);
            setIntParamSafe(ip, _hasClient, next);
          }
        } else {
          if (auto ip = cast(IntegerParameter) _params[Params.releaseMode]) {
            int next = (ip.value() + 1) % (ip.maxValue() + 1);
            setIntParamSafe(ip, _hasClient, next);
          }
        }
        syncLabels();
        setDirtyWhole();
        return Click.handled;
      }
      // E. Master Mix & Limiter Toggle (x in 800..1030)
      if (x >= 800 && x <= 885) {
        const double norm = cast(double)(x - 804) / 76.0;
        setNormParamSafe(_params[Params.masterDryWet], _hasClient, norm);
        setDirtyWhole();
        return Click.handled;
      }
      if (x > 885 && x <= 960) {
        if (auto bp = cast(BoolParameter) _params[Params.limiterEnable]) {
          setBoolParamSafe(bp, _hasClient, !bp.value());
          setDirtyWhole();
          return Click.handled;
        }
      }
      return Click.handled;
    }

    // 2. Left Column Module Rack (x in 0..230, y >= 72)
    if (x >= 0 && x < RACK_W && y >= HEADER_H) {
      for (int slot = 0; slot <= ModuleSlot.limiter; ++slot) {
        const box2i r = slotRect(slot);
        if (y >= r.min.y && y < r.max.y) {
          // If clicked on power toggle area (x < 36), toggle module enable
          if (x < 36) {
            const Params enParam = moduleEnableParam(slot);
            if (auto bp = cast(BoolParameter) _params[enParam]) {
              setBoolParamSafe(bp, _hasClient, !bp.value());
            }
          }
          setActiveModule(slot);
          return Click.handled;
        }
      }
      return Click.handled;
    }

    // 3. Parameter Sub-Panel Sliders (x in 236..1032, y in 76..210)
    if (x >= 236 && x <= 1032 && y >= 76 && y <= 210) {
      // Power toggle button in sub-panel header (x in 940..1020, y in 82..110)
      if (x >= 940 && y <= 112) {
        const Params enParam = moduleEnableParam(_activeModule);
        if (auto bp = cast(BoolParameter) _params[enParam]) {
          setBoolParamSafe(bp, _hasClient, !bp.value());
          syncLabels();
          setDirtyWhole();
          return Click.handled;
        }
      }
      updateSubPanelSliderAt(x, y);
      _dragMode = DragMode.subPanelSlider;
      return Click.startDrag;
    }

    // 4. Large TVM Curve Editor (x in 236..1032, y in 216..630)
    if (x >= 236 && x <= 1032 && y >= 216 && y <= 630) {
      return handleCurveEditorClick(x, y, isDoubleClick);
    }

    // 5. 12 Preset Curve Shape Bar (x in 236..1032, y in 634..676)
    if (x >= 236 && x <= 1032 && y >= 634 && y <= 678) {
      int shapeIdx = (x - 240) / 65;
      if (shapeIdx < 0) shapeIdx = 0;
      if (shapeIdx >= 12) shapeIdx = 11;
      applyCurvePresetToActiveModule(shapeIdx);
      return Click.handled;
    }

    return Click.unhandled;
  }

  void handleWorkspaceDrag(int rawX, int rawY, int dx, int dy) {
    const float scale = (position.width > 0)
      ? (cast(float) position.width / cast(float) BASE_WIDTH)
      : 1.0f;
    const int x = cast(int)(cast(float) rawX / scale);
    const int y = cast(int)(cast(float) rawY / scale);

    if (_dragMode == DragMode.subPanelSlider) {
      updateSubPanelSliderAt(x, y);
    } else if (_dragMode == DragMode.curveNode) {
      updateCurveNodeDrag(x, y);
    }
  }

  void handleWorkspaceStopDrag() {
    _dragMode = DragMode.none;
    _dragNodeIdx = -1;
  }

  void advanceAnimation(double dt, double time) {
    if (_client !is null && _client.gestureController().getIsActive()) {
      _playheadPhase = _client.gestureController().getGesturePhase();
    } else {
      if (dt > 0.0 && !isNaN(dt)) {
        _playheadPhase = cast(float)((_playheadPhase + dt * 0.5) % 1.0);
      }
    }
  }

  // ===========================================================================
  // Headless Testing Interface
  // ===========================================================================

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

    void testDrag(int x, int y, int dx, int dy) {
      MouseState mstate;
      _windowListener.onMouseMove(x, y, dx, dy, mstate);
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
    curveNode,
    subPanelSlider,
  }

  StutterClient _client;
  Parameter[] _params;
  bool _hasClient = false;
  Font _font;
  StutterCanvasOverlay _overlay;
  UIWindowResizer _resizer;

  int _activeModule = ModuleSlot.stutter;
  TVMCurve[NumTVMModuleSlots] _curves;
  float _playheadPhase = 0.0f;
  DragMode _dragMode = DragMode.none;
  int _dragNodeIdx = -1;

  // Header & Rack Labels
  UILabel _logoLabel;
  UILabel _modeLabel;
  UILabel _presetLabel;
  UILabel _gridLabel;
  UILabel _releaseLabel;
  UILabel[15] _rackLabels;
  UILabel _subPanelTitleLabel;
  UILabel _subPanelStateLabel;
  UILabel[4] _subPanelParamLabels;

  Vec!box2i _defaultRects;
  Vec!float _defaultTextSizes;

  /// Computes the bounding box of a left-rack slot in base 1040x680 coordinates.
  static box2i slotRect(int slot) pure {
    if (slot == ModuleSlot.stutter) return rectangle(4, 76, 222, 38);
    if (slot == ModuleSlot.buffer)  return rectangle(4, 116, 222, 38);
    if (slot >= ModuleSlot.gate && slot <= ModuleSlot.reverb) {
      const int idx = slot - ModuleSlot.gate; // 0..10
      return rectangle(4, 158 + idx * 36, 222, 34);
    }
    if (slot == ModuleSlot.delay)   return rectangle(4, 556, 222, 38);
    return rectangle(4, 598, 222, 36); // Limiter
  }

  bool isModuleEnabled(int slot) {
    const Params id = moduleEnableParam(slot);
    if (_params.length > id) {
      if (auto bp = cast(BoolParameter) _params[id]) {
        return bp.value();
      }
    }
    return false;
  }

  void buildLabelsAndWidgets() {
    _logoLabel = addTextLabel("KDR-STUTTER", rectangle(24, 14, 160, 22), 14.0f, textBright);
    _modeLabel = addTextLabel("AUTO MODE", rectangle(24, 36, 160, 20), 11.0f, RGBA(0, 229, 255, 255));
    _presetLabel = addTextLabel("01 Rhythmic Stutter", rectangle(226, 18, 108, 36), 10.0f, textBright);
    _gridLabel = addTextLabel("LEN: 1 Bar", rectangle(624, 13, 162, 20), 10.0f, textBright);
    _releaseLabel = addTextLabel("REL: Full Gesture", rectangle(624, 39, 162, 20), 10.0f, textMuted);

    for (int slot = 0; slot <= ModuleSlot.limiter; ++slot) {
      const box2i r = slotRect(slot);
      _rackLabels[slot] = addTextLabel(
        moduleSlotNames[slot],
        rectangle(r.min.x + 34, r.min.y + 4, r.width - 40, r.height - 8),
        11.0f,
        textBright
      );
    }

    _subPanelTitleLabel = addTextLabel("STUTTER MODULE", rectangle(250, 84, 240, 24), 14.0f, textBright);
    _subPanelStateLabel = addTextLabel("ENABLED", rectangle(940, 84, 84, 24), 11.0f, RGBA(0, 255, 180, 255));

    _subPanelParamLabels[0] = addTextLabel("MIN RANGE", rectangle(252, 116, 175, 16), 10.0f, textMuted);
    _subPanelParamLabels[1] = addTextLabel("MAX RANGE", rectangle(442, 116, 175, 16), 10.0f, textMuted);
    _subPanelParamLabels[2] = addTextLabel("PARAMETER", rectangle(632, 116, 175, 16), 10.0f, textMuted);
    _subPanelParamLabels[3] = addTextLabel("CURVE TENSION", rectangle(822, 116, 190, 16), 10.0f, textMuted);
  }

  UILabel addTextLabel(string text, box2i rect, float size, RGBA col) {
    auto lbl = mallocNew!UILabel(context, _font, text);
    lbl.position = rect;
    lbl.textSize = size;
    lbl.textColor = col;
    addChild(lbl);
    return lbl;
  }

  void syncLabels() {
    if (_modeLabel !is null) {
      const bool autoOn = isAutoMode();
      _modeLabel.text = autoOn ? "MODE: AUTO" : "MODE: MIDI";
      _modeLabel.textColor = autoOn ? RGBA(0, 229, 255, 255) : RGBA(255, 180, 0, 255);
    }
    if (_presetLabel !is null && _params.length > Params.bankPreset) {
      if (auto ip = cast(IntegerParameter) _params[Params.bankPreset]) {
        int idx = ip.value();
        if (idx < 0) idx = 0;
        if (idx >= NUM_FACTORY_PRESETS) idx = idx % NUM_FACTORY_PRESETS;
        _presetLabel.text = factoryPresetNames[idx];
      }
    }
    if (_gridLabel !is null && _params.length > Params.gestureLength) {
      if (auto ep = cast(EnumParameter) _params[Params.gestureLength]) {
        _gridLabel.text = ep.getValueString(ep.value());
      }
    }
    if (_releaseLabel !is null && _params.length > Params.releaseMode) {
      if (auto ep = cast(EnumParameter) _params[Params.releaseMode]) {
        _releaseLabel.text = ep.getValueString(ep.value());
      }
    }
    if (_subPanelTitleLabel !is null) {
      _subPanelTitleLabel.text = moduleSlotNames[_activeModule];
      _subPanelTitleLabel.textColor = moduleAccentRGBA(_activeModule);
    }
    if (_subPanelStateLabel !is null) {
      const bool en = isModuleEnabled(_activeModule);
      _subPanelStateLabel.text = en ? "ON" : "BYPASS";
      _subPanelStateLabel.textColor = en ? moduleAccentRGBA(_activeModule) : textMuted;
    }
    Params pMin, pMax, pAux;
    moduleRangeParams(_activeModule, pMin, pMax, pAux);
    if (_subPanelParamLabels[0] !is null && _params.length > pMin) {
      _subPanelParamLabels[0].text = _params[pMin].name();
    }
    if (_subPanelParamLabels[1] !is null && _params.length > pMax) {
      _subPanelParamLabels[1].text = _params[pMax].name();
    }
    if (_subPanelParamLabels[2] !is null && _params.length > pAux) {
      _subPanelParamLabels[2].text = _params[pAux].name();
    }
  }

  static void fillScaledBox(
      ref ImageRef!RGBA diff, box2i dirty, float scale, box2i logicalRect, RGBA col) pure {
    const box2i r = logicalRect.scaleByFactor(scale).intersection(dirty);
    if (r.empty) return;
    diff.cropImageRef(box2i(r.min - dirty.min, r.max - dirty.min)).fillAll(col);
  }

  static void drawScaledBorderedBox(
      ref ImageRef!RGBA diff, box2i dirty, float scale,
      box2i logicalRect, RGBA fillCol, RGBA borderCol, int borderPx = 1) pure {
    fillScaledBox(diff, dirty, scale, logicalRect, borderCol);
    const box2i inner = box2i(
      logicalRect.min.x + borderPx, logicalRect.min.y + borderPx,
      logicalRect.max.x - borderPx, logicalRect.max.y - borderPx
    );
    if (!inner.empty) {
      fillScaledBox(diff, dirty, scale, inner, fillCol);
    }
  }

  void drawHeaderMetersAndMix(ref Canvas canvas) {
    // Master Mix Bar (806, 28, 72, 22)
    float mixVal = 1.0f;
    if (_params.length > Params.masterDryWet) {
      mixVal = cast(float) _params[Params.masterDryWet].getNormalized();
    }
    canvas.fillStyle = RGBA(14, 17, 23, 255);
    canvas.fillRect(806, 26, 72, 22);
    canvas.fillStyle = RGBA(0, 229, 255, 220);
    canvas.fillRect(808, 28, 68.0f * mixVal, 18);

    // Limiter Indicator & Gain Reduction Bar (888, 26, 64, 22)
    const bool limOn = isModuleEnabled(ModuleSlot.limiter);
    canvas.fillStyle = limOn ? RGBA(0, 230, 160, 220) : RGBA(55, 65, 80, 220);
    canvas.fillRect(888, 26, 64, 10);
    float grDb = (_client !is null) ? _client.limiterGainReductionDb() : 0.0f;
    if (grDb > 12.0f) grDb = 12.0f;
    canvas.fillStyle = RGBA(255, 60, 80, 230);
    canvas.fillRect(888, 38, (grDb / 12.0f) * 64.0f, 10);

    // Stereo Output Peak Meters (962, 16, 56, 40)
    float pkL = (_client !is null) ? _client.peakLevelL() : 0.65f;
    float pkR = (_client !is null) ? _client.peakLevelR() : 0.60f;
    if (pkL > 1.0f) pkL = 1.0f;
    if (pkR > 1.0f) pkR = 1.0f;
    canvas.fillStyle = RGBA(12, 15, 20, 255);
    canvas.fillRect(962, 16, 24, 40);
    canvas.fillRect(990, 16, 24, 40);

    canvas.fillStyle = RGBA(0, 240, 180, 230);
    const float hL = 36.0f * pkL;
    const float hR = 36.0f * pkR;
    canvas.fillRect(964, 54.0f - hL, 20, hL);
    canvas.fillRect(992, 54.0f - hR, 20, hR);
  }

  void drawParameterSubPanelBars(ref Canvas canvas, RGBA accent) {
    Params pMin, pMax, pAux;
    moduleRangeParams(_activeModule, pMin, pMax, pAux);
    const int slot = (_activeModule < NumTVMModuleSlots) ? _activeModule : 0;
    const Params pTens = moduleTensionParam(slot);

    const Params[4] ids = [pMin, pMax, pAux, pTens];
    for (int i = 0; i < 4; ++i) {
      const float bx = 252.0f + i * 190.0f;
      const float by = 138.0f;
      const float bw = 175.0f;
      const float bh = 54.0f;

      canvas.fillStyle = RGBA(14, 17, 23, 255);
      canvas.fillRect(bx, by, bw, bh);

      float norm = 0.5f;
      if (_params.length > ids[i] && _params[ids[i]] !is null) {
        norm = cast(float) _params[ids[i]].getNormalized();
      }
      if (norm < 0.0f) norm = 0.0f;
      if (norm > 1.0f) norm = 1.0f;

      canvas.fillStyle = RGBA(accent.r, accent.g, accent.b, 90);
      canvas.fillRect(bx + 4.0f, by + 8.0f, (bw - 8.0f) * norm, bh - 16.0f);

      canvas.fillStyle = accent;
      canvas.fillRect(bx + 4.0f + (bw - 10.0f) * norm, by + 4.0f, 3.0f, bh - 8.0f);
    }
  }

  void drawTVMCurveEditor(ref Canvas canvas, RGBA accent, RGBA accentFill) {
    enum float ex = 236.0f;
    enum float ey = 216.0f;
    enum float ew = 796.0f;
    enum float eh = 414.0f;
    enum float pad = 14.0f;
    const float cw = ew - pad * 2.0f;
    const float ch = eh - pad * 2.0f;

    // 1. Beat-subdivision vertical grid lines (16 subdivisions)
    for (int i = 0; i <= 16; ++i) {
      const float gx = ex + pad + (cast(float) i / 16.0f) * cw;
      const bool isBeat = (i % 4 == 0);
      canvas.fillStyle = isBeat ? RGBA(65, 78, 100, 180) : RGBA(34, 42, 56, 140);
      canvas.fillRect(gx - 0.5f, ey + 4.0f, isBeat ? 1.5f : 1.0f, eh - 8.0f);
    }

    // 2. Horizontal percentage level grid lines (0%, 25%, 50%, 75%, 100%)
    for (int j = 0; j <= 4; ++j) {
      const float gy = ey + pad + (cast(float) j / 4.0f) * ch;
      canvas.fillStyle = (j == 2) ? RGBA(65, 78, 100, 180) : RGBA(34, 42, 56, 140);
      canvas.fillRect(ex + 4.0f, gy - 0.5f, ew - 8.0f, 1.0f);
    }

    const ref TVMCurve curve = activeCurve();

    // 3. Shaded translucent polygon fill under the TVM curve
    canvas.fillStyle = accentFill;
    canvas.beginPath();
    canvas.moveTo(ex + pad, ey + pad + ch);
    enum int NUM_STEPS = 160;
    for (int s = 0; s <= NUM_STEPS; ++s) {
      const float p = cast(float) s / cast(float) NUM_STEPS;
      const float v = curve.evaluate(p);
      const float px = ex + pad + p * cw;
      const float py = ey + pad + (1.0f - v) * ch;
      canvas.lineTo(px, py);
    }
    canvas.lineTo(ex + pad + cw, ey + pad + ch);
    canvas.closePath();
    canvas.fill();

    // 4. Glowing color-coded curve ribbon stroke
    canvas.fillStyle = accent;
    canvas.beginPath();
    for (int s = 0; s <= NUM_STEPS; ++s) {
      const float p = cast(float) s / cast(float) NUM_STEPS;
      const float v = curve.evaluate(p);
      const float px = ex + pad + p * cw;
      const float py = ey + pad + (1.0f - v) * ch - 1.5f;
      if (s == 0) canvas.moveTo(px, py);
      else canvas.lineTo(px, py);
    }
    for (int s = NUM_STEPS; s >= 0; --s) {
      const float p = cast(float) s / cast(float) NUM_STEPS;
      const float v = curve.evaluate(p);
      const float px = ex + pad + p * cw;
      const float py = ey + pad + (1.0f - v) * ch + 1.5f;
      canvas.lineTo(px, py);
    }
    canvas.closePath();
    canvas.fill();

    // 5. Interactive Breakpoint Node Handles
    const int nNodes = curve.nodeCount();
    for (int i = 0; i < nNodes; ++i) {
      const float nx = ex + pad + curve.nodes[i].x * cw;
      const float ny = ey + pad + (1.0f - curve.nodes[i].y) * ch;
      canvas.fillStyle = RGBA(14, 17, 23, 255);
      canvas.fillCircle(nx, ny, 7.0f);
      canvas.fillStyle = accent;
      canvas.fillCircle(nx, ny, 5.0f);
      canvas.fillStyle = textBright;
      canvas.fillCircle(nx, ny, 2.2f);
    }

    // 6. Live Animated Vertical Gesture Playhead & Curve Follower Dot
    float ph = _playheadPhase;
    if (ph < 0.0f) ph = 0.0f;
    if (ph > 1.0f) ph = 1.0f;
    const float phX = ex + pad + ph * cw;
    const float phVal = curve.evaluate(ph);
    const float phY = ey + pad + (1.0f - phVal) * ch;

    canvas.fillStyle = playheadColor;
    canvas.fillRect(phX - 1.0f, ey + 4.0f, 2.0f, eh - 8.0f);
    canvas.fillStyle = accent;
    canvas.fillCircle(phX, phY, 6.5f);
    canvas.fillStyle = RGBA(255, 255, 255, 255);
    canvas.fillCircle(phX, phY, 3.0f);
  }

  void drawPresetShapeBar(ref Canvas canvas, RGBA accent) {
    int activePreset = -1;
    const int slot = (_activeModule < NumTVMModuleSlots) ? _activeModule : 0;
    const Params cParam = moduleCurveParam(slot);
    if (_params.length > cParam) {
      if (auto ip = cast(IntegerParameter) _params[cParam]) {
        activePreset = ip.value();
      }
    }

    TVMCurve preview;
    for (int i = 0; i < 12; ++i) {
      const float bx = 240.0f + i * 65.5f;
      const float by = 638.0f;
      const float bw = 61.0f;
      const float bh = 32.0f;
      const bool isSel = (i == activePreset);

      canvas.fillStyle = isSel ? RGBA(accent.r, accent.g, accent.b, 60) : RGBA(26, 31, 42, 255);
      canvas.fillRect(bx, by, bw, bh);

      preview.loadPreset(i);
      canvas.fillStyle = isSel ? accent : textMuted;
      for (int s = 0; s < 16; ++s) {
        const float p = cast(float) s / 15.0f;
        const float v = preview.evaluate(p);
        const float px = bx + 6.0f + p * (bw - 12.0f);
        const float py = by + 5.0f + (1.0f - v) * (bh - 10.0f);
        canvas.fillCircle(px, py, 1.4f);
      }
    }
  }

  void updateSubPanelSliderAt(int x, int y) {
    int colIdx = (x - 252) / 190;
    if (colIdx < 0) colIdx = 0;
    if (colIdx > 3) colIdx = 3;

    const float bx = 252.0f + colIdx * 190.0f;
    double norm = (cast(double) x - bx) / 175.0;
    if (norm < 0.0) norm = 0.0;
    if (norm > 1.0) norm = 1.0;

    Params pMin, pMax, pAux;
    moduleRangeParams(_activeModule, pMin, pMax, pAux);
    const int slot = (_activeModule < NumTVMModuleSlots) ? _activeModule : 0;
    const Params pTens = moduleTensionParam(slot);
    const Params[4] ids = [pMin, pMax, pAux, pTens];

    const Params target = ids[colIdx];
    if (_params.length > target && _params[target] !is null) {
      setNormParamSafe(_params[target], _hasClient, norm);
    }
    syncLabels();
    setDirtyWhole();
    if (_overlay !is null) _overlay.setDirtyWhole();
  }

  Click handleCurveEditorClick(int x, int y, bool isDoubleClick) {
    enum float ex = 236.0f + 14.0f;
    enum float ey = 216.0f + 14.0f;
    enum float cw = 796.0f - 28.0f;
    enum float ch = 414.0f - 28.0f;

    float normX = (cast(float) x - ex) / cw;
    float normY = 1.0f - (cast(float) y - ey) / ch;
    if (normX < 0.0f) normX = 0.0f;
    if (normX > 1.0f) normX = 1.0f;
    if (normY < 0.0f) normY = 0.0f;
    if (normY > 1.0f) normY = 1.0f;

    const int slot = (_activeModule >= 0 && _activeModule < NumTVMModuleSlots) ? _activeModule : 0;
    TVMCurve* cLocal = &_curves[slot];
    TVMCurve* cClient = (_client !is null) ? &_client.modulationEngine().curves[slot] : null;

    // Find closest existing node within 18 px
    int bestIdx = -1;
    float bestDist2 = 18.0f * 18.0f;
    const int nNodes = cLocal.nodeCount();
    for (int i = 0; i < nNodes; ++i) {
      const float nx = ex + cLocal.nodes[i].x * cw;
      const float ny = ey + (1.0f - cLocal.nodes[i].y) * ch;
      const float dx = cast(float) x - nx;
      const float dy = cast(float) y - ny;
      const float d2 = dx * dx + dy * dy;
      if (d2 < bestDist2) {
        bestDist2 = d2;
        bestIdx = i;
      }
    }

    if (isDoubleClick) {
      if (bestIdx > 0 && bestIdx < nNodes - 1) {
        // Cycle curve interpolation type on interior node
        const ubyte nextT = cast(ubyte)((cast(ubyte) cLocal.nodes[bestIdx].type + 1) % 5);
        cLocal.nodes[bestIdx].type = cast(CurveType) nextT;
        if (cClient !is null && bestIdx < cClient.nodeCount()) {
          cClient.nodes[bestIdx].type = cast(CurveType) nextT;
        }
      } else {
        // Insert a new breakpoint node at (normX, normY)
        cLocal.addNode(normX, normY, 0.0f, CurveType.linear);
        if (cClient !is null) {
          cClient.addNode(normX, normY, 0.0f, CurveType.linear);
        }
      }
      setDirtyWhole();
      if (_overlay !is null) _overlay.setDirtyWhole();
      return Click.handled;
    }

    if (bestIdx == -1) {
      // Insert or pick an interior node at the clicked position so dragging shapes the curve immediately
      if (cLocal.nodeCount() < 16) {
        cLocal.addNode(normX, normY, 0.0f, CurveType.linear);
        if (cClient !is null) {
          cClient.addNode(normX, normY, 0.0f, CurveType.linear);
        }
        // Find index of newly added node
        bestIdx = 1;
        for (int i = 1; i < cLocal.nodeCount() - 1; ++i) {
          if (fabs(cLocal.nodes[i].x - normX) < 1e-4f) {
            bestIdx = i;
            break;
          }
        }
      } else {
        bestIdx = cLocal.nodeCount() / 2;
      }
    }

    _dragMode = DragMode.curveNode;
    _dragNodeIdx = bestIdx;
    updateCurveNodeDrag(x, y);
    return Click.startDrag;
  }

  void updateCurveNodeDrag(int x, int y) {
    if (_dragNodeIdx < 0) return;
    enum float ex = 236.0f + 14.0f;
    enum float ey = 216.0f + 14.0f;
    enum float cw = 796.0f - 28.0f;
    enum float ch = 414.0f - 28.0f;

    float normX = (cast(float) x - ex) / cw;
    float normY = 1.0f - (cast(float) y - ey) / ch;
    if (normX < 0.0f) normX = 0.0f;
    if (normX > 1.0f) normX = 1.0f;
    if (normY < 0.0f) normY = 0.0f;
    if (normY > 1.0f) normY = 1.0f;

    const int slot = (_activeModule >= 0 && _activeModule < NumTVMModuleSlots) ? _activeModule : 0;
    TVMCurve* cLocal = &_curves[slot];
    TVMCurve* cClient = (_client !is null) ? &_client.modulationEngine().curves[slot] : null;

    const int n = cLocal.nodeCount();
    if (_dragNodeIdx >= n) return;

    const CurveType cType = cLocal.nodes[_dragNodeIdx].type;
    const float cTens = cLocal.nodes[_dragNodeIdx].tension;
    cLocal.setNode(_dragNodeIdx, normX, normY, cTens, cType);
    if (cClient !is null && _dragNodeIdx < cClient.nodeCount()) {
      cClient.setNode(_dragNodeIdx, normX, normY, cTens, cType);
    }

    setDirtyWhole();
    if (_overlay !is null) _overlay.setDirtyWhole();
  }

  void applyCurvePresetToActiveModule(int presetIdx) {
    if (presetIdx < 0) presetIdx = 0;
    if (presetIdx > 11) presetIdx = 11;
    const int slot = (_activeModule >= 0 && _activeModule < NumTVMModuleSlots) ? _activeModule : 0;

    _curves[slot].loadPreset(presetIdx);
    if (_client !is null) {
      _client.modulationEngine().curves[slot].loadPreset(presetIdx);
    }

    const Params cParam = moduleCurveParam(slot);
    if (_params.length > cParam) {
      setIntParamSafe(_params[cParam], _hasClient, presetIdx);
    }
    setDirtyWhole();
    if (_overlay !is null) _overlay.setDirtyWhole();
  }
}

// =============================================================================
// Headless Framebuffer Verification Helpers & Unit Tests
// =============================================================================

version (unittest) {
  @nogc nothrow pure
  float computeLuminanceVariance(ImageRef!RGBA fb, box2i region) {
    const box2i bounds = box2i(0, 0, fb.w, fb.h).intersection(region);
    if (bounds.empty) return 0.0f;

    double sum = 0.0;
    double sumSq = 0.0;
    long count = 0;

    for (int y = bounds.min.y; y < bounds.max.y; ++y) {
      RGBA[] row = fb.scanline(y);
      for (int x = bounds.min.x; x < bounds.max.x; ++x) {
        const RGBA p = row[x];
        const double lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
        sum += lum;
        sumSq += lum * lum;
        count++;
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
  import kdr.params : buildParams;

  // 1. Instantiate StutterClient & StutterGUI headlessly
  auto client = new StutterClient();
  auto gui = mallocNew!StutterGUI(client, client.params());
  scope(exit) destroyFree(gui);

  // 2. Resize & Render at base resolution (1040 x 680)
  gui.testResize(1040, 680);
  gui.testDraw();

  ImageRef!RGBA fb = gui.testFramebuffer();
  assert(fb.w == 1040);
  assert(fb.h == 680);

  // 3. Verify non-blank visual output across all 4 regions
  // Zone A: Top Header & Gesture Bar (0, 0, 1040, 72)
  assert(computeLuminanceVariance(fb, box2i(0, 0, 1040, 72)) > 5.0f);
  // Zone B: Left Module Rack (0, 72, 230, 680)
  assert(computeLuminanceVariance(fb, box2i(0, 72, 230, 680)) > 5.0f);
  // Zone C: Parameter Sub-Panel (230, 72, 1040, 210)
  assert(computeLuminanceVariance(fb, box2i(230, 72, 1040, 210)) > 5.0f);
  // Zone D: TVM Curve Editor (230, 216, 1040, 630)
  assert(computeLuminanceVariance(fb, box2i(230, 216, 1040, 630)) > 5.0f);

  // 4. Test Interactive State Transitions:
  // A. Click Filter module slot in Left Rack (slot 5: y = 158 + 3*36 = 266..300)
  assert(gui.activeModule() == ModuleSlot.stutter);
  bool handled = gui.testClick(100, 280);
  assert(handled);
  assert(gui.activeModule() == ModuleSlot.filter);
  gui.testDraw();

  // Verify TVM Curve Editor color transitioned to Filter Amber (#FFD600)
  assert(hasColorSignature(fb, box2i(236, 216, 1032, 630), moduleAccentRGBA(ModuleSlot.filter)));

  // B. Click Preset Curve Shape #3 (Ramp Down, index 3) in bottom bar
  int rampDownX = 240 + 3 * 65 + 30;
  gui.testClick(rampDownX, 650);
  gui.testDraw();
  assert(gui.activeCurve().evaluate(0.0f) >= 0.95f);
  assert(gui.activeCurve().evaluate(1.0f) <= 0.05f);

  // C. Click & Drag Breakpoint Node in TVM Curve Editor
  gui.testClick(620, 420);
  gui.testDrag(620, 320, 0, -100);
  gui.testDraw();
  assert(gui.activeCurve().nodeCount() >= 3);

  // D. Toggle Auto Mode in Top Header (x=60, y=36)
  bool prevAuto = gui.isAutoMode();
  gui.testClick(60, 36);
  assert(gui.isAutoMode() != prevAuto);

  // E. Click Mini Keyboard Strip (x=440, y=35)
  gui.testClick(440, 35);
  gui.testDraw();

  // F. Animate Gesture Playhead
  gui.testAnimate(0.05, 1.0);
  gui.testDraw();
}
