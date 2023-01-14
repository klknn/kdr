import dplug.core;
import dplug.client;

class ClientWithInfo : dplug.client.Client {
  override PluginInfo buildPluginInfo() {
    static immutable info = parsePluginInfo(import("plugin.json"));
    return info;
  }
}

mixin(pluginEntryPoints!ClientWithInfo);
