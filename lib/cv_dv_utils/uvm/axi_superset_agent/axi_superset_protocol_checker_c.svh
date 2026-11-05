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
//  Description : Collect request/response from the monitor and the response
//                model and compare them to verify the axi_superset protocol
//
// ----------------------------------------------------------------------------

// -----------------------------------------------------------------------
// Class axi_superset_protocol_checker_c
// -----------------------------------------------------------------------
class axi_superset_protocol_checker_c extends uvm_scoreboard;

  `uvm_component_utils(axi_superset_protocol_checker_c)

  protected string name                ;
  event            reset_asserted      ;
  event            reset_deasserted    ;
  protected bit    covergroup_enable   ;

  // Variable to configure the memory map concerning the scoreboard instance
  protected int    bus_size            ;

  // Typedef
  typedef struct {
    axi_superset_txn_c excl_txn ;
    logic              modified ;
  } exclusive_db ;

  // -----------------------------------------------------------------------
  // Analysis Ports
  // -----------------------------------------------------------------------
  uvm_tlm_analysis_fifo #(axi_superset_txn_c) m_write_req_packets_collected ;
  uvm_tlm_analysis_fifo #(axi_superset_txn_c) m_read_req_packets_collected  ;
  uvm_tlm_analysis_fifo #(axi_superset_txn_c) m_write_rsp_packets_collected ;
  uvm_tlm_analysis_fifo #(axi_superset_txn_c) m_read_rsp_packets_collected  ;

  // -----------------------------------------------------------------------
  // Data Structures to store axi_superset/chi req/rsp
  // -----------------------------------------------------------------------
  // Data structure to store analysis port outputs
  axi_superset_txn_c m_wreq_packet ;
  axi_superset_txn_c m_rreq_packet ;
  axi_superset_txn_c m_wrsp_packet ;
  axi_superset_txn_c m_rrsp_packet ;

  // Associative array to store transaction
  axi_superset_txn_c m_read_txn_db[axi_sig_id_t][$]  ;
  axi_superset_txn_c m_write_txn_db[axi_sig_id_t][$] ;

  // Associative array to monitor exclusive accesses
  exclusive_db m_exclusive_txn_db[axi_sig_id_t]  ;

  // -----------------------------------------------------------------------
  // Coverage covergroups
  // -----------------------------------------------------------------------
  // Covergroup
  axi_superset_req_cg   m_axi_superset_read_req_cg  ;
  axi_superset_req_cg   m_axi_superset_write_req_cg ;
  axi_superset_rsp_cg   m_axi_superset_read_rsp_cg  ;
  axi_superset_rsp_cg   m_axi_superset_write_rsp_cg ;
  axi_superset_dat_cg   m_axi_superset_read_dat_cg  ;
  axi_superset_dat_cg   m_axi_superset_write_dat_cg ;

  // Packets for the covergroup
  axi_superset_txn_c  m_axi_superset_read_req_packet  ;
  axi_superset_txn_c  m_axi_superset_write_req_packet ;
  axi_superset_txn_c  m_axi_superset_read_rsp_packet  ;
  axi_superset_txn_c  m_axi_superset_write_rsp_packet ;
  axi_superset_txn_c  m_axi_superset_read_dat_packet  ;
  axi_superset_txn_c  m_axi_superset_write_dat_packet ;

  // -----------------------------------------------------------------------
  // Counter for the number of request/response
  // -----------------------------------------------------------------------
  protected int m_count_read_req  ;
  protected int m_count_write_req ;
  protected int m_count_read_rsp  ;
  protected int m_count_write_rsp ;

  // -----------------------------------------------------------------------
  // Counters for expected responses. In case of some ATOPs, one request
  // gives rise to both read and write responses
  // -----------------------------------------------------------------------
  protected int m_count_exp_read_rsp;
  protected int m_count_exp_write_rsp;

  // -----------------------------------------------------------------------
  // Counter for the total number of bytes
  // -----------------------------------------------------------------------
  protected int m_write_bytes ;
  protected int m_read_bytes  ;

  // -----------------------------------------------------------------------
  // Agent configuration
  // -----------------------------------------------------------------------
  axi_superset_config_c  m_agent_config ;

  // ------------------------------------------------------------------------
  // Constructor
  // ------------------------------------------------------------------------
  function new(string name, uvm_component parent);
        super.new(name, parent);
        this.name = name;


  endfunction: new

  // ------------------------------------------------------------------------
  // Function set/get
  // ------------------------------------------------------------------------
  // AGENT CONFIGURATION
  function axi_superset_config_c get_agent_config();
    get_agent_config = m_agent_config  ;
  endfunction : get_agent_config

  function void set_agent_config( axi_superset_config_c config_i );
    `uvm_info(this.name,
              $sformatf("Setting the agent configuraiton CFG=%0s", config_i.convert2string() ),
              UVM_DEBUG)
    m_agent_config = config_i ;
  endfunction: set_agent_config

  // -----------------------------------------------------------------------
  // Build Phase
  // -----------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
      int unsigned id_width   ;
      int unsigned addr_width ;
      int unsigned data_width ;

      super.build_phase(phase);

      covergroup_enable = m_agent_config.get_covergroup_enable();

      // Covergroup bus size configuration
      id_width         = m_agent_config.get_txn_config().get_id_width();
      addr_width       = m_agent_config.get_txn_config().get_addr_width();
      data_width       = m_agent_config.get_txn_config().get_data_width();

      // Initialisation of the uvm_tlm_analysis_fifo for axi_superset interface
      m_write_req_packets_collected = new("m_write_req_packets_collected" , this) ;
      m_read_req_packets_collected  = new("m_read_req_packets_collected"  , this) ;
      m_write_rsp_packets_collected = new("m_write_rsp_packets_collected" , this) ;
      m_read_rsp_packets_collected  = new("m_read_rsp_packets_collected"  , this) ;

      // Initialisation of the axi_superset packets for the covergroups
      m_wreq_packet = axi_superset_txn_c::type_id::create("m_wreq_packet" , this) ;
      m_rreq_packet = axi_superset_txn_c::type_id::create("m_rreq_packet" , this) ;
      m_wrsp_packet = axi_superset_txn_c::type_id::create("m_wrsp_packet" , this) ;
      m_rrsp_packet = axi_superset_txn_c::type_id::create("m_rrsp_packet" , this) ;
 
      if ( covergroup_enable ) begin
        // Instantiation of the packet for the covergroups
        m_axi_superset_read_req_packet  = new("m_axi_superset_read_req_packet"  ) ;
        m_axi_superset_write_req_packet = new("m_axi_superset_write_req_packet" ) ;
        m_axi_superset_read_rsp_packet  = new("m_axi_superset_read_rsp_packet"  ) ;
        m_axi_superset_write_rsp_packet = new("m_axi_superset_write_rsp_packet" ) ;
        m_axi_superset_read_dat_packet  = new("m_axi_superset_read_dat_packet"  ) ;
        m_axi_superset_write_dat_packet = new("m_axi_superset_write_dat_packet" ) ;

         // Creation of covergroups
        m_axi_superset_read_req_cg  = new( m_axi_superset_read_req_packet  , id_width , addr_width) ;
        m_axi_superset_write_req_cg = new( m_axi_superset_write_req_packet , id_width , addr_width) ;
        m_axi_superset_read_rsp_cg  = new( m_axi_superset_read_rsp_packet  , id_width ) ;
        m_axi_superset_write_rsp_cg = new( m_axi_superset_write_rsp_packet , id_width ) ;
        m_axi_superset_read_dat_cg  = new( data_width ) ;
        m_axi_superset_write_dat_cg = new( data_width ) ;

        m_axi_superset_read_req_cg.option.name  = $sformatf("%0s_read_req_cg"  , this.name) ;
        m_axi_superset_write_req_cg.option.name = $sformatf("%0s_write_req_cg" , this.name) ;
        m_axi_superset_read_rsp_cg.option.name  = $sformatf("%0s_read_rsp_cg"  , this.name) ;
        m_axi_superset_write_rsp_cg.option.name = $sformatf("%0s_write_rsp_cg" , this.name) ;
        m_axi_superset_read_dat_cg.option.name  = $sformatf("%0s_read_dat_cg"  , this.name) ;
        m_axi_superset_write_dat_cg.option.name = $sformatf("%0s_write_dat_cg" , this.name) ;

        // Deactivating some coverpoints for some covergroup
        m_axi_superset_write_req_cg.cov_atop.option.weight = 0 ;
        m_axi_superset_read_rsp_cg.cov_resp.option.weight  = 0 ;
        m_axi_superset_read_dat_cg.cov_wstrb.option.weight = 0 ;
        m_axi_superset_write_dat_cg.cov_resp.option.weight = 0 ;
      end // covergroup_enable

      // Initialisation of the counters of the testbench
      // axi_superset transactions counters
      m_count_read_req  = 0 ;
      m_count_write_req = 0 ;
      m_count_read_rsp  = 0 ;
      m_count_write_rsp = 0 ;

      m_count_exp_read_rsp  = 0 ;
      m_count_exp_write_rsp = 0 ;

      // Number of bytes counters
      m_write_bytes = 0 ;
      m_read_bytes  = 0 ;

      `uvm_info(this.name, "Build stage complete.", UVM_LOW)
  endfunction: build_phase
  
  // ------------------------------------------------------------------------
  // Pre reset phase
  // ------------------------------------------------------------------------
  virtual task pre_reset_phase(uvm_phase phase);
      -> reset_asserted;
      `uvm_info(this.name, "Pre Reset stage complete.", UVM_LOW)
  endtask : pre_reset_phase

  // ------------------------------------------------------------------------
  // Reset phase
  // ------------------------------------------------------------------------
  task reset_phase(uvm_phase phase );
    super.reset_phase(phase);

    // Flushing the axi_superset uvm_tlm_analysis_fifo
    m_write_req_packets_collected.flush() ;
    m_read_req_packets_collected.flush()  ;
    m_write_rsp_packets_collected.flush() ;
    m_read_rsp_packets_collected.flush()  ;

    // Reset of the associative arrays
    m_read_txn_db.delete()  ;
    m_write_txn_db.delete() ;

      // Initialisation of the counters of the testbench
      // axi_superset transactions counters
      m_count_read_req  = 0 ;
      m_count_write_req = 0 ;
      m_count_read_rsp  = 0 ;
      m_count_write_rsp = 0 ;

      m_count_exp_read_rsp  = 0 ;
      m_count_exp_write_rsp = 0 ;

      // Number of bytes counters
      m_write_bytes = 0 ;
      m_read_bytes  = 0 ;
    `uvm_info(this.name, "Reset stage complete.", UVM_LOW)
  endtask: reset_phase
  
  // ------------------------------------------------------------------------
  // Post reset phase
  // ------------------------------------------------------------------------
  virtual task post_reset_phase(uvm_phase phase);
    -> reset_deasserted;
    `uvm_info(this.name, "Post Reset stage complete.", UVM_LOW)
  endtask : post_reset_phase

  // -----------------------------------------------------------------------
  // Run Phase
  // -----------------------------------------------------------------------
  virtual task run_phase(uvm_phase phase);
      super.run_phase(phase);
      forever begin
        @(reset_deasserted);
        fork

          collect_write_req ( phase ) ;
          collect_read_req  ( phase ) ;
          collect_write_rsp ( phase ) ;
          collect_read_rsp  ( phase ) ;

        join_none
        @(reset_asserted);
        disable fork;
      end
  endtask: run_phase


  // -----------------------------------------------------------------------
  // -----------------------------------------------------------------------
  // Interface tasks 
  // -----------------------------------------------------------------------
  // -----------------------------------------------------------------------

  // -----------------------------------------------------------------------
  // Task collect_write_req
  //
  // Collect input write requests from the axi interface
  // -----------------------------------------------------------------------
  virtual task collect_write_req( uvm_phase phase );
    axi_superset_txn_c  write_req;

    forever begin
        // Wait to receive a packet from the analysis port and store it in the
        // m_axi_superset_req_packet data structure
        m_write_req_packets_collected.get(m_wreq_packet);

        // Creating a new object to store the input packet data structure,
        // before storing it inside a queue
        write_req = new;
        $cast(write_req, m_wreq_packet.clone());

        // Monitoring exclusives
        monitor_exclusive_addresses ( write_req );

        // Verification of the axi_superset write request
        check_write_req ( write_req );

        // Register the axi_superset transaction in an associative array
        m_write_txn_db[write_req.m_id].push_front(write_req);

        if ( covergroup_enable ) begin
          // Sample write metada for the coverage
          $cast( m_axi_superset_write_req_packet, write_req.clone() );
          m_axi_superset_write_req_cg.sample( );
          // Sample write data for the coverage
          $cast( m_axi_superset_write_dat_packet, write_req.clone() );
          foreach ( m_axi_superset_write_dat_packet.m_data[i] )
            m_axi_superset_write_dat_cg.sample( m_axi_superset_write_dat_packet, i );
        end

        // Increment write request counter
        m_count_write_req++;
        m_count_exp_write_rsp++;

    end // forever
  endtask: collect_write_req

  // -----------------------------------------------------------------------
  // Task collect_read_req
  //
  // Collect input read requests from the axi interface
  // -----------------------------------------------------------------------
  virtual task collect_read_req( uvm_phase phase );
    string ids_s;
    axi_superset_txn_c  read_req;

    forever begin
        // Wait to receive a packet from the analysis port and store it in the
        // m_req_packet data structure
        m_read_req_packets_collected.get(m_rreq_packet);

        // Creating a new object to store the input packet data structure,
        // before storing it inside a queue
        read_req = new;
        $cast(read_req, m_rreq_packet.clone());

        // Verification of the axi read request
        check_read_req ( read_req );

        // Register the axi transaction in an associative array
        m_read_txn_db[read_req.m_id].push_front(read_req);

        if ( covergroup_enable ) begin
          // Sample for the coverage
          $cast( m_axi_superset_read_req_packet, read_req.clone() );
          m_axi_superset_read_req_cg.sample( );
        end

        // Increment read request counter
        m_count_read_req++;
        m_count_exp_read_rsp++;

    end // forever
  endtask: collect_read_req

  // -----------------------------------------------------------------------
  // Task collect_write_rsp
  //
  // Collect input write response from the axi interface
  // -----------------------------------------------------------------------
  virtual task collect_write_rsp( uvm_phase phase );
    axi_superset_txn_c  write_rsp;

    forever begin
        // Wait to receive a packet from the analysis port and store it in the
        // m_rsp_packet data structure
        m_write_rsp_packets_collected.get( m_wrsp_packet );

        // Creating a new object to store the response packet information,
        // before storing it inside a queue
        write_rsp = new;
        $cast( write_rsp, m_wrsp_packet.clone() );

        // Verification of the axi write response
        check_write_rsp ( write_rsp );

        if ( covergroup_enable ) begin
          // Sample for the coverage
          $cast( m_axi_superset_write_rsp_packet, write_rsp.clone() );
          m_axi_superset_write_rsp_cg.sample( );
        end

        // Increment the write rsp counter
        m_count_write_rsp++;

    end
  endtask : collect_write_rsp

  // -----------------------------------------------------------------------
  // Task collect_read_rsp
  //
  // Collect input read response from the axi interface
  // -----------------------------------------------------------------------
  virtual task collect_read_rsp( uvm_phase phase );
    axi_superset_txn_c  read_rsp;

    forever begin
        // Wait to receive a packet from the analysis port and store it in the
        // m_rsp_packet data structure
        m_read_rsp_packets_collected.get( m_rrsp_packet );

        // Creating a new object to store the response packet information,
        // before storing it inside a queue
        read_rsp = new;
        $cast( read_rsp, m_rrsp_packet.clone() );
        
        // If the rsp is the last of its burst, increment the corresponding
        // counter and register the event for the perf mon
        // Call the corresponding task to compare requests/responses
        check_read_rsp ( read_rsp );

        if ( covergroup_enable ) begin
          // Sample for the coverage
          // Sample read response metadata
          $cast( m_axi_superset_read_rsp_packet, read_rsp.clone() );
          m_axi_superset_read_rsp_cg.sample( );
          // Sample read payload
          $cast( m_axi_superset_read_dat_packet, read_rsp.clone() );
          foreach( read_rsp.m_data[i] ) 
            m_axi_superset_read_dat_cg.sample( m_axi_superset_read_dat_packet,i );
        end

        // Increment the read rsp counter
        m_count_read_rsp++;

    end
  endtask : collect_read_rsp


  // -----------------------------------------------------------------------
  // -----------------------------------------------------------------------
  //
  // VERIFICATION TASKS
  //
  // -----------------------------------------------------------------------
  // -----------------------------------------------------------------------

  // -----------------------------------------------------------------------
  // Task check_write_req
  //
  // Compare the corresponding write request from the source to the write
  // request received on the dest interface
  // -----------------------------------------------------------------------
  task check_write_req ( 
    axi_superset_txn_c  write_req
  );
    int nb_flits   ; // Number of flits of data of the transaction
    int bus_nbytes ; // Number of bytes of the data bus
    int nb_bytes   ; // Maximum number of bytes of the transaction for each flit of data

    // Variables used for the byte lane computing
    axi_sig_addr_t aligned_addr, address_n ;
    axi_sig_addr_t wrap_boundary ;
    int flag_wrap  ;

    // Computing some values necessary for the verification of the transaction
    nb_flits   = write_req.m_len + 1 ;
    bus_nbytes = m_agent_config.get_txn_config().get_data_width()/8 ;
    nb_bytes   = 2**write_req.m_size ;

    // If the unique id is configured in the agent, and that the ID of the
    // transaction alwritey exist, print an error.
    if ( m_agent_config.get_id_management_enable() ) begin
      if ( m_write_txn_db.exists(write_req.m_id) )
        `uvm_error(this.name,
          $sformatf("The agent was configured to generate only for unique ID, and the ID=%0h(h) is currently also used by another write transaction", write_req.m_id) )
    end

    // Check the number of flit of data
    if ( write_req.m_data.size() != nb_flits ) begin
      `uvm_error(this.name,
        $sformatf("Number of flits of data are not matching: WRITE_REQ=%0d(d) WRITE_REQ_LEN=%0h(h) ; WRITE_REQ_DATA=%0p(p)",
                  m_count_write_req,
                  write_req.m_len,
                  write_req.m_data ) )
    end

    // Check the number of flit of wstrb
    if ( write_req.m_wstrb.size() != nb_flits ) begin
      `uvm_error(this.name,
        $sformatf("Number of flits of wstrb are not matching: WRITE_REQ=%0d(d) WRITE_REQ_LEN=%0h(h) ; WRITE_REQ_WSTRB=%0p(p)",
                  m_count_write_req,
                  write_req.m_len,
                  write_req.m_wstrb ) )
    end

    // Check the number of flit of last
    if ( write_req.m_last.size() != nb_flits ) begin
      `uvm_error(this.name,
        $sformatf("Number of flits of last are not matching: WRITE_REQ=%0d(d) WRITE_REQ_LEN=%0h(h) ; WRITE_REQ_LAST=%0p(p)",
                  m_count_write_req,
                  write_req.m_len,
                  write_req.m_last ) )
    end

    // Check that only the last flit of last is tied to 1'b1
    foreach( write_req.m_last[i] ) begin
      if ( ( i != write_req.m_last.size() - 1 ) ? (write_req.m_last[i] == 1) : (write_req.m_last[i] == 0 ) ) begin
        `uvm_error(this.name,
          $sformatf("The last value doesn't match the protocol AXI: WRITE_REQ=%0d(d) WRITE_REQ_last=%0p(p)",
                    m_count_write_req,
                    i,
                    write_req.m_last ) )
        break;
      end // if
    end // foreach

    // Check that the size correspond to the bus width
    if ( nb_bytes > bus_nbytes ) begin
      `uvm_error(this.name,
        $sformatf("The size field value doesn't match the bus width: WRITE_REQ=%0d(d) WRITE_REQ_SIZE=%0h(h) ; DATA_bus_nbytes=%0d(d)",
                  m_count_write_req,
                  nb_bytes,
                  bus_nbytes ) )
    end

    // Check that if the burst mode is WRAP, that the address is aligned to
    // the size of the transfert
    if ( write_req.m_burst == RESERVED ) begin
      `uvm_error(this.name,
        $sformatf("The burst mode RESERVED is not supported: WRITE_REQ=%0d(d) WRITE_REQ_BURST_MODE=%0h(h)",
                  m_count_write_req,
                  write_req.m_burst) )
    end

    // Check that if the burst mode is WRAP, that the address is aligned to
    // the size of the transfert
    if ( ( write_req.m_burst == WRAP ) &&
         ( write_req.m_addr != ( write_req.m_addr + ( write_req.m_addr % nb_bytes ) ) ) ) begin
      `uvm_error(this.name,
        $sformatf("In WRAP burst mode, the address is not aligned to the size of the transfert: WRITE_REQ=%0d(d) WRITE_REQ_ADDR=%0h(h) ; WRITE_REQ_SIZE=%0p(p)",
                  m_count_write_req,
                  write_req.m_addr,
                  write_req.m_size ) )
    end

    // Check that in WRAP burst mode, the number of flit matches the
    // AXI specification constraints
    if ( ( write_req.m_burst == WRAP ) &&
         ( ( nb_flits != 2  ) &&
           ( nb_flits != 4  ) &&
           ( nb_flits != 8  ) &&
           ( nb_flits != 16 ) 
         ) ) begin
      `uvm_error(this.name,
        $sformatf("The number of flit doesn't match the burst mode WRAP: WRITE_REQ=%0d(d) WRITE_REQ_LEN=%0h(h), NB_FLITS=%0d(d)",
                  m_count_write_req,
                  write_req.m_len,
                  nb_flits) )
    end

    // Check that the number of bytes exchanged for each flit respect the
    // protocol depending of the start address, the size of the transaction
    // and the number of flit exchanged
    aligned_addr = axi_sig_addr_t'( write_req.m_addr / nb_bytes ) * nb_bytes ;
    wrap_boundary = axi_sig_addr_t'( write_req.m_addr / ( nb_bytes * nb_flits ) ) * ( nb_bytes * nb_flits ) ;
    flag_wrap = 0 ;
    address_n = 0 ;
    foreach( write_req.m_wstrb[i] ) begin
      int unsigned lower_byte_lane, upper_byte_lane ;

      // Checking that the number of bytes exchanged in the flit doesn't
      // exceed the transaction size
      if ( nb_bytes < $countones(write_req.m_wstrb[i]) ) begin
        `uvm_error(this.name,
          $sformatf("The number of bytes exchanged doesn't match the size field value: WRITE_REQ=%0d(d) WRITE_REQ_SIZE=%0h(h) ; WRITE_REQ_WSTRB[flit=%0d]=%0x(x)",
                    m_count_write_req,
                    nb_bytes,
                    i,
                    write_req.m_wstrb[i] ) )
      end // if

      // Using the equation of the specification, section A3.4 of the IHI022H
      // version of the amba axi protocol to check if the position of the
      // exchanged bytes in the write strobe respects the protocol axi
      // Equation from the specification
      if ( write_req.m_burst != FIXED ) begin // Burst mode INCR or WRAP

        // Computing the address and byte lane for the first flit of the
        // transaction
        if ( i == 0 ) begin
          address_n       = write_req.m_addr ;
          lower_byte_lane = write_req.m_addr - int'( write_req.m_addr / bus_nbytes ) * bus_nbytes;
          upper_byte_lane = aligned_addr + ( nb_bytes - 1 ) - int'( write_req.m_addr / bus_nbytes ) * bus_nbytes ;
        end else begin
          // Computing the flit address depending of the burst mode, and
          // if the transaction has wrapped or not.
          if ( ( write_req.m_burst == WRAP ) && flag_wrap ) begin // If burst mode is WRAP and the transaction has already wrapped
            address_n = write_req.m_addr + ( i * nb_bytes ) - ( nb_bytes * nb_flits ) ;
          end else begin // For burst mode INCR, and WRAP if the transaction has not wrapped
            address_n = aligned_addr + i * nb_bytes;
          end

          // Computing the byte lane
          lower_byte_lane = address_n - int'( address_n / bus_nbytes ) * bus_nbytes;
          upper_byte_lane = lower_byte_lane + nb_bytes - 1;
        end

        // Checking for the burst mode WRAP if the address has wrapped
        if ( address_n == ( wrap_boundary + ( nb_bytes * nb_flits ) ) ) begin
          flag_wrap = 1 ;
          address_n = wrap_boundary ;
          // Computing the byte lane again since the address_n has been just
          // changed
          lower_byte_lane = address_n - int'( address_n / bus_nbytes ) * bus_nbytes;
          upper_byte_lane = lower_byte_lane + nb_bytes - 1;
        end // if wrap

      end else begin // Burst mode FIXED
        // Constant addr and byte lane for all flits of the transaction
        address_n = write_req.m_addr ;
        lower_byte_lane = write_req.m_addr - int'( write_req.m_addr / bus_nbytes ) * bus_nbytes;
        upper_byte_lane = aligned_addr + ( nb_bytes - 1 ) - int'( write_req.m_addr / bus_nbytes ) * bus_nbytes ;
      end // if FIXED
      
      for ( int j = 0 ; j < bus_nbytes ; j++ ) begin
        if ( ( ( j > upper_byte_lane ) || ( j < lower_byte_lane ) ) && ( write_req.m_wstrb[i][j] == 1'b1 ) )
          `uvm_error(this.name,
            $sformatf("The write strobe enabled are not aligned on the address: WRITE_REQ=%0d(d) WRITE_REQ_ADDR=%0h(h)  WRITE_REQ_WSTRB[flit=%0d]=%0x(x)",
                      m_count_write_req,
                      write_req.m_addr,
                      i,
                      write_req.m_wstrb[i] ) )
      end
    end // foreach

    // Check if the cache value corresponds to a mem_type
    if ( get_mem_type( AXI_WRITE_REQ, write_req.m_cache ) == CACHE_RESERVED )
        `uvm_error(this.name,
          $sformatf("The cache value doesn't corresponds to anything in the memory type encoding: WRITE_REQ=%0d(d) WRITE_REQ_CACHE=%0h(h) ;",
                    m_count_write_req,
                    write_req.m_cache ) )

    // Check exclusive access
    if ( write_req.m_lock == EXCLUSIVE )
      check_exclusive_request( write_req ) ;

  endtask: check_write_req

  // -----------------------------------------------------------------------
  // Task check_read_req
  //
  // Compare the corresponding read request from the source to the read
  // request received on the dest interface
  // -----------------------------------------------------------------------
  task check_read_req ( 
    axi_superset_txn_c  read_req
  );

    // If the unique id is configured in the agent, and that the ID of the
    // transaction already exist, print an error.
    if ( m_agent_config.get_id_management_enable() ) begin
      if ( m_read_txn_db.exists(read_req.m_id) )
        `uvm_error(this.name,
          $sformatf("The agent was configured to generate only unique IDs, and the ID=%0h(h) is currently also used by another read transaction", read_req.m_id) )
    end

    // Check that the size correspond to the bus width
    if ( 2**read_req.m_size > m_agent_config.get_txn_config().get_data_width()/8 ) begin
      `uvm_error(this.name,
        $sformatf("The size field value doesn't match the bus width: READ_REQ=%0d(d) READ_REQ_SIZE=%0h(h) ; DATA_bus_nbytes=%0d(d)",
                  m_count_read_req,
                  read_req.m_size,
                  m_agent_config.get_txn_config().get_data_width() ) )
    end

    // Check if the cache value corresponds to a mem_type
    if ( get_mem_type( AXI_READ_REQ, read_req.m_cache ) == CACHE_RESERVED )
        `uvm_error(this.name,
          $sformatf("The cache value doesn't corresponds to anything in the memory type encoding: READ_REQ=%0d(d) READ_REQ_CACHE=%0h(h) ;",
                    m_count_read_req,
                    read_req.m_cache ) )

    // Check exclusive access
    if ( read_req.m_lock == EXCLUSIVE ) begin
      check_exclusive_request( read_req ) ;
    end

  endtask: check_read_req

  // -----------------------------------------------------------------------
  // Task check_write_rsp
  //
  // Compare the corresponding write response from the dest to the write
  // response received on the source interface
  // -----------------------------------------------------------------------
  task check_write_rsp ( 
    axi_superset_txn_c  write_rsp
  );
    axi_superset_txn_c  write_req ;
    
    if ( m_write_txn_db.exists( write_rsp.m_id ) ) begin
      write_req = m_write_txn_db[write_rsp.m_id].pop_back() ;
    end else begin
      `uvm_error(this.name, 
        $sformatf("No corresponding write request found in database m_write_txn_db: ID=%0h(h)", write_req) )
    end

    // Remove the transaction from the transaction associative array
    if ( m_write_txn_db[write_rsp.m_id].size() == 0 )
      m_write_txn_db.delete(write_rsp.m_id);

    if ( write_req.m_lock == EXCLUSIVE )
      check_exclusive_response( write_req, write_rsp );

  endtask: check_write_rsp

  // -----------------------------------------------------------------------
  // Task check_read_rsp
  //
  // Compare the corresponding read response from the dest to the read
  // response received on the source interface
  // -----------------------------------------------------------------------
  task check_read_rsp ( 
    axi_superset_txn_c  read_rsp
  );
    int nb_flits ;

    axi_superset_txn_c  read_req ;
    
    if ( m_read_txn_db.exists( read_rsp.m_id ) ) begin
      read_req = m_read_txn_db[read_rsp.m_id].pop_back() ;
    end else begin
      `uvm_error(this.name, 
        $sformatf("No corresponding read request found in database m_read_txn_db: ID=%0h(h)", read_rsp.m_id) )
    end

    // Get the number of flit from the corresponding read transaction
    nb_flits = read_req.m_len + 1 ;

    // Check the number of flit of data
    if ( read_rsp.m_data.size() != nb_flits ) begin
      `uvm_error(this.name,
        $sformatf("Number of flits of data are not matching: READ_RSP=%0d(d) READ_REQ_LEN=%0h(h) ; READ_RSP_DATA=%0p(p)",
                  m_count_read_rsp,
                  read_req.m_len,
                  read_rsp.m_data ) )
    end

    // Check the number of flit of last
    if ( read_rsp.m_last.size() != nb_flits ) begin
      `uvm_error(this.name,
        $sformatf("Number of flits of last are not matching: READ_RSP=%0d(d) READ_REQ_LEN=%0h(h) ; READ_RSP_LAST=%0p(p)",
                  m_count_read_rsp,
                  read_req.m_len,
                  read_rsp.m_last ) )
    end

    // Check that only the last flit of last is tied to 1'b1
    foreach( read_rsp.m_last[i] ) begin
      if ( ( i != read_rsp.m_last.size() - 1 ) ? (read_rsp.m_last[i] == 1) : (read_rsp.m_last[i] == 0 ) ) begin
        `uvm_error(this.name,
          $sformatf("The last value doesn't match the protocol AXI: READ_RSP=%0d(d) READ_RSP_LAST=%0p(p)",
                    m_count_read_rsp,
                    read_rsp.m_last ) )
      end // if
    end // foreach

    // Check the number of flit of resp
    if ( read_rsp.m_resp.size() != nb_flits ) begin
      `uvm_error(this.name,
        $sformatf("Number of flits of resp are not matching: READ_RSP=%0d(d) READ_REQ_LEN=%0h(h) ; READ_RSP_RESP=%0p(p)",
                  m_count_read_rsp,
                  read_req.m_len,
                  read_rsp.m_resp ) )
    end

    // Check exclusive access
    if ( read_req.m_lock == EXCLUSIVE ) begin
      // Flag to detect what kind or error value are mixed in the response
      // burst
      int flag_error        = 0 ;
      int flag_okay_error   = 0 ;
      int flag_exokay_error = 0 ;

      foreach( read_rsp.m_resp[i] ) begin
        // TODO: on slave side, add an exclusive support configuration and
        // check here if the response corresponds to it
        case ( read_rsp.m_resp[i] )
          OKAY : begin
            // `uvm_info( this.name, "Exclusive transactions are not supported by the slave" , UVM_DEBUG)
            // Recording that there is an error in the exclusive burst
            // response
            flag_okay_error = 1 ;
          end
          EXOKAY : begin
            // `uvm_info( this.name, "Exclusive transactions are supported by the slave" , UVM_DEBUG)
            // Recording that there is an error in the exclusive burst
            // response
            flag_exokay_error = 1 ;
          end
          SLVERR , DECERR : begin

            // Recording that there is an error in the exclusive burst
            // response
            flag_error = 1 ;
          end 
          default : begin
            `uvm_error( this.name, "Unsupported response error value" )
          end
        endcase
      end // foreach

      // Checking if the slave have mixed EXOKAY and OKAY responses in the
      // response burst
      if ( flag_okay_error && flag_exokay_error )
        `uvm_error( this.name,
          $sformatf("The slave side has mixed EXOKAY and OKAY response in the response burst, which is not permitted; READ_RSP=%0d(d) ; READ_RSP_RESP=%0p(p)",
                     m_count_read_rsp,
                     read_rsp.m_resp))

      // If there was not a SLVERR or DECERR mixed in the 
      if ( !flag_error ) begin
        check_exclusive_response( read_req, read_rsp );
      end else begin
        `uvm_info( this.name,
          $sformatf("An error unrelated to the exclusive was received; READ_RSP=%0d(d) ; READ_RSP_RESP=%0p(p)",
                     m_count_read_rsp,
                     read_rsp.m_resp),
          UVM_DEBUG)
      end
    end

    // Remove the transaction from the transaction associative array
    if ( m_read_txn_db[read_rsp.m_id].size() == 0 )
      m_read_txn_db.delete(read_rsp.m_id);

  endtask: check_read_rsp

  // -----------------------------------------------------------------------
  // check_exclusive_request function
  // Function to check that the exclusive access follows the constraint of the
  // sectiont A7.2.4 of the IHI022H version of the amba axi protocol
  // -----------------------------------------------------------------------
  virtual function void check_exclusive_request (
    axi_superset_txn_c req
  );
    int flag_error = 0 ;
    
    // Check if the address is aligned to the total number of bytes in the
    // transaction
    if ( req.m_addr != req.m_addr + req.m_addr % ( req.get_total_number_of_bytes_exchanged ) )
      `uvm_error(this.name,
        $sformatf("The exclusive request address is not aligned to the total number of bytes exchanged : REQ_ID=%0h(h) REQ_ADDR=%0h(h) ; REQ_TOT_NB_BYTES=%0d(d)",
                  req.m_id,
                  req.m_addr,
                  req.get_total_number_of_bytes_exchanged() ) )

    // Check if the burst length exceed 16 flits
    if ( req.m_len + 1  > 16 ) 
      `uvm_error(this.name,
        $sformatf("The burst length of the exclusive transaction exceed 16 flits: REQ_ID=%0h(h) ; REQ_LEN=%0h(h)",
                  req.m_id,
                  req.m_len) )

    // Check if the total number of bytes exchanged exceeds 128 bytes
    if ( req.get_total_number_of_bytes_exchanged() > 128 ) 
      `uvm_error(this.name,
        $sformatf("The total number of byte exchanged exceed 128 bytes: REQ_ID=%0h(h) ; REQ_LEN=%0h(h) ; REQ_SIZE=%0h(h) ; TOT_NB_BYTES_EXCHANGED=%0d(d)",
                  req.m_id,
                  req.m_len,
                  req.m_size,
                  req.get_total_number_of_bytes_exchanged() ) )

    // Check if the total number of bytes exchanged doesn't match the
    // available value from the specification
    if ( ( req.get_total_number_of_bytes_exchanged() != 1   ) &&
         ( req.get_total_number_of_bytes_exchanged() != 2   ) &&
         ( req.get_total_number_of_bytes_exchanged() != 4   ) &&
         ( req.get_total_number_of_bytes_exchanged() != 8   ) &&
         ( req.get_total_number_of_bytes_exchanged() != 16  ) &&
         ( req.get_total_number_of_bytes_exchanged() != 32  ) &&
         ( req.get_total_number_of_bytes_exchanged() != 64  ) &&
         ( req.get_total_number_of_bytes_exchanged() != 128 ) )
      `uvm_error(this.name,
        $sformatf("The number of byte exchanged for the exclusive access is not a power of 2: REQ_ID=%0h(h) ; REQ_LEN=%0h(h) ; REQ_SIZE=%0h(h) ; TOT_NB_BYTES_EXCHANGED=%0d(d)",
                  req.m_id,
                  req.m_len,
                  req.m_size,
                  req.get_total_number_of_bytes_exchanged() ) )

    // Check the cache value of the exclusive transaction
    if ( ( req.m_mem_type != DEVICE_BUFFERABLE                     ) &&
         ( req.m_mem_type != NORMAL_NON_CACHEABLE_NON_BUFFERABLE   ) &&
         ( req.m_mem_type != NORMAL_NON_CACHEABLE_BUFFERABLE       ) &&
         ( req.m_mem_type != WRITE_THROUGH_NO_ALLOCATE             ) &&
         ( req.m_mem_type != WRITE_THROUGH_READ_ALLOCATE           ) &&
         ( req.m_mem_type != WRITE_THROUGH_WRITE_ALLOCATE          ) &&
         ( req.m_mem_type != WRITE_THROUGH_READ_AND_WRITE_ALLOCATE ) )
      `uvm_error(this.name,
        $sformatf("The AxCache value doesn't follow the specification constraint: REQ_ID=%0h(h) ; REQ_MEM_TYPE=%0p(p) ; REQ_CACHE=%0h(h)",
                  req.m_id,
                  req.m_mem_type,
                  req.m_cache ) )

  endfunction

  // -----------------------------------------------------------------------
  // check_exclusive_request function
  // Function to check that the exclusive access follows the constraint of the
  // sectiont A7.2.4 of the IHI022H version of the amba axi protocol
  // -----------------------------------------------------------------------
  virtual function void check_exclusive_response (
    axi_superset_txn_c exclusive_txn_req,
    axi_superset_txn_c exclusive_txn_rsp
  );
  
    // Check the transaction type to check how the transaction should be
    // processed
    case ( exclusive_txn_req.m_txn_type )
      AXI_WRITE_REQ : begin
        // Checking if the address / id are already monitored
        if ( m_exclusive_txn_db.exists(exclusive_txn_rsp.m_id) ) begin
          // Checking if the write request address match the monitored address
          if ( m_exclusive_txn_db[exclusive_txn_rsp.m_id].excl_txn.m_addr == exclusive_txn_req.m_addr ) begin
            // Checking if the monitored address content has been modified before this
            // exclusive write
            if ( m_exclusive_txn_db[exclusive_txn_rsp.m_id].modified ) begin
              case ( exclusive_txn_rsp.m_resp[0] )
                EXOKAY : begin
                  `uvm_error( this.name,
                              $sformatf("Unexpected write exclusive success; since the address content has been modified after the exclusive read access. MONITORED_ADDR=%0h(h) ; MONITORED_ID=%0h(h) ", 
                                       m_exclusive_txn_db[exclusive_txn_rsp.m_id].excl_txn.m_addr,
                                       exclusive_txn_rsp.m_id) )
                end
                OKAY : begin
                  `uvm_info( this.name,
                             $sformatf("Expected failure of the exclusive access ADDR=%0h(h) ID=%0h(h), since the address content has been modified", 
                                       exclusive_txn_req.m_addr,
                                       exclusive_txn_req.m_id),
                             UVM_DEBUG)
                end
                default : begin // SLVERR, DECERR or unsupported
                  `uvm_info( this.name,
                             $sformatf("Unrelated failure of the exclusive access ADDR=%0h(h) ID=%0h(h) RESP=%0p(p)", 
                                     exclusive_txn_req.m_addr,
                                     exclusive_txn_req.m_id,
                                     exclusive_txn_rsp.m_resp[0]),
                             UVM_DEBUG)
                end
              endcase
            end else begin // the address content has not been modified
              case ( exclusive_txn_rsp.m_resp[0] )
                EXOKAY : begin
                  `uvm_info( this.name,
                             $sformatf("Success of the exclusive access ADDR=%0h(h) ID=%0h(h), removing the monitoring", 
                                       exclusive_txn_req.m_addr,
                                       exclusive_txn_req.m_id),
                             UVM_DEBUG)
                  m_exclusive_txn_db.delete(exclusive_txn_req.m_id) ;
                end
                OKAY : begin
                  `uvm_error( this.name,
                              $sformatf("Unexpected write exclusive failure. MONITORED_ADDR=%0h(h) ; MONITORED_ID=%0h(h) ; EXCLUSIVE_REQ_ADDR=%0h(h) ; EXCLUSIVE_REQ_ID=%0h(h)", 
                                       m_exclusive_txn_db[exclusive_txn_rsp.m_id].excl_txn.m_addr,
                                       exclusive_txn_rsp.m_id,
                                       exclusive_txn_req.m_addr,
                                       exclusive_txn_req.m_id) )
                end
                default : begin // SLVERR, DECERR or unsupported
                  `uvm_info( this.name,
                             $sformatf("Unrelated failure of the exclusive access ADDR=%0h(h) ID=%0h(h) RESP=%0p(p)", 
                                     exclusive_txn_req.m_addr,
                                     exclusive_txn_req.m_id,
                                     exclusive_txn_rsp.m_resp[0]),
                             UVM_DEBUG)
                end
              endcase
            end // modified
          end else begin // The address monitored doesn't match the exclusive access address for the same write ID
            case ( exclusive_txn_rsp.m_resp[0] )
              EXOKAY : begin
                `uvm_error( this.name,
                           $sformatf("Unexpected write exclusive success. MONITORED_ADDR=%0h(h) ; MONITORED_ID=%0h(h) ; EXCLUSIVE_REQ_ADDR=%0h(h) ; EXCLUSIVE_REQ_ID=%0h(h)", 
                                     m_exclusive_txn_db[exclusive_txn_rsp.m_id].excl_txn.m_addr,
                                     exclusive_txn_rsp.m_id,
                                     exclusive_txn_req.m_addr,
                                     exclusive_txn_req.m_id) )
              end
              OKAY : begin
                `uvm_info( this.name,
                           $sformatf("Normal failure of the write exclusive access MONITORED_ADDR=%0h(h) EXCLUSIVE_REQ_ADDR=%0h(h)", 
                                     m_exclusive_txn_db[exclusive_txn_rsp.m_id].excl_txn.m_addr,
                                     exclusive_txn_req.m_addr),
                           UVM_DEBUG)
              end
              default : begin // SLVERR, DECERR or unsupported
                `uvm_info( this.name,
                           $sformatf("Unrelated failure of the exclusive access ADDR=%0h(h) ID=%0h(h) RESP=%0p(p)", 
                                   exclusive_txn_req.m_addr,
                                   exclusive_txn_req.m_id,
                                   exclusive_txn_rsp.m_resp[0]),
                           UVM_DEBUG)
              end
            endcase
          end // if addr
        end else begin // The id was not monitored, 
          `uvm_error( this.name,
                     $sformatf("Unexpected write exclusive access: this exclusive write was not preceded by read exclusive access for this ID/ADDR; EXCLUSIVE_REQ_ADDR=%0h(h) ; EXCLUSIVE_REQ_ID=%0h(h)", 
                               exclusive_txn_req.m_addr,
                               exclusive_txn_req.m_id) )
        end
      end
      AXI_READ_REQ : begin
        // Checking if the address / id are already monitored
        if ( m_exclusive_txn_db.exists(exclusive_txn_rsp.m_id) ) begin
          case ( exclusive_txn_rsp.m_resp[0] )
            EXOKAY : begin
              `uvm_info( this.name,
                         $sformatf("Success of the read exclusive access ADDR=%0h(h) ID=%0h(h), updating the address monitored", 
                                   exclusive_txn_req.m_addr,
                                   exclusive_txn_req.m_id),
                         UVM_DEBUG)
              m_exclusive_txn_db[exclusive_txn_req.m_id].excl_txn = exclusive_txn_req ;
              m_exclusive_txn_db[exclusive_txn_req.m_id].modified = 1'b0 ;
            end
            OKAY : begin
              `uvm_error( this.name,
                         $sformatf("Unexpected read exclusive failure: the request ID is already monitored on slave side, this exlusive read access should have updated the address monitored") )
            end
            default : begin // SLVERR, DECERR or unsupported
              `uvm_info( this.name,
                         $sformatf("Unrelated failure of the exclusive access ADDR=%0h(h) ID=%0h(h) RESP=%0p(p)", 
                                   exclusive_txn_req.m_addr,
                                   exclusive_txn_req.m_id,
                                   exclusive_txn_rsp.m_resp[0]),
                         UVM_DEBUG)
            end
          endcase
        end else begin // the addr/id was not already monitored
          case ( exclusive_txn_rsp.m_resp[0] )
            EXOKAY : begin
              `uvm_info( this.name,
                         $sformatf("Success of the read exclusive access ADDR=%0h(h) ID=%0h(h), Starting to monitor a new address", 
                                   exclusive_txn_req.m_addr,
                                   exclusive_txn_req.m_id),
                         UVM_DEBUG)
              m_exclusive_txn_db[exclusive_txn_req.m_id].excl_txn = exclusive_txn_req ;
              m_exclusive_txn_db[exclusive_txn_req.m_id].modified = 1'b0 ;
            end
            OKAY : begin
              `uvm_info( this.name,
                         $sformatf("The slave doesn't support exclusive access"), UVM_DEBUG )
            end
            default : begin // SLVERR, DECERR or unsupported
              `uvm_info( this.name,
                         $sformatf("Unrelated failure of the exclusive access ADDR=%0h(h) ID=%0h(h) RESP=%0p(p)", 
                                   exclusive_txn_req.m_addr,
                                   exclusive_txn_req.m_id,
                                   exclusive_txn_rsp.m_resp[0]),
                         UVM_DEBUG)
            end
          endcase
        end // if m_exclusive_txn_db
      end
      default : begin
        `uvm_error( this.name, "Unsupported TXN_TYPE" )
      end
    endcase
  endfunction

  // -----------------------------------------------------------------------
  // monitor_exclusive_addresses function
  // Function that compare the address of an incoming write_request with the
  // monitored address content from previous exclusive transaction, to
  // register if the write request is modifying the exclusive address contents
  // -----------------------------------------------------------------------
  virtual function void monitor_exclusive_addresses (
    axi_superset_txn_c write_req
  );
    axi_superset_txn_c excl_txn ;
    axi_sig_addr_t excl_addr ;
    int unsigned excl_nb_bytes ;

    foreach ( m_exclusive_txn_db[i] ) begin
      excl_txn      = m_exclusive_txn_db[i].excl_txn ;
      excl_addr     = excl_txn.m_addr ;
      excl_nb_bytes = excl_txn.get_total_number_of_bytes_exchanged() ;

      foreach ( write_req.m_flit_addr[j] ) begin
        `uvm_info( this.name,
                   $sformatf("REQ_ID=%0h(h) REQ_FLIT_ADDR[%0d]=%0h(h) MONITORED_ID=%0h(h) MONITORED_ADDR=%0h(h) MONITORED_NB_BYTES=%0d(d)", 
                             write_req.m_id,
                             j, write_req.m_flit_addr[j],
                             i,
                             excl_addr,
                             excl_nb_bytes
                             ),
                   UVM_DEBUG)
        if ( ( write_req.m_flit_addr[j] >= excl_addr ) &&
             ( write_req.m_flit_addr[i] < excl_addr + excl_nb_bytes ) 
           ) begin
          m_exclusive_txn_db[i].modified = 1'b1 ;
          `uvm_info( this.name,
                     $sformatf("The exclusive address with ID=%0h(h) ADDR=%0h(h) has been modified by the write request ID=%0h(h) ", 
                             excl_txn.m_id,
                             excl_txn.m_addr,
                             write_req.m_id), UVM_DEBUG)
          break;
        end

      end // foreach
    end // foreach

  endfunction

  // -----------------------------------------------------------------------
  // Report phase
  // -----------------------------------------------------------------------
  virtual function void report_phase(uvm_phase phase);
        // -----------------------------------------------------------------------
        // Check that the transaction counters are coherent
        // -----------------------------------------------------------------------
        if (m_count_exp_read_rsp != m_count_read_rsp)
            `uvm_error(this.name, "Number of expected read responses is not equal to the number of received read responses")
        if (m_count_exp_write_rsp != m_count_write_rsp)
            `uvm_error(this.name, "Number of expected write responses is not equal to the number of received write responses")

        // -----------------------------------------------------------------------
        // Check that the dynamic  arrays are empty at the end of the
        // simulation
        // -----------------------------------------------------------------------
        if ( m_read_txn_db.num() != 0  )
            `uvm_error(this.name, "The read response dynamic  array is not empty")
        if ( m_write_txn_db.num() != 0 )
            `uvm_error(this.name, "The write response dynamic  array is not empty")
        
  endfunction: report_phase

endclass: axi_superset_protocol_checker_c
