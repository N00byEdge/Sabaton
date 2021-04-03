const sabaton = @import("root").sabaton;
const std = @import("std");

var smp_tag: ?[]u8 = null;

comptime {
    asm(
        \\ .section .text.smp_stub
        \\ .global smp_stub
        \\smp_stub:
        \\  B .
        \\  LDR X1, [X0, #8] // Load stack
        \\  MOV SP, X1
        \\  // Fall through to smp_entry
    );
}

extern fn smp_stub(context: u64) callconv(.C) noreturn;

export fn smp_entry(context: u64) linksection(".text.smp_entry") noreturn {
    @call(.{.modifier = .always_inline}, sabaton.stivale2_smp_ready, .{context});
}

pub fn init() void {
    if(smp_tag) |tag| {
        var ap: usize = 1;
        const num_cpus = (tag.len - 40)/32;

        while(ap < num_cpus) : (ap += 1) {
            const tag32 = @intToPtr([*]u32, @ptrToInt(tag.ptr) + 40 + 32 * ap);
            const id = tag32[0];
            _ = sabaton.psci.wake_cpu(@ptrToInt(smp_stub), id, @ptrToInt(tag32), .HVC);
        }
    }
}

// // This could be moved into lib some day if anything else needs it
// fn write_int_reverse(buf: []u8, val_c: u32) usize {
//     var i: usize = 0;
//     var val = val_c;

//     while(true) : (i += 1) {
//         buf[i] = @intCast(u8, val % 10) + '0';
//         val /= 10;

//         if(val == 0)
//           return i + 1;
//     }
// }

// // This too
// fn fmt_int(buf: []u8, val: u32) usize {
//     const result = write_int_reverse(buf, val);
//     std.mem.reverse(u8, buf[0..result]);
//     return result;
// }

// fn get_cpu_reg(cpuid: u32) ?u32 {
//     var buf: [32]u8 = undefined;
//     buf[0] = 'c';
//     buf[1] = 'p';
//     buf[2] = 'u';
//     buf[3] = '@';
//     const int_bytes = fmt_int(buf[4..], cpuid);
//     const reg_bytes = sabaton.dtb.find(buf[0..4+int_bytes], "reg") catch return null;
//     return std.mem.readIntBig(u32, reg_bytes[0..][0..4]);
// }

// No need for the dynamic version as virt only supports up to 8 cpus (?)
fn get_cpu_reg(cpuid: u32) ?u32 {
    var buf: [5]u8 = undefined;
    buf[0] = 'c';
    buf[1] = 'p';
    buf[2] = 'u';
    buf[3] = '@';
    buf[4] = '0' + @intCast(u8, cpuid);
    const reg_bytes = sabaton.dtb.find(buf[0..], "reg") catch return null;
    return std.mem.readIntBig(u32, reg_bytes[0..][0..4]);
}

pub fn prepare() void {
    var num_aps: u32 = 0;

    while(get_cpu_reg(num_aps + 1)) |_| {
        num_aps += 1;
    }

    sabaton.log_hex("Number of CPUs discovered: ", num_aps);

    // We don't need to do anything.
    if(num_aps == 0) return;

    smp_tag = sabaton.pmm.alloc_aligned(40 + 32 * (num_aps + 1), .ReclaimableData);
    sabaton.add_tag(@intToPtr(*sabaton.Stivale2tag, @ptrToInt(smp_tag.?.ptr)));

    var curr_ap: u32 = 0;
    while(curr_ap < num_aps) : (curr_ap += 1) {
        const data = @intToPtr([*]u64, @ptrToInt(smp_tag.?.ptr) + 40 + 32 * curr_ap);
        // A page each
        const psz = sabaton.platform.get_page_size();
        data[1] = @ptrToInt(sabaton.pmm.alloc_aligned(psz, .ReclaimableData).ptr) + psz;
    }
}
