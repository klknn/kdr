import dplug.client;
import kdr.synth2.client : Synth2Client;

///
class Synth2ClientWithInfo : Synth2Client {
  override PluginInfo buildPluginInfo() {
    // Plugin info is parsed from plugin.json here at compile time.
    static immutable info = parsePluginInfo(import("plugin.json"));
    return info;
  }
}


mixin(pluginEntryPoints!Synth2Client);
