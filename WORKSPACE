load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("//rules:dmd.bzl", "dmd_repositories")
load("//rules:ldc2.bzl", "ldc2_repositories")

dmd_repositories()
ldc2_repositories()

new_local_repository(
    name = "mir-core",
    path = "third_party/mir-core",
    build_file = "third_party/BUILD.mir-core",
)

new_local_repository(
    name = "intel-intrinsics",
    path = "third_party/intel-intrinsics",
    build_file = "third_party/BUILD.intel-intrinsics",
)

new_local_repository(
    name = "Dplug",
    path = "third_party/Dplug",
    build_file = "third_party/BUILD.Dplug",
)
