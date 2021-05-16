const std = @import("std");
pub const sabaton = @import("../../sabaton.zig");
pub const io = sabaton.io_impl.status_uart_mmio_32;
pub const panic = sabaton.panic;
pub const display = @import("display.zig");
pub const ElfType = [*]u8;
usingnamespace @import("regs.zig");

var page_size: u64 = 0x1000;
pub fn get_page_size() u64 { return page_size; }

fn delay(cycles: usize) void {
  var i: u32 = 0; while (i < cycles) : (i += 1) { asm volatile ("nop"); }
}

const VC4_CLOCK = 250*1000*1000; // 250 MHz

fn minuart_calculate_baud(baudrate: u32) u32 {
  return VC4_CLOCK / (8 * baudrate) - 1; // the bcm2835 spec gives this formula: baudrate = vc4_clock / (8*(reg + 1))
}

const GpioMode = packed enum(u3) {
  Input = 0b000, Output,
  Alt0 = 0b100, Alt1, Alt2, Alt3,
  Alt4 = 0b011, Alt5 = 0b010,
};

fn gpio_fsel(pin: u5, mode: GpioMode, val: u32) u32 {
  const mode_int: u32 = @enumToInt(mode);
  const bit = pin * 3; 
  var temp = val;
  temp &= ~(@as(u32, 0b111) << bit);
  temp |= mode_int << bit;
  return temp;
}

// This is the miniUART, it requires enable_uart=1 in config.txt
fn miniuart_init() void {
  GPFSEL1.* = gpio_fsel(14-10, .Alt5, gpio_fsel(15-10, .Alt5, GPFSEL1.*)); // set pins 14-15 to alt5 (miniuart). gpfsel1 handles pins 10 to 19
  GPPUD.* = 0; // disable pullup, pulldown for the clocked regs
  delay(150);
  GPPUDCLK0.* = (1 << 14) | (1 << 15); // clock pins 14-15
  delay(150);
  GPPUDCLK0.* = 0; // clear clock for next usage
  delay(150);

  AUX_ENABLES.* |= 1; // enable the uart regs
  AUX_MU_CNTL.* = 0; // disable uart functionality to set the regs
  AUX_MU_IER.* = 0; // disable uart interrupts
  AUX_MU_LCR.* = 0b11; // 8-bit mode 
  AUX_MU_MCR.* = 0; // RTS always high 
  AUX_MU_IIR.* = 0xc6;
  AUX_MU_BAUD.* = minuart_calculate_baud(115200);
  AUX_MU_CNTL.* = 0b11; // enable tx and rx fifos
}

export fn _main() linksection(".text.main") noreturn {
  miniuart_init();
  @call(.{.modifier = .always_inline}, sabaton.main, .{});
}

pub fn mbox_call(channel: u4, ptr: usize) void {
  while ((MBOX_STATUS .* & 0x80000000) != 0) {}
  const addr = @truncate(u32, ptr) | @as(u32, channel);
  MBOX_WRITE.* = addr;
}

pub fn get_dram() []allowzero u8 {
  var slice: [8]u32 align(16) = undefined;
  var mbox = @intToPtr([*]volatile u32, @ptrToInt(&slice));
  mbox[0] = 8*4; // size
  mbox[1] = 0; // req

  mbox[2] = 0x10005; // tag
  mbox[3] = 8; // buffer size
  mbox[4] = 0; // req/resp code
  mbox[5] = 0; // base
  mbox[6] = 0; // size
  mbox[7] = 0; // terminator

  mbox_call(8, @ptrToInt(mbox));
  const size = mbox[6];
  const addr = mbox[5];
  return @intToPtr([*]allowzero u8, addr)[0..size];
}

pub fn get_uart_info() io.Info {
  const base = 0x1C28000;
  return .{
    .uart = AUX_MU_IO,
    .status = AUX_MU_LSR,
    .mask = 0x20,
    .value = 0x20,
  };
}

pub fn get_kernel() [*]u8 {
  return @intToPtr([*]u8, 0x200000); // TODO: this relies on the config.txt/qemu setup, replace it with a real SD driver
}

pub fn add_platform_tags(kernel_header: *sabaton.Stivale2hdr) void {
  sabaton.add_tag(&sabaton.near("uart_tag").addr(sabaton.Stivale2tag)[0]);
}

pub fn map_platform(root: *sabaton.paging.Root) void {
  sabaton.paging.map(MMIO_BASE, MMIO_BASE, 0xFFFFFFF, .rw, .mmio, root);
  sabaton.paging.map(sabaton.upper_half_phys_base + MMIO_BASE, MMIO_BASE, 0xFFFFFFF, .rw, .mmio, root);
}
