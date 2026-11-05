// Copyright 2022 Thales DIS SAS
//
// Licensed under the Solderpad Hardware Licence, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.0
// You may obtain a copy of the License at https://solderpad.org/licenses/
//
// Original Author: Alae Eddine EZ ZEJJARI (alae-eddine.ez-zejjari@external.thalesgroup.com) – sub-contractor MU-Electronics for Thales group

module  uvma_axi_amo_assert (uvma_axi_intf axi_assert);

   import uvm_pkg::*;

/********************************************** Atomic assertion ******************************************************/

   //  Check if atop Signal is not equal to X or Z when AWVALID is HIGH (Section A3.2.2)
   property AXI4_ATOP_X;
      @(posedge axi_assert.clk && axi_assert.axi_amo_assertion_enabled) disable iff (!axi_assert.rst_n) axi_assert.psv_axi_cb.aw_valid |-> (!$isunknown(axi_assert.psv_axi_cb.aw_atop));
   endproperty

  // check if an atomic operation has a burst length greater than one, AWSIZE is full data bus width. (Section E1.1.3)
   property AXI_ATOP_LEN_SIZE;
      @(posedge axi_assert.clk && axi_assert.axi_amo_assertion_enabled) disable iff (!axi_assert.rst_n) (axi_assert.aw_valid && axi_assert.aw_len > 0) |-> 2**axi_assert.aw_size == ($size(axi_assert.w_data)/8);
   endproperty

   // check if AWADDR is aligned to the data size for AtomicStore, AtomicLoad, and AtomicSwap  (Section E1.1.3)
   property AXI_ATOP_ALIGN;
      @(posedge axi_assert.clk && axi_assert.axi_amo_assertion_enabled) disable iff (!axi_assert.rst_n) (axi_assert.aw_valid && (axi_assert.aw_atop[5:4] == 32 || axi_assert.aw_atop[5:4] == 16 || axi_assert.aw_atop == 48)) |-> !((axi_assert.aw_addr) % (2**axi_assert.aw_size));
   endproperty

   // check if the burst type id INCR for AtomicStore, AtomicLoad, and AtomicSwap operations (Section E1.1.3)
   property AXI_ATOP_BURST_INCR;
      @(posedge axi_assert.clk && axi_assert.axi_amo_assertion_enabled) disable iff (!axi_assert.rst_n) (axi_assert.aw_valid && (axi_assert.aw_atop[5:4] == 32 || axi_assert.aw_atop[5:4] == 16 || axi_assert.aw_atop == 48)) |-> axi_assert.aw_burst == 2'b01;
   endproperty

   // check if the write data is 1, 2, 4 or 8 bytes for AtomicStore, AtomicLoad, and AtomicSwap operations (Section E1.1.3)
   property AXI_ATOP_DATA;
      @(posedge axi_assert.clk && axi_assert.axi_amo_assertion_enabled) disable iff (!axi_assert.rst_n) (axi_assert.aw_valid && (axi_assert.aw_atop[5:4] == 32 || axi_assert.aw_atop[5:4] == 16 || axi_assert.aw_atop == 48)) |-> (axi_assert.aw_len + 1) * (2**axi_assert.aw_size) == 2 || (axi_assert.aw_len + 1) * (2**axi_assert.aw_size) == 4 || (axi_assert.aw_len + 1) * (2**axi_assert.aw_size) == 8 || (axi_assert.aw_len + 1) * (2**axi_assert.aw_size) == 1;
   endproperty

   // check if the write data is 2, 4, 8, 16, or 32 bytes for AtomicCompare operation  (Section E1.1.3)
   property AXI_ATOP_COMP_DATA;
      @(posedge axi_assert.clk && axi_assert.axi_amo_assertion_enabled) disable iff (!axi_assert.rst_n) axi_assert.aw_valid && axi_assert.aw_atop == 49 |-> (axi_assert.aw_len + 1) * (2**axi_assert.aw_size) == 2 || (axi_assert.aw_len + 1) * (2**axi_assert.aw_size) == 4 || (axi_assert.aw_len + 1) * (2**axi_assert.aw_size) == 8 || (axi_assert.aw_len + 1) * (2**axi_assert.aw_size) == 16 || (axi_assert.aw_len + 1) * (2**axi_assert.aw_size) == 32;
   endproperty

   // check if an AtomicCompare has an aligned address to a single write data value (Section E1.1.3)
   property AXI_ATOP_COMP_ALIGN;
      @(posedge axi_assert.clk && axi_assert.axi_amo_assertion_enabled) disable iff (!axi_assert.rst_n) (axi_assert.aw_valid && axi_assert.aw_atop == 49) |-> !((axi_assert.aw_addr) % (2**((axi_assert.aw_size * axi_assert.aw_len)/2)));
   endproperty

   // check if an AtomicCompare has an INCR burst type if AWADDR points to the lower half of the transaction and WRAP burst type if AWADDR points to the upper half of the transaction (Section E1.1.3)
   property AXI_ATOP_COMP_BURST;
      @(posedge axi_assert.clk && axi_assert.axi_amo_assertion_enabled) disable iff (!axi_assert.rst_n) (axi_assert.aw_valid && axi_assert.aw_atop == 49) |-> (!((axi_assert.aw_addr) % (2**axi_assert.aw_size)) && axi_assert.aw_burst == 2'b01) || ((axi_assert.aw_addr) % (2**axi_assert.aw_size) > 0 && axi_assert.aw_burst == 2'b11);
   endproperty

   // check if AWLOCK is 0 for Atomic operation  (Section E1.1.3)
   property AXI_ATOP_ACCESS;
      @(posedge axi_assert.clk && axi_assert.axi_amo_assertion_enabled) disable iff (!axi_assert.rst_n) axi_assert.aw_valid && (axi_assert.aw_atop == 49 || axi_assert.aw_atop[5:4] == 32 || axi_assert.aw_atop[5:4] == 16 || axi_assert.aw_atop == 48) |-> axi_assert.aw_lock == 0;
   endproperty


/********************************************** Assert Property ******************************************************/

   amo_atop_x               : assert property (AXI4_ATOP_X)
                         else `uvm_error (" AXI4 protocol checks assertion ", "Violation of AXI4_ATOP_X");

   amo_len_size              : assert property (AXI_ATOP_LEN_SIZE)
                         else `uvm_error (" AXI4 protocol checks assertion ", "Violation of AXI_ATOP_LEN_SIZE");

   amo_align                 : assert property (AXI_ATOP_ALIGN)
                         else `uvm_error (" AXI4 protocol checks assertion ", "Violation of AXI_ATOP_ALIGN");

   amo_burst                 : assert property (AXI_ATOP_BURST_INCR)
                         else `uvm_error (" AXI4 protocol checks assertion ", "Violation of AXI_ATOP_BURST_INCR");

   amo_comp_align            : assert property (AXI_ATOP_COMP_ALIGN)
                         else `uvm_error (" AXI4 protocol checks assertion ", "Violation of AXI_ATOP_COMP_ALIGN");

   amo_comp_burst            : assert property (AXI_ATOP_COMP_BURST)
                         else `uvm_error (" AXI4 protocol checks assertion ", "Violation of AXI_ATOP_COMP_BURST");

   amo_access                : assert property (AXI_ATOP_ACCESS)
                         else `uvm_error (" AXI4 protocol checks assertion ", "Violation of AXI_ATOP_ACCESS");

   amo_data                  : assert property (AXI_ATOP_DATA)
                         else `uvm_error (" AXI4 protocol checks assertion ", "Violation of AXI_ATOP_DATA");

   amo_comp_data             : assert property (AXI_ATOP_COMP_DATA)
                         else `uvm_error (" AXI4 protocol checks assertion ", "Violation of AXI_ATOP_COMP_DATA");

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////


   int ass_aw_id;   //Store aw_id every clock cycle
   //Variable for checking assertion coverage
   int aw_id_tr[];
   int aw_id_amo[];
   int aw_id_len[];
   int state_amo = 0;
   //Variable for checking assertion coverage
   int cov_w_data_num = 0;

   int ar_id_tr[];   //Store the number of transaction
   int ar_len_tr[][];   //Store the length of every burst
   int tab[];
   int ass_ar_id;   //Store ar_id every clock cycle
   int ass_r_id;   //Store ar_id every clock cycle

   int size_aw_id;
   //Variable for checking assertion coverage
   int cov_errs_rid_property;
   int cov_r_last_property = 0;
   int cnt_amo[];
   int size;   //Store transfer size every clock cycle
   int s = 0;

   // Check if the number of write data items matches AWLEN for the corresponding address (Section A3.4.1)
   always @(posedge axi_assert.clk && axi_assert.axi_amo_assertion_enabled) begin

      if(axi_assert.rst_n) begin

         ass_aw_id  = signed'(axi_assert.aw_id);
         size_aw_id = signed'(aw_id_tr.size());
         if(axi_assert.aw_valid && axi_assert.aw_ready && axi_assert.aw_atop != 0) begin

            if(size_aw_id <= ass_aw_id) begin
               aw_id_tr = new[ass_aw_id+1] (aw_id_tr);
               aw_id_tr[ass_aw_id] = 1;
               if(axi_assert.aw_atop[5:4] != 1) begin
                  aw_id_len = new[ass_aw_id+1] (aw_id_len);
                  aw_id_len[ass_aw_id] = axi_assert.aw_len + 1;
                  aw_id_amo = new[ass_aw_id+1] (aw_id_amo);
                  aw_id_amo[ass_aw_id] = axi_assert.aw_atop;
               end
            end else begin
               aw_id_tr[ass_aw_id] = aw_id_tr[ass_aw_id] + 1;
               if(axi_assert.aw_atop[5:4] != 1) begin
                  aw_id_amo[ass_aw_id] = axi_assert.aw_atop;
                  aw_id_len[ass_aw_id] = axi_assert.aw_len + 1;
               end
            end
            if(axi_assert.aw_atop[5:4] != 1) begin
               state_amo++;
            end

            // Check if the ID used to identify an Atomic transactions has not been used for other transactions that are outstanding at the same time (Section E1.1.4)
            w_amo_id : assert(aw_id_tr[ass_aw_id] == 1) begin
               cov_w_data_num++;
            end else begin
               `uvm_error("AXI4 protocol checks assertion", "Violation of w_data_num");
               cov_w_data_num++;
            end

         end
         if(axi_assert.b_valid && axi_assert.b_ready && axi_assert.aw_atop[5:4] == 1) begin
            aw_id_tr[axi_assert.b_id]--;
         end
      end
   end


   always @(posedge axi_assert.clk && axi_assert.axi_amo_assertion_enabled) begin
      if(axi_assert.rst_n) begin
         ass_ar_id = signed'(axi_assert.ar_id);
         size = signed'(ar_id_tr.size());
         if(axi_assert.ar_valid && axi_assert.ar_ready) begin
            if(size <= ass_ar_id) begin
               `uvm_info("AXI4 protocol checks assertion", "new ID", UVM_HIGH)
               ar_id_tr = new[ass_ar_id+1] (ar_id_tr);
               ar_id_tr[ass_ar_id] = 1;
               ar_len_tr = new[ass_ar_id+1] (ar_len_tr);
               ar_len_tr[ass_ar_id] = new[1];
               ar_len_tr[ass_ar_id][0] = signed'(axi_assert.ar_len+1);
            end else begin
               `uvm_info("AXI4 protocol checks assertion", "new TR", UVM_HIGH)
               ar_id_tr[ass_ar_id] = ar_id_tr[ass_ar_id] + 1;
               ar_len_tr[ass_ar_id] = new[ar_id_tr[ass_ar_id]] (ar_len_tr[ass_ar_id]);
               ar_len_tr[ass_ar_id][ar_id_tr[ass_ar_id]-1] = signed'(axi_assert.ar_len+1);
            end
         end
         ass_r_id = signed'(axi_assert.r_id);
         if(axi_assert.r_valid && axi_assert.r_ready) begin
            //  A read data beat belongs to an outstanding read of its ID (A5.2), otherwise to
            //  an outstanding atomic transaction of that ID (E1.1.4), otherwise it is an error.
            if(ass_r_id < ar_len_tr.size() && ar_len_tr[ass_r_id].size() > 0 &&
               ar_len_tr[ass_r_id][0] >= 1) begin
               ar_len_tr[ass_r_id][0] = ar_len_tr[ass_r_id][0] - 1;
               cov_errs_rid_property++;
            end else begin
               // In cas that we don't have any read outstanding transaction we check if there is an atomic outstanding transaction with the same ID
               if(aw_id_tr[ass_r_id] > 0 && state_amo >= 1) begin
                  s = 1;
               end else begin
                  `uvm_error("AXI4 protocol checks assertion", "Violation of axi4_errs_rid");
               end
               cov_errs_rid_property++;
            end
            if(s == 1) begin
               if(cnt_amo.size() <= ass_r_id) begin
                  cnt_amo = new[ass_r_id+1] (cnt_amo);
                  cnt_amo[ass_r_id]++;
               end else begin
                  cnt_amo[ass_r_id]++;
               end
               // Check if the ID used to identify an Atomic transactions response data has not been used for other read transactions that are outstanding at the same time (Section E1.1.4)
               r_amo_id : assert(ar_id_tr[ass_r_id] == 0 || ar_id_tr.size() <= ass_r_id) else begin
                  `uvm_error("AXI4 protocol checks assertion", "Violation of r_amo_id_assert");
               end
               if(axi_assert.r_last) begin
                  if(aw_id_amo [ass_r_id] == 49) begin
                     // check if the length of the read transaction is equal to half of the write transaction, for AtomicCompare. (Section E1.1.3)
                     amo_r_comp_len : assert(cnt_amo[ass_r_id] == aw_id_len[ass_r_id]/2) else begin
                        `uvm_error("AXI4 protocol checks assertion", "Violation of r_amo_len_assert");
                     end
                     cnt_amo[ass_r_id] = cnt_amo[ass_r_id] - aw_id_len[ass_r_id]/2;
                  end else begin
                     // check if the length of the read transaction is equal to the write transaction, for other Atomic operation. (Section E1.1.3)
                     amo_comp_len : assert(cnt_amo[ass_r_id] == aw_id_len[ass_r_id]) else begin
                        `uvm_error("AXI4 protocol checks assertion", "Violation of r_amo_len_assert");
                     end
                     cnt_amo[ass_r_id] = cnt_amo[ass_r_id] - aw_id_len[ass_r_id];
                  end
                  state_amo--;
                  aw_id_tr[ass_r_id] = 0;
                  aw_id_amo[ass_r_id] = 0;
                  aw_id_len[ass_r_id] = 0;
               end
               s = 0;
            end else begin
               if(ar_len_tr[ass_r_id][0] == 0) begin
                  tab = new[ar_id_tr[ass_r_id]];
                  ar_id_tr[ass_r_id]--;
                  foreach(ar_len_tr[i,j]) begin
                     tab[j] = ar_len_tr[ass_r_id][j];
                  end
                  for(int i = 0; i<tab.size(); i++) begin
                     ar_len_tr[ass_r_id][i] = tab[i+1];
                  end
               end
            end
         end
      end
   end

endmodule : uvma_axi_amo_assert
