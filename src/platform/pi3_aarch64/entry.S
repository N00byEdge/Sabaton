.global _start

.section .text.entry
_start:
  // Copy page settings to EL1
  MRS X1, SCTLR_EL2
  MSR SCTLR_EL1, X1
  MRS X1, TCR_EL2
  MSR TCR_EL1, X1
  MRS X1, MAIR_EL2
  MSR MAIR_EL1, X1
  MRS X1, TTBR0_EL2
  MSR TTBR0_EL1, X1
  MSR TTBR1_EL1, XZR

  TLBI VMALLE1

  BL el2_to_el1

  // Relocate ourselves
  ADR X0, _start
  LDR X1, relocation_base
  LDR X2, relocation_end

.relocate_loop:
  CMP X1, X2
  B.EQ .relocate_done

  // I also know how to write bzero like this :)
  LDP X3, X4, [X0, #0x00]
  STP X3, X4, [X1, #0x00]

  ADD X0, X0, #0x10
  ADD X1, X1, #0x10

  B .relocate_loop
.relocate_done:

  // Jump to relocated code
  LDR X1, relocation_base
  ADD X1, X1, .cont - _start
  BR X1

.cont:
  MSR SPSel, #0
  ADR X18, _start
  MOV SP, X18
  B _main

.section .text
.global el2_to_el1
el2_to_el1:
  // aarch64 in EL1
  ORR X1, XZR, #(1 << 31)
  ORR X1, X1,  #(1 << 1)
  MSR HCR_EL2, X1

  // Counters in EL1
  MRS X1, CNTHCTL_EL2
  ORR X1, X1, #3
  MSR CNTHCTL_EL2, X1
  MSR CNTVOFF_EL2, XZR

  // FP/SIMD in EL1
  MOV X1, #0x33FF
  MSR CPTR_EL2, X1
  MSR HSTR_EL2, XZR
  MOV X1, #0x300000
  MSR CPACR_EL1, X1

  // Get the fuck out of EL2 into EL1
  MSR ELR_EL2, LR
  MOV X1, #0x3C5
  MSR SPSR_EL2, X1
  ERET

.global devicetree_tag
.global uart_tag
.global uart_reg
.section .data.stivale_tags
.balign 8
platform_tags:

.balign 8
uart_tag:
  .8byte 0xf77485dbfeb260f9 // u32 MMIO UART with status
  .8byte 0
uart_reg:
  .8byte 0x3f215040
uart_status:
  .8byte 0x3f215054
uart_status_mask:
  .4byte 0x20
uart_status_value:
  .4byte 0x20

.global kernel_file_loc
.section .rodata
.balign 8
relocation_base:
  .8byte __blob_base
relocation_end:
  .8byte __blob_end
