module kdr.fm6.gui;

import std.algorithm : min;

import dplug.core;
import dplug.client;
import dplug.gui;
import dplug.pbrwidgets;
import kdr.simplegui : PBRSimpleGUI;

enum RGBA lineColor = RGBA(0, 255, 255, 96);
enum RGBA gradColor = RGBA(0, 64, 64, 96);
enum RGBA gridColor = RGBA(100, 200, 200, 32);
enum RGBA darkColor = RGBA(128, 128, 128, 128);
enum RGBA lightColor = RGBA(100, 200, 200, 100);
enum RGBA textColor = RGBA(155, 255, 255, 0);
enum RGBA knobColor = RGBA(96, 96, 96, 96);
enum RGBA litColor = RGBA(155, 255, 255, 0);
enum RGBA unlitColor = RGBA(0, 32, 32, 0);

enum int numOps = 6;

///
class Fm6GUI : PBRSimpleGUI {
public:
  ///
  @nogc nothrow
  this(Parameter[] params) {
    static immutable float[] ratios = [1.0f, 1.25f, 1.5f, 1.75f, 2.0f];
    super(makeSizeConstraintsDiscrete(600, 400, ratios));

    this._params = params;

    int opIdx = 0;
    foreach (x; 0 .. numOps) {
      foreach (y; 0 .. numOps) {
        _opKnobs[opIdx] = buildKnob(params[opIdx]);
        ++opIdx;
      }
    }
  }

  override void reflow() {
    super.reflow();
    int W = this.position.width;
    int H = this.position.height;
    int knobSize = min(W, H) / numOps;
    int opIdx = 0;
    foreach (x; 0 .. numOps) {
      foreach (y; 0 .. numOps) {
        _opKnobs[opIdx].position = rectangle(x * knobSize, y * knobSize, knobSize, knobSize);
        ++opIdx;
      }
    }
  }

private:
@nogc nothrow:

  UIKnob buildKnob(Parameter p) {
    UIKnob knob;
    addChild(knob = mallocNew!UIKnob(this.context, p));
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

  Parameter[] _params;
  UIKnob[numOps * numOps] _opKnobs;
}
