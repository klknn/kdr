module kdr.comp1.params;

import dplug.client;
import dplug.core;

enum Params {
  depth,
  time,
  inGain,
  outGain,
}

@nogc nothrow
Parameter[] buildParams() {
  Vec!Parameter params;
  params.pushBack(mallocNew!LinearFloatParameter(0, "depth", "", 0.0, 100.0, 100.0));
  params.pushBack(mallocNew!LogFloatParameter(1, "time", "", 1e-3, 1000.0, 100.0));
  params.pushBack(mallocNew!GainParameter(2, "In Gain", 19.1, 0.0));
  params.pushBack(mallocNew!GainParameter(3, "Out Gain", 19.1, 0.0));

  return params.releaseData();
}
