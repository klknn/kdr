package(default_visibility = ["//:__subpackages__"])

load("//rules:d.bzl", "d_library", "d_test", "d_library_with_test")

d_library_with_test(
    name = "params",
    srcs = ["params.d"],
    imports = ["//source"],
    deps = [
        "//source/kdr:delay",
        "//source/kdr:effect",
        "//source/kdr:waveform",
        "//source/kdr:filter",
        "//source/kdr:lfo",
        "//source/kdr:params",
        "@Dplug//:core",
        "@Dplug//:client",
        "@mir-core//:math",
    ],
)

d_library(
    name = "gui",
    srcs = ["gui.d"],
    imports = ["//source"],
    string_imports = [
        "//resource:ttf",
        "//resource:png",
    ],
    deps = [
        ":params",
        "//source/kdr:lfo",
        "//source/kdr:params",
        "//source/kdr:delay",
        "//source/kdr:effect",
        "//source/kdr:filter",
        "@Dplug//:core",
        "@Dplug//:client",
        "@Dplug//:graphics",
        "@Dplug//:gui",
        "@Dplug//:flatwidgets",
        "@Dplug//:pbrwidgets",
        "@Dplug//:math",
    ],
)

d_library(
    name = "client",
    srcs = ["client.d"],
    imports = ["//source"],
    deps = [
        ":params",
        ":gui",
        "//source/kdr:chorus",
        "//source/kdr:delay",
        "//source/kdr:equalizer",
        "//source/kdr:effect",
        "//source/kdr:envelope",
        "//source/kdr:filter",
        "//source/kdr:modfilter",
        "//source/kdr:lfo",
        "//source/kdr:oscillator",
        "//source/kdr:params",
        "//source/kdr:waveform",
        "@Dplug//:core",
        "@Dplug//:client",
        "@mir-core//:math",
    ],
)

d_test(
    name = "client_test",
    srcs = ["client.d"],
    imports = ["//source"],
    deps = [
        ":params",
        "//source/kdr:chorus",
        "//source/kdr:delay",
        "//source/kdr:equalizer",
        "//source/kdr:effect",
        "//source/kdr:envelope",
        "//source/kdr:filter",
        "//source/kdr:modfilter",
        "//source/kdr:lfo",
        "//source/kdr:oscillator",
        "//source/kdr:params",
        "//source/kdr:waveform",
        "@Dplug//:core",
        "@Dplug//:client",
        "@mir-core//:math",
    ],
)
