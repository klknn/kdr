/**
 * Empirical Challenge Harness for Milestone 1.
 * Tests parameter bounds, normalization, builder registrations, and StutterClient lifecycle.
 */
module tests.stutter_m1_challenge;

import std.traits : EnumMembers;
import core.memory : GC;
import core.math : fabs;
import std.math : isNaN, isInfinity;
import std.stdio : writeln, writefln;

import dplug.client : LegalIO, Parameter, TimeInfo;
import dplug.client.params : BoolParameter, EnumParameter, IntegerParameter,
  LinearFloatParameter, LogFloatParameter;
import dplug.core.nogc : destroyFree;

import kdr.params : buildParams, typedParam;
import kdr.stutter.params;
import kdr.stutter.client : StutterClient;

// =============================================================================
// Suite 1: Parameter Bounds, Normalization & Builder Registrations
// =============================================================================

void testParamsBuilderAndBounds() {
  writeln("[CHALLENGE] Running Suite 1: Parameter Bounds & Normalization Stress Tests...");

  Parameter[] ps = buildParams!Params();
  assert(ps.length == 137, "Expected 137 parameters");

  // 1. Verify every parameter index matches sequential order and non-null
  foreach (size_t i, p; ps) {
    assert(p !is null, "Null parameter detected at index");
    assert(p.index == cast(int)i, "Parameter index mismatch");
  }

  // 2. Verify all 137 parameters are accessible via typedParam
  static foreach (member; EnumMembers!Params) {
    {
      auto tp = typedParam!member(ps);
      assert(tp !is null, "typedParam failed for: " ~ __traits(identifier, member));
      assert(tp.index == cast(int)member, "typedParam index mismatch for: " ~ __traits(identifier, member));
    }
  }

  // 3. Verify helper enum array lengths
  assert(tvmCurvePresetNames.length == EnumMembers!TVMCurvePreset.length);
  assert(releaseModeNames.length == EnumMembers!ReleaseMode.length);
  assert(quantizeGridNames.length == EnumMembers!QuantizeGrid.length);
  assert(quantizeGridBeats.length == EnumMembers!QuantizeGrid.length);
  assert(gestureLengthNames.length == EnumMembers!GestureLength.length);
  assert(gestureLengthBeats.length == EnumMembers!GestureLength.length);
  assert(autoRateNames.length == EnumMembers!AutoRate.length);
  assert(autoRateBeats.length == EnumMembers!AutoRate.length);
  assert(stutterSubdivisionNames.length == EnumMembers!StutterSubdivision.length);
  assert(stutterSubdivisionBeats.length == EnumMembers!StutterSubdivision.length);
  assert(stutterQuantizeModeNames.length == EnumMembers!StutterQuantizeMode.length);
  assert(bufferDirectionNames.length == EnumMembers!BufferDirection.length);
  assert(gateSubdivisionNames.length == EnumMembers!GateSubdivision.length);
  assert(gateSubdivisionBeats.length == EnumMembers!GateSubdivision.length);
  assert(filterTypeNames.length == EnumMembers!FilterType.length);
  assert(phaserStagesNames.length == EnumMembers!PhaserStages.length);
  assert(delaySubdivisionNames.length == EnumMembers!DelaySubdivision.length);
  assert(delaySubdivisionBeats.length == EnumMembers!DelaySubdivision.length);
  assert(moduleSlotNames.length == EnumMembers!ModuleSlot.length);
  assert(moduleColors.length == EnumMembers!ModuleSlot.length);

  // 4. Normalization and boundary stress on all parameters
  foreach (p; ps) {
    // Check initial normalized value is in valid [0, 1]
    double initNorm = p.getNormalized();
    assert(initNorm >= 0.0 && initNorm <= 1.0, "Initial normalized value out of range");

    // Test setFromHost boundaries
    p.setFromHost(0.0);
    double norm0 = p.getNormalized();
    assert(norm0 >= 0.0 && norm0 <= 0.05, "setFromHost(0.0) did not yield lower bound");

    p.setFromHost(1.0);
    double norm1 = p.getNormalized();
    assert(norm1 >= 0.95 && norm1 <= 1.0, "setFromHost(1.0) did not yield upper bound");

    p.setFromHost(0.5);
    double normMid = p.getNormalized();
    assert(normMid >= 0.0 && normMid <= 1.0, "setFromHost(0.5) out of range");

    // Adversarial normalized inputs (clamping checks)
    p.setFromHost(-1.0);
    assert(p.getNormalized() >= 0.0 && p.getNormalized() <= 1.0);

    p.setFromHost(2.0);
    assert(p.getNormalized() >= 0.0 && p.getNormalized() <= 1.0);

    p.setFromHost(-1e20);
    assert(p.getNormalized() >= 0.0 && p.getNormalized() <= 1.0);

    p.setFromHost(1e20);
    assert(p.getNormalized() >= 0.0 && p.getNormalized() <= 1.0);

    // Restore initial normalized value
    p.setFromHost(initNorm);
  }

  // 5. Test specific parameter bounds
  auto filterMin = typedParam!(Params.filterCutoffMin)(ps);
  filterMin.setFromHost(0.0);
  assert(fabs(filterMin.value - 20.0) < 1e-2);
  filterMin.setFromHost(1.0);
  assert(fabs(filterMin.value - 20000.0) < 1.0);

  auto filterMax = typedParam!(Params.filterCutoffMax)(ps);
  filterMax.setFromHost(0.0);
  assert(fabs(filterMax.value - 20.0) < 1e-2);
  filterMax.setFromHost(1.0);
  assert(fabs(filterMax.value - 20000.0) < 1.0);

  auto limiterCeil = typedParam!(Params.limiterCeiling)(ps);
  limiterCeil.setFromHost(0.0);
  assert(fabs(limiterCeil.value - (-12.0f)) < 1e-3f);
  limiterCeil.setFromHost(1.0);
  assert(fabs(limiterCeil.value - (0.0f)) < 1e-3f);

  auto limiterThresh = typedParam!(Params.limiterThreshold)(ps);
  limiterThresh.setFromHost(0.0);
  assert(fabs(limiterThresh.value - (-24.0f)) < 1e-3f);
  limiterThresh.setFromHost(1.0);
  assert(fabs(limiterThresh.value - (0.0f)) < 1e-3f);

  auto limiterRel = typedParam!(Params.limiterRelease)(ps);
  limiterRel.setFromHost(0.0);
  assert(fabs(limiterRel.value - 1.0f) < 1e-3f);
  limiterRel.setFromHost(1.0);
  assert(fabs(limiterRel.value - 500.0f) < 1e-3f);

  auto panCenter = typedParam!(Params.panCenterMin)(ps);
  panCenter.setFromHost(0.0);
  assert(fabs(panCenter.value - (-1.0f)) < 1e-3f);
  panCenter.setFromHost(1.0);
  assert(fabs(panCenter.value - (1.0f)) < 1e-3f);

  auto activeGest = typedParam!(Params.activeGesture)(ps);
  activeGest.setFromHost(0.0);
  assert(activeGest.value == 0);
  activeGest.setFromHost(1.0);
  assert(activeGest.value == 23);

  auto bankPreset = typedParam!(Params.bankPreset)(ps);
  bankPreset.setFromHost(0.0);
  assert(bankPreset.value == 0);
  bankPreset.setFromHost(1.0);
  assert(bankPreset.value == 15);

  // Clean up allocated parameters
  foreach (p; ps) {
    destroyFree(p);
  }

  writeln("[CHALLENGE] Suite 1 Passed Successfully.");
}

// =============================================================================
// Suite 2: StutterClient Lifecycle, Extreme Scenarios & @nogc Guarantees
// =============================================================================

// Helper @nogc nothrow function to empirically verify @nogc nothrow callability
@nogc nothrow void callProcessAudioNoGC(StutterClient client, const(float*)[] inputs, float*[] outputs, int frames) {
  TimeInfo info;
  client.processAudio(inputs, outputs, frames, info);
}

@nogc nothrow void callResetNoGC(StutterClient client, double sampleRate, int maxFrames, int inChans, int outChans) {
  client.reset(sampleRate, maxFrames, inChans, outChans);
}

void testStutterClientLifecycleAndAudio() {
  writeln("[CHALLENGE] Running Suite 2: StutterClient Lifecycle & Audio Processing Stress Tests...");

  auto client = new StutterClient();
  assert(client !is null);

  // 1. Multi-sample rate stress
  static immutable double[] rates = [
    8000.0,
    11025.0,
    22050.0,
    32000.0,
    44100.0,
    48000.0,
    88200.0,
    96000.0,
    176400.0,
    192000.0,
    384000.0,
  ];

  static immutable int[] bufferSizes = [1, 2, 7, 16, 31, 32, 64, 128, 256, 512, 1024, 2048, 4096];

  foreach (rate; rates) {
    foreach (bufSize; [16, 32, 64, 512, 2048]) {
      callResetNoGC(client, rate, bufSize, 2, 2);
    }
  }

  // 1b. Rapid resets in tight loop (1,000 rapid resets alternating configurations)
  for (int r = 0; r < 1000; ++r) {
    double sRate = rates[r % rates.length];
    int bSize = bufferSizes[r % bufferSizes.length];
    int ch = (r % 2) + 1;
    callResetNoGC(client, sRate, bSize, ch, ch);
  }

  // 2. Varying buffer sizes & zero-length input testing
  float[4096] inBufL;
  float[4096] inBufR;
  float[4096] outBufL;
  float[4096] outBufR;

  for (int i = 0; i < 4096; ++i) {
    inBufL[i] = (i % 100) * 0.01f - 0.5f;
    inBufR[i] = -inBufL[i];
  }

  const(float*)[2] inputs2 = [inBufL.ptr, inBufR.ptr];
  float*[2] outputs2 = [outBufL.ptr, outBufR.ptr];

  // Zero-length frames test (must not divide by zero or crash)
  callProcessAudioNoGC(client, inputs2[], outputs2[], 0);

  // Varying buffer sizes
  foreach (frames; bufferSizes) {
    outBufL[] = 0.0f;
    outBufR[] = 0.0f;
    callProcessAudioNoGC(client, inputs2[], outputs2[], frames);

    // Verify bit-accurate passthrough
    for (int f = 0; f < frames; ++f) {
      assert(outBufL[f] == inBufL[f], "Left channel mismatch in passthrough");
      assert(outBufR[f] == inBufR[f], "Right channel mismatch in passthrough");
    }
  }

  // 3. Channel Aliasing Tests
  // 3a. In-place processing (inputs[0] is outputs[0])
  float[256] inPlaceBufL;
  float[256] inPlaceBufR;
  for (int i = 0; i < 256; ++i) {
    inPlaceBufL[i] = 0.123f * i;
    inPlaceBufR[i] = -0.456f * i;
  }
  const(float*)[2] inPlaceIn = [inPlaceBufL.ptr, inPlaceBufR.ptr];
  float*[2] inPlaceOut = [inPlaceBufL.ptr, inPlaceBufR.ptr];

  // Must not trigger D runtime overlapping array copy assertion!
  callProcessAudioNoGC(client, inPlaceIn[], inPlaceOut[], 256);
  for (int i = 0; i < 256; ++i) {
    assert(inPlaceBufL[i] == 0.123f * i, "In-place left buffer modified incorrectly");
    assert(inPlaceBufR[i] == -0.456f * i, "In-place right buffer modified incorrectly");
  }

  // 3b. Cross-channel aliasing (inputs[0] is outputs[1], inputs[1] is outputs[0])
  float[64] crossBufA;
  float[64] crossBufB;
  for (int i = 0; i < 64; ++i) {
    crossBufA[i] = 1.0f;
    crossBufB[i] = 2.0f;
  }
  const(float*)[2] crossIn = [crossBufA.ptr, crossBufB.ptr];
  float*[2] crossOut = [crossBufB.ptr, crossBufA.ptr];
  callProcessAudioNoGC(client, crossIn[], crossOut[], 64);

  // 3c. Shared input channels (inputs[0] is inputs[1])
  float[64] monoInBuf;
  float[64] splitOutL;
  float[64] splitOutR;
  for (int i = 0; i < 64; ++i) monoInBuf[i] = 0.777f;
  const(float*)[2] sharedIn = [monoInBuf.ptr, monoInBuf.ptr];
  float*[2] splitOut = [splitOutL.ptr, splitOutR.ptr];
  callProcessAudioNoGC(client, sharedIn[], splitOut[], 64);
  for (int i = 0; i < 64; ++i) {
    assert(splitOutL[i] == 0.777f);
    assert(splitOutR[i] == 0.777f);
  }

  // 3d. Shared output channels (outputs[0] is outputs[1])
  float[64] sharedOutBuf;
  float*[2] sharedOut = [sharedOutBuf.ptr, sharedOutBuf.ptr];
  callProcessAudioNoGC(client, inputs2[], sharedOut[], 64);
  // chan 0 writes inBufL to sharedOutBuf, then chan 1 writes inBufR to sharedOutBuf
  for (int i = 0; i < 64; ++i) {
    assert(sharedOutBuf[i] == inBufR[i]);
  }

  // 4. Asymmetric and Null Channel Scenarios
  // 4a. Mono in, Mono out
  const(float*)[1] monoIn = [inBufL.ptr];
  float*[1] monoOut = [outBufL.ptr];
  callProcessAudioNoGC(client, monoIn[], monoOut[], 64);
  for (int i = 0; i < 64; ++i) assert(outBufL[i] == inBufL[i]);

  // 4b. Mono in, Stereo out (output 1 must be zeroed)
  outBufR[] = 999.0f;
  callProcessAudioNoGC(client, monoIn[], outputs2[], 64);
  for (int i = 0; i < 64; ++i) {
    assert(outBufL[i] == inBufL[i]);
    assert(outBufR[i] == 0.0f, "Missing input channel was not zeroed");
  }

  // 4c. Stereo in, Mono out
  callProcessAudioNoGC(client, inputs2[], monoOut[], 64);
  for (int i = 0; i < 64; ++i) assert(outBufL[i] == inBufL[i]);

  // 4d. Null channel pointer in inputs
  const(float*)[2] nullChanIn = [null, inBufR.ptr];
  outBufL[] = 888.0f;
  callProcessAudioNoGC(client, nullChanIn[], outputs2[], 64);
  for (int i = 0; i < 64; ++i) {
    assert(outBufL[i] == 0.0f, "Null input channel was not zeroed");
    assert(outBufR[i] == inBufR[i]);
  }

  // 4e. Zero outputs (outputs.length == 0)
  callProcessAudioNoGC(client, inputs2[], (float*[]).init, 64);

  // 4f. Zero inputs (inputs.length == 0)
  outBufL[] = 777.0f;
  outBufR[] = 777.0f;
  callProcessAudioNoGC(client, (const(float*)[]).init, outputs2[], 64);
  for (int i = 0; i < 64; ++i) {
    assert(outBufL[i] == 0.0f);
    assert(outBufR[i] == 0.0f);
  }

  // 5. Audio Value Extremes
  float[32] extremeIn;
  float[32] extremeOut;
  const(float*)[1] extInSlice = [extremeIn.ptr];
  float*[1] extOutSlice = [extremeOut.ptr];

  // DC Bias
  extremeIn[] = 1.0f;
  callProcessAudioNoGC(client, extInSlice[], extOutSlice[], 32);
  assert(extremeOut[0] == 1.0f);

  // Massive Gain Spike (+100 dBFS / 100000.0f)
  extremeIn[] = 100000.0f;
  callProcessAudioNoGC(client, extInSlice[], extOutSlice[], 32);
  assert(extremeOut[0] == 100000.0f);

  // Subnormals / Denormals
  extremeIn[] = 1e-35f;
  callProcessAudioNoGC(client, extInSlice[], extOutSlice[], 32);
  assert(extremeOut[0] == 1e-35f);

  // Special IEEE 754: NaN & Inf
  extremeIn[0] = float.infinity;
  extremeIn[1] = -float.infinity;
  extremeIn[2] = float.nan;
  callProcessAudioNoGC(client, extInSlice[], extOutSlice[], 3);
  assert(isInfinity(extremeOut[0]));
  assert(isInfinity(extremeOut[1]));
  assert(isNaN(extremeOut[2]));

  // 6. Empirical Zero-GC Verification
  GC.collect();
  auto gcStatsBefore = GC.stats();

  // Run 100,000 blocks of processAudio under heavy iteration
  for (int iteration = 0; iteration < 100_000; ++iteration) {
    callProcessAudioNoGC(client, inputs2[], outputs2[], 32);
  }

  auto gcStatsAfter = GC.stats();
  assert(gcStatsAfter.usedSize == gcStatsBefore.usedSize,
    "GC allocations detected during real-time processAudio!");

  writeln("[CHALLENGE] Suite 2 Passed Successfully.");
}

unittest {
  writeln("=== [Challenger M1_1] Starting Empirical Verification of Milestone 1 ===");
  testParamsBuilderAndBounds();
  testStutterClientLifecycleAndAudio();
  writeln("=== [Challenger M1_1] All Milestone 1 Empirical Challenges PASSED ===");
}
