"""DMD rules."""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

DMD_BUILD_FILE = """
package(default_visibility = ["//visibility:public"])

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
        ":darwin": ["dmd2/osx/bin/dmd"],
        ":k8": ["dmd2/linux/bin64/dmd"],
        ":x64_windows": ["dmd2/windows/bin64/dmd.exe"],
    }),
)

filegroup(
    name = "libphobos2",
    srcs = select({
        ":darwin": ["dmd2/osx/lib/libphobos2.a"],
        ":k8": [
            "dmd2/linux/lib64/libphobos2.a",
            "dmd2/linux/lib64/libphobos2.so",
        ],
        ":x64_windows": ["dmd2/windows/lib64/phobos64.lib"],
    }),
)

filegroup(
    name = "phobos-src",
    srcs = glob(["dmd2/src/phobos/**/*.*"]),
)

filegroup(
    name = "druntime-import-src",
    srcs = glob([
        "dmd2/src/druntime/import/*.*",
        "dmd2/src/druntime/import/**/*.*",
    ]),
)
"""

def dmd_repositories():
    http_archive(
        name = "dmd_linux_x86_64",
        urls = [
            "http://downloads.dlang.org/releases/2021/dmd.2.097.1.linux.tar.xz",
        ],
        sha256 = "030fd1bc3b7308dadcf08edc1529d4a2e46496d97ee92ed532b246a0f55745e6",
        build_file_content = DMD_BUILD_FILE,
    )

    http_archive(
        name = "dmd_darwin_x86_64",
        urls = [
            "http://downloads.dlang.org/releases/2021/dmd.2.097.1.osx.tar.xz",
        ],
        sha256 = "383a5524266417bcdd3126da947be7caebd4730f789021e9ec26d869c8448f6a",
        build_file_content = DMD_BUILD_FILE,
    )

    http_archive(
        name = "dmd_windows_x86_64",
        urls = [
            "http://downloads.dlang.org/releases/2021/dmd.2.097.1.windows.zip",
        ],
        sha256 = "63a00e624bf23ab676c543890a93b5325d6ef6b336dee2a2f739f2bbcef7ef1f",
        build_file_content = DMD_BUILD_FILE,
    )

dmd_compile_attrs = {
    "_dmd_flag_version": attr.string(default = "-version"),
    "_dmd_compiler": attr.label(
        default = Label("//rules:dmd"),
        executable = True,
        allow_single_file = True,
        cfg = "host",
    ),
    "_dmd_runtime_import_src": attr.label(
        default = Label("//rules:druntime-import-src"),
    ),
    "_dmd_stdlib": attr.label(
        default = Label("//rules:libphobos2"),
    ),
    "_dmd_stdlib_src": attr.label(
        default = Label("//rules:phobos-src"),
    ),
}
