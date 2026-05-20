load("@hedron_compile_commands//:refresh_compile_commands.bzl", "refresh_compile_commands")
load("@rules_cc//cc:defs.bzl", "cc_binary")

cc_binary(
    name = "demo",
    srcs = ["demo.cpp"],
    deps = [
        "@opencv//:core",
        "@opencv//:imgcodecs",
        "@opencv//:imgproc",
    ],
)

refresh_compile_commands(
    name = "refresh_compile_commands",
    targets = {
        "//...": "",
    },
)
