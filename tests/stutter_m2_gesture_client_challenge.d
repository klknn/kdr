/**
 * Empirical Challenge Harness for Milestone 2: Gesture Controller & Client Lifecycle.
 *
 * Stress-tests:
 * 1. All 4 release modes (Instant, Latch, Full Gesture, On Grid) under erratic MIDI streams.
 * 2. Auto Mode vs MIDI Trigger Mode mid-playback switching without phase discontinuities or dropouts.
 * 3. Stopped host transport fallbacks (tempo=0, hostIsPlaying=false), negative song beats, extreme tempos (20 & 999 BPM).
 * 4. Client lifecycle: multi-sample-rates (8kHz to 384kHz), varying buffer sizes (1 to 4096),
 *    rapid reset() cycles, channel topologies (mono, stereo, in-place aliasing), and real-time @nogc zero-allocation safety.
 *
 * Conforms to PROJECT.md layout: placed in tests/ directory and executed via `dub test`.
 *
 * Copyright: kdr 2026.
 * License: Boost License 1.0.
 */
module tests.stutter_m2_gesture_client_challenge;

import core.memory : GC;
import core.math : fabs;
import std.math : isNaN, isInfinity, isFinite, abs, sin, PI;
import std.stdio : writeln, writefln;

import dplug.client : LegalIO, MidiMessage, Parameter, TimeInfo,
  makeMidiMessageNoteOn, makeMidiMessageNoteOff;
import dplug.core.nogc : destroyFree;

import kdr.params : typedParam;
import kdr.stutter.params;
import kdr.stutter.gesture;
import kdr.stutter.stutter;
import kdr.stutter.buffer;
import kdr.stutter.client;

// =============================================================================
// Helper Functions & Wrappers
// =============================================================================

@nogc nothrow void callProcessAudioNoGC(StutterClient client, const(float*)[] inputs, float*[] outputs, int frames, TimeInfo info) {
  client.processAudio(inputs, outputs, frames, info);
}

@nogc nothrow void callResetNoGC(StutterClient client, double sampleRate, int maxFrames, int inChans, int outChans) {
  client.reset(sampleRate, maxFrames, inChans, outChans);
}

// =============================================================================
// Suite 1: All 4 Release Modes Under Erratic MIDI Streams
// =============================================================================

void testErraticMidiAndReleaseModes() {
  writeln("[CHALLENGE M2_2] Suite 1: Testing all 4 release modes under erratic MIDI streams...");

  // ---------------------------------------------------------------------------
  // 1.1: ReleaseMode.instant
  // ---------------------------------------------------------------------------
  {
    GestureController ctrl;
    ctrl.reset(44100.0);
    ctrl.setParams(false, ReleaseMode.instant, 4.0f, QuantizeGrid.instant);

    const double bps = 120.0 / (60.0 * 44100.0); // 120 BPM
    float phase;
    bool active;
    int gIdx;
    bool triggered;

    // Single note trigger & instant release
    ctrl.handleMidi(makeMidiMessageNoteOn(0, 0, 36, 100), 0.0);
    ctrl.advanceSample(bps, phase, active, gIdx, triggered);
    assert(active, "Instant: should be active after Note-On");
    assert(gIdx == 0, "Instant: Note 36 maps to gesture 0");
    assert(triggered, "Instant: should flag triggered on Note-On");

    // Advance 50 samples
    for (int i = 0; i < 50; ++i) {
      ctrl.advanceSample(bps, phase, active, gIdx, triggered);
      assert(active);
      assert(phase > 0.0f);
    }

    // Note-Off -> immediate deactivation
    ctrl.handleMidi(makeMidiMessageNoteOff(0, 0, 36), 50.0 * bps);
    ctrl.advanceSample(bps, phase, active, gIdx, triggered);
    assert(!active, "Instant: must deactivate immediately on Note-Off");
    assert(phase == 0.0f, "Instant: phase must reset to 0 on release");

    // Rapid erratic note stream (1,000 iterations of rapid alternation)
    for (int iter = 0; iter < 1000; ++iter) {
      const int noteA = 36 + (iter % 12);
      const int noteB = 48 + ((iter * 7) % 12);

      // Note A On
      ctrl.handleMidi(makeMidiMessageNoteOn(0, 0, noteA, 100), iter * 4 * bps);
      ctrl.advanceSample(bps, phase, active, gIdx, triggered);
      assert(active);
      assert(gIdx == mapMidiNoteToGesture(noteA));

      // Note B On (simultaneous with Note A)
      ctrl.handleMidi(makeMidiMessageNoteOn(0, 0, noteB, 110), (iter * 4 + 1) * bps);
      ctrl.advanceSample(bps, phase, active, gIdx, triggered);
      assert(active);
      assert(gIdx == mapMidiNoteToGesture(noteB), "Last-note priority must select Note B");
      assert(ctrl.numHeldNotes == 2);

      // Note A Off (Note B remains held)
      ctrl.handleMidi(makeMidiMessageNoteOff(0, 0, noteA), (iter * 4 + 2) * bps);
      ctrl.advanceSample(bps, phase, active, gIdx, triggered);
      assert(active);
      assert(gIdx == mapMidiNoteToGesture(noteB), "Note B still held, should remain active");
      assert(ctrl.numHeldNotes == 1);

      // Note B Off (all notes released)
      ctrl.handleMidi(makeMidiMessageNoteOff(0, 0, noteB), (iter * 4 + 3) * bps);
      ctrl.advanceSample(bps, phase, active, gIdx, triggered);
      assert(!active, "All notes released: must return to idle");
      assert(ctrl.numHeldNotes == 0);
    }

    // Chords: 5 notes simultaneously triggered
    ctrl.handleMidi(makeMidiMessageNoteOn(0, 0, 36, 100), 0.0);
    ctrl.handleMidi(makeMidiMessageNoteOn(0, 0, 40, 100), 0.0);
    ctrl.handleMidi(makeMidiMessageNoteOn(0, 0, 43, 100), 0.0);
    ctrl.handleMidi(makeMidiMessageNoteOn(0, 0, 48, 100), 0.0);
    ctrl.handleMidi(makeMidiMessageNoteOn(0, 0, 55, 100), 0.0);
    assert(ctrl.numHeldNotes == 5);

    // Release in reverse order: 55, 48, 43, 40, 36
    ctrl.handleMidi(makeMidiMessageNoteOff(0, 0, 55), 0.1);
    ctrl.advanceSample(bps, phase, active, gIdx, triggered);
    assert(active && gIdx == mapMidiNoteToGesture(48));

    ctrl.handleMidi(makeMidiMessageNoteOff(0, 0, 48), 0.2);
    ctrl.advanceSample(bps, phase, active, gIdx, triggered);
    assert(active && gIdx == mapMidiNoteToGesture(43));

    ctrl.handleMidi(makeMidiMessageNoteOff(0, 0, 43), 0.3);
    ctrl.advanceSample(bps, phase, active, gIdx, triggered);
    assert(active && gIdx == mapMidiNoteToGesture(40));

    ctrl.handleMidi(makeMidiMessageNoteOff(0, 0, 40), 0.4);
    ctrl.advanceSample(bps, phase, active, gIdx, triggered);
    assert(active && gIdx == mapMidiNoteToGesture(36));

    ctrl.handleMidi(makeMidiMessageNoteOff(0, 0, 36), 0.5);
    ctrl.advanceSample(bps, phase, active, gIdx, triggered);
    assert(!active);
    assert(ctrl.numHeldNotes == 0);

    // Boundary MIDI notes: 0 and 127
    assert(mapMidiNoteToGesture(0) >= 0 && mapMidiNoteToGesture(0) < MAX_GESTURES);
    assert(mapMidiNoteToGesture(127) >= 0 && mapMidiNoteToGesture(127) < MAX_GESTURES);
    ctrl.handleMidi(makeMidiMessageNoteOn(0, 0, 0, 100), 0.0);
    ctrl.advanceSample(bps, phase, active, gIdx, triggered);
    assert(active && gIdx == mapMidiNoteToGesture(0));
    ctrl.handleMidi(makeMidiMessageNoteOff(0, 0, 0), 0.1);
    ctrl.advanceSample(bps, phase, active, gIdx, triggered);
    assert(!active);

    ctrl.handleMidi(makeMidiMessageNoteOn(0, 0, 127, 100), 0.0);
    ctrl.advanceSample(bps, phase, active, gIdx, triggered);
    assert(active && gIdx == mapMidiNoteToGesture(127));
    ctrl.handleMidi(makeMidiMessageNoteOff(0, 0, 127), 0.1);
    ctrl.advanceSample(bps, phase, active, gIdx, triggered);
    assert(!active);

    // All-notes-off panic
    ctrl.handleMidi(makeMidiMessageNoteOn(0, 0, 36, 100), 0.0);
    ctrl.handleMidi(makeMidiMessageNoteOn(0, 0, 40, 100), 0.0);
    ctrl.allNotesOff();
    ctrl.advanceSample(bps, phase, active, gIdx, triggered);
    assert(!active && ctrl.numHeldNotes == 0);
  }

  // ---------------------------------------------------------------------------
  // 1.2: ReleaseMode.latch
  // ---------------------------------------------------------------------------
  {
    GestureController ctrl;
    ctrl.reset(44100.0);
    ctrl.setParams(false, ReleaseMode.latch, 2.0f, QuantizeGrid.instant);

    const double bps = 120.0 / (60.0 * 44100.0); // 120 BPM: 2.0 beats = 44,100 samples
    float phase;
    bool active;
    int gIdx;
    bool triggered;

    // Trigger Note 36 and release immediately at sample 10
    ctrl.handleMidi(makeMidiMessageNoteOn(0, 0, 36, 100), 0.0);
    for (int i = 0; i < 10; ++i) {
      ctrl.advanceSample(bps, phase, active, gIdx, triggered);
    }
    assert(active && gIdx == 0);

    // Release Note 36
    ctrl.handleMidi(makeMidiMessageNoteOff(0, 0, 36), 10.0 * bps);
    ctrl.advanceSample(bps, phase, active, gIdx, triggered);
    assert(active, "Latch: MUST remain active after Note-Off!");
    assert(ctrl.numHeldNotes == 0);

    // Advance through 3 complete gesture cycles (3 * 44,100 = 132,300 samples + float accumulator margin)
    int loopCount = 0;
    float prevP = phase;
    for (int i = 0; i < 133_000; ++i) {
      ctrl.advanceSample(bps, phase, active, gIdx, triggered);
      assert(active, "Latch: MUST continue running indefinitely");
      assert(phase >= 0.0f && phase < 1.0f);
      if (phase < prevP - 0.5f) {
        loopCount++;
        if (loopCount == 3) break;
      }
      prevP = phase;
    }
    assert(loopCount == 3, "Latch: expected exactly 3 loop boundary wraps");

    // Trigger Note 40 while latched: seamlessly updates active gesture
    ctrl.handleMidi(makeMidiMessageNoteOn(0, 0, 40, 100), 10.0);
    ctrl.advanceSample(bps, phase, active, gIdx, triggered);
    assert(active && gIdx == mapMidiNoteToGesture(40));

    // Release Note 40: continues looping Note 40's gesture
    ctrl.handleMidi(makeMidiMessageNoteOff(0, 0, 40), 10.1);
    ctrl.advanceSample(bps, phase, active, gIdx, triggered);
    assert(active && gIdx == mapMidiNoteToGesture(40));

    // Calling allNotesOff() cleanly stops latched mode
    ctrl.allNotesOff();
    ctrl.advanceSample(bps, phase, active, gIdx, triggered);
    assert(!active, "allNotesOff must terminate latch");
  }

  // ---------------------------------------------------------------------------
  // 1.3: ReleaseMode.fullGesture
  // ---------------------------------------------------------------------------
  {
    GestureController ctrl;
    ctrl.reset(44100.0);
    ctrl.setParams(false, ReleaseMode.fullGesture, 1.0f, QuantizeGrid.instant);

    // 1.0 beat at 120 BPM = 22,050 samples
    const double bps = 120.0 / (60.0 * 44100.0);
    float phase;
    bool active;
    int gIdx;
    bool triggered;

    // Trigger Note 36
    ctrl.handleMidi(makeMidiMessageNoteOn(0, 0, 36, 100), 0.0);
    ctrl.advanceSample(bps, phase, active, gIdx, triggered);
    assert(active);

    // Release early at sample 100 (phase ≈ 0.0045)
    for (int i = 0; i < 99; ++i) {
      ctrl.advanceSample(bps, phase, active, gIdx, triggered);
    }
    ctrl.handleMidi(makeMidiMessageNoteOff(0, 0, 36), 100.0 * bps);
    ctrl.advanceSample(bps, phase, active, gIdx, triggered);
    assert(active, "Full Gesture: MUST remain active after early Note-Off");

    // Advance to sample 22,000 (well past Note-Off at 100, remaining active throughout)
    for (int i = 101; i < 22_000; ++i) {
      ctrl.advanceSample(bps, phase, active, gIdx, triggered);
      assert(active, "Full Gesture: MUST stay active until gesture completes");
      assert(phase < 1.0f);
    }

    // Advance until gesture completes (phase reaches 1.0 around sample 22,048-22,050)
    bool deactivated = false;
    for (int i = 22_000; i < 22_150; ++i) {
      ctrl.advanceSample(bps, phase, active, gIdx, triggered);
      if (!active) {
        deactivated = true;
        break;
      }
    }
    assert(deactivated, "Full Gesture: MUST deactivate once full gesture completes");
    assert(phase == 0.0f);

    // If Note remains held throughout gesture, it loops
    ctrl.handleMidi(makeMidiMessageNoteOn(0, 0, 36, 100), 0.0);
    for (int i = 0; i < 44_100; ++i) { // 2 full cycles with key held
      ctrl.advanceSample(bps, phase, active, gIdx, triggered);
      assert(active, "Full Gesture: should loop while note is held");
    }
    ctrl.handleMidi(makeMidiMessageNoteOff(0, 0, 36), 2.0);
    // Now it completes the current cycle and then stops
    for (int i = 0; i < 25_000; ++i) {
      ctrl.advanceSample(bps, phase, active, gIdx, triggered);
    }
    assert(!active, "Full Gesture: should deactivate after completing current cycle");
  }

  // ---------------------------------------------------------------------------
  // 1.4: ReleaseMode.onGrid
  // ---------------------------------------------------------------------------
  {
    GestureController ctrl;
    ctrl.reset(44100.0);
    // 1/4 note grid = 1.0 beat = 22,050 samples at 120 BPM
    ctrl.setParams(false, ReleaseMode.onGrid, 4.0f, QuantizeGrid.grid1_4);

    const double bps = 120.0 / (60.0 * 44100.0);
    float phase;
    bool active;
    int gIdx;
    bool triggered;

    // Start playback at beat 0.0
    ctrl.updateHostTransport(true, 0.0);

    // Note-On right on beat 0.0 -> triggers immediately
    ctrl.handleMidi(makeMidiMessageNoteOn(0, 0, 36, 100), 0.0);
    ctrl.advanceSample(bps, phase, active, gIdx, triggered);
    assert(active);

    // Advance to beat 0.4 (8,820 samples) - between grid boundaries [0.0 .. 1.0]
    for (int i = 1; i < 8820; ++i) {
      ctrl.updateHostTransport(true, cast(double) i * bps);
      ctrl.advanceSample(bps, phase, active, gIdx, triggered);
      assert(active);
    }

    // Release Note-Off at beat 0.4
    const double releaseBeat = 8820.0 * bps;
    ctrl.handleMidi(makeMidiMessageNoteOff(0, 0, 36), releaseBeat);
    ctrl.advanceSample(bps, phase, active, gIdx, triggered);
    assert(active, "On Grid: MUST remain active until next grid boundary (beat 1.0)");
    assert(ctrl.getState() == GestureState.pendingRelease);

    // Advance to beat 0.99 (21,829 samples)
    for (int i = 8821; i < 21_829; ++i) {
      ctrl.updateHostTransport(true, cast(double) i * bps);
      ctrl.advanceSample(bps, phase, active, gIdx, triggered);
      assert(active, "On Grid: MUST still be active at beat 0.99");
    }

    // Advance past beat 1.0 (22,050 samples) -> deactivates cleanly at grid boundary!
    bool gridDeactivated = false;
    for (int i = 21_829; i < 22_200; ++i) {
      ctrl.updateHostTransport(true, cast(double) i * bps);
      ctrl.advanceSample(bps, phase, active, gIdx, triggered);
      if (!active) {
        gridDeactivated = true;
        // Verify deactivation occurred close to beat 1.0
        const double curBeats = cast(double) i * bps;
        assert(curBeats >= 1.0 - 1e-4, "Deactivated before beat 1.0!");
        break;
      }
    }
    assert(gridDeactivated, "On Grid: MUST deactivate at beat 1.0 boundary");
  }

  writeln("[CHALLENGE M2_2] Suite 1 Passed Successfully.");
}

// =============================================================================
// Suite 2: Auto Mode vs MIDI Trigger Mode Mid-Playback Transitions
// =============================================================================

void testAutoVsMidiTriggerModeSwitching() {
  writeln("[CHALLENGE M2_2] Suite 2: Testing Auto Mode vs MIDI Mode switching mid-playback...");

  auto client = new StutterClient();
  client.reset(44100.0, 32, 2, 2);

  TimeInfo info;
  info.tempo = 120.0;
  info.hostIsPlaying = true;
  info.timeInSamples = 0;

  // Prepare sinusoidal audio buffers
  float[32] inL, inR;
  float[32] outL, outR;
  const(float)*[2] inPtrs = [inL.ptr, inR.ptr];
  float*[2] outPtrs = [outL.ptr, outR.ptr];

  // Helper to generate sine wave block
  void fillSine(long startSample) {
    for (int f = 0; f < 32; ++f) {
      const double t = cast(double)(startSample + f) / 44100.0;
      inL[f] = cast(float) sin(2.0 * PI * 440.0 * t) * 0.5f;
      inR[f] = cast(float) sin(2.0 * PI * 880.0 * t) * 0.5f;
    }
  }

  // 1. Start in Auto Mode
  client.param(Params.autoMode).setFromHost(1.0);
  client.param(Params.releaseMode).setFromHost(0.0); // Instant release for direct MIDI release testing
  client.param(Params.quantizeGrid).setFromHost(0.0); // Instant grid for direct MIDI testing
  assert(client.readParam!bool(Params.autoMode) == true);

  // Run 10 blocks (320 frames) in Auto Mode
  for (int b = 0; b < 10; ++b) {
    fillSine(info.timeInSamples);
    callProcessAudioNoGC(client, inPtrs[], outPtrs[], 32, info);
    info.timeInSamples += 32;

    for (int f = 0; f < 32; ++f) {
      assert(isFinite(outL[f]) && !isNaN(outL[f]));
      assert(isFinite(outR[f]) && !isNaN(outR[f]));
      assert(fabs(outL[f]) <= 2.0f);
    }
  }
  assert(client.gestureController().getIsActive(), "Auto mode must be active during playback");

  // 2. Mid-playback switch: Auto Mode -> MIDI Trigger Mode (no notes held)
  client.param(Params.autoMode).setFromHost(0.0);
  assert(client.readParam!bool(Params.autoMode) == false);

  // During subsequent blocks, gateCrossfader must fade from stutter to dry over 64 samples
  float prevSampleL = outL[31];
  for (int b = 0; b < 5; ++b) {
    fillSine(info.timeInSamples);
    callProcessAudioNoGC(client, inPtrs[], outPtrs[], 32, info);
    info.timeInSamples += 32;

    for (int f = 0; f < 32; ++f) {
      assert(isFinite(outL[f]) && !isNaN(outL[f]));
      assert(isFinite(outR[f]) && !isNaN(outR[f]));
      // Verify no abrupt audio dropouts or massive step discontinuity
      const float stepDelta = fabs(outL[f] - prevSampleL);
      assert(stepDelta < 0.8f, "Discontinuity or dropout detected during Auto -> MIDI transition");
      prevSampleL = outL[f];
    }
  }

  // Once crossfade completes, client must be in idle dry passthrough
  assert(!client.gestureController().getIsActive(), "MIDI mode with no notes should be idle");
  assert(!client.stutterEngine().isStuttering(), "Stutter engine must finish release crossfade");

  fillSine(info.timeInSamples);
  callProcessAudioNoGC(client, inPtrs[], outPtrs[], 32, info);
  info.timeInSamples += 32;
  for (int f = 0; f < 32; ++f) {
    assert(outL[f] == inL[f], "Idle passthrough must bit-accurately match dry input");
    assert(outR[f] == inR[f], "Idle passthrough must bit-accurately match dry input");
  }

  // 3. Mid-playback switch: MIDI Trigger Mode -> Auto Mode
  prevSampleL = outL[31];
  client.param(Params.autoMode).setFromHost(1.0);
  for (int b = 0; b < 5; ++b) {
    fillSine(info.timeInSamples);
    callProcessAudioNoGC(client, inPtrs[], outPtrs[], 32, info);
    info.timeInSamples += 32;

    for (int f = 0; f < 32; ++f) {
      assert(isFinite(outL[f]) && !isNaN(outL[f]));
      assert(isFinite(outR[f]) && !isNaN(outR[f]));
      const float stepDelta = fabs(outL[f] - prevSampleL);
      assert(stepDelta < 0.8f, "Discontinuity detected during MIDI -> Auto transition");
      prevSampleL = outL[f];
    }
  }
  assert(client.gestureController().getIsActive());

  // 4. MIDI Note held across Auto <-> MIDI mode transitions
  // Switch to MIDI Mode
  client.param(Params.autoMode).setFromHost(0.0);
  for (int b = 0; b < 5; ++b) {
    fillSine(info.timeInSamples);
    callProcessAudioNoGC(client, inPtrs[], outPtrs[], 32, info);
    info.timeInSamples += 32;
  }
  assert(!client.gestureController().getIsActive());

  // Trigger Note 36 in MIDI Mode
  client.enqueueMIDIFromHost(makeMidiMessageNoteOn(0, 0, 36, 100));
  fillSine(info.timeInSamples);
  callProcessAudioNoGC(client, inPtrs[], outPtrs[], 32, info);
  info.timeInSamples += 32;
  assert(client.gestureController().getIsActive());

  // Switch to Auto Mode WHILE Note 36 is still held
  client.param(Params.autoMode).setFromHost(1.0);
  fillSine(info.timeInSamples);
  callProcessAudioNoGC(client, inPtrs[], outPtrs[], 32, info);
  info.timeInSamples += 32;
  assert(client.gestureController().getIsActive(), "Must stay active when transitioning to Auto Mode");

  // Switch back to MIDI Mode WHILE Note 36 is STILL held
  client.param(Params.autoMode).setFromHost(0.0);
  fillSine(info.timeInSamples);
  callProcessAudioNoGC(client, inPtrs[], outPtrs[], 32, info);
  info.timeInSamples += 32;
  assert(client.gestureController().getIsActive(), "Must stay active because Note 36 is still held!");

  // Now release Note 36
  client.enqueueMIDIFromHost(makeMidiMessageNoteOff(0, 0, 36));
  for (int b = 0; b < 5; ++b) {
    fillSine(info.timeInSamples);
    callProcessAudioNoGC(client, inPtrs[], outPtrs[], 32, info);
    info.timeInSamples += 32;
  }
  assert(!client.gestureController().getIsActive(), "Must deactivate after Note 36 release");

  // 5. Rapid repeated mode toggling (500 iterations)
  for (int iter = 0; iter < 500; ++iter) {
    client.param(Params.autoMode).setFromHost((iter % 2 == 0) ? 1.0 : 0.0);
    fillSine(info.timeInSamples);
    callProcessAudioNoGC(client, inPtrs[], outPtrs[], 32, info);
    info.timeInSamples += 32;

    for (int f = 0; f < 32; ++f) {
      assert(isFinite(outL[f]) && !isNaN(outL[f]));
      assert(isFinite(outR[f]) && !isNaN(outR[f]));
    }
  }

  writeln("[CHALLENGE M2_2] Suite 2 Passed Successfully.");
}

// =============================================================================
// Suite 3: Stopped Host Transport, Negative Song Beats & Extreme Tempos
// =============================================================================

void testTransportFallbacksAndExtremeTempos() {
  writeln("[CHALLENGE M2_2] Suite 3: Testing transport fallbacks, negative beats & extreme tempos...");

  auto client = new StutterClient();
  client.reset(44100.0, 32, 2, 2);

  float[32] inL = 0.5f, inR = -0.5f;
  float[32] outL = 0.0f, outR = 0.0f;
  const(float)*[2] inPtrs = [inL.ptr, inR.ptr];
  float*[2] outPtrs = [outL.ptr, outR.ptr];

  // ---------------------------------------------------------------------------
  // 3.1: Stopped Host Transport Fallback (hostIsPlaying = false)
  // ---------------------------------------------------------------------------
  TimeInfo info;
  info.tempo = 120.0;
  info.hostIsPlaying = false;
  info.timeInSamples = 0;

  // In MIDI Trigger Mode: triggering a note while host transport is stopped
  client.param(Params.autoMode).setFromHost(0.0);
  client.param(Params.releaseMode).setFromHost(0.0); // instant

  client.enqueueMIDIFromHost(makeMidiMessageNoteOn(0, 0, 36, 100));
  callProcessAudioNoGC(client, inPtrs[], outPtrs[], 32, info);
  assert(client.gestureController().getIsActive(), "Gesture must trigger even when host transport is stopped");

  // Advance 100 blocks while transport remains stopped
  float prevPhase = client.gestureController().getGesturePhase();
  for (int b = 0; b < 100; ++b) {
    callProcessAudioNoGC(client, inPtrs[], outPtrs[], 32, info);
    const float curPhase = client.gestureController().getGesturePhase();
    assert(curPhase >= prevPhase, "Phase must advance monotonically via internal fallback when transport stopped");
    prevPhase = curPhase;
  }
  client.enqueueMIDIFromHost(makeMidiMessageNoteOff(0, 0, 36));
  for (int b = 0; b < 5; ++b) {
    callProcessAudioNoGC(client, inPtrs[], outPtrs[], 32, info);
  }
  assert(!client.gestureController().getIsActive());

  // In Auto Mode: when host transport is initially stopped, StutterClient stays idle
  client.param(Params.autoMode).setFromHost(1.0);
  info.hostIsPlaying = false;
  callProcessAudioNoGC(client, inPtrs[], outPtrs[], 32, info);
  assert(!client.gestureController().getIsActive(), "Auto mode starts idle when transport is stopped");
  assert(outL[0] == inL[0], "Stopped auto mode passes dry audio initially");

  // Start transport: Auto Mode immediately activates
  info.hostIsPlaying = true;
  callProcessAudioNoGC(client, inPtrs[], outPtrs[], 32, info);
  assert(client.gestureController().getIsActive(), "Auto mode activates when host starts playing");

  // Stop transport mid-playback: Auto Mode falls back to internal sample counter fallback
  info.hostIsPlaying = false;
  const float phaseBeforeStop = client.gestureController().getGesturePhase();
  for (int b = 0; b < 10; ++b) {
    callProcessAudioNoGC(client, inPtrs[], outPtrs[], 32, info);
    for (int f = 0; f < 32; ++f) {
      assert(!isNaN(outL[f]) && isFinite(outL[f]));
      assert(!isNaN(outR[f]) && isFinite(outR[f]));
    }
  }
  assert(client.gestureController().getIsActive(), "Once running, Auto Mode falls back to internal counter when host stops");
  assert(client.gestureController().getGesturePhase() >= phaseBeforeStop, "Phase advances via internal fallback");

  // ---------------------------------------------------------------------------
  // 3.2: Corrupted Host Tempos (0.0, negative, NaN, Inf)
  // ---------------------------------------------------------------------------
  client.param(Params.autoMode).setFromHost(0.0);
  client.enqueueMIDIFromHost(makeMidiMessageNoteOn(0, 0, 36, 100));

  static immutable double[] corruptTempos = [
    0.0,
    -120.0,
    -0.0001,
    double.nan,
    double.infinity,
    -double.infinity
  ];

  foreach (t; corruptTempos) {
    info.tempo = t;
    info.hostIsPlaying = true;
    callProcessAudioNoGC(client, inPtrs[], outPtrs[], 32, info);

    for (int f = 0; f < 32; ++f) {
      assert(!isNaN(outL[f]), "Corrupted tempo produced NaN in output L");
      assert(!isNaN(outR[f]), "Corrupted tempo produced NaN in output R");
      assert(!isInfinity(outL[f]), "Corrupted tempo produced Inf in output L");
      assert(!isInfinity(outR[f]), "Corrupted tempo produced Inf in output R");
    }
  }
  client.gestureController().allNotesOff();

  // ---------------------------------------------------------------------------
  // 3.3: Negative Song Beats (Pickup measures in DAW projects)
  // ---------------------------------------------------------------------------
  // Test pure math helpers
  assert(modBeats(-0.5, 1.0) == 0.5);
  assert(modBeats(-2.25, 1.0) == 0.75);
  assert(modBeats(-4.0, 4.0) == 0.0);
  assert(nextGridBoundary(-0.5, 1.0) == 0.0);
  assert(nextGridBoundary(-2.5, 1.0) == -2.0);
  assert(nextGridBoundary(-1.0, 1.0) == -1.0);

  // Test Auto Mode across negative beats into positive beats
  client.param(Params.autoMode).setFromHost(1.0);
  info.tempo = 120.0;
  info.hostIsPlaying = true;

  // Start 2 bars before beat 0 (beat -8.0 at 120 BPM = -4.0 seconds = -176,400 samples)
  info.timeInSamples = -176_400;
  float lastPhase = -1.0f;
  for (int b = 0; b < 200; ++b) {
    callProcessAudioNoGC(client, inPtrs[], outPtrs[], 32, info);
    info.timeInSamples += 32;

    const float curPhase = client.gestureController().getGesturePhase();
    assert(curPhase >= 0.0f && curPhase < 1.0f, "Phase must remain within [0.0, 1.0) under negative beats");
    for (int f = 0; f < 32; ++f) {
      assert(!isNaN(outL[f]));
      assert(!isNaN(outR[f]));
    }
  }

  // ---------------------------------------------------------------------------
  // 3.4: Extreme Tempo Values (20 BPM and 999 BPM)
  // ---------------------------------------------------------------------------
  // 20 BPM (ultra-slow)
  info.tempo = 20.0;
  info.timeInSamples = 0;
  client.param(Params.autoMode).setFromHost(0.0);
  client.enqueueMIDIFromHost(makeMidiMessageNoteOn(0, 0, 36, 100));
  for (int b = 0; b < 100; ++b) {
    callProcessAudioNoGC(client, inPtrs[], outPtrs[], 32, info);
    info.timeInSamples += 32;
    for (int f = 0; f < 32; ++f) {
      assert(!isNaN(outL[f]) && isFinite(outL[f]));
      assert(!isNaN(outR[f]) && isFinite(outR[f]));
    }
  }

  // 999 BPM (ultra-fast: rapid loop wraps)
  info.tempo = 999.0;
  info.timeInSamples = 0;
  for (int b = 0; b < 200; ++b) {
    callProcessAudioNoGC(client, inPtrs[], outPtrs[], 32, info);
    info.timeInSamples += 32;
    for (int f = 0; f < 32; ++f) {
      assert(!isNaN(outL[f]) && isFinite(outL[f]));
      assert(!isNaN(outR[f]) && isFinite(outR[f]));
      assert(fabs(outL[f]) <= 4.0f);
    }
  }
  client.enqueueMIDIFromHost(makeMidiMessageNoteOff(0, 0, 36));
  for (int b = 0; b < 5; ++b) {
    callProcessAudioNoGC(client, inPtrs[], outPtrs[], 32, info);
  }

  writeln("[CHALLENGE M2_2] Suite 3 Passed Successfully.");
}

// =============================================================================
// Suite 4: Client Lifecycle, Sample Rates, Buffers, Topologies & Zero-GC
// =============================================================================

void testClientLifecycleAndTopologies() {
  writeln("[CHALLENGE M2_2] Suite 4: Testing client lifecycle, sample rates, buffers, topologies & zero-GC...");

  auto client = new StutterClient();

  // ---------------------------------------------------------------------------
  // 4.1: Multi-Sample-Rates (8 kHz to 384 kHz)
  // ---------------------------------------------------------------------------
  static immutable double[] sampleRates = [
    8000.0,
    11025.0,
    16000.0,
    22050.0,
    44100.0,
    48000.0,
    88200.0,
    96000.0,
    176400.0,
    192000.0,
    384000.0
  ];

  float[32] inL = 0.5f, inR = -0.5f;
  float[32] outL = 0.0f, outR = 0.0f;
  const(float)*[2] inPtrs = [inL.ptr, inR.ptr];
  float*[2] outPtrs = [outL.ptr, outR.ptr];

  TimeInfo info;
  info.tempo = 120.0;
  info.hostIsPlaying = true;
  info.timeInSamples = 0;

  foreach (sr; sampleRates) {
    callResetNoGC(client, sr, 32, 2, 2);
    assert(client.captureBuffer().isAllocated(), "Capture buffer must be allocated");
    assert(client.captureBuffer().sampleRate() == sr, "Buffer sample rate mismatch");

    // Dry passthrough check
    client.param(Params.autoMode).setFromHost(0.0);
    callProcessAudioNoGC(client, inPtrs[], outPtrs[], 32, info);
    assert(outL[0] == inL[0] && outR[0] == inR[0], "Passthrough mismatch at rate");

    // Active stutter check
    client.enqueueMIDIFromHost(makeMidiMessageNoteOn(0, 0, 36, 100));
    for (int b = 0; b < 10; ++b) {
      callProcessAudioNoGC(client, inPtrs[], outPtrs[], 32, info);
      for (int f = 0; f < 32; ++f) {
        assert(!isNaN(outL[f]) && isFinite(outL[f]));
        assert(!isNaN(outR[f]) && isFinite(outR[f]));
      }
    }
    client.enqueueMIDIFromHost(makeMidiMessageNoteOff(0, 0, 36));
    for (int b = 0; b < 5; ++b) {
      callProcessAudioNoGC(client, inPtrs[], outPtrs[], 32, info);
    }
  }

  // ---------------------------------------------------------------------------
  // 4.2: Varying Buffer Sizes (1 to 4096)
  // ---------------------------------------------------------------------------
  static immutable int[] bufferSizes = [
    1, 2, 3, 7, 16, 31, 32, 64, 127, 128, 255, 256, 512, 1024, 2048, 4096
  ];

  float[4096] bigInL, bigInR;
  float[4096] bigOutL, bigOutR;
  for (int i = 0; i < 4096; ++i) {
    bigInL[i] = cast(float) sin(cast(double) i * 0.05);
    bigInR[i] = cast(float) cos(cast(double) i * 0.05);
  }

  const(float)*[2] bigInPtrs = [bigInL.ptr, bigInR.ptr];
  float*[2] bigOutPtrs = [bigOutL.ptr, bigOutR.ptr];

  foreach (frames; bufferSizes) {
    callResetNoGC(client, 44100.0, frames, 2, 2);
    client.param(Params.autoMode).setFromHost(0.0);
    client.param(Params.releaseMode).setFromHost(0.0); // instant

    // 1. Idle passthrough
    callProcessAudioNoGC(client, bigInPtrs[], bigOutPtrs[], frames, info);
    for (int i = 0; i < frames; ++i) {
      assert(bigOutL[i] == bigInL[i], "Varying buffer idle mismatch");
      assert(bigOutR[i] == bigInR[i], "Varying buffer idle mismatch");
    }

    // 2. Active processing
    client.enqueueMIDIFromHost(makeMidiMessageNoteOn(0, 0, 36, 100));
    callProcessAudioNoGC(client, bigInPtrs[], bigOutPtrs[], frames, info);
    for (int i = 0; i < frames; ++i) {
      assert(!isNaN(bigOutL[i]) && isFinite(bigOutL[i]));
      assert(!isNaN(bigOutR[i]) && isFinite(bigOutR[i]));
    }
  }

  // Micro-buffer verification: 500 consecutive calls with frames = 1
  client.reset(44100.0, 1, 2, 2);
  client.param(Params.autoMode).setFromHost(0.0);
  client.enqueueMIDIFromHost(makeMidiMessageNoteOn(0, 0, 36, 100));

  float prevPhaseMicro = 0.0f;
  for (int step = 0; step < 500; ++step) {
    callProcessAudioNoGC(client, bigInPtrs[], bigOutPtrs[], 1, info);
    assert(client.gestureController().getIsActive());
    const float p = client.gestureController().getGesturePhase();
    assert(p >= prevPhaseMicro, "Micro-buffer phase must increment monotonically");
    prevPhaseMicro = p;
    assert(!isNaN(bigOutL[0]) && isFinite(bigOutL[0]));
  }
  client.gestureController().allNotesOff();

  // ---------------------------------------------------------------------------
  // 4.3: Rapid Reset Cycles (2,000 resets)
  // ---------------------------------------------------------------------------
  for (int iter = 0; iter < 2000; ++iter) {
    const double sr = sampleRates[iter % sampleRates.length];
    const int frames = bufferSizes[iter % bufferSizes.length];
    const int inCh = (iter % 2 == 0) ? 1 : 2;
    const int outCh = (iter % 3 == 0) ? 1 : 2;
    callResetNoGC(client, sr, frames, inCh, outCh);
    assert(client.captureBuffer().isAllocated());
  }

  // After 2,000 resets, immediately process audio without issue
  callResetNoGC(client, 44100.0, 32, 2, 2);
  callProcessAudioNoGC(client, inPtrs[], outPtrs[], 32, info);
  assert(outL[0] == inL[0]);

  // ---------------------------------------------------------------------------
  // 4.4: Channel Topologies & In-Place Aliasing
  // ---------------------------------------------------------------------------
  // Topology 1: Mono In / Stereo Out (1 -> 2)
  const(float)*[1] monoInPtrs = [inL.ptr];
  float*[2] stereoOutPtrs = [outL.ptr, outR.ptr];
  callProcessAudioNoGC(client, monoInPtrs[], stereoOutPtrs[], 32, info);
  assert(outL[0] == inL[0]);
  assert(outR[0] == 0.0f, "Mono in idle: Right channel must be zeroed");

  // Topology 2: Mono In / Mono Out (1 -> 1)
  float*[1] monoOutPtrs = [outL.ptr];
  callProcessAudioNoGC(client, monoInPtrs[], monoOutPtrs[], 32, info);
  assert(outL[0] == inL[0]);

  // Topology 3: In-Place Aliasing (inputs[c] is outputs[c])
  float[32] aliasedL = 0.7f;
  float[32] aliasedR = -0.7f;
  const(float)*[2] aliasedIn = [aliasedL.ptr, aliasedR.ptr];
  float*[2] aliasedOut = [aliasedL.ptr, aliasedR.ptr];

  // Idle in-place
  callProcessAudioNoGC(client, aliasedIn[], aliasedOut[], 32, info);
  assert(aliasedL[0] == 0.7f && aliasedR[0] == -0.7f, "Idle in-place must preserve data");

  // Active stutter in-place
  client.enqueueMIDIFromHost(makeMidiMessageNoteOn(0, 0, 36, 100));
  for (int b = 0; b < 10; ++b) {
    callProcessAudioNoGC(client, aliasedIn[], aliasedOut[], 32, info);
    assert(!isNaN(aliasedL[0]) && isFinite(aliasedL[0]));
    assert(!isNaN(aliasedR[0]) && isFinite(aliasedR[0]));
  }
  client.gestureController().allNotesOff();

  // Topology 4: Null channel handling
  const(float)*[2] nullIn = [inL.ptr, null];
  float*[2] nullOut = [outL.ptr, null];
  callProcessAudioNoGC(client, nullIn[], nullOut[], 32, info);
  assert(!isNaN(outL[0]));

  // ---------------------------------------------------------------------------
  // 4.5: Real-Time Zero-GC Guarantee Verification (50,000 blocks)
  // ---------------------------------------------------------------------------
  GC.collect();
  const auto gcStatsBefore = GC.stats();

  for (int iter = 0; iter < 50_000; ++iter) {
    // Erratic MIDI triggers and releases
    if (iter % 30 == 0) {
      client.enqueueMIDIFromHost(makeMidiMessageNoteOn(0, 0, cast(ubyte)(36 + (iter % 24)), 100));
    } else if (iter % 45 == 0) {
      client.enqueueMIDIFromHost(makeMidiMessageNoteOff(0, 0, cast(ubyte)(36 + (iter % 24))));
    }

    // Erratic tempo and transport updates
    info.tempo = (iter % 100 == 0) ? 999.0 : ((iter % 50 == 0) ? 20.0 : 120.0);
    info.timeInSamples += 32;

    callProcessAudioNoGC(client, inPtrs[], outPtrs[], 32, info);
  }

  const auto gcStatsAfter = GC.stats();
  assert(gcStatsAfter.usedSize == gcStatsBefore.usedSize,
    "GC allocations detected during real-time processAudio under heavy load!");

  writeln("[CHALLENGE M2_2] Suite 4 Passed Successfully.");
}

// =============================================================================
// Top-Level Unittest Harness Runner
// =============================================================================

unittest {
  writeln("=== [Challenger M2_2] Starting Empirical Verification of Milestone 2 ===");
  testErraticMidiAndReleaseModes();
  testAutoVsMidiTriggerModeSwitching();
  testTransportFallbacksAndExtremeTempos();
  testClientLifecycleAndTopologies();
  writeln("=== [Challenger M2_2] All Milestone 2 Empirical Challenges PASSED ===");
}
