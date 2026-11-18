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
//  Description : Monitor AXI requests and responses
//                Based on the IHI0022F_b_amba_axi_protocol_specification from
//                ARM(TM).
//                The monitor is connected on the AXI channels via an
//                AXI interface. By using the control signals, he samples
//                the transaction going through the interface and convert them
//                into uvm_transaction (axi_superset_txn_c) which are then sent to a scoreboard.
//                
//                This monitor also that each request get a response and count 
//                the number of transactons that are exchanged. 
//                The number of request/response counted are printed in the report phase.
//
//                Only the mode AXI INCR is supported by this monitor
//                This monitor should be given just after the initialisation the name of 
//                its AXI interface to search in the uvm database, in case of multiple AXI
//                interfaces in the same testbench
//
// ----------------------------------------------------------------------------

// -----------------------------------------------------------------------
// Class axi_superset_monitor
//
// Passive monitor which monitor the axi_superset interface and send informations to
// the scoreboard
// -----------------------------------------------------------------------
class axi_superset_monitor_c extends uvm_monitor;

    `uvm_component_utils( axi_superset_monitor_c )

    // ------------------------------------------------------------------------
    // Local variable
    // ------------------------------------------------------------------------
    protected string       name ;
    protected string       interface_name ;
    protected axi_dv_ver_t axi_version ;
    protected bit          is_master_side ;

    event reset_asserted ;
    event reset_deasserted ;

    protected uvm_active_passive_enum is_active = UVM_PASSIVE;

    // ------------------------------------------------------------------------
    // Virtual interfaces
    // ------------------------------------------------------------------------
    typedef virtual axi_superset_if axi_superset_virt_if_t;
    axi_superset_virt_if_t          m_axi_superset_vif;
    
    // -----------------------------------------------------------------------
    // Agent configuration
    // -----------------------------------------------------------------------
    axi_superset_config_c  m_agent_config;

    // -----------------------------------------------------------------------
    // Analysis Ports
    // -----------------------------------------------------------------------
    uvm_analysis_port #(axi_superset_txn_c) m_axi_superset_read_req_packets_collected  ;
    uvm_analysis_port #(axi_superset_txn_c) m_axi_superset_write_req_packets_collected ;
    uvm_analysis_port #(axi_superset_txn_c) m_axi_superset_read_rsp_packets_collected  ;
    uvm_analysis_port #(axi_superset_txn_c) m_axi_superset_write_rsp_packets_collected ;

    uvm_analysis_port #(axi_superset_txn_c) m_axi_superset_mon2seq_packets_collected   ;

    // -----------------------------------------------------------------------
    // Transaction queue for write packect
    // -----------------------------------------------------------------------
    axi_superset_txn_c m_queue_write_req[$];
    axi_superset_txn_c m_queue_write_dat[$];

    axi_superset_txn_c m_read_rsp_db[axi_sig_id_t][$]  ;

    // -----------------------------------------------------------------------
    // Counter for the number of request/response that the monitor detects
    // -----------------------------------------------------------------------
    int m_num_rreq_pkts ; // read request counter
    int m_num_wreq_pkts ; // write request counter
    int m_num_wdat_pkts ; // write data counter
    int m_num_rrsp_pkts ; // response counter
    int m_num_wrsp_pkts ; // response counter

    // ------------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------------
    function new(string name = "axi_superset_monitor_c", uvm_component parent = null);
        super.new(name, parent);
        this.name = name;

    endfunction

    // -----------------------------------------------------------------------
    // Build Phase
    // -----------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        string interface_name;

        super.build_phase(phase);

        // Get the driver configuration from the agent configuration
        interface_name    = m_agent_config.get_interface_name();
        axi_version       = m_agent_config.get_axi_version();
        is_master_side    = m_agent_config.get_is_master_side();

        // Instantiation of the uvm_analysis_port
        m_axi_superset_write_req_packets_collected = new("m_axi_superset_write_req_packets_collected" , this) ;
        m_axi_superset_read_req_packets_collected  = new("m_axi_superset_read_req_packets_collected"  , this) ;
        m_axi_superset_write_rsp_packets_collected = new("m_axi_superset_write_rsp_packets_collected" , this) ;
        m_axi_superset_read_rsp_packets_collected  = new("m_axi_superset_read_rsp_packets_collected"  , this) ;
        m_axi_superset_mon2seq_packets_collected   = new("m_axi_superset_mon2seq_packets_collected"   , this) ;

        // Initialisation of the value of the counter
        m_num_rreq_pkts = 0 ;
        m_num_wreq_pkts = 0 ;
        m_num_rrsp_pkts = 0 ;
        m_num_wrsp_pkts = 0 ;

        // Getting the axi_superset interface from uvm_config_db
        `uvm_info(this.name, $sformatf("Interface Name %0s", interface_name), UVM_DEBUG)
        if (interface_name == "") begin
            `uvm_info(this.name, "No interface name configured", UVM_DEBUG)

            if(!uvm_config_db #(axi_superset_virt_if_t)::get(this, "*", "AXI_SUPERSET_IF", m_axi_superset_vif))
              `uvm_error("Config Error", "uvm_config_db #( axi_superset_if_t )::get cannot find resource AXI_SUPERSET_DRIVER_IF" )

        end else begin
            if(!uvm_config_db #(axi_superset_virt_if_t)::get(this, "*", interface_name, m_axi_superset_vif))
                `uvm_error("Config Error", "uvm_config_db::get cannot find axi interface")
            
        end

        // Give the version of the interface to the virtual interface, to
        // activate the corresponding assertion depending of the version
        m_axi_superset_vif.axi_version = axi_version ;

        `uvm_info(this.name, "Build stage complete.", UVM_DEBUG)
    endfunction : build_phase

    // ------------------------------------------------------------------------
    // Pre reset phase
    // ------------------------------------------------------------------------ 
    virtual task pre_reset_phase(uvm_phase phase);
        -> reset_asserted;
        `uvm_info(this.name, "Pre Reset stage complete.", UVM_DEBUG)
    endtask : pre_reset_phase

    // ------------------------------------------------------------------------
    // Reset phase
    // ------------------------------------------------------------------------ 
    virtual task reset_phase(uvm_phase phase);
        super.reset_phase(phase);
        m_queue_write_req.delete();
        m_queue_write_dat.delete();
        m_read_rsp_db.delete();

        // Initialisation of the value of the counter
        m_num_rreq_pkts = 0 ;
        m_num_wreq_pkts = 0 ;
        m_num_rrsp_pkts = 0 ;
        m_num_wrsp_pkts = 0 ;

        `uvm_info(this.name, "Reset stage complete.", UVM_DEBUG)
    endtask : reset_phase

    // ------------------------------------------------------------------------
    // Post reset phase
    // ------------------------------------------------------------------------  
    virtual task post_reset_phase(uvm_phase phase);
      -> reset_deasserted;
      `uvm_info(this.name, "Post Reset stage complete.", UVM_DEBUG)
    endtask : post_reset_phase

    // -----------------------------------------------------------------------
    // Run Phase
    // -----------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        forever begin
            @(reset_deasserted);
            fork
                receive_AW_channel_transaction_task(phase);
                receive_W_channel_transaction_task(phase);
                combine_write_req_data_task(phase);
                receive_AR_channel_transaction_task(phase);
                receive_B_channel_transaction_task(phase);
                receive_R_channel_transaction_task(phase);
            join_none
            @(reset_asserted);
            disable fork;
        end
    endtask : run_phase

    // -----------------------------------------------------------------------
    // Task receive write requests
    //
    // Collect input write requests on the AW channel of the  axi_superset interface
    // -----------------------------------------------------------------------
    task receive_AW_channel_transaction_task(uvm_phase phase);
        axi_superset_txn_c  wreq;
        axi_superset_txn_c  wreq_atop ;

        forever begin
            @(posedge m_axi_superset_vif.clk_i);
            // -----------------------------------------------------------------------
            // Collect request on Write Address and Write data channels
            // -----------------------------------------------------------------------
            if (m_axi_superset_vif.aw_valid && m_axi_superset_vif.aw_ready) begin
                
                // Creating a new object to send to the scoreboard,
                // and get requests informations into it
                wreq = new();
                wreq.m_txn_config   = m_agent_config.get_txn_config( );

                wreq.m_id           = m_axi_superset_vif.aw_id                                ;
                wreq.m_addr         = m_axi_superset_vif.aw_addr                              ;
                wreq.m_len          = m_axi_superset_vif.aw_len                               ;
                wreq.m_size         = axi_dv_size_t'(m_axi_superset_vif.aw_size )             ;
                wreq.m_burst        = axi_dv_burst_t'(m_axi_superset_vif.aw_burst)            ;
                wreq.m_lock         = axi_dv_lock_t'(m_axi_superset_vif.aw_lock )             ;
                wreq.m_cache        = m_axi_superset_vif.aw_cache                             ;
                wreq.m_mem_type     = get_mem_type(AXI_WRITE_REQ,m_axi_superset_vif.aw_cache) ;
                wreq.m_prot         = axi_dv_prot_t'(m_axi_superset_vif.aw_prot)              ;
                wreq.m_qos          = m_axi_superset_vif.aw_qos                               ;
                wreq.m_region       = m_axi_superset_vif.aw_region                            ;
                wreq.m_user         = m_axi_superset_vif.aw_user                              ;
                wreq.m_atop         = m_axi_superset_vif.aw_atop                              ;
                wreq.m_trace        = m_axi_superset_vif.aw_trace                             ;
                wreq.m_loop         = m_axi_superset_vif.aw_loop                              ;
                wreq.m_mmusecsid    = m_axi_superset_vif.aw_mmusecsid                         ;
                wreq.m_mmusid       = m_axi_superset_vif.aw_mmusid                            ;
                wreq.m_mmussidv     = m_axi_superset_vif.aw_mmussidv                          ;
                wreq.m_mmussid      = m_axi_superset_vif.aw_mmussid                           ;
                wreq.m_mmuatst      = m_axi_superset_vif.aw_mmuatst                           ;
                wreq.m_nsaid        = m_axi_superset_vif.aw_nsaid                             ;
                wreq.m_idunq        = m_axi_superset_vif.aw_idunq                             ;

                wreq.m_txn_type     = AXI_WRITE_REQ ;
                wreq.m_axi_version  = axi_version   ;
                wreq.m_timestamp.push_back($time)   ;

                // Generating the flit_addr / lower_byte_lane
                // upper_byte_lane for the transaction, to help for debug or
                // on slave side
                wreq.post_randomize() ;

                // Print information about the transaction
                `uvm_info( this.name, $sformatf("WRITE_REQ=%0d(d), Info: %0s",m_num_wreq_pkts, wreq.convert2string()) , UVM_DEBUG)

                // Push the write address request into a queue for the
                // combine_write_req_data_task
                m_queue_write_req.push_back(wreq);

                // Pushing a dummy read transaction into the protocol checker
                // if a atomic needing an additional read response is
                // detected.
                // This allows to receive the read response in the protocol
                // checker before the entire write transaction (AW + W) is
                // sent
                if ( wreq.m_atop[5] ) begin
                  wreq_atop = new();
                  $cast( wreq_atop, wreq.clone() );
                  wreq_atop.m_txn_type = AXI_READ_REQ ;
                  m_axi_superset_read_req_packets_collected.write(wreq_atop);
                end

                // Increment Write Address counter
                m_num_wreq_pkts++;

            end // if
        end // forever
    endtask : receive_AW_channel_transaction_task

    // -----------------------------------------------------------------------
    // Task receive write data
    //
    // Collect input write requests on the W channel of the axi_superset interface
    // -----------------------------------------------------------------------
    task receive_W_channel_transaction_task(uvm_phase phase);
        axi_superset_txn_c   wreq_data;

        forever begin
            @(posedge m_axi_superset_vif.clk_i);
            // -----------------------------------------------------------------------
            // Collect request on Write Address and Write data channels
            // -----------------------------------------------------------------------
            if (m_axi_superset_vif.w_valid && m_axi_superset_vif.w_ready) begin
                
                // A new txn arrived, raise the uvm objection until its
                // response comes out
                // phase.raise_objection(this);

                // Creating a new object to send to the scoreboard,
                // and get requests informations into it
                wreq_data = new();

                wreq_data.m_data.push_back( m_axi_superset_vif.w_data)  ;
                wreq_data.m_wstrb.push_back(m_axi_superset_vif.w_strb)  ;
                wreq_data.m_last.push_back( m_axi_superset_vif.w_last)  ;
                wreq_data.m_w_user       = m_axi_superset_vif.w_user    ;
                wreq_data.m_w_trace      = m_axi_superset_vif.w_trace   ;
                wreq_data.m_datachk      = m_axi_superset_vif.w_datachk ;
                wreq_data.m_poison       = m_axi_superset_vif.w_poison  ;

                wreq_data.m_txn_type     = AXI_WRITE_REQ ;
                wreq_data.m_axi_version  = axi_version   ;
                wreq_data.m_timestamp.push_back($time)   ;

                // Print informations about the transaction
                `uvm_info( this.name, $sformatf("WRITE_DAT=%0d(d), Info: %0s",m_num_wdat_pkts, wreq_data.convert2string()) , UVM_DEBUG)

                // Push the Write data packet into the queue for the
                // combine_write_req_data_task
                m_queue_write_dat.push_back(wreq_data);

                // Increment the Write data counter
                m_num_wdat_pkts++;

            end // if
        end // forever
    endtask : receive_W_channel_transaction_task

    // -----------------------------------------------------------------------
    // Task combine write req data 
    //
    // Collect input write address requests and write data requests on the axi_superset
    // interface, on the AW and W channels, and combine their data into
    // transaction to send to the scoreboard
    // -----------------------------------------------------------------------
    task combine_write_req_data_task( uvm_phase phase );
        axi_superset_txn_c  wreq_addr ;
        axi_superset_txn_c  wreq_data ;
        axi_superset_txn_c  wreq_txn  ;

        axi_sig_len_t  req_len;
        int counter_data_pkt = 0   ;
        int counter_txn_pkt  = 0   ;

        forever begin
            wreq_addr = new();

            // Waiting for a new write address request
            wait( m_queue_write_req.size() != 0 );
            wreq_addr = m_queue_write_req.pop_front() ;
            $cast( wreq_txn, wreq_addr.clone() );
            req_len = wreq_txn.m_len ;

            // For each packet of a burst of a write data request, get the
            // data packet transaction from the queue
            for(int i = 0 ; i < wreq_addr.m_len + 1 ; i ++) begin
                wreq_data = new();
                // Waiting for a new write data request
                wait( m_queue_write_dat.size() != 0 );
                wreq_data = m_queue_write_dat.pop_front();

                // Creating a new object to send to the scoreboard,
                // and get requests informations into it by combining
                // write address and write data requests informations
                wreq_txn.append_write_flit(wreq_data.m_data[0],
                                           wreq_data.m_wstrb[0],
                                           wreq_data.m_last[0]);
                wreq_txn.m_datachk        = wreq_data.m_datachk      ;
                wreq_txn.m_poison         = wreq_data.m_poison       ;
                wreq_txn.m_timestamp.push_back(wreq_data.m_timestamp[0]) ;

                // Fixing the change of len introduced by the append_write_flit
                // function
                wreq_txn.m_len = req_len ;

                // Print informations about the transaction
                `uvm_info( this.name, $sformatf("WRITE_COMB_DAT=%0d(d), Info: %0s", counter_data_pkt, wreq_txn.convert2string()) , UVM_DEBUG)

                // Increment the Write data counter
                counter_data_pkt++;
                
            end // for

            // Increment the txn counter
            counter_txn_pkt++;

            `uvm_info( this.name, $sformatf("WRITE_TXN=%0d(d), Info: %0s", counter_txn_pkt, wreq_txn.convert2string()) , UVM_DEBUG)

            // Sending the transaction to the scoreboard
            m_axi_superset_write_req_packets_collected.write(wreq_txn);
            if ( !is_master_side )
              m_axi_superset_mon2seq_packets_collected.write(wreq_txn);

            fork
                begin
                    int unsigned wreq_handle;
                    axi_superset_txn_c req_write;
                    req_write = new;
                    $cast(req_write, wreq_data.clone());
                    wreq_handle = begin_tr(req_write, "WRITE_REQ" );
                    @(posedge m_axi_superset_vif.clk_i);
                    end_tr( req_write ); 
                end
            join_none

        end // forever
    endtask : combine_write_req_data_task

    // -----------------------------------------------------------------------
    // Task receive read requests
    //
    // Collect input read requests on the axi_superset interface, on the AR channel
    // -----------------------------------------------------------------------
    task receive_AR_channel_transaction_task(uvm_phase phase);
        axi_superset_txn_c rreq;

        forever begin
            @(posedge m_axi_superset_vif.clk_i);

            // -----------------------------------------------------------------------
            // Collect request on Read Address channel
            // -----------------------------------------------------------------------
            if (m_axi_superset_vif.ar_valid && m_axi_superset_vif.ar_ready) begin

                // A new txn arrived, raise the uvm objection until its
                // response comes out
                // phase.raise_objection(this);

                // Creating a new object to send to the scoreboard,
                // and get requests informations into it
                rreq = new() ;
                rreq.m_id           = m_axi_superset_vif.ar_id                               ;
                rreq.m_addr         = m_axi_superset_vif.ar_addr                             ;
                rreq.m_len          = m_axi_superset_vif.ar_len                              ;
                rreq.m_size         = axi_dv_size_t'(m_axi_superset_vif.ar_size)             ;
                rreq.m_burst        = axi_dv_burst_t'(m_axi_superset_vif.ar_burst)           ;
                rreq.m_lock         = axi_dv_lock_t'(m_axi_superset_vif.ar_lock)             ;
                rreq.m_cache        = m_axi_superset_vif.ar_cache                            ;
                rreq.m_mem_type     = get_mem_type(AXI_READ_REQ,m_axi_superset_vif.ar_cache) ;
                rreq.m_prot         = axi_dv_prot_t'(m_axi_superset_vif.ar_prot)             ;
                rreq.m_qos          = m_axi_superset_vif.ar_qos                              ;
                rreq.m_region       = m_axi_superset_vif.ar_region                           ;
                rreq.m_user         = m_axi_superset_vif.ar_user                             ;
                rreq.m_trace        = m_axi_superset_vif.ar_trace                            ;
                rreq.m_loop         = m_axi_superset_vif.ar_loop                             ;
                rreq.m_mmusecsid    = m_axi_superset_vif.ar_mmusecsid                        ;
                rreq.m_mmusid       = m_axi_superset_vif.ar_mmusid                           ;
                rreq.m_mmussidv     = m_axi_superset_vif.ar_mmussidv                         ;
                rreq.m_mmussid      = m_axi_superset_vif.ar_mmussid                          ;
                rreq.m_mmuatst      = m_axi_superset_vif.ar_mmuatst                          ;
                rreq.m_nsaid        = m_axi_superset_vif.ar_nsaid                            ;
                rreq.m_idunq        = m_axi_superset_vif.ar_idunq                            ;

                rreq.m_txn_type     = AXI_READ_REQ ;
                rreq.m_axi_version  = axi_version  ;
                rreq.m_timestamp.push_back($time)  ;

                // Print the information about the transaction
                `uvm_info( this.name, $sformatf("READ_REQ=%0d(d), Info: %0s",m_num_rreq_pkts, rreq.convert2string()) , UVM_DEBUG)

                // Send object to the scoreboard
                m_axi_superset_read_req_packets_collected.write(rreq);
                if ( !is_master_side )
                  m_axi_superset_mon2seq_packets_collected.write(rreq);

                // Increment the Read request counter
                m_num_rreq_pkts++;

                fork
                    begin
                        int unsigned rreq_handle;
                        axi_superset_txn_c req_read;
                        req_read = new;
                        $cast(req_read, rreq.clone());
                        rreq_handle = begin_tr(req_read, "READ_REQ" );
                        @(posedge m_axi_superset_vif.clk_i);
                        end_tr( req_read ); 
                    end
                join_none
            end // if
        end // forever
    endtask : receive_AR_channel_transaction_task

    // -----------------------------------------------------------------------
    // Task receive response
    //
    // Collect input response on the axi_superset interface, on the B channel
    // -----------------------------------------------------------------------
    task receive_B_channel_transaction_task(uvm_phase phase);
        axi_superset_txn_c wrsp;

        forever begin
            @(posedge m_axi_superset_vif.clk_i);

            // -----------------------------------------------------------------------
            // Collect response on Write response channel
            // -----------------------------------------------------------------------
            if (m_axi_superset_vif.b_valid && m_axi_superset_vif.b_ready) begin
                // Creating a new object to send to the scoreboard,
                // and get requests informations into it
                wrsp = new();
                wrsp.m_id            = m_axi_superset_vif.b_id    ;
                wrsp.m_user          = m_axi_superset_vif.b_user  ;
                wrsp.m_resp.push_back(axi_dv_resp_t'(m_axi_superset_vif.b_resp))  ;
                wrsp.m_trace         = m_axi_superset_vif.b_trace ;
                wrsp.m_loop          = m_axi_superset_vif.b_loop  ;
                wrsp.m_idunq         = m_axi_superset_vif.b_idunq ;

                wrsp.m_txn_type     = AXI_WRITE_RSP ;
                wrsp.m_axi_version  = axi_version   ;
                wrsp.m_timestamp.push_back($time)   ;

                // Print information about the transaction
                `uvm_info( this.name, $sformatf("WRITE_RSP=%0d(d), Info: %0s",m_num_wrsp_pkts, wrsp.convert2string()) , UVM_DEBUG)

                // Send object to the scoreboard
                m_axi_superset_write_rsp_packets_collected.write(wrsp);

                // Increment the Write response counter
                m_num_wrsp_pkts++;

                fork
                    begin
                        int unsigned wrsp_handle;
                        axi_superset_txn_c rsp_write;
                        rsp_write = new;
                        $cast(rsp_write, wrsp.clone());
                        wrsp_handle = begin_tr(rsp_write, "WRITE_RSP" );
                        @(posedge m_axi_superset_vif.clk_i);
                        end_tr( rsp_write ); 
                    end
                join_none
            end // if
        end // forever
    endtask : receive_B_channel_transaction_task

    // -----------------------------------------------------------------------
    // Task receive read response
    //
    // Collect input response on the axi_superset interface, on the R channel
    // -----------------------------------------------------------------------
    task receive_R_channel_transaction_task(uvm_phase phase);
        axi_superset_txn_c rrsp;

        forever begin
            @(posedge m_axi_superset_vif.clk_i);

            // -----------------------------------------------------------------------
            // Collect response on Read data channel
            // -----------------------------------------------------------------------
            if (m_axi_superset_vif.r_valid && m_axi_superset_vif.r_ready) begin
                // Creating a new object to send to the scoreboard,
                // and get requests informations into it
                rrsp = new() ;

                if ( m_read_rsp_db.exists( m_axi_superset_vif.r_id ) )
                  rrsp = m_read_rsp_db[m_axi_superset_vif.r_id].pop_front() ;

                // Creating a read response transaction to sample it
                // and send it to the scoreboard
                rrsp.m_id         = m_axi_superset_vif.r_id     ;
                rrsp.append_read_flit(m_axi_superset_vif.r_data,
                                      axi_dv_resp_t'(m_axi_superset_vif.r_resp),
                                      m_axi_superset_vif.r_last);
                rrsp.m_user       = m_axi_superset_vif.r_user   ;
                rrsp.m_trace      = m_axi_superset_vif.r_trace  ;
                rrsp.m_loop       = m_axi_superset_vif.r_loop   ;
                rrsp.m_idunq      = m_axi_superset_vif.r_idunq  ;
                rrsp.m_poison     = m_axi_superset_vif.r_poison ;

                rrsp.m_txn_type        = AXI_READ_RSP ;
                rrsp.m_axi_version     = axi_version  ;
                rrsp.m_timestamp.push_back($time)     ;
                `uvm_info( this.name, $sformatf("READ_RSP=%0d(d), Info: %0s",m_num_rrsp_pkts, rrsp.convert2string()) , UVM_NONE)

                if ( m_axi_superset_vif.r_last ) begin
                  // Complete the transaction and put it in the analysis_port
                  // Print the information about the transaction
                  `uvm_info( this.name, $sformatf("READ_RSP=%0d(d), Info: %0s",m_num_rrsp_pkts, rrsp.convert2string()) , UVM_DEBUG)
                  
                  // Send object to the scoreboard
                  m_axi_superset_read_rsp_packets_collected.write(rrsp);

                  // Remove the ID from the queue
                  m_read_rsp_db.delete(rrsp.m_id);

                  // Increment the Read response counter
                  m_num_rrsp_pkts++;
                end else begin
                  // Push back the transaction in the queue, waiting for the
                  // transaction to be complete before putting it in the
                  // analysis port
                  `uvm_info( this.name, $sformatf("READ_RSP_QUEUE=%0s(s)", rrsp.convert2string() ) , UVM_DEBUG)
                  m_read_rsp_db[rrsp.m_id].push_front(rrsp);
                end

                fork
                    begin
                        int unsigned rrsp_handle;
                        axi_superset_txn_c rsp_read;
                        rsp_read = new;
                        $cast(rsp_read, rrsp.clone());
                        rrsp_handle = begin_tr(rsp_read, "READ_RSP" );
                        @(posedge m_axi_superset_vif.clk_i);
                        end_tr( rsp_read ); 
                    end
                join_none
            end // if
        end // forever
    endtask : receive_R_channel_transaction_task

    // -----------------------------------------------------------------------
    // Report Phase
    // -----------------------------------------------------------------------
    virtual function void report_phase(uvm_phase phase);
        `uvm_info($sformatf("%s%s", this.name, "_REPORT_PHASE"), 
                  $sformatf("REPORT: COLLECTED WRITE REQ PACKETS = %0d", m_num_wreq_pkts), 
                  UVM_DEBUG)
        `uvm_info($sformatf("%s%s", this.name, "_REPORT_PHASE"), 
                  $sformatf("REPORT: COLLECTED WRITE DAT PACKETS = %0d", m_num_wdat_pkts), 
                  UVM_DEBUG)
        `uvm_info($sformatf("%s%s", this.name, "_REPORT_PHASE"), 
                  $sformatf("REPORT: COLLECTED WRITE RSP PACKETS = %0d", m_num_wrsp_pkts), 
                  UVM_DEBUG)
        `uvm_info($sformatf("%s%s", this.name, "_REPORT_PHASE"), 
                  $sformatf("REPORT: COLLECTED READ REQ PACKETS = %0d",  m_num_rreq_pkts), 
                  UVM_DEBUG)
        `uvm_info($sformatf("%s%s", this.name, "_REPORT_PHASE"), 
                  $sformatf("REPORT: COLLECTED READ RSP PACKETS = %0d",  m_num_rrsp_pkts), 
                  UVM_DEBUG)

        if ( m_queue_write_req.size() != 0)
          `uvm_error($sformatf("%s%s", this.name, "_REPORT_PHASE"), 
                  $sformatf("REPORT: WRITE_REQ_QUEUE NOT EMPTY SIZE=%0d",  m_queue_write_req.size()))
        if ( m_queue_write_dat.size() != 0)
          `uvm_error($sformatf("%s%s", this.name, "_REPORT_PHASE"), 
                  $sformatf("REPORT: WRITE_DAT_QUEUE NOT EMPTY SIZE=%0d", m_queue_write_dat.size()))
        if ( m_read_rsp_db.size() != 0)
          `uvm_error($sformatf("%s%s", this.name, "_REPORT_PHASE"), 
                  $sformatf("REPORT: READ_RSP_QUEUE NOT EMPTY SIZE=%0d", m_read_rsp_db.size()))

    endfunction: report_phase

    // -----------------------------------------------------------------------
    // Functions set/get
    // -----------------------------------------------------------------------
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

endclass : axi_superset_monitor_c
