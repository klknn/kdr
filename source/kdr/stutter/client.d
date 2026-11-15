/**
 * StutterClient audio effect client.
 *
 * Implements Stutter Edit 2 audio client lifecycle, coordinating:
 * - StereoCaptureBuffer: 2^19 continuous circular audio capture and Hermite cubic lookup.
 * - StutterEngine: Rhythmic slice repetition, 64-sample equal-power cosine crossfading,
 *   rate ramping, stepped quantization, and directional trajectories.
 * - GestureController: Host tempo synchronization, MIDI Note-On/Off trigger modes,
 *   Auto Mode, and normalized phase progression p in [0.0, 1.0).
 *
 * Copyright: kdr 2026.
 * License: Boost License 1.0.
 */
module kdr.stutter.client;

import std.math : isNaN, isFinite, exp2;
import core.math : fabs;
import dplug.client : Client, IGraphics, LegalIO, MidiMessage, Parameter, PluginInfo, TimeInfo;
import dplug.core.math : convertDecibelToLinearGain;
import dplug.core : mallocNew, makeVec, Vec;

import kdr.params : buildParams;
import kdr.stutter.params : Params, ReleaseMode, QuantizeGrid, BufferDirection,
  StutterSubdivision, StutterQuantizeMode, autoRateBeats, gestureLengthBeats;
import kdr.stutter.buffer : StereoCaptureBuffer;
import kdr.stutter.stutter : StutterEngine;
import kdr.stutter.gesture : GestureController;
import kdr.stutter.tvm : TVMModulationEngine, TVMModuleSlot, NumTVMModuleSlots, TVMCurve, evaluateModulatedParam;
import kdr.stutter.fx : StutterFXRack;
import kdr.stutter.gui : StutterGUI;

/// StutterClient audio effect client.
class StutterClient : Client {
public:
  nothrow @nogc:

  this() {
    super();
  }

  override PluginInfo buildPluginInfo() {
    return PluginInfo.init;
  }

  override Parameter[] buildParameters() {
    return buildParams!Params();
  }

  override IGraphics createGraphics() {
    return mallocNew!StutterGUI(this, params());
  }

  override LegalIO[] buildLegalIO() {
    auto io = makeVec!LegalIO();
    io ~= LegalIO(1, 1);
    io ~= LegalIO(2, 2);
    return io.releaseData();
  }

  override int maxFramesInProcess() pure {
    return 32;
  }

  override void reset(double sampleRate, int maxFrames, int numInputs, int numOutputs) {
    _sampleRate = sampleRate > 0.0 ? sampleRate : 44_100.0;
    _buffer.allocate(_sampleRate, 10.0f);
    _stutter.reset(_sampleRate);
    _gesture.reset(_sampleRate);
    _tvmEngine.reset(_sampleRate);
    if (!_fxRackInitialized || _fxRackDirty) {
      _fxRack.reset(_sampleRate);
      _fxRackInitialized = true;
      _fxRackDirty = false;
    } else {
      // Fast sample-rate update when FX buffers are already zeroed
      _fxRack.gate.reset(_sampleRate);
      _fxRack.pan.reset(_sampleRate);
      _fxRack.filter.reset(_sampleRate);
      _fxRack.lofi.reset(_sampleRate);
      _fxRack.distort.reset(_sampleRate);
      _fxRack.comb.reset(_sampleRate);
      _fxRack.phaser.reset(_sampleRate);
      _fxRack.limiter.reset(_sampleRate);
      _fxRack.tapeStop.sampleRate = _sampleRate;
      _fxRack.chorus.sampleRate = _sampleRate;
      _fxRack.flanger.sampleRate = _sampleRate;
      _fxRack.reverb.sampleRate = _sampleRate;
      _fxRack.delay.sampleRate = _sampleRate;
    }
    _lastStutterCurve = -1;
    _lastStutterTension = float.nan;
    _lastBufferCurve = -1;
    _lastBufferTension = float.nan;
    _peakL = 0.0f;
    _peakR = 0.0f;
  }

  override void processAudio(const(float*)[] inputs, float*[] outputs, int frames, TimeInfo info) {
    const int numInputs = cast(int) inputs.length;
    const int numOutputs = cast(int) outputs.length;
    if (numOutputs == 0 || frames <= 0) return;

    // 1. Check incoming MIDI messages
    const(MidiMessage)[] midiMessages = getNextMidiMessages(frames);
    const int numMidi = cast(int) midiMessages.length;

    // 2. Read core mode & FX enable parameters
    const bool autoMode = readParam!bool(Params.autoMode);
    const bool isPlaying = info.hostIsPlaying;
    const bool isAutoRunning = autoMode && isPlaying;
    const bool hasMidiNotes = (_gesture.numHeldNotes > 0) || (_gesture.noteHeldForActive);

    const bool gateEnable     = readParam!bool(Params.gateEnable);
    const bool panEnable      = readParam!bool(Params.panEnable);
    const bool tapeStopEnable = readParam!bool(Params.tapeStopEnable);
    const bool filterEnable   = readParam!bool(Params.filterEnable);
    const bool lofiEnable     = readParam!bool(Params.lofiEnable);
    const bool distortEnable  = readParam!bool(Params.distortEnable);
    const bool combEnable     = readParam!bool(Params.combEnable);
    const bool chorusEnable   = readParam!bool(Params.chorusEnable);
    const bool flangerEnable  = readParam!bool(Params.flangerEnable);
    const bool phaserEnable   = readParam!bool(Params.phaserEnable);
    const bool reverbEnable   = readParam!bool(Params.reverbEnable);
    const bool delayEnable    = readParam!bool(Params.delayEnable);

    const bool anyPostFXEnabled = gateEnable || panEnable || tapeStopEnable || filterEnable ||
                                  lofiEnable || distortEnable || combEnable || chorusEnable ||
                                  flangerEnable || phaserEnable || reverbEnable || delayEnable;

    // Determine if gesture or stutter engine should run
    const bool shouldRunGesture = isAutoRunning || hasMidiNotes || (numMidi > 0) ||
                                  _gesture.getIsActive() || _stutter.isStuttering();

    if (!shouldRunGesture && !anyPostFXEnabled) {
      // Idle state: continuously capture input audio into circular history buffer
      for (int f = 0; f < frames; ++f) {
        float sL = (numInputs > 0 && inputs[0] !is null) ? inputs[0][f] : 0.0f;
        float sR = (numInputs > 1 && inputs[1] !is null) ? inputs[1][f] : sL;
        _buffer.writeSample(sL, sR);
      }

      // Bit-accurate channel-by-channel passthrough matching lifecycle test requirements
      for (int chan = 0; chan < outputs.length; ++chan) {
        if (chan < inputs.length && inputs[chan] !is null) {
          if (inputs[chan] !is outputs[chan]) {
            outputs[chan][0 .. frames] = inputs[chan][0 .. frames];
          }
        } else {
          if (outputs[chan] !is null) {
            outputs[chan][0 .. frames] = 0.0f;
          }
        }
      }
      return;
    }

    _fxRackDirty = true;

    // Active state: DSP gesture, stutter engine, and 11 FX + Delay + Limiter processing
    const double tempo = (info.tempo > 0.0 && isFinite(info.tempo)) ? info.tempo : 120.0;
    _stutter.setTempo(tempo);
    _fxRack.setTempo(tempo);
    const double beatPerSample = tempo / (60.0 * _sampleRate);

    const int releaseMode = readParam!int(Params.releaseMode);
    const int quantizeGrid = readParam!int(Params.quantizeGrid);

    float gestureBeats = 4.0f;
    if (autoMode) {
      const int autoRateIdx = readParam!int(Params.autoRate);
      if (autoRateIdx >= 0 && autoRateIdx < cast(int) autoRateBeats.length) {
        gestureBeats = cast(float) autoRateBeats[autoRateIdx];
      }
    } else {
      const int gLenIdx = readParam!int(Params.gestureLength);
      if (gLenIdx >= 0 && gLenIdx < cast(int) gestureLengthBeats.length) {
        gestureBeats = cast(float) gestureLengthBeats[gLenIdx];
      }
    }
    _gesture.setParams(autoMode, releaseMode, gestureBeats, quantizeGrid);

    const bool stutterEnable = readParam!bool(Params.stutterEnable);
    _stutter.enabled = stutterEnable;
    const int rateStart = readParam!int(Params.stutterRateStart);
    const int rateEnd = readParam!int(Params.stutterRateEnd);
    const int quantizeMode = readParam!int(Params.stutterQuantize);
    const int stutterCurveId = readParam!int(Params.stutterCurve);
    const float stutterTension = readParam!float(Params.stutterCurveTension);

    if (stutterCurveId != _lastStutterCurve) {
      _tvmEngine.curves[TVMModuleSlot.stutter].loadPreset(stutterCurveId);
      _lastStutterCurve = stutterCurveId;
    }
    if (stutterTension != _lastStutterTension) {
      if (_tvmEngine.curves[TVMModuleSlot.stutter].nodeCount() > 0) {
        _tvmEngine.curves[TVMModuleSlot.stutter].nodes[0].tension = stutterTension;
      }
      _lastStutterTension = stutterTension;
    }

    const bool bufferEnable = readParam!bool(Params.bufferEnable);
    int directionMode = readParam!int(Params.bufferDirection);
    float stereoOffset = readParam!float(Params.bufferStereoOffset);
    float pitchMin = readParam!float(Params.bufferPitchMin);
    float pitchMax = readParam!float(Params.bufferPitchMax);
    const float bufferPosMin = readParam!float(Params.bufferPositionMin);
    const float bufferPosMax = readParam!float(Params.bufferPositionMax);
    const int bufferCurveId = readParam!int(Params.bufferCurve);
    const float bufferTension = readParam!float(Params.bufferCurveTension);

    if (bufferCurveId != _lastBufferCurve) {
      _tvmEngine.curves[TVMModuleSlot.buffer].loadPreset(bufferCurveId);
      _lastBufferCurve = bufferCurveId;
    }
    if (bufferTension != _lastBufferTension) {
      if (_tvmEngine.curves[TVMModuleSlot.buffer].nodeCount() > 0) {
        _tvmEngine.curves[TVMModuleSlot.buffer].nodes[0].tension = bufferTension;
      }
      _lastBufferTension = bufferTension;
    }

    if (!bufferEnable) {
      directionMode = BufferDirection.forward;
      stereoOffset = 0.0f;
      pitchMin = 0.0f;
      pitchMax = 0.0f;
    }

    // Read post-FX parameters when enabled
    int gateSubdiv = 0; float gateWMin = 0.5f, gateWMax = 0.5f, gateTail = 5.0f, gateMix = 1.0f;
    if (gateEnable) {
      gateSubdiv = readParam!int(Params.gateSubdivision);
      gateWMin   = readParam!float(Params.gateWidthMin);
      gateWMax   = readParam!float(Params.gateWidthMax);
      gateTail   = readParam!float(Params.gateTail);
      gateMix    = readParam!float(Params.gateMix);
      syncSlotCurve(TVMModuleSlot.gate, Params.gateCurve, Params.gateCurveTension);
    }

    float panCMin = 0.0f, panCMax = 0.0f, panWMin = 1.0f, panWMax = 1.0f, panMix = 1.0f;
    if (panEnable) {
      panCMin = readParam!float(Params.panCenterMin);
      panCMax = readParam!float(Params.panCenterMax);
      panWMin = readParam!float(Params.panWidthMin);
      panWMax = readParam!float(Params.panWidthMax);
      panMix  = readParam!float(Params.panMix);
      syncSlotCurve(TVMModuleSlot.pan, Params.panCurve, Params.panCurveTension);
    }

    float tapeSMin = 0.0f, tapeSMax = 1.0f, tapeMix = 1.0f; bool tapePlunge = true;
    if (tapeStopEnable) {
      tapeSMin   = readParam!float(Params.tapeStopSlowdownMin);
      tapeSMax   = readParam!float(Params.tapeStopSlowdownMax);
      tapePlunge = readParam!bool(Params.tapeStopPlunge);
      tapeMix    = readParam!float(Params.tapeStopMix);
      syncSlotCurve(TVMModuleSlot.tapeStop, Params.tapeStopCurve, Params.tapeStopCurveTension);
    }

    int filtType = 0; float filtCMin = 200.0f, filtCMax = 8000.0f, filtRes = 0.3f, filtDrive = 0.0f, filtMix = 1.0f;
    if (filterEnable) {
      filtType  = readParam!int(Params.filterType);
      filtCMin  = readParam!float(Params.filterCutoffMin);
      filtCMax  = readParam!float(Params.filterCutoffMax);
      filtRes   = readParam!float(Params.filterResonance);
      filtDrive = readParam!float(Params.filterDrive);
      filtMix   = readParam!float(Params.filterMix);
      syncSlotCurve(TVMModuleSlot.filter, Params.filterCurve, Params.filterCurveTension);
    }

    float lofiBMin = 16.0f, lofiBMax = 6.0f, lofiDMin = 1.0f, lofiDMax = 12.0f, lofiGrit = 0.2f, lofiMix = 1.0f;
    if (lofiEnable) {
      lofiBMin = readParam!float(Params.lofiBitDepthMin);
      lofiBMax = readParam!float(Params.lofiBitDepthMax);
      lofiDMin = readParam!float(Params.lofiDownsampleMin);
      lofiDMax = readParam!float(Params.lofiDownsampleMax);
      lofiGrit = readParam!float(Params.lofiGrit);
      lofiMix  = readParam!float(Params.lofiMix);
      syncSlotCurve(TVMModuleSlot.lofi, Params.lofiCurve, Params.lofiCurveTension);
    }

    float distXover = 800.0f, distLMin = 0.0f, distLMax = 0.5f, distHMin = 0.0f, distHMax = 0.7f, distTone = 0.0f, distMix = 1.0f;
    if (distortEnable) {
      distXover = readParam!float(Params.distortCrossover);
      distLMin  = readParam!float(Params.distortDriveLowMin);
      distLMax  = readParam!float(Params.distortDriveLowMax);
      distHMin  = readParam!float(Params.distortDriveHighMin);
      distHMax  = readParam!float(Params.distortDriveHighMax);
      distTone  = readParam!float(Params.distortTone);
      distMix   = readParam!float(Params.distortMix);
      syncSlotCurve(TVMModuleSlot.distort, Params.distortCurve, Params.distortCurveTension);
    }

    float combFMin = 100.0f, combFMax = 800.0f, combFb = 0.7f, combDamp = 0.2f, combPhase = 45.0f, combMix = 0.5f;
    if (combEnable) {
      combFMin  = readParam!float(Params.combFreqMin);
      combFMax  = readParam!float(Params.combFreqMax);
      combFb    = readParam!float(Params.combFeedback);
      combDamp  = readParam!float(Params.combDamping);
      combPhase = readParam!float(Params.combStereoPhase);
      combMix   = readParam!float(Params.combMix);
      syncSlotCurve(TVMModuleSlot.comb, Params.combCurve, Params.combCurveTension);
    }

    float chorRate = 0.6f, chorDMin = 0.1f, chorDMax = 0.8f, chorFb = 0.25f, chorWidth = 1.0f, chorMix = 0.5f;
    if (chorusEnable) {
      chorRate  = readParam!float(Params.chorusRate);
      chorDMin  = readParam!float(Params.chorusDepthMin);
      chorDMax  = readParam!float(Params.chorusDepthMax);
      chorFb    = readParam!float(Params.chorusFeedback);
      chorWidth = readParam!float(Params.chorusWidth);
      chorMix   = readParam!float(Params.chorusMix);
      syncSlotCurve(TVMModuleSlot.chorus, Params.chorusCurve, Params.chorusCurveTension);
    }

    float flangRate = 0.25f, flangDMin = 0.2f, flangDMax = 3.5f, flangFb = 0.7f, flangPhase = 90.0f, flangMix = 0.5f;
    if (flangerEnable) {
      flangRate  = readParam!float(Params.flangerRate);
      flangDMin  = readParam!float(Params.flangerDepthMin);
      flangDMax  = readParam!float(Params.flangerDepthMax);
      flangFb    = readParam!float(Params.flangerFeedback);
      flangPhase = readParam!float(Params.flangerStereoPhase);
      flangMix   = readParam!float(Params.flangerMix);
      syncSlotCurve(TVMModuleSlot.flanger, Params.flangerCurve, Params.flangerCurveTension);
    }

    float phasRate = 0.35f, phasCMin = 200.0f, phasCMax = 3000.0f, phasFb = 0.6f, phasMix = 0.5f; int phasStages = 1;
    if (phaserEnable) {
      phasRate   = readParam!float(Params.phaserRate);
      phasStages = readParam!int(Params.phaserStages);
      phasCMin   = readParam!float(Params.phaserCenterMin);
      phasCMax   = readParam!float(Params.phaserCenterMax);
      phasFb     = readParam!float(Params.phaserFeedback);
      phasMix    = readParam!float(Params.phaserMix);
      syncSlotCurve(TVMModuleSlot.phaser, Params.phaserCurve, Params.phaserCurveTension);
    }

    float revSMin = 0.2f, revSMax = 0.85f, revDamp = 0.3f, revPre = 10.0f, revMix = 0.35f; bool revFreeze = false;
    if (reverbEnable) {
      revSMin   = readParam!float(Params.reverbSizeMin);
      revSMax   = readParam!float(Params.reverbSizeMax);
      revDamp   = readParam!float(Params.reverbDamping);
      revPre    = readParam!float(Params.reverbPreDelay);
      revFreeze = readParam!bool(Params.reverbFreeze);
      revMix    = readParam!float(Params.reverbMix);
      syncSlotCurve(TVMModuleSlot.reverb, Params.reverbCurve, Params.reverbCurveTension);
    }

    int delTimeL = 2, delTimeR = 3; float delFbMin = 0.1f, delFbMax = 0.65f, delCross = 0.5f, delDamp = 0.3f, delMix = 0.3f;
    if (delayEnable) {
      delTimeL = readParam!int(Params.delayTimeL);
      delTimeR = readParam!int(Params.delayTimeR);
      delFbMin = readParam!float(Params.delayFeedbackMin);
      delFbMax = readParam!float(Params.delayFeedbackMax);
      delCross = readParam!float(Params.delayCross);
      delDamp  = readParam!float(Params.delayDamp);
      delMix   = readParam!float(Params.delayMix);
      syncSlotCurve(TVMModuleSlot.delay, Params.delayCurve, Params.delayCurveTension);
    }

    const bool limEnable   = readParam!bool(Params.limiterEnable);
    const float limThresh  = readParam!float(Params.limiterThreshold);
    const float limCeiling = readParam!float(Params.limiterCeiling);
    const float limRelease = readParam!float(Params.limiterRelease);

    const float dryWet = readParam!float(Params.masterDryWet);
    const float gainDb = readParam!float(Params.masterOutputGain);
    const float outGain = convertDecibelToLinearGain(gainDb);

    int midiIdx = 0;

    for (int f = 0; f < frames; ++f) {
      const double songBeats = (info.timeInSamples + f) * beatPerSample;
      _gesture.updateHostTransport(info.hostIsPlaying, songBeats);

      // Dispatch MIDI events occurring at or before this frame
      while (midiIdx < numMidi && midiMessages[midiIdx].offset <= f) {
        _gesture.handleMidi(midiMessages[midiIdx], songBeats);
        midiIdx++;
      }

      // Advance gesture phase & state
      float gesturePhase;
      bool isGestureActive;
      int activeGestureIdx;
      bool justTriggered;
      _gesture.advanceSample(beatPerSample, gesturePhase, isGestureActive, activeGestureIdx, justTriggered);

      if (justTriggered) {
        _tvmEngine.onGestureTriggered(gesturePhase);
      }

      // Modulate buffer position and pitch via TVM curves & single-pole smoothers
      const float bufCurveVal = _tvmEngine.curves[TVMModuleSlot.buffer].evaluate(gesturePhase);
      const float targetPos = evaluateModulatedParam(bufferEnable, isGestureActive, bufferPosMin, bufferPosMin, bufferPosMax, bufCurveVal);
      const float smoothedPos = _tvmEngine.smoothBufferPos.nextSample(targetPos);

      const float targetPitch = evaluateModulatedParam(bufferEnable, isGestureActive, pitchMin, pitchMin, pitchMax, bufCurveVal);
      const float smoothedPitch = _tvmEngine.smoothBufferPitch.nextSample(targetPitch);
      const float pitchRatio = exp2(smoothedPitch / 12.0f);

      // Synchronize StutterEngine trigger / release with gesture
      if (justTriggered) {
        _stutter.trigger(_buffer.writePos(), smoothedPos);
      } else if (isGestureActive && !_stutter.active) {
        _stutter.trigger(_buffer.writePos(), smoothedPos);
      } else if (!isGestureActive && _stutter.active) {
        _stutter.release();
      }

      if (_stutter.active) {
        _stutter.bufferPosition = smoothedPos;
      }

      // Read audio input samples
      float inL = (numInputs > 0 && inputs[0] !is null) ? inputs[0][f] : 0.0f;
      float inR = (numInputs > 1 && inputs[1] !is null) ? inputs[1][f] : inL;

      // Continuous capture recording
      _buffer.writeSample(inL, inR);

      // Supply active stutter rate curve to StutterEngine
      const TVMCurve* rateCurve = &_tvmEngine.curves[TVMModuleSlot.stutter];

      // Process stutter repetition and Hermite cubic interpolation
      float sigL, sigR;
      _stutter.process(&_buffer, inL, inR, sigL, sigR,
                       gesturePhase, cast(float) rateStart, cast(float) rateEnd, rateCurve,
                       quantizeMode, directionMode, pitchRatio, stereoOffset);

      // Run 11 Post-FX + End-of-Chain Delay when enabled
      if (anyPostFXEnabled) {
        if (gateEnable) {
          const float cv = _tvmEngine.curves[TVMModuleSlot.gate].evaluate(gesturePhase);
          const float w = _tvmEngine.smoothGateWidth.nextSample(
            evaluateModulatedParam(true, isGestureActive, gateWMin, gateWMin, gateWMax, cv));
          _fxRack.gate.process(sigL, sigR, sigL, sigR, gateSubdiv, w, gateTail, gateMix, true);
        }
        if (panEnable) {
          const float cv = _tvmEngine.curves[TVMModuleSlot.pan].evaluate(gesturePhase);
          const float c = _tvmEngine.smoothPanCenter.nextSample(
            evaluateModulatedParam(true, isGestureActive, panCMin, panCMin, panCMax, cv));
          const float w = _tvmEngine.smoothPanWidth.nextSample(
            evaluateModulatedParam(true, isGestureActive, panWMin, panWMin, panWMax, cv));
          _fxRack.pan.process(sigL, sigR, sigL, sigR, c, w, panMix, true);
        }
        if (tapeStopEnable) {
          const float cv = _tvmEngine.curves[TVMModuleSlot.tapeStop].evaluate(gesturePhase);
          const float s = _tvmEngine.smoothTapeSlowdown.nextSample(
            evaluateModulatedParam(true, isGestureActive, tapeSMin, tapeSMin, tapeSMax, cv));
          _fxRack.tapeStop.process(sigL, sigR, sigL, sigR, s, tapePlunge, tapeMix, true);
        }
        if (filterEnable) {
          const float cv = _tvmEngine.curves[TVMModuleSlot.filter].evaluate(gesturePhase);
          const float cut = _tvmEngine.smoothFilterCutoff.nextSample(
            evaluateModulatedParam(true, isGestureActive, filtCMin, filtCMin, filtCMax, cv, true));
          _fxRack.filter.process(sigL, sigR, sigL, sigR, filtType, cut, filtRes, filtDrive, filtMix, true);
        }
        if (lofiEnable) {
          const float cv = _tvmEngine.curves[TVMModuleSlot.lofi].evaluate(gesturePhase);
          const float bits = _tvmEngine.smoothLofiBits.nextSample(
            evaluateModulatedParam(true, isGestureActive, lofiBMin, lofiBMin, lofiBMax, cv));
          const float ds = _tvmEngine.smoothLofiDownsample.nextSample(
            evaluateModulatedParam(true, isGestureActive, lofiDMin, lofiDMin, lofiDMax, cv, true));
          _fxRack.lofi.process(sigL, sigR, sigL, sigR, bits, ds, lofiGrit, lofiMix, true);
        }
        if (distortEnable) {
          const float cv = _tvmEngine.curves[TVMModuleSlot.distort].evaluate(gesturePhase);
          const float dL = _tvmEngine.smoothDistortDriveLow.nextSample(
            evaluateModulatedParam(true, isGestureActive, distLMin, distLMin, distLMax, cv));
          const float dH = _tvmEngine.smoothDistortDriveHigh.nextSample(
            evaluateModulatedParam(true, isGestureActive, distHMin, distHMin, distHMax, cv));
          _fxRack.distort.process(sigL, sigR, sigL, sigR, distXover, dL, dH, distTone, distMix, true);
        }
        if (combEnable) {
          const float cv = _tvmEngine.curves[TVMModuleSlot.comb].evaluate(gesturePhase);
          const float fq = _tvmEngine.smoothCombFreq.nextSample(
            evaluateModulatedParam(true, isGestureActive, combFMin, combFMin, combFMax, cv, true));
          _fxRack.comb.process(sigL, sigR, sigL, sigR, fq, combFb, combDamp, combPhase, combMix, true);
        }
        if (chorusEnable) {
          const float cv = _tvmEngine.curves[TVMModuleSlot.chorus].evaluate(gesturePhase);
          const float dp = _tvmEngine.smoothChorusDepth.nextSample(
            evaluateModulatedParam(true, isGestureActive, chorDMin, chorDMin, chorDMax, cv));
          _fxRack.chorus.process(sigL, sigR, sigL, sigR, chorRate, dp, chorFb, chorWidth, chorMix, true);
        }
        if (flangerEnable) {
          const float cv = _tvmEngine.curves[TVMModuleSlot.flanger].evaluate(gesturePhase);
          const float dp = _tvmEngine.smoothFlangerDepth.nextSample(
            evaluateModulatedParam(true, isGestureActive, flangDMin, flangDMin, flangDMax, cv));
          _fxRack.flanger.process(sigL, sigR, sigL, sigR, flangRate, dp, flangFb, flangPhase, flangMix, true);
        }
        if (phaserEnable) {
          const float cv = _tvmEngine.curves[TVMModuleSlot.phaser].evaluate(gesturePhase);
          const float ct = _tvmEngine.smoothPhaserCenter.nextSample(
            evaluateModulatedParam(true, isGestureActive, phasCMin, phasCMin, phasCMax, cv, true));
          _fxRack.phaser.process(sigL, sigR, sigL, sigR, phasRate, phasStages, ct, phasFb, phasMix, true);
        }
        if (reverbEnable) {
          const float cv = _tvmEngine.curves[TVMModuleSlot.reverb].evaluate(gesturePhase);
          const float sz = _tvmEngine.smoothReverbSize.nextSample(
            evaluateModulatedParam(true, isGestureActive, revSMin, revSMin, revSMax, cv));
          _fxRack.reverb.process(sigL, sigR, sigL, sigR, sz, revDamp, revPre, revFreeze, revMix, true);
        }
        if (delayEnable) {
          const float cv = _tvmEngine.curves[TVMModuleSlot.delay].evaluate(gesturePhase);
          const float fb = _tvmEngine.smoothDelayFeedback.nextSample(
            evaluateModulatedParam(true, isGestureActive, delFbMin, delFbMin, delFbMax, cv));
          _fxRack.delay.process(sigL, sigR, sigL, sigR, delTimeL, delTimeR, fb, delCross, delDamp, delMix, true);
        }
      }

      // Dry / wet mix and master output gain
      float outL = (inL * (1.0f - dryWet) + sigL * dryWet) * outGain;
      float outR = (inR * (1.0f - dryWet) + sigR * dryWet) * outGain;

      // Master brickwall safety limiter
      if (anyPostFXEnabled || fabs(outL) > 0.99f || fabs(outR) > 0.99f) {
        _fxRack.limiter.process(outL, outR, outL, outR, limThresh, limCeiling, limRelease, limEnable);
      }

      // Update peak telemetry for GUI meters
      const float aL = fabs(outL);
      const float aR = fabs(outR);
      _peakL = aL > _peakL * 0.999f ? aL : _peakL * 0.999f;
      _peakR = aR > _peakR * 0.999f ? aR : _peakR * 0.999f;

      // Write to output channels
      if (numOutputs > 0 && outputs[0] !is null) outputs[0][f] = outL;
      if (numOutputs > 1 && outputs[1] !is null) outputs[1][f] = outR;
    }

    // Process any trailing MIDI events with offset >= frames
    while (midiIdx < numMidi) {
      const double songBeats = (info.timeInSamples + frames) * beatPerSample;
      _gesture.handleMidi(midiMessages[midiIdx], songBeats);
      midiIdx++;
    }

    // Zero out any additional channels beyond stereo
    for (int chan = 2; chan < numOutputs; ++chan) {
      if (outputs[chan] !is null) {
        outputs[chan][0 .. frames] = 0.0f;
      }
    }
  }

  /// Direct engine accessors for unit testing, GUI telemetry, and inspection
  StereoCaptureBuffer* captureBuffer() pure return { return &_buffer; }
  StutterEngine* stutterEngine() pure return { return &_stutter; }
  GestureController* gestureController() pure return { return &_gesture; }
  inout(TVMModulationEngine)* modulationEngine() inout pure return { return &_tvmEngine; }
  StutterFXRack* fxRack() pure return { return &_fxRack; }
  float limiterGainReductionDb() const pure { return _fxRack.limiter.gainReductionDb(); }
  float peakLevelL() const pure { return _peakL; }
  float peakLevelR() const pure { return _peakR; }

private:
  double _sampleRate = 44_100.0;
  StereoCaptureBuffer _buffer;
  StutterEngine _stutter;
  GestureController _gesture;
  TVMModulationEngine _tvmEngine;
  StutterFXRack _fxRack;
  bool _fxRackInitialized = false;
  bool _fxRackDirty = true;
  int _lastStutterCurve = -1;
  float _lastStutterTension = float.nan;
  int _lastBufferCurve = -1;
  float _lastBufferTension = float.nan;
  int[NumTVMModuleSlots] _lastSlotCurves = -1;
  float[NumTVMModuleSlots] _lastSlotTensions = float.nan;
  float _peakL = 0.0f;
  float _peakR = 0.0f;

  void syncSlotCurve(TVMModuleSlot slot, Params curveParam, Params tensionParam) {
    const int idx = cast(int) slot;
    const int cId = readParam!int(curveParam);
    const float tens = readParam!float(tensionParam);
    if (cId != _lastSlotCurves[idx]) {
      _tvmEngine.curves[idx].loadPreset(cId);
      _lastSlotCurves[idx] = cId;
    }
    if (tens != _lastSlotTensions[idx]) {
      if (_tvmEngine.curves[idx].nodeCount() > 0) {
        _tvmEngine.curves[idx].nodes[0].tension = tens;
      }
      _lastSlotTensions[idx] = tens;
    }
  }
}

// =============================================================================
// Unit Tests
// =============================================================================

unittest {
  import kdr.testing : benchmarkWithDefaultParams;
  import dplug.client : LegalIO, makeMidiMessageNoteOn, makeMidiMessageNoteOff;

  // 1. Verify Instantiation & IO
  auto client = new StutterClient();
  assert(client !is null);

  LegalIO[] io = client.buildLegalIO();
  assert(io.length == 2);
  assert(io[0] == LegalIO(1, 1));
  assert(io[1] == LegalIO(2, 2));
  assert(client.maxFramesInProcess() == 32);

  // 2. Verify Lifecycle Across Sample Rates
  client.reset(44100.0, 32, 2, 2);
  assert(client.captureBuffer().isAllocated());
  assert(client.captureBuffer().sampleRate() == 44100.0);

  client.reset(48000.0, 64, 2, 2);
  assert(client.captureBuffer().sampleRate() == 48000.0);

  client.reset(96000.0, 128, 2, 2);
  assert(client.captureBuffer().sampleRate() == 96000.0);

  client.reset(192000.0, 256, 2, 2);
  assert(client.captureBuffer().sampleRate() == 192000.0);

  // 3. Audio Pass-Through When Idle (Dry Signal Continuity)
  client.reset(44100.0, 32, 2, 2);
  TimeInfo info;
  info.tempo = 120.0;
  info.hostIsPlaying = false;
  info.timeInSamples = 0;

  float[32] inL = 0.5f;
  float[32] inR = -0.5f;
  float[32] outL = 0.0f;
  float[32] outR = 0.0f;

  const(float)*[2] inPtrs = [inL.ptr, inR.ptr];
  float*[2] outPtrs = [outL.ptr, outR.ptr];

  client.processAudio(inPtrs[], outPtrs[], 32, info);

  // When no gesture is active and transport is stopped, passes dry input bit-accurately
  for (int i = 0; i < 32; ++i) {
    assert(outL[i] == 0.5f);
    assert(outR[i] == -0.5f);
  }

  // Verify buffer continuously captured the incoming samples
  assert(client.captureBuffer().writePos() == 32);
  assert(client.captureBuffer().peek(0, 0) == 0.5f);
  assert(client.captureBuffer().peek(1, 0) == -0.5f);

  // 4. Stutter Processing in Auto Mode When Playing
  info.hostIsPlaying = true;
  client.processAudio(inPtrs[], outPtrs[], 32, info);
  assert(client.gestureController().getIsActive());

  // 5. MIDI Trigger Mode Processing
  // Reset and disable Auto Mode to test MIDI Note-On triggering
  client.reset(44100.0, 32, 2, 2);
  client.param(Params.autoMode).setFromHost(0.0); // disable auto mode
  client.param(Params.releaseMode).setFromHost(0.0); // ReleaseMode.instant
  info.hostIsPlaying = false;

  // Before MIDI Note-On: idle
  client.processAudio(inPtrs[], outPtrs[], 32, info);
  assert(!client.gestureController().getIsActive());

  // Enqueue MIDI Note-On (Note 36 = C2 -> Gesture 0)
  client.enqueueMIDIFromHost(makeMidiMessageNoteOn(0, 0, 36, 100));
  client.processAudio(inPtrs[], outPtrs[], 32, info);
  assert(client.gestureController().getIsActive());
  assert(client.gestureController().getActiveGestureIndex() == 0);
  assert(client.stutterEngine().isStuttering());

  // Enqueue MIDI Note-Off
  client.enqueueMIDIFromHost(makeMidiMessageNoteOff(0, 0, 36));
  // Advance through 64-sample release crossfade (3 blocks of 32 frames = 96 frames)
  for (int b = 0; b < 5; ++b) {
    client.processAudio(inPtrs[], outPtrs[], 32, info);
  }
  assert(!client.gestureController().getIsActive());
  assert(!client.stutterEngine().isStuttering());

  // 6. Verify Benchmark Execution
  benchmarkWithDefaultParams!StutterClient();

  // 7. Verify TVM Modulation Integration in Client
  assert(client.modulationEngine() !is null);
  assert(client.modulationEngine().curves[TVMModuleSlot.stutter].nodeCount() >= 2);
  assert(client.modulationEngine().curves[TVMModuleSlot.buffer].nodeCount() >= 2);
  client.reset(44100.0, 32, 2, 2);
  assert(client.modulationEngine().smoothBufferPitch.isSettled());
  assert(client.modulationEngine().smoothBufferPos.isSettled());
}
