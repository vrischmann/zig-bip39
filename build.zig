const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const lib = b.addStaticLibrary("bip39-zig", "src/lib.zig");
    lib.setBuildMode(mode);

    var main_tests = b.addTest("src/lib.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    const example = b.addExecutable("example", "example/main.zig");
    example.setBuildMode(mode);
    example.addPackagePath("bip39", "src/lib.zig");
    example.install();

    const run_example_cmd = example.run();
    run_example_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_example_cmd.addArgs(args);
    }

    const run_example_step = b.step("run-example", "Run the example");
    run_example_step.dependOn(&run_example_cmd.step);
}
