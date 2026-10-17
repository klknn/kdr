import dplug.client;
import kdr.synth2p1.client : Synth2p1Client;
import kdr.compat;

///
class Synth2p1ClientWithInfo : Synth2p1Client {
  override PluginInfo buildPluginInfo() {
    forceCompatLink();
    // Plugin info is parsed from plugin.json here at compile time.
    static immutable info = parsePluginInfo(import("plugin.json"));
    return info;
  }
}

mixin(pluginEntryPoints!Synth2p1ClientWithInfo);
