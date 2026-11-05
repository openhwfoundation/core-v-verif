// ----------------------------------------------------------------------------
//Copyright 2023 CEA*
//*Commissariat a l'Energie Atomique et aux Energies Alternatives (CEA)
//
//Licensed under the Apache License, Version 2.0 (the "License");
//you may not use this file except in compliance with the License.
//You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
//Unless required by applicable law or agreed to in writing, software
//distributed under the License is distributed on an "AS IS" BASIS,
//WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//See the License for the specific language governing permissions and
//limitations under the License.
//[END OF HEADER]
// ----------------------------------------------------------------------------
// ----------------------------------------------------------------------------
//  Description : Package containing all the covergroup of the axi_superset monitor
//                package
//
// ----------------------------------------------------------------------------

// -----------------------------------------------------------------------
// ACE5-LITE covergroups
// -----------------------------------------------------------------------

// Axi write transaction coverage
covergroup axi_superset_req_cg (ref axi_superset_txn_c packet, int unsigned id_width, int unsigned addr_width);
  option.per_instance = 1;


  // Coverpoint coverage
  cov_id        : coverpoint packet.m_id
  {
    bins zero   = {'h0};
    bins all[8] = {['h1:2**id_width-1]};
    bins one    = {2**id_width};
  }
  cov_addr      : coverpoint packet.m_addr
  {
    bins zero   = {'h0};
    bins all[8] = {['h1:2**addr_width-1]};
    bins one    = {2**addr_width};
  }
  cov_len       : coverpoint packet.m_len       ;
  cov_size      : coverpoint packet.m_size      ;

  // TODO: for the moment, as only the mode INCR is supported, it makes senses to only sample this value.
  // Add other values when they are supported
  cov_burst     : coverpoint packet.m_burst
  {
    bins fixed = {FIXED};
    bins incr  = {INCR};
    bins wrap  = {WRAP};
  }
  cov_lock      : coverpoint packet.m_lock      ;
  cov_cache     : coverpoint packet.m_cache     ;
  cov_prot      : coverpoint packet.m_prot      ;
  cov_qos       : coverpoint packet.m_qos       ;
  cov_region    : coverpoint packet.m_region    ;

  cov_atop      : coverpoint packet.m_atop      ;

  // Cross coverage

endgroup: axi_superset_req_cg

covergroup axi_superset_rsp_cg (ref axi_superset_txn_c packet, int unsigned id_width);
  option.per_instance = 1;
  // Coverpoint coverage
  cov_id : coverpoint packet.m_id
  {
    bins zero   = {'h0};
    bins all[8] = {['h1:2**id_width-1]};
    bins one    = {2**id_width};
  }
  cov_resp : coverpoint packet.m_resp[0]  ;

  // Cross coverage

endgroup: axi_superset_rsp_cg

covergroup axi_superset_dat_cg (int unsigned data_width)
  with function sample( axi_superset_txn_c packet,  int unsigned index );
  option.per_instance = 1;
  // Coverpoint coverage
  cov_data : coverpoint packet.m_data[index]
  {
    bins zero   = {'h0};
    bins all[8] = {['h1:2**data_width-1]};
    bins one    = {2**data_width};
  }
  cov_wstrb : coverpoint packet.m_wstrb[index]
  {
    bins zero   = {'h0};
    bins all[8] = {['h1:2**(data_width/8)-1]};
    bins one    = {2**(data_width/8)};
  }
  cov_resp : coverpoint packet.m_resp[index]  ;

  // Cross coverage

endgroup: axi_superset_dat_cg
