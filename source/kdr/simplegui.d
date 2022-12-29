module kdr.simplegui;

import dplug.core : mallocNew, destroyFree;
import dplug.math : box2i, rectangle;
import dplug.graphics : blitTo, cropImageRef, ImageRef, OwnedImage, RGBA, toRef, L16;
import dplug.gui : flagPBR, flagAnimated, GUIGraphics, SizeConstraints, makeSizeConstraintsFixed;

/// Minimalist GUI for PBR elements.
class PBRSimpleGUI : GUIGraphics {
 public:
  @nogc nothrow:
  this(SizeConstraints size, RGBA color = RGBA(114, 114, 114, 0)) {
    super(size, flagPBR | flagAnimated);
    _color = color;
  }

  override void onDrawPBR(
      ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap,
      ImageRef!RGBA materialMap, box2i[] dirtyRects) const pure {
    foreach(dirtyRect; dirtyRects) {
      fill(diffuseMap, dirtyRect, _color);
      fill(depthMap, dirtyRect, L16(0));
      fill(materialMap, dirtyRect, RGBA(0, 0, 0, 0));
    }
  }

 private:
  void fill(T)(ImageRef!T map, box2i dirtyRect, T color) const pure {
    ImageRef!T output = map.cropImageRef(dirtyRect);
    foreach (y; 0 .. output.h) {
      output.scanline(y)[0 .. $] = color;
    }
  }

  RGBA _color;
}

nothrow
unittest {
  int w = 100, h = 100;
  RGBA color = RGBA(42, 42, 42, 42);
  auto gui = new PBRSimpleGUI(makeSizeConstraintsFixed(w, h), color);
  auto dif = new OwnedImage!RGBA(w, h);
  auto dep = new OwnedImage!L16(w, h);
  auto mat = new OwnedImage!RGBA(w, h);
  gui.onDrawPBR(toRef(dif), toRef(dep), toRef(mat), [rectangle(0, 0, w, h)]);

  assert(dif[0, 0] == color);
  assert(dif[w-1, h-1] == color);

  assert(dep[0, 0] == L16(0));
  assert(dep[w-1, h-1] == L16(0));

  assert(mat[0, 0] == RGBA(0, 0, 0, 0));
  assert(mat[w-1, h-1] == RGBA(0, 0, 0, 0));
}
