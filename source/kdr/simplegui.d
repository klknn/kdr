module kdr.simplegui;

import dplug.gui;

class PBRSimpleGUI : GUIGraphics {
 public:
  @nogc nothrow:
  this(SizeConstraints size, RGBA color = RGBA(114, 114, 114, 0)) {
    super(size, flagPBR | flagAnimated);
    _color = color;
  }

  override void onDrawPBR(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects) {
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
