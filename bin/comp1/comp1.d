import dplug.core;
import dplug.client;

import kdr.comp1.client;

///
class ClientWithInfo : Comp1Client {
  override PluginInfo buildPluginInfo() {
    static immutable info = parsePluginInfo(import("plugin.json"));
    return info;
  }
}

mixin(pluginEntryPoints!ClientWithInfo);
