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

module uvma_obi_memory_assert
  import uvm_pkg::*;
  #(
    parameter int unsigned ADDR_WIDTH  = 32,
    parameter int unsigned DATA_WIDTH  = 32,
    parameter int unsigned AUSER_WIDTH = 0,
    parameter int unsigned WUSER_WIDTH = 0,
    parameter int unsigned RUSER_WIDTH = 0,
    parameter int unsigned ID_WIDTH    = 0,
    parameter int unsigned ACHK_WIDTH  = 0,
    parameter int unsigned RCHK_WIDTH  = 0,
    parameter bit          IS_1P2      = 0
  )
  (
    input                    clk,
    input                    reset_n,

    // A bus 1P1
    input                    req,
    input                    gnt,
    input [ADDR_WIDTH-1:0]   addr,
    input                    we,
    input [DATA_WIDTH/8-1:0] be,
    input [DATA_WIDTH-1:0]   wdata,

    // A bus 1P2
    input [((AUSER_WIDTH == 0) ? 0 : AUSER_WIDTH - 1) : 0] auser,
    input [((WUSER_WIDTH == 0) ? 0 : WUSER_WIDTH - 1) : 0] wuser,
    input [((ID_WIDTH == 0) ? 0 : ID_WIDTH - 1) : 0]       aid,
    input [5:0]              atop,
    input [1:0]              memtype,
    input [2:0]              prot,
    input                    reqpar,
    input                    gntpar,
    input [((ACHK_WIDTH == 0) ? 0 : ACHK_WIDTH - 1) : 0] achk,

    // R bus 1P1
    input [DATA_WIDTH-1:0]   rdata,
    input                    rvalid,

    // R bus 1P2
    input                    rready,
    input                    err,
    input [((RUSER_WIDTH == 0) ? 0 : RUSER_WIDTH - 1) : 0] ruser,
    input [((ID_WIDTH == 0) ? 0 : ID_WIDTH - 1) : 0]       rid,
    input                    exokay,
    input                    rvalidpar,
    input                    rreadypar,
    input [((RCHK_WIDTH == 0) ? 0 : RCHK_WIDTH - 1) : 0] rchk
  );

  // ---------------------------------------------------------------------------
  // Local parameters
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // Local variables
  // ---------------------------------------------------------------------------
  string info_tag = "OBIMEMASRT";

  wire valid_a_phase;
  wire valid_r_phase;

  // ---------------------------------------------------------------------------
  // Clocking blocks
  // ---------------------------------------------------------------------------

  // Single clock, single reset design, use default clocking
  default clocking @(posedge clk); endclocking
  default disable iff !(reset_n);

  // ---------------------------------------------------------------------------
  // Begin module code
  // ---------------------------------------------------------------------------

  // If this is 1P2 generate the 1p2 assertion module
  generate if (IS_1P2) begin : gen_1p2
    uvma_obi_memory_1p2_assert#(
      .ADDR_WIDTH(ADDR_WIDTH),
      .DATA_WIDTH(DATA_WIDTH),
      .AUSER_WIDTH(AUSER_WIDTH),
      .WUSER_WIDTH(WUSER_WIDTH),
      .RUSER_WIDTH(RUSER_WIDTH),
      .ID_WIDTH(ID_WIDTH),
      .ACHK_WIDTH(ACHK_WIDTH),
      .RCHK_WIDTH(RCHK_WIDTH)
    ) u_1p2_assert(.atop   ('0), // todo: remove a-ext related signals
                   .exokay ('0), //
                   .*);
  end
  endgenerate

  // Modeling logic and common decoding
  assign valid_a_phase = req && gnt;
  assign valid_r_phase = rvalid;

  // R-3.1.1 : A phase signals stable during address phase
  property p_addr_signal_stable(sig);
    req ##0 !gnt |=> $stable(sig);
  endproperty : p_addr_signal_stable

  a_addr_stable: assert property(p_addr_signal_stable(addr))
  else
    `uvm_error(info_tag, "addr signal not stable in address phase")
  c_addr_stable : cover property(p_addr_signal_stable(addr));

  a_we_stable: assert property(p_addr_signal_stable(we))
  else
    `uvm_error(info_tag, "we signal not stable in address phase")
  c_we_stable : cover property(p_addr_signal_stable(we));

  a_wdata_stable: assert property(p_addr_signal_stable(wdata))
  else
    `uvm_error(info_tag, "wdata signal not stable in address phase")
  c_wdata_stable : cover property(p_addr_signal_stable(wdata));

  a_be_stable: assert property(p_addr_signal_stable(be))
  else
    `uvm_error(info_tag, "be signal not stable in address phase")
  c_be_stable : cover property(p_addr_signal_stable(be));

  // R-3.1.2 : Req may not deassewrt until the gnt is asserted
  property p_req_until_gnt;
    req ##0 !gnt |=> req;
  endproperty : p_req_until_gnt
  a_req_until_gnt : assert property(p_req_until_gnt)
  else
    `uvm_error(info_tag, "req may not deassert until gnt asserted")
  c_req_until_gnt : cover property(p_req_until_gnt);

  // These next 2 are not strictly a functional requirement, but the testbench should simulate this
  // Therefore these are coded as a set of cover properties

  // R-3.2.1 : slave shall be allowed to de-assert (retract) gnt at any time even if req is deasserted
  property p_gnt_assert_no_req;
    !req ##0 !gnt ##1 !req ##0 gnt;
  endproperty : p_gnt_assert_no_req
  c_gnt_assert_no_req : cover property(p_gnt_assert_no_req);

  // R-3.2.2 : slave shall be allowed to de-assert (retract) gnt at any time even if req is deasserted
  property p_gnt_deassert_no_req;
    !req ##0 gnt ##1 !req ##0 !gnt;
  endproperty : p_gnt_deassert_no_req
  c_gnt_deassert_no_req : cover property(p_gnt_deassert_no_req);

  // R-5 ensure that rvalid is never asserted before or coincident to its address phase
  // Model outstanding accepted addresses. OBI does not limit their number.
  int unsigned outstanding_trn_cnt;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      outstanding_trn_cnt <= 0;
    end
    else begin
      if (valid_a_phase && !valid_r_phase)
        outstanding_trn_cnt <= outstanding_trn_cnt + 1;
      else if (!valid_a_phase && valid_r_phase)
        outstanding_trn_cnt <= outstanding_trn_cnt - 1;
    end
  end

  property p_r_after_a;
    rvalid |-> outstanding_trn_cnt != 0;
  endproperty : p_r_after_a
  a_r_after_a : assert property(p_r_after_a)
  else
    `uvm_error(info_tag, "response phase started before address phase")
  c_r_after_a : cover property (p_r_after_a);

  // R-7 At least one byte enable must be set
  property p_be_not_zero;
    req |-> be != 0;
  endproperty : p_be_not_zero
  a_be_not_zero : assert property(p_be_not_zero)
  else
    `uvm_error(info_tag, "be was zero during an address cycle")
  c_be_not_zero : cover property (p_be_not_zero);

  // R-7 All ones must be contiguous during the address phase
  reg[7:0] contiguous_be[] = {
    8'b00000001,
    8'b00000011,
    8'b00000111,
    8'b00001111,
    8'b00011111,
    8'b00111111,
    8'b01111111,
    8'b11111111,
    8'b00000010,
    8'b00000110,
    8'b00001110,
    8'b00011110,
    8'b00111110,
    8'b01111110,
    8'b11111110,
    8'b00000100,
    8'b00001100,
    8'b00011100,
    8'b00111100,
    8'b01111100,
    8'b11111100,
    8'b00001000,
    8'b00011000,
    8'b00111000,
    8'b01111000,
    8'b11111000,
    8'b00010000,
    8'b00110000,
    8'b01110000,
    8'b11110000,
    8'b00100000,
    8'b01100000,
    8'b11100000,
    8'b01000000,
    8'b11000000,
    8'b10000000
  };
  bit be_inside_contiguous_be;
  always_comb begin
    be_inside_contiguous_be = be inside {contiguous_be};
  end
  property p_be_contiguous;
    req |-> be_inside_contiguous_be;
  endproperty : p_be_contiguous
  a_be_contiguous : assert property(p_be_contiguous)
  else
    `uvm_error(info_tag, $sformatf("be of 0x%0x was not contiguous", $sampled(be)));
  c_be_contiguous : cover property (p_be_contiguous);

  // R-8 Data address LSBs must be consistent with byte enables on writes
  function bit [2:0] get_addr_lsb(bit[7:0] be);
    casex (be)
      8'b???????1: return 0;
      8'b??????10: return 1;
      8'b?????100: return 2;
      8'b????1000: return 3;
      8'b???10000: return 4;
      8'b??100000: return 5;
      8'b?1000000: return 6;
      8'b10000000: return 7;
    endcase
  endfunction : get_addr_lsb

  // R-8 Address LSBs must be consistent with byte enables during the address phase
  property p_addr_be_consistent;
    req |-> addr[DATA_WIDTH/32:0] <= get_addr_lsb(be);
  endproperty : p_addr_be_consistent
  a_addr_be_consistent: assert property(p_addr_be_consistent)
  else
    `uvm_error(info_tag, $sformatf("be of 0x%01x not consistent with addr 0x%08x", $sampled(be), $sampled(addr)));
  c_addr_be_consistent : cover property (p_addr_be_consistent);


endmodule : uvma_obi_memory_assert

