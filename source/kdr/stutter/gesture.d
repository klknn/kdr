/**
 * GestureController: Gesture trigger state machine and phase progression engine.
 *
 * Implements MIDI Trigger Mode (Note-On activation, release modes: Instant, Latch,
 * Full Gesture, On Grid), Auto Mode (continuous tempo-synced looping), per-sample
 * normalized phase progression p in [0.0, 1.0) with host sync and internal fallback,
 * quantize grid alignment, and clean gesture handover.
 *
 * Copyright: kdr 2026.
 * License: Boost License 1.0.
 */
module kdr.stutter.gesture;

import std.math : isNaN, isFinite;
import dplug.client.midi : MidiMessage;
import kdr.stutter.params : ReleaseMode, QuantizeGrid, quantizeGridBeats;

/// State of the gesture triggering state machine.
enum GestureState : ubyte {
  idle = 0,           /// Inactive, passing dry audio through
  pendingTrigger = 1, /// Trigger queued, waiting for quantize grid boundary
  active = 2,         /// Running gesture, advancing phase p in [0.0 .. 1.0)
  pendingRelease = 3, /// Key released, waiting for quantize grid boundary to deactivate
}

/// Total number of gestures per preset bank (2 octaves)
enum MAX_GESTURES = 24;

/// Default base MIDI note (C2 = Note 36, or C3 = Note 48)
enum DEFAULT_BASE_MIDI_NOTE = 36;

// =============================================================================
// Helper Functions for Timing, Subdivision & Grid Conversion
// =============================================================================

/// Safe floating-point modulo producing a result in [0.0, b)
double modBeats(double a, double b) pure nothrow @nogc @safe {
  if (b <= 0.0) return 0.0;
  double r = a % b;
  if (r < 0.0) r += b;
  return r;
}

/// Map a MIDI note number (0..127) to a gesture index (0..23) with octave folding.
int mapMidiNoteToGesture(int noteNumber, int baseNote = DEFAULT_BASE_MIDI_NOTE) pure nothrow @nogc @safe {
  int rel = (noteNumber - baseNote) % MAX_GESTURES;
  if (rel < 0) rel += MAX_GESTURES;
  return rel;
}

/// Calculate the exact next grid beat boundary B >= currentBeats.
/// Handles positive and negative song beats cleanly.
double nextGridBoundary(double currentBeats, double gridSize) pure nothrow @nogc @safe {
  if (gridSize <= 0.0) return currentBeats;
  double m = modBeats(currentBeats, gridSize);
  if (m < 1e-6 || (gridSize - m) < 1e-6) return currentBeats;
  return currentBeats + (gridSize - m);
}

/// Convert musical beats to seconds at the specified tempo (BPM).
double beatsToSeconds(double beats, double tempo) pure nothrow @nogc @safe {
  const double safeTempo = (tempo > 0.0 && isFinite(tempo)) ? tempo : 120.0;
  return beats * (60.0 / safeTempo);
}

/// Convert musical beats to audio samples at the specified tempo and sample rate.
long beatsToSamples(double beats, double tempo, double sampleRate) pure nothrow @nogc @safe {
  const double safeSr = (sampleRate > 0.0 && isFinite(sampleRate)) ? sampleRate : 44100.0;
  return cast(long)(beatsToSeconds(beats, tempo) * safeSr);
}

/// Convert audio samples to musical beats at the specified tempo and sample rate.
double samplesToBeats(long samples, double tempo, double sampleRate) pure nothrow @nogc @safe {
  const double safeTempo = (tempo > 0.0 && isFinite(tempo)) ? tempo : 120.0;
  const double safeSr = (sampleRate > 0.0 && isFinite(sampleRate)) ? sampleRate : 44100.0;
  const double bps = safeTempo / (60.0 * safeSr);
  return cast(double)samples * bps;
}

// =============================================================================
// GestureController
// =============================================================================

/// Gesture trigger state machine and normalized phase conductor.
struct GestureController {
nothrow @nogc:

  // --- Configuration ---
  double sampleRate = 44100.0;
  bool autoMode = false;
  ReleaseMode releaseMode = ReleaseMode.instant;
  float gestureBeats = 4.0f;       // Length of gesture in beats (e.g. 4.0 for 1 bar in 4/4)
  QuantizeGrid quantizeGrid = QuantizeGrid.instant;
  int baseMidiNote = DEFAULT_BASE_MIDI_NOTE;
  int defaultGestureIndex = 0;
  bool palindrome = false;         // Ping-pong 0 -> 1 -> 0 gesture curve playback
  bool stickMode = false;          // Toggle-latch on note-on ("Stick" release behavior)
  bool freezeActive = false;       // Global Freeze pauses phase progression

  // --- Runtime State ---
  GestureState state = GestureState.idle;
  float phase = 0.0f;
  float prevPhase = 0.0f;
  int palindromeDir = 1;
  int currentGestureIndex = 0;
  int pendingGestureIndex = 0;
  bool triggeredThisSample = false;

  // --- Host Transport Tracking & Fallback ---
  bool hostIsPlaying = false;
  double currentSongBeats = 0.0;
  double internalBeats = 0.0;
  long internalSampleCount = 0;
  double targetGridBeat = 0.0;
  double targetReleaseBeat = 0.0;

  // --- Note Tracking ---
  bool[128] noteHeld = false;
  int numHeldNotes = 0;
  int lastHeldNote = -1;
  ubyte[32] noteHistory = 0;
  int noteHistoryCount = 0;
  bool noteHeldForActive = false;

  // --- Pending Handover ---
  bool pendingHandover = false;
  int handoverGestureIndex = 0;
  double targetHandoverBeat = 0.0;

  // ===========================================================================
  // Public Lifecycle & Parameter Configuration
  // ===========================================================================

  /// Reset internal state, sample rate, and clear all note history.
  void reset(double sampleRate) pure @safe {
    this.sampleRate = (sampleRate > 0.0 && isFinite(sampleRate)) ? sampleRate : 44100.0;
    this.state = this.autoMode ? GestureState.active : GestureState.idle;
    this.phase = 0.0f;
    this.prevPhase = 0.0f;
    this.palindromeDir = 1;
    this.currentGestureIndex = this.defaultGestureIndex;
    this.pendingGestureIndex = 0;
    this.triggeredThisSample = false;

    this.hostIsPlaying = false;
    this.currentSongBeats = 0.0;
    this.internalBeats = 0.0;
    this.internalSampleCount = 0;
    this.targetGridBeat = 0.0;
    this.targetReleaseBeat = 0.0;

    this.noteHeld[] = false;
    this.numHeldNotes = 0;
    this.lastHeldNote = -1;
    this.noteHistoryCount = 0;
    this.noteHeldForActive = false;

    this.pendingHandover = false;
    this.handoverGestureIndex = 0;
    this.targetHandoverBeat = 0.0;
  }

  /// Configure core parameters from plugin controls.
  void setParams(bool autoMode, int releaseMode, float gestureBeats, int quantizeGrid) pure @safe {
    const bool prevAuto = this.autoMode;
    this.autoMode = autoMode;
    this.releaseMode = cast(ReleaseMode)releaseMode;
    this.gestureBeats = (gestureBeats > 0.001f && isFinite(gestureBeats)) ? gestureBeats : 4.0f;
    this.quantizeGrid = cast(QuantizeGrid)quantizeGrid;

    // Transitioning from MIDI to Auto Mode
    if (!prevAuto && this.autoMode) {
      this.state = GestureState.active;
      this.pendingHandover = false;
    } else if (prevAuto && !this.autoMode) {
      // Transitioning from Auto to MIDI Mode
      if (this.numHeldNotes == 0) {
        this.state = GestureState.idle;
        this.phase = 0.0f;
      }
    }
  }

  /// Update host transport state and current project song position in beats.
  void updateHostTransport(bool hostIsPlaying, double songBeats) pure @safe {
    this.hostIsPlaying = hostIsPlaying;
    this.currentSongBeats = songBeats;
  }

  /// Set the base MIDI note for note-to-gesture mapping (e.g. 36 for C2, 48 for C3).
  void setBaseNote(int noteNumber) pure @safe {
    this.baseMidiNote = (noteNumber >= 0 && noteNumber <= 104) ? noteNumber : DEFAULT_BASE_MIDI_NOTE;
  }

  /// Set the default gesture index used when auto mode starts without prior note input.
  void setDefaultGesture(int gestureIndex) pure @safe {
    this.defaultGestureIndex = (gestureIndex >= 0 && gestureIndex < MAX_GESTURES) ? gestureIndex : 0;
    if (this.state == GestureState.idle) {
      this.currentGestureIndex = this.defaultGestureIndex;
    }
  }

  /// Trigger gesture manually from UI (e.g. clicking mini keyboard strip or pad).
  void triggerManual(int gestureIndex, double currentBeats) pure @safe {
    const int idx = (gestureIndex >= 0 && gestureIndex < MAX_GESTURES) ? gestureIndex : 0;
    this.currentGestureIndex = idx;
    this.state = GestureState.active;
    this.phase = 0.0f;
    this.prevPhase = 0.0f;
    this.palindromeDir = 1;
    this.triggeredThisSample = true;
    this.noteHeldForActive = true;
    this.pendingHandover = false;
  }

  /// Release manual gesture trigger.
  void releaseManual(double currentBeats) pure @safe {
    this.noteHeldForActive = false;
    if (this.releaseMode == ReleaseMode.instant && !this.stickMode) {
      this.state = GestureState.idle;
      this.phase = 0.0f;
      this.palindromeDir = 1;
    }
  }

  /// Panic / All-Notes-Off handler.
  void allNotesOff() pure @safe {
    this.noteHeld[] = false;
    this.numHeldNotes = 0;
    this.lastHeldNote = -1;
    this.noteHistoryCount = 0;
    this.noteHeldForActive = false;
    this.pendingHandover = false;
    if (!this.autoMode) {
      this.state = GestureState.idle;
      this.phase = 0.0f;
      this.palindromeDir = 1;
    }
  }

  // ===========================================================================
  // MIDI Input Handling
  // ===========================================================================

  /// Handle incoming MIDI message at the current beat position.
  void handleMidi(MidiMessage msg, double currentBeats) @system {
    if (msg.isAllNotesOff() || msg.isAllSoundsOff()) {
      allNotesOff();
      return;
    }

    if (msg.isNoteOn()) {
      handleNoteOn(msg.noteNumber(), msg.noteVelocity(), currentBeats);
    } else if (msg.isNoteOff()) {
      handleNoteOff(msg.noteNumber(), currentBeats);
    }
  }

  /// Private Note-On state transition logic.
  private void handleNoteOn(int note, int velocity, double currentBeats) pure @safe {
    if (note >= 0 && note < 128) {
      if (!this.noteHeld[note]) {
        this.noteHeld[note] = true;
        this.numHeldNotes++;
      }
      this.lastHeldNote = note;
      if (this.noteHistoryCount < this.noteHistory.length) {
        this.noteHistory[this.noteHistoryCount++] = cast(ubyte)note;
      } else {
        for (size_t i = 1; i < this.noteHistory.length; ++i) {
          this.noteHistory[i - 1] = this.noteHistory[i];
        }
        this.noteHistory[$ - 1] = cast(ubyte)note;
      }
    }

    const int targetGesture = mapMidiNoteToGesture(note, this.baseMidiNote);

    // Stick mode: re-pressing the active gesture key releases it
    if (this.stickMode && !this.autoMode && this.state == GestureState.active &&
        this.currentGestureIndex == targetGesture) {
      this.state = GestureState.idle;
      this.phase = 0.0f;
      this.palindromeDir = 1;
      this.noteHeldForActive = false;
      this.pendingHandover = false;
      return;
    }

    // In Auto Mode, hitting a note changes the active gesture for the ongoing cycle
    if (this.autoMode) {
      this.currentGestureIndex = targetGesture;
      return;
    }

    const double G = quantizeGridBeats[this.quantizeGrid];

    // Instant Quantize: activate immediately
    if (G <= 0.0) {
      this.state = GestureState.active;
      this.currentGestureIndex = targetGesture;
      this.phase = 0.0f;
      this.prevPhase = 0.0f;
      this.palindromeDir = 1;
      this.triggeredThisSample = true;
      this.noteHeldForActive = true;
      this.pendingHandover = false;
      return;
    }

    // Grid Quantize active: check if right on the grid line
    double m = modBeats(currentBeats, G);
    if (m < 1e-6 || (G - m) < 1e-6) {
      this.state = GestureState.active;
      this.currentGestureIndex = targetGesture;
      this.phase = 0.0f;
      this.prevPhase = 0.0f;
      this.palindromeDir = 1;
      this.triggeredThisSample = true;
      this.noteHeldForActive = true;
      this.pendingHandover = false;
      return;
    }

    // If currently running, queue clean handover at next grid boundary
    if (this.state == GestureState.active || this.state == GestureState.pendingRelease) {
      this.pendingHandover = true;
      this.handoverGestureIndex = targetGesture;
      this.targetHandoverBeat = nextGridBoundary(currentBeats, G);
      this.noteHeldForActive = true;
      this.state = GestureState.active;
    } else {
      // Idle or pending trigger: queue start at next grid boundary
      this.state = GestureState.pendingTrigger;
      this.pendingGestureIndex = targetGesture;
      this.targetGridBeat = nextGridBoundary(currentBeats, G);
      this.noteHeldForActive = true;
    }
  }

  /// Private Note-Off state transition logic.
  private void handleNoteOff(int note, double currentBeats) pure @safe {
    if (note >= 0 && note < 128) {
      if (this.noteHeld[note]) {
        this.noteHeld[note] = false;
        if (this.numHeldNotes > 0) this.numHeldNotes--;
      }
      if (note == this.lastHeldNote) {
        this.lastHeldNote = -1;
        for (int i = this.noteHistoryCount - 1; i >= 0; --i) {
          ubyte n = this.noteHistory[i];
          if (this.noteHeld[n]) {
            this.lastHeldNote = n;
            break;
          }
        }
      }
    }

    if (this.autoMode || this.stickMode) return;

    // Polyphonic legato check: if other notes are still held, handover to previous note
    if (this.numHeldNotes > 0 && this.lastHeldNote >= 0) {
      const int targetGesture = mapMidiNoteToGesture(this.lastHeldNote, this.baseMidiNote);
      const double G = quantizeGridBeats[this.quantizeGrid];
      if (G <= 0.0) {
        this.currentGestureIndex = targetGesture;
        this.phase = 0.0f;
        this.prevPhase = 0.0f;
        this.palindromeDir = 1;
        this.triggeredThisSample = true;
      } else {
        this.pendingHandover = true;
        this.handoverGestureIndex = targetGesture;
        this.targetHandoverBeat = nextGridBoundary(currentBeats, G);
      }
      return;
    }

    // All notes released
    this.noteHeldForActive = false;

    if (this.state == GestureState.pendingTrigger) {
      if (this.releaseMode == ReleaseMode.instant) {
        this.state = GestureState.idle;
        this.phase = 0.0f;
        this.palindromeDir = 1;
      }
      return;
    }

    if (this.state == GestureState.active) {
      final switch (this.releaseMode) {
        case ReleaseMode.instant:
          this.state = GestureState.idle;
          this.phase = 0.0f;
          this.palindromeDir = 1;
          this.pendingHandover = false;
          break;
        case ReleaseMode.latch:
          // Latch ignores release, continues looping indefinitely
          break;
        case ReleaseMode.fullGesture:
          // Runs through until gesturePhase >= 1.0, handled in advanceSample
          break;
        case ReleaseMode.onGrid:
          const double G = quantizeGridBeats[this.quantizeGrid];
          if (G <= 0.0) {
            this.state = GestureState.idle;
            this.phase = 0.0f;
            this.palindromeDir = 1;
          } else {
            this.state = GestureState.pendingRelease;
            this.targetReleaseBeat = nextGridBoundary(currentBeats, G);
          }
          break;
      }
    }
  }

  // ===========================================================================
  // Per-Sample Phase Progression Engine
  // ===========================================================================

  /// Advance time by 1 sample and compute current normalized phase and active state.
  void advanceSample(double beatPerSample, out float gesturePhase, out bool isActive, out int activeGestureIndex) pure @safe {
    bool dummyTriggered;
    advanceSample(beatPerSample, gesturePhase, isActive, activeGestureIndex, dummyTriggered);
  }

  /// Advance time by 1 sample with retrigger event notification.
  void advanceSample(double beatPerSample, out float gesturePhase, out bool isActive,
                     out int activeGestureIndex, out bool justTriggered) pure @safe {
    const double safeBps = (beatPerSample > 0.0 && isFinite(beatPerSample)) ?
      beatPerSample : (120.0 / (60.0 * this.sampleRate));

    // Internal time fallback progression
    this.internalSampleCount++;
    this.internalBeats += safeBps;
    this.currentSongBeats += safeBps;

    const double currentBeats = this.hostIsPlaying ? this.currentSongBeats : this.internalBeats;

    bool wasTriggered = this.triggeredThisSample;
    this.triggeredThisSample = false;

    // --- AUTO MODE ---
    if (this.autoMode) {
      this.state = GestureState.active;
      if (!this.freezeActive) {
        const double L = (this.gestureBeats > 0.001) ? this.gestureBeats : 4.0;
        if (this.palindrome) {
          const double m2 = modBeats(currentBeats, 2.0 * L);
          float newPhase;
          if (m2 < L) {
            newPhase = cast(float)(m2 / L);
            this.palindromeDir = 1;
          } else {
            newPhase = 1.0f - cast(float)((m2 - L) / L);
            this.palindromeDir = -1;
          }
          if (newPhase < 0.0f) newPhase = 0.0f;
          if (newPhase >= 1.0f) newPhase = 0.999999f;
          if (this.palindromeDir == 1 && newPhase < 0.05f && this.prevPhase >= 0.05f && m2 < L * 0.1) {
            wasTriggered = true;
          }
          this.prevPhase = newPhase;
          this.phase = newPhase;
        } else {
          this.palindromeDir = 1;
          double m = modBeats(currentBeats, L);
          float newPhase = cast(float)(m / L);
          if (newPhase < 0.0f) newPhase = 0.0f;
          if (newPhase >= 1.0f) newPhase = 0.999999f;

          // Detect loop boundary retrigger
          if (newPhase < this.prevPhase - 0.5f) {
            wasTriggered = true;
          }
          this.prevPhase = newPhase;
          this.phase = newPhase;
        }
      }

      gesturePhase = this.phase;
      isActive = true;
      activeGestureIndex = this.currentGestureIndex;
      justTriggered = wasTriggered;
      return;
    }

    // --- MIDI TRIGGER MODE ---

    // 1. Process pending trigger waiting for grid boundary
    if (this.state == GestureState.pendingTrigger) {
      if (currentBeats >= this.targetGridBeat - 1e-6) {
        this.state = GestureState.active;
        this.currentGestureIndex = this.pendingGestureIndex;
        this.phase = 0.0f;
        this.prevPhase = 0.0f;
        this.palindromeDir = 1;
        wasTriggered = true;
      }
    }

    // 2. Process pending handover between active gestures
    if (this.state == GestureState.active && this.pendingHandover) {
      if (currentBeats >= this.targetHandoverBeat - 1e-6) {
        this.currentGestureIndex = this.handoverGestureIndex;
        this.phase = 0.0f;
        this.prevPhase = 0.0f;
        this.palindromeDir = 1;
        this.pendingHandover = false;
        wasTriggered = true;
      }
    }

    // 3. Process pending release waiting for grid boundary
    if (this.state == GestureState.pendingRelease) {
      if (currentBeats >= this.targetReleaseBeat - 1e-6) {
        this.state = GestureState.idle;
        this.phase = 0.0f;
        this.prevPhase = 0.0f;
        this.palindromeDir = 1;
      }
    }

    // 4. Advance phase if active or pending release (paused when Freeze active)
    if (!this.freezeActive && (this.state == GestureState.active || this.state == GestureState.pendingRelease)) {
      const double L = (this.gestureBeats > 0.001) ? this.gestureBeats : 4.0;
      const float phaseInc = cast(float)(safeBps / L);
      const bool shouldLoop = (this.stickMode || this.releaseMode == ReleaseMode.latch ||
                               this.numHeldNotes > 0 || this.noteHeldForActive);

      if (this.palindrome) {
        this.phase += phaseInc * cast(float) this.palindromeDir;
        if (this.phase >= 1.0f) {
          if (this.state == GestureState.pendingRelease) {
            this.state = GestureState.idle;
            this.phase = 0.0f;
            this.palindromeDir = 1;
          } else {
            this.phase = 2.0f - this.phase;
            if (this.phase > 1.0f) this.phase = 1.0f;
            this.palindromeDir = -1;
          }
        } else if (this.phase <= 0.0f) {
          if (this.state == GestureState.pendingRelease || !shouldLoop) {
            this.state = GestureState.idle;
            this.phase = 0.0f;
            this.palindromeDir = 1;
          } else {
            this.phase = -this.phase;
            if (this.phase < 0.0f) this.phase = 0.0f;
            this.palindromeDir = 1;
            wasTriggered = true;
          }
        }
      } else {
        this.palindromeDir = 1;
        this.phase += phaseInc;

        if (this.phase >= 1.0f) {
          if (this.state == GestureState.pendingRelease) {
            this.state = GestureState.idle;
            this.phase = 0.0f;
          } else if (shouldLoop) {
            // Loop gesture
            this.phase = cast(float)modBeats(this.phase, 1.0);
            wasTriggered = true;
          } else {
            // No notes held and not latch/stick
            final switch (this.releaseMode) {
              case ReleaseMode.fullGesture:
              case ReleaseMode.onGrid:
              case ReleaseMode.instant:
                this.state = GestureState.idle;
                this.phase = 0.0f;
                break;
              case ReleaseMode.latch:
                this.phase = cast(float)modBeats(this.phase, 1.0);
                wasTriggered = true;
                break;
            }
          }
        }
      }
    }

    // Output values
    if (this.state == GestureState.active || this.state == GestureState.pendingRelease) {
      gesturePhase = this.phase;
      isActive = true;
      activeGestureIndex = this.currentGestureIndex;
    } else {
      gesturePhase = 0.0f;
      isActive = false;
      activeGestureIndex = this.currentGestureIndex;
    }

    this.prevPhase = this.phase;
    justTriggered = wasTriggered;
  }

  // ===========================================================================
  // Property Getters
  // ===========================================================================

  GestureState getState() const pure @safe { return this.state; }
  bool getIsActive() const pure @safe { return this.state == GestureState.active || this.state == GestureState.pendingRelease; }
  float getGesturePhase() const pure @safe { return this.phase; }
  int getActiveGestureIndex() const pure @safe { return this.currentGestureIndex; }
  bool getJustTriggered() const pure @safe { return this.triggeredThisSample; }
}

// =============================================================================
// Comprehensive Unit Tests
// =============================================================================

unittest {
  import dplug.client.midi : makeMidiMessageNoteOn, makeMidiMessageNoteOff;

  // 1. Initial State & Reset
  GestureController ctrl;
  ctrl.reset(44100.0);
  assert(ctrl.getState() == GestureState.idle);
  assert(!ctrl.getIsActive());
  assert(ctrl.getGesturePhase() == 0.0f);
  assert(ctrl.getActiveGestureIndex() == 0);

  // 2. Note to Gesture Mapping
  assert(mapMidiNoteToGesture(36) == 0);  // C2
  assert(mapMidiNoteToGesture(37) == 1);  // C#2
  assert(mapMidiNoteToGesture(59) == 23); // B3
  assert(mapMidiNoteToGesture(60) == 0);  // C4 wraps to 0
  assert(mapMidiNoteToGesture(48, 48) == 0); // With C3 base

  // 3. Grid Boundary Helper
  assert(nextGridBoundary(0.0, 1.0) == 0.0);
  assert(nextGridBoundary(0.25, 1.0) == 1.0);
  assert(nextGridBoundary(1.0, 1.0) == 1.0);
  assert(nextGridBoundary(1.001, 1.0) == 2.0);
  assert(nextGridBoundary(-0.5, 1.0) == 0.0);

  // 4. Time Conversion Helpers
  assert(beatsToSeconds(2.0, 120.0) == 1.0);
  assert(beatsToSamples(2.0, 120.0, 44100.0) == 44100);
  assert(samplesToBeats(44100, 120.0, 44100.0) == 2.0);

  // 5. Auto Mode - Continuous Tempo Synced Looping
  ctrl.reset(44100.0);
  ctrl.setParams(true, ReleaseMode.instant, 4.0f, QuantizeGrid.instant);
  ctrl.updateHostTransport(true, 0.0);

  const double bps = 120.0 / (60.0 * 44100.0); // 120 BPM
  float phase;
  bool active;
  int gestureIdx;
  bool justTriggered;

  // Advance 1 beat (22050 samples) -> phase should reach 0.25
  foreach (_; 0 .. 22050) {
    ctrl.advanceSample(bps, phase, active, gestureIdx, justTriggered);
  }
  assert(active);
  assert(phase >= 0.249f && phase <= 0.251f);

  // Advance 3 more beats (66150 samples) -> should complete 4-beat cycle and wrap
  bool sawRetrigger = false;
  foreach (_; 0 .. 66150) {
    ctrl.advanceSample(bps, phase, active, gestureIdx, justTriggered);
    if (justTriggered) sawRetrigger = true;
  }
  assert(active);
  assert(sawRetrigger);
  assert(phase >= 0.0f && phase < 0.01f);

  // 6. Auto Mode - Host Stopped Fallback (Internal Sample Counter)
  ctrl.reset(44100.0);
  ctrl.setParams(true, ReleaseMode.instant, 4.0f, QuantizeGrid.instant);
  ctrl.updateHostTransport(false, 0.0);

  foreach (_; 0 .. 44100) {
    ctrl.advanceSample(bps, phase, active, gestureIdx);
  }
  assert(active);
  assert(phase >= 0.499f && phase <= 0.501f);

  // 7. MIDI Trigger Mode - Instant Release Mode
  ctrl.reset(44100.0);
  ctrl.setParams(false, ReleaseMode.instant, 4.0f, QuantizeGrid.instant);
  assert(!ctrl.getIsActive());

  // Note-On (Note 38 -> Gesture 2)
  MidiMessage noteOn = makeMidiMessageNoteOn(0, 0, 38, 100);
  ctrl.handleMidi(noteOn, 0.0);
  ctrl.advanceSample(bps, phase, active, gestureIdx, justTriggered);
  assert(active);
  assert(gestureIdx == 2);
  assert(justTriggered);

  // Note-Off -> deactivates immediately
  MidiMessage noteOff = makeMidiMessageNoteOff(0, 0, 38);
  ctrl.handleMidi(noteOff, 0.1);
  ctrl.advanceSample(bps, phase, active, gestureIdx);
  assert(!active);
  assert(phase == 0.0f);

  // 8. MIDI Trigger Mode - Full Gesture Release Mode
  ctrl.reset(44100.0);
  ctrl.setParams(false, ReleaseMode.fullGesture, 1.0f, QuantizeGrid.instant); // 1 beat gesture

  ctrl.handleMidi(noteOn, 0.0);
  ctrl.advanceSample(bps, phase, active, gestureIdx);
  assert(active);

  // Quick Note-Off early in the gesture
  ctrl.handleMidi(noteOff, 0.1);
  ctrl.advanceSample(bps, phase, active, gestureIdx);
  assert(active); // Still active! Full gesture must finish

  // Advance remaining samples of 1 beat (22050 total)
  foreach (_; 0 .. 22050) {
    ctrl.advanceSample(bps, phase, active, gestureIdx);
  }
  // Now that full gesture finished, it deactivates
  assert(!active);

  // 9. MIDI Trigger Mode - Latch Mode
  ctrl.reset(44100.0);
  ctrl.setParams(false, ReleaseMode.latch, 1.0f, QuantizeGrid.instant);
  ctrl.handleMidi(noteOn, 0.0);
  ctrl.handleMidi(noteOff, 0.1); // Released immediately
  // Advance through 3 complete cycles
  foreach (_; 0 .. 66150) {
    ctrl.advanceSample(bps, phase, active, gestureIdx);
    assert(active); // Must remain active in latch mode
  }

  // 10. Quantize Grid Alignment
  ctrl.reset(44100.0);
  ctrl.setParams(false, ReleaseMode.instant, 4.0f, QuantizeGrid.grid1_4); // 1.0 beat grid
  ctrl.updateHostTransport(true, 0.3); // In between beats

  ctrl.handleMidi(noteOn, 0.3);
  ctrl.advanceSample(bps, phase, active, gestureIdx);
  assert(!active); // Pending quantize grid!
  assert(ctrl.getState() == GestureState.pendingTrigger);

  // Advance to beat 1.0 (0.7 beats = 15435 samples)
  foreach (_; 0 .. 15435) {
    ctrl.advanceSample(bps, phase, active, gestureIdx, justTriggered);
  }
  assert(active);
  assert(gestureIdx == 2);

  // 11. Legato Handover (Polyphonic Note Priority)
  ctrl.reset(44100.0);
  ctrl.setParams(false, ReleaseMode.instant, 4.0f, QuantizeGrid.instant);

  MidiMessage note1 = makeMidiMessageNoteOn(0, 0, 36, 100); // Gesture 0
  MidiMessage note2 = makeMidiMessageNoteOn(0, 0, 40, 100); // Gesture 4
  ctrl.handleMidi(note1, 0.0);
  ctrl.advanceSample(bps, phase, active, gestureIdx);
  assert(gestureIdx == 0);

  // Press second note while holding first -> switches to Gesture 4
  ctrl.handleMidi(note2, 0.1);
  ctrl.advanceSample(bps, phase, active, gestureIdx);
  assert(gestureIdx == 4);

  // Release second note -> reverts to still-held first note (Gesture 0)
  MidiMessage note2Off = makeMidiMessageNoteOff(0, 0, 40);
  ctrl.handleMidi(note2Off, 0.2);
  ctrl.advanceSample(bps, phase, active, gestureIdx);
  assert(active);
  assert(gestureIdx == 0);

  // Release first note -> now deactivates
  MidiMessage note1Off = makeMidiMessageNoteOff(0, 0, 36);
  ctrl.handleMidi(note1Off, 0.3);
  ctrl.advanceSample(bps, phase, active, gestureIdx);
  assert(!active);

  // 12. Negative Song Time Stability
  ctrl.reset(44100.0);
  ctrl.setParams(true, ReleaseMode.instant, 4.0f, QuantizeGrid.instant);
  ctrl.updateHostTransport(true, -10.0); // 10 beats before start
  ctrl.advanceSample(bps, phase, active, gestureIdx);
  assert(phase >= 0.0f && phase < 1.0f);
  assert(active);

  // 13. Quantized Handover
  ctrl.reset(44100.0);
  ctrl.setParams(false, ReleaseMode.instant, 4.0f, QuantizeGrid.grid1_4); // 1.0 beat grid
  ctrl.updateHostTransport(true, 0.0);

  // Start Gesture 0 on beat 0.0
  ctrl.handleMidi(note1, 0.0);
  ctrl.advanceSample(bps, phase, active, gestureIdx);
  assert(active);
  assert(gestureIdx == 0);

  // Advance to beat 0.5
  foreach (_; 0 .. 11024) {
    ctrl.advanceSample(bps, phase, active, gestureIdx);
  }
  assert(gestureIdx == 0); // Still Gesture 0

  // Hit Note 2 (Gesture 4) at beat 0.5 -> pending handover at beat 1.0
  ctrl.handleMidi(note2, 0.5);
  ctrl.advanceSample(bps, phase, active, gestureIdx);
  assert(gestureIdx == 0); // Still Gesture 0 while waiting for grid beat 1.0

  // Advance remaining samples to beat 1.0
  foreach (_; 0 .. 11025) {
    ctrl.advanceSample(bps, phase, active, gestureIdx, justTriggered);
  }
  // Now on beat 1.0, handover occurred!
  assert(gestureIdx == 4);
  assert(active);

  // 14. All Notes Off / Panic
  ctrl.allNotesOff();
  ctrl.advanceSample(bps, phase, active, gestureIdx);
  assert(!active);
  assert(phase == 0.0f);

  // 15. Manual UI Trigger and Release
  ctrl.reset(44100.0);
  ctrl.setParams(false, ReleaseMode.instant, 2.0f, QuantizeGrid.instant);
  ctrl.triggerManual(7, 0.0);
  ctrl.advanceSample(bps, phase, active, gestureIdx);
  assert(active);
  assert(gestureIdx == 7);
  ctrl.releaseManual(0.1);
  ctrl.advanceSample(bps, phase, active, gestureIdx);
  assert(!active);

  // 16. Multi-Sample-Rate Lifecycle Stability
  const double[] testRates = [44100.0, 48000.0, 88200.0, 96000.0, 192000.0];
  foreach (sr; testRates) {
    ctrl.reset(sr);
    ctrl.setParams(true, ReleaseMode.instant, 4.0f, QuantizeGrid.instant);
    const double sBps = 120.0 / (60.0 * sr);
    foreach (_; 0 .. 1000) {
      ctrl.advanceSample(sBps, phase, active, gestureIdx);
      assert(active);
      assert(phase >= 0.0f && phase < 1.0f);
    }
  }
}
