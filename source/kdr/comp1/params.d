module kdr.comp1.params;

import dplug.client;
import dplug.core;

enum Params {
  depth,
  time,
  inGain,
  outGain,
  gainH,
  gainM,
  gainL,
  belowThresholdH,
  aboveThresholdH,
  belowThresholdM,
  aboveThresholdM,
  belowThresholdL,
  aboveThresholdL,
  upwardStrength,
  downwardStrength,
}

@nogc nothrow
Parameter[] buildParams() {
  Vec!Parameter params;
  int n = 0;
  params.pushBack(mallocNew!LinearFloatParameter(n++, "Depth", "", 0.0, 100.0, 100.0));
  params.pushBack(mallocNew!LogFloatParameter(n++, "Time", "", 1e-3, 1000.0, 100.0));
  params.pushBack(mallocNew!GainParameter(n++, "In Gain", 19.1, 0.0));
  params.pushBack(mallocNew!GainParameter(n++, "Out Gain", 19.1, 0.0));
  params.pushBack(mallocNew!GainParameter(n++, "Gain H", 6.0, 0.0));
  params.pushBack(mallocNew!GainParameter(n++, "Gain M", 6.0, 0.0));
  params.pushBack(mallocNew!GainParameter(n++, "Gain L", 6.0, 0.0));

  params.pushBack(mallocNew!GainParameter(n++, "Below Threshold H", 0.0, -40.8));
  params.pushBack(mallocNew!GainParameter(n++, "Above Threshold H", 0.0, -35.5));
  params.pushBack(mallocNew!GainParameter(n++, "Below Threshold M", 0.0, -41.8));
  params.pushBack(mallocNew!GainParameter(n++, "Above Threshold M", 0.0, -30.2));
  params.pushBack(mallocNew!GainParameter(n++, "Below Threshold L", 0.0, -40.8));
  params.pushBack(mallocNew!GainParameter(n++, "Above Threshold M", 0.0, -33.8));

  params.pushBack(mallocNew!LinearFloatParameter(n++, "Upwd Strgth", "", 0.0, 200.0, 100.0));
  params.pushBack(mallocNew!LinearFloatParameter(n++, "Dnwd Strgth", "", 0.0, 200.0, 100.0));

  return params.releaseData();
}
