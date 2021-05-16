pub const platform = @import("root");
pub const io_impl = @import("io/io.zig");
pub const util = @import("lib/util.zig");
pub const dtb = @import("lib/dtb.zig");
pub const pmm = @import("lib/pmm.zig");
pub const stivale = @import("lib/stivale.zig");

pub const acpi = @import("platform/acpi.zig");
pub const paging = @import("platform/paging.zig");
pub const pci = @import("platform/pci.zig");
pub const psci = @import("platform/psci.zig");
pub const fw_cfg = @import("platform/drivers/fw_cfg.zig");
pub const ramfb = @import("platform/drivers/ramfb.zig");

pub const puts = io_impl.puts;
pub const log_hex = io_impl.log_hex;
pub const print_hex = io_impl.print_hex;
pub const print_str = io_impl.print_str;
pub const log = io_impl.log;
pub const putchar = io_impl.putchar;
pub const near = util.near;
pub const vital = util.vital;
pub const io = platform.io;

pub const debug = @import("builtin").mode == .Debug;
pub const safety = std.debug.runtime_safety;

pub const upper_half_phys_base = 0xFFFF800000000000;

const std = @import("std");

pub fn panic(reason: []const u8, stacktrace: ?*std.builtin.StackTrace) noreturn {
  if(@hasDecl(platform, "panic_hook"))
    platform.panic_hook();
  puts("PANIC!");
  if(reason.len != 0) {
    puts(" Reason: ");
    print_str(reason);
  }

  if(sabaton.debug) {
    if(stacktrace) |t| {
      log("\nTrace:\n", .{});
      for(t.instruction_addresses) |addr| {
        log("  0x{X}\n", .{addr});
      }
    } else {
      log("\nNo trace.\n", .{});
    }
  }

  asm volatile(
    \\  // Disable interrupts
    \\  MSR DAIFSET, 0xF
    \\
    \\  // Hang
    \\1:WFI
    \\  B 1b
  );
  unreachable;
}

const Elf = @import("lib/elf.zig").Elf;
const sabaton = @This();

pub const Stivale2tag = packed struct {
  ident: u64,
  next: ?*@This(),
};

const InfoStruct = struct {
  brand: [64]u8 = pad_str("Sabaton - Forged in Valhalla by the hammer of Thor", 64),
  version: [64]u8 = pad_str(@import("build_options").board_name ++ " - " ++ @tagName(std.builtin.mode), 64),
  tags: ?*Stivale2tag = null,
};

pub const Stivale2hdr = struct {
  entry_point: u64,
  stack: u64,
  flags: u64,
  tags: ?*Stivale2tag,
};

fn pad_str(str: []const u8, comptime len: usize) [len]u8 {
  var ret = [1]u8{0} ** len;
  // Check that we fit the string and a null terminator
  if(str.len >= len) unreachable;
  @memcpy(@ptrCast([*]u8, &ret[0]), str.ptr, str.len);
  return ret;
}

var stivale2_info: InfoStruct = .{ };

pub fn add_tag(tag: *Stivale2tag) void {
  tag.next = stivale2_info.tags;
  stivale2_info.tags = tag;
}

var paging_root: paging.Root = undefined;

comptime {
  if(comptime sabaton.safety) {
    asm(
      \\.section .text
      \\.balign 0x800
      \\evt_base:
      \\.balign 0x80; B fatal_error // curr_el_sp0_sync
      \\.balign 0x80; B fatal_error // curr_el_sp0_irq
      \\.balign 0x80; B fatal_error // curr_el_sp0_fiq
      \\.balign 0x80; B fatal_error // curr_el_sp0_serror
      \\.balign 0x80; B fatal_error // curr_el_spx_sync
      \\.balign 0x80; B fatal_error // curr_el_spx_irq
      \\.balign 0x80; B fatal_error // curr_el_spx_fiq
      \\.balign 0x80; B fatal_error // curr_el_spx_serror
      \\.balign 0x80; B fatal_error // lower_el_aarch64_sync
      \\.balign 0x80; B fatal_error // lower_el_aarch64_irq
      \\.balign 0x80; B fatal_error // lower_el_aarch64_fiq
      \\.balign 0x80; B fatal_error // lower_el_aarch64_serror
      \\.balign 0x80; B fatal_error // lower_el_aarch32_sync
      \\.balign 0x80; B fatal_error // lower_el_aarch32_irq
      \\.balign 0x80; B fatal_error // lower_el_aarch32_fiq
      \\.balign 0x80; B fatal_error // lower_el_aarch32_serror
    );
  }
}

export fn fatal_error() noreturn {
  if(comptime sabaton.safety) {
    const error_count = asm volatile(
      \\ MRS %[res], TPIDR_EL1
      \\ ADD %[res], %[res], 1
      \\ MSR TPIDR_EL1, %[res]
      : [res] "=r" (-> u64)
    );

    if(error_count != 1) {
      while(true) { }
    }

    const elr = asm(
      \\MRS %[elr], ELR_EL1
      : [elr] "=r" (-> u64)
    );
    sabaton.log_hex("ELR: ", elr);
    const esr = asm(
      \\MRS %[elr], ESR_EL1
      : [elr] "=r" (-> u64)
    );
    sabaton.log_hex("ESR: ", esr);
    const ec = @truncate(u6, esr >> 26);
    switch(ec) {
      0b000000 => sabaton.puts("Unknown reason\n"),
      0b100001 => sabaton.puts("Instruction fault\n"),
      0b001110 => sabaton.puts("Illegal execution state\n"),
      0b100101 => {
        sabaton.puts("Data abort\n");
        const far = asm(
          \\MRS %[elr], FAR_EL1
          : [elr] "=r" (-> u64)
        );
        sabaton.log_hex("FAR: ", far);
      },
      else => sabaton.log_hex("Unknown ec: ", ec),
    }
    @panic("Fatal error");
  } else {
    asm volatile("ERET");
    unreachable;
  }
}

pub fn install_evt() void {
  asm volatile(
    \\ MSR VBAR_EL1, %[evt]
    \\ MSR TPIDR_EL1, XZR
    :
    : [evt] "r" (sabaton.near("evt_base").addr(u8))
  );
  sabaton.puts("Installed EVT\n");
}

pub fn main() noreturn {
  if(comptime sabaton.safety) {
    install_evt();
  }

  const dram = platform.get_dram();
  const dram_base = @ptrToInt(dram.ptr);

  var kernel_elf = Elf {
    .data = platform.get_kernel(),
  };

  kernel_elf.init();

  var kernel_header: Stivale2hdr = undefined;
  _ = vital(
    kernel_elf.load_section(".stivale2hdr", util.to_byte_slice(&kernel_header)),
    "loading .stivale2hdr", true,
  );

  platform.add_platform_tags(&kernel_header);

  // Allocate space for backing pages of the kernel
  pmm.switch_state(dram_base, .KernelPages);
  sabaton.puts("Allocating kernel memory\n");
  const kernel_memory_pool = pmm.alloc_aligned(kernel_elf.paged_bytes(), .KernelPage);
  sabaton.log_hex("Bytes allocated for kernel: ", kernel_memory_pool.len);

  // TODO: Allocate and put modules here

  pmm.switch_state(dram_base, .PageTables);
  paging_root = paging.init_paging();
  platform.map_platform(&paging_root);
  {
    sabaton.paging.map(dram_base, dram_base, dram.len, .rwx, .memory, &paging_root);
    sabaton.paging.map(dram_base + upper_half_phys_base, dram_base, dram.len, .rwx, .memory, &paging_root);
  }

  @call(.{.modifier = .never_inline}, paging.apply_paging, .{&paging_root});
  // Check the flags in the stivale2 header
  sabaton.puts("Loading kernel into memory\n");
  kernel_elf.load(kernel_memory_pool);

  if(sabaton.debug)
    sabaton.puts("Sealing PMM\n");

  pmm.switch_state(dram_base, .Sealed);

  // Maybe do these conditionally one day once we parse stivale2 kernel tags?
  if(@hasDecl(platform, "display")) {
    sabaton.puts("Starting display\n");
    platform.display.init();
  }

  if(@hasDecl(platform, "smp")) {
    sabaton.puts("Starting SMP\n");
    platform.smp.init();
  }

  if(@hasDecl(platform, "acpi")) {
    platform.acpi.init();
  }

  pmm.write_dram_size(@ptrToInt(dram.ptr) + dram.len);

  add_tag(&near("memmap_tag").addr(Stivale2tag)[0]);

  if(@hasDecl(platform, "launch_kernel_hook"))
    platform.launch_kernel_hook();

  sabaton.puts("Entering kernel...\n");

  asm volatile(
    \\  DMB SY
    \\  CBZ %[stack], 1f
    \\  MOV SP, %[stack]
    \\1:BR %[entry]
    :
    : [entry] "r" (kernel_elf.entry())
    , [stack] "r" (kernel_header.stack)
    , [info] "{X0}" (&stivale2_info)
  );
  unreachable;
}

pub fn stivale2_smp_ready(context: u64) noreturn {
  paging.apply_paging(&paging_root);

  const cpu_tag = @intToPtr(*stivale.SMPTagEntry, context);

  var goto: u64 = undefined;
  while(true) {
    goto = @atomicLoad(u64, &cpu_tag.goto, .Acquire);
    if(goto != 0)
      break;

    asm volatile(
      \\YIELD
    );
  }

  asm volatile("DSB SY\n" ::: "memory");

  asm volatile(
    \\   MSR SPSel, #0
    \\   MOV SP, %[stack]
    \\   MOV LR, #~0
    \\   BR  %[goto]
    :
    : [stack] "r" (cpu_tag.stack)
    , [arg] "{X0}" (cpu_tag)
    , [goto] "r" (goto)
    : "memory"
  );
  unreachable;
}

pub const fb_width = 1024;
pub const fb_height = 768;
pub const fb_bpp = 4;
pub const fb_pitch = fb_width * fb_bpp;
pub const fb_bytes = fb_pitch * fb_height;

pub var fb: packed struct {
  tag: Stivale2tag = .{
    .ident = 0x506461d2950408fa,
    .next = null,
  },
  addr: u64 = undefined,
  width: u16 = fb_width,
  height: u16 = fb_height,
  pitch: u16 = fb_pitch,
  bpp: u16 = fb_bpp * 8,
  mmodel: u8 = 1,
  red_mask_size: u8 = 8,
  red_mask_shift: u8 = 0,
  green_mask_size: u8 = 8,
  green_mask_shift: u8 = 8,
  blue_mask_size: u8 = 8,
  blue_mask_shift: u8 = 16,
} = .{};

pub fn add_framebuffer(addr: u64) void {
  add_tag(&fb.tag);
  fb.addr = addr;
}

var rsdp: packed struct {
  tag: Stivale2tag = .{
    .ident = 0x9e1786930a375e78,
    .next = null,
  },
  rsdp: u64 = undefined,
} = .{};

pub fn add_rsdp(addr: u64) void {
  add_tag(&rsdp.tag);
  rsdp.rsdp = addr;
}
