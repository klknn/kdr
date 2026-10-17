import dplug.client;

import kdr.khrm.client : KhrmClient;

class ClientWithInfo : KhrmClient {
  override PluginInfo buildPluginInfo() {
    static immutable info = parsePluginInfo(import("plugin.json"));
    return info;
  }
}

mixin(pluginEntryPoints!ClientWithInfo);
