load("@build_bazel_rules_apple//apple:ios.bzl", "ios_unit_test")
load("@build_bazel_rules_apple//apple/testing/default_runner:ios_test_runner.bzl", "ios_test_runner")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "SGPrivacyTools",
    module_name = "SGPrivacyTools",
    srcs = glob(["Sources/**/*.swift"]),
    copts = ["-warnings-as-errors"],
    visibility = ["//visibility:public"],
)

swift_library(
    name = "SGPrivacyToolsTestsLib",
    testonly = True,
    srcs = glob(["Tests/**/*.swift"]),
    deps = [":SGPrivacyTools"],
)

ios_test_runner(
    name = "SGPrivacyToolsTestRunner",
    device_type = "iPhone 17",
    os_version = "26.5",
)

ios_unit_test(
    name = "SGPrivacyToolsTests",
    minimum_os_version = "13.0",
    runner = ":SGPrivacyToolsTestRunner",
    deps = [":SGPrivacyToolsTestsLib"],
    visibility = ["//visibility:public"],
)
