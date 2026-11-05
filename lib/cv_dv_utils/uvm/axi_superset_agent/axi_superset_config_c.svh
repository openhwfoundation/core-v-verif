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
//  Description : Configuration of the axi driver
//
// ----------------------------------------------------------------------------

// ----------------------------------------------------------------------------
// Class axi_superset_config_c
//
// This class contains the configuration for the agent
//
// ----------------------------------------------------------------------------

class axi_superset_config_c extends uvm_object;

    protected string name;

    // ----------------------------------------------------------------------- 
    // Configuration fields
    // ----------------------------------------------------------------------- 
    axi_dv_ver_t            axi_version             ;
    axi_dv_lite_t           axi_lite                ;
    string                  interface_name          ;
    bit                     is_master_side          ;
    axi_dv_driver_idle_t    driver_idle_value_cfg   ;
    axi_superset_txn_cfg_c  txn_config              ;
    bit                     id_management_enable    ;
    bit                     protocol_checker_enable ;
    bit                     covergroup_enable       ;

    // ------------------------------------------------------------------------
    // Utility/fields macros
    // ------------------------------------------------------------------------
    `uvm_object_utils_begin(axi_superset_config_c)
        `uvm_field_enum       ( axi_dv_ver_t         , axi_version             , UVM_DEFAULT)
        `uvm_field_enum       ( axi_dv_lite_t        , axi_lite                , UVM_DEFAULT)
        `uvm_field_string     (                        interface_name          , UVM_DEFAULT)
        `uvm_field_int        (                        is_master_side          , UVM_DEFAULT)
        `uvm_field_enum       ( axi_dv_driver_idle_t , driver_idle_value_cfg   , UVM_DEFAULT)
        `uvm_field_object     (                        txn_config              , UVM_DEFAULT)
        `uvm_field_int        (                        id_management_enable    , UVM_DEFAULT)
        `uvm_field_int        (                        protocol_checker_enable , UVM_DEFAULT)
        `uvm_field_int        (                        covergroup_enable       , UVM_DEFAULT)
    `uvm_object_utils_end

    // -----------------------------------------------------------------------
    // Constraints
    // -----------------------------------------------------------------------

    // ----------------------------------------------------------------------- 
    // Constructor
    // ----------------------------------------------------------------------- 
    function new( string name = "");
        super.new(name);
        this.name = name;

        // Default values
        axi_version             = AXI4                   ; // VERSION AXI4 by default
        axi_lite                = NO_LITE                ; // NO Lite by default
        interface_name          = "AXI_SUPERSET_IF"      ; // Default name
        is_master_side          = 1'b1                   ; // Master side by default
        driver_idle_value_cfg   = ZERO                   ; // Zero value on idle by default
        txn_config              = null                   ; // Default txn configuration
        id_management_enable    = 1'b1                   ; // Unique id gestion by default
        protocol_checker_enable = 1'b1                   ; // Protocol checker enabled by default
        covergroup_enable       = 1'b0                   ; // Covergroup disabled by default

    endfunction

    // -----------------------------------------------------------------------
    // Functions/tasks
    // -----------------------------------------------------------------------


    // ------------------------------------------------------------------------
    // convert2string
    // ------------------------------------------------------------------------
    virtual function string convert2string;
        string s;

        s = super.convert2string();
        s = $sformatf("%0s : ", this.name);
        s = $sformatf("%0s AXI_VERSION=%0p(p),"              , s , axi_version                 ) ;
        s = $sformatf("%0s AXI_LITE=%0p(p),"                 , s , axi_lite                    ) ;
        s = $sformatf("%0s INTERFACE_NAME=%0s(s),"           , s , interface_name              ) ;
        s = $sformatf("%0s AGENT_MASTER_SIDE=%0b(b),"        , s , is_master_side              ) ;
        s = $sformatf("%0s DRIVER_IDLE_VALUE=%0p(p),"        , s , driver_idle_value_cfg       ) ;
        s = $sformatf("%0s TRANSACTION_CFG=%0s(s),"          , s , txn_config.convert2string() ) ;
        s = $sformatf("%0s ID_MANAGEMENT_ENABLE=%0b(b),"     , s , id_management_enable        ) ;
        s = $sformatf("%0s PROTOCOL_CHECKER_ENABLE=%0b(b),"  , s , protocol_checker_enable     ) ;
        s = $sformatf("%0s COVERGROUP_ENABLE=%0b(b),"        , s , covergroup_enable           ) ;

        return s;
    endfunction: convert2string

    // -----------------------------------------------------------------------
    // AXI version
    // -----------------------------------------------------------------------
    function void set_axi_version( axi_dv_ver_t new_axi_version );
      axi_version = new_axi_version;
    endfunction : set_axi_version

    function axi_dv_ver_t get_axi_version( );
      get_axi_version = axi_version;
    endfunction : get_axi_version

    // -----------------------------------------------------------------------
    // AXI Lite version
    // -----------------------------------------------------------------------
    function void set_axi_lite( axi_dv_lite_t new_axi_lite );
      axi_lite = new_axi_lite;
    endfunction : set_axi_lite

    function axi_dv_lite_t get_axi_lite( );
      get_axi_lite = axi_lite;
    endfunction : get_axi_lite

    // -----------------------------------------------------------------------
    // Interface name
    // -----------------------------------------------------------------------
    function void set_interface_name( string interface_name );
        this.interface_name = interface_name;
    endfunction

    function string get_interface_name( );
        get_interface_name = this.interface_name;
    endfunction

    // -----------------------------------------------------------------------
    // Master/Slave
    // -----------------------------------------------------------------------
    function void set_is_master_side( bit new_is_master_side );
      this.is_master_side = new_is_master_side;
    endfunction : set_is_master_side

    function bit get_is_master_side( );
      get_is_master_side = this.is_master_side;
    endfunction : get_is_master_side

    // -----------------------------------------------------------------------
    // Set/Get idle value tasks
    // -----------------------------------------------------------------------
    function void set_driver_idle_value_cfg( axi_dv_driver_idle_t driver_idle_value_cfg );
      `uvm_info($sformatf("%0s_CONFIG_DRIVER_IDLE_VALUE", this.name),
                $sformatf("NEW_CFG_DRIVER_IDLE_VALUE_CFG=%0p(p)", driver_idle_value_cfg),
                UVM_DEBUG);
      this.driver_idle_value_cfg = driver_idle_value_cfg ;
    endfunction: set_driver_idle_value_cfg

    function axi_dv_driver_idle_t get_driver_idle_value_cfg( );
      get_driver_idle_value_cfg = this.driver_idle_value_cfg;
    endfunction: get_driver_idle_value_cfg

    // TXN CONFIGURATION
    function axi_superset_txn_cfg_c get_txn_config();
      if ( txn_config == null )
        `uvm_fatal("NO_TXN_CONFIG",
          $sformatf("The agent was not given any transaction configuration. The user should use create its own transaction configuration when configuring the agent, and use the function set_txn_config to set the transaction configuration in the agent configuration ") )
      get_txn_config = txn_config  ;
    endfunction : get_txn_config

    function void set_txn_config( axi_superset_txn_cfg_c config_i );
      txn_config = config_i ;
    endfunction: set_txn_config

    // -----------------------------------------------------------------------
    // id_management_enable
    // -----------------------------------------------------------------------
    function void set_id_management_enable( bit new_id_management_enable );
      this.id_management_enable = new_id_management_enable;
    endfunction : set_id_management_enable

    function bit get_id_management_enable( );
      get_id_management_enable = this.id_management_enable;
    endfunction : get_id_management_enable

    // -----------------------------------------------------------------------
    // protocol_checker_enable
    // -----------------------------------------------------------------------
    function void set_protocol_checker_enable( bit new_protocol_checker_enable );
      this.protocol_checker_enable = new_protocol_checker_enable;
    endfunction : set_protocol_checker_enable

    function bit get_protocol_checker_enable( );
      get_protocol_checker_enable = this.protocol_checker_enable;
    endfunction : get_protocol_checker_enable

    // -----------------------------------------------------------------------
    // covergroup_enable
    // -----------------------------------------------------------------------
    function void set_covergroup_enable( bit new_covergroup_enable );
      this.covergroup_enable = new_covergroup_enable;
    endfunction : set_covergroup_enable

    function bit get_covergroup_enable( );
      get_covergroup_enable = this.covergroup_enable;
    endfunction : get_covergroup_enable

endclass
