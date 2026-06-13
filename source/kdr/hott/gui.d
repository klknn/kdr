module kdr.hott.gui;

import std.algorithm.comparison : clamp, max, min;
import std.math : log10, pow, abs;
import std.format : format;

import core.stdc.stdio : snprintf;

static float attackNormToMs(float norm) nothrow @nogc {
    import std.math : pow;
    return 0.1f * pow(1000.0f, norm);
}
static float releaseNormToMs(float norm) nothrow @nogc {
    import std.math : pow;
    return 10.0f * pow(100.0f, norm);
}
static float ratioNormToRatio(float norm) nothrow @nogc {
    if (norm >= 0.999f) return 1000.0f;
    return 1.0f / (1.0f - norm);
}
static float upThreshNormToDb(float norm) nothrow @nogc {
    return norm * 72.0f - 60.0f;
}
static float downThreshNormToDb(float norm) nothrow @nogc {
    return norm * 60.0f - 60.0f;
}

string formatAttRel(char[] buf, float val, bool isAttack) nothrow @nogc {
    int len;
    if (isAttack) {
        len = snprintf(buf.ptr, buf.length, "%.1f ms", val);
    } else {
        len = snprintf(buf.ptr, buf.length, "%.0f ms", val);
    }
    if (len < 0) return "";
    if (len >= buf.length) len = cast(int)buf.length - 1;
    return cast(string) buf[0..len];
}

string formatDb(char[] buf, float val) nothrow @nogc {
    int len = snprintf(buf.ptr, buf.length, "%.1f dB", val);
    if (len < 0) return "";
    if (len >= buf.length) len = cast(int)buf.length - 1;
    return cast(string) buf[0..len];
}

string formatRatio(char[] buf, float ratio, bool isUpward) nothrow @nogc {
    int len;
    if (isUpward) {
        len = snprintf(buf.ptr, buf.length, "1:%.2f", ratio);
    } else {
        if (ratio >= 999.0f) {
            len = snprintf(buf.ptr, buf.length, "inf:1");
        } else {
            len = snprintf(buf.ptr, buf.length, "%.1f:1", ratio);
        }
    }
    if (len < 0) return "";
    if (len >= buf.length) len = cast(int)buf.length - 1;
    return cast(string) buf[0..len];
}

import dplug.core : mallocNew, destroyFree;
import dplug.client;
import dplug.math : vec2f, box2f, box2i, rectangle;
import dplug.gui;
import dplug.graphics : cropImageRef, ImageRef, RGBA, Font, L16;
import dplug.canvas : Canvas;
import dplug.pbrwidgets : UILabel, UIKnob, UIOnOffSwitch;
import dplug.flatwidgets : UIWindowResizer;
import kdr.logging : logDebug;

import kdr.simplegui : PBRSimpleGUI;
import kdr.hott.params;

// Visual Theme constants from comp1
enum RGBA TEXT_COLOR = RGBA(155, 255, 255, 0);
enum RGBA lineColor = RGBA(0, 255, 255, 96);
enum RGBA lineColorDim = RGBA(0, 255, 255, 40);
enum RGBA gradColor = RGBA(0, 64, 64, 96);
enum RGBA gridColor = RGBA(100, 100, 100, 75);
enum RGBA darkColor = RGBA(128, 128, 128, 128);
enum RGBA lightColor = RGBA(100, 200, 200, 100);
enum RGBA knobColor = RGBA(96, 96, 96, 0);
enum RGBA litColor = RGBA(155, 255, 255, 0);
enum RGBA unlitColor = RGBA(0, 32, 32, 0);

enum BackgroundStart = RGBA(0, 64, 64, 32);
enum BackgroundEnd = RGBA(0, 16, 16, 128);

enum minThreshold = -80;
enum alphaColor = 120;
enum belowColor = RGBA(100, 150, 150, alphaColor);
enum midColor = RGBA(0, 32, 32, alphaColor);
enum aboveColor = RGBA(130, 100, 100, alphaColor);

enum RGBA grOrange = RGBA(255, 140, 0, 255);

interface IHottClient {
    nothrow @nogc:
    float getBandInputDb(int band);
    float getBandOutputDb(int band);
    float getBandGainReduction(int band);
}

class HottDisplayUI : UIElement, IParameterListener {
public:
    @nogc nothrow:

    enum Tab {
        time = 0,
        below = 1,
        above = 2
    }

    Tab activeTab = Tab.time;
    int dragBand = -1;
    bool dragIsUp = false; // true = upward threshold, false = downward threshold
    int dragType = 0; // 0 = threshold, 1 = attack/release/ratio

    this(UIContext context, IHottClient client, Parameter[] params) {
        super(context, flagRaw | flagAnimated);
        _client = client;
        _params = params;
        foreach (p; _params) p.addListener(this);
    }

    ~this() {
        foreach (p; _params) p.removeListener(this);
    }

    float getParamValue(int index) {
        if (auto p = cast(LinearFloatParameter) _params[index]) {
            return p.value;
        }
        if (auto p = cast(BoolParameter) _params[index]) {
            return p.value ? 1.0f : 0.0f;
        }
        return 0.0f;
    }

    override Click onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate) {
        int pad = 6;
        int tabBtnW = 18;
        int tabBtnH = 14;
        int tabGap = 2;
        int tabX = position.width - 60 - pad;
        int tabY = position.height - pad - tabBtnH;

        for (int t = 0; t < 3; ++t) {
            int tx = tabX + t * (tabBtnW + tabGap);
            if (x >= tx && x < tx + tabBtnW && y >= tabY && y < tabY + tabBtnH) {
                activeTab = cast(Tab) t;
                setDirtyWhole();
                return Click.handled;
            }
        }

        int h = position.height;
        int bandAreaH = h - pad * 2 - 18;
        int bandH = (bandAreaH - pad * 2) / 3;

        int meterW = getMeterWidth();
        int attRelX = pad + meterW + 4;

        for (int b = 0; b < 3; ++b) {
            int by = pad + b * (bandH + pad);
            if (y >= by && y < by + bandH) {
                dragBand = b;
                if (x >= attRelX) {
                    dragType = 1;
                    dragIsUp = (y - by) < (bandH / 2);
                } else {
                    dragType = 0;
                    if (activeTab == Tab.below) {
                        dragIsUp = true;
                    } else if (activeTab == Tab.above) {
                        dragIsUp = false;
                    } else {
                        float downDb = downThreshNormToDb(getParamValue(getDownThreshParam(b)));
                        float upDb = upThreshNormToDb(getParamValue(getUpThreshParam(b)));
                        float downX = pad + dbToNorm(downDb) * meterW;
                        float upX = pad + dbToNorm(upDb) * meterW;
                        dragIsUp = abs(x - upX) < abs(x - downX);
                    }
                }
                handleDrag(x, y);
                return Click.startDrag;
            }
        }

        return Click.unhandled;
    }

    override void onMouseDrag(int x, int y, int dx, int dy, MouseState mstate) {
        handleDrag(x, y);
    }

    void handleDrag(int mx, int my) {
        if (dragBand < 0) return;

        int pad = 6;
        int meterW = getMeterWidth();
        int dspB = 2 - dragBand; // Map display band to DSP band

        if (dragType == 1) {
            int attRelX = pad + meterW + 4;
            int attRelW = 70;
            float fraction = clamp(cast(float)(mx - attRelX) / attRelW, 0.0f, 1.0f);

            if (activeTab == Tab.time) {
                if (dragIsUp) {
                    auto p = cast(LinearFloatParameter) _params[Params.lowAttack + dspB];
                    p.beginParamEdit();
                    p.setFromGUI(fraction);
                    p.endParamEdit();
                } else {
                    auto p = cast(LinearFloatParameter) _params[Params.lowRelease + dspB];
                    p.beginParamEdit();
                    p.setFromGUI(fraction);
                    p.endParamEdit();
                }
            } else if (activeTab == Tab.below) {
                auto p = cast(LinearFloatParameter) _params[Params.lowUpRatio + dspB];
                p.beginParamEdit();
                p.setFromGUI(fraction);
                p.endParamEdit();
            } else if (activeTab == Tab.above) {
                auto p = cast(LinearFloatParameter) _params[Params.lowDownRatio + dspB];
                p.beginParamEdit();
                p.setFromGUI(fraction);
                p.endParamEdit();
            }
        } else {
            float db = -80.0f + cast(float)(mx - pad) * 80.0f / meterW;
            db = clamp(db, -80.0f, 0.0f);

            if (dragIsUp) {
                auto p = cast(LinearFloatParameter) _params[getUpThreshParam(dragBand)];
                p.beginParamEdit();
                p.setFromGUI(dbToUpThreshNorm(db));
                p.endParamEdit();
            } else {
                auto p = cast(LinearFloatParameter) _params[getDownThreshParam(dragBand)];
                p.beginParamEdit();
                p.setFromGUI(dbToDownThreshNorm(db));
                p.endParamEdit();
            }
        }
        setDirtyWhole();
    }

    override void onDrawRaw(ImageRef!RGBA rawMap, box2i[] dirtyRects) {
        foreach (ref rect; dirtyRects) {
            ImageRef!RGBA cropped = cropImageRef(rawMap, rect);
            _canvas.initialize(cropped);
            _canvas.translate(-rect.min.x, -rect.min.y);

            // Draw background gradient
            auto grad = _canvas.createLinearGradient(0, 0, 0, position.height);
            grad.addColorStop(0, BackgroundStart);
            grad.addColorStop(position.height, BackgroundEnd);
            _canvas.fillStyle = grad;
            _canvas.fillRect(0, 0, position.width, position.height);

            int w = position.width;
            int h = position.height;
            int pad = 6;
            int tabAreaW = 60;
            int attRelW = 70;
            int meterW = getMeterWidth();
            int tabH = 18;
            int bandAreaH = h - pad - tabH;
            int bandH = (bandAreaH - pad * 2) / 3;

            // Draw grid lines
            _canvas.fillStyle = gridColor;
            float dw = cast(float) meterW / 8;
            foreach (float i; 1 .. 9) {
                _canvas.fillRect(pad + cast(int)(dw * i) - 1, pad, 1, bandAreaH - pad);
            }

            // Draw bands
            for (int b = 0; b < 3; ++b) {
                int y = pad + b * (bandH + pad);

                float downDb = downThreshNormToDb(getParamValue(getDownThreshParam(b)));
                float upDb = upThreshNormToDb(getParamValue(getUpThreshParam(b)));
                float downNorm = dbToNorm(downDb);
                float upNorm = dbToNorm(upDb);
                int downX = pad + cast(int)(downNorm * meterW);
                int upX = pad + cast(int)(upNorm * meterW);

                // Range colors
                _canvas.fillStyle = belowColor;
                _canvas.fillRect(pad, y, max(0, upX - pad), bandH);

                _canvas.fillStyle = midColor;
                _canvas.fillRect(upX, y, max(0, downX - upX), bandH);

                _canvas.fillStyle = aboveColor;
                _canvas.fillRect(downX, y, max(0, pad + meterW - downX), bandH);

                // Real-time output level bar
                float outDb = _client.getBandOutputDb(b);
                if (outDb > -80.0f) {
                    float outNorm = dbToNorm(outDb);
                    int outW = cast(int)(outNorm * meterW);
                    _canvas.fillStyle = RGBA(0, 255, 255, 120);
                    _canvas.fillRect(pad, y + bandH / 2 - 2, outW, 4);
                }

                // Real-time input indicator (orange dot)
                float inDb = _client.getBandInputDb(b);
                if (inDb > -80.0f) {
                    float inNorm = dbToNorm(inDb);
                    int inX = pad + cast(int)(inNorm * meterW);
                    _canvas.fillStyle = grOrange;
                    _canvas.fillRect(inX - 2, y + bandH / 2 - 5, 4, 10);
                }

                // Real-time gain reduction/boost bar (drawn at the top edge of the band)
                float grDb = _client.getBandGainReduction(b);
                if (grDb < -0.1f) {
                    float grNorm = clamp(-grDb / 80.0f, 0.0f, 1.0f);
                    int grW = cast(int)(grNorm * meterW);
                    _canvas.fillStyle = RGBA(255, 60, 0, 180); // red-orange for downward GR
                    _canvas.fillRect(pad + meterW - grW, y, grW, 3);
                } else if (grDb > 0.1f) {
                    float grNorm = clamp(grDb / 80.0f, 0.0f, 1.0f);
                    int grW = cast(int)(grNorm * meterW);
                    _canvas.fillStyle = RGBA(0, 255, 100, 180); // green for upward boost
                    _canvas.fillRect(pad + meterW - grW, y, grW, 3);
                }

                // Threshold division lines
                _canvas.fillStyle = lineColor;
                _canvas.fillRect(upX - 1, y, 2, bandH);
                _canvas.fillRect(downX - 1, y, 2, bandH);
            }

            // Draw Tab buttons background
            int tabX = w - tabAreaW - pad;
            int tabY = bandAreaH + 2;
            int tabBtnW = 18;
            int tabBtnH = 14;
            int tabGap = 2;

            for (int t = 0; t < 3; ++t) {
                int tx = tabX + t * (tabBtnW + tabGap);
                bool active = (activeTab == cast(Tab) t);
                _canvas.fillStyle = active ? lineColor : RGBA(155, 255, 255, 20);
                _canvas.fillRect(tx, tabY, tabBtnW, tabBtnH);
            }
        }
    }

    override void onAnimate(double dt, double time) {
        setDirtyWhole();
    }

    override void onParameterChanged(Parameter sender) {
        setDirtyWhole();
    }

    override void onBeginParameterEdit(Parameter sender) {}
    override void onEndParameterEdit(Parameter sender) {}
    override void onBeginParameterHover(Parameter sender) {}
    override void onEndParameterHover(Parameter sender) {}

    int getMeterWidth() {
        int pad = 6;
        int tabAreaW = 60;
        int attRelW = 70;
        return position.width - pad * 2 - attRelW - 4 - tabAreaW;
    }

private:
    IHottClient _client;
    Parameter[] _params;
    Canvas _canvas;

    static int getDownThreshParam(int band) {
        return Params.highDownThresh - band;
    }

    static int getUpThreshParam(int band) {
        return Params.highUpThresh - band;
    }

    static int getAttackParam(int band) {
        return Params.highAttack - band;
    }

    static int getReleaseParam(int band) {
        return Params.highRelease - band;
    }

    static float dbToNorm(float db) {
        return clamp((db + 80.0f) / 80.0f, 0.0f, 1.0f);
    }

    static float downThreshNormToDb(float norm) {
        return norm * 60.0f - 60.0f;
    }

    static float dbToDownThreshNorm(float db) {
        return clamp((db + 60.0f) / 60.0f, 0.0f, 1.0f);
    }

    static float upThreshNormToDb(float norm) {
        return norm * 72.0f - 60.0f;
    }

    static float dbToUpThreshNorm(float db) {
        return clamp((db + 60.0f) / 72.0f, 0.0f, 1.0f);
    }
}

class HottSubPaneBackgroundUI : UIElement {
public:
    @nogc nothrow:
    this(UIContext context) {
        super(context, flagRaw);
    }

    override void onDrawRaw(ImageRef!RGBA rawMap, box2i[] dirtyRects) {
        foreach (ref rect; dirtyRects) {
            ImageRef!RGBA cropped = cropImageRef(rawMap, rect);
            _canvas.initialize(cropped);
            _canvas.translate(-rect.min.x, -rect.min.y);

            // Draw gradient background for sub-pane
            auto grad = _canvas.createLinearGradient(0, 0, 0, position.height);
            grad.addColorStop(0, BackgroundStart);
            grad.addColorStop(position.height, BackgroundEnd);
            _canvas.fillStyle = grad;
            _canvas.fillRect(0, 0, position.width, position.height);

            // Draw a thin border separating the left and right panels
            _canvas.fillStyle = lineColorDim;
            _canvas.fillRect(0, 0, 1, position.height);
        }
    }
private:
    Canvas _canvas;
}

class HottGUI : PBRSimpleGUI, IParameterListener {
public:
    @nogc nothrow:

    this(IHottClient client, Parameter[] params) {
        logDebug("Initialize %s", __FUNCTION__.ptr);

        static immutable float[] ratios = [1.0f, 1.25f, 1.5f, 1.75f, 2.0f];
        // Expanded width to 780px to accommodate the sub-pane next to main controls
        super(makeSizeConstraintsDiscrete(780, 580, ratios));

        _client = client;
        _params = params;
        _font = mallocNew!Font(cast(ubyte[]) import("FORCED SQUARE.ttf"));

        addChild(_resizer = mallocNew!UIWindowResizer(context()));

        // Left Pane Title
        _title = buildLabel("kdr hott");
        _date = buildLabel("" ~ __DATE__ ~ "" ~ __TIME__);

        // Top knobs
        _knobAmount = buildKnob(Params.amount);
        _labelAmount = buildLabel("AMOUNT");
        _knobTime = buildKnob(Params.time);
        _labelTime = buildLabel("TIME");
        _knobOutput = buildKnob(Params.output);
        _labelOutput = buildLabel("OUT GAIN");
        _knobLowXover = buildKnob(Params.lowXover);
        _labelLowXover = buildLabel("LOW XOVER");

        // Display
        addChild(_display = mallocNew!HottDisplayUI(context(), _client, params));

        // TBA Display labels
        _labelTabT = buildLabel("T");
        _labelTabB = buildLabel("B");
        _labelTabA = buildLabel("A");

        _labelBandName[0] = buildLabel("HIGH");
        _labelBandName[1] = buildLabel("MID");
        _labelBandName[2] = buildLabel("LOW");

        for (int b = 0; b < 3; ++b) {
            _labelValTop[b] = buildLabel("");
            _labelValBottom[b] = buildLabel("");
        }

        // Right side knobs of left panel (H Out, M Out, L Out)
        _knobHighOut = buildKnob(Params.highOut);
        _labelHighOut = buildLabel("H OUT");
        _knobMidOut = buildKnob(Params.midOut);
        _labelMidOut = buildLabel("M OUT");
        _knobLowOut = buildKnob(Params.lowOut);
        _labelLowOut = buildLabel("L OUT");

        // Bottom knobs/toggles of left panel
        _knobHighXover = buildKnob(Params.highXover);
        _labelHighXover = buildLabel("HIGH XOVER");

        _switchSoftKnee = mallocNew!UIOnOffSwitch(context(), cast(BoolParameter) _params[Params.softKnee]);
        addChild(_switchSoftKnee);
        _labelSoftKnee = buildLabel("KNEE");

        _switchRmsMode = mallocNew!UIOnOffSwitch(context(), cast(BoolParameter) _params[Params.rmsMode]);
        addChild(_switchRmsMode);
        _labelRmsMode = buildLabel("RMS");

        // Sub-pane on the right (detailed controls)
        addChild(_subPaneBackground = mallocNew!HottSubPaneBackgroundUI(context()));
        _labelSubPaneTitle = buildLabel("DETAILED BAND CONTROLS");

        // Sub-pane headers
        _labelHeaderAtt = buildLabel("ATTACK");
        _labelHeaderRel = buildLabel("RELEASE");
        _labelHeaderUpTh = buildLabel("UP TH");
        _labelHeaderUpRt = buildLabel("UP RT");
        _labelHeaderDnTh = buildLabel("DN TH");
        _labelHeaderDnRt = buildLabel("DN RT");

        // Sub-pane rows labels
        _labelRowHigh = buildLabel("HIGH");
        _labelRowMid = buildLabel("MID");
        _labelRowLow = buildLabel("LOW");

        // 18 Detailed knobs in the grid
        // GUI display order: High = 0 (Params index + 2), Mid = 1 (Params index + 1), Low = 2 (Params index + 0)
        // DSP order: Low = 0, Mid = 1, High = 2
        for (int b = 0; b < 3; ++b) {
            int dspB = 2 - b;
            _knobAttack[b] = buildKnob(cast(Params)(Params.lowAttack + dspB));
            _knobRelease[b] = buildKnob(cast(Params)(Params.lowRelease + dspB));
            _knobUpThresh[b] = buildKnob(cast(Params)(Params.lowUpThresh + dspB));
            _knobUpRatio[b] = buildKnob(cast(Params)(Params.lowUpRatio + dspB));
            _knobDownThresh[b] = buildKnob(cast(Params)(Params.lowDownThresh + dspB));
            _knobDownRatio[b] = buildKnob(cast(Params)(Params.lowDownRatio + dspB));
        }
        updateDisplayLabels();
    }

    ~this() {
        destroyFree(_font);
    }

    override void reflow() {
        super.reflow();
        const int W = position.width;
        const float S = W / cast(float)(context.getDefaultUIWidth());

        // We split the window: Left panel is W_left = 400 * S, Right panel is W_right = 380 * S
        int leftW = cast(int)(400 * S);
        int rightW = W - leftW;

        // --- Left Panel Layout ---
        int headerY = 10;
        _title.position = rect(0, headerY, 250, 40);
        _title.textSize = 40 * S;
        _date.position = rect(250, headerY, 150, 15);
        _date.textSize = 15 * S;

        // Top knobs (left panel)
        int knobSize = 100;
        int knobLabelSize = 12;
        int knobY = 50;
        _knobAmount.position = rect(0, knobY, knobSize, knobSize);
        _labelAmount.position = rect(0, knobY + knobSize, knobSize, knobLabelSize);
        _labelAmount.textSize = knobLabelSize * S;

        _knobTime.position = rect(knobSize, knobY, knobSize, knobSize);
        _labelTime.position = rect(knobSize, knobY + knobSize, knobSize, knobLabelSize);
        _labelTime.textSize = knobLabelSize * S;

        _knobOutput.position = rect(knobSize * 2, knobY, knobSize, knobSize);
        _labelOutput.position = rect(knobSize * 2, knobY + knobSize, knobSize, knobLabelSize);
        _labelOutput.textSize = knobLabelSize * S;

        _knobLowXover.position = rect(knobSize * 3, knobY, knobSize, knobSize);
        _labelLowXover.position = rect(knobSize * 3, knobY + knobSize, knobSize, knobLabelSize);
        _labelLowXover.textSize = knobLabelSize * S;

        // Multi-band Display
        int compHeight = 70;
        int compWidth = 350;
        int compKnobSize = 50;
        _display.position = rect(0, 200, compWidth, compHeight * 3 + 10 * 2);

        // Position TBA Tab labels and Band/Value labels
        {
            int dispX = 0;
            int dispY = 200;
            int dispW = 350;
            int dispH = 230;

            int pad = 6;
            int tabAreaW = 60;
            int attRelW = 70;
            int bandAreaH = dispH - pad - 18;
            int bandH = (bandAreaH - pad * 2) / 3;

            int tabX = dispW - tabAreaW - pad;
            int tabY = bandAreaH + 2;
            int tabBtnW = 18;
            int tabGap = 2;

            _labelTabT.position = rect(dispX + tabX + 0 * (tabBtnW + tabGap) + 4, dispY + tabY + 1, 10, 12);
            _labelTabT.textSize = 9 * S;
            _labelTabB.position = rect(dispX + tabX + 1 * (tabBtnW + tabGap) + 4, dispY + tabY + 1, 10, 12);
            _labelTabB.textSize = 9 * S;
            _labelTabA.position = rect(dispX + tabX + 2 * (tabBtnW + tabGap) + 4, dispY + tabY + 1, 10, 12);
            _labelTabA.textSize = 9 * S;

            int meterW = dispW - pad * 2 - attRelW - 4 - tabAreaW;
            int attRelX = pad + meterW + 4;

            for (int b = 0; b < 3; ++b) {
                int y = pad + b * (bandH + pad);

                _labelBandName[b].position = rect(dispX + pad + meterW - 35, dispY + y + 4, 32, 10);
                _labelBandName[b].textSize = 8 * S;

                _labelValTop[b].position = rect(dispX + attRelX, dispY + y + 8, 66, 12);
                _labelValTop[b].textSize = 9 * S;

                _labelValBottom[b].position = rect(dispX + attRelX, dispY + y + bandH - 18, 66, 12);
                _labelValBottom[b].textSize = 9 * S;
            }
        }

        // Right side knobs of left panel (H OUT, M OUT, L OUT)
        int compKnobY = 200;
        _knobHighOut.position = rect(350, compKnobY, compKnobSize, compKnobSize);
        _labelHighOut.position = rect(350, compKnobY + compKnobSize, compKnobSize, 15);
        _labelHighOut.textSize = 8 * S;

        compKnobY += compKnobSize + 25;
        _knobMidOut.position = rect(350, compKnobY, compKnobSize, compKnobSize);
        _labelMidOut.position = rect(350, compKnobY + compKnobSize, compKnobSize, 15);
        _labelMidOut.textSize = 8 * S;

        compKnobY += compKnobSize + 25;
        _knobLowOut.position = rect(350, compKnobY, compKnobSize, compKnobSize);
        _labelLowOut.position = rect(350, compKnobY + compKnobSize, compKnobSize, 15);
        _labelLowOut.textSize = 8 * S;

        // Bottom knobs / switches of left panel
        int bottomKnobY = compKnobY + compKnobSize + 30;
        _knobHighXover.position = rect(0, bottomKnobY, knobSize, knobSize);
        _labelHighXover.position = rect(0, bottomKnobY + knobSize, knobSize, 15);
        _labelHighXover.textSize = knobLabelSize * S;

        _switchSoftKnee.position = rect(knobSize + 25, bottomKnobY + 10, 50, 20);
        _labelSoftKnee.position = rect(knobSize + 25, bottomKnobY + knobSize, 50, 15);
        _labelSoftKnee.textSize = knobLabelSize * S;

        _switchRmsMode.position = rect(knobSize * 2 + 25, bottomKnobY + 10, 50, 20);
        _labelRmsMode.position = rect(knobSize * 2 + 25, bottomKnobY + knobSize, 50, 15);
        _labelRmsMode.textSize = knobLabelSize * S;

        // --- Right Sub-Pane Layout ---
        int paneX = 405; // starts slightly after left panel
        _subPaneBackground.position = rect(400, 0, 380, 580);

        _labelSubPaneTitle.position = rect(paneX, headerY, 350, 20);
        _labelSubPaneTitle.textSize = 18 * S;

        // Column headers position
        int subKnobSize = 48;
        int colGap = 8;
        int rowGap = 20;

        int headersY = 50;
        _labelHeaderAtt.position = rect(paneX + 50, headersY, subKnobSize, 15);
        _labelHeaderAtt.textSize = 8 * S;
        _labelHeaderRel.position = rect(paneX + 50 + (subKnobSize + colGap), headersY, subKnobSize, 15);
        _labelHeaderRel.textSize = 8 * S;
        _labelHeaderUpTh.position = rect(paneX + 50 + (subKnobSize + colGap) * 2, headersY, subKnobSize, 15);
        _labelHeaderUpTh.textSize = 8 * S;
        _labelHeaderUpRt.position = rect(paneX + 50 + (subKnobSize + colGap) * 3, headersY, subKnobSize, 15);
        _labelHeaderUpRt.textSize = 8 * S;
        _labelHeaderDnTh.position = rect(paneX + 50 + (subKnobSize + colGap) * 4, headersY, subKnobSize, 15);
        _labelHeaderDnTh.textSize = 8 * S;
        _labelHeaderDnRt.position = rect(paneX + 50 + (subKnobSize + colGap) * 5, headersY, subKnobSize, 15);
        _labelHeaderDnRt.textSize = 8 * S;

        // Rows for HIGH (0), MID (1), LOW (2)
        int curRowY = 80;
        for (int b = 0; b < 3; ++b) {
            // Row Label
            UILabel rowLab = (b == 0) ? _labelRowHigh : ((b == 1) ? _labelRowMid : _labelRowLow);
            rowLab.position = rect(paneX, curRowY + subKnobSize / 2 - 8, 40, 16);
            rowLab.textSize = 12 * S;

            int curX = paneX + 50;
            _knobAttack[b].position = rect(curX, curRowY, subKnobSize, subKnobSize);
            curX += subKnobSize + colGap;
            _knobRelease[b].position = rect(curX, curRowY, subKnobSize, subKnobSize);
            curX += subKnobSize + colGap;
            _knobUpThresh[b].position = rect(curX, curRowY, subKnobSize, subKnobSize);
            curX += subKnobSize + colGap;
            _knobUpRatio[b].position = rect(curX, curRowY, subKnobSize, subKnobSize);
            curX += subKnobSize + colGap;
            _knobDownThresh[b].position = rect(curX, curRowY, subKnobSize, subKnobSize);
            curX += subKnobSize + colGap;
            _knobDownRatio[b].position = rect(curX, curRowY, subKnobSize, subKnobSize);

            curRowY += subKnobSize + rowGap;
        }

        // Resizer at bottom right
        int hintSize = 20;
        _resizer.position = rect(context.getDefaultUIWidth - hintSize,
                                 context.getDefaultUIHeight - hintSize,
                                 hintSize, hintSize);
    }

    override void onAnimate(double dt, double time) {
        super.onAnimate(dt, time);
        updateDisplayLabels();
    }

    override void onParameterChanged(Parameter sender) {
        updateDisplayLabels();
    }
    override void onBeginParameterEdit(Parameter sender) {}
    override void onEndParameterEdit(Parameter sender) {}
    override void onBeginParameterHover(Parameter sender) {}
    override void onEndParameterHover(Parameter sender) {}

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

    void updateDisplayLabels() {
        if (!_display || !_labelValTop[0]) return;

        const int W = position.width;
        const float S = W / cast(float)(context.getDefaultUIWidth());

        auto tab = _display.activeTab;

        _labelTabT.textColor = (tab == HottDisplayUI.Tab.time) ? RGBA(0, 0, 0, 255) : RGBA(187, 187, 187, 0);
        _labelTabB.textColor = (tab == HottDisplayUI.Tab.below) ? RGBA(0, 0, 0, 255) : RGBA(187, 187, 187, 0);
        _labelTabA.textColor = (tab == HottDisplayUI.Tab.above) ? RGBA(0, 0, 0, 255) : RGBA(187, 187, 187, 0);

        _labelTabT.textSize = 9 * S;
        _labelTabB.textSize = 9 * S;
        _labelTabA.textSize = 9 * S;

        for (int b = 0; b < 3; ++b) {
            int dspB = 2 - b;
            _labelBandName[b].textColor = RGBA(255, 255, 255, 100);
            _labelBandName[b].textSize = 8 * S;

            _labelValTop[b].textColor = litColor;
            _labelValBottom[b].textColor = litColor;
            _labelValTop[b].textSize = 9 * S;
            _labelValBottom[b].textSize = 9 * S;
            
            if (tab == HottDisplayUI.Tab.time) {
                float attMs = attackNormToMs(_display.getParamValue(Params.lowAttack + dspB));
                float relMs = releaseNormToMs(_display.getParamValue(Params.lowRelease + dspB));
                
                _labelValTop[b].text = formatAttRel(_valTopBuf[b][], attMs, true);
                _labelValBottom[b].text = formatAttRel(_valBottomBuf[b][], relMs, false);
            } else if (tab == HottDisplayUI.Tab.below) {
                float upDb = upThreshNormToDb(_display.getParamValue(HottDisplayUI.getUpThreshParam(b)));
                float upRatio = ratioNormToRatio(_display.getParamValue(Params.lowUpRatio + dspB));
                
                _labelValTop[b].text = formatDb(_valTopBuf[b][], upDb);
                _labelValBottom[b].text = formatRatio(_valBottomBuf[b][], upRatio, true);
            } else if (tab == HottDisplayUI.Tab.above) {
                float downDb = downThreshNormToDb(_display.getParamValue(HottDisplayUI.getDownThreshParam(b)));
                float downRatio = ratioNormToRatio(_display.getParamValue(Params.lowDownRatio + dspB));
                
                _labelValTop[b].text = formatDb(_valTopBuf[b][], downDb);
                _labelValBottom[b].text = formatRatio(_valBottomBuf[b][], downRatio, false);
            }
        }
    }

    IHottClient _client;
    Parameter[] _params;
    Font _font;
    UILabel _title, _date, _labelAmount, _labelTime, _labelOutput, _labelLowXover,
            _labelHighOut, _labelMidOut, _labelLowOut,
            _labelHighXover, _labelSoftKnee, _labelRmsMode,
            _labelSubPaneTitle, _labelHeaderAtt, _labelHeaderRel, _labelHeaderUpTh, _labelHeaderUpRt, _labelHeaderDnTh, _labelHeaderDnRt,
            _labelRowHigh, _labelRowMid, _labelRowLow;

    // TBA Display Labels
    UILabel _labelTabT, _labelTabB, _labelTabA;
    UILabel[3] _labelBandName;
    UILabel[3] _labelValTop;
    UILabel[3] _labelValBottom;

    char[32][3] _valTopBuf;
    char[32][3] _valBottomBuf;

    UIWindowResizer _resizer;
    UIKnob _knobAmount, _knobTime, _knobOutput, _knobLowXover,
           _knobHighOut, _knobMidOut, _knobLowOut,
           _knobHighXover;
    UIOnOffSwitch _switchSoftKnee, _switchRmsMode;
    HottDisplayUI _display;

    // Sub-pane components
    HottSubPaneBackgroundUI _subPaneBackground;
    UIKnob[3] _knobAttack;
    UIKnob[3] _knobRelease;
    UIKnob[3] _knobUpThresh;
    UIKnob[3] _knobUpRatio;
    UIKnob[3] _knobDownThresh;
    UIKnob[3] _knobDownRatio;
}
