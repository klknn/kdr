package(default_visibility = ["//:__subpackages__"])

load("//rules:d.bzl", "d_library", "d_test", "d_library_with_test")

d_library_with_test(
    name = "filter",
    srcs = ["filter.d"],
    string_imports = ["//resource:filter_coeff"],
    imports = [".."],
    deps = [
        "@mir-core//:math"
    ],
)

d_library_with_test(
    name = "random",
    srcs = ["random.d"],
    imports = [".."],
)

d_library_with_test(
    name = "waveform",
    srcs = ["waveform.d"],
    imports = [".."],
    deps = [
        ":random",
        "@mir-core//:math"
    ],
)

d_library_with_test(
    name = "ringbuffer",
    srcs = ["ringbuffer.d"],
    imports = [".."],
)

d_library_with_test(
    name = "delay",
    srcs = ["delay.d"],
    imports = [".."],
    deps = [":ringbuffer"],
)

d_library_with_test(
    name = "effect",
    srcs = ["effect.d"],
    imports = [".."],
    deps = [
        ":filter",
        ":waveform",
        "@Dplug//:core",
        "@mir-core//:math",
    ],
)

d_library_with_test(
    name = "lfo",
    srcs = ["lfo.d"],
    imports = [".."],
    deps = [
        ":waveform",
        "@Dplug//:core",
        "@Dplug//:client",
    ],
)

d_library_with_test(
    name = "envelope",
    srcs = ["envelope.d"],
    imports = [".."],
    deps = [
        "@Dplug//:client",
        "@mir-core//:math",
    ],
)

d_library_with_test(
    name = "equalizer",
    srcs = ["equalizer.d"],
    imports = [".."],
    deps = [
        ":filter",
        "@mir-core//:math",
    ],
)

d_library_with_test(
    name = "modfilter",
    srcs = ["modfilter.d"],
    imports = [".."],
    deps = [
        ":envelope",
        ":filter",
        "@Dplug//:client",
        "@mir-core//:math",
    ],
)

d_library_with_test(
    name = "voice",
    srcs = ["voice.d"],
    imports = [".."],
    deps = [
        ":envelope",
        "@mir-core//:math",
    ],
)

d_library_with_test(
    name = "oscillator",
    srcs = ["oscillator.d"],
    imports = [".."],
    deps = [
        ":waveform",
        ":voice",
        "@Dplug//:client",
        "@mir-core//:math",
    ],
)

d_library_with_test(
    name = "params",
    srcs = ["params.d"],
    imports = [".."],
    deps = [
        "@Dplug//:client",
        "@Dplug//:core",
    ],
)

d_library(
    name = "chorus",
    srcs = ["chorus.d"],
    imports = [".."],
    deps = [
        ":delay",
        ":lfo",
        ":waveform",
    ],
)
