import dplug.client;

import kdr.compat : forceCompatLink;
import kdr.stutter.client : StutterClient;

/// Entry point client subclassing StutterClient with compile-time plugin info.
class StutterClientWithInfo : StutterClient {
  override PluginInfo buildPluginInfo() {
    forceCompatLink();
    // Plugin info is parsed from plugin.json at compile time.
    static immutable info = parsePluginInfo(import("plugin.json"));
    return info;
  }
}

mixin(pluginEntryPoints!StutterClientWithInfo);
