const std = @import("std");
const version = @import("build.zig.zon").dependencies.@"vapoursynth-mvtools".version;

const flags = .{
    "-fvisibility=hidden",
};

pub fn build(b: *std.Build) void {
    const upstream = b.dependency("vapoursynth-mvtools", .{});
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // const is_windows = target.result.os.tag == .windows;
    // const is_mac = target.result.os.tag == .macos;
    const is_x86 = target.result.cpu.arch == .x86_64;
    const is_aarch64 = target.result.cpu.arch == .aarch64;

    const strip = b.option(bool, "strip", "Enable debug symbol stripping (default true if ReleaseFast else false)") orelse
        (optimize == .ReleaseFast);
    const pic = b.option(bool, "pic", "Enable PIC (position independent code) (default true)") orelse true;

    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .strip = strip,
        .pic = pic,
    });

    mod.addCMacro("PACKAGE_VERSION", version);

    if(is_x86) {
        mod.addCMacro("MVTOOLS_X86", "1");
    }
    if (is_aarch64) {
        mod.addCMacro("MVTOOLS_ARM", "1");
    }

    const vs_include_path = b.run(&.{"python", "-c", "import vapoursynth as vs; print(vs.get_include())"});
    
    // Add VS Headers
    const path: std.Build.LazyPath = .{ .cwd_relative = vs_include_path };
    mod.addIncludePath(path);
    mod.addIncludePath(upstream.path("src"));

    mod.addCSourceFiles(.{
        .root = upstream.path("src"),
        .files = &generic_sources,
        .flags = &flags,
    });

    const lib = b.addLibrary(.{
        .name = "mvtools",
        .root_module = mod,
        .linkage = .dynamic,
    });

    b.installArtifact(lib);
}

const generic_sources = .{
    "CopyCode.cpp",
    "CPU.c",
    "DCTFFTW.cpp",
    "EntryPoint.c",
    "Fakery.c",
    "GroupOfPlanes.c",
    "Luma.cpp",
    "MaskFun.cpp",
    "MVAnalyse.c",
    "MVAnalysisData.c",
    "MVBlockFPS.c",
    "MVCompensate.c",
    "MVDegrains.cpp",
    "MVDepan.cpp",
    "MVFinest.c",
    "MVFlow.cpp",
    "MVFlowBlur.c",
    "MVFlowFPS.c",
    "MVFlowFPSHelper.c",
    "MVFlowInter.c",
    "MVFrame.cpp",
    "MVMask.c",
    "MVRecalculate.c",
    "MVSCDetection.c",
    "MVSuper.c",
    "Overlap.cpp",
    "PlaneOfBlocks.cpp",
    "SADFunctions.cpp",
    "SimpleResize.cpp",
};

const avx2_sources = .{
    "MaskFun_AVX2.cpp",
    "MVDegrains_AVX2.cpp",
    "MVFrame_AVX2.cpp",
    "Overlap_AVX2.cpp",
    "SADFunctions_AVX2.cpp",
    "SimpleResize_AVX2.cpp",
};

const arm_sources = .{
    "asm/aarch64-pixel-a.S",
};
