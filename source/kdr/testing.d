module kdr.testing;

import std.datetime.stopwatch : benchmark;

import dplug.core;
import dplug.client;

import kdr.logging : logInfo;

/// Mock host for testing a client.
struct GenericTestHost(C) {
  C client;
  int frames = 8;
  Vec!float[2] inputFrames, outputFrames;
  MidiMessage msg1 = makeMidiMessageNoteOn(0, 0, 100, 100);
  MidiMessage msg2 = makeMidiMessageNoteOn(1, 0, 90, 10);
  MidiMessage msg3 = makeMidiMessageNoteOff(2, 0, 100);
  bool noteOff = false;

  @nogc nothrow:

  void processAudio() {
    inputFrames[0].resize(this.frames);
    inputFrames[1].resize(this.frames);
    outputFrames[0].resize(this.frames);
    outputFrames[1].resize(this.frames);
    client.reset(44_100, 32, 0, 2);

    float*[2] inputs, outputs;
    inputs[0] = &outputFrames[0][0];
    inputs[1] = &inputFrames[1][0];
    outputs[0] = &outputFrames[0][0];
    outputs[1] = &outputFrames[1][0];

    client.enqueueMIDIFromHost(msg1);
    client.enqueueMIDIFromHost(msg2);
    if (noteOff) {
      client.enqueueMIDIFromHost(msg3);
    }

    TimeInfo info;
    info.hostIsPlaying = true;
    client.processAudioFromHost(inputs[], outputs[], frames, info);
  }
}

/// Test default params with benchmark.
void benchmarkWithDefaultParams(ClientImpl)(int timeoutMSec = 20) {
  GenericTestHost!ClientImpl host = { client: new ClientImpl(), frames: 100 };

  host.processAudio();  // to omit the first record.
  auto time = benchmark!(() => host.processAudio())(100)[0].split!("msecs", "usecs");
  logInfo("benchmark %s/default: %d ms %d us", ClientImpl.stringof.ptr,
          cast(int) time.msecs, cast(int) time.usecs);

  version (D_Coverage) {}
  else {
    version (OSX) {}
    else {
      version (LDC) assert(time.msecs <= timeoutMSec);
    }
  }
}
