import dplug.client;

import kdr.rezonizer.client : RezonizerClient;

class ClientWithInfo : RezonizerClient {
  override PluginInfo buildPluginInfo() {
    static immutable info = parsePluginInfo(import("plugin.json"));
    return info;
  }
}

mixin(pluginEntryPoints!ClientWithInfo);
