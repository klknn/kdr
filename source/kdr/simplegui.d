module kdr.simplegui;

import dplug.gui;

class PBRSimpleGUI : GUIGraphics {
 public:
  @nogc nothrow:
  this(SizeConstraints size, RGBA color = RGBA(114, 114, 114, 0)) {
    super(size, flagPBR | flagAnimated);
    _color = color;
  }

  override void onDrawPBR(
      ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap,
      ImageRef!RGBA materialMap, box2i[] dirtyRects) {
    foreach(dirtyRect; dirtyRects) {
      fill(diffuseMap, dirtyRect, _color);
      fill(depthMap, dirtyRect, L16(0));
      fill(materialMap, dirtyRect, RGBA(0, 0, 0, 0));
    }
  }

 private:
  void fill(T)(ImageRef!T map, box2i dirtyRect, T color) {
    ImageRef!T rawout = map.cropImageRef(dirtyRect);
    auto owned = mallocNew!(OwnedImage!T)(rawout.w, rawout.h);
    scope (exit) destroyFree(owned);
    owned.fillWith(color);
    blitTo(owned, rawout);
  }

  RGBA _color;
}


unittest {
  int w = 100, h = 100;
  auto gui = new PBRSimpleGUI(makeSizeConstraintsFixed(w, h));
  auto dif = new OwnedImage!RGBA(w, h);
  auto dep = new OwnedImage!L16(w, h);
  auto mat = new OwnedImage!RGBA(w, h);
  gui.onDrawPBR(toRef(dif), toRef(dep), toRef(mat), [rectangle(0, 0, w, h)]);
}
