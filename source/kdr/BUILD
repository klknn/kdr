package(default_visibility = ["//visibility:public"])

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

# d_library_with_test(
#     name = "effect",
#     srcs = ["effect.d"],
#     imports = [".."],
#     deps = [
#         ":filter",
#         ":waveform",
#         # TODO(klknn): Setup this indirect deps in //rules/d.bzl.
#         "@intel-intrinsics//:intel-intrinsics",
#         "@Dplug//:core",
#         "@mir-core//:math",
#     ],
# )

# d_library_with_test(
#     name = "lfo",
#     srcs = ["lfo.d"],
#     imports = [".."],
#     deps = [
#         ":waveform",
#         "@Dplug//:core",
#         "@Dplug//:client",
#     ],
# )
