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
//  Description : This file defines the AXI superset sequencer module
//                
// 
// ----------------------------------------------------------------------------

// ----------------------------------------------------------------------------
// Class axi_superset_sequencer_c
//
// This class is only a simple sequencer parametized with the
// axi_superset_txn_c.
//
// The class also contains the transaction configuration that was configured
// for the agent, so the sequence can get it from the sequencer to configure
// its uvm_sequence_item with it.
//
// ----------------------------------------------------------------------------

class axi_superset_sequencer_c extends uvm_sequencer #( axi_superset_txn_c );

    `uvm_sequencer_utils( axi_superset_sequencer_c );

    protected string name ;
    protected int max_number_txn;

    // Transaction configuration
    axi_superset_config_c   m_agent_config  ;

    // Associative array that keeps track of in-flight read and write request IDs.
    protected axi_sig_id_t  write_ids_queue[axi_sig_id_t][$] ;
    protected axi_sig_id_t  read_ids_queue[axi_sig_id_t][$] ;

    // Associative array that keeps track of in-flight ATOPs that require a write response
    protected axi_sig_id_t  atop_write_ids_queue[axi_sig_id_t] ;

    // Associative array that keeps track of in-flight ATOPs that require a read response
    protected axi_sig_id_t  atop_read_ids_queue[axi_sig_id_t] ;

    // Flag to indicate if the maximum number of ID available are used
    protected bit flag_write_id_full;
    protected bit flag_read_id_full;

    // -----------------------------------------------------------------------
    // Analysis Ports
    // -----------------------------------------------------------------------
    uvm_tlm_analysis_fifo #(axi_superset_txn_c) m_mon2seq_export;

    // -------------------------------------------------------------------------
    // Function: is_id_queue_full
    // Function which return the flag indicating if there is no more ID
    // available, corresponding of the type of request.
    // -------------------------------------------------------------------------
    function bit is_id_queue_full ( axi_dv_txn_type_t  txn_type );
      `uvm_info( $sformatf("%0s", this.name), "Queue is full", UVM_DEBUG );
      case ( txn_type )
        AXI_WRITE_REQ : begin return flag_write_id_full ; end
        AXI_READ_REQ  : begin return flag_read_id_full  ; end
        default       : begin `uvm_error(this.name, $sformatf("WRONG TXN TYPE %0p", txn_type)) end
      endcase
    endfunction : is_id_queue_full

    function bit is_id_queue_empty ();
      `uvm_info( $sformatf("%0s", this.name), $sformatf("Write queue size %0d(d), Read queue size %0d()", write_ids_queue.size, read_ids_queue.size), UVM_DEBUG );
      return !write_ids_queue.size & !read_ids_queue.size;
    endfunction : is_id_queue_empty

    // -------------------------------------------------------------------------
    // Function: is_id_used
    // Function which check if the ID provided to the function is already
    // registered in the corresponding associative array
    // -------------------------------------------------------------------------
    function bit is_id_used ( axi_dv_txn_type_t  txn_type, axi_sig_id_t  new_id );
      case ( txn_type )
        AXI_WRITE_REQ : begin return ( write_ids_queue.exists( new_id ) == 1 ) ; end
        AXI_READ_REQ  : begin return ( read_ids_queue.exists( new_id )  == 1 ) ; end
        default       : begin `uvm_error(this.name, $sformatf("WRONG TXN TYPE %0p", txn_type)) end
      endcase 
    endfunction : is_id_used

    // -------------------------------------------------------------------------
    // Function: release_id
    // Function which release the id provided from the corresponding
    // associative array.
    // If there are multiple instance of the same id, only one instance is
    // removed. But the ID is still not released.
    // If there is only one instance of the same id, the id is released and
    // its entry in the associative array is deleted.
    // If the ID was not yet used, an UVM_INFO informs the user.
    // -------------------------------------------------------------------------
    function void release_id ( axi_dv_txn_type_t  txn_type, axi_sig_id_t  old_id, string sequence_name );
      axi_sig_id_t  id;
      case ( txn_type )
        AXI_WRITE_RSP : begin
          // Check if the ID is already used for a write transaction and update the table
          if (write_ids_queue.exists(old_id)) begin

            id = write_ids_queue[old_id].pop_back();

            // If it's the last in-flight request using this ID, remove the corresponding entry from the table
            if (!write_ids_queue[old_id].size()) begin
              write_ids_queue.delete(old_id);
              flag_write_id_full = 0 ;
            end

            // Check if the ID is that of an ATOP transaction and empty
            // the corresponding entry in the table  
            if ( atop_write_ids_queue.exists(old_id) ) begin
              atop_write_ids_queue.delete(old_id);
            end

          end else begin
            `uvm_error( $sformatf("%0s_%0s", this.name, sequence_name), 
                        $sformatf("There is no pending request with ID %0h for the received response", old_id) );
          end
        end

        AXI_READ_RSP  : begin
          // Check if the ID is already used for a write transaction and update the table
          if (read_ids_queue.exists(old_id)) begin

            id = read_ids_queue[old_id].pop_back();

            // If it's the last in-flight request using this ID, remove the corresponding entry from the table
            if (!read_ids_queue[old_id].size()) begin
              read_ids_queue.delete(old_id);
              flag_read_id_full = 0 ;
            end

            // Check if the ID is that of an ATOP transaction and empty the corresponding
            // entry in the table
            if ( atop_read_ids_queue.exists(old_id) )
              atop_read_ids_queue.delete(old_id);

          end else begin
            `uvm_error( $sformatf("%0s_%0s", this.name, sequence_name), 
                        $sformatf("There is no pending request with ID %0h for the received response", old_id) );
          end          
        end
      endcase 


    endfunction : release_id

    // -------------------------------------------------------------------------
    // Function: register_id
    // Function which register an ID in the corresponding associative array,
    // depending on the transaction type. 
    // -------------------------------------------------------------------------
    function void register_id ( axi_sig_atop_t  atop, axi_dv_txn_type_t  txn_type, axi_sig_id_t  current_id, string sequence_name );
      case ( txn_type )
        AXI_WRITE_REQ : begin
          // Check if the transaction is an ATOP
          if (atop != 6'h0) begin
            // Update the ATOP in-flight requests table(s) depending on the type of transaction
            if (atop[5]) atop_read_ids_queue[current_id] = current_id;
            atop_write_ids_queue[current_id] = current_id;
          end
          // Update in-flight write requests table
          write_ids_queue[current_id].push_front(current_id);
        end
        AXI_READ_REQ  : begin
          // Update in-flight read requests table
          read_ids_queue[current_id].push_front(current_id);
        end
      endcase


    endfunction : register_id

    // -------------------------------------------------------------------------
    // Function: get_unique_unused_id
    // Function which generates a unused id for the user, depending on the
    // transaction type.
    // The function checks if there are still some available unique id,
    // depending on the number of available IDs. If this is the case, a
    // unique ID is randomized.
    // If there are no more available unique ID, the flag which indicates it
    // is enabled.
    // The ID given as argument is directly updated by the function. 
    // The function return a flag to indicate if getting an unique id was
    // succesful or not.
    // -------------------------------------------------------------------------
    function axi_sig_id_t get_unique_unused_id ( axi_dv_txn_type_t  txn_type, ref axi_sig_id_t unique_id, string sequence_name ) ;
      case ( txn_type )
        AXI_WRITE_REQ : begin
          // If there is no more unique ids available, the flag is enabled and
          // a uvm_info is printed to inform the user
          if ( write_ids_queue.size() == max_number_txn ) begin
            `uvm_info( $sformatf("%0s_%0s", this.name, sequence_name), $sformatf("TXN_TYPE=%0p, ID_QUEUE IS FULL" ,txn_type ), UVM_LOW );
            flag_write_id_full = 1;
            // Getting a unique id was unsuccesful.
            return 0;
          end else begin
            // Until a unique id is obtained, the randomization is repeated
            if ( std::randomize(unique_id) with {
              unique_id < max_number_txn ;
              !( unique_id inside { write_ids_queue } );
            } == 0 )
              `uvm_fatal($sformatf("%0s_%0s", this.name, sequence_name), "Error randomizing the write request id");
            `uvm_info( $sformatf("%0s_%0s", this.name, sequence_name), $sformatf("TXN_TYPE=%0p, ID=%0h(h) is taken" ,txn_type, unique_id  ), UVM_LOW );
            // Getting a unique id was succesful.
            return 1;
          end
        end
        AXI_READ_REQ  : begin
          // If the associative array is already full, there is no unused id,
          // an error is then returned.
          if ( read_ids_queue.size() == max_number_txn ) begin
            `uvm_info( $sformatf("%0s_%0s", this.name, sequence_name), $sformatf("TXN_TYPE=%0p, ID_QUEUE IS FULL" ,txn_type ), UVM_LOW );
            flag_read_id_full = 1;
            // Getting an unique id was unsuccesful.
            return 0;
          end else begin
            // Until a unique id is obtained, the randomization is repeated
            if ( std::randomize(unique_id) with { 
              unique_id < max_number_txn ; 
              !( unique_id inside { read_ids_queue } );
            } == 0 )
              `uvm_fatal($sformatf("%0s_%0s", this.name, sequence_name), "Error randomizing the write request id");
            `uvm_info( $sformatf("%0s_%0s", this.name, sequence_name), $sformatf("TXN_TYPE=%0p, ID=%0h(h) is taken" ,txn_type, unique_id ), UVM_LOW );
            // Getting a unique id was succesful.
            return 1;
          end
        end
        default : return 0;
      endcase 
      
    endfunction : get_unique_unused_id

    // ---------------------------------------------------------------------------------------------
    // Function: get_unused_id
    // Function which generates a valid ID when unique ID management is not enabled.
    // Randomization constraints are declared in section E1.1.4 of the AXI protocol, which are as follows :
    //  - an atomic transaction must not use the same ID as that of any in-flight atomic transaction;
    //  - an atomic transaction must not use the same ID used by other in-flight non-atomic transactions.
    // In order to avoid generating warnings when the solver fails to generate a valid ID satisfying
    // all the aforementioned constraints, the valid id range was declared as a soft constraint.
    // This allows the solver to always find a solution that satisfies the first four hard constraints.
    // In the case where the generated ID is not within the configured range, the function returns 0
    // signaling that another attempt should be made to generate a valid ID.
    // -------------------------------------------------------------------------------------------------
    function bit get_unused_id (axi_sig_atop_t  atop, ref axi_sig_id_t valid_id, string sequence_name ) ;
      if (!std::randomize(valid_id) with {
        !( valid_id inside { atop_write_ids_queue } ) ;
        !( valid_id inside { atop_read_ids_queue  } ) ;
        (atop != '0) -> !( valid_id inside { write_ids_queue } ) ;
        (atop != '0) -> !( valid_id inside { read_ids_queue }  ) ;
        soft valid_id   <=   max_number_txn   ;
      }) begin
        `uvm_error( $sformatf("%0s_%0s", this.name, sequence_name), "Randomization of valid id failed" );
        return 1'b0;
      end
      if (valid_id < max_number_txn ) begin
        `uvm_info( $sformatf("%0s_%0s", this.name, sequence_name), $sformatf("ID=%0h(h) is taken" , valid_id ), UVM_LOW );
        return 1'b1;
      end
      // If the generated ID is bigger than the maximum supported ID, it means that there is no possible legal ID.
      // The user must wait for a valid ID to be freed
      return 1'b0;
    endfunction : get_unused_id

    // ----------------------------------------------------------
    // Constructor 
    // ----------------------------------------------------------
    function new( string name, uvm_component parent );
        super.new( name, parent );
        this.name = name ;

        flag_write_id_full = 0;
        flag_read_id_full  = 0;
      endfunction: new

    // -----------------------------------------------------------------------
    // Build Phase
    // -----------------------------------------------------------------------
    function void build_phase(uvm_phase phase);

        super.build_phase(phase);

        // Initialisation of the uvm_tlm_analysis_fifo for axi_superset interface
        m_mon2seq_export = new("m_mon2seq_export" , this) ;

    endfunction: build_phase

    // -----------------------------------------------------------------------
    // Rest Phase
    // -----------------------------------------------------------------------
    virtual task reset_phase (uvm_phase phase);
      super.reset_phase(phase);

      m_mon2seq_export.flush();

      write_ids_queue.delete();
      read_ids_queue.delete();

      atop_write_ids_queue.delete();
      atop_read_ids_queue.delete();

      flag_write_id_full = 0;
      flag_read_id_full  = 0;

    endtask: reset_phase

    // -----------------------------------------------------------------------
    // Report Phase
    // -----------------------------------------------------------------------
    virtual function void report_phase(uvm_phase phase);
        if ( write_ids_queue.size() != 0)
          `uvm_error($sformatf("%s%s", this.name, "_REPORT_PHASE"), 
            $sformatf("REPORT: WRITE_ID_QUEUE NOT EMPTY NUM=%0d",  write_ids_queue.size() ))
        if ( flag_write_id_full == 1)
          `uvm_error($sformatf("%s%s", this.name, "_REPORT_PHASE"), 
            $sformatf("REPORT: FLAG_WRITE_ID_FULL=%0d",  flag_write_id_full ))
        if ( read_ids_queue.size() != 0)
          `uvm_error($sformatf("%s%s", this.name, "_REPORT_PHASE"), 
            $sformatf("REPORT: READ_ID_QUEUE  NOT EMPTY NUM=%0d", read_ids_queue.size()))
        if ( flag_read_id_full == 1)
          `uvm_error($sformatf("%s%s", this.name, "_REPORT_PHASE"), 
            $sformatf("REPORT: FLAG_read_ID_FULL=%0d",  flag_read_id_full ))
        if ( atop_write_ids_queue.size() != 0)
          `uvm_error($sformatf("%s%s", this.name, "_REPORT_PHASE"),
            $sformatf("REPORT: ATOP_WRITE_ID_QUEUE NOT EMPTY NUM=%0d",  atop_write_ids_queue.size() ))
        if ( atop_read_ids_queue.size() != 0)
          `uvm_error($sformatf("%s%s", this.name, "_REPORT_PHASE"),
            $sformatf("REPORT: ATOP_READ_ID_QUEUE NOT EMPTY NUM=%0d",  atop_read_ids_queue.size() ))
    endfunction: report_phase


    // CONFIGURATION
    function axi_superset_config_c get_agent_config();
      get_agent_config = m_agent_config  ;
    endfunction : get_agent_config

    function void set_agent_config( axi_superset_config_c config_i );
      `uvm_info(this.name,
                $sformatf("Setting the agent configuraiton CFG=%0s", config_i.convert2string() ),
                UVM_DEBUG)
      m_agent_config = config_i ;
      max_number_txn = 2**(m_agent_config.get_txn_config().get_id_width());
    endfunction: set_agent_config

endclass: axi_superset_sequencer_c

