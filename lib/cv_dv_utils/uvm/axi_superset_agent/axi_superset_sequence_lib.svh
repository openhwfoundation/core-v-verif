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

class axi_superset_base_sequence_c  extends uvm_sequence #( axi_superset_txn_c, axi_superset_txn_c );

    `uvm_object_utils( axi_superset_base_sequence_c )
 
    protected string name;

    // Number of sequence_item of the sequence
    protected int num_txn;
    protected int num_rsp;

    // Debug variables
    protected int current_num_write_txn;
    protected int current_num_read_txn;

    // With this variable enabled the responses are stored in an Assocaitive
    // Array. This can be used to retrieve the responses specially in the case
    // of read 
    protected bit enable_manage_response;
    // Get the handle of the sequencer to get the configuration for the
    // sequence_iem
    axi_superset_sequencer_c   m_sequencer  ;

    // Associative array of queues for storing the responses of each transactions,
    // for each type of transactions. Allows to to access the response 
    protected axi_superset_txn_c  write_rsp_queue[axi_sig_id_t][$];
    protected axi_superset_txn_c  read_rsp_queue[axi_sig_id_t][$];

    // -------------------------------------------------------------------------
    // Constructor for base sequences
    //
    // All sequencies are derived from this base class.
    //
    // In the constructor, the number of transactions sent by the sequence can
    // be configured via three options:
    // - the argument number_txn: when calling the function new, the user can
    //   give the number of transaction wanted for the instance of the sequence.
    // - The plusargs +NUM_TXN: if the argument number_txn have its default
    //   value, the plusargs NUM_TXN is used to configured the number of
    //   transaction of the sequence.
    // - Function set_num_txn: in case the user prefer this way, there is
    //   a function set which allow to configure the number of transaction
    //   after the creation of the sequence.
    // -------------------------------------------------------------------------
    function new( string name = "base_txn_seq", int number_txn = -1 );
      super.new(name);
      this.name = name;

      if ( number_txn == -1 ) begin
        // Getting the number of transaction for the sequence from a plusargs 
        if (!$value$plusargs("NUM_TXN=%d", num_txn )) begin
          num_txn = 100;
        end // if
      end else begin
        num_txn = number_txn;
      end
      `uvm_info( this.name, $sformatf("NUM_TXN=%0d" , num_txn), UVM_LOW );

      // Activating the response handler feature : the response handler
      // receives the responses from the driver and its processed by a call
      // back which is define below in the response_handler function.
      use_response_handler(1);

      // initialising the number of response
      num_rsp = 0;
      current_num_write_txn = 0 ;
      current_num_read_txn  = 0 ;

    endfunction: new

    // ------------------------------------------------------------------------
    // Pre body task
    // Task in charge of getting the sequencer of the agent, to get the
    // configuration of the agent from the sequencer, to get if the ID are
    // unique or not and to get the transaction configuration for the
    // randomization.
    // ------------------------------------------------------------------------
    virtual task pre_body();
      if ( !$cast(m_sequencer, get_sequencer()) )
        `uvm_error(this.name,"Error during the cast of the sequencer");
    endtask: pre_body


    // -----------------------------------------------------------------------
    // Body
    // -----------------------------------------------------------------------
    virtual task post_body( );
      super.post_body();
      // Waiting for the reception of all responses in the case of id management
      wait( m_sequencer.is_id_queue_empty() == 1 );
    endtask: post_body

    // -------------------------------------------------------------------------
    // TASK: send_txn
    // Task in charge of sending a transaction given by the user.
    // For this task to work correctly, it is assumed that the transaction is
    // already randomized with its own constraints before giving it to the task
    // -------------------------------------------------------------------------
    protected task send_txn
    ( 
      input axi_superset_txn_c  item, // Transaction to send to the driver
      input int txn_number = 0        // Debug input, to print the number of the transaction if this transaction is part of a bigger sequence of transactions.
    );
      axi_superset_txn_c item_clone;

      if ( !$cast( item_clone, item.clone() ) )
        `uvm_error(this.name,"Error during the cast of the transaction");

      if ( ( m_sequencer.m_agent_config.get_axi_version() == AXI4 ) && ( item_clone.m_axi_version != AXI4 ) )
        `uvm_fatal(this.name,$sformatf("The protocol version m_axi_version=%0p of the transaction is not compatible with the protocol version m_agent_config.m_axi_version=AXI4 configured in the agent", item_clone.m_axi_version ) );

      if ( ( 
            ( ( item_clone.m_txn_type == AXI_WRITE_REQ ) || ( item_clone.m_txn_type == AXI_READ_REQ ) ) &&
            ( m_sequencer.m_agent_config.get_is_master_side() )
          ) || (
            ( ( item_clone.m_txn_type == AXI_WRITE_RSP ) || ( item_clone.m_txn_type == AXI_READ_RSP ) ) &&
            ( !m_sequencer.m_agent_config.get_is_master_side() )
          )
        ) begin

        // Start the item
        start_item( item_clone );

        // Increment the counter for debug purposes
        if ( item_clone.m_txn_type == AXI_WRITE_REQ ) begin
          current_num_write_txn++;
          // In the case of an atop, as there will be 2 responses for
          // 1 request, decrease the num_rsp to avoid ending the sequence too
          // soon
          if ( item_clone.m_atop[5] ) begin
            num_rsp--;
            current_num_read_txn++;
          end
        end else begin
          current_num_read_txn++;
        end

        if (  m_sequencer.m_agent_config.get_is_master_side() ) begin
          // Generate a unique id
          if ( m_sequencer.m_agent_config.get_id_management_enable())
            obtain_unique_id ( item_clone );
          else
            if ( m_sequencer.m_agent_config.get_axi_version() != AXI4 ) begin
              // Generate a valid ID, blocking until ID is valid
              obtain_valid_id ( item_clone );
            end
        end

        // Send the transction to the driver
        finish_item( item_clone );

      end // if
    endtask

    // -------------------------------------------------------------------------
    // TASK: send_txn_get_rsp
    // Task in charge of sending a transaction given by the user.
    // For this task to work correctly, it is assumed that the transaction is
    // already randomized with its own constraints before giving it to the task
    // This task waits for the response and blocks the sequences
    // -------------------------------------------------------------------------
    protected task send_txn_get_rsp
    ( 
      input axi_superset_txn_c  item, // Transaction to send to the driver
      output axi_superset_txn_c  rsp
    );
       axi_superset_txn_c item_clone;
       enable_manage_response = 1; 

       if ( !$cast( item_clone, item.clone() ) )
         `uvm_error(this.name,"Error during the cast of the transaction");

       if ( ( ( item_clone.m_txn_type == AXI_WRITE_REQ ) || ( item_clone.m_txn_type == AXI_READ_REQ ) ) &&
            ( m_sequencer.m_agent_config.get_is_master_side() )
          ) begin

           // Start the item
           start_item( item_clone );

           // Increment the counter for debug purpose
           if ( item_clone.m_txn_type == AXI_WRITE_REQ ) begin
             current_num_write_txn++;
           end else begin
             current_num_read_txn++;
           end

           // Generate an unique id
           if ( m_sequencer.m_agent_config.get_id_management_enable() && m_sequencer.m_agent_config.get_is_master_side() )
             obtain_unique_id ( item_clone );

          // Send the transction to the driver
          finish_item( item_clone );

           // Wait for response
          case(item_clone.m_txn_type)
            AXI_READ_REQ:get_rd_rsp(item_clone.m_id, rsp);
            AXI_WRITE_REQ:get_wr_rsp(item_clone.m_id, rsp);
          endcase
        end
    endtask

    // -------------------------------------------------------------------------
    // TASK: send_exclusive_txn
    // WARNING : This task is an example of how an exclusive access can be
    // processed on the master side from the start to the end.
    // It should be used as an example for the user to develop its own
    // sequence sending exclusive access, or can be used to check if the slave
    // support exclusive access, but doesn't contains all the available
    // features of AXI exclusive accesses.
    // List of the features not contained:
    //  - The user can't choose the parameter of the exclusive access
    //  ( metadata && data )
    //  - The task blocks the sequence until the end of the exclusive acces:
    //  sending other transactions in parallel of this exclusive access may
    //  result in unpredictable behavior.
    //  - The write part is done just after the read part of the exclusive
    //  access, not some time later.
    //  - The master will not abandon the exclusive operation, it will
    //  complete the write portion.
    // -------------------------------------------------------------------------
    virtual task send_exclusive_txn
    ( 
      input axi_dv_ver_t   ver  = AXI4,
      input axi_dv_lite_t  lite = NO_LITE,
      input axi_dv_err_t   err  = NO_ERR,
      input int txn_number = 0
    );

      axi_superset_txn_c  req; 
      axi_superset_txn_c  rsp; 
      enable_manage_response = 1; 

      // Creating the transaction and setting its configuration before the
      // randomization
      req = axi_superset_txn_c::type_id::create("item");
      req.set_config( m_sequencer.get_agent_config().get_txn_config() ) ;

      // Randomization of the transaction
      if (!req.randomize() with 
      { 
        m_txn_type    == AXI_READ_REQ ;
        m_axi_version == ver  ;
        m_lite        == lite ;
        m_err         == err  ;
        m_lock        == EXCLUSIVE ;
      } )
        `uvm_error(this.name,"Error randomizing the request metadata");
      `uvm_info( this.name, $sformatf("READ_EXCL_REQ, Info: %0s", req.convert2string()) , UVM_DEBUG)

      // Start the item
      start_item( req );

      // Waiting for the ID to be free to use, then register it
      wait( !m_sequencer.is_id_used( AXI_READ_REQ, req.m_id ) );
      m_sequencer.register_id( req.m_atop, req.m_txn_type, req.m_id, this.name );

      // Increment the counter for debug purposes
      current_num_read_txn++;

      // Send the transction to the driver
      finish_item( req );

      // Waiting for the read response
      get_rd_rsp(req.m_id, rsp);
      `uvm_info( this.name, $sformatf("READ_EXCL_RSP, Info: %0s", rsp.convert2string()) , UVM_DEBUG)

      // Checking the response error value and exiting the task if a value
      // different from EXOKAY was received
      // If EXOKAY and OKAY are mixed in the response, there is a problem on
      // the slave side 
      foreach( rsp.m_resp[i] ) begin
        case ( rsp.m_resp[i] )
          OKAY : begin
            `uvm_info( this.name, "Exclusive transactions are not supported by the slave, ending the send_exclusive_txn task now" , UVM_LOW)
            return;
          end
          EXOKAY : begin
            `uvm_info( this.name, "Exclusive transactions are supported by the slave, sending now the write part of the exclusive transaction" , UVM_LOW)
          end
          SLVERR , DECERR : begin
            `uvm_error( this.name, $sformatf("An error was sent back in the read response, READ RSP Info: %0s", rsp.convert2string()) )
            return;
          end 
          default : begin
            `uvm_error( this.name, "Unsupported response error value" )
            return;
          end
        endcase
      end // foreach

      // An EXOKAY response was received, sending now the write part of the
      // exclusive transaction
      // Start the item
      start_item( req );

      // Keeping all the fields ( addr, id, ... ) of the read request for the
      // write request, just changing the type from READ to WRITE
      // Randomization of the transaction
      if (!req.randomize() with 
      { 
        m_txn_type    == AXI_WRITE_REQ ;
        m_axi_version == ver  ;
        m_lite        == lite ;
        m_err         == err  ;
        m_lock        == EXCLUSIVE ;
        m_addr        == req.m_addr ;
        m_id          == req.m_id ;
      } )
        `uvm_error(this.name,"Error randomizing the request metadata");
      `uvm_info( this.name, $sformatf("WRITE_EXCL_REQ, Info: %0s", req.convert2string()) , UVM_DEBUG)

      // Waiting for the ID to be free to use, then register it
      wait( !m_sequencer.is_id_used( AXI_WRITE_REQ, req.m_id ) );
      m_sequencer.register_id( req.m_atop, req.m_txn_type, req.m_id, this.name );

      // Increment the counter for debug purposes
      current_num_write_txn++;

      // Send the transction to the driver
      finish_item( req );

      // Waiting for the response
      get_wr_rsp(req.m_id, rsp);
      `uvm_info( this.name, $sformatf("WRITE_EXCL_RSP, Info: %0s", rsp.convert2string()) , UVM_DEBUG)
      // Checking the response error value and exiting the task if a value
      // different from EXOKAY was received
      case ( rsp.m_resp[0] )
        OKAY : begin
          `uvm_info( this.name, "The content of the addressed location has been updated since the exclusive read, the exclusive access is a fail" , UVM_LOW)
        end
        EXOKAY : begin
          `uvm_info( this.name, "The exclusive transaction was a success" , UVM_LOW)
        end
        SLVERR , DECERR : begin
          `uvm_error( this.name, $sformatf("An error was sent back in the write response, WRITE RSP Info: %0s", rsp.convert2string()) )
        end 
        default : begin
          `uvm_error( this.name, "Unsupported response error value" )
        end
      endcase

      `uvm_info( this.name, "Ending the send_exclusive_txn task" , UVM_DEBUG)

    endtask

    // -------------------------------------------------------------------------
    // TASK: send_uniflit_req
    // Task in charge of sending a random request with an unique flit.
    // By default, the transaction is an AXI4 request with no error. 
    // This task should only be used in a sequence for a Master agent.
    // -------------------------------------------------------------------------
    virtual task send_uniflit_req
    ( 
      input axi_dv_ver_t   ver  = AXI4,
      input axi_dv_lite_t  lite = NO_LITE,
      input axi_dv_err_t   err  = NO_ERR,
      input int txn_number = 0
    );

      axi_superset_txn_c  item; 

      // Creating the transaction and setting its configuration before the
      // randomization
      item = axi_superset_txn_c::type_id::create("item");
      item.set_config( m_sequencer.get_agent_config().get_txn_config() ) ;

      // Randomization of the transaction
      if (!item.randomize() with 
      { 
        m_txn_type inside {AXI_WRITE_REQ, AXI_READ_REQ};
        m_axi_version == ver  ;
        m_lite        == lite ;
        m_err         == err  ;
        m_len         == 0    ;
        m_lock        == NORMAL ;
      } )
        `uvm_error(this.name,"Error randomizing the request metadata");
      `uvm_info( this.name, $sformatf("REQ, Info: %0s", item.convert2string()) , UVM_DEBUG)

        send_txn( item, txn_number );

    endtask

    // -------------------------------------------------------------------------
    // TASK: send_multiflit_req
    // Task in charge of sending a random request with multiple flits.
    // By default, the transaction is an AXI4 request with no error. 
    // This task should only be used in a sequence for a Master agent.
    // -------------------------------------------------------------------------
    virtual task send_multiflit_req
    ( 
      input axi_dv_ver_t   ver  = AXI4,
      input axi_dv_lite_t  lite = NO_LITE,
      input axi_dv_err_t   err  = NO_ERR,
      input int txn_number = 0
    );

      axi_superset_txn_c  item; 

      // Creating the transaction and setting its configuration before the
      // randomization
      item = axi_superset_txn_c::type_id::create("item");
      item.set_config( m_sequencer.get_agent_config().get_txn_config() ) ;

      // Randomization of the transaction
      if (!item.randomize() with 
      { 
        m_txn_type inside {AXI_WRITE_REQ, AXI_READ_REQ};
        m_axi_version == ver  ;
        m_lite        == lite ;
        m_err         == err  ;
        m_len         <= 15   ;
        m_lock        == NORMAL ;
      } )
        `uvm_error(this.name,"Error randomizing the request metadata");
      `uvm_info( this.name, $sformatf("REQ, Info: %0s", item.convert2string()) , UVM_DEBUG)

        send_txn( item, txn_number );

    endtask

    // -------------------------------------------------------------------------
    // TASK: send_uniflit_write
    // Task in charge of sending a write request
    // By default, the transaction is an AXI4 request with no error. 
    // This task should only be used in a sequence for a Master agent.
    // -------------------------------------------------------------------------
    protected task send_uniflit_write
    (
      input axi_dv_ver_t      ver  = AXI4,
      input axi_dv_lite_t     lite = NO_LITE,
      input axi_dv_err_t      err  = NO_ERR,
      input int txn_number = 0
    );

      axi_superset_txn_c  item; 

      // Creating the transaction with its configuration
      item = axi_superset_txn_c::type_id::create("item");
      item.set_config( m_sequencer.get_agent_config().get_txn_config() ) ;

      // Randomizing the transaction
      if (!item.randomize() with 
      { 
        m_txn_type    == AXI_WRITE_REQ ;
        m_axi_version == ver           ;
        m_lite        == lite          ;
        m_err         == err           ;
        m_len         == 0             ;
        m_lock        == NORMAL ;
      } )
        `uvm_error(this.name,"Error randomizing the write request metadata");

      send_txn( item, txn_number );

    endtask

    // -------------------------------------------------------------------------
    // TASK: send_multiflit_write
    // Task in charge of sending a write request with multiple flits
    // By default, the transaction is an AXI4 request with no error. 
    // This task should only be used in a sequence for a Master agent.
    // -------------------------------------------------------------------------
    protected task send_multiflit_write
    (
      input axi_dv_ver_t      ver  = AXI4,
      input axi_dv_lite_t     lite = NO_LITE,
      input axi_dv_err_t      err  = NO_ERR,
      input int txn_number = 0
    );

      axi_superset_txn_c  item; 

      // Creating the transaction with its configuration
      item = axi_superset_txn_c::type_id::create("item");
      item.set_config( m_sequencer.get_agent_config().get_txn_config() ) ;

      // Randomizing the transaction
      if (!item.randomize() with 
      { 
        m_txn_type    == AXI_WRITE_REQ ;
        m_axi_version == ver           ;
        m_lite        == lite          ;
        m_err         == err           ;
        m_len         <= 15   ;
        m_lock        == NORMAL ;
      } )
        `uvm_error(this.name,"Error randomizing the write request metadata");

      send_txn( item, txn_number );

    endtask

    // -------------------------------------------------------------------------
    // TASK: send_uniflit_read
    // Task in charge of sending a read request
    // By default, the transaction is an AXI4 request with no error. 
    // This task should only be used in a sequence for a Master agent.
    // -------------------------------------------------------------------------
    protected task send_uniflit_read
    (
      input axi_dv_ver_t      ver     = AXI4,
      input axi_dv_lite_t     lite    = NO_LITE,
      input axi_dv_err_t      err     = NO_ERR,
      input int txn_number = 0
    );

      axi_superset_txn_c  item;

      // Creating the transaction with its configuration
      item = axi_superset_txn_c::type_id::create("item");
      item.set_config( m_sequencer.get_agent_config().get_txn_config() ) ;

      // Randomization of the transaction
      if (!item.randomize() with 
      { 
        m_txn_type    == AXI_READ_REQ ;
        m_axi_version == ver          ;
        m_lite        == lite         ;
        m_err         == err          ;
        m_len         == 0            ;
        m_lock        == NORMAL ;
      } )
        `uvm_error(this.name,"Error randomizing the read request metadata");

      // Sending the transaction via the send_txn task
      send_txn( item, txn_number);

    endtask

    // -------------------------------------------------------------------------
    // TASK: send_multiflit_read
    // Task in charge of sending a read request
    // By default, the transaction is an AXI4 request with no error. 
    // This task should only be used in a sequence for a Master agent.
    // -------------------------------------------------------------------------
    protected task send_multiflit_read
    (
      input axi_dv_ver_t      ver     = AXI4,
      input axi_dv_lite_t     lite    = NO_LITE,
      input axi_dv_err_t      err     = NO_ERR,
      input int txn_number = 0
    );

      axi_superset_txn_c  item;

      // Creating the transaction with its configuration
      item = axi_superset_txn_c::type_id::create("item");
      item.set_config( m_sequencer.get_agent_config().get_txn_config() ) ;

      // Randomization of the transaction
      if (!item.randomize() with 
      { 
        m_txn_type    == AXI_READ_REQ ;
        m_axi_version == ver          ;
        m_lite        == lite         ;
        m_err         == err          ;
        m_len         <= 15   ;
        m_lock        == NORMAL ;
      } )
        `uvm_error(this.name,"Error randomizing the read request metadata");

      // Sending the transaction via the send_txn task
      send_txn( item, txn_number);

    endtask

    // -------------------------------------------------------------------------
    // TASK: obtain_unique_id
    // Task in charge of generating a unique id for the transaction.
    // If there is no more id for this type of transaction, the task will wait
    // until a unique id is released by the sequencer.
    // The id is then set in the transaction, and registered in the
    // appropriate list in the sequencer.
    // -------------------------------------------------------------------------
    virtual task obtain_unique_id ( ref axi_superset_txn_c  item );
      axi_sig_id_t  txn_id;

      // Block to set an unique id for the transaction
      // An unique_id is asked to the sequencer, for the corresponding type of
      // transaction
      if ( !m_sequencer.get_unique_unused_id( item.m_txn_type, txn_id, this.name ) ) begin
        // In the case there is no unique id left, the transaction will wait
        // for one to be released before trying to get its unique id
        wait( !m_sequencer.is_id_queue_full( item.m_txn_type ) );

        if ( !m_sequencer.get_unique_unused_id( item.m_txn_type, txn_id, this.name ) )
          `uvm_error(this.name,"Error in getting an unused id: an unused ID should have been released, and the function was not able to get it.");

      end

      // Set the id of the transaction, and register it with the sequencer
      item.set_id( txn_id );
      m_sequencer.register_id( item.m_atop, item.m_txn_type, txn_id, this.name );
      
      // If the transaction is an atop with an additional read response, the
      // id also needs to be registered in the read list to avoid having another
      // read transaction with the same id. So as the id is already registered
      // in the write list, the sequence will wait for this id to be released
      // to get/register it for a read transaction.
      if ( ( item.m_txn_type == AXI_WRITE_REQ ) && ( item.m_atop[5] ) ) begin
        // Waiting for the ID to also be free for the read list
        wait( !m_sequencer.is_id_used( AXI_READ_REQ, txn_id ) );
        // Registering the ID in the read list
        m_sequencer.register_id( item.m_atop, AXI_READ_REQ, txn_id, this.name );
      end

      // If the transaction is an AXI5 transaction, set up its idunq field to
      // 1 to indicate that the agent is working with unique ID
      item.set_idunq( 1'b1 );

    endtask : obtain_unique_id

    // -------------------------------------------------------------------------
    // TASK: obtain_valid_id
    // Task in charge of generating a valid id for the transaction.
    // If there is no more id for this type of transaction, the task will wait
    // until an id is released by the sequencer.
    // The id is then set in the transaction, and registered in the
    // appropriate list in the sequencer.
    // --------------------------------------
    // -------------------------------------------------------------------------
    virtual task obtain_valid_id ( ref axi_superset_txn_c  item );
      axi_sig_id_t  txn_id;

      // Wait for a valid ID to be generated
      wait ( m_sequencer.get_unused_id( item.m_atop, txn_id, this.name ) );

      if ( item.m_atop_type != ATOP_NONE ) item.set_idunq( 1'b1 );
      else                                 item.set_idunq( 1'b0 );

      // Set the id of the transaction, and register it with the sequencer
      item.set_id( txn_id );
      m_sequencer.register_id( item.m_atop, item.m_txn_type, txn_id, this.name );

      // In a case of an atop, also register the id in the read list to later
      // release it when the response arrives
      if ( ( item.m_atop[5] ) && ( item.m_txn_type == AXI_WRITE_REQ ) )
        m_sequencer.register_id( item.m_atop, AXI_READ_REQ, txn_id, this.name );

    endtask : obtain_valid_id

    // -------------------------------------------------------------------------
    // Function response handler
    // Function in charge of receiving responses from the driver.
    // When a response is received, its ID is released and the number of
    // responses received is incremented.
    // Description from the uvm_sequence_base class
    // Function: response_handler
    //
    // When the use_reponse_handler bit is set to 1, this virtual task is called
    // by the sequencer for each response that arrives for this sequence.
    // -------------------------------------------------------------------------
    function void response_handler( uvm_sequence_item  response );
      axi_superset_txn_c  axi_response;

      `uvm_info( this.name, $sformatf("Response handler responses=%0d" , num_rsp ), UVM_DEBUG );
      // Cast the response from an uvm_sequence_axi_response to a axi_superset_txn_c
      if ( !$cast(axi_response, response) )
        `uvm_error(this.name,"Error during the cast of the response");

      // Release the id
      if ( m_sequencer.get_agent_config().get_id_management_enable() ||
           m_sequencer.get_agent_config().get_axi_version() != AXI4 )
        m_sequencer.release_id( axi_response.m_txn_type, axi_response.m_id, this.name );

      // Stock the responses in a queue 
      // A get_rsp(id, type) can be used to get the responses
      if ( enable_manage_response ) begin
        case ( axi_response.m_txn_type )
          AXI_WRITE_RSP: write_rsp_queue[axi_response.m_id].push_back(axi_response);
          AXI_READ_RSP : read_rsp_queue[axi_response.m_id].push_back(axi_response);
        endcase
      end

      // Increment the number of response
      num_rsp++;
    endfunction : response_handler

    // ------------------------------
    // API to get the responses 
    // ------------------------------
    virtual task get_wr_rsp(input axi_sig_id_t id, output axi_superset_txn_c rsp);

      // Wait until a response is seen 
      wait (write_rsp_queue.exists(id));
      wait (write_rsp_queue[id].size() > 0);
      rsp = write_rsp_queue[id].pop_front();

    endtask

    virtual task get_rd_rsp(input axi_sig_id_t id, output axi_superset_txn_c rsp);

      // Wait until a response is seen 
      wait (read_rsp_queue.exists(id));
      wait (read_rsp_queue[id].size() > 0);
      rsp = read_rsp_queue[id].pop_front();

    endtask

    // -----------------------------------------------------------------------
    // Function set/get
    // -----------------------------------------------------------------------

    // -----------------------------------------------------------------------
    // num_txn
    // -----------------------------------------------------------------------
    function void set_num_txn( int new_num_txn );
      `uvm_info( this.name, $sformatf("New number of txn=%0d" , new_num_txn ), UVM_LOW );
      this.num_txn = new_num_txn;
    endfunction : set_num_txn

    function int get_num_txn( );
      return this.num_txn;
    endfunction : get_num_txn

endclass 


// -------------------------------------------------------------------------
// Library of sequences
// - axi_superset_master_sequence_c
// - axi_superset_master_write_sequence_c
// - axi_superset_master_read_sequence_c
// - axi_superset_reactive_slave_sequence_c
// -------------------------------------------------------------------------

// -----------------------------------------------------------------------
// axi_superset_master_sequence_c
// Sequence which send `num_txn random request transaction from the master
// -----------------------------------------------------------------------
class axi_superset_master_sequence_c  extends axi_superset_base_sequence_c ;
  `uvm_object_utils(axi_superset_master_sequence_c)

  // -----------------------------------------------------------------------
  // Constructor
  // -----------------------------------------------------------------------
  function new(string name = "axi_superset_master_sequence_c", int number_txn = -1 );
      super.new(name, number_txn);
  endfunction:new

  // -----------------------------------------------------------------------
  // Body
  // -----------------------------------------------------------------------
  virtual task body( );
    super.body();
    `uvm_info(this.name, "Sequence axi_superset_master_sequence_c is starting", UVM_DEBUG)

    // Sending `num_txn random transactions
    for ( int i = 0 ; i < num_txn ; i++ ) begin
      send_multiflit_req(.txn_number(i));
    end
    // Waiting for the reception of all responses
    wait( num_txn == num_rsp );
    `uvm_info(this.name, "Sequence axi_superset_master_sequence_c is ending", UVM_DEBUG)
  endtask: body

endclass: axi_superset_master_sequence_c


// -----------------------------------------------------------------------
// axi_superset_master_write_sequence_c
// Sequence which send `num_txn random write only request transactions from the master
// -----------------------------------------------------------------------
class axi_superset_master_write_sequence_c  extends axi_superset_base_sequence_c ;
  `uvm_object_utils(axi_superset_master_write_sequence_c)

  // -----------------------------------------------------------------------
  // Constructor
  // -----------------------------------------------------------------------
  function new(string name = "axi_superset_master_write_sequence_c", int number_txn = -1 );
      super.new(name, number_txn);
  endfunction:new

  // -----------------------------------------------------------------------
  // Body
  // -----------------------------------------------------------------------
  virtual task body( );
    super.body();
    `uvm_info(this.name, "Sequence axi_superset_master_write_sequence_c is starting", UVM_DEBUG)

    // Sending `num_txn random write only transactions
    for ( int i = 0 ; i < num_txn ; i++ ) begin
      send_multiflit_write(.txn_number(i));
    end
    // Waiting for the reception of all responses
    wait( num_txn == num_rsp );
    `uvm_info(this.name, "Sequence axi_superset_master_write_sequence_c is ending", UVM_DEBUG)
  endtask: body

endclass: axi_superset_master_write_sequence_c


// -----------------------------------------------------------------------
// axi_superset_master_read_sequence_c
// Sequence which send `num_txn random read only request transactions from the master
// -----------------------------------------------------------------------
class axi_superset_master_read_sequence_c  extends axi_superset_base_sequence_c ;
  `uvm_object_utils(axi_superset_master_read_sequence_c)

  // -----------------------------------------------------------------------
  // Constructor
  // -----------------------------------------------------------------------
  function new(string name = "axi_superset_master_read_sequence_c", int number_txn = -1 );
      super.new(name, number_txn);
  endfunction:new

  // -----------------------------------------------------------------------
  // Body
  // -----------------------------------------------------------------------
  virtual task body( );
    super.body();
    `uvm_info(this.name, "Sequence axi_superset_master_read_sequence_c is starting", UVM_DEBUG)

    // Sending `num_txn random read only transactions
    for ( int i = 0 ; i < num_txn ; i++ ) begin
      send_multiflit_read(.txn_number(i));
    end
    // Waiting for the reception of all responses
    wait( num_txn == num_rsp );
    `uvm_info(this.name, "Sequence axi_superset_master_read_sequence_c is ending", UVM_DEBUG)
  endtask: body

endclass: axi_superset_master_read_sequence_c

// -----------------------------------------------------------------------
// axi_superset_master_excl_sequence_c
// Sequence which send `num_txn random read only request transactions from the master
// -----------------------------------------------------------------------
class axi_superset_master_excl_sequence_c  extends axi_superset_base_sequence_c ;
  `uvm_object_utils(axi_superset_master_excl_sequence_c)

  // -----------------------------------------------------------------------
  // Constructor
  // -----------------------------------------------------------------------
  function new(string name = "axi_superset_master_excl_sequence_c", int number_txn = -1 );
      super.new(name, number_txn);
  endfunction:new

  // -----------------------------------------------------------------------
  // Body
  // -----------------------------------------------------------------------
  virtual task body( );
    super.body();
    `uvm_info(this.name, "Sequence axi_superset_master_excl_sequence_c is starting", UVM_DEBUG)

    // Sending `num_txn random read only transactions
    for ( int i = 0 ; i < num_txn ; i++ ) begin
      send_exclusive_txn(.txn_number(i));
    end
    // Waiting for the reception of all responses
    // wait( num_txn == num_rsp );
    `uvm_info(this.name, "Sequence axi_superset_master_excl_sequence_c is ending", UVM_DEBUG)
  endtask: body

endclass: axi_superset_master_excl_sequence_c

// -----------------------------------------------------------------------
// axi_superset_slave_sequence_c
// Sequence which send `num_txn random request transaction from the slave
// -----------------------------------------------------------------------
class axi_superset_reactive_slave_sequence_c extends axi_superset_base_sequence_c ;
  `uvm_object_utils(axi_superset_reactive_slave_sequence_c)

  // -----------------------------------------------------------------------
  // Constructor
  // -----------------------------------------------------------------------
  function new(string name = "axi_superset_reactive_slave_sequence_c", int number_txn = -1 );
      super.new(name, number_txn);
  endfunction:new

  // -----------------------------------------------------------------------
  // Body
  // -----------------------------------------------------------------------
  virtual task body( );
    axi_superset_txn_c  req;
    axi_superset_txn_c  rsp;
    axi_superset_txn_c  atop_rsp;

    super.body();

    `uvm_info(this.name, "Sequence axi_superset_reactive_slave_sequence_c is starting", UVM_DEBUG)

    req = axi_superset_txn_c::type_id::create("req");
    req.set_config( m_sequencer.get_agent_config().get_txn_config() ) ;

    forever begin
      m_sequencer.m_mon2seq_export.get(req);

      `uvm_info(this.name, "Getting a new request, generating its response", UVM_DEBUG)

      case ( req.m_txn_type )
        AXI_WRITE_REQ : begin
          rsp = axi_superset_txn_c::type_id::create("rsp");
          rsp.set_config( m_sequencer.get_agent_config().get_txn_config() ) ;

          // Randomization of the response
          if (!rsp.randomize() with 
          { 
            m_txn_type    == AXI_WRITE_RSP ;
            m_axi_version == req.m_axi_version  ;
            m_lite        == req.m_lite ;
            m_err         == req.m_err  ;
            m_id          == req.m_id   ;
          } )
            `uvm_error(this.name,"Error randomizing the request metadata");
          
          // Sending the response to the driver
          `uvm_info(this.name, $sformatf("Generating new write rsp TXN_ID=%0h(h)", rsp.m_id), UVM_DEBUG)
          send_txn( rsp ) ;

          // Generating an additional read response if the request is an
          // atomic
          if ( req.m_atop[5] ) begin
            atop_rsp = axi_superset_txn_c::type_id::create("atop_rsp");
            atop_rsp.set_config( m_sequencer.get_agent_config().get_txn_config() ) ;

            if (!atop_rsp.randomize() with
            { m_txn_type           == AXI_READ_RSP  ;
              m_axi_version        == m_axi_version ;
              m_id                 == req.m_id  ;
              m_len                == req.m_len ;
            } )
              `uvm_error(this.name,"Error randomizing the request metadata");
            // Sending the response to the driver
            `uvm_info(this.name, $sformatf("Generating an additional read rsp TXN_ID=%0h(h)", rsp.m_id), UVM_DEBUG)
            send_txn( atop_rsp ) ;
          end

        end

        AXI_READ_REQ : begin
          rsp = axi_superset_txn_c::type_id::create("rsp");
          rsp.set_config( m_sequencer.get_agent_config().get_txn_config() ) ;

          if (!rsp.randomize() with 
            { m_txn_type           == AXI_READ_RSP      ;
              m_axi_version        == req.m_axi_version ;
              m_id                 == req.m_id          ;
              m_len                == req.m_len         ;
            } )
            `uvm_error(this.name,"Error randomizing the request metadata");
          // Sending the response to the driver
          `uvm_info(this.name, $sformatf("Generating new read rsp TXN_ID=%0h(h)", rsp.m_id), UVM_DEBUG)
          send_txn( rsp ) ;

        end
        default : begin

        end
      endcase
    end // forever

    `uvm_info(this.name, "Sequence axi_superset_reactive_slave_sequence_c is ending", UVM_DEBUG)
  endtask: body

endclass: axi_superset_reactive_slave_sequence_c


