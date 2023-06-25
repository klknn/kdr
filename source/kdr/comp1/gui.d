module kdr.comp1.gui;

import dplug.client;
import dplug.gui;
import kdr.simplegui;

/// GUI for comp1.
class Comp1GUI : PBRSimpleGUI {
@nogc nothrow:
public:
  ///
  this(Parameter[] params) {
    static immutable float[] ratios = [1.0f, 1.25f, 1.5f, 1.75f, 2.0f];
    super(makeSizeConstraintsDiscrete(600, 300, ratios));
  }

  override void reflow() {
  }

}
