import dplug.client;
import kdr.hott.client : HottClient;
import kdr.compat;

class ClientWithInfo : HottClient {
  override PluginInfo buildPluginInfo() {
    forceCompatLink();
    static immutable info = parsePluginInfo(import("plugin.json"));
    return info;
  }
}

mixin(pluginEntryPoints!ClientWithInfo);
