// Copyright 2026 PlanV GmbH
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Stubs used only by the Verilator build of cv32e40p.
//
// The Imperas vendor SV (vendor_lib/imperas/.../imperas_CV32.sv) declares DPI
// imports with user-defined struct output arguments, which the upstream tool
// does not yet support. To avoid `ifndef VERILATOR_SIM guards on the entire
// ISS wrapper / step-compare / RVVI_memory machinery, this file mirrors the
// minimum set of interfaces / modules / hierarchical paths the TB references,
// so the unguarded source elaborates as no-op code on Verilator.
//
// Backdoor writes from the virtual peripheral random-number sequence land in
// the dummy memory and are silently dropped (no ISS to observe them).
//
// Only consumed by mk/uvmt/verilator.mk; never seen by Questa/VCS/Xcelium.

`ifndef __UVMT_CV32E40P_VERILATOR_ISS_STUBS_SV__
`define __UVMT_CV32E40P_VERILATOR_ISS_STUBS_SV__

interface RVVI_memory;
   // Fixed-size array used as a no-op sink for backdoor writes. Verilator does
   // not support virtual interface triggers on associative-array members.
   bit [31:0] mem [0:1023];
endinterface

interface RVVI_io;
   bit        deferint;
   bit [31:0] irq_i;
   bit        haltreq;
   bit        DM;
   bit        irq_ack_o;
   bit [4:0]  irq_id_o;
endinterface

interface RVVI_bus;
   bit Clk;
endinterface

module RAM;
   RVVI_memory memory();
endmodule

module CPU #(parameter int ID = 0, parameter string VARIANT = "");
endmodule

module uvmt_cv32e40p_iss_wrap
  #(
    parameter int ROM_START_ADDR = 'h00000000,
    parameter int ROM_BYTE_SIZE  = 'h0,
    parameter int RAM_BYTE_SIZE  = 'h1B000000,
    parameter int ID = 0
   )
   (
    input realtime                clk_period,
    uvma_clknrst_if               clknrst_if,
    uvmt_cv32e40p_step_compare_if step_compare_if,
    uvmt_cv32e40p_isa_covg_if     isa_covg_if
   );
   RVVI_bus bus();
   RVVI_io  io();
   RAM      ram();
   CPU      cpu();
endmodule

module uvmt_cv32e40p_step_compare
  (
   uvma_clknrst_if               clknrst_if,
   uvmt_cv32e40p_step_compare_if step_compare_if
  );
endmodule

`endif // __UVMT_CV32E40P_VERILATOR_ISS_STUBS_SV__
