import dplug.client;
import kdr.hibiki.client : HibikiClient;

///
class HibikiClientWithInfo : HibikiClient {
  override PluginInfo buildPluginInfo() {
    // Plugin info is parsed from plugin.json here at compile time.
    static immutable info = parsePluginInfo(import("plugin.json"));
    return info;
  }
}


mixin(pluginEntryPoints!HibikiClientWithInfo);
