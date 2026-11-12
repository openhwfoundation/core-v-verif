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
//  Description : This holds a UVM agent for the axi interface. This is
//                a parameterized agent which can cover the functionality
//                of the axi
//
//
// ----------------------------------------------------------------------------

class axi_superset_agent_c extends uvm_agent;

  `uvm_component_utils( axi_superset_agent_c )

    // ------------------------------------------------------------------------
    // Typedef
    // ------------------------------------------------------------------------
    typedef axi_superset_reg_adapter_c   #( axi_superset_txn_c ) axi_superset_reg_adapter_t;

    // ------------------------------------------------------------------------
    // Local variable
    // ------------------------------------------------------------------------
    protected string name ;

    // -------------------------------------------------------------------------
    // 3 Structural Components
    // -------------------------------------------------------------------------
    axi_superset_sequencer_c            m_sequencer        ;
    axi_superset_driver_c               m_driver           ;
    axi_superset_monitor_c              m_monitor          ;
    axi_superset_protocol_checker_c     m_protocol_checker ;
    axi_superset_reg_adapter_t          m_reg_adapter      ;

    // -------------------------------------------------------------------------
    // Configuration modules
    // -------------------------------------------------------------------------
    // Agent configuration
    axi_superset_config_c   m_agent_config  ;

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------
    function new( string name, uvm_component parent);
        super.new(name,parent);
        this.name = name;
        this.m_agent_config = new("DEFAULT_AGENT_CFG");
    endfunction: new

    // -----------------------------------------------------------------------
    // Functions/tasks
    // -----------------------------------------------------------------------
    // AGENT CONFIGURATION
    function axi_superset_config_c get_agent_config();
      get_agent_config = m_agent_config  ;
    endfunction : get_agent_config

    function void set_agent_config( axi_superset_config_c config_i );
      `uvm_info(this.name,
                $sformatf("Setting the agent configuration CFG=%0s", config_i.clone().convert2string() ),
                UVM_DEBUG)
      if ( !$cast( m_agent_config, config_i.clone() ) )
        `uvm_error(this.name, "Error during the cast of the configuration in the agent" )
    endfunction: set_agent_config

    // -------------------------------------------------------------------------
    // Build Phase
    // -------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        m_monitor = axi_superset_monitor_c::type_id::create($sformatf("%0s_MONITOR", this.name), this);
        m_monitor.set_agent_config( m_agent_config );

        if ( m_agent_config.get_protocol_checker_enable() ) begin
          m_protocol_checker = axi_superset_protocol_checker_c::type_id::create($sformatf("%0s_PROTOCOL_CHECKER", this.name), this);
          m_protocol_checker.set_agent_config( m_agent_config );
        end

        if ( is_active == UVM_ACTIVE ) begin
            `uvm_info( "BUILD", "Is Active", UVM_MEDIUM );
            // SEQUENCER
            m_sequencer = axi_superset_sequencer_c::type_id::create( $sformatf("%0s_SEQUENCER", this.name), this);
            m_sequencer.set_agent_config( m_agent_config );

            // DRIVER
            m_driver = axi_superset_driver_c::type_id::create( $sformatf("%0s_DRIVER", this.name), this);
            m_driver.set_agent_config( m_agent_config );

            // ADAPTER
            m_reg_adapter = axi_superset_reg_adapter_t::type_id::create( $sformatf("%0s_REG_ADAPTER", this.name), this);
            m_reg_adapter.set_config( m_agent_config.get_txn_config() );

        end else begin
            `uvm_info( "BUILD", "Is Passive", UVM_MEDIUM );
        end // if
    endfunction: build_phase

    // -------------------------------------------------------------------------
    // Connect Phase
    //
    // Connect driver to sequencer
    // -------------------------------------------------------------------------
    function void connect_phase(uvm_phase phase);
        if ( is_active == UVM_ACTIVE ) begin
            m_driver.seq_item_port.connect(m_sequencer.seq_item_export);

            if ( m_agent_config.get_is_master_side() ) begin
              m_driver.rsp_port.connect(m_sequencer.rsp_export);
            end else begin // Slave side
              // Connecting the monitor to the sequencer
              m_monitor.m_axi_superset_mon2seq_packets_collected.connect( m_sequencer.m_mon2seq_export.analysis_export ) ;
            end

            `uvm_info( "CONNECT", "Connect stage complete.", UVM_MEDIUM );
        end // if

        if ( m_agent_config.get_protocol_checker_enable() ) begin
          // Connecting the monitor to the protocol checker module
          m_monitor.m_axi_superset_write_req_packets_collected.connect(m_protocol_checker.m_write_req_packets_collected.analysis_export);
          m_monitor.m_axi_superset_read_req_packets_collected.connect(m_protocol_checker.m_read_req_packets_collected.analysis_export);
          m_monitor.m_axi_superset_write_rsp_packets_collected.connect(m_protocol_checker.m_write_rsp_packets_collected.analysis_export);
          m_monitor.m_axi_superset_read_rsp_packets_collected.connect(m_protocol_checker.m_read_rsp_packets_collected.analysis_export);
        end

    endfunction: connect_phase

    // -------------------------------------------------------------------------
    // Pre-Reset
    //
    // Stop the sequencer - in case it is active
    // -------------------------------------------------------------------------
    virtual task pre_reset_phase( uvm_phase phase );
        if ( is_active == UVM_ACTIVE ) begin
            m_sequencer.stop_sequences();
            `uvm_info( "STOPPED SEQUENCES", "STOPPED SEQUENCES", UVM_MEDIUM );
        end // if
    endtask: pre_reset_phase

endclass: axi_superset_agent_c
