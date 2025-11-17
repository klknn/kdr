import dplug.client;
import kdr.fm6.client;

///
class Fm6ClientWithInfo : Fm6Client {
  override PluginInfo buildPluginInfo() {
    // Plugin info is parsed from plugin.json here at compile time.
    static immutable info = parsePluginInfo(import("plugin.json"));
    return info;
  }
}

mixin(pluginEntryPoints!Fm6ClientWithInfo);
