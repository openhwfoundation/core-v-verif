// Copyright 2023 Thales DIS SAS
//
// Licensed under the Solderpad Hardware Licence, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.0
// You may obtain a copy of the License at https://solderpad.org/licenses/
//
// Original Author: Alae Eddine EZ ZEJJARI (alae-eddine.ez-zejjari@external.thalesgroup.com) – sub-contractor MU-Electronics for Thales group


`ifndef __UVMA_AXI_AMO_SYNCHRONIZER_SV__
`define __UVMA_AXI_AMO_SYNCHRONIZER_SV__

/**
 * Component that prepares the request for sequences to facilitate response generation.
 */
class uvma_axi_amo_synchronizer_c extends uvma_axi_synchronizer_c;

   local event atomic_read;
   local longint init_data = -1;

   `uvm_component_utils(uvma_axi_amo_synchronizer_c)

   /**
    * Default constructor.
    */
   extern function new(string name = "uvma_axi_amo_synchronizer_c", uvm_component parent);

   /**
    * 1. Ensures cntxt handles are not null
    * 2. Builds all components
    */
   extern function void build_phase(uvm_phase phase);

   /**
    * List all write transfer that is ready to write in the memory
    */
   extern task write_data();

   /**
    * Standard method to select the READ ID from a table
    */
   extern task read_data(int selected_id);

endclass : uvma_axi_amo_synchronizer_c


function uvma_axi_amo_synchronizer_c::new(string name = "uvma_axi_amo_synchronizer_c", uvm_component parent);

   super.new(name, parent);

endfunction


function void uvma_axi_amo_synchronizer_c::build_phase(uvm_phase phase);

   super.build_phase(phase);

endfunction


task uvma_axi_amo_synchronizer_c::write_data();

   longint data;
   longint new_data;
   longint signed_init_data;
   longint unsigned unsigned_init_data;
   longint signed_new_data;
   longint unsigned unsigned_new_data;
   int size;
   int write_id;

   longint exclusive_data;
   longint original_data;
   uvma_axi_transaction_c ex_r_data;
   int last_trs = -1;
   int checkexclusive;
   bit[7:0] data_mask = 0;
   int index = 0;
   uvma_axi_sig_data_t data_write = 0;
   uvma_axi_sig_data_t data_read  = 0;

   ex_r_data = uvma_axi_transaction_c::type_id::create("ex_r_data");
   foreach(w_trs_queue[i]) begin
      for(int j = 0; j < w_trs_queue[i].size(); j++) begin

         if(w_trs_queue[i][j].m_trs_status == ADDR_DATA_COMPLETE) begin
            //  Exclusive access monitor (AXI A7.2.3): an exclusive read reserves its address
            //  (exclusive_addr = 1); a later plain write to that address breaks the
            //  reservation (-1); an exclusive write succeeds only if the reservation is
            //  still held, and releases it (0).
            if(w_trs_queue[i][j].m_lock == 0 && w_trs_queue[i][j].m_atop == 0 &&
               exclusive_addr[w_trs_queue[i][j].m_addr] == 1) exclusive_addr[w_trs_queue[i][j].m_addr] = -1;

            if(w_trs_queue[i][j].m_atop!=0)begin   // Atomic transaction
               @atomic_read;
               if(init_data == -1) return;

               for(int k = w_trs_queue[i][j].lower_byte_lane; k <= w_trs_queue[i][j].upper_byte_lane; k++) begin
                  new_data[((k+1)*8-1)-:8] = w_trs_queue[i][j].m_data[0][((k+1)*8-1)-:8];
               end

               size = 2**w_trs_queue[i][j].m_size;
               signed_init_data     = signed'(init_data);
               signed_init_data[63] = init_data[(size * 8) - 1];
               unsigned_init_data   = unsigned'(init_data);
               signed_new_data      = signed'(new_data);
               signed_new_data[63]  = new_data[(size * 8) - 1];
               unsigned_new_data    = unsigned'(new_data);

		       if(w_trs_queue[i][j].m_atop[5:4] == 3) begin   // Atomic swap operation
                  for(int k = w_trs_queue[i][j].lower_byte_lane; k <= w_trs_queue[i][j].upper_byte_lane; k++) begin
                    if(w_trs_queue[i][j].m_wstrb[0][k]) data [((k+1)*8-1)-:8] = w_trs_queue[i][j].m_data[0][((k+1)*8-1)-:8];
                  end
               end else if(w_trs_queue[i][j].m_atop[5:4] == 2) begin   //Atomic load operations

		          case (w_trs_queue[i][j].m_atop[2:0])
                     3'b000: begin
                        `uvm_info(get_type_name(), $sformatf("AMO ADD operation"), UVM_HIGH)
                        data = init_data + new_data;
                     end
                     3'b001: begin
                        data = init_data;
                        for(int p = w_trs_queue[i][j].lower_byte_lane*8; p<(w_trs_queue[i][j].upper_byte_lane+1)*8; p++) begin
                           if(new_data[p]) begin
                              data[p] = 1'b0;
                           end
                        end
                     end
                     3'b010: begin
                        data = new_data ^ init_data;
                     end
                     3'b011: begin
                        data = init_data;
                        for(int p = w_trs_queue[i][j].lower_byte_lane*8; p<(w_trs_queue[i][j].upper_byte_lane+1)*8; p++) begin
                           if(new_data[p]) begin
                              data[p] = 1'b1;
                           end
                        end
                     end
                     3'b100: begin
                        data = (signed_new_data >= signed_init_data) ? signed_new_data : signed_init_data;
                     end
                     3'b101: begin
                        data = (signed_new_data >= signed_init_data) ? signed_init_data : signed_new_data;
                     end
                     3'b110: begin
                        data = (unsigned_new_data >= unsigned_init_data) ? unsigned_new_data : unsigned_init_data;
                     end
                     3'b111: begin
                        data = (unsigned_new_data >= unsigned_init_data) ? unsigned_init_data : unsigned_new_data;
                     end
                  endcase

               end

               w_trs_queue[i][j].m_data[0] = data;
               checkexclusive = 1;
               init_data = -1;
            end
            else if(w_trs_queue[i][j].m_lock == 1 && cfg.axi_lock_enabled) begin
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
               exclusive_addr[w_trs_queue[i][j].m_addr] = 0;
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
                           write_id = w_trs_queue[i][j-1].m_id;
                           w_trs_queue[i].delete(j);
                           memory_write_access_api(w_trs_queue[i][j-1]);
                        end else begin
                           write_id = w_trs_queue[i][j].m_id;
                           memory_write_access_api(w_trs_queue[i][j]);
                        end
                        w_finished_trs_id.push_back(write_id);
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


task uvma_axi_amo_synchronizer_c::read_data(int selected_id);
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
            if(r_trs_queue[selected_id][i].m_atop != 0) begin
               init_data = r_trs_queue[selected_id][i].m_data[0];
               ->atomic_read;
            end
         end else begin
            `uvm_error(get_full_name(), "YOU CAN NOT WRITE DATA IN THIS ADDRESS LOCATION")
         end
         break;
      end
   end

endtask : read_data


`endif //__UVMA_AXI_AMO_SYNCHRONIZER_SV__
