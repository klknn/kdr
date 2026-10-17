module kdr.synth2p1.client;

import dplug.client.graphics : IGraphics;
import dplug.core.nogc : mallocNew;
import kdr.synth2.client : Synth2Client;
version (unittest) {} else import kdr.synth2.gui2 : Synth2GUI2;

/// Synth2 with modern page-based UI (v2.1).
class Synth2p1Client : Synth2Client {
 public:
  nothrow @nogc:

  this() {
    super();
  }

  version (unittest) {} else {
    override IGraphics createGraphics() {
      _gui2 = mallocNew!Synth2GUI2(this.params);
      return _gui2;
    }

    override void updateGuiTempo(double tempo) {
      if (_gui2) {
        _gui2.setTempo(tempo);
      }
    }

   private:
    Synth2GUI2 _gui2;
  }
}

unittest {
  import kdr.testing : benchmarkWithDefaultParams;
  benchmarkWithDefaultParams!Synth2p1Client();
}
