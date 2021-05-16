pub const MMIO_BASE = 0x3F000000;
const MMIO_BANK = RegBank.base(0x3F000000);

const AUX_BANK           = MMIO_BANK.sub(0x215000);
pub const AUX_ENABLES    = AUX_BANK.reg(0x04);
pub const AUX_MU_IO      = AUX_BANK.reg(0x40);
pub const AUX_MU_IER     = AUX_BANK.reg(0x44);
pub const AUX_MU_IIR     = AUX_BANK.reg(0x48);
pub const AUX_MU_LCR     = AUX_BANK.reg(0x4C);
pub const AUX_MU_MCR     = AUX_BANK.reg(0x50);
pub const AUX_MU_LSR     = AUX_BANK.reg(0x54);
pub const AUX_MU_MSR     = AUX_BANK.reg(0x58);
pub const AUX_MU_SCRATCH = AUX_BANK.reg(0x5C);
pub const AUX_MU_CNTL    = AUX_BANK.reg(0x60);
pub const AUX_MU_STAT    = AUX_BANK.reg(0x64);
pub const AUX_MU_BAUD    = AUX_BANK.reg(0x68);

const GPIO_BANK     = MMIO_BANK.sub(0x200000);
pub const GPFSEL0   = GPIO_BANK.reg(0x00);
pub const GPFSEL1   = GPIO_BANK.reg(0x04);
pub const GPPUD     = GPIO_BANK.reg(0x94);
pub const GPPUDCLK0 = GPIO_BANK.reg(0x98);

const MBOX_BANK       = MMIO_BANK.sub(0xB880);
pub const MBOX_READ   = MBOX_BANK.reg(0x00);
pub const MBOX_CONFIG = MBOX_BANK.reg(0x1C);
pub const MBOX_WRITE  = MBOX_BANK.reg(0x20);
pub const MBOX_STATUS = MBOX_BANK.reg(0x18);

const RegBank = struct {
    bank_base: usize,

    /// Create the base register bank
    pub fn base(comptime bank_base: comptime_int) @This() {
        return .{ .bank_base = bank_base };
    }
    
    /// Make a smaller register sub-bank out of a bigger one
    pub fn sub(self: @This(), comptime offset: comptime_int) @This() {
        return .{ .bank_base = self.bank_base + offset };
    }
    
    /// Define a single register
    pub fn reg(self: @This(), comptime offset: comptime_int) *volatile u32 {
        return @intToPtr(*volatile u32, self.bank_base + offset);
    }
};
