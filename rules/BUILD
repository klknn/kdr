"""Bazel rules.

Flags:

  To switch D compiler, set: --//rules:d_compiler=ldc2 (default: dmd)
"""
package(default_visibility = ["//visibility:public"])
load(":d_toolchain.bzl", "d_compiler")

d_compiler(name = "d_compiler", build_setting_default = "dmd")

filegroup(
    name = "srcs",
    srcs = glob(["**"]),
)

config_setting(
    name = "darwin",
    values = {"host_cpu": "darwin"},
)

config_setting(
    name = "k8",
    values = {"host_cpu": "k8"},
)

config_setting(
    name = "x64_windows",
    values = {"host_cpu": "x64_windows"},
)

filegroup(
    name = "dmd",
    srcs = select({
        ":darwin": ["@dmd_darwin_x86_64//:dmd"],
        ":k8": ["@dmd_linux_x86_64//:dmd"],
        ":x64_windows": ["@dmd_windows_x86_64//:dmd"],
    }),
)

filegroup(
    name = "libphobos2",
    srcs = select({
        ":darwin": ["@dmd_darwin_x86_64//:libphobos2"],
        ":k8": ["@dmd_linux_x86_64//:libphobos2"],
        ":x64_windows": ["@dmd_windows_x86_64//:libphobos2"],
    }),
)

filegroup(
    name = "phobos-src",
    srcs = select({
        ":darwin": ["@dmd_darwin_x86_64//:phobos-src"],
        ":k8": ["@dmd_linux_x86_64//:phobos-src"],
        ":x64_windows": ["@dmd_windows_x86_64//:phobos-src"],
    }),
)

filegroup(
    name = "druntime-import-src",
    srcs = select({
        ":darwin": ["@dmd_darwin_x86_64//:druntime-import-src"],
        ":k8": ["@dmd_linux_x86_64//:druntime-import-src"],
        ":x64_windows": ["@dmd_windows_x86_64//:druntime-import-src"],
    }),
)

filegroup(
    name = "ldc2",
    srcs = select({
        ":darwin": ["@ldc2_darwin_x86_64//:ldc2"],
        ":k8": ["@ldc2_linux_x86_64//:ldc2"],
        # ":x64_windows": ["@ldc2_windows_x86_64//:ldc2"],
    }),
)

filegroup(
    name = "libphobos2-ldc2",
    srcs = select({
        ":darwin": ["@ldc2_darwin_x86_64//:libphobos2"],
        ":k8": ["@ldc2_linux_x86_64//:libphobos2"],
        # ":x64_windows": ["@ldc2_windows_x86_64//:libphobos2"],
    }),
)

filegroup(
    name = "phobos-src-ldc2",
    srcs = select({
        ":darwin": ["@ldc2_darwin_x86_64//:phobos-src"],
        ":k8": ["@ldc2_linux_x86_64//:phobos-src"],
        # ":x64_windows": ["@ldc2_windows_x86_64//:phobos-src"],
    }),
)

filegroup(
    name = "druntime-import-src-ldc2",
    srcs = select({
        ":darwin": ["@ldc2_darwin_x86_64//:druntime-import-src"],
        ":k8": ["@ldc2_linux_x86_64//:druntime-import-src"],
        # ":x64_windows": ["@ldc2_windows_x86_64//:druntime-import-src"],
    }),
)
