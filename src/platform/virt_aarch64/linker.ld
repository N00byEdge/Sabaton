ENTRY(_start)
OUTPUT_FORMAT(elf64-littleaarch64)
OUTPUT_ARCH(aarch64)

PHDRS {
  none   PT_NULL FLAGS(0);
}

__kernel_file_loc = 0x4000000;
__dram_base       = 0x40000000;

SECTIONS {
  . = 0x40100000;
  .blob : {
    __blob_base = .;
    *(.text.entry)
    KEEP(*(.text.main))
    *(.text.smp_stub)
    KEEP(*(.text.smp_entry))
    *(.text*)
    *(.data*)
    *(.rodata*)
    *(.bss*)
    . = ALIGN(16);
    __blob_end = .;
  }

  . = ALIGN(4K);
  __pmm_base = .;

  .eh_frame : {
    *(.eh_frame*)
  }
}
