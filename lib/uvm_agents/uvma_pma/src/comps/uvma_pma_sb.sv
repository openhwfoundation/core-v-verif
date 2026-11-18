// Copyright 2021 OpenHW Group
//
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Licensed under the Solderpad Hardware License v 2.1 (the "License"); you may not use this file except in compliance
// with the License, or, at your option, the Apache License version 2.0.  You may obtain a copy of the License at
//                                        https://solderpad.org/licenses/SHL-2.1/
// Unless required by applicable law or agreed to in writing, any work distributed under the License is distributed on
// an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations under the License.


`ifndef __UVMA_PMA_SB_SV__
`define __UVMA_PMA_SB_SV__

/**
 * Component sampling transactions from a Memory attribution agent for OpenHW Group CORE-V verification testbenches virtual interface (uvma_pma_if).
 */
class uvma_pma_sb_c#(int ILEN=DEFAULT_ILEN,
                     int XLEN=DEFAULT_XLEN) extends uvm_component;

   // Objects
   uvma_pma_cfg_c    cfg;

   // Counters
   int unsigned pma_trn_i_checked_cnt;
   int unsigned pma_trn_d_checked_cnt;

   // TLM exports
   uvm_analysis_imp_rvfi_instr#(uvma_rvfi_instr_seq_item_c#(ILEN,XLEN), uvma_pma_sb_c)  rvfi_instr_export;
   uvm_analysis_export#(uvma_pma_mon_trn_c)                   pma_export;
   uvm_tlm_analysis_fifo #(uvma_pma_mon_trn_c)                pma_fifo;

   `uvm_component_param_utils_begin(uvma_pma_sb_c#(ILEN,XLEN))
      `uvm_field_object(cfg           , UVM_DEFAULT)
      `uvm_field_int(pma_trn_i_checked_cnt, UVM_DEFAULT)
      `uvm_field_int(pma_trn_d_checked_cnt, UVM_DEFAULT)
   `uvm_component_utils_end

   /**
    * Default constructor.
    */
   extern function new(string name="uvma_pma_sb", uvm_component parent=null);

   /**
    * Ensures cfg handle is not null.
    */
   extern virtual function void build_phase(uvm_phase phase);

   /**
    * Oversees monitoring, depending on the reset state, by calling mon_<pre|in|post>_reset() tasks.
    */
   extern virtual task run_phase(uvm_phase phase);

   /**
    * Report stats from checker
    */
   extern virtual function void report_phase(uvm_phase phase);

   /**
    * Print out checked counters when aborting test due to fatal or too many errors
    */
   extern function void pre_abort();

   /**
    * RVFI instructions
    */
   extern virtual function void write_rvfi_instr(uvma_rvfi_instr_seq_item_c#(ILEN,XLEN) instr);

   /**
    *  Check pma_trn instruction
    */
   extern virtual function void write_pma_trn_i(uvma_pma_mon_trn_c pma_trn);

   /**
    * Check pma_trn data
    */
   extern virtual function void write_pma_trn_d(uvma_pma_mon_trn_c pma_trn);

   /**
    * Check an pma_trn instruction fetch for a deconfigured PMA region (PMA disabled)
    */
   extern virtual function void check_pma_trn_i_deconfigured(uvma_pma_mon_trn_c pma_trn);

   /**
    * Check an pma_trn instruction fetch for a mappped region
    */
   extern virtual function void check_pma_trn_i_mapped_region(uvma_pma_mon_trn_c pma_trn, int index);

   /**
    * Check an pma_trn instruction fetch for a default PMA region (PMA enabled, but address does not map to any region)
    */
   extern virtual function void check_pma_trn_i_default_region(uvma_pma_mon_trn_c pma_trn);

   /**
    * Check an pma_trn data accessfor a deconfigured PMA region (PMA disabled)
    */
   extern virtual function void check_pma_trn_d_deconfigured(uvma_pma_mon_trn_c pma_trn, int index);

   /**
    * Check an pma_trn data access for a mappped region
    */
   extern virtual function void check_pma_trn_d_mapped_region(uvma_pma_mon_trn_c pma_trn, int index);

   /**
    * Check an pma_trn data access for a default PMA region (PMA enabled, but address does not map to any region)
    */
   extern virtual function void check_pma_trn_d_default_region(uvma_pma_mon_trn_c pma_trn);

   /**
    * Common print report state
    */
   extern virtual function void print_checked_stats();

endclass : uvma_pma_sb_c


function uvma_pma_sb_c::new(string name="uvma_pma_sb", uvm_component parent=null);

   super.new(name, parent);

endfunction : new


function void uvma_pma_sb_c::build_phase(uvm_phase phase);

   super.build_phase(phase);

   void'(uvm_config_db#(uvma_pma_cfg_c)::get(this, "", "cfg", cfg));
   if (!cfg) begin
      `uvm_fatal("CFG", "Configuration handle is null")
   end

   rvfi_instr_export = new("rvfi_instr_export", this);
   pma_export    = new("pma_export", this);
   pma_fifo      = new("pma_fifo", this);

   this.pma_export.connect(this.pma_fifo.analysis_export);

endfunction : build_phase

task uvma_pma_sb_c::run_phase(uvm_phase phase);

   super.run_phase(phase);

   forever begin
      uvma_pma_mon_trn_c pma_trn;

      pma_fifo.get(pma_trn);

      if(pma_trn.access == UVMA_PMA_ACCESS_INSTR) begin

         write_pma_trn_i(pma_trn);

      end else begin

         write_pma_trn_d(pma_trn);

      end
   end
endtask : run_phase

function void uvma_pma_sb_c::write_rvfi_instr(uvma_rvfi_instr_seq_item_c#(ILEN,XLEN) instr);

endfunction : write_rvfi_instr


function void uvma_pma_sb_c::write_pma_trn_i(uvma_pma_mon_trn_c pma_trn);

   int index;

   // If scoreboard not enabled, then bail out
   if (!cfg.scoreboard_enabled)
      return;

   // Will check this pma_trn
   pma_trn_i_checked_cnt++;

   // If deconfigured then check directly
   if (cfg.regions.size() == 0) begin

      check_pma_trn_i_deconfigured(pma_trn);
      return;
   end

   // Get expected index of the pma_trn transaction
   index = cfg.get_pma_region_for_addr(pma_trn.address);

   // If the region does not map, then we are in the default pma_trn region
   if (index == -1) begin

      check_pma_trn_i_default_region(pma_trn);
      return;
   end

   check_pma_trn_i_mapped_region(pma_trn, index);

endfunction : write_pma_trn_i

function void uvma_pma_sb_c::write_pma_trn_d(uvma_pma_mon_trn_c pma_trn);

   int index;

   // If scoreboard not enabled, then bail out
   if (!cfg.scoreboard_enabled)
      return;

   pma_trn_d_checked_cnt++;
   // Get expected index of the pma_trn transaction
   index = cfg.get_pma_region_for_addr(pma_trn.address);

   // If deconfigured then check directly
   if (cfg.regions.size() == 0) begin

      check_pma_trn_d_deconfigured(pma_trn, index);
      return;
   end


   // If the region does not map, then we are in the default pma_trn region
   if (index == -1) begin
      check_pma_trn_d_default_region(pma_trn);

      return;
   end

   check_pma_trn_d_mapped_region(pma_trn, index);

endfunction : write_pma_trn_d

function void uvma_pma_sb_c::report_phase(uvm_phase phase);

   print_checked_stats();

endfunction : report_phase

function void uvma_pma_sb_c::pre_abort();

   print_checked_stats();

endfunction : pre_abort

function void uvma_pma_sb_c::print_checked_stats();

   `uvm_info("PMASB", $sformatf("checked %0d pma_trn I transactions", pma_trn_i_checked_cnt), UVM_NONE);
   `uvm_info("PMASB", $sformatf("checked %0d pma_trn D transactions", pma_trn_d_checked_cnt), UVM_NONE);

endfunction : print_checked_stats

function void uvma_pma_sb_c::check_pma_trn_i_deconfigured(uvma_pma_mon_trn_c pma_trn);

   // Check: Bufferable bit must be 0 in pma_trn for instruction fetches
   if ((pma_trn.memtype == UVMA_PMA_MEM_NC_NB) || (pma_trn.memtype ==UVMA_PMA_MEM_C_NB )) begin
      `uvm_error("PMA_trnI", $sformatf("pma_trn I %s address: 0x%08x bufferable bit set for deconfigured PMA",
                                       pma_trn.access, pma_trn.address));
   end

   // Check: Cacheable bit must be 0 in pma_trn
   if ((pma_trn.memtype == UVMA_PMA_MEM_NC_NB) || (pma_trn.memtype ==UVMA_PMA_MEM_NC_B)) begin
      `uvm_error("PMA_trnI", $sformatf("pma_trn I %s address: 0x%08x cacheable bit set for deconfigured PMA",
                                       pma_trn.access, pma_trn.address));
   end

   // Check: atomic attributes should be 0
   if (pma_trn.atomic) begin
      `uvm_error("PMA_trnI", $sformatf("pma_trn I %s address: 0x%08x atomic is not zero, pma_trn: 0x%0x",
                                       pma_trn.access.name(), pma_trn.address,
                                       pma_trn.atomic));
   end

endfunction : check_pma_trn_i_deconfigured


 function void uvma_pma_sb_c::check_pma_trn_i_default_region(uvma_pma_mon_trn_c pma_trn);

   // Check: Bufferable bit must be 0 in pma_trn for instruction fetches
   if ((pma_trn.memtype == UVMA_PMA_MEM_NC_B ) || (pma_trn.memtype == UVMA_PMA_MEM_C_B )) begin
      `uvm_error("PMA_trnI", $sformatf("pma_trn I %s address: 0x%08x bufferable bit set for PMA default region",
                                       pma_trn.access.name(), pma_trn.address));
   end

   // Check: Cacheable bit must be 0 in pma_trn
   if ((pma_trn.memtype == UVMA_PMA_MEM_C_NB) || (pma_trn.memtype == UVMA_PMA_MEM_C_B)) begin
      `uvm_error("PMA_trnI", $sformatf("pma_trn I %s address: 0x%08x cacheable bit set for PMA default region",
                                       pma_trn.access.name(), pma_trn.address));
   end

   // Check: atomic attributes should be 0
   if (pma_trn.atomic) begin
      `uvm_error("PMA_trnI", $sformatf("pma_trn I %s address: 0x%08x atomic is not zero, pma_trn: 0x%0x",
                                       pma_trn.access.name(), pma_trn.address,
                                       pma_trn.atomic));
   end

endfunction : check_pma_trn_i_default_region


function void uvma_pma_sb_c::check_pma_trn_i_mapped_region(uvma_pma_mon_trn_c pma_trn, int index);
   // Check: Must be main memory
   if (!cfg.regions[index].main) begin
      `uvm_error("PMA_trnI", $sformatf("pma_trn I %s address: 0x%08x, region: %0d instruction fetch from I/O memory",
                                       pma_trn.access.name(), pma_trn.address, index));
   end

   // Check: Bufferable bit must be 0 in pma_trn for instruction fetches
   if ((pma_trn.memtype == UVMA_PMA_MEM_NC_B ) || (pma_trn.memtype ==UVMA_PMA_MEM_C_B )) begin
      `uvm_error("PMA_trnI", $sformatf("pma_trn I %s address: 0x%08x bufferable bit set for PMA default region",
                                       pma_trn.access.name(), pma_trn.address));
   end

   // Check: Cacheable bit must match memtype[0] in pma_trn
   if ((((pma_trn.memtype == UVMA_PMA_MEM_NC_NB) || (pma_trn.memtype == UVMA_PMA_MEM_NC_B)) && cfg.regions[index].cacheable ==1) || (((pma_trn.memtype == UVMA_PMA_MEM_C_NB) || (pma_trn.memtype == UVMA_PMA_MEM_C_B)) && cfg.regions[index].cacheable ==0)) begin
      `uvm_error("PMA_trnI", $sformatf("pma_trn I %s address: 0x%08x, region: %0d cacheable bit mismatch, pma_trn: %s, PMA: %0d",
                                       pma_trn.access.name(), pma_trn.address, index,
                                       pma_trn.memtype.name(), cfg.regions[index].cacheable));
   end

   // Check: atomic attributes should be 0
   if (pma_trn.atomic) begin
      `uvm_error("PMA_trnI", $sformatf("pma_trn I %s address: 0x%08x, region: %0d atomic is not zero, OBI: 0x%0x",
                                       pma_trn.access.name(), pma_trn.address, index,
                                       pma_trn.atomic));
   end

endfunction : check_pma_trn_i_mapped_region

function void uvma_pma_sb_c::check_pma_trn_d_deconfigured(uvma_pma_mon_trn_c pma_trn, int index);

   // Check: Bufferable bit must be 0 in pma_trn
   if ((pma_trn.memtype == UVMA_PMA_MEM_NC_NB) || (pma_trn.memtype ==UVMA_PMA_MEM_C_NB) ) begin
      `uvm_error("PMA_trnD", $sformatf("pma_trn D %s address: 0x%08x bufferable bit set for PMA default region",
                                       pma_trn.access.name(), pma_trn.address));
   end

   // Check: Cacheable bit must match cacheable flag in pma_trn
   if (((pma_trn.memtype == UVMA_PMA_MEM_NC_NB) || (pma_trn.memtype == UVMA_PMA_MEM_NC_B) && cfg.regions[index].cacheable ==1) || ((pma_trn.memtype == UVMA_PMA_MEM_C_NB) || (pma_trn.memtype == UVMA_PMA_MEM_C_B) && cfg.regions[index].cacheable ==0)  ) begin
      `uvm_error("PMA_trnD", $sformatf("pma_trn D %s address: 0x%08x, region: %0d cacheable bit mismatch, pma_trn: %s, PMA: %0d",
                                       pma_trn.access.name(), pma_trn.address, index,
                                       pma_trn.memtype.name(), cfg.regions[index].cacheable));
   end

endfunction : check_pma_trn_d_deconfigured

function void uvma_pma_sb_c::check_pma_trn_d_default_region(uvma_pma_mon_trn_c pma_trn);

   // Check: Bufferable bit must be 0 in pma_trn for data loads
   if ((pma_trn.memtype == UVMA_PMA_MEM_NC_NB ) || (pma_trn.memtype == UVMA_PMA_MEM_C_NB )) begin
      `uvm_error("PMA_trnD", $sformatf("pma_trn D %s address: 0x%08x bufferable bit set for PMA default region",
                                       pma_trn.access.name(), pma_trn.address));
   end

   // Check: Cacheable bit must be 0 in pma_trn
   if ((pma_trn.memtype == UVMA_PMA_MEM_NC_NB) || (pma_trn.memtype == UVMA_PMA_MEM_NC_B)) begin
      `uvm_error("PMA_trnD", $sformatf("pma_trn D %s address: 0x%08x cacheable bit set for PMA default region",
                                       pma_trn.access.name(), pma_trn.address));
   end

   // Check: atomic attributes should be 0
   if (pma_trn.atomic) begin
      `uvm_error("PMA_trnD", $sformatf("pma_trn D %s address: 0x%08x atomic is not zero, pma_trn: 0x%0x",
                                       pma_trn.access.name(), pma_trn.address,
                                       pma_trn.atomic));
   end

endfunction : check_pma_trn_d_default_region


function void uvma_pma_sb_c::check_pma_trn_d_mapped_region(uvma_pma_mon_trn_c pma_trn, int index);

   if (pma_trn.rw == UVMA_PMA_RW_READ) begin
      // Check: Bufferable bit must be 0 in pma_trn for data loads
      if ((pma_trn.memtype == UVMA_PMA_MEM_NC_B ) || (pma_trn.memtype == UVMA_PMA_MEM_C_B )) begin
         `uvm_error("PMA_trnD", $sformatf("pma_trn D %s address: 0x%08x, region: %0d bufferable bit set for data load",
                                          pma_trn.access.name(), pma_trn.address, index));
      end
   end
   else begin
      // Check: Bufferable bit must match memtype in pma_trn
      if ((((pma_trn.memtype == UVMA_PMA_MEM_NC_NB) || (pma_trn.memtype == UVMA_PMA_MEM_C_NB)) && cfg.regions[index].bufferable ==1) || (((pma_trn.memtype == UVMA_PMA_MEM_C_NB) || (pma_trn.memtype == UVMA_PMA_MEM_C_B)) && cfg.regions[index].bufferable ==0)  ) begin
         `uvm_error("PMA_trnD", $sformatf("OBI D %s address: 0x%08x, region: %0d bufferable bit mismatch, pma_trn: %0d, PMA: %0d",
                                          pma_trn.access.name(), pma_trn.address, index,
                                          pma_trn.memtype.name(), cfg.regions[index].bufferable));
      end
   end

   // Check: Cacheable bit must match memtype in pma_trn
   if ((((pma_trn.memtype == UVMA_PMA_MEM_NC_NB) || (pma_trn.memtype == UVMA_PMA_MEM_NC_B)) && cfg.regions[index].cacheable ==1) || (((pma_trn.memtype == UVMA_PMA_MEM_C_NB) || (pma_trn.memtype == UVMA_PMA_MEM_C_B)) && cfg.regions[index].cacheable ==0)  ) begin
     `uvm_error("PMA_trnD", $sformatf("pma_trn D %s address: 0x%08x, region: %0d cacheable bit mismatch, pma_trn: %s, PMA: %0d",
                                       pma_trn.access.name(), pma_trn.address, index,
                                       pma_trn.memtype.name(), cfg.regions[index].cacheable));
   end

   // Check: atomic attributes should be 0
   if (pma_trn.atomic) begin
      `uvm_error("PMA_trnD", $sformatf("pma_trn D %s address: 0x%08x, region: %0d atomic is not zero, pma_trn: 0x%0x",
                                       pma_trn.access.name(), pma_trn.address, index,
                                       pma_trn.atomic));
   end

endfunction : check_pma_trn_d_mapped_region

`endif // __UVMA_PMA_SB_SV__
