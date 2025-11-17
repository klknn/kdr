module kdr.fm6.gui;

import dplug.client;
import dplug.gui;
import kdr.simplegui : PBRSimpleGUI;

///
class Fm6GUI : PBRSimpleGUI {
  ///
  @nogc nothrow
  this(Parameter[] params) {
    static immutable float[] ratios = [1.0f, 1.25f, 1.5f, 1.75f, 2.0f];
    super(makeSizeConstraintsDiscrete(600, 400, ratios));
  }
}
