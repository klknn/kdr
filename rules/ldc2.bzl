"""LDC2 rules for Bazel."""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

def ldc2_sha256dict(s):
    d = {}
    for line in s.strip().splitlines():
        v, k = line.split("  ")
        d[k] = v
    return d

# https://github.com/ldc-developers/ldc/releases/download/v1.28.0/ldc2-1.28.0.sha256sums.txt
_LDC2_SHA256SUMS = ldc2_sha256dict("""
17fee8bb535bcb8cda0a45947526555c46c045f302a7349cc8711b254e54cf09  ldc-1.28.0-src.tar.gz
f59936c1c816698ab790b13b4a8cd0b2954bc5f43a38e4dd7ffaa29e28c2f3a6  ldc-1.28.0-src.zip
52666ebeaeddee402c022cbcdc39b8c27045e6faab15e53c72564b9eaf32ccff  ldc2-1.28.0-android-aarch64.tar.xz
c9b22ea84ed5738afcdf1740f501eea68a3269bda7e1a9eb1f139f9c4e5b96de  ldc2-1.28.0-android-armv7a.tar.xz
9786c36c4dfd29dd308a50c499c115e4c2079baeaded07e5ac5396c4a7fd0278  ldc2-1.28.0-linux-x86_64.tar.xz
f9786b8c28d8af1fdd331d8eb889add80285dbebfb97ea47d5dd9110a7df074b  ldc2-1.28.0-osx-arm64.tar.xz
02472507de988c8b5dd83b189c6df3b474741546589496c2ff3d673f26b8d09a  ldc2-1.28.0-osx-x86_64.tar.xz
8917876e2dbe763feec2d2d2ba81f20bfd32ed13753e5ea1bc5ce0ea564f3eaf  ldc2-1.28.0-windows-multilib.7z
e6ce44b6533fc4b7639b6ed078bdb107294fefc7b638141c42bf37b46e491990  ldc2-1.28.0-windows-multilib.exe
26bb3ece7774ef70d9c7485eab5fbc182d4e74411e4a8d2f339e9b421a76f069  ldc2-1.28.0-windows-x64.7z
af5465b316dfb582ded4fd6f83dfa02dfdd896fad6d397cc53d098e3ba9f9281  ldc2-1.28.0-windows-x86.7z
""")

_LDC2_BUILD_FILE = """
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
    name = "ldc2",
    srcs = ["bin/ldc2"],
)

filegroup(
    name = "libphobos2",
    srcs = select({
        ":darwin": ["lib/libphobos2-ldc.a", "lib/libphobos2-ldc-shared.dylib"],
        ":k8": ["lib/libphobos2-ldc.a", "lib/libphobos2-ldc-shared.so"],
        ":x64_windows": ["lib/phobos2-ldc.lib"],
    }),
)

filegroup(
    name = "phobos-src",
    srcs = glob([
        "import/std/*.*",
        "import/std/**/*.*",
    ]),
)

filegroup(
    name = "druntime-import-src",
    srcs = glob([
        "import/*.*",
        "import/core/*.*",
        "import/core/**/*.*",
        "import/etc/*.*",
        "import/etc/**/*.*",
        "import/ldc/*.*",
        "import/ldc/**/*.*",
    ]),
)
"""

def ldc2_archive(name, prefix, ext):
    archive = prefix + ext
    return http_archive(
        name = name,
        urls = ["https://github.com/ldc-developers/ldc/releases/download/v" +
                version + "/" + archive],
        sha256 = _LDC2_SHA256SUMS[archive],
        strip_prefix=prefix,
        build_file_content = _LDC2_BUILD_FILE,
    )

def ldc2_repositories(version="1.28.0"):
    # TODO(karita): Support non x86_64 arch
    ldc2_archive("ldc2_linux_x86_64", 'ldc2-' + version + "-linux-x86_64", ".tar.xz")
    ldc2_archive("ldc2_darwin_x86_64", 'ldc2-' + version + "-osx-x86_64", ".tar.xz")
    ldc2_archive("ldc2_windows_x86_64", 'ldc2-' + version + "-windows-x64", ".7z")

ldc2_compile_attrs = {
    "_ldc2_flag_version": attr.string(default = "--d-version"),
    "_ldc2_compiler": attr.label(
        default = Label("//rules:ldc2"),
        executable = True,
        allow_single_file = True,
        cfg = "host",
    ),
    "_ldc2_runtime_import_src": attr.label(
        default = Label("//rules:druntime-import-src-ldc2"),
    ),
    "_ldc2_stdlib": attr.label(
        default = Label("//rules:libphobos2-ldc2"),
    ),
    "_ldc2_stdlib_src": attr.label(
        default = Label("//rules:phobos-src-ldc2"),
    ),
}
