package(default_visibility = ["//visibility:public"])

load("//rules:d.bzl", "d_library", "d_test")

d_library(
    name = "random",
    srcs = ["random.d"],
)

d_test(
    name = "random_test",
    srcs = ["random.d"],
    deps = [":random"],
)
