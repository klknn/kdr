load("//rules:d.bzl", "d_library", "d_test", "d_library_with_test")

filegroup(
    name = "json",
    srcs = ["plugin.json"],
)

d_library(
    name = "synth2",
    srcs = ["main.d"],
    string_imports = [":json"],
    versions = ["VST3"],
    linkstatic = False,
    deps = [
        "//source/kdr/synth2:client",
        "@Dplug//:client",
        "@Dplug//:vst3",
    ],
)
