module kdr.epiano2.client;

import std.algorithm : min;

import dplug.core : mallocNew, makeVec, Vec;
import dplug.client : Client, IntegerParameter, LegalIO, LinearFloatParameter, MidiControlChange, MidiMessage, Parameter, PluginInfo, Preset, TimeInfo;
import mir.math : fabs, fastmath, exp, pow;

import kdr.audiofmt : Wav;
import kdr.epiano2.parameter : ModParameter;
import kdr.testing : benchmarkWithDefaultParams;

enum Param : int {
  envelopeDecay = 0,
  envelopeRelease = 1,
  hardness = 2,
  trebleBoost = 3,
  modulation = 4,
  lfoRate = 5, // see resume() to get unnormalized val
  velocitySense = 6,
  stereoWidth = 7,
  polyphony = 8,
  fineTuning = 9,
  randomTuning = 10,
  overdrive = 11,
}

struct Voice {
  // Sample playback.
  int delta;
  int frac;
  int pos;
  int end;
  int loop;

  // Envelope.
  float env = 0.0f;
  float dec = 0.99f;  // all notes off.

  // First-order LPF.
  float f0 = 0;
  float f1 = 0;
  float ff = 0;

  float outl = 0;
  float outr = 0;
  int note;
}

struct KeyGroup {
  int root;
  int high;
  int pos;
  int end;
  int loop;
}

class Epiano2Client : Client {
  @fastmath nothrow @nogc public:

  this() {
    super();
    //Waveform data and keymapping
    kgrp[ 0].root = 36;  kgrp[ 0].high = 39; //C1
    kgrp[ 3].root = 43;  kgrp[ 3].high = 45; //G1
    kgrp[ 6].root = 48;  kgrp[ 6].high = 51; //C2
    kgrp[ 9].root = 55;  kgrp[ 9].high = 57; //G2
    kgrp[12].root = 60;  kgrp[12].high = 63; //C3
    kgrp[15].root = 67;  kgrp[15].high = 69; //G3
    kgrp[18].root = 72;  kgrp[18].high = 75; //C4
    kgrp[21].root = 79;  kgrp[21].high = 81; //G4
    kgrp[24].root = 84;  kgrp[24].high = 87; //C5
    kgrp[27].root = 91;  kgrp[27].high = 93; //G5
    kgrp[30].root = 96;  kgrp[30].high =999; //C6

    kgrp[0].pos = 0;        kgrp[0].end = 8476;     kgrp[0].loop = 4400;
    kgrp[1].pos = 8477;     kgrp[1].end = 16248;    kgrp[1].loop = 4903;
    kgrp[2].pos = 16249;    kgrp[2].end = 34565;    kgrp[2].loop = 6398;
    kgrp[3].pos = 34566;    kgrp[3].end = 41384;    kgrp[3].loop = 3938;
    kgrp[4].pos = 41385;    kgrp[4].end = 45760;    kgrp[4].loop = 1633; //was 1636;
    kgrp[5].pos = 45761;    kgrp[5].end = 65211;    kgrp[5].loop = 5245;
    kgrp[6].pos = 65212;    kgrp[6].end = 72897;    kgrp[6].loop = 2937;
    kgrp[7].pos = 72898;    kgrp[7].end = 78626;    kgrp[7].loop = 2203; //was 2204;
    kgrp[8].pos = 78627;    kgrp[8].end = 100387;   kgrp[8].loop = 6368;
    kgrp[9].pos = 100388;   kgrp[9].end = 116297;   kgrp[9].loop = 10452;
    kgrp[10].pos = 116298;  kgrp[10].end = 127661;  kgrp[10].loop = 5217; //was 5220;
    kgrp[11].pos = 127662;  kgrp[11].end = 144113;  kgrp[11].loop = 3099;
    kgrp[12].pos = 144114;  kgrp[12].end = 152863;  kgrp[12].loop = 4284;
    kgrp[13].pos = 152864;  kgrp[13].end = 173107;  kgrp[13].loop = 3916;
    kgrp[14].pos = 173108;  kgrp[14].end = 192734;  kgrp[14].loop = 2937;
    kgrp[15].pos = 192735;  kgrp[15].end = 204598;  kgrp[15].loop = 4732;
    kgrp[16].pos = 204599;  kgrp[16].end = 218995;  kgrp[16].loop = 4733;
    kgrp[17].pos = 218996;  kgrp[17].end = 233801;  kgrp[17].loop = 2285;
    kgrp[18].pos = 233802;  kgrp[18].end = 248011;  kgrp[18].loop = 4098;
    kgrp[19].pos = 248012;  kgrp[19].end = 265287;  kgrp[19].loop = 4099;
    kgrp[20].pos = 265288;  kgrp[20].end = 282255;  kgrp[20].loop = 3609;
    kgrp[21].pos = 282256;  kgrp[21].end = 293776;  kgrp[21].loop = 2446;
    kgrp[22].pos = 293777;  kgrp[22].end = 312566;  kgrp[22].loop = 6278;
    kgrp[23].pos = 312567;  kgrp[23].end = 330200;  kgrp[23].loop = 2283;
    kgrp[24].pos = 330201;  kgrp[24].end = 348889;  kgrp[24].loop = 2689;
    kgrp[25].pos = 348890;  kgrp[25].end = 365675;  kgrp[25].loop = 4370;
    kgrp[26].pos = 365676;  kgrp[26].end = 383661;  kgrp[26].loop = 5225;
    kgrp[27].pos = 383662;  kgrp[27].end = 393372;  kgrp[27].loop = 2811;
    kgrp[28].pos = 383662;  kgrp[28].end = 393372;  kgrp[28].loop = 2811; //ghost
    kgrp[29].pos = 393373;  kgrp[29].end = 406045;  kgrp[29].loop = 4522;
    kgrp[30].pos = 406046;  kgrp[30].end = 414486;  kgrp[30].loop = 2306;
    kgrp[31].pos = 406046;  kgrp[31].end = 414486;  kgrp[31].loop = 2306; //ghost
    kgrp[32].pos = 414487;  kgrp[32].end = 422408;  kgrp[32].loop = 2169;


    Wav epianoWav = Wav(import("epiano.wav"));
    const short[] epianoData = epianoWav.data;
    waves = makeVec!short(epianoData.length);
    waves.ptr[0 .. epianoData.length] = epianoData;

    //extra xfade looping...
    foreach (k; 0 .. 28) {
      int p0 = kgrp[k].end;
      int p1 = kgrp[k].end - kgrp[k].loop;

      float xf = 1.0f;
      float dxf = -0.02f;

      while(xf > 0.0f) {
        waves[p0] = cast(short)((1.0f - xf) * cast(float)waves[p0]
                                + xf * cast(float)waves[p1]);
        p0--;
        p1--;
        xf += dxf;
      }
    }
  }

  /// Needs to be overriden in bin/epiano2/main.d.
  override PluginInfo buildPluginInfo() {
    return PluginInfo.init;
  }

  override Preset[] buildPresets() {
    auto presets = makeVec!Preset();

    void fillpatch(string name, float[12] params...) {
      presets ~= mallocNew!Preset(name, params[]);
    }

    fillpatch("Default", 0.500f, 0.500f, 0.500f, 0.500f, 0.500f, 0.650f, 0.250f, 0.500f, 0.50f, 0.500f, 0.146f, 0.000f);
    fillpatch("Bright", 0.500f, 0.500f, 1.000f, 0.800f, 0.500f, 0.650f, 0.250f, 0.500f, 0.50f, 0.500f, 0.146f, 0.500f);
    fillpatch("Mellow", 0.500f, 0.500f, 0.000f, 0.000f, 0.500f, 0.650f, 0.250f, 0.500f, 0.50f, 0.500f, 0.246f, 0.000f);
    fillpatch("Autopan", 0.500f, 0.500f, 0.500f, 0.500f, 0.250f, 0.650f, 0.250f, 0.500f, 0.50f, 0.500f, 0.246f, 0.000f);
    fillpatch("Tremolo", 0.500f, 0.500f, 0.500f, 0.500f, 0.750f, 0.650f, 0.250f, 0.500f, 0.50f, 0.500f, 0.246f, 0.000f);
    fillpatch("(default)", 0.500f, 0.500f, 0.500f, 0.500f, 0.500f, 0.650f, 0.250f, 0.500f, 0.50f, 0.500f, 0.146f, 0.000f);
    fillpatch("(default)", 0.500f, 0.500f, 0.500f, 0.500f, 0.500f, 0.650f, 0.250f, 0.500f, 0.50f, 0.500f, 0.146f, 0.000f);
    fillpatch("(default)", 0.500f, 0.500f, 0.500f, 0.500f, 0.500f, 0.650f, 0.250f, 0.500f, 0.50f, 0.500f, 0.146f, 0.000f);
    return presets.releaseData;
  }

  override Parameter[] buildParameters() const {
    auto params = makeVec!Parameter();

    params ~= mallocNew!IntegerParameter(
        /*index=*/Param.envelopeDecay, /*name=*/"Envelope Decay", /*label=*/"%",
        /*min=*/0, /*max=*/100, /*defaultValue=*/50);

    params ~= mallocNew!IntegerParameter(
        /*index=*/Param.envelopeRelease, /*name=*/"Envelope Release",
        /*label=*/"%",
        /*min=*/0, /*max=*/100, /*defaultValue=*/50);

    params ~= mallocNew!IntegerParameter(
        /*index=*/Param.hardness, /*name=*/"Hardness",
        /*label=*/"%",
        /*min=*/-50, /*max=*/50, /*defaultValue=*/0);

    params ~= mallocNew!IntegerParameter(
        /*index=*/Param.trebleBoost, /*name=*/"Treble Boost", /*label=*/"%",
        /*min=*/-50, /*max=*/50, /*defaultValue=*/0);

    params ~= mallocNew!ModParameter(
        /*index=*/Param.modulation, /*name=*/"Modulation", /*label=*/"%",
        /*min=*/-100, /*max=*/100, /*defaultValue=*/0);

    params ~= mallocNew!LinearFloatParameter(
        /*index=*/Param.lfoRate, /*name=*/"LFO rate", "Hz",
        /*min=*/0.07, /*max=*/36.97, /*defaultValue=*/4.19);

    params ~= mallocNew!IntegerParameter(
        /*index=*/Param.velocitySense, /*name=*/"Velocity Sense", /*label=*/"%",
        /*min=*/0, /*max=*/100, /*defaultValue=*/25);

    params ~= mallocNew!IntegerParameter(
        /*index=*/Param.stereoWidth, /*name=*/"Stereo Width", /*label=*/"%",
        /*min=*/0, /*max=*/200, /*defaultValue=*/100);

    params ~= mallocNew!IntegerParameter(
        /*index=*/Param.polyphony, /*name=*/"Polyphony", /*label=*/"voices",
        /*min=*/0, /*max=*/32, /*defaultValue=*/16);

    params ~= mallocNew!IntegerParameter(
        /*index=*/Param.fineTuning, /*name=*/"Fine Tuning",
        /*label=*/"cents",
        /*min=*/-50, /*max=*/50, /*defaultValue=*/0);

    params ~= mallocNew!LinearFloatParameter(
        /*index=*/Param.randomTuning, /*name=*/"Random Tuning", "cents",
        /*min=*/0.0, /*max=*/50.0, /*defaultValue=*/1.1);

    params ~= mallocNew!LinearFloatParameter(
        /*index=*/Param.overdrive, /*name=*/"Overdrive", "%",
        /*min=*/0.0, /*max=*/100.0, /*defaultValue=*/0.0);

    return params.releaseData();
  }

  override LegalIO[] buildLegalIO() const {
    auto io = makeVec!LegalIO();
    io ~= LegalIO(/*numInputChannels=*/0, /*numOutputChannels*/2);
    return io.releaseData();
  }

  override void reset(
      double sampleRate, int maxFrames, int numInputs, int numOutputs) {
    Fs = sampleRate;
    iFs = 1f / sampleRate;
  }

  override int maxFramesInProcess() { return 64; }

  override void processAudio(
      const(float*)[] inputs, float*[] outputs, int sampleFrames, TimeInfo info) {
    processParams();
    processMidi(sampleFrames);

    int index, event, frame;
    while(frame<sampleFrames) {
      auto frames = notes[event++];
      if(frames>sampleFrames) frames = sampleFrames;
      frames -= frame;
      frame += frames;

      while(--frames>=0) {
        auto l = 0f;
        auto r = 0f;

        foreach (ref V; voice) {
          V.frac += V.delta;  //integer-based linear interpolation
          V.pos += V.frac >> 16;
          V.frac &= 0xFFFF;
          if(V.pos > V.end) V.pos -= V.loop;
          int i = waves[V.pos];
          i = (i << 7) + (V.frac >> 9) * (waves[V.pos + 1] - i) + 0x40400000;
          auto x = V.env * (*cast(float *)&i - 3.0f);  //fast int.float
          V.env = V.env * V.dec;  //envelope

          if(x>0.0f) { x -= overdrive * x * x;  if(x < -V.env) x = -V.env; } //+= 0.5f * x * x; } //overdrive

          l += V.outl * x;
          r += V.outr * x;
        }

        tl += tfrq * (l - tl);  //treble boost
        tr += tfrq * (r - tr);
        r  += treb * (r - tr);
        l  += treb * (l - tl);
        lfo0 += dlfo * lfo1;  //LFO for tremolo and autopan
        lfo1 -= dlfo * lfo0;
        l += l * lmod * lfo1;
        r += r * rmod * lfo1;  //worth making all these local variables?

        outputs[0][index] = l;
        outputs[1][index] = r;
        ++index;
      }

      if(frame<sampleFrames) {
        //reset LFO phase - good idea?
        if(activevoices == 0 && modulation > 0.5f) {
          lfo0 = -0.7071f;
          lfo1 = 0.7071f;
        }
        int note = notes[event++];
        int vel  = notes[event++];
        if (vel > 0) noteOn(note, vel);
        else noteOff(note);
      }
    }
    if(fabs(tl)<1.0e-10) tl = 0.0f; //anti-denormal
    if(fabs(tr)<1.0e-10) tr = 0.0f;

    for (int v=0; v<activevoices; v++)
      if(voice[v].env < SILENCE) voice[v] = voice[--activevoices];

    notes[0] = EVENTS_DONE;  //mark events buffer as done
  }

 private:
  void processMidi(int frames) {
    int npos = 0;
    foreach (MidiMessage msg; getNextMidiMessages(frames)) {
      if (msg.isNoteOn) {
        notes[npos++] = msg.offset;
        notes[npos++] = msg.noteNumber;
        notes[npos++] = msg.noteVelocity;
      } else if (msg.isNoteOff) {
        notes[npos++] = msg.offset;
        notes[npos++] = msg.noteNumber;
        notes[npos++] = 0;
      } else if (msg.isControlChange) {
        switch (msg.controlChangeControl) {
          case MidiControlChange.modWheel:
            modwhl = msg.controlChangeValue0to1;
            //over-ride pan/trem depth
            if(modwhl > 0.05f) {
              rmod = lmod = modwhl; //lfo depth
              if(modulation < 0.5f) rmod = -rmod;
            }
            break;
          case MidiControlChange.channelVolume:
            volume = 0.00002f * cast(float) (msg.controlChangeValue * msg.controlChangeValue);
            break;

          case MidiControlChange.sustainOnOff:
          case MidiControlChange.sustenutoOnOff:
            sustain = msg.controlChangeValue & 0x44;
            if (sustain == 0) {
              notes[npos++] = msg.offset;
              notes[npos++] = SUSTAIN; //end all sustained notes
              notes[npos++] = 0;
            }
            break;
          case MidiControlChange.allNotesOff:
          case MidiControlChange.allSoundsOff:
            for(int v=0; v<NVOICES; v++) voice[v].dec=0.99f;
            sustain = 0;
            muff = 160.0f;
            break;
          default:
            break;
        }
      }

      // TODO support program change.
      if (npos > EVENTBUFFER) npos -= 3; // discard events if buffer full
    }
    notes[npos] = EVENTS_DONE;
  }

  void noteOn(int note, int velocity) {
    int vl;
    if(activevoices < poly) {
      vl = activevoices;
      activevoices++;
      voice[vl].f0 = voice[vl].f1 = 0.0f;
    } else {
      //steal a note
      //find quietest voice
      float l = float.infinity;
      foreach (v; 0 .. poly) {
        if(voice[v].env < l) { l = voice[v].env;  vl = v; }
      }
    }

    int k = (note - 60) * (note - 60);
    float l = fine + random * (cast(float)(k % 13) - 6.5f);  //random & fine tune
    if(note > 60) l += stretch * cast(float)k; //stretch

    k = 0;
    while(note > (kgrp[k].high + size)) k += 3;  //find keygroup

    l += cast(float)(note - kgrp[k].root); //pitch
    l = 32000.0f * iFs * cast(float)exp(0.05776226505 * l);
    voice[vl].delta = cast(int)(65536.0f * l);
    voice[vl].frac = 0;

    if(velocity > 48) k++; //mid velocity sample
    if(velocity > 80) k++; //high velocity sample
    voice[vl].pos = kgrp[k].pos;
    voice[vl].end = kgrp[k].end - 1;
    voice[vl].loop = kgrp[k].loop;

    voice[vl].env = (3.0f + 2.0f * velsens) * cast(float)pow(0.0078f * velocity, velsens); //velocity

    if(note > 60) voice[vl].env *= cast(float)exp(0.01f * cast(float)(60 - note)); //new! high notes quieter

    l = 50.0f + modulation * modulation * muff + muffvel * cast(float)(velocity - 64); //muffle
    if(l < (55.0f + 0.4f * cast(float)note)) l = 55.0f + 0.4f * cast(float)note;
    if(l > 210.0f) l = 210.0f;
    voice[vl].ff = l * l * iFs;

    voice[vl].note = note; //note->pan
    if(note <  12) note = 12;
    if(note > 108) note = 108;
    l = volume;
    voice[vl].outr = l + l * width * cast(float)(note - 60);
    voice[vl].outl = l + l - voice[vl].outr;

    if (note < 44) note = 44;
    voice[vl].dec = cast(float) exp(
        -iFs * exp(-1.0 + 0.03 * cast(double)note - 2.0f * decay));
  }

  void noteOff(int note) {
    const dec = cast(float) exp(-iFs * exp(6.0 + 0.01 * cast(double) note - 5.0 * release));
    foreach (v; 0 .. NVOICES) {
      //any voices playing that note?
      if(voice[v].note == note) {
        if(sustain == 0) voice[v].dec = dec;
        else voice[v].note = SUSTAIN;
      }
    }
  }

  void processParams() {
    size = cast(int) (12f * param(Param.hardness).getNormalized - 6.0);

    auto trebNormalized = param(Param.trebleBoost).getNormalized;
    treb = 4f * trebNormalized * trebNormalized - 1f;
    tfrq = (trebNormalized > 0.5f) ? 14000f : 5000f;
    tfrq = 1.0f - cast(float) exp(-iFs * tfrq);

    auto modNormalized = param(Param.modulation).getNormalized;
    rmod = lmod = 2 * modNormalized - 1.0f; //lfo depth
    if(modNormalized < 0.5f) rmod = -rmod;

    dlfo = 6.283f * iFs * cast(float)exp(6.22f * param(Param.lfoRate).getNormalized - 2.61f); //lfo rate

    auto velsensNormalized = param(Param.velocitySense).getNormalized;
    velsens = 2 * velsensNormalized + 1.0f;
    if(velsensNormalized < 0.25f) velsens -= 0.75f - 3.0f * velsensNormalized;

    width = 0.03f * param(Param.stereoWidth).getNormalized;
    poly = 1 + cast(int)(31.9f * param(Param.polyphony).getNormalized);
    fine = param(Param.fineTuning).getNormalized - 0.5f;
    auto randomNormalized = param(Param.randomTuning).getNormalized;
    random = 0.077f * randomNormalized * randomNormalized;
    stretch = 0.0f; //0.000434f * (param[11] - 0.5f); parameter re-used for overdrive!
    overdrive = 1.8f * param(Param.overdrive).getNormalized;

    release = param(Param.envelopeRelease).getNormalized;
    decay = param(Param.envelopeDecay).getNormalized;
    modulation = param(Param.modulation).getNormalized;
  }

  float Fs, iFs;

  enum EVENTBUFFER = 120;
  enum EVENTS_DONE = 99999999;
  //list of delta|note|velocity for current block
  int[EVENTBUFFER + 8] notes = [EVENTS_DONE];

  // Global internal variables
  KeyGroup[34] kgrp;
  Vec!short waves;

  enum SILENCE = 0.0001f;
  enum SUSTAIN = 128;
  enum NVOICES = 32;
  Voice[NVOICES] voice;

  int  activevoices = 0, poly = 16;
  float width = 0;
  int  size, sustain = 0;
  float lfo0 = 0, lfo1 = 1, dlfo = 0, lmod = 0, rmod = 0;
  float treb = 0, tfrq = 0.5, tl = 0, tr = 0;
  float tune = 0, fine = 0, random = 0, stretch = 0, overdrive = 0;
  float muff = 160, muffvel = 0, sizevel, velsens = 1, volume = 0.2, modwhl = 0;
  float modulation = 0, decay = 0, release = 0;
}

unittest {
  benchmarkWithDefaultParams!Epiano2Client;
}
