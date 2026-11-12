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
//  Description : Driver AXI superset requests or responses
//                Based on the IHI0022F_b_amba_axi_protocol_specification from
//                ARM(TM).
//                The driver is connected on the AXI channels via an
//                AXI interface. It get transaction from the sequencer, push
//                them in the corresponding queue depending of its m_txn_type
//                value, which is connected in the corresponding task to drive
//                the corresponding channel:
//                - AXI_WRITE_REQ -> AW and W channel
//                - AXI_READ_REQ  -> AR channel
//                - AXI_WRITE_RSP -> B channel
//                - AXI_READ_RSP  -> R channel
//                
//                The driver can be configured with the bit is_master_side.
//                This bit configure if the driver is on the master side or
//                the slave side of the AXI interface. If the driver is
//                master side, only the channels AW, W and AR will be driven.
//                On the slave side, only the channels B and R will be driven.
//
//                Only the burst mode AXI INCR is currently supported by this driver.
//                This driver should be given the name of its AXI interface just after the
//                initialisation to get it from the uvm database, in case of multiple AXI
//                interfaces in the same testbench
//
// ----------------------------------------------------------------------------

class axi_superset_driver_c extends uvm_driver # ( axi_superset_txn_c );

    `uvm_component_utils( axi_superset_driver_c )

    // ------------------------------------------------------------------------
    // Local variable
    // ------------------------------------------------------------------------
    protected string               name             ;
    protected axi_dv_ver_t         axi_version      ;
    protected bit                  is_master_side   ;
    protected axi_dv_driver_idle_t drive_idle_value ;

    event reset_asserted ;
    event reset_deasserted ;

    // -----------------------------------------------------------------------
    // Virtual interface
    // -----------------------------------------------------------------------
    typedef virtual axi_superset_if axi_superset_virt_if_t;
    axi_superset_virt_if_t          axi_superset_vif;

    // -----------------------------------------------------------------------
    // Agent configuration
    // -----------------------------------------------------------------------
    axi_superset_config_c  m_agent_config;
    
    // Queue for storing transactions between the get_and_drive task
    // and the task corresponding to the transaction, depending of its
    // m_txn_type. 
    axi_superset_txn_c   aw_txn_queue[$]    ;
    axi_superset_txn_c   w_txn_queue[$]     ;
    axi_superset_txn_c   ar_txn_queue[$]    ;
    axi_superset_txn_c   b_txn_queue[$]     ;
    axi_superset_txn_c   r_txn_queue[$]     ;

    // Queue for storing transactions between the request and the response:
    // the request is stored to keep its sequencer values, and extracted when
    // sending back the corresponding response
    axi_superset_txn_c   global_txn_queue[string][$] ;

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------
    function new( string name , uvm_component parent = null ); 
      super.new( name , parent);
      this.name = name;
    endfunction

    // -----------------------------------------------------------------------
    // Build phase
    // -----------------------------------------------------------------------
    virtual function void build_phase (uvm_phase phase);
        string interface_name;

        super.build_phase(phase);

        // Get the driver configuration from the agent configuration
        interface_name   = m_agent_config.get_interface_name();
        axi_version      = m_agent_config.get_axi_version( );
        is_master_side   = m_agent_config.get_is_master_side( );
        drive_idle_value = m_agent_config.get_driver_idle_value_cfg( );

        // Getting the axi_superset interface from uvm_config_db
        `uvm_info(this.name, $sformatf("Interface Name %0s", interface_name ), UVM_DEBUG)
        if (interface_name == "") begin
            `uvm_info(this.name, "No interface name configured", UVM_DEBUG)

            if(!uvm_config_db #(axi_superset_virt_if_t)::get(this, "*", "AXI_SUPERSET_IF", axi_superset_vif))
              `uvm_error("Config Error", "uvm_config_db #( axi_superset_virt_if_t )::get cannot find resource AXI_SUPERSET_DRIVER_IF" )

        end else begin
            if(!uvm_config_db #(axi_superset_virt_if_t)::get(this, "*", interface_name, axi_superset_vif))
                `uvm_error("Config Error", "uvm_config_db::get cannot find axi interface")
            
        end

    endfunction

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

        // Emptying the queues
        aw_txn_queue.delete() ;
        w_txn_queue.delete()  ;
        ar_txn_queue.delete() ;
        b_txn_queue.delete()  ;
        r_txn_queue.delete()  ;

        // Driving idle bus values
        if ( is_master_side ) begin
          drive_AW_channel_signals();
          drive_W_channel_signals();
          drive_AR_channel_signals();
        end else begin
          drive_B_channel_signals();
          drive_R_channel_signals();
        end

        global_txn_queue.delete();

        `uvm_info(this.name, "Reset stage complete.", UVM_DEBUG)
    endtask

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
         // ----------------------------------------------------------------------------
         // get_and_drive    : task in charge of getting new transactions and depending of 
         //                    its m_txn_type, the transaction is stored into its 
         //                    corresponding queue new transaction.
         //
         // drive_AW_channel   : Task in charge of driving transactions on the AW
         //                      channel.
         // drive_W_channel    : Task in charge of driving transactions on the W
         //                      channel.
         // drive_B_channel    : Task in charge of driving transactions on the B
         //                      channel.
         // drive_AR_channel   : Task in charge of driving transactions on the AR
         //                      channel.
         // drive_R_channel    : Task in charge of driving transactions on the R
         //                      channel.
         //
         // receive_B_channel  : Task in charge of receiving transactions on the B
         //                      channel.
         // receive_R_channel  : Task in charge of receiving transactions on the R
         //                      channel.
         // ----------------------------------------------------------------------------
        forever begin
            @(reset_deasserted);
            `uvm_info(this.name, $sformatf("This driver is %0d(d)", is_master_side), UVM_DEBUG)

            fork
              get_and_drive();
            join_none

            if ( is_master_side ) begin
              fork // Master tasks
                drive_AW_channel();
                drive_W_channel();
                receive_B_channel();
                drive_AR_channel();
                receive_R_channel();
              join_none
            end else begin
              fork // Slave tasks
                drive_B_channel();
                drive_R_channel();
              join_none
            end
            @(reset_asserted);
            disable fork;
          end
    endtask : run_phase

    // ----------------------------------------------------------------------------
    // get_and_drive 
    // Task in charge of getting new transactions and depending of its m_txn_type, 
    // the transaction is stored into its corresponding queue new transaction.
    // ----------------------------------------------------------------------------
    virtual task get_and_drive( );
        axi_superset_txn_c txn ;
        axi_superset_txn_c txn_channel;

        string ids_s;

        // Put the transaction in the corresponding queue
        `uvm_info(this.name, "Get_and_drive stask is starting", UVM_DEBUG)
        forever begin
          // Get the next transaction from the sequencer
          seq_item_port.get(txn);

          if ( !$cast( txn_channel, txn.clone() ) )
            `uvm_error(this.name,"Error during the cast of the transaction");

          // Registering the request in a global queue on master side, since
          // they will be necessary to send back the response the sequence
          if ( is_master_side ) begin
            // In case of an Atomic Store, only a write response is expected. The other
            // atomic transactions expect a read response as well
            if ( ( txn_channel.m_atop[5]) && ( txn_channel.m_txn_type == AXI_WRITE_REQ ) ) begin
              ids_s = $sformatf("AXI_READ_REQ_%0h", txn.m_id);
              global_txn_queue[ids_s].push_front(txn);
            end

            ids_s = $sformatf("%0s_%0h", txn.m_txn_type, txn.m_id);
            // Storing the transaction in an associate array of queue to use it
            // when its time to send back the corresponding response to the sequence
            global_txn_queue[ids_s].push_front(txn);
          end

          `uvm_info(this.name,
             $sformatf("%0s", txn.convert2string()),
             UVM_DEBUG)
          if ( is_master_side ) begin // Master agent driver
            case (txn.m_txn_type)
              AXI_WRITE_REQ : begin
                fork
                  aw_txn_queue.push_front(txn_channel) ;
                  w_txn_queue.push_front(txn_channel)  ;
                join_none
              end
              AXI_READ_REQ  : begin ar_txn_queue.push_front(txn_channel) ; end
              AXI_WRITE_RSP : begin `uvm_warning(this.name, "This driver is on the master side, and can't drive slave controlled channel by sending a AXI_WRITE_RSP") end
              AXI_READ_RSP  : begin `uvm_warning(this.name, "This driver is on the master side, and can't drive slave controlled channel by sending a AXI_READ_RSP") end
            endcase 
          end else begin // Slave agent driver
            case (txn.m_txn_type)
              AXI_WRITE_REQ : begin `uvm_warning(this.name, "This driver is on the slave side, and can't drive master controlled channel by sending a AXI_WRITE_REQ") end
              AXI_READ_REQ  : begin `uvm_warning(this.name, "This driver is on the slave side, and can't drive master controlled channel by sending a AXI_READ_REQ") end
              AXI_WRITE_RSP : begin b_txn_queue.push_front(txn_channel)  ; end
              AXI_READ_RSP  : begin r_txn_queue.push_front(txn_channel)  ; end
            endcase 
          end
        end
    endtask

    // ----------------------------------------------------------------------------
    // Driving tasks
    // ----------------------------------------------------------------------------

    // ----------------------------------------------------------------------------
    // Drive AW channel 
    // Task in charge of driving transactions on the AW channel.
    // ----------------------------------------------------------------------------
    task drive_AW_channel();
      axi_superset_txn_c aw_txn ;

      `uvm_info(this.name, "drive_AW_channel task is starting", UVM_DEBUG)
      forever begin

        // Drive bus signals to idle while waiting for a transaction.
        drive_AW_channel_signals();

        // Waiting and extracting the last request from the queue
        wait ( aw_txn_queue.size() != 0 );
        aw_txn = aw_txn_queue.pop_back() ;

        // Applying the delay of the transaction before enabling the valid
        // signal
        if ( aw_txn.m_delay_cycle_chan_X != 0 )
          axi_superset_vif.wait_n_clock_cycle( aw_txn.m_delay_cycle_chan_X );

        // Driving all the signals of the interface with the transaction
        drive_AW_channel_signals( aw_txn );

        `uvm_info(this.name, "DRIVING VALID", UVM_DEBUG)
        // Handshake process
        axi_superset_vif.aw_valid <= 1;
        do begin
          @(posedge axi_superset_vif.clk_i);
          `uvm_info(this.name, $sformatf("READY ARRIVE, %d", axi_superset_vif.aw_ready), UVM_DEBUG)
        end while ( axi_superset_vif.aw_ready == 0 );

        // End of the transaction
        axi_superset_vif.aw_valid <= 0;
        `uvm_info(this.name, "READY ARRIVE", UVM_DEBUG)

      end // forever

    endtask // drive_AW_channel

    // ----------------------------------------------------------------------------
    // Drive W channel 
    // Task in charge of driving transactions on the W channel.
    // ----------------------------------------------------------------------------
    task drive_W_channel();
      axi_superset_txn_c w_txn  ;
      axi_superset_txn_c w_flit ;
      `uvm_info(this.name, "drive_W_channel task is starting", UVM_DEBUG)
      forever begin

        // Drive bus signals to idle while waiting for a transaction.
        drive_W_channel_signals();

        // Waiting and extracting the last request from the queue
        wait ( w_txn_queue.size() != 0 );
        w_txn = w_txn_queue.pop_back() ;

        // Applying the delay of the transaction before enabling the valid
        // signal
        if ( w_txn.m_delay_cycle_chan_W != 0 )
          axi_superset_vif.wait_n_clock_cycle( w_txn.m_delay_cycle_chan_W );

        for ( int i = 0 ; i < w_txn.m_len + 1 ; i++ ) begin
          // Driving all the signals of the interface with the transaction
          w_flit = new();
          w_flit.m_data.push_front( w_txn.m_data[i]  );
          w_flit.m_wstrb.push_front( w_txn.m_wstrb[i] );
          w_flit.m_last.push_front( w_txn.m_last[i]  );
          w_flit.m_user    = w_txn.m_user     ;
          w_flit.m_datachk = w_txn.m_datachk  ;
          w_flit.m_poison  = w_txn.m_poison   ;
          w_flit.m_trace   = w_txn.m_trace    ;

          drive_W_channel_signals( w_flit ) ;

          // Handshake process
          axi_superset_vif.w_valid <= 1;
          do begin
            @(posedge axi_superset_vif.clk_i);
          end while ( axi_superset_vif.w_ready == 0 ); 

          // End of the first flit transaction
          axi_superset_vif.w_valid <= 0;
          if ( w_txn.m_delay_cycle_flits[i] != 0 )
            axi_superset_vif.wait_n_clock_cycle( w_txn.m_delay_cycle_flits[i] );

        end // for
        axi_superset_vif.w_last <= 0;

      end // forever

    endtask // drive_W_channel

    // ----------------------------------------------------------------------------
    // Drive B channel 
    // Task in charge of driving transactions on the B channel.
    // ----------------------------------------------------------------------------
    task drive_B_channel();
      axi_superset_txn_c b_txn ;

      `uvm_info(this.name, "drive_B_channel task is starting", UVM_DEBUG)
      forever begin

        // Drive bus signals to idle while waiting for a transaction.
        drive_B_channel_signals();

        // Waiting and extracting the last request from the queue
        wait ( b_txn_queue.size() != 0 );
        b_txn = b_txn_queue.pop_back() ;

        // Applying the delay of the transaction before enabling the valid
        // signal
        if ( b_txn.m_delay_cycle_chan_X != 0 )
          axi_superset_vif.wait_n_clock_cycle( b_txn.m_delay_cycle_chan_X );

        // Driving all the signals of the interface with the transaction
        drive_B_channel_signals( b_txn );

        // Handshake process
        axi_superset_vif.b_valid <= 1;
        do begin
          @(posedge axi_superset_vif.clk_i);
        end while ( axi_superset_vif.b_ready == 0 );

        // End of the transaction
        axi_superset_vif.b_valid <= 0;

      end // forever

    endtask // drive_B_channel

    // ----------------------------------------------------------------------------
    // Drive AR channel 
    // Task in charge of driving transactions on the AR channel.
    // ----------------------------------------------------------------------------
    task drive_AR_channel();
      axi_superset_txn_c ar_txn ;

      `uvm_info(this.name, "drive_AR_channel task is starting", UVM_DEBUG)
      forever begin

        // Drive bus signals to idle while waiting for a transaction.
        drive_AR_channel_signals();

        // Waiting and extracting the last request from the queue
        wait ( ar_txn_queue.size() != 0 );
        ar_txn = ar_txn_queue.pop_back() ;

        // Applying the delay of the transaction before enabling the valid
        // signal
        if ( ar_txn.m_delay_cycle_chan_X != 0 )
          axi_superset_vif.wait_n_clock_cycle( ar_txn.m_delay_cycle_chan_X );

        // Driving all the signals of the interface with the transaction
        drive_AR_channel_signals( ar_txn );

        // Handshake process
        axi_superset_vif.ar_valid <= 1;
        do begin
          @(posedge axi_superset_vif.clk_i);
        end while ( axi_superset_vif.ar_ready == 0 );

        // End of the transaction
        axi_superset_vif.ar_valid <= 0;

      end // forever

    endtask // drive_AR_channel

    // ----------------------------------------------------------------------------
    // Drive R channel 
    // Task in charge of driving transactions on the R channel.
    // ----------------------------------------------------------------------------
    task drive_R_channel();
      axi_superset_txn_c r_txn ;
      axi_superset_txn_c r_flit ;

      `uvm_info(this.name, "drive_R_channel task is starting", UVM_DEBUG)
      forever begin

        // Drive bus signals to idle while waiting for a transaction.
        drive_R_channel_signals();

        // Waiting and extracting the last request from the queue
        wait ( r_txn_queue.size() != 0 );
        r_txn = r_txn_queue.pop_back() ;

        // Applying the delay of the transaction before enabling the valid
        // signal
        if ( r_txn.m_delay_cycle_chan_X != 0 )
          axi_superset_vif.wait_n_clock_cycle( r_txn.m_delay_cycle_chan_X );

        for ( int i = 0 ; i < r_txn.m_data.size() ; i++ ) begin
          // Driving each flit of the transaction on the interface
          r_flit = new();
          r_flit.m_id      = r_txn.m_id      ;
          r_flit.m_data.push_front( r_txn.m_data[i] ) ;
          r_flit.m_last.push_front( r_txn.m_last[i] ) ;
          r_flit.m_resp.push_front( r_txn.m_resp[i] ) ;
          r_flit.m_user    = r_txn.m_user    ;
          r_flit.m_datachk = r_txn.m_datachk ;
          r_flit.m_poison  = r_txn.m_poison  ;
          r_flit.m_trace   = r_txn.m_trace   ;
          r_flit.m_loop    = r_txn.m_loop    ;
          r_flit.m_idunq   = r_txn.m_idunq   ;

          // Driving the flit signals on the interface
          drive_R_channel_signals( r_flit );

          // Handshake process
          axi_superset_vif.r_valid <= 1;
          do begin
            @(posedge axi_superset_vif.clk_i);
          end while ( axi_superset_vif.r_ready == 0 );

          // End of the first flit transaction
          axi_superset_vif.r_valid <= 0;
          if ( r_txn.m_delay_cycle_flits[i] != 0 )
            axi_superset_vif.wait_n_clock_cycle( r_txn.m_delay_cycle_flits[i] );

        end // for
        axi_superset_vif.r_last <= 0;

      end // forever

    endtask // drive_R_channel

    // ----------------------------------------------------------------------------
    // Receiving tasks
    // ----------------------------------------------------------------------------

    // ----------------------------------------------------------------------------
    // Receive B channel ( Master tasks ) 
    // Task in charge of receiving the response on the B channel by managing
    // the b_ready signal
    // ----------------------------------------------------------------------------
    task receive_B_channel();
      axi_superset_txn_c txn;
      string ids_s;

      `uvm_info(this.name, "receive_B_channel task is starting", UVM_DEBUG)

      forever begin
        @(posedge axi_superset_vif.clk_i);

        if ( axi_superset_vif.b_valid && axi_superset_vif.b_ready ) begin

          // Get the IDS_s from the response, to identify the request associated
          // to this transaction in the associative array
          ids_s = $sformatf("%0s_%0h", "AXI_WRITE_REQ", axi_superset_vif.b_id );

          // Get the original transaction from the associative array/queu
          if ( global_txn_queue.exists( ids_s ) ) begin
            // Extract the transaction from the associative array/queue and
            // override it with the response
            txn = global_txn_queue[ids_s].pop_back();
            if ( global_txn_queue[ids_s].size() == 0 )
              global_txn_queue.delete(ids_s);
            `uvm_info(this.name,
             $sformatf("%0s", txn.convert2string()),
             UVM_DEBUG)

            txn.m_txn_type = AXI_WRITE_RSP            ;
            txn.m_id       = axi_superset_vif.b_id    ;
            txn.m_user     = axi_superset_vif.b_user  ;
            txn.m_resp[0]  = axi_dv_resp_t'(axi_superset_vif.b_resp)  ;
            txn.m_trace    = axi_superset_vif.b_trace ;
            txn.m_loop     = axi_superset_vif.b_loop  ;

            // Sending the response to the sequencer on the posedge
            // @(posedge axi_superset_vif.clk_i);
            seq_item_port.put( txn );

          end else begin
            `uvm_error(this.name, 
                $sformatf("No corresponding txn found in global_txn_queue: ID=%0s(s)", ids_s) )
          end
        end // if

      end // forever

    endtask // receive_B_channel

    // ----------------------------------------------------------------------------
    // Receive R channel ( Master task ) 
    // Task in charge of receiving the response on the R channel by managing
    // the r_ready signal
    // ----------------------------------------------------------------------------
    task receive_R_channel();
      axi_superset_txn_c txn;
      axi_sig_data_t       m_data[$];
      axi_sig_resp_t       m_resp[$];
      string ids_s ;

      `uvm_info(this.name, "receive_R_channel task is starting", UVM_DEBUG)

      forever begin
        @(posedge axi_superset_vif.clk_i);

        if ( axi_superset_vif.r_valid && axi_superset_vif.r_ready ) begin


          // Assign data 
          m_data.push_back(axi_superset_vif.r_data);
          m_resp.push_back(axi_superset_vif.r_resp);

          // Wait for the read response to be completed before sending the
          // response to the sequencer        
          if ( axi_superset_vif.r_last ) begin

            // Get the IDS_s from the response, to identify the request associated
            // to this transaction in the associative array
            ids_s = $sformatf("%0s_%0h", "AXI_READ_REQ", axi_superset_vif.r_id );

            // Get the original transaction from the associative array/queu
            if ( global_txn_queue.exists( ids_s ) ) begin

              // Extract the transaction from the associative array/queue and
              // override it with the response
              txn = global_txn_queue[ids_s].pop_back();
              if ( global_txn_queue[ids_s].size() == 0 )
                global_txn_queue.delete(ids_s);

              txn.m_txn_type = AXI_READ_RSP;
              txn.m_id       = axi_superset_vif.r_id     ;

              for ( int i = 0 ; i < txn.m_len + 1 ; i++ ) begin
                txn.set_data_flit( m_data[i] , i ) ;
                txn.set_resp_flit( axi_dv_resp_t'(m_resp[i]) , i ) ;
              end
              m_data.delete();
              m_resp.delete();

              // Sending the transaction to the sequencer
              seq_item_port.put( txn );

            end else begin
              `uvm_error(this.name, 
                  $sformatf("No corresponding txn found in global_txn_queue: ID=%0s(s)", ids_s) )
            end // elsif
          end // if
        end // if

      end // forever

    endtask // receive_R_channel

    // ----------------------------------------------------------------------------
    // drive_idle tasks
    // ----------------------------------------------------------------------------

    // ----------------------------------------------------------------------------
    // Drive AW channel signals
    // ----------------------------------------------------------------------------
    task drive_AW_channel_signals( axi_superset_txn_c  aw_txn = null );

      if ( ( aw_txn == null ) && ( drive_idle_value == RANDOM ) ) begin
        aw_txn = new();
        aw_txn.m_txn_config = m_agent_config.get_txn_config( );
        if (!aw_txn.randomize() with 
          { m_txn_type           == AXI_WRITE_REQ ;
            m_axi_version        == m_axi_version ;
          } )
          `uvm_error(this.name,"Error randomizing the request metadata");
      end

      if ( aw_txn != null ) begin
        // Payload
        axi_superset_vif.aw_id          <= aw_txn.m_id                     ;
        axi_superset_vif.aw_addr        <= aw_txn.m_addr                   ;
        axi_superset_vif.aw_len         <= aw_txn.m_len                    ;
        axi_superset_vif.aw_size        <= axi_sig_size_t'(aw_txn.m_size)  ;
        axi_superset_vif.aw_burst       <= axi_sig_burst_t'(aw_txn.m_burst);
        axi_superset_vif.aw_lock        <= axi_sig_lock_t'(aw_txn.m_lock)  ;
        axi_superset_vif.aw_cache       <= aw_txn.m_cache                  ;
        axi_superset_vif.aw_prot        <= axi_sig_prot_t'(aw_txn.m_prot)  ;
        axi_superset_vif.aw_qos         <= aw_txn.m_qos                    ;
        axi_superset_vif.aw_region      <= aw_txn.m_region                 ;
        axi_superset_vif.aw_user        <= aw_txn.m_user                   ;
        axi_superset_vif.aw_atop        <= aw_txn.m_atop                   ;
        axi_superset_vif.aw_trace       <= aw_txn.m_trace                  ;
        axi_superset_vif.aw_loop        <= aw_txn.m_loop                   ;
        axi_superset_vif.aw_mmusecsid   <= aw_txn.m_mmusecsid              ;
        axi_superset_vif.aw_mmusid      <= aw_txn.m_mmusid                 ;
        axi_superset_vif.aw_mmussidv    <= aw_txn.m_mmussidv               ;
        axi_superset_vif.aw_mmussid     <= aw_txn.m_mmussid                ;
        axi_superset_vif.aw_mmuatst     <= aw_txn.m_mmuatst                ;
        axi_superset_vif.aw_nsaid       <= aw_txn.m_nsaid                  ;
        axi_superset_vif.aw_idunq       <= aw_txn.m_idunq                  ;
      end else begin
        // Payload
        axi_superset_vif.aw_id        <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.aw_addr      <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.aw_len       <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.aw_size      <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.aw_burst     <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.aw_lock      <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.aw_cache     <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.aw_prot      <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.aw_qos       <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.aw_region    <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.aw_user      <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.aw_atop      <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.aw_trace     <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.aw_loop      <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.aw_mmusecsid <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.aw_mmusid    <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.aw_mmussidv  <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.aw_mmussid   <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.aw_mmuatst   <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.aw_nsaid     <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.aw_idunq     <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
      end // if

      // Control signal
      axi_superset_vif.aw_valid <= 0 ;

    endtask // drive_AW_channel_signals

    // ----------------------------------------------------------------------------
    // Drive W channel signals 
    // ----------------------------------------------------------------------------
    task drive_W_channel_signals( axi_superset_txn_c  w_txn = null );

      if ( ( w_txn == null ) && ( drive_idle_value == RANDOM ) ) begin
        w_txn = new();
        w_txn.m_txn_config = m_agent_config.get_txn_config( );
        if (!w_txn.randomize() with 
          { m_txn_type    == AXI_WRITE_REQ ;
            m_len         == 0             ;
            m_axi_version == m_axi_version ;
          } )
          `uvm_error(this.name,"Error randomizing the request data");
      end

      if ( w_txn != null ) begin
        axi_superset_vif.w_data    <= w_txn.m_data[0]  ;
        axi_superset_vif.w_strb    <= w_txn.m_wstrb[0] ;
        axi_superset_vif.w_last    <= w_txn.m_last[0]  ;
        axi_superset_vif.w_user    <= w_txn.m_user     ;
        axi_superset_vif.w_datachk <= w_txn.m_datachk  ;
        axi_superset_vif.w_poison  <= w_txn.m_poison   ;
        axi_superset_vif.w_trace   <= w_txn.m_trace    ;
      end else begin
        // Payload
        axi_superset_vif.w_data    <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.w_strb    <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.w_last    <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.w_user    <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.w_datachk <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.w_poison  <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.w_trace   <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
      end 

      // Control signal
      axi_superset_vif.w_valid <= 0 ;

    endtask // drive_idle_W_channel

    // ----------------------------------------------------------------------------
    // Drive B channel signals
    // ----------------------------------------------------------------------------
    task drive_B_channel_signals( axi_superset_txn_c  b_txn = null );

      if ( ( b_txn == null ) && ( drive_idle_value == RANDOM ) ) begin
        b_txn = new();
        b_txn.m_txn_config = m_agent_config.get_txn_config( );
        if (!b_txn.randomize() with 
          { m_txn_type    == AXI_WRITE_RSP ;
            m_axi_version == m_axi_version ;
          } )
          `uvm_error(this.name,"Error randomizing the write response metadata");
      end

      if ( b_txn != null ) begin
        axi_superset_vif.b_id    <= b_txn.m_id      ;
        axi_superset_vif.b_resp  <= axi_sig_resp_t'(b_txn.m_resp[0]) ;
        axi_superset_vif.b_user  <= b_txn.m_user    ;
        axi_superset_vif.b_trace <= b_txn.m_trace   ;
        axi_superset_vif.b_loop  <= b_txn.m_loop    ;
        axi_superset_vif.b_idunq <= b_txn.m_idunq   ;
      end else begin
        // Payload
        axi_superset_vif.b_id      <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.b_resp    <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.b_user    <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.b_trace   <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.b_loop    <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.b_idunq   <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
      end

      // Control signal
      axi_superset_vif.b_valid <= 0 ;

    endtask // drive_idle_B_channel

    // ----------------------------------------------------------------------------
    // Drive idle AR channel signals
    // ----------------------------------------------------------------------------
    task drive_AR_channel_signals( axi_superset_txn_c  ar_txn = null );

      if ( ( ar_txn == null ) && ( drive_idle_value == RANDOM ) ) begin
        ar_txn = new();
        ar_txn.m_txn_config = m_agent_config.get_txn_config( );
        if (!ar_txn.randomize() with 
          { m_txn_type    == AXI_READ_REQ ;
            m_axi_version == m_axi_version ;
          } )
          `uvm_error(this.name,"Error randomizing the read request metadata");
      end

      if ( ar_txn != null ) begin
        axi_superset_vif.ar_id        <= ar_txn.m_id          ;
        axi_superset_vif.ar_addr      <= ar_txn.m_addr        ;
        axi_superset_vif.ar_len       <= ar_txn.m_len         ;
        axi_superset_vif.ar_size      <= axi_sig_size_t'(ar_txn.m_size)        ;
        axi_superset_vif.ar_burst     <= axi_sig_burst_t'(ar_txn.m_burst)       ;
        axi_superset_vif.ar_lock      <= axi_sig_lock_t'(ar_txn.m_lock)        ;
        axi_superset_vif.ar_cache     <= ar_txn.m_cache       ;
        axi_superset_vif.ar_prot      <= axi_sig_prot_t'(ar_txn.m_prot)        ;
        axi_superset_vif.ar_qos       <= ar_txn.m_qos         ;
        axi_superset_vif.ar_region    <= ar_txn.m_region      ;
        axi_superset_vif.ar_user      <= ar_txn.m_user        ;
        axi_superset_vif.ar_trace     <= ar_txn.m_trace       ;
        axi_superset_vif.ar_loop      <= ar_txn.m_loop        ;
        axi_superset_vif.ar_mmusecsid <= ar_txn.m_mmusecsid   ;
        axi_superset_vif.ar_mmusid    <= ar_txn.m_mmusid      ;
        axi_superset_vif.ar_mmussidv  <= ar_txn.m_mmussidv    ;
        axi_superset_vif.ar_mmussid   <= ar_txn.m_mmussid     ;
        axi_superset_vif.ar_mmuatst   <= ar_txn.m_mmuatst     ;
        axi_superset_vif.ar_nsaid     <= ar_txn.m_nsaid       ;
        axi_superset_vif.ar_idunq     <= ar_txn.m_idunq       ;
      end else begin
        // Payload
        axi_superset_vif.ar_id        <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.ar_addr      <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.ar_len       <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.ar_size      <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.ar_burst     <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.ar_lock      <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.ar_cache     <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.ar_prot      <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.ar_qos       <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.ar_region    <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.ar_user      <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.ar_trace     <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.ar_loop      <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.ar_mmusecsid <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.ar_mmusid    <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.ar_mmussidv  <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.ar_mmussid   <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.ar_mmuatst   <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.ar_nsaid     <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.ar_idunq     <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
      end

      // Control signal
      axi_superset_vif.ar_valid <= 0 ;

    endtask // drive_idle_AR_channel

    // ----------------------------------------------------------------------------
    // Drive R channel signals
    // ----------------------------------------------------------------------------
    task drive_R_channel_signals( axi_superset_txn_c  r_txn = null );

      if ( ( r_txn == null ) && ( drive_idle_value == RANDOM ) ) begin
        r_txn = new();
        r_txn.m_txn_config = m_agent_config.get_txn_config( );
        if (!r_txn.randomize() with 
          { m_txn_type    == AXI_READ_RSP ;
            m_axi_version == m_axi_version ;
          } )
          `uvm_error(this.name,"Error randomizing the read response metadata");
      end

      if ( r_txn != null ) begin
        axi_superset_vif.r_id      <= r_txn.m_id      ;
        axi_superset_vif.r_data    <= r_txn.m_data[0] ;
        axi_superset_vif.r_resp    <= axi_sig_resp_t'(r_txn.m_resp[0]) ;
        axi_superset_vif.r_last    <= r_txn.m_last[0] ;
        axi_superset_vif.r_user    <= r_txn.m_user    ;
        axi_superset_vif.r_datachk <= r_txn.m_datachk ;
        axi_superset_vif.r_poison  <= r_txn.m_poison  ;
        axi_superset_vif.r_trace   <= r_txn.m_trace   ;
        axi_superset_vif.r_loop    <= r_txn.m_loop    ;
        axi_superset_vif.r_idunq   <= r_txn.m_idunq   ;
      end else begin
        // Payload
        axi_superset_vif.r_id      <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.r_data    <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.r_resp    <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.r_last    <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.r_user    <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.r_datachk <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.r_poison  <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.r_trace   <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.r_loop    <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
        axi_superset_vif.r_idunq   <= ( drive_idle_value == UNDEFINED  ) ? 'hx : 0 ;
      end

      // Control signal
      axi_superset_vif.r_valid <= 0 ;

    endtask // drive_idle_R_channel

    // -----------------------------------------------------------------------
    // Functions/tasks
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

    // -----------------------------------------------------------------------
    // Report Phase
    // -----------------------------------------------------------------------
    virtual function void report_phase(uvm_phase phase);
        if ( global_txn_queue.size() != 0)
          `uvm_error($sformatf("%s%s", this.name, "_REPORT_PHASE"), 
            $sformatf("REPORT: REQUEST_QUEUE NOT EMPTY NUM=%0d",  global_txn_queue.size()))

        if ( aw_txn_queue.size() != 0)
          `uvm_error($sformatf("%s%s", this.name, "_REPORT_PHASE"), 
            $sformatf("REPORT: WRITE_REQUEST_QUEUE NOT EMPTY NUM=%0d",  aw_txn_queue.size()))
        if ( w_txn_queue.size() != 0)
          `uvm_error($sformatf("%s%s", this.name, "_REPORT_PHASE"), 
            $sformatf("REPORT: WRITE_DATA_QUEUE NOT EMPTY NUM=%0d",  w_txn_queue.size()))
        if ( ar_txn_queue.size() != 0)
          `uvm_error($sformatf("%s%s", this.name, "_REPORT_PHASE"), 
            $sformatf("REPORT: READ_REQUEST_QUEUE NOT EMPTY NUM=%0d",  ar_txn_queue.size()))
        if ( b_txn_queue.size() != 0)
          `uvm_error($sformatf("%s%s", this.name, "_REPORT_PHASE"), 
            $sformatf("REPORT: WRITE_RESPONSE_QUEUE NOT EMPTY NUM=%0d",  b_txn_queue.size()))
        if ( r_txn_queue.size() != 0)
          `uvm_error($sformatf("%s%s", this.name, "_REPORT_PHASE"), 
            $sformatf("REPORT: READ_RESPONSE_QUEUE NOT EMPTY NUM=%0d",  r_txn_queue.size()))

    endfunction: report_phase

endclass
