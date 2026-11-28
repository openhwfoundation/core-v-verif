// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Copyright 2020 OpenHW Group
// Copyright 2020 Datum Technology Corporation
// Copyright 2020 Silicon Labs, Inc.
//
// Licensed under the Solderpad Hardware Licence, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://solderpad.org/licenses/
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//


`ifndef __UVMA_RVFI_INSTR_MON_SV__
`define __UVMA_RVFI_INSTR_MON_SV__


/**
 * Component sampling transactions from a Clock & Reset virtual interface
 * (uvma_rvfi_instr_if).
 */
class uvma_rvfi_instr_mon_c#(int ILEN=DEFAULT_ILEN,
                             int XLEN=DEFAULT_XLEN) extends uvm_monitor;

   // Objects
   uvma_rvfi_cfg_c    cfg;
   uvma_rvfi_cntxt_c  cntxt;

   // TLM
   uvm_analysis_port#(uvma_rvfi_instr_seq_item_c#(ILEN,XLEN)) ap;

   // State of monitor
   bit                last_dcsr_nmip = 0;
   bit [uvma_rvfi_csr_seq_item_c#()::XLEN-1:0] dcsr_ret_data;

   longint unsigned supported_csrs_addrs [$];
   string supported_csrs_names [$];

   string log_tag = "RVFIMONLOG";

   `uvm_component_utils_begin(uvma_rvfi_instr_mon_c)
      `uvm_field_int(last_dcsr_nmip, UVM_DEFAULT)
      `uvm_field_int(dcsr_ret_data,  UVM_DEFAULT)
      `uvm_field_object(cfg,         UVM_DEFAULT | UVM_REFERENCE)
      `uvm_field_object(cntxt,       UVM_DEFAULT | UVM_REFERENCE)
   `uvm_component_utils_end

   /**
    * Default constructor.
    */
   extern function new(string name="uvma_rvfi_instr_mon", uvm_component parent=null);

   /**
    * 1. Ensures cfg & cntxt handles are not null.
    * 2. Builds ap.
    */
   extern virtual function void build_phase(uvm_phase phase);

   /**
    * Oversees monitoring via monitor_clk() and monitor_reset() tasks in parallel
    * forks.
    */
   extern virtual task run_phase(uvm_phase phase);

   /**
    * Monitor the instruction interface
    */
   extern virtual task monitor_rvfi_instr();

endclass : uvma_rvfi_instr_mon_c

function uvma_rvfi_instr_mon_c::new(string name="uvma_rvfi_instr_mon", uvm_component parent=null);

   super.new(name, parent);

endfunction : new


function void uvma_rvfi_instr_mon_c::build_phase(uvm_phase phase);

   super.build_phase(phase);

   if ($test$plusargs("log_rvfi"))
      set_report_id_verbosity(log_tag, UVM_HIGH);

   void'(uvm_config_db#(uvma_rvfi_cfg_c#(ILEN,XLEN))::get(this, "", "cfg", cfg));
   if (!cfg) begin
      `uvm_fatal("CFG", "Configuration handle is null")
   end

   void'(uvm_config_db#(uvma_rvfi_cntxt_c#(ILEN,XLEN))::get(this, "", "cntxt", cntxt));
   if (!cntxt) begin
      `uvm_fatal("CNTXT", "Context handle is null")
   end

   ap = new("ap", this);

endfunction : build_phase

task uvma_rvfi_instr_mon_c::run_phase(uvm_phase phase);

   super.run_phase(phase);

    cfg.core_cfg.get_supported_csrs_names(supported_csrs_names);
    cfg.core_cfg.get_supported_csrs_addrs(supported_csrs_addrs);

    // TODO Make this prettier
    if (cfg.enabled) begin
        while (1) begin
            wait (cntxt.instr_vif[0].reset_n === 1'b0);
            wait (cntxt.instr_vif[0].reset_n === 1'b1);

            fork
                begin
                    monitor_rvfi_instr();
                end
                begin
                    wait (cntxt.instr_vif[0].reset_n === 1'b0);
                end
            join_any
        end
    end
endtask : run_phase


task uvma_rvfi_instr_mon_c::monitor_rvfi_instr();

   if (!cfg.ap_write_en) begin
      `uvm_warning("RVFI INSTR MON", "Writing to Analysis Port has been disabled")
   end

   while(1) begin
      @(cntxt.instr_vif[0].mon_cb)

      for(int i = 0; i < cfg.nret; i++)
      begin
          int nret_id;
          bit monitor_condition;

         nret_id = i;
         monitor_condition = (!cfg.core_cfg.unified_traps) ?
                             (cntxt.instr_vif[nret_id].mon_cb.rvfi_valid || cntxt.instr_vif[nret_id].mon_cb.rvfi_trap[0]) :
                             (cntxt.instr_vif[nret_id].mon_cb.rvfi_valid);

         // OPTIMIZATION: Only create and populate transaction if it will be used.
         if (cfg.ap_write_en || cfg.insn_bus_fault_enabled || uvm_report_enabled(UVM_HIGH, UVM_INFO, log_tag)) begin
            uvma_rvfi_instr_seq_item_c#(ILEN,XLEN) mon_trn;

            mon_trn = uvma_rvfi_instr_seq_item_c#(ILEN,XLEN)::type_id::create("mon_trn");

            mon_trn.nret_id  = nret_id;
            mon_trn.cycle_cnt = cntxt.instr_vif[nret_id].mon_cb.cycle_cnt;
            mon_trn.order     = cntxt.instr_vif[nret_id].mon_cb.rvfi_order;
            mon_trn.insn      = cntxt.instr_vif[nret_id].mon_cb.rvfi_insn;
            mon_trn.trap      = cntxt.instr_vif[nret_id].mon_cb.rvfi_trap;
            mon_trn.halt      = cntxt.instr_vif[nret_id].mon_cb.rvfi_halt;
            mon_trn.dbg       = cntxt.instr_vif[nret_id].mon_cb.rvfi_dbg;
            mon_trn.dbg_mode  = cntxt.instr_vif[nret_id].mon_cb.rvfi_dbg_mode;
            mon_trn.nmip      = cntxt.instr_vif[nret_id].mon_cb.rvfi_nmip;
            mon_trn.intr      = cntxt.instr_vif[nret_id].mon_cb.rvfi_intr;
            $cast(mon_trn.mode, cntxt.instr_vif[nret_id].mon_cb.rvfi_mode);
            mon_trn.ixl       = cntxt.instr_vif[nret_id].mon_cb.rvfi_ixl;
            mon_trn.pc_rdata  = cntxt.instr_vif[nret_id].mon_cb.rvfi_pc_rdata;
            mon_trn.pc_wdata  = cntxt.instr_vif[nret_id].mon_cb.rvfi_pc_wdata;

            mon_trn.rs1_addr   = cntxt.instr_vif[nret_id].mon_cb.rvfi_rs1_addr;
            mon_trn.rs1_rdata  = cntxt.instr_vif[nret_id].mon_cb.rvfi_rs1_rdata;

            mon_trn.rs2_addr   = cntxt.instr_vif[nret_id].mon_cb.rvfi_rs2_addr;
            mon_trn.rs2_rdata  = cntxt.instr_vif[nret_id].mon_cb.rvfi_rs2_rdata;

            mon_trn.rs3_addr   = cntxt.instr_vif[nret_id].mon_cb.rvfi_rs3_addr;
            mon_trn.rs3_rdata  = cntxt.instr_vif[nret_id].mon_cb.rvfi_rs3_rdata;

            mon_trn.rd1_addr   = cntxt.instr_vif[nret_id].mon_cb.rvfi_rd1_addr;
            mon_trn.rd1_wdata  = cntxt.instr_vif[nret_id].mon_cb.rvfi_rd1_wdata;

            mon_trn.rd2_addr   = cntxt.instr_vif[nret_id].mon_cb.rvfi_rd2_addr;
            mon_trn.rd2_wdata  = cntxt.instr_vif[nret_id].mon_cb.rvfi_rd2_wdata;

            mon_trn.mem_addr  = cntxt.instr_vif[nret_id].mon_cb.rvfi_mem_addr;
            mon_trn.mem_rdata = cntxt.instr_vif[nret_id].mon_cb.rvfi_mem_rdata;
            mon_trn.mem_rmask = cntxt.instr_vif[nret_id].mon_cb.rvfi_mem_rmask;
            mon_trn.mem_wdata = cntxt.instr_vif[nret_id].mon_cb.rvfi_mem_wdata;
            mon_trn.mem_wmask = cntxt.instr_vif[nret_id].mon_cb.rvfi_mem_wmask;

            // Get the CSRs
            if (!cfg.core_cfg.disable_all_csr_checks) begin
               if (!cfg.unified_csr_vif) begin
                  foreach (cntxt.csr_vif[csr]) begin
                     uvma_rvfi_csr_seq_item_c csr_trn = uvma_rvfi_csr_seq_item_c#(XLEN)::type_id::create({csr, "_trn"});

                     csr_trn.csr = csr;
                     csr_trn.nret_id = nret_id;
                     csr_trn.rmask = cntxt.csr_vif[csr][nret_id].mon_cb.rvfi_csr_rmask;
                     csr_trn.wmask = cntxt.csr_vif[csr][nret_id].mon_cb.rvfi_csr_wmask;
                     csr_trn.rdata = cntxt.csr_vif[csr][nret_id].mon_cb.rvfi_csr_rdata;
                     csr_trn.wdata = cntxt.csr_vif[csr][nret_id].mon_cb.rvfi_csr_wdata;

                     mon_trn.name_csrs[csr] = csr_trn;
                  end
               end
               else begin
                  uvma_rvfi_csr_seq_item_c csr_trn;
                  longint unsigned addr;

                  // Only process CSR if active (wmask or rmask != 0) OR if we strictly need to check everything
                  // The implicit CSR access (the one pointed to by rvfi_csr_addr)
                  addr = cntxt.csr_unified_vif[nret_id].mon_cb.rvfi_csr_addr;
                  if (cntxt.csr_unified_vif[nret_id].mon_cb.rvfi_csr_wmask != 0 || 
                      cntxt.csr_unified_vif[nret_id].mon_cb.rvfi_csr_rmask != 0 ||
                      cntxt.csr_unified_vif[nret_id].mon_cb.rvfi_csr_rdata != 0) begin
                     // Note: rdata check is heuristic, strict compliance might require checking masks only
                     
                     csr_trn = uvma_rvfi_csr_seq_item_c#(XLEN)::type_id::create({addr, "_trn"});
                     csr_trn.addr = addr;
                     csr_trn.wmask = cntxt.csr_unified_vif[nret_id].mon_cb.rvfi_csr_wmask;
                     csr_trn.wdata = cntxt.csr_unified_vif[nret_id].mon_cb.rvfi_csr_wdata;
                     csr_trn.rmask = cntxt.csr_unified_vif[nret_id].mon_cb.rvfi_csr_rmask;
                     csr_trn.rdata = cntxt.csr_unified_vif[nret_id].mon_cb.rvfi_csr_rdata;
                     mon_trn.addr_csrs[addr] = csr_trn;
                  end

                  foreach(supported_csrs_addrs[i]) begin
                     addr = supported_csrs_addrs[i];
                     // Performance Optimization: Only create object if CSR is actually accessed (read or written)
                     if (cntxt.csr_unified_vif[nret_id].mon_cb.rvfi_named_csr_wmask[addr] != 0 || 
                         cntxt.csr_unified_vif[nret_id].mon_cb.rvfi_named_csr_rmask[addr] != 0) begin
                        
                        csr_trn = uvma_rvfi_csr_seq_item_c#(XLEN)::type_id::create({addr, "_trn"});
                        csr_trn.addr = addr;
                        csr_trn.wmask = cntxt.csr_unified_vif[nret_id].mon_cb.rvfi_named_csr_wmask[addr];
                        csr_trn.wdata = cntxt.csr_unified_vif[nret_id].mon_cb.rvfi_named_csr_wdata[addr];
                        csr_trn.rmask = cntxt.csr_unified_vif[nret_id].mon_cb.rvfi_named_csr_rmask[addr];
                        csr_trn.rdata = cntxt.csr_unified_vif[nret_id].mon_cb.rvfi_named_csr_rdata[addr];
                        mon_trn.addr_csrs[addr] = csr_trn;
                     end
                  end
               end

               // Decode interrupts that need to be communicated to ISS (external or NMI bus faults)
               if (mon_trn.intr) begin
                  // The cause of the interrupt should be in the "rdata" field of the mcause CSR RVFI port
                  bit [XLEN-1:0] csr_mcause;

                  if (!cfg.unified_csr_vif) begin
                     if (mon_trn.name_csrs.exists("mcause"))
                        csr_mcause = mon_trn.name_csrs["mcause"].rdata;
                  end
                  else begin
                     if (mon_trn.addr_csrs.exists(MCAUSE))
                        csr_mcause = mon_trn.addr_csrs[MCAUSE].rdata;
                  end

                  // External interrupt
                  if (csr_mcause[31]) begin
                     // NMI - Load fault
                     if (cfg.nmi_load_fault_enabled && csr_mcause[XLEN-2:0] == cfg.nmi_load_fault_cause) begin
                        mon_trn.insn_nmi_load_fault = 1;
                     end
                     // NMI - Store fault
                     else if (cfg.nmi_store_fault_enabled && csr_mcause[XLEN-2:0] == cfg.nmi_store_fault_cause) begin
                        mon_trn.insn_nmi_store_fault = 1;
                     end
                     // External interrupt
                     else begin
                        mon_trn.insn_interrupt    = 1;
                        mon_trn.insn_interrupt_id = { 1'b0, csr_mcause[XLEN-2:0] };
                     end
                  end
               end
               if (!cfg.unified_csr_vif && mon_trn.name_csrs.exists("dcsr"))
                  dcsr_ret_data = mon_trn.name_csrs["dcsr"].get_csr_retirement_data();
               else if (cfg.unified_csr_vif && mon_trn.addr_csrs.exists(DCSR))
                  dcsr_ret_data = mon_trn.addr_csrs[DCSR].get_csr_retirement_data();

               // In debug mode, detect NMIP event for a data bus error
               if (mon_trn.dbg_mode &&
                   !last_dcsr_nmip &&
                   mon_trn.nmip[0] &&
                   dcsr_ret_data[3])
               begin
                  `uvm_info("RVFIMON", $sformatf("Debug NMIP"), UVM_LOW);

                  if (mon_trn.nmip[1] == 0) begin
                     mon_trn.insn_nmi_load_fault = 1;
                  end else begin
                     mon_trn.insn_nmi_store_fault = 1;
                  end
               end

               // Latch the last DCSR NMIP bit to detect positive assertion of dcsr.nmip
               last_dcsr_nmip = dcsr_ret_data[3];
            end

            // Detect instruction bus fault
            if (cfg.insn_bus_fault_enabled &&
                mon_trn.is_trap() &&
                mon_trn.get_trap_cause() == cfg.insn_bus_fault_cause) begin
               mon_trn.insn_bus_fault = 1;
               `uvm_info("RVFIMON", $sformatf("Detected bus fault"), UVM_LOW)
            end

            `uvm_info(log_tag, $sformatf("%s", mon_trn.convert2string()), UVM_HIGH);

            if (cfg.ap_write_en) begin
               ap.write(mon_trn);
            end
         end

      end
   end

endtask : monitor_rvfi_instr

`endif // __UVMA_RVFI_INSTR_MON_SV__

