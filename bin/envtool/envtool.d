import dplug.client;

import kdr.envtool.client : EnvToolClient;
import kdr.compat;


///
class ClientWithInfo : EnvToolClient {
  override PluginInfo buildPluginInfo() {
    forceCompatLink();
    // Plugin info is parsed from plugin.json here at compile time.
    static immutable info = parsePluginInfo(import("plugin.json"));
    return info;
  }
}


mixin(pluginEntryPoints!ClientWithInfo);
