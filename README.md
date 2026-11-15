# RISC-V Register File and Load-Store Unit (LSU)

## Overview
A synthesizable Register-Transfer Level (RTL) implementation of two core **RV32I Base Integer Instruction Set** datapath components: the **32-bit Register File (`riscv_regfile`)** and the **Load-Store Unit (`riscv_lsu`)**, written in standard Verilog-2001.

This design strictly adheres to the RISC-V Unprivileged ISA Specification, featuring hardwired `x0` protection, same-cycle write-through register bypassing, hardware misaligned-address exception detection, and dynamic pipeline stall generation for multi-cycle memory interfaces.

---

## Microarchitecture & RTL Highlights

### 1. 32-Bit RISC-V Register File (`riscv_regfile`)
* **Area-Optimized Storage (`x1`–`x31`):** Physically instantiates 31 registers (`registers[1:31]`) while hardwiring `x0` (`5'd0`) to `32'd0` combinationally, eliminating 32 redundant flip-flops during synthesis.
* **Hardwired Zero Priority:** Strictly blocks write attempts targeting `x0` (`rd == 5'd0`) and prioritizes `x0` zero-evaluation ahead of internal bypass paths.
* **Dual-Port Asynchronous Read with Write-Through Bypass:** Supports two concurrent combinational reads (`rs1`, `rs2`). Includes an internal write-through forwarding multiplexer (`(we && (rsX == rd)) ? wdata : registers[rsX]`) to allow simultaneous read and write-back to the same register within a single clock cycle without pipeline stalls.
* **Synchronous Write:** Updates target registers on the rising clock edge (`posedge clk`) with asynchronous active-low reset (`rst_n`).

### 2. RISC-V Load-Store Unit (`riscv_lsu`)
* **Byte & Halfword Lane Steering (`SB`, `SH`, `SW`):** Dynamically generates 4-bit write strobes (`mem_byte_en`) and shifts store data (`mem_wdata`) across 32-bit word-aligned memory boundaries based on byte offset `addr[1:0]`.
* **Shared-Mux Sign & Zero Extension (`LB`, `LBU`, `LH`, `LHU`, `LW`):** Uses area-optimized 8-bit and 16-bit extraction multiplexers followed by unified sign/zero extension logic to format sub-word loads.
* **Hardware Misaligned Exception Detection (`addr_fault`):** Continuously checks access granularity against address alignment (`addr[0] != 1'b0` for 16-bit halfwords; `addr[1:0] != 2'b00` for 32-bit words). Immediately gates off `mem_valid` and `mem_we_out` on a fault to prevent memory corruption.
* **FSM Handshake & Dynamic Pipeline Stalls (`stall`):** Incorporates a 3-state controller (`IDLE`, `WAIT_MEM`, `FAULT`) that tracks multi-cycle memory latency (`!mem_ready`) and asserts `stall` only on valid, aligned requests—preventing pipeline deadlocks during alignment traps.

---

## LSU Access Encoding & Alignment Rules

| `size[1:0]` | `l_unsigned` | `mem_we` | RV32I Instruction | Required Alignment | `mem_byte_en` |
| :---: | :---: | :---: | :--- | :--- | :---: |
| `2'b00` | `0` / `1` | `0` | `LB` / `LBU` (8-bit Load) | Any (`addr[1:0]` = `00..11`) | `4'b0000` |
| `2'b00` | `X` | `1` | `SB` (8-bit Store) | Any (`addr[1:0]` = `00..11`) | `4'b0001 << addr[1:0]` |
| `2'b01` | `0` / `1` | `0` | `LH` / `LHU` (16-bit Load) | Halfword (`addr[0] == 0`) | `4'b0000` |
| `2'b01` | `X` | `1` | `SH` (16-bit Store) | Halfword (`addr[0] == 0`) | `4'b0011` or `4'b1100` |
| `2'b10` | `X` | `0` | `LW` (32-bit Load) | Word (`addr[1:0] == 2'b00`) | `4'b0000` |
| `2'b10` | `X` | `1` | `SW` (32-bit Store) | Word (`addr[1:0] == 2'b00`) | `4'b1111` |
| `2'b11` | `X` | `X` | *Reserved / Invalid* | Triggers `addr_fault = 1` | `4'b0000` |

---

## Verification Suite
The repository includes a self-checking Verilog testbench (`riscv_tb.v`) that verifies:
1. **Zero Register (`x0`) Integrity:** Confirms write attempts to `x0` are ignored and reads always return `32'd0`.
2. **Same-Cycle Write-Through Forwarding:** Verifies simultaneous read/write to the same non-zero register returns the newly written `wdata`.
3. **Unaligned Word & Halfword Exceptions:** Injects misaligned addresses to confirm `addr_fault` asserts, `mem_we_out` is suppressed, and `stall` does not deadlock the pipeline.
4. **Sign-Extended & Zero-Extended Sub-Word Loads:** Verifies `LB`/`LBU` and `LH`/`LHU` extraction across all byte offsets.
5. **Sub-Word Store Alignment & Multi-Cycle Stalls:** Verifies payload shifting, `mem_byte_en` generation, and `WAIT_MEM` stall recovery when `mem_ready` is delayed.
