import dplug.client;
import dplug.vst3;

import kdr.epiano2.client : Epiano2Client;

class ClientWithInfo : Epiano2Client {
  override PluginInfo buildPluginInfo() {
    static immutable info = parsePluginInfo(import("plugin.json"));
    return info;
  }
}

mixin(pluginEntryPoints!ClientWithInfo);
