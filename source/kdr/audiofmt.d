/// Audio formats.
module kdr.audiofmt;

/// http://soundfile.sapp.org/doc/WaveFormat/
struct Wav {
  @nogc nothrow:

  struct Header {
    char[4] riffId;
    int chunkSize;
    char[4] waveId;
    char[4] fmtId;
    int fmtSize;
    short fmtCode;
    short numChannels;
    int sampleRate;
    int bytePerSecond;
    short blockBoundary;
    short bitPerSample;
    char[4] dataId;
    int fileSize;
  }

  const(Header)* header;
  const(void)* ptr;

  alias header this;

  this(const(void)[] bytes) {
    this.header = cast(const(Header)*) bytes.ptr;
    this.ptr = bytes.ptr + Header.sizeof;

    assert(riffId == "RIFF");
    assert(waveId == "WAVE");
    assert(fmtId == "fmt ");
    assert(dataId == "data");
  }

  const(T)[] data(T = short)() const {
    assert(T.sizeof * 8 == bitPerSample);
    auto p = cast(T*) this.ptr;
    return p[0 .. this.fileSize / (T.sizeof / byte.sizeof)];
  }
}

unittest {
  Wav wav = Wav(import("epiano.wav"));
  with (wav) {
    assert(fmtSize == 16);
    assert(fmtCode == 1);
    assert(numChannels == 1);
    assert(sampleRate == 44100);
    assert(bytePerSecond == sampleRate * blockBoundary);
    assert(blockBoundary == 2);
    assert(bitPerSample == 16);
    assert(data!short.length == 422418);
    assert(data!short[0] == -7);
    assert(data!short[$-1] == 0);
  }
}
