const std = @import("std");

pub fn build(b: *std.Build) void {
    const target_option = b.option(
        []const u8,
        "target-board",
        "Target board: rp2350 (default) or qemu",
    ) orelse "rp2350";

    const is_qemu = std.mem.eql(u8, target_option, "qemu");

    const target = b.resolveTargetQuery(.{
        .cpu_arch = .riscv32,
        .cpu_model = .{ .explicit = &std.Target.riscv.cpu.baseline_rv32 },
        .os_tag = .freestanding,
        .abi = .none,
    });

    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = if (is_qemu) "kolos-kernel-qemu" else "kolos-kernel",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .single_threaded = true,
        }),
    });
    
    // Add assembly entry point
    exe.root_module.addAssemblyFile(b.path("src/boot/start.S"));
    
    // Disable stack protector for freestanding
    exe.root_module.stack_protector = false;
    
    // Use appropriate linker script
    if (is_qemu) {
        exe.setLinkerScript(b.path("src/boot/linker-qemu.ld"));
    } else {
        exe.setLinkerScript(b.path("src/boot/linker.ld"));
    }

    // Add build option to pass to code
    const options = b.addOptions();
    options.addOption(bool, "is_qemu", is_qemu);
    exe.root_module.addOptions("build_options", options);

    b.installArtifact(exe);
    
    // Generate bin file
    const bin = b.addObjCopy(exe.getEmittedBin(), .{
        .format = .bin,
    });
    
    const bin_name = if (is_qemu) "kolos-kernel-qemu.bin" else "kolos-kernel.bin";
    const install_bin = b.addInstallBinFile(bin.getOutput(), bin_name);
    b.getInstallStep().dependOn(&install_bin.step);
    
    // Generate hex file (only for RP2350)
    if (!is_qemu) {
        const hex = b.addObjCopy(exe.getEmittedBin(), .{
            .format = .hex,
        });
        
        const install_hex = b.addInstallBinFile(hex.getOutput(), "kolos-kernel.hex");
        b.getInstallStep().dependOn(&install_hex.step);
    }

    // Add QEMU run step
    if (is_qemu) {
        const run_qemu = b.addSystemCommand(&[_][]const u8{
            "qemu-system-riscv32",
            "-machine",
            "virt",
            "-m",
            "128M",
            "-bios",
            "none",
            "-kernel",
        });
        run_qemu.addFileArg(exe.getEmittedBin());
        run_qemu.addArgs(&[_][]const u8{
            "-nographic",
            "-serial",
            "mon:stdio",
        });
        run_qemu.step.dependOn(b.getInstallStep());

        const run_step = b.step("run", "Run the kernel in QEMU");
        run_step.dependOn(&run_qemu.step);
    }
}
