module kdr.envtool.params;

import kdr.params : RegisterBuilder;

@RegisterBuilder
enum Params {
  beatScale,
  depth,
  stereoOffset,
  volumeMod,
  filterMod,
  filterMode,
  filterCutoff,
  filterRes,
}
