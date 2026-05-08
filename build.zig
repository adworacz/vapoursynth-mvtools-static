const std = @import("std");
const version = @import("build.zig.zon").dependencies.@"vapoursynth-mvtools".version;

const flags: []const []const u8 = &.{
    "-fvisibility=hidden",
};

pub fn build(b: *std.Build) void {
    const upstream = b.dependency("vapoursynth-mvtools", .{});
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const is_windows = target.result.os.tag == .windows;
    const is_mac = target.result.os.tag == .macos;
    const is_linux = target.result.os.tag == .linux;
    const is_x86 = target.result.cpu.arch == .x86_64;
    const is_aarch64 = target.result.cpu.arch == .aarch64;

    const strip = b.option(bool, "strip", "Enable debug symbol stripping (default true if ReleaseFast else false)") orelse
        (optimize == .ReleaseFast);
    const pic = b.option(bool, "pic", "Enable PIC (position independent code) (default true)") orelse true;

    const fftw = b.dependency("fftw", .{
        .target = target,
        .optimize = optimize,
        .precision = .single,
        .threads = true,
    });

    const nasm = b.dependency("nasm", .{
        .optimize = .ReleaseFast,
    });
    const nasm_exe = nasm.artifact("nasm");

    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
        .strip = strip,
        .pic = pic,
    });

    mod.linkLibrary(fftw.artifact("fftw3f"));

    mod.addCMacro("PACKAGE_VERSION", b.fmt("\"{s}\"", .{version}));

    const vs_include_path = b.run(&.{ "python", "-c", "import vapoursynth as vs; print(vs.get_include(), end='')" });
    mod.addIncludePath(.{ .cwd_relative = vs_include_path });
    mod.addIncludePath(upstream.path("src"));

    mod.addCSourceFiles(.{
        .root = upstream.path("src"),
        .files = &generic_sources,
        .flags = flags,
    });

    // build SIMD + assembly

    if (is_aarch64) {
        mod.addCMacro("MVTOOLS_ARM", "1");
        if (is_mac) {
            mod.addCMacro("PREFIX", "1");
        }
        mod.addCSourceFiles(.{
            .root = upstream.path("src"),
            .files = aarch64_sources,
            .flags = flags,
        });
    }

    if (is_x86) {
        mod.addCMacro("MVTOOLS_X86", "1");
        // AVX2 optimized functions
        const avx2_mod = b.addModule("avx2", .{
            // Force the compiler to target haswell when compiling the AVX2 code
            .target = b.resolveTargetQuery(.{
                .os_tag = target.result.os.tag,
                .cpu_arch = target.result.cpu.arch,
                .abi = target.result.abi,
                .cpu_model = .{ .explicit = &std.Target.x86.cpu.haswell },
            }),
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
            .pic = pic,
            .strip = strip,
        });
        avx2_mod.addCMacro("MVTOOLS_X86", "1");
        avx2_mod.addIncludePath(.{ .cwd_relative = vs_include_path });
        avx2_mod.addIncludePath(upstream.path("src"));
        avx2_mod.addCSourceFiles(.{
            .root = upstream.path("src"),
            .files = avx2_sources,
            .flags = flags,
        });
        mod.linkLibrary(b.addLibrary(.{
            .name = "avx2",
            .linkage = .static,
            .root_module = avx2_mod,
        }));

        for (x86_sources) |a| {
            const nasm_run = b.addRunArtifact(nasm_exe);
            nasm_run.addArgs(&.{
                "-w",                                                         "-Worphan-labels",    "-Wunrecognized-char",
                "-Dprivate_prefix=mvtools",                                   "-DHIGH_BIT_DEPTH=0", "-DBIT_DEPTH=8",
                b.fmt("-DARCH_X86_64={d}", .{@as(u8, if (is_x86) 1 else 0)}),
            });

            if (pic) {
                nasm_run.addArg("-DPIC");
            }

            if (is_windows) {
                // nasm_run.addArgs(&.{ "-f", "win64", "-DPREFIX" });
                nasm_run.addArgs(&.{ "-f", "win64" });
            }
            if (is_linux) {
                nasm_run.addArgs(&.{ "-f", "elf64" });
            }
            if (is_mac) {
                nasm_run.addArgs(&.{ "-f", "macho64", "-DPREFIX" });
                // nasm_run.addArgs(&.{ "-f", "macho64", });
            }

            if (!strip) {
                nasm_run.addArg("-g");
            }

            // Nasm requires '/' at the end of its includes
            nasm_run.addDecoratedDirectoryArg("-I", upstream.path("src/asm/include"), "/");

            nasm_run.addFileArg(upstream.path("src").path(b, a));

            nasm_run.addArg("-o");
            const ext = if (is_windows) ".obj" else ".o";
            mod.addObjectFile(nasm_run.addOutputFileArg(b.fmt("{s}{s}", .{ std.fs.path.stem(a), ext })));
        }
    }

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

const avx2_sources = &.{
    "MaskFun_AVX2.cpp",
    "MVDegrains_AVX2.cpp",
    "MVFrame_AVX2.cpp",
    "Overlap_AVX2.cpp",
    "SADFunctions_AVX2.cpp",
    "SimpleResize_AVX2.cpp",
};

const aarch64_sources = &.{
    "asm/aarch64-pixel-a.S",
};

const x86_sources: []const []const u8 = &.{
    "asm/const-a.asm",
    "asm/cpu-a.asm",
    "asm/pixel-a.asm",
    "asm/sad-a.asm",
};
