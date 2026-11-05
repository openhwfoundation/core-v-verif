Tool-specific Makefiles for the CORE-V-VERIF UVM Verification Environment
==================================
This directory contains a set of simulator-specific Makefiles.
The Makefile selected is controlled by the `CV_SIMULATOR` shell environment variable.
For more information see Makefiles in [../README](../README.md#makefiles).

Running the environment with Verilator (verilator)
----------------------

[Verilator](https://github.com/verilator/verilator) is an open-source SystemVerilog simulator.
The cv32e40p UVM testbench can be compiled and run on Verilator with some exclusions documented below.

Verilator-specific accommodations take three forms — `` `ifdef VERILATOR_SIM `` source guards (SVA only), build-time `.flist` filtering (standalone SVA modules), and a Verilator-only stub library that mirrors the ISS / RVVI shapes (`uvmt_cv32e40p_verilator_iss_stubs.sv`). Existing Questa/VCS/Xcelium flows are unaffected.

### Prerequisites

| Requirement | Details |
|-------------|---------|
| Verilator   | Stable release v5.038 or later |
| UVM         | [uvm-verilator](https://github.com/chipsalliance/uvm-verilator/) from CHIPS Alliance |
| g++         | Version 10 or later (required for `-fcoroutines` / `--timing` support) |

### Quick Start

```bash
# Clone UVM library (one-time setup; default branch works, individual UVM
# versions such as uvm-2017-1.0-vlt and uvm-2020-3.1-vlt have also been verified)
git clone https://github.com/chipsalliance/uvm-verilator.git

export VERILATOR_ROOT=/path/to/verilator
export UVM_ROOT=/path/to/uvm-verilator

cd cv32e40p/sim/uvmt
make test SIMULATOR=verilator TEST=hello-world
```

**Hint**: setting `CV_SIMULATOR=verilator` as a shell environment variable is equivalent to passing `SIMULATOR=verilator` on each `make` invocation.

### Current Status

The `hello-world` firmware test passes end-to-end on Verilator with 0 UVM_ERROR / 0 UVM_FATAL.
The following features are excluded from Verilator simulation (details below):
- SVA assertion checking
- Functional coverage collection
- ISS/RVVI instruction-level co-simulation

All other UVM testbench functionality (sequences, virtual peripherals, OBI protocol agents) operates normally. Note that while the scoreboard is compiled, it has nothing to do without a reference model (ISS).

### Features Excluded from Verilator Simulation

The following features are present in the cv32e40p UVM testbench but are excluded from Verilator simulation via two distinct mechanisms: source-level `ifdef` guards and compile-time warning suppression.

#### 1. SVA Assertions — excluded via `ifdef` guards and `.flist` filtering

SystemVerilog Assertions (SVA) are not fully supported by Verilator. All SVA-related code is excluded at compile time so that it never reaches the Verilator elaboration stage.

**Source-level exclusion** (`` `ifndef VERILATOR_SIM ``):
| Location | What is excluded |
|----------|-----------------|
| `uvma_obi_memory_pkg.sv` | `include` of `uvma_obi_memory_assert.sv`, `uvma_obi_memory_1p2_assert.sv`, `uvma_obi_memory_assert_if_wrp.sv` |
| `uvmt_cv32e40p_tb.sv` | `bind` statements for OBI memory assertion wrappers |
| `uvmt_cv32e40p_tb.sv` | `bind` statement for `uvmt_cv32e40p_interrupt_assert` |
| `uvmt_cv32e40p_tb.sv` | Instantiation of `uvmt_cv32e40p_debug_assert` module |

**Build-level exclusion** (`verilator.mk`):
The Makefile generates a filtered `.flist` at build time via `sed`, removing lines that reference standalone SVA module files (these cannot be guarded with `` `ifdef `` inside `.flist` files):
- `uvmt_cv32e40p_interrupt_assert.sv`
- `uvmt_cv32e40p_debug_assert.sv`
- `svlib_pkg.flist`

**Functional impact**: No assertion checking is performed. Functional verification relies on UVM scoreboard and sequence-level checks only.

#### 2. Functional Coverage — compiles but not collected

Verilator compiles covergroup constructs without error but does **not** collect coverage data. Coverage code is **not** excluded from the source — it compiles and is present in the design, but produces no coverage database.

The `-Wno-COVERIGN` flag in `verilator.mk` suppresses the per-instance "coverage ignored" warnings that Verilator emits for each covergroup.

**Functional impact**: No functional coverage data is generated. Coverage analysis must be performed with a commercial simulator.

#### 3. ISS/RVVI Co-simulation — replaced by Verilator-only stubs

The Imperas Instruction Set Simulator (ISS) is not available in the Verilator flow. The Imperas vendor SV (`vendor_lib/imperas/.../imperas_CV32.sv`) declares DPI imports with user-defined `output` struct arguments (`RMData_ioT`, `SVData_ioT`, etc.), which the upstream tool does not yet support (`E_UNSUPPORTED` in `V3Task.cpp`).

Rather than scattering `` `ifndef VERILATOR_SIM `` guards across the ISS wrapper / step-compare / RVVI_memory sites, a single Verilator-only file mirrors the minimum shapes the TB references so the unguarded source elaborates as no-op code:

`cv32e40p/tb/uvmt/uvmt_cv32e40p_verilator_iss_stubs.sv` provides:
- `interface RVVI_memory` (fixed-size array sink for backdoor writes)
- `interface RVVI_io` / `interface RVVI_bus`
- `module CPU` / `module RAM` / `module uvmt_cv32e40p_iss_wrap` / `module uvmt_cv32e40p_step_compare` (all empty-body or hierarchical-mirror only)

This file is added to `SRC_ARGS` exclusively in `verilator.mk`; Questa/VCS/Xcelium never see it.

**Functional impact**: No instruction-level comparison against a reference model. The ISS arbitration logic in `uvmt_cv32e40p_tb.sv` still elaborates and runs every cycle, but its outputs feed only the stub interfaces (no observers). Test pass/fail is determined by firmware self-checking (test-program exit status via virtual peripherals) and UVM error counts.

**Future-proofing**: Once Verilator supports DPI struct args (and an Imperas license + `imperas_CV32.dpi.so` are available), drop the stub file from `verilator.mk` and add `imperas_iss.flist` instead — no source-level changes required.

### Verilator Compile Flags

| Flag | Purpose |
|------|---------|
| `+define+VERILATOR_SIM` | Activates all `` `ifdef VERILATOR_SIM `` guards in the testbench |
| `+define+$(CV_CORE_UC)_TRACE_EXECUTION` | Enables the `tracer_i` instance inside `cv32e40p_wrapper`. Required because the (unguarded) ISS arbitration block in `uvmt_cv32e40p_tb.sv` references `dut_wrap.cv32e40p_wrapper_i.tracer_i.retire/insn_pc`. Other simulator makefiles (vsim/vcs/xrun/dsim/riviera) already pass the same define |
| `-DUVM_NO_DPI` | Disables UVM DPI-based functionality (`uvm_cmdline_processor`, HDL backdoor register access, DPI-based regex matching). Uses `-D` (C preprocessor) syntax because Verilator propagates it to both SV elaboration and C++ compilation. Required because the uvm-verilator library provides alternative non-DPI implementations for these features |
| `+define+UVM_ENABLE_DEPRECATED_API` | Enables deprecated UVM API used by the existing testbench code |

### Verilator Warning Suppression Flags

The following `-Wno-*` flags are passed to Verilator to suppress warnings from the existing testbench code. Most are cosmetic; those with functional or timing implications are highlighted.

| Flag | Description | Impact |
|------|-------------|--------|
| **`-Wno-COVERIGN`** | **Suppress warnings for coverage constructs being ignored** | **Functional — see Section 2 above** |
| `-Wno-ZERODLY` | Suppress warnings for `#0` zero-delay constructs | Timing — Verilator converts `#0` to scheduling events; behavior may differ from event-driven simulators in edge cases |
| `-Wno-COMBDLY` | Suppress warnings for delayed assignments in combinational blocks | Timing — may mask combinational timing differences |
| `-Wno-UNOPTFLAT` | Suppress warnings for unoptimizable circular logic | Performance — may cause slower simulation but does not affect correctness |
| `-Wno-MULTIDRIVEN` | Suppress warnings for signals driven from multiple always blocks | Functional — required for the (now unguarded) ISS arbitration in `uvmt_cv32e40p_tb.sv`, which intentionally drives `irq_deferint_ack/sleep` and `RVVI_io.deferint` from multiple always blocks. Other simulators accept this without complaint |
| `-Wno-lint` | Suppress all lint warnings (WIDTH, IMPLICIT, CASEINCOMPLETE, etc.) | Broad — necessary due to volume of warnings from existing testbench code. Replacing with specific `-Wno-<code>` flags is recommended as a follow-up |
| `-Wno-style` | Suppress all style warnings (ASSIGNDLY, BLKSEQ, UNDRIVEN, etc.) | Cosmetic |
| `-Wno-SYMRSVDWORD` | Suppress warnings for SV identifiers that collide with C++ reserved words | Cosmetic — Verilator auto-renames these internally |
| `-Wno-IGNOREDRETURN` | Suppress warnings for function return values being ignored | Cosmetic — common UVM pattern of calling functions as tasks |
| `-Wno-BADSTDPRAGMA` | Suppress warnings for unrecognized standard pragmas | Cosmetic — UVM library uses non-standard pragmas |

### Global Fixes

The following fixes were introduced alongside Verilator support but are **simulator-agnostic**. Verilator's stricter compilation exposed these pre-existing issues in the testbench code. All fixes are made without any `ifdef VERILATOR_SIM` guard and have been verified to pass on both Verilator and Questa.

| Fix | File(s) | Reason |
|-----|---------|--------|
| Remove `pragma protect` directives | 11 files in `uvma_debug`, `uvma_interrupt`, `uvme_rv32isa_covg_trn` | Template-tool artifacts; never used by OpenHW, safely ignored by all commercial simulators |
| Fix JSON format specifiers (`%h/%b/%d` &rarr; `%s`) | `uvma_clknrst_mon_trn_logger.sv` | Format specifiers did not match string argument types |
| Replace deprecated `uvm_do_on_with` macro | `uvme_cv32e40p_reset_vseq.sv` | Deprecated per IEEE 1800.2-2017; replaced with explicit sequence execution |
| Fix constructor ordering: `super.new()` first | `uvml_logs_reg_logger_cbs.sv` | IEEE 1800-2023 Section 8.15 requires `super.new()` as the first statement |
| Rename `errno` &rarr; `errnum` | `uvml_mem.sv` | `errno` collides with the C `<errno.h>` macro during C++ compilation |
| Use `uvm_report_server::get_server()` | `uvmt_cv32e40p_tb.sv` | Static class method; replaces `uvm_top.get_report_server()` for portability |
| Reorder `build_phase`: `create_cntxt()` before `randomize_test()` | `uvmt_cv32e40p_base_test.sv` | Prevents null-dereference when the constraint solver accesses uninitialized rand sub-objects |

**Note**: When adding new UVM components, avoid using C standard library macros or POSIX names (e.g. `errno`, `stdin`, `stdout`) as SystemVerilog identifiers — Verilator translates SV names directly to C++ and the collision causes compilation failures.
