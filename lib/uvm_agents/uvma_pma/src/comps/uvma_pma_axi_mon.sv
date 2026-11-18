// Copyright 2021 OpenHW Group
//
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Licensed under the Solderpad Hardware License v 2.1 (the "License"); you may not use this file except in compliance
// with the License, or, at your option, the Apache License version 2.0.  You may obtain a copy of the License at
//                                        https://solderpad.org/licenses/SHL-2.1/
// Unless required by applicable law or agreed to in writing, any work distributed under the License is distributed on
// an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations under the License.


`ifndef __UVMA_PMA_AXI_MON_SV__
`define __UVMA_PMA_AXI_MON_SV__

/**
 * Component sampling transactions from a Memory attribution agent for OpenHW Group CORE-V verification testbenches virtual interface (uvma_pma_if).
 */
 class  uvma_pma_axi_mon_c#(int ILEN=DEFAULT_ILEN, int XLEN=DEFAULT_XLEN) extends uvm_monitor;

   // Objects
   uvma_pma_cfg_c    cfg;

   // TLM ports
   uvm_analysis_port#(uvma_pma_mon_trn_c)  ap;

   // TLM exports
   uvm_analysis_export#(uvma_axi_transaction_c)                   read_axi_export;
   uvm_tlm_analysis_fifo #(uvma_axi_transaction_c)                read_axi_fifo;
   uvm_analysis_export#(uvma_axi_transaction_c)                   write_axi_export;
   uvm_tlm_analysis_fifo #(uvma_axi_transaction_c)                write_axi_fifo;

   uvm_analysis_imp_rvfi_instr#(uvma_rvfi_instr_seq_item_c#(ILEN,XLEN), uvma_pma_axi_mon_c) rvfi_instr_export;

   `uvm_component_param_utils_begin(uvma_pma_axi_mon_c#(ILEN,XLEN))
     `uvm_field_object(cfg  , UVM_DEFAULT)
   `uvm_component_utils_end

   /**
    * Default constructor.
    */
   extern function new(string name="uvma_pma_axi_mon_c", uvm_component parent=null);

   /**
    * 1. Ensures cfg handle is not null.
    * 2. Builds ap.
    */
   extern virtual function void build_phase(uvm_phase phase);

   /**
    * Oversees monitoring, depending on the reset state, by calling mon_<pre|in|post>_reset() tasks.
    */
   extern virtual task run_phase(uvm_phase phase);

   /**
    * RVFI instructions
    */
   extern function void write_rvfi_instr(uvma_rvfi_instr_seq_item_c#(ILEN,XLEN) instr);

   /**
    * axi data
    */
   extern virtual function void write_axi_d(uvma_axi_transaction_c axi);

   /**
    * Appends cfg, prints out trn and issues heartbeat.
    */
   extern virtual function void process_trn(ref uvma_pma_mon_trn_c trn);


 endclass : uvma_pma_axi_mon_c


function uvma_pma_axi_mon_c::new(string name="uvma_pma_axi_mon_c", uvm_component parent=null);

   super.new(name, parent);

endfunction : new


function void uvma_pma_axi_mon_c::build_phase(uvm_phase phase);

   super.build_phase(phase);

   void'(uvm_config_db#(uvma_pma_cfg_c)::get(this, "", "cfg", cfg));
   if (!cfg) begin
      `uvm_fatal("CFG", "Configuration handle is null")
   end

   ap = new("ap", this);

   read_axi_export      = new("read_axi_export", this);
   read_axi_fifo      = new("read_axi_fifo", this);
   write_axi_export      = new("write_axi_export", this);
   write_axi_fifo      = new("write_axi_fifo", this);
   rvfi_instr_export = new("rvfi_instr_export", this);

   this.write_axi_export.connect(this.write_axi_fifo.analysis_export);
   this.read_axi_export.connect(this.read_axi_fifo.analysis_export);

endfunction : build_phase

task uvma_pma_axi_mon_c::run_phase(uvm_phase phase);

   super.run_phase(phase);

   forever begin
      uvma_axi_transaction_c ar_axi_item;
      uvma_axi_transaction_c aw_axi_item;

      fork
         read_axi_fifo.get(ar_axi_item);
         write_axi_fifo.get(aw_axi_item);
      join_any
      disable fork;

      if(ar_axi_item != null)
         write_axi_d(ar_axi_item);
      else
         write_axi_d(aw_axi_item);
   end

endtask : run_phase

function void uvma_pma_axi_mon_c::process_trn(ref uvma_pma_mon_trn_c trn);

   trn.cfg = cfg;
   trn.__originator = get_full_name();
   `uvm_info("${name_uppecase}_MON", $sformatf("Sampled transaction from the virtual interface:\n%s", trn.sprint()), UVM_HIGH)
   `uvml_hrtbt()

endfunction : process_trn

function void uvma_pma_axi_mon_c::write_rvfi_instr(uvma_rvfi_instr_seq_item_c#(ILEN,XLEN) instr);

   // Create a new pma transaction with mapped index region
   uvma_pma_mon_trn_c mon_trn;

   mon_trn              = uvma_pma_mon_trn_c#(ILEN,XLEN)::type_id::create("mon_trn");
   process_trn(mon_trn);
   mon_trn.access       = UVMA_PMA_ACCESS_INSTR;
   mon_trn.rw           = UVMA_PMA_RW_READ;
   mon_trn.region_index = cfg.get_pma_region_for_addr(instr.pc_rdata);
   if (mon_trn.region_index != -1) begin
      mon_trn.is_first_word = ((instr.pc_rdata >> 2) == (cfg.regions[mon_trn.region_index].word_addr_low)) ? 1 : 0;
      mon_trn.is_last_word  = ((instr.pc_rdata >> 2) == (cfg.regions[mon_trn.region_index].word_addr_high - 1)) ? 1 : 0;
   end

   if (mon_trn.region_index == -1 && cfg.regions.size() == 0) begin
      mon_trn.is_default = 1;
   end

      ap.write(mon_trn);

endfunction : write_rvfi_instr

function void uvma_pma_axi_mon_c::write_axi_d(uvma_axi_transaction_c axi);

   // Create a new pma transaction with mapped index region
   uvma_pma_mon_trn_c mon_trn;

   mon_trn               = uvma_pma_mon_trn_c#(ILEN,XLEN)::type_id::create("mon_trn");
   process_trn(mon_trn);
   mon_trn.access        = (axi.m_id == 0)? UVMA_PMA_ACCESS_INSTR : UVMA_PMA_ACCESS_DATA;
   mon_trn.address       =  axi.m_addr;
   mon_trn.rw            = (axi.m_txn_type == UVMA_AXI_WRITE_REQ) ?  UVMA_PMA_RW_WRITE : UVMA_PMA_RW_READ ;
   mon_trn.region_index  = cfg.get_pma_region_for_addr(mon_trn.address);

   case (axi.m_cache)
      0000 : mon_trn.memtype = UVMA_PMA_MEM_C_NB;
      0001, 0011 : mon_trn.memtype = UVMA_PMA_MEM_NC_B;
      1010, 0110, 1110, 1011, 0111, 1111 : mon_trn.memtype = UVMA_PMA_MEM_C_B;
      0010 : mon_trn.memtype = UVMA_PMA_MEM_NC_NB;
   endcase

   if ((axi.m_atop != 0) || (axi.m_lock)) begin
      mon_trn.atomic        = 1;
   end
   else begin
      mon_trn.atomic        = 0;
   end

   if (mon_trn.region_index != -1) begin
      mon_trn.is_first_word = ((mon_trn.address >> 2) == (cfg.regions[mon_trn.region_index].word_addr_low)) ? 1 : 0;
      mon_trn.is_last_word  = ((mon_trn.address >> 2) == (cfg.regions[mon_trn.region_index].word_addr_high - 1)) ? 1 : 0;
   end

   if (mon_trn.region_index == -1) begin
      mon_trn.is_default = 1;
   end

   ap.write(mon_trn);

endfunction : write_axi_d

`endif // __UVMA_PMA_MON_SV__

