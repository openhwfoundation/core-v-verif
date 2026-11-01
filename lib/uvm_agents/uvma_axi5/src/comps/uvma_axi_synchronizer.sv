// Copyright 2023 Thales DIS SAS
//
// Licensed under the Solderpad Hardware Licence, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.0
// You may obtain a copy of the License at https://solderpad.org/licenses/
//
// Original Author: Alae Eddine EZ ZEJJARI (alae-eddine.ez-zejjari@external.thalesgroup.com) – sub-contractor MU-Electronics for Thales group


`ifndef __UVMA_AXI_SYNCHRONIZER_SV__
`define __UVMA_AXI_SYNCHRONIZER_SV__

/**
 * Component that prepares the request for sequences to facilitate response generation.
 */
class uvma_axi_synchronizer_c extends uvm_component;

   `uvm_component_utils(uvma_axi_synchronizer_c)

   //Object
   uvma_axi_cntxt_c  cntxt;
   uvma_axi_cfg_c    cfg;

   // Sequence items queue
   static uvma_axi_transaction_c w_trs_queue[int][$];
   static uvma_axi_transaction_c r_trs_queue[int][$];
   static uvma_axi_transaction_c w_trs_item_bp[$];

   // Exclusive transactions queue
   static uvma_axi_transaction_c exclusive_r_access[int][$];
   static uvma_axi_transaction_c exclusive_w_access[int][$];
   static int exclusive_addr[int];

   // Queue of finished transactions
   static int w_finished_trs_id[$];
   static int r_finished_trs_id[$];

   static int w_trs_class[$];

   int  outstanding_read_call_times  = 0;
   int  outstanding_write_call_times = 0;

   int  last_outoforder_if = -1;
   int  count_outoforder   = -1;

   /**
    * Default constructor.
    */
   extern function new(string name = "uvma_axi_synchronizer_c", uvm_component parent);

   /**
    * 1. Ensures cntxt handles are not null
    * 2. Builds all components
    */
   extern virtual function void build_phase(uvm_phase phase);

   /**
    * 1. Add transaction to w_trs_queue
    * 2. Change the state of the transaction for each transfer
    */
   extern virtual task add_w_trs(uvma_axi_transaction_c axi_witem);

   /**
    * 1. Add transaction to r_trs_queue
    * 2. Change the state of the transaction for each transfer
    */
   extern virtual task add_r_trs(uvma_axi_transaction_c axi_ritem);

   /**
    * List all write transfer that is ready to write in the memory
    */
   extern virtual task write_data();

   /**
    * change the state of transaction for each read response
    */
   extern virtual function void read_data_complete(int selected_id);

   /**
    * 1. prepare a transaction to send it to other component
    * 2. Delete the completed transactions the transaction from r queue
    */
   extern virtual function void read_burst_complete(int selected_id);

   /**
    * 1. prepare a transaction to send it to other component
    * 2. Delete the completed transactions the transaction from w queue
    */
   extern virtual function void write_burst_complete(int selected_id);

   /**
    * Return the b_resp of an exclusive write access
    */
   extern virtual function int check_exclusive_resp(int selected_id);

   /**
    * Standard method to select the Write ID from a table
    */
   extern virtual function int w_select_id(int tab[]);

   /**
    * Standard method to select the READ ID from a table
    */
   extern virtual task r_select_id(int tab[], output int selected);

   /**
    * Standard method to select the READ ID from a table
    */
   extern virtual task read_data(int selected_id);

   /**
    * Standard api to read data from the memory
    */
   extern virtual task memory_read_access_api(ref uvma_axi_transaction_c axi_item, output longint read_data);

   /**
    * Standard api to write data in the memory
    */
   extern virtual task memory_write_access_api(uvma_axi_transaction_c axi_item);

   /**
    * API to write single axi transfer in the memory
    * take in input the address of access the number of bytes to write, the write data and the write mask
    * The mask is extracted from the strob and is used if we want to mask a byte into the data
    */
   extern virtual task mem_write_transfer_api(uvma_axi_transaction_c axi_item, uvma_axi_sig_addr_t write_address, uvma_axi_sig_data_t write_data, int size, uvma_axi_sig_wstrb_t mask, int item_index);

   /**
    * API to read single axi transfer from the memory
    * take in input the address of access and the number of bytes to read
    * The output read data contain the returned data
    */
   extern virtual task mem_read_transfer_api(ref uvma_axi_transaction_c axi_item, input uvma_axi_sig_addr_t read_address, input int size, output longint read_data);

   /**
   * check the memory access permission
   */
   extern virtual function int check_memory_access(uvma_axi_transaction_c axi_item);

endclass : uvma_axi_synchronizer_c


function uvma_axi_synchronizer_c::new(string name = "uvma_axi_synchronizer_c", uvm_component parent);

      super.new(name, parent);

endfunction


function void uvma_axi_synchronizer_c::build_phase(uvm_phase phase);

   super.build_phase(phase);

   void'(uvm_config_db#(uvma_axi_cntxt_c)::get(this, "", "cntxt", cntxt));
      if (cntxt == null) begin
         `uvm_fatal("build_phase", "monitor cntxt class failed")
      end

   void'(uvm_config_db#(uvma_axi_cfg_c)::get(this, "", "cfg", cfg));
      if (cfg == null) begin
         `uvm_fatal("build_phase", "monitor cfg class failed")
      end

endfunction


task uvma_axi_synchronizer_c::add_w_trs(uvma_axi_transaction_c axi_witem);

   uvma_axi_transaction_c  last_w_req;
   uvma_axi_transaction_c  axi_item;
   int size;
   int index;
   longint addr, Aligned_Address, Lower_Wrap_Boundary, Upper_Wrap_Boundary;
   int Number_Bytes, dtsize;
   bit aligned;

   last_w_req = uvma_axi_transaction_c::type_id::create("last_w_req");
   axi_item = uvma_axi_transaction_c::type_id::create("axi_item");
   $cast(axi_item, axi_witem.clone());

   if(axi_item.m_txn_type == UVMA_AXI_WRITE_ADD_REQ) begin

      if(w_trs_queue.size() > 0) begin
         index = w_trs_queue[axi_item.m_id].size();
      end else index = 0;

      size = w_trs_queue[axi_item.m_id].size();
      addr = axi_item.m_addr; // Variable for current address
      Number_Bytes = 2**axi_item.m_size;
      Aligned_Address = (longint'(addr/Number_Bytes) * Number_Bytes);
      aligned = (Aligned_Address == addr); // Check whether addr is aligned to nbytes
      dtsize = Number_Bytes * axi_item.m_len; // Maximum total data transaction size
      if (axi_item.m_burst == 2) begin
         Lower_Wrap_Boundary = (longint'(addr/dtsize) * dtsize);
         // addr must be aligned for a wrapping burst
         Upper_Wrap_Boundary = Lower_Wrap_Boundary + dtsize;
      end

      for(int j=0; j < axi_item.m_len+1; j++) begin

         axi_item.lower_byte_lane = addr - (longint'(addr/(MAX_ADDR_WIDTH/8))) * (MAX_ADDR_WIDTH/8);
         if (aligned)
            axi_item.upper_byte_lane = axi_item.lower_byte_lane + Number_Bytes - 1;
         else
            axi_item.upper_byte_lane = Aligned_Address + Number_Bytes - 1 - (longint'(addr/(MAX_ADDR_WIDTH/8))) * (MAX_ADDR_WIDTH/8);

         axi_item.m_addr =  addr - addr%(MAX_ADDR_WIDTH/8);

         w_trs_queue[axi_item.m_id][w_trs_queue[axi_item.m_id].size()] = new axi_item;
         w_trs_queue[axi_item.m_id][size + j].m_trs_status = ADDR_DATA_NOT_COMPLETE;

         // Increment address if necessary
         if (axi_item.m_burst != 0) begin
            if (aligned) begin
               addr = addr + Number_Bytes;
               if (axi_item.m_burst == 2 && addr >= Upper_Wrap_Boundary) addr = Lower_Wrap_Boundary;
            end else begin
               addr = Aligned_Address + Number_Bytes;
               aligned = 1; // All transfers after the first are aligned
            end
         end
      end
      w_trs_class.push_back(axi_item.m_id);

      if(w_trs_item_bp.size() > 0) begin

         do begin
            w_trs_queue[axi_item.m_id][index].m_data.push_back(w_trs_item_bp[0].m_data[0]);
            w_trs_queue[axi_item.m_id][index].m_wstrb.push_back(w_trs_item_bp[0].m_wstrb[0]);
            w_trs_queue[axi_item.m_id][index].m_last.push_back(w_trs_item_bp[0].m_last[0]);
            w_trs_queue[axi_item.m_id][index].m_x_user.push_back(w_trs_item_bp[0].m_x_user[0]);
            w_trs_queue[axi_item.m_id][index].m_trs_status = ADDR_DATA_COMPLETE;
            last_w_req = new w_trs_item_bp[0];
            w_trs_item_bp.delete(0);
            index++;
         end while(w_trs_item_bp.size() > 0 && !last_w_req.m_last[0]);

         if(last_w_req.m_last[0] == 1) begin
            w_trs_class.delete(0);
         end
      end
   end else begin
      if(w_trs_queue.size() > 0 && w_trs_queue[w_trs_class[0]].size() > 0 && w_trs_queue[w_trs_class[0]][$].m_trs_status == ADDR_DATA_NOT_COMPLETE) begin

         `uvm_info( "Core Test", $sformatf("NEW W_TRS"), UVM_HIGH)
         foreach(w_trs_queue[w_trs_class[0]][i]) begin
            if(w_trs_queue[w_trs_class[0]][i].m_trs_status == ADDR_DATA_NOT_COMPLETE) begin

               w_trs_queue[w_trs_class[0]][i].m_data.push_back(axi_item.m_data[0]);
               w_trs_queue[w_trs_class[0]][i].m_wstrb.push_back(axi_item.m_wstrb[0]);
               w_trs_queue[w_trs_class[0]][i].m_last.push_back(axi_item.m_last[0]);
               w_trs_queue[w_trs_class[0]][i].m_x_user.push_back(axi_item.m_x_user[0]);
               w_trs_queue[w_trs_class[0]][i].m_trs_status = ADDR_DATA_COMPLETE;
               if(axi_item.m_last[0]) begin
                  w_trs_class.delete(0);
               end
               break;
            end
         end
      end else begin
         w_trs_item_bp.push_back(axi_item);
      end
   end
   write_data();

endtask : add_w_trs


task uvma_axi_synchronizer_c::add_r_trs(uvma_axi_transaction_c axi_ritem);

   longint addr, Aligned_Address, Lower_Wrap_Boundary, Upper_Wrap_Boundary;
   int Number_Bytes, dtsize;
   bit aligned;
   uvma_axi_transaction_c axi_item;
   longint init_data = 0;

   axi_item = uvma_axi_transaction_c::type_id::create("axi_item");
   $cast(axi_item, axi_ritem.clone());

   addr = axi_item.m_addr; // Variable for current address
   Number_Bytes = 2**axi_item.m_size;
   Aligned_Address = (int'(addr/Number_Bytes) * Number_Bytes);
   aligned = (Aligned_Address == addr); // Check whether addr is aligned to nbytes
   dtsize = Number_Bytes * axi_item.m_len; // Maximum total data transaction size
   if (axi_item.m_burst == 2) begin
      Lower_Wrap_Boundary = (int'(addr/dtsize) * dtsize);
      // addr must be aligned for a wrapping burst
      Upper_Wrap_Boundary = Lower_Wrap_Boundary + dtsize;
   end

   for(int i=0; i < axi_item.m_len+1; i++) begin

      axi_item.lower_byte_lane = addr - (int'(addr/(MAX_ADDR_WIDTH/8))) * (MAX_ADDR_WIDTH/8);
      if (aligned)
         axi_item.upper_byte_lane = axi_item.lower_byte_lane + Number_Bytes - 1;
      else
         axi_item.upper_byte_lane = Aligned_Address + Number_Bytes - 1 - (int'(addr/(MAX_ADDR_WIDTH/8))) * (MAX_ADDR_WIDTH/8);

      axi_item.m_addr =  addr - addr%(MAX_ADDR_WIDTH/8);

      r_trs_queue[axi_item.m_id][r_trs_queue[axi_item.m_id].size()] = new axi_item;

      if(i == axi_item.m_len) begin
         r_trs_queue[axi_item.m_id][r_trs_queue[axi_item.m_id].size()-1].m_last.push_back(1);
         r_trs_queue[axi_item.m_id][r_trs_queue[axi_item.m_id].size()-1].m_trs_status = ADDR_DATA_NOT_COMPLETE;
         end else begin
         r_trs_queue[axi_item.m_id][r_trs_queue[axi_item.m_id].size()-1].m_last.push_back(0);
         r_trs_queue[axi_item.m_id][r_trs_queue[axi_item.m_id].size()-1].m_trs_status = ADDR_DATA_NOT_COMPLETE;
      end

      if(axi_item.m_lock) begin
         r_trs_queue[axi_item.m_id][r_trs_queue[axi_item.m_id].size()-1].m_resp.push_back(1);
         exclusive_addr[r_trs_queue[axi_item.m_id][r_trs_queue[axi_item.m_id].size()-1].m_addr] = 1;
      end else r_trs_queue[axi_item.m_id][r_trs_queue[axi_item.m_id].size()-1].m_resp.push_back(0);
      r_trs_queue[axi_item.m_id][r_trs_queue[axi_item.m_id].size()-1].m_x_user.push_back(0);
      r_trs_queue[axi_item.m_id][r_trs_queue[axi_item.m_id].size()-1].m_txn_type = UVMA_AXI_READ_RSP;
      r_trs_queue[axi_item.m_id][r_trs_queue[axi_item.m_id].size()-1].m_data[0] = init_data;

      // Increment address if necessary
      if (axi_item.m_burst != 0) begin
         if (aligned) begin
            addr = addr + Number_Bytes;
            if (axi_item.m_burst == 2 && addr >= Upper_Wrap_Boundary) addr = Lower_Wrap_Boundary;
         end else begin
            addr = Aligned_Address + Number_Bytes;
            aligned = 1; // All transfers after the first are aligned
         end
      end
   end
   r_finished_trs_id.push_back(axi_item.m_id);

endtask : add_r_trs


task uvma_axi_synchronizer_c::write_data();

   longint exclusive_data;
   longint original_data;
   uvma_axi_transaction_c ex_r_data;
   int last_trs = -1;
   int checkexclusive;
   uvma_axi_sig_wstrb_t data_mask  = 0;
   uvma_axi_sig_data_t  data_write = 0;
   int index = 0;

   ex_r_data = uvma_axi_transaction_c::type_id::create("ex_r_data");

   foreach(w_trs_queue[i]) begin
      for(int j = 0; j < w_trs_queue[i].size(); j++) begin

         if(w_trs_queue[i][j].m_trs_status == ADDR_DATA_COMPLETE) begin
            if(exclusive_addr[w_trs_queue[i][j].m_addr] == 1) exclusive_addr[w_trs_queue[i][j].m_addr] = -1;
            if(w_trs_queue[i][j].m_lock == 1 && cfg.axi_lock_enabled) begin

               `uvm_info(get_type_name(), $sformatf("EXCLUSIVE ACCESS"), UVM_HIGH)
               checkexclusive = 1;

               if(exclusive_w_access[w_trs_queue[i][j].m_id].size() > 0) begin
                  if(exclusive_w_access[w_trs_queue[i][j].m_id][$].m_last[0] == 1) begin
                     exclusive_w_access[w_trs_queue[i][j].m_id].delete();
                     exclusive_w_access[w_trs_queue[i][j].m_id].push_back(w_trs_queue[i][j]);
                  end
               end else begin
                  exclusive_w_access[w_trs_queue[i][j].m_id].push_back(w_trs_queue[i][j]);
               end

               foreach(exclusive_r_access[w_trs_queue[i][j].m_id][k]) begin
                  ex_r_data = new exclusive_r_access[w_trs_queue[i][j].m_id][k];
                  if(ex_r_data.m_addr == w_trs_queue[i][j].m_addr && ex_r_data.lower_byte_lane == w_trs_queue[i][j].lower_byte_lane && ex_r_data.upper_byte_lane == w_trs_queue[i][j].upper_byte_lane) begin
                     original_data = ex_r_data.m_data[0];
                     last_trs = k;
                     `uvm_info(get_type_name(), $sformatf("find first match trs req"), UVM_HIGH)
                     break;
                  end
               end
               checkexclusive = 1;
               if(exclusive_addr[w_trs_queue[i][j].m_addr] == -1) checkexclusive = 0;

               if(last_trs == -1) begin
                  checkexclusive = -1;
               end

               if(checkexclusive == 1) begin
                  exclusive_w_access[w_trs_queue[i][j].m_id][exclusive_w_access[w_trs_queue[i][j].m_id].size()-1].m_resp.push_back(1);
                  foreach(exclusive_r_access[w_trs_queue[i][j].m_id][k]) begin
                     if(k >= last_trs && last_trs != -1 && k < (exclusive_r_access[w_trs_queue[i][j].m_id].size()-1)) begin
                        exclusive_r_access[w_trs_queue[i][j].m_id][k] =  exclusive_r_access[w_trs_queue[i][j].m_id][k+1];
                     end
                  end
                  exclusive_r_access[w_trs_queue[i][j].m_id].delete(exclusive_r_access[w_trs_queue[i][j].m_id].size()-1);
               end else begin
                  exclusive_w_access[w_trs_queue[i][j].m_id][exclusive_w_access[w_trs_queue[i][j].m_id].size()-1].m_resp.push_back(0);
               end
               last_trs = -1;
            end else begin
               `uvm_info(get_type_name(), $sformatf("NORMAL ACCESS"), UVM_HIGH)
               checkexclusive = 1;
            end
            w_trs_queue[i][j].m_trs_status = WAITING_RESP;

            if(check_memory_access(w_trs_queue[i][j]) == 1) begin
               if(checkexclusive == 1) begin
                  if(cfg.external_mem) begin
                     if(w_trs_queue[i][j].m_last[0] == 1) begin
                        if(j > 0 && w_trs_queue[i][j-1].m_last[$] == 0) begin
                           w_trs_queue[i][j-1].m_data.push_back(w_trs_queue[i][j].m_data[0]);
                           w_trs_queue[i][j-1].m_last.push_back(w_trs_queue[i][j].m_last[0]);
                           w_trs_queue[i][j-1].m_wstrb.push_back(w_trs_queue[i][j].m_wstrb[0]);
                            w_trs_queue[i].delete(j);
                           memory_write_access_api(w_trs_queue[i][j-1]);
                        end else begin
                           memory_write_access_api(w_trs_queue[i][j]);
                        end
                        w_finished_trs_id.push_back(w_trs_queue[i][j].m_id);
                     end else begin
                        if(j > 0 && w_trs_queue[i][j-1].m_last[$] == 0) begin
                            w_trs_queue[i][j-1].m_data.push_back(w_trs_queue[i][j].m_data[0]);
                            w_trs_queue[i][j-1].m_last.push_back(w_trs_queue[i][j].m_last[0]);
                            w_trs_queue[i][j-1].m_wstrb.push_back(w_trs_queue[i][j].m_wstrb[0]);
                            w_trs_queue[i].delete(j);
                        end
                     end
                  end else begin
                     for(int k = w_trs_queue[i][j].lower_byte_lane; k <= w_trs_queue[i][j].upper_byte_lane; k++) begin
                        data_mask[index] = w_trs_queue[i][j].m_wstrb[0][k];
                        data_write[((index+1)*8-1)-:8] = w_trs_queue[i][j].m_data[0][((k+1)*8-1)-:8];
                        index++;
                     end
                     index = 0;
                     mem_write_transfer_api(w_trs_queue[i][j], w_trs_queue[i][j].m_addr + w_trs_queue[i][j].lower_byte_lane, data_write, w_trs_queue[i][j].upper_byte_lane - w_trs_queue[i][j].lower_byte_lane, data_mask, 0);
                     if(w_trs_queue[i][j].m_last[0] == 1)  w_finished_trs_id.push_back(w_trs_queue[i][j].m_id);
                  end
               end else if(checkexclusive == 0) begin
                  `uvm_error(get_full_name(), "The memory location has been modified by another master");
               end else begin
                  `uvm_error(get_full_name(), "We cannot find any read exclusive access with the same parameters");
               end
            end else begin
               `uvm_error(get_full_name(), "YOU CAN NOT WRITE DATA IN THIS ADDRESS LOCATION")
            end
         end
      end
   end

endtask : write_data


function void uvma_axi_synchronizer_c::write_burst_complete(int selected_id);

   int length;

   if(check_exclusive_resp(selected_id) == 1 || check_exclusive_resp(selected_id) == 0) begin
      `uvm_info(get_type_name(), $sformatf("Finish exclusive transaction"), UVM_HIGH)
      exclusive_w_access[selected_id].delete();
   end

   foreach(w_finished_trs_id[i]) begin
      if(w_finished_trs_id[i] == selected_id) begin
         w_finished_trs_id.delete(i);
         break;
      end
   end

   length = w_trs_queue[selected_id][0].m_len;
   for(int i = 0; i <= length; i++) begin
      w_trs_queue[selected_id].delete(0);
   end

endfunction : write_burst_complete


function void uvma_axi_synchronizer_c::read_data_complete(int selected_id);

   foreach(r_trs_queue[selected_id][i]) begin
      if(r_trs_queue[selected_id][i].m_trs_status == WAITING_RESP) begin
         r_trs_queue[selected_id][i].m_trs_status = ADDR_DATA_COMPLETE;
         if(r_trs_queue[selected_id][i].m_lock) begin
            if(exclusive_r_access[selected_id].size() > 0) begin
               if(exclusive_r_access[selected_id][exclusive_r_access[selected_id].size() - 1].m_last[0] == 1) begin
                  exclusive_r_access[selected_id].delete();
                  exclusive_r_access[selected_id][exclusive_r_access[selected_id].size()] = new r_trs_queue[selected_id][i];
               end else begin
                  exclusive_r_access[selected_id][exclusive_r_access[selected_id].size()] = new r_trs_queue[selected_id][i];
               end
            end else begin
               exclusive_r_access[selected_id][exclusive_r_access[selected_id].size()] = new r_trs_queue[selected_id][i];
            end
            `uvm_info( "uvma_axi_synchronizer_c", $sformatf("add exclyusive read trs with id = %d", selected_id), UVM_HIGH)
         end
         break;
      end
   end

endfunction : read_data_complete

function void uvma_axi_synchronizer_c::read_burst_complete(int selected_id);

   int length;

   foreach(r_trs_queue[selected_id][i]) begin
      if(r_trs_queue[selected_id][i].m_trs_status == WAITING_RESP) begin
         if(r_trs_queue[selected_id][i].m_lock) begin
            if(exclusive_r_access[selected_id].size() > 0) begin
               if(exclusive_r_access[selected_id][exclusive_r_access[selected_id].size() - 1].m_last[0] == 1) begin
                  exclusive_r_access[selected_id].delete();
                  exclusive_r_access[selected_id][exclusive_r_access[selected_id].size()] = new r_trs_queue[selected_id][i];
               end else begin
                  exclusive_r_access[selected_id][exclusive_r_access[selected_id].size()] = new r_trs_queue[selected_id][i];
               end
            end
            else begin
               exclusive_r_access[selected_id][exclusive_r_access[selected_id].size()] = new r_trs_queue[selected_id][i];
            end
            `uvm_info( "uvma_axi_synchronizer_c", $sformatf("add exclyusive read trs with id = %d", selected_id), UVM_HIGH)
         end
         break;
      end
   end

   length = r_trs_queue[selected_id][0].m_len;
   for(int i = 0; i <= length; i++) begin
      r_trs_queue[selected_id].delete(0);
   end

   foreach(r_finished_trs_id[i]) begin
      if(r_finished_trs_id[i] == selected_id) begin
         r_finished_trs_id.delete(i);
         break;
      end
   end

endfunction : read_burst_complete


function int uvma_axi_synchronizer_c::check_exclusive_resp(int selected_id);
   int exc_resp = -1;

   if(w_trs_queue[selected_id][0].m_lock == 1) begin
      exc_resp = 1;
      foreach(exclusive_w_access[selected_id][i]) begin
         if(exclusive_w_access[selected_id][i].m_resp[0] != 1) begin
            exc_resp = 0;
            `uvm_info(get_type_name(), $sformatf("Find resp don't match"), UVM_HIGH)
            break;
         end
         if(exclusive_w_access[selected_id][i].m_last[0]) begin
            break;
         end
      end
   end

   return exc_resp;

endfunction : check_exclusive_resp


function int uvma_axi_synchronizer_c::w_select_id(int tab[]);

   int selected;
   int ind_slct;
   case (cfg.ordering_write_mode)
      UVMA_AXI_ORDERING_MODE_RANDOM : begin
         if(tab.size() >= cfg.max_outstanding_write_trs) begin
            ind_slct = $urandom_range(0, tab.size() - 1);
            selected = tab[ind_slct];
            outstanding_write_call_times = 0;
         end else begin
            selected = -1;
            if(tab.size() < cfg.max_outstanding_write_trs && tab.size() != 0) begin
               outstanding_write_call_times++;
               if(outstanding_write_call_times == cfg.max_write_response_latency) begin
                  selected = tab[0];
                  outstanding_write_call_times = 0;
               end
            end
         end
      end
      UVMA_AXI_OUTSTANDING_MODE : begin

         if(tab.size() >= cfg.max_outstanding_write_trs) begin

            `uvm_info(get_type_name(), $sformatf("double transaction ready"), UVM_HIGH)
            outstanding_write_call_times = 0;
            selected = tab[0];

         end else begin

            selected = -1;
            if(tab.size() < cfg.max_outstanding_write_trs && tab.size() != 0) begin
               outstanding_write_call_times++;
               if(outstanding_write_call_times == cfg.max_write_response_latency) begin
                  selected = tab[0];
                  outstanding_write_call_times = 0;
               end
            end

         end
      end

      UVMA_AXI_ORDERING_MODE_FIFO : begin

         selected = -1;
         if (tab.size() > 0) begin
            selected = tab[0];
         end

      end
   endcase
   return selected;

endfunction : w_select_id


task uvma_axi_synchronizer_c::r_select_id(int tab[], output int selected);

   int ind_slct;
   case (cfg.ordering_read_mode)
      UVMA_AXI_INTERLEAVING_MODE : begin
         if(tab.size() >= cfg.max_outstanding_read_trs) begin
            ind_slct = $urandom_range(0, tab.size() - 1);
            selected = tab[ind_slct];
            outstanding_read_call_times = 0;
         end else begin
            selected = -1;
            if(tab.size() < cfg.max_outstanding_read_trs && tab.size() != 0) begin
               outstanding_read_call_times++;
               if(outstanding_read_call_times == cfg.max_read_response_latency) begin
                  selected = tab[0];
                  outstanding_read_call_times = 0;
               end
            end
         end
      end

      UVMA_AXI_ORDERING_MODE_RANDOM : begin
         if(tab.size() >= cfg.max_outstanding_read_trs) begin
            if(last_outoforder_if == -1) begin
               ind_slct = $urandom_range(0, tab.size() - 1);
               selected = tab[ind_slct];
               last_outoforder_if = selected;
               outstanding_read_call_times = 0;
               count_outoforder++;
               if(r_trs_queue[selected][0].m_len == count_outoforder) begin
                  last_outoforder_if = -1;
                  count_outoforder = -1;
               end
            end else begin
               selected = last_outoforder_if;
               count_outoforder++;
               if(r_trs_queue[selected][0].m_len == count_outoforder) begin
                  last_outoforder_if = -1;
                  count_outoforder = -1;
               end
            end
         end else begin
            selected = -1;
            if(tab.size() < cfg.max_outstanding_read_trs && tab.size() != 0) begin
               outstanding_read_call_times++;
               if(outstanding_read_call_times == cfg.max_read_response_latency) begin
                  selected = tab[0];
                  last_outoforder_if = selected;
                  count_outoforder++;
                  if(r_trs_queue[selected][0].m_len == count_outoforder) begin
                     last_outoforder_if = -1;
                     count_outoforder = -1;
                  end
                  outstanding_read_call_times = 0;
               end
            end
         end
      end

      UVMA_AXI_OUTSTANDING_MODE : begin

         if(tab.size() >= cfg.max_outstanding_read_trs) begin

            `uvm_info(get_type_name(), $sformatf("double transaction ready"), UVM_HIGH)
            outstanding_read_call_times = 0;
            selected = tab[0];

         end else begin
            `uvm_info(get_type_name(), $sformatf("max_write_response_latency", cfg.max_read_response_latency), UVM_HIGH)
            selected = -1;
            if(tab.size() < cfg.max_outstanding_read_trs && tab.size() != 0) begin

               `uvm_info(get_type_name(), $sformatf("one transaction ready"), UVM_HIGH)
               outstanding_read_call_times++;
               if(outstanding_read_call_times == cfg.max_read_response_latency) begin
                  selected = tab[0];
                  outstanding_read_call_times = 0;
               end

            end
         end
      end

      UVMA_AXI_ORDERING_MODE_FIFO : begin
         selected = -1;
         if (tab.size() != 0) begin
            selected = tab[0];
         end
      end
   endcase

   read_data(selected);

endtask : r_select_id


task uvma_axi_synchronizer_c::read_data(int selected_id);
   int length;
   uvma_axi_sig_data_t data_read = 0;
   int index = 0;

   foreach(r_trs_queue[selected_id][i]) begin
      if(r_trs_queue[selected_id][i].m_trs_status == ADDR_DATA_NOT_COMPLETE) begin
         if(check_memory_access(r_trs_queue[selected_id][i]) == 1) begin
            r_trs_queue[selected_id][i].m_trs_status = WAITING_RESP;
            if(cfg.external_mem) begin
               length = r_trs_queue[selected_id][i].m_len;
               r_trs_queue[selected_id][i].m_len = 0;
               memory_read_access_api(r_trs_queue[selected_id][i], r_trs_queue[selected_id][i].m_data[0]);
               r_trs_queue[selected_id][i].m_len = length;
            end else begin
               mem_read_transfer_api(r_trs_queue[selected_id][i], r_trs_queue[selected_id][i].m_addr + r_trs_queue[selected_id][i].lower_byte_lane, r_trs_queue[selected_id][i].upper_byte_lane - r_trs_queue[selected_id][i].lower_byte_lane, data_read);
               for(int j = r_trs_queue[selected_id][i].lower_byte_lane; j <= r_trs_queue[selected_id][i].upper_byte_lane; j++) begin
                  r_trs_queue[selected_id][i].m_data[0][((j+1)*8-1)-:8]   = data_read[((index+1)*8-1)-:8];
                  index++;
               end
            end
         end else begin
            `uvm_error(get_full_name(), "YOU CAN NOT WRITE DATA IN THIS ADDRESS LOCATION")
         end
         break;
      end
   end

endtask : read_data

task uvma_axi_synchronizer_c::memory_read_access_api(ref uvma_axi_transaction_c axi_item, output longint read_data);
   uvma_axi_sig_data_t data_read = 0;
   int index = 0;

   `uvm_info(get_type_name(), $sformatf("API READ DATA"), UVM_HIGH)
   #10;
   mem_read_transfer_api(axi_item, axi_item.m_addr + axi_item.lower_byte_lane, axi_item.upper_byte_lane - axi_item.lower_byte_lane, data_read);
   for(int j = axi_item.lower_byte_lane; j <= axi_item.upper_byte_lane; j++) begin
      read_data[((j+1)*8-1)-:8] = data_read[((index+1)*8-1)-:8];
      index++;
   end
   index     = 0;
   data_read = 0;

endtask : memory_read_access_api

task uvma_axi_synchronizer_c::memory_write_access_api(uvma_axi_transaction_c axi_item);
   uvma_axi_sig_data_t  data_write = 0;
   uvma_axi_sig_wstrb_t data_mask  = 0;
   int index = 0;

   `uvm_info(get_type_name(), $sformatf("API WRITE DATA"), UVM_HIGH)
   #10;
   for(int i = 0; i <= axi_item.m_len; i++) begin
      for(int j = axi_item.lower_byte_lane; j <= axi_item.upper_byte_lane; j++) begin
         data_mask[index]  = axi_item.m_wstrb[i][j];
         data_write[((index+1)*8-1)-:8] = axi_item.m_data[i][((j+1)*8-1)-:8];
         index++;
      end
      mem_write_transfer_api(axi_item, axi_item.m_addr + axi_item.lower_byte_lane, data_write, axi_item.upper_byte_lane - axi_item.lower_byte_lane, data_mask, i);
      index      = 0;
      data_write = 0;
      data_mask = 0;
   end

endtask : memory_write_access_api

task uvma_axi_synchronizer_c::mem_write_transfer_api(uvma_axi_transaction_c axi_item, uvma_axi_sig_addr_t write_address, uvma_axi_sig_data_t write_data, int size, uvma_axi_sig_wstrb_t mask, int item_index);

   for(int k = 0; k <= size; k++) begin
      if(mask[k]) cntxt.mem.write(write_address + k, write_data[((k+1)*8-1)-:8]);
   end

endtask : mem_write_transfer_api

task uvma_axi_synchronizer_c::mem_read_transfer_api(ref uvma_axi_transaction_c axi_item, input uvma_axi_sig_addr_t read_address, input int size, output longint read_data);

   for(int j = 0; j <= size; j++) begin
      read_data[((j+1)*8-1)-:8]   = cntxt.mem.read(read_address + j);
   end

endtask : mem_read_transfer_api


function int uvma_axi_synchronizer_c::check_memory_access(uvma_axi_transaction_c axi_item);

   int access      = 1;
   bit prot_access = 1;
   bit m_access    = 1;
   int region_index;

   case (axi_item.m_txn_type)
      UVMA_AXI_WRITE_REQ  : begin

         if(cfg.axi_region_enabled) begin
            m_access = cfg.m_part_st[axi_item.m_region].m_type_access[1];
            if(cfg.axi_prot_enabled) begin
               prot_access = cfg.m_part_st[axi_item.m_region].axi_prot_type_access && axi_item.m_prot;
            end
         end else begin
            foreach(cfg.m_part_st[i]) begin
               if( i == cfg.m_part_st.size() -1) begin
                  if(cfg.m_part_st[i].m_part_addr_start <= axi_item.m_addr && cfg.m_addr_end > axi_item.m_addr) begin
                     region_index = i;
                     break;
                  end
               end else begin
                  if(cfg.m_part_st[i].m_part_addr_start <= axi_item.m_addr && cfg.m_part_st[i+1].m_part_addr_start > axi_item.m_addr) begin
                     region_index = i;
                     break;
                  end
               end
            end
            m_access = cfg.m_part_st[region_index].m_type_access[1];
            if(cfg.axi_prot_enabled) begin
               prot_access = cfg.m_part_st[region_index].axi_prot_type_access && axi_item.m_prot;
            end
         end

      end

      UVMA_AXI_READ_REQ  : begin

         if(cfg.axi_region_enabled) begin
            m_access = cfg.m_part_st[axi_item.m_region].m_type_access[0];
            if(cfg.axi_prot_enabled) begin
               prot_access = cfg.m_part_st[axi_item.m_region].axi_prot_type_access && axi_item.m_prot;
            end
         end else begin
            foreach(cfg.m_part_st[i]) begin
               if( i == cfg.m_part_st.size() -1) begin
                  if(cfg.m_part_st[i].m_part_addr_start <= axi_item.m_addr && cfg.m_addr_end > axi_item.m_addr) begin
                     region_index = i;
                     break;
                  end
               end else begin
                  if(cfg.m_part_st[i].m_part_addr_start <= axi_item.m_addr && cfg.m_part_st[i+1].m_part_addr_start > axi_item.m_addr) begin
                     region_index = i;
                     break;
                  end
               end
            end
            m_access = cfg.m_part_st[region_index].m_type_access[0];
            if(cfg.axi_prot_enabled) begin
               prot_access = cfg.m_part_st[region_index].axi_prot_type_access && axi_item.m_prot;
            end
         end

      end
   endcase

   access = m_access && prot_access;

   if(access == 0) begin
      return -1;
   end else begin
      return 1;
   end

endfunction : check_memory_access

`endif //__UVMA_AXI_SYNCHRONIZER_SV__
