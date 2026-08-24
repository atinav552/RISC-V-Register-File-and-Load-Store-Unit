# RISC-V Register File and LSU Module

## Overview
A structural implementation of two critical RISC-V CPU datapath components: the 32-bit Register File (RF) and the Load-Store Unit (LSU), written in standard Verilog-2001. 

This design strictly adheres to the RISC-V unprivileged ISA specification, including the `x0` hardwired zero register and robust memory alignment controls.

## Architecture Highlights
### 1. Register File (RF)
* **32 General Purpose Registers:** 32-bit data width.
* **Hardwired Zero:** Register `x0` strictly evaluates to `0` and ignores all write attempts.
* **Dual-Port Asynchronous Read:** Allows the CPU to fetch two operands combinationally without clock cycle delays.
* **Synchronous Write:** Updates destination registers dynamically on the positive clock edge.

### 2. Load-Store Unit (LSU)
* **Dynamic Byte Enables:** Automatically calculates standard 4-bit memory write strobes (`mem_byte_en`) to selectively overwrite specific bytes, halfwords, or full words in main memory.
* **Sign & Zero Extension:** Implements internal multiplexers to correctly format retrieved 8-bit or 16-bit data, seamlessly supporting both signed loads (`LB`, `LH`) and unsigned loads (`LBU`, `LHU`).
* **Misaligned Fault Detection:** Continuously monitors the target memory address against the requested size. It immediately flags an `addr_fault` exception if a word is not 4-byte aligned or a halfword is not 2-byte aligned, preventing hardware data corruption.

## Verification
The repository includes a comprehensive Verilog testbench (`riscv_tb.v`) that tests:
1. **Zero Register Integrity:** Proves `x0` cannot be overwritten.
2. **Unaligned Word Exceptions:** Intentionally passes misaligned addresses to verify the `addr_fault` logic triggers correctly.
3. **Sign-Extended Byte Loads:** Verifies the LSU accurately extracts a negative 8-bit integer from a 32-bit block and pads it with 1s.
4. **Halfword Store Alignment:** Verifies that a 16-bit store payload is correctly shifted to the proper byte lanes alongside accurate write strobes.
