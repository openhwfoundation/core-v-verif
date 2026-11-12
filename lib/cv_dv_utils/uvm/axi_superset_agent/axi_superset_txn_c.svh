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
//  Description : First set of the AXI superset transaction
//
// ----------------------------------------------------------------------------

// -----------------------------------------------------------------------
// Class axi_superset_txn_c
//
// This class contains the fields necessary to represent each transaction type
// from either AXI4 or a subset of AXI5.
//
// This class can manage either a WRITE_REQ, a READ_REQ, a WRITE_RSP or
// a READ_RSP and the type of the transaction is defined in the m_txn_type
// field.
//
// The AXI protocol version is defined by the field m_axi_version. Currently
// only a subset of AXI4 and AXI5 protocols is supported.
//
// Protocol errors can be enabled/disabled in the transaction with the field m_err:
// if the value of this field is NO_ERR, the transaction will be randomized with constraints
// to respect the AXI protocol. Other values of m_err are not yet supported.
//
// By default, the bus width of some fields are oversized to allow the user to
// use this transaction with multiple instances of different AXI interfaces
// in the same testbench.
// - The oversized fields are the fields m_id, m_addr, m_data, m_user, m_loop,
//   m_mmusid and m_mmussid.
// - The MAX value of these fields are defined in the package.
// - Typedef of each oversized fields are defined in the package, to allow the
//   user to reuse them in its testbench.
// - It is possible to configure the actual width of these configurable fields of an instance
//   of a transaction with the class m_txn_config.
//   The configuration class contains the fields and the methods necessary to configure
//   the width of the configurable bus widths.
// - It is assumed that the transaction already has its own configuration before randomizing it,
//   as part of the randomization of the transaction depending on its configuration.
// - The randomization is in charge of fixing to 0 the unused bits between the
//   configurated bus width and the MAX width.
// - When created, the transaction does not have a default configuration. The user must pass their desired 
// configuration, otherwise a UVM_FATAL will be triggered.
//
// Concerning the AXI transaction, the class contains the following elements:
//  - All the metadatas of the transaction : id, addr, size, len, burst, etc...
//  - The total payload of the transaction : all flits of data of the
//    transaction are stored in the fields m_data, m_wstrb, m_last and
//    m_resp.
//    These fields are queues, where each item is a single flit
//    of the transaction.
//    - m_wstrb is concerned only in a case of a AXI_WRITE_REQ.
//    - m_resp is concerned only in cases of an AXI_WRITE_RSP or an AXI_READ_RSP.
//      This field should only have one flit in a case of an AXI_WRITE_RSP, and can have more than
//      one flit only in a case of a AXI_READ_RSP.
//    - In the randomization, the field m_len is solved before all the payload fields : that means
//      that the size of the queue (and so number of flit of the transaction) for the m_data/m_wstrb/etc
//      is determined by the value of the len.
//      So when the transaction is randomized, the value of the len have to be constrained to match the
//      number of flits wanted by the user.
//      The user can also constrain each flit (data/wstrb/etc) as long as their number matches the len.
//    - The write strobe is managed differently: to obtain a write
//      strobe coherent with the protocol instead of a fully random write
//      strobe, the write strobe is regenerated in the post randomize phase
//      using the equation of the specification. If the user decides to set
//      himself the write strobe, he must set a valid write strobe by
//      himself.
//  - By default, when the transaction is created but not yet randomized, the queue are empty and all fields
//    contains X
//  - Concerning the cache value, a mem_type from the section A4.4 of the
//    specification IHI022H_c is randomized. Then in the driver, depending of
//    the transaction type, the corresponding cache value is sent on the
//    interface. The user should be aware of the memory type that should be
//    sent when randomizing the transaction. Also, only preferred AXI4 cache 
//    value from the specification are used, not the legal AXI3 values
//
// This class also contains fields to define delays. The delays are expressed
// here in number of cycles:
// - The field m_delay_cycle_chan_X defines the number of cycles before enabling the
//   valid signal of the corresponding channel.
//   The channels concerned by this field are the channels AW, AR, R and B
// - The field m_delay_cycle_chan_W defines the number of cycles before enabling the
//   valid signal of the W channel. This fields is here to allow to
//   desynchronize the AW and W channels.
// - The field m_delay_cycle_flits defines the number of cycles between each flits of
//   a transaction before enabling the valid signal of the W channel or the R channel.
//   Each flit can have its own delay defined in the queue m_delay_cycle_flits.
//
//
// Methods
// - convert2string :
//    Convert the transaction into a string to print it in debug message.
// - get_total_number_of_bytes_exchanged :
//    Return the total number of bytes exchanged by the transaction on the
//    interface
// - get_total_number_of_bytes_in_mem :
//    Return the total number of bytes written or read in the memory by the
//    transaction
// - compare_bytes_in_mem :
//    Compare two transactions to check if the number of bytes written or read
//    in the memory is the same
// - append_write_flit()
//    User provides a data flit and it is appended to the write request.
// - append_read_flit()
//    User provides a data flit and it is appended to the read response.
// - set/get functions for all metadata/payload fields of the transactions
//
// The user fields are not totally supported in this agent for the moment: it
// is not possible currently to define for each channel its own user bus width.
// All channels have the same user fields bus width currently, defined in the
// package.
// -----------------------------------------------------------------------
//
class axi_superset_txn_c extends uvm_sequence_item;

    protected string name;

    // ------------------------------------------------------------------------
    // Fields
    // ------------------------------------------------------------------------
    // Transaction verification fields
    rand axi_dv_txn_type_t     m_txn_type    ;
    rand axi_dv_ver_t          m_axi_version ;
    rand axi_dv_lite_t         m_lite        ;
    rand axi_dv_err_t          m_err         ;

    // AXI4 fields
    rand axi_sig_id_t          m_id           ;
    rand axi_sig_addr_t        m_addr         ;
    rand axi_sig_data_t        m_data[$]      ;
    rand axi_sig_wstrb_t       m_wstrb[$]     ;
    rand logic                 m_last[$]      ;
    rand axi_sig_len_t         m_len          ;
    rand axi_dv_size_t         m_size         ;
    rand axi_dv_burst_t        m_burst        ;
    rand axi_dv_lock_t         m_lock         ;
    rand axi_sig_cache_t       m_cache        ;
    rand axi_dv_prot_t         m_prot         ;
    rand axi_sig_qos_t         m_qos          ;
    rand axi_sig_region_t      m_region       ;
    rand axi_sig_user_t        m_user         ;
    rand axi_dv_resp_t         m_resp[$]      ;

    rand axi_sig_user_t        m_w_user       ;

    // AXI5 specific fields    
    rand axi_sig_atop_t        m_atop         ;
    rand logic                 m_trace        ;
    rand axi_sig_loop_t        m_loop         ; // Up to 8  bits from the spec, but configurable normally
    rand logic                 m_mmusecsid    ;
    rand axi_sig_mmusid_t      m_mmusid       ; // Up to 32 bits from the spec, but configurable normally
    rand logic                 m_mmussidv     ;
    rand axi_sig_mmussid_t     m_mmussid      ; // Up to 20 bits from the spec, but configurable normally
    rand logic                 m_mmuatst      ;
    rand axi_sig_nsaid_t       m_nsaid        ;
    rand logic                 m_idunq        ;
    rand axi_sig_datachk_t     m_datachk      ;
    rand axi_sig_poison_t      m_poison       ;

    rand logic                 m_w_trace      ;

    // Memory type for the m_cache encoding
    rand axi_dv_mem_type_t     m_mem_type     ;

    // Internal fields to store the addr, lower byte / upper byte / wrap
    // boundary.
    // Can serve for debug purpose on master side, or to have the necessary
    // value to write in the memory for each flit on slave side.
    rand axi_sig_addr_t        m_flit_addr[$] ;
    rand int unsigned          m_flit_lower_byte_lane[$];
    rand int unsigned          m_flit_upper_byte_lane[$];

    // Channel delay fields
    rand int unsigned          m_delay_cycle_chan_X   ; // Delay before driving the transaction on the AW/AR/B/R channels
    rand int unsigned          m_delay_cycle_chan_W   ; // Delay before driving the transaction on the W channel
    rand int unsigned          m_delay_cycle_flits[$] ; // Delay in cycles between two flits on the W or the R channels

    // Internal fields to generate m_atop field
    rand axi_sig_atop_type_t       m_atop_type       ; // Atomic transaction type (None, Load, Store, Compare, Swap)
    rand axi_sig_atop_endianness_t m_atop_endianness ; // Endianness that is required for arithmetic operation in case of AtomicStore and AtomicLoad
    rand axi_sig_atop_op_t         m_atop_op         ; // Operation encodings for AtomicStore and AtomicLoad

    // Configuration field: this fields contains the width of the configurable
    // bus width
    axi_superset_txn_cfg_c     m_txn_config  ;

    // Timestamp: array that contains the timestamp of the reception of each
    // flit of the transaction. This fields is used only in the monitor.
    // Stil some reflection is needed for this fields
    time                  m_timestamp[$] ;

    // ------------------------------------------------------------------------
    // Utility/fields macros
    // ------------------------------------------------------------------------
    `uvm_object_utils_begin(axi_superset_txn_c)
        `uvm_field_int        (                     m_id                 , UVM_DEFAULT | UVM_HEX)
        `uvm_field_int        (                     m_addr               , UVM_DEFAULT | UVM_HEX)
        `uvm_field_queue_int  (                     m_data               , UVM_DEFAULT | UVM_HEX)
        `uvm_field_queue_int  (                     m_wstrb              , UVM_DEFAULT | UVM_HEX)
        `uvm_field_queue_int  (                     m_last               , UVM_DEFAULT | UVM_DEC)
        `uvm_field_int        (                     m_datachk            , UVM_DEFAULT | UVM_HEX)
        `uvm_field_int        (                     m_poison             , UVM_DEFAULT | UVM_HEX)
        `uvm_field_int        (                     m_len                , UVM_DEFAULT | UVM_DEC)
        `uvm_field_enum       ( axi_dv_size_t     , m_size               , UVM_DEFAULT)
        `uvm_field_enum       ( axi_dv_burst_t    , m_burst              , UVM_DEFAULT)
        `uvm_field_enum       ( axi_dv_lock_t     , m_lock               , UVM_DEFAULT)
        `uvm_field_int        (                     m_cache              , UVM_DEFAULT | UVM_BIN)
        `uvm_field_enum       ( axi_dv_prot_t     , m_prot               , UVM_DEFAULT)
        `uvm_field_int        (                     m_qos                , UVM_DEFAULT | UVM_HEX)
        `uvm_field_int        (                     m_region             , UVM_DEFAULT | UVM_HEX)
        `uvm_field_int        (                     m_user               , UVM_DEFAULT | UVM_HEX)
        `uvm_field_int        (                     m_w_user             , UVM_DEFAULT | UVM_HEX)
        `uvm_field_int        (                     m_atop               , UVM_DEFAULT | UVM_HEX)
        `uvm_field_int        (                     m_trace              , UVM_DEFAULT | UVM_HEX)
        `uvm_field_int        (                     m_w_trace            , UVM_DEFAULT | UVM_HEX)
        `uvm_field_int        (                     m_loop               , UVM_DEFAULT | UVM_HEX)
        `uvm_field_int        (                     m_mmusecsid          , UVM_DEFAULT | UVM_HEX)
        `uvm_field_int        (                     m_mmusid             , UVM_DEFAULT | UVM_HEX)
        `uvm_field_int        (                     m_mmussidv           , UVM_DEFAULT | UVM_HEX)
        `uvm_field_int        (                     m_mmussid            , UVM_DEFAULT | UVM_HEX)
        `uvm_field_int        (                     m_mmuatst            , UVM_DEFAULT | UVM_HEX)
        `uvm_field_int        (                     m_nsaid              , UVM_DEFAULT | UVM_HEX)
        `uvm_field_int        (                     m_idunq              , UVM_DEFAULT | UVM_BIN)
        `uvm_field_queue_enum ( axi_dv_resp_t     , m_resp               , UVM_DEFAULT)
        `uvm_field_enum       ( axi_dv_txn_type_t , m_txn_type           , UVM_DEFAULT)
        `uvm_field_enum       ( axi_dv_ver_t      , m_axi_version        , UVM_DEFAULT | UVM_NOCOMPARE)
        `uvm_field_enum       ( axi_dv_lite_t     , m_lite               , UVM_DEFAULT | UVM_NOCOMPARE)
        `uvm_field_enum       ( axi_dv_mem_type_t , m_mem_type           , UVM_DEFAULT)
        `uvm_field_object     (                     m_txn_config         , UVM_DEFAULT | UVM_NOCOMPARE)
        `uvm_field_int        (                     m_delay_cycle_chan_X , UVM_DEFAULT | UVM_NOCOMPARE)
        `uvm_field_int        (                     m_delay_cycle_chan_W , UVM_DEFAULT | UVM_NOCOMPARE)
        `uvm_field_queue_int  (                     m_delay_cycle_flits  , UVM_DEFAULT | UVM_NOCOMPARE)
        `uvm_field_queue_int  (                     m_flit_addr          , UVM_DEFAULT | UVM_NOCOMPARE)
        `uvm_field_queue_int  (                     m_flit_upper_byte_lane , UVM_DEFAULT | UVM_NOCOMPARE)
        `uvm_field_queue_int  (                     m_flit_lower_byte_lane , UVM_DEFAULT | UVM_NOCOMPARE)
        `uvm_field_queue_int  (                     m_timestamp          , UVM_DEFAULT | UVM_NOCOMPARE)
    `uvm_object_utils_end


    // ------------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------------
    function new(string name = "axi_superset_txn_c");
        super.new(name);
        this.name = name;

        // Default configuration
        m_axi_version = AXI4;
        m_lite = NO_LITE;

    endfunction

    // -----------------------------------------------------------------------
    // -----------------------------------------------------------------------
    // Constraints
    // -----------------------------------------------------------------------
    // -----------------------------------------------------------------------

    // ------------------------------------------------------------------------
    // Protocol constraints
    // ------------------------------------------------------------------------
    // Channel protocol constraints
    constraint c_size_data_width  { 2**m_size <= m_txn_config.get_data_width()/8 ; }
    constraint c_data_length      { m_data.size()              == m_len + 1 ; }
    constraint c_wstrb_length     { m_wstrb.size()             == m_len + 1 ; }
    constraint c_last_length      { m_last.size()              == m_len + 1 ; }
    constraint c_resp_length      { m_resp.size()              == m_len + 1 ; }
    constraint c_delay_flits      { m_delay_cycle_flits.size() == m_len + 1 ; }

    constraint c_flits_addr       { m_flit_addr.size()            == m_len + 1 ; }
    constraint c_flits_lb         { m_flit_lower_byte_lane.size() == m_len + 1 ; }
    constraint c_flits_up         { m_flit_upper_byte_lane.size() == m_len + 1 ; }

    // Constraint to force each last flit to be set to 0, apart from the
    // last one which is set to 1, to follow the AXI protocol.
    constraint c_last
    {
      foreach( m_last[i] )
        { if ( i != m_last.size()-1 ) m_last[i] == 0 ;
          else                        m_last[i] == 1 ;
        }
    }

    // According to AXI spec section E1.1.3
    constraint c_atop_size  {
      m_atop_type inside { ATOP_STORE, ATOP_LOAD, ATOP_SWAP} -> (m_size inside { BYTES_1, BYTES_2, BYTES_4, BYTES_8 }) ;
      ( m_atop_type == ATOP_CMP )                            -> (m_size inside { BYTES_2, BYTES_4, BYTES_8, BYTES_16, BYTES_32 });
    }
    // According to AXI spec section E1.1.3
    constraint c_atop_burst_type {
      m_atop_type inside { ATOP_STORE, ATOP_LOAD, ATOP_SWAP} -> ( m_burst == INCR );
    }

    // Constraint for the burst type
    constraint c_burst_reserved { m_burst != RESERVED ; }
    constraint c_burst_wrap_aligned { ( m_burst == WRAP  ) -> ( m_addr == m_addr + m_addr % ( 2**m_size ) ) ; }
    constraint c_burst_wrap_length  { ( m_burst == WRAP  ) -> 
                                      ( ( m_len + 1 == 2  ) ||
                                        ( m_len + 1 == 4  ) ||
                                        ( m_len + 1 == 8  ) ||
                                        ( m_len + 1 == 16 ) ) ;
                                    }

    // Misc constraint
    constraint c_X_delay    { m_delay_cycle_chan_X <= m_txn_config.get_max_delay_cycles() ; }
    constraint c_mem_type   { m_mem_type != CACHE_RESERVED ; }

    constraint c_axi5_lite   { ( m_axi_version == AXI5 ) -> ( m_lite != LITE ) ; }

    // Constraint for the Lite mode
    constraint c_lite_size   { ( m_lite == LITE ) -> ( 2**m_size  == m_txn_config.get_data_width()/8 ) ; }
    constraint c_lite_addr   { ( m_lite == LITE ) -> ( m_addr     == m_addr + m_addr % ( m_txn_config.get_data_width()/8 ) ) ; }
    constraint c_lite_length { ( m_lite == LITE ) -> ( m_len      == 0 ) ; }
    constraint c_lite_cache  { ( m_lite == LITE ) -> ( m_mem_type == DEVICE_NON_BUFFERABLE ) ; }
    constraint c_lite_prot   { ( m_lite == LITE ) -> ( m_lock     == NORMAL ) ; }

    // AW channel
    constraint c_AW_cache_value { ( m_txn_type == AXI_WRITE_REQ ) -> ( m_cache == get_cache_value( AXI_WRITE_REQ, m_mem_type ) ) ; }

    // W channel
    constraint c_W_wstrb_size
    { foreach( m_wstrb[i] ) { ( m_txn_type == AXI_WRITE_REQ ) -> ( $countones(m_wstrb[i]) <= 2**m_size ) ; } }
    // Arbitrary upper bound delay
    constraint c_W_delay    { ( m_txn_type == AXI_WRITE_REQ ) -> ( m_delay_cycle_chan_W <= m_txn_config.get_max_delay_cycles() ) ; }
    // Arbitrary upper bound delay
    constraint c_W_flits_delay
    { foreach( m_delay_cycle_flits[i] ) { ( m_txn_type == AXI_WRITE_REQ ) -> ( m_delay_cycle_flits[i] <= m_txn_config.get_max_delay_cycles() ) ; } }

    // B channel
    constraint c_B_len { ( m_txn_type == AXI_WRITE_RSP ) -> ( m_len == 0 ) ; }

    // AR channel
    constraint c_AR_channel
    { ( m_txn_type == AXI_READ_REQ ) && (m_axi_version == AXI5) ->
      ( ( m_atop_type == ATOP_NONE ) && ( m_datachk == 0 ) && ( m_poison == 0 ) );
    }
    constraint c_AR_cache_value { ( m_txn_type == AXI_READ_REQ ) -> ( m_cache == get_cache_value( AXI_READ_REQ, m_mem_type ) ) ; }

    // R channel
    // Arbitrary upper bound delay
    constraint c_R_flits_delay
    { foreach( m_delay_cycle_flits[i] ) { ( m_txn_type == AXI_READ_RSP ) -> ( m_delay_cycle_flits[i] <= m_txn_config.get_max_delay_cycles() ) ; } }

    // Version constraints
    constraint c_axi4_version
    { ( m_axi_version == AXI4 ) ->
      ( ( m_atop_type == ATOP_NONE ) && ( m_trace    == 0 ) && ( m_loop     == 0 ) &&
        ( m_mmusecsid == 0 ) && ( m_mmusid   == 0 ) && ( m_mmussidv == 0 ) &&
        ( m_mmussid   == 0 ) && ( m_mmuatst  == 0 ) && ( m_nsaid    == 0 ) &&
        ( m_idunq     == 0 ) && ( m_datachk  == 0 ) && ( m_poison   == 0 ) );
    }

    // All the fields that are not supported by the current version of the AXI agent are driven to zero
    constraint c_unsupported_fields
    { ( m_trace    == 0 ) && ( m_loop     == 0 ) &&
      ( m_mmusecsid == 0 ) && ( m_mmusid   == 0 ) && ( m_mmussidv == 0 ) &&
      ( m_mmussid   == 0 ) && ( m_mmuatst  == 0 ) && ( m_nsaid    == 0 ) &&
      ( m_datachk   == 0 ) && ( m_poison   == 0 ) ;
    }
    // Constraint to generate m_atop 
    constraint c_atop_field {
      if ( ( m_atop_type == ATOP_LOAD ) || ( m_atop_type == ATOP_STORE ) ) 
        m_atop == ( m_atop_type || ( m_atop_endianness << 3 ) || m_atop_op ) ;
      else
        m_atop == m_atop_type; 
    }
    constraint c_atomic_txns
    { ( m_atop_type != ATOP_NONE ) -> (m_lock == NORMAL); }
    constraint c_atop_addr   { ( m_atop_type != ATOP_NONE ) -> ( m_addr == m_addr + m_addr % m_size ) ; }

    // Exclusive accesses and ATOPs are non-modifiable transactions
    // cf. section A4.3.1 of AXI specifications
    constraint c_non_modifiable_txns
    { ( m_atop_type != ATOP_NONE ) -> (m_mem_type inside { DEVICE_NON_BUFFERABLE , DEVICE_BUFFERABLE } ) ; }

    // ------------------------------------------------------------------------
    // Exclusive access restrictions (Section A7.2.4)
    // ------------------------------------------------------------------------
    constraint c_excl_addr
    { 
      ( m_lock == EXCLUSIVE ) ->
      ( m_addr == m_addr + m_addr % ( ( m_len + 1 ) * ( 2**m_size ) ) ) ;
    }
    constraint c_excl_len
    {
      ( m_lock == EXCLUSIVE ) -> ( m_len + 1 <= 15 ) ;
    }
    constraint c_excl_tot_nb_byte_exchanged
    {
      ( m_lock == EXCLUSIVE ) -> ( ( m_len + 1 ) * ( 2**m_size ) <= 128 ) ;
    }
    constraint c_excl_nb_byte_exchanged
    { ( m_lock == EXCLUSIVE ) ->
      ( ( ( m_len + 1 ) * ( 2**m_size ) == 1   ) ||
        ( ( m_len + 1 ) * ( 2**m_size ) == 2   ) ||
        ( ( m_len + 1 ) * ( 2**m_size ) == 4   ) ||
        ( ( m_len + 1 ) * ( 2**m_size ) == 8   ) ||
        ( ( m_len + 1 ) * ( 2**m_size ) == 16  ) ||
        ( ( m_len + 1 ) * ( 2**m_size ) == 32  ) ||
        ( ( m_len + 1 ) * ( 2**m_size ) == 64  ) ||
        ( ( m_len + 1 ) * ( 2**m_size ) == 128 ) ) ;
    }
    constraint c_excl_mem_type
    { ( m_lock == EXCLUSIVE ) ->
      ( m_mem_type inside { DEVICE_BUFFERABLE,
                            NORMAL_NON_CACHEABLE_NON_BUFFERABLE,
                            NORMAL_NON_CACHEABLE_BUFFERABLE,
                            WRITE_THROUGH_NO_ALLOCATE,
                            WRITE_THROUGH_READ_ALLOCATE,
                            WRITE_THROUGH_WRITE_ALLOCATE,
                            WRITE_THROUGH_READ_AND_WRITE_ALLOCATE }
      ) ;
    }

    // ------------------------------------------------------------------------
    // Ordering constraints
    // ------------------------------------------------------------------------
    constraint c_atop_type_before_atop  { solve m_atop_type       before m_atop     ; }
    constraint c_atop_type_before_cache { solve m_atop_type       before m_mem_type ; }
    constraint c_lock_before_cache      { solve m_lock            before m_mem_type ; }
    constraint c_atop_type_before_lock  { solve m_atop_type       before m_lock     ; }
    constraint c_endianness_before_atop { solve m_atop_endianness before m_atop     ; }
    constraint c_version_before_type    { solve m_axi_version     before m_txn_type ; }
    constraint c_version_before_lite    { solve m_axi_version     before m_lite     ; }
    constraint c_lite_before_err        { solve m_lite            before m_err      ; }
    constraint c_size_before_wstrb      { solve m_size            before m_wstrb    ; }
    constraint c_type_before_burst      { solve m_txn_type        before m_burst    ; }
    constraint c_burst_before_len       { solve m_burst           before m_len      ; }
    constraint c_burst_before_addr      { solve m_burst           before m_addr     ; }
    constraint c_lock_before_size       { solve m_lock            before m_size     ; }
    constraint c_lock_before_len        { solve m_lock            before m_len      ; }

    constraint c_len_before_data        { solve m_len before m_data              ; }
    constraint c_len_before_last        { solve m_len before m_last              ; }
    constraint c_len_before_wstrb       { solve m_len before m_wstrb             ; }
    constraint c_len_before_resp        { solve m_len before m_resp              ; }
    constraint c_len_before_delay_flits { solve m_len before m_delay_cycle_flits ; }
    constraint c_len_before_timestamp   { solve m_len before m_timestamp         ; }

    // Enum to logic conversion constraint
    constraint c_type_before_mem_type   { solve m_txn_type before m_mem_type ; }
    constraint c_mem_type_before_cache  { solve m_mem_type before m_cache    ; }

    // Constraint for the atop support
    constraint c_atop_before_size       { solve m_atop_type before m_size ; }

    // ------------------------------------------------------------------------
    // Configuration constraints
    // ------------------------------------------------------------------------
    // General
    constraint c_id_cfg      { m_id      <= 2**m_txn_config.get_id_width()-1      ; }
    constraint c_addr_cfg    { m_addr    <= 2**m_txn_config.get_addr_width()-1    ; }
    constraint c_user_cfg    { m_user    <= 2**m_txn_config.get_user_width()-1    ; }
    constraint c_loop_cfg    { m_loop    <= 2**m_txn_config.get_loop_width()-1    ; }
    constraint c_mmusid_cfg  { m_mmusid  <= 2**m_txn_config.get_mmusid_width()-1  ; }
    constraint c_mmussid_cfg { m_mmussid <= 2**m_txn_config.get_mmussid_width()-1 ; }

    // Data config constraints
    constraint c_data_cfg    { foreach( m_data[i]  ) { m_data[i]  <= 2**m_txn_config.get_data_width()-1     ; } }
    constraint c_wstrb_cfg   { foreach( m_wstrb[i] ) { m_wstrb[i] <= 2**(m_txn_config.get_data_width()/8)-1 ; } }

    constraint c_datachk_cfg { m_datachk <= 2**(m_txn_config.get_data_width()/8)-1  ; }
    constraint c_poison_cfg  { m_poison  <= 2**(m_txn_config.get_data_width()/64)-1 ; }

    function void pre_randomize();
      if ( m_txn_config == null )
        `uvm_fatal("NO_TXN_CONFIG",
          $sformatf("The transaction was not given any transaction configuration before the randomization. The user should use the function set_config to set a configuration for the transaction corresponding to the axi interface") )
    endfunction : pre_randomize

    function void post_randomize();
      int unsigned bus_nbytes, nb_bytes ;
      int unsigned lower_byte_lane, upper_byte_lane ;
      axi_sig_addr_t aligned_addr, address_n ;
      axi_sig_addr_t wrap_boundary ; 

      super.post_randomize();

      // Using the equation of the specification, section A3.4 of the IHI022H
      // version of the amba axi protocol to regenerate a valid write strobe
      // for the transaction
      // Computing some variables
      bus_nbytes    = m_txn_config.get_data_width() / 8;
      nb_bytes      = 2**m_size ;
      aligned_addr  = axi_sig_addr_t'( m_addr / nb_bytes ) * nb_bytes ;
      wrap_boundary = axi_sig_addr_t'( m_addr / ( nb_bytes * ( m_len + 1 ) ) ) * ( nb_bytes * ( m_len + 1 ) ) ;

      if ( m_txn_type == AXI_WRITE_REQ ) begin
        logic flag_wrap = 0 ; // Flag to determine when the address has wrapped, if BURST_TYPE == WRAP
        foreach ( m_wstrb[i] ) begin
          logic flag_error ; // Flag which is only used for debug purpose: if there is a problem in the write strobe generation, an error is printed

          // Equation from the specification
          if ( m_burst != FIXED ) begin // Burst mode INCR or WRAP

            // Computing the address and byte lane for the first flit of the
            // transaction
            if ( i == 0 ) begin
              address_n       = m_addr ;
              lower_byte_lane = m_addr - int'( m_addr / bus_nbytes ) * bus_nbytes;
              upper_byte_lane = aligned_addr + ( nb_bytes - 1 ) - int'( m_addr / bus_nbytes ) * bus_nbytes ;
            end else begin
              // Computing the flit address depending of the burst mode, and
              // if the transaction has wrapped or not.
              if ( ( m_burst == WRAP ) && flag_wrap ) begin // If burst mode is WRAP and the transaction has already wrapped
                address_n = m_addr + ( i * nb_bytes ) - ( nb_bytes * ( m_len + 1 ) ) ;
              end else begin // For burst mode INCR, and WRAP if the transaction has not wrapped
                address_n = aligned_addr + i * nb_bytes;
              end

              // Computing the byte lane
              lower_byte_lane = address_n - int'( address_n / bus_nbytes ) * bus_nbytes;
              upper_byte_lane = lower_byte_lane + nb_bytes - 1;
            end

            // Checking for the burst mode WRAP if the address has wrapped
            if ( address_n == ( wrap_boundary + ( nb_bytes * ( m_len + 1 ) ) ) ) begin
              flag_wrap = 1 ;
              address_n = wrap_boundary ;

              // Computing the byte lane again since address_n has been
              // changed
              lower_byte_lane = address_n - int'( address_n / bus_nbytes ) * bus_nbytes;
              upper_byte_lane = lower_byte_lane + nb_bytes - 1;
            end // if wrap

          end else begin // Burst mode FIXED
            // Constant addr and byte lane for all flits of the transaction
            address_n = m_addr ;
            lower_byte_lane = m_addr - int'( m_addr / bus_nbytes ) * bus_nbytes;
            upper_byte_lane = aligned_addr + ( nb_bytes - 1 ) - int'( m_addr / bus_nbytes ) * bus_nbytes ;
          end // if FIXED

          // Filling the lower byte / upper byte / flit addr queue for the
          // corresponding flit
          m_flit_addr[i]            = address_n       ;
          m_flit_lower_byte_lane[i] = lower_byte_lane ;
          m_flit_upper_byte_lane[i] = upper_byte_lane ;

          // Cleaning the write strobe, to re randomize it bit by bit
          m_wstrb[i] = 'h0 ;
          flag_error = 1;
          for ( int j = 0 ; j < bus_nbytes ; j++ ) begin
            if ( ( j <= upper_byte_lane ) && ( j >= lower_byte_lane ) ) begin
              logic strb;
              if ( !std::randomize(strb) )
                `uvm_error(this.name,"Randomizing strb error")
              m_wstrb[i][j] = strb ;
            end
            flag_error = 0;
          end

          if ( flag_error )
            `uvm_error(this.name,"Not entered the wstrb loop: error of byte lane computing")
        end
      end

      if ( m_err != NO_ERR )
        `uvm_fatal("UNSUPPORTED_ERROR_MODE",
          $sformatf("The error mode %0p is not supported by this agent. Only the error mode NO_ERR is supported by this agent currently",m_err) )

      if ( m_burst == RESERVED )
        `uvm_fatal("UNSUPPORTED_BURST_MODE", 
          $sformatf("The burst mode RESERVED is not supported by this agent. ") )

    endfunction : post_randomize

    // -----------------------------------------------------------------------
    // -----------------------------------------------------------------------
    // Functions/tasks
    // -----------------------------------------------------------------------
    // -----------------------------------------------------------------------

    // ------------------------------------------------------------------------
    // get_total_number_of_bytes_exchanged
    // Task in charge of counting the total number of bytes exchanged in the
    // transaction.
    // ------------------------------------------------------------------------
    function int get_total_number_of_bytes_exchanged();
      return ( ( this.m_len + 1 ) * ( 2**this.m_size ) ) ;
    endfunction : get_total_number_of_bytes_exchanged

    // ------------------------------------------------------------------------
    // get_total_number_of_bytes_in_mem
    // Task in charge of counting the total number of bytes written or read in
    // the memory by the transaction
    // ------------------------------------------------------------------------
    function int get_total_number_of_bytes_in_mem();
      int number_of_bytes = 0;

      case ( m_txn_type )
        AXI_WRITE_REQ : begin
          foreach ( m_wstrb[i] ) begin
            number_of_bytes += $countones( m_wstrb[i] );
          end // foreach
        end
        AXI_WRITE_RSP : number_of_bytes = 0 ; // the write response has no fields indicating how many bytes were written in the memory
        AXI_READ_REQ  : number_of_bytes = this.get_total_number_of_bytes_exchanged();
        AXI_READ_RSP  : number_of_bytes = this.m_txn_config.get_data_width() * this.m_data.size() ;
      endcase
      get_total_number_of_bytes_in_mem = number_of_bytes;

    endfunction : get_total_number_of_bytes_in_mem

    // ------------------------------------------------------------------------
    // compare_bytes_in_mem
    // Function to compare the number of bytes written or read in the memory
    // between two transactions, which can have different data bus width
    // ------------------------------------------------------------------------
    function bit compare_bytes_in_mem ( axi_superset_txn_c other_txn );
      int this_number_of_bytes  ;
      int other_number_of_bytes ;

      this_number_of_bytes  = this.get_total_number_of_bytes_in_mem();
      other_number_of_bytes = other_txn.get_total_number_of_bytes_in_mem();

      if ( this_number_of_bytes != other_number_of_bytes ) return 0;
      else return 1;

    endfunction : compare_bytes_in_mem

    // ------------------------------------------------------------------------
    // convert2string
    // ------------------------------------------------------------------------
    virtual function string convert2string;
        string s;
        string array;

        s = super.convert2string();
        s = $sformatf("%s, ID=%0h(h)", m_txn_type, m_id);

        if ( ( m_txn_type == AXI_WRITE_REQ ) || ( m_txn_type == AXI_READ_REQ ) ) begin
            s = $sformatf("%0s, ADDR=%0h(h), LEN=%0h(h), SIZE=%0p(h), BURST=%0p(h), LOCK=%0p(d), CACHE=%0h(h), MEM_TYPE=%0p(p), PROT=%0b(b), QOS=%0h(h), REGION=%0h(h)",
                        s    ,
                        m_addr        ,
                        m_len         ,
                        m_size        ,
                        m_burst       ,
                        m_lock        ,
                        m_cache       ,
                        m_mem_type    ,
                        m_prot        ,
                        m_qos         ,
                        m_region);
        end
        if ( ( m_txn_type == AXI_WRITE_REQ ) || ( m_txn_type == AXI_READ_RSP ) ) begin
            array = "";
            foreach( m_data[i] ) array = $sformatf("%0s%0h ", array, m_data[i]);
            s = $sformatf("%0s, DATA=%0s(h)", s , array);
            if ( ( m_txn_type == AXI_WRITE_REQ ) ) begin
                array = "";
                foreach( m_wstrb[i] ) array = $sformatf("%0s%0h ", array, m_wstrb[i]);
                s = $sformatf("%0s, WSTRB=%0s(h)", s , array);
                array = "";
                foreach( m_flit_addr[i] ) array = $sformatf("%0s%0h ", array, m_flit_addr[i]);
                s = $sformatf("%0s, FLIT_ADDR=%0s(h)", s , array);
                array = "";
                foreach( m_flit_upper_byte_lane[i] ) array = $sformatf("%0s%0h ", array, m_flit_upper_byte_lane[i]);
                s = $sformatf("%0s, FLIT_UPPER_BYTE_LANE=%0s(h)", s , array);
                array = "";
                foreach( m_flit_lower_byte_lane[i] ) array = $sformatf("%0s%0h ", array, m_flit_lower_byte_lane[i]);
                s = $sformatf("%0s, FLIT_LOWER_BYTE_LANE=%0s(h)", s , array);
            end
            s = $sformatf("%0s, LAST=%0p(p)", s , m_last);
        end
        if ( ( m_txn_type == AXI_WRITE_RSP ) || ( m_txn_type == AXI_READ_RSP ) ) begin
            array = "";
            foreach( m_resp[i] ) array = $sformatf("%0s%0p ", array, m_resp[i]);
            s = $sformatf("%0s, RESP=%0s(p)", s , array);
        end

        if ( m_axi_version == AXI5 ) begin
            s = $sformatf("%0s, TRACE=%0h(h), LOOP=%0h(h), MMUSECSID=%0h(h), MMUSID=%0h(h), MMUSSIDV=%0h(h), MMUSSID=%0h(h), MMUATST=%0h(h), NSAID=%0h(h)",
                      s             ,
                      m_trace       ,
                      m_loop        ,
                      m_mmusecsid   ,
                      m_mmusid      ,
                      m_mmussidv    ,
                      m_mmussid     ,
                      m_mmuatst     ,
                      m_nsaid);
            if ( ( m_txn_type == AXI_WRITE_REQ ) || ( m_txn_type == AXI_READ_RSP ) ) begin
                if ( m_txn_type == AXI_WRITE_REQ ) begin
                    s = $sformatf("%0s, ATOP=%0h(h)", s , m_atop);
                end
                s = $sformatf("%0s, DATACHK=%0h(h), POISON=%0h(h)", s , m_datachk, m_poison);
            end
        end

        s = $sformatf("%0s, DELAY_CHANNEL=%0d(d)", s , m_delay_cycle_chan_X);
        if ( m_txn_type == AXI_WRITE_REQ ) begin
          s = $sformatf("%0s, DELAY_W_CHANNEL=%0d(d)", s , m_delay_cycle_chan_W);
        end

        if ( ( m_txn_type == AXI_WRITE_REQ ) || ( m_txn_type == AXI_READ_RSP ) ) begin
            array = "";
            foreach( m_delay_cycle_flits[i] ) array = $sformatf("%0s%0d ", array, m_delay_cycle_flits[i]);
            s = $sformatf("%0s, DELAY_FLITS=%0s(h)", s , array);
        end

        s = $sformatf("%0s, USER=%0h(h), TIME=%0p(p)", s , m_user, m_timestamp);
        return s;
    endfunction: convert2string

    // ------------------------------------------------------------------------
    // function append_write_flit()
    //
    // User provides a data flit and it is appended to the transaction.
    // It is assumed that the transaction is already initialized/randomized
    // when using this function.
    // By default, the function assume the response status is OK, but
    //      user can optionally specify the status.
    // By default, the function assumes the wrtsb is all 1’s.
    // By default, the function will tag the last flit that was received
    //     as last. But, user can optionally provided the last field, in
    //     which it is directly associated with the data.
    // ------------------------------------------------------------------------
    virtual function void append_write_flit(
      axi_sig_data_t data_i,
      axi_sig_wstrb_t wstrb_i = 2**(m_txn_config.get_data_width()/8)-1,
      logic last_i = 1'bx
    );
      if ( m_len + 1 <= MAX_NB_TXN_BURST ) begin
        m_len++;
        m_data.push_back(data_i);
        m_wstrb.push_back(wstrb_i);

        if ( last_i == 1'bx ) begin
          foreach (m_last[i]) m_last[i] = 0 ;
          m_last[m_len] = 1 ;
        end else begin
          m_last.push_back(last_i);
        end // if
      end else begin
        `uvm_warning("ERROR_NB_TXN_BURST",
          $sformatf("Cannot add more flits to this transaction, as there is already the maximum number of flits") )
      end
    endfunction : append_write_flit

    // ------------------------------------------------------------------------
    // function append_read_flit()
    //
    // User provides a data flit and it is appended to the transaction.
    // It is assumed that the transaction is already initialized/randomized
    // when using this function.
    // By default, the function assume the response status is OK, but
    //      user can optionally specify the status.
    // By default, the function will tag the last flit that was received
    //     as last. But, user can optionally provided the last field, in
    //     which it is directly associated with the data.
    // ------------------------------------------------------------------------
    virtual function void append_read_flit(
      axi_sig_data_t data_i,
      axi_dv_resp_t resp_i = OKAY, // assume OK status
      logic last_i  = 1'bx // set to X by default, let user over-ride
    );
      if ( m_data.size() + 1 <= MAX_NB_TXN_BURST ) begin
        m_data.push_back(data_i);  // append data flit
        m_resp.push_back(resp_i);  // append response
        if ( last_i == 1'bx ) begin
          foreach ( m_last[i] ) m_last[i] = 0;
          m_last[m_len + 1] = 1 ;
        end else begin
          m_last.push_back(last_i);
        end // if
      end else begin
        `uvm_warning("ERROR_NB_TXN_BURST",
          $sformatf("Cannot add more flits to this transaction, as there is already the maximum number of flits") )
      end
    endfunction : append_read_flit

    // ------------------------------------------------------------------------
    // set/get functions
    // ------------------------------------------------------------------------
    // ID
    function axi_sig_id_t get_id();
      get_id = m_id ;
    endfunction : get_id

    function void set_id( axi_sig_id_t id_i );
      m_id = id_i ;
    endfunction: set_id

    // ADDR
    function axi_sig_addr_t get_addr();
      get_addr = m_addr ;
    endfunction : get_addr

    function void set_addr( axi_sig_addr_t addr_i );
      m_addr = addr_i ;
    endfunction: set_addr

    // ALL DATA FLITS
    function void get_all_data_flits ( ref axi_sig_data_t data_o [$] );
      foreach ( m_data[i] ) data_o[i] = m_data[i] ;
    endfunction : get_all_data_flits

    function void set_all_data_flits( axi_sig_data_t data_i[$] );
      foreach ( data_i[i] ) m_data[i] = data_i[i] ;
    endfunction: set_all_data_flits

    // DATA FLIT
    function void get_data_flit ( ref axi_sig_data_t data_o, int index );
      if ( index < m_data.size() ) data_o = m_data[index] ;
      else `uvm_warning(this.name, $sformatf("The index %0d is out of bound of the dynamic array of size %0d", index, m_data.size() ) )
    endfunction : get_data_flit

    function void set_data_flit( axi_sig_data_t data_i , int index);
      if ( index < m_data.size() ) m_data[index] = data_i ;
      else `uvm_warning(this.name, $sformatf("The index %0d is out of bound of the dynamic array of size %0d", index, m_data.size() ) )
    endfunction: set_data_flit

    // ALL WSTRB FLITS
    function void get_all_wstrb_flits( ref axi_sig_wstrb_t wstrb_o );
      foreach ( m_wstrb[i] ) wstrb_o[i] = m_wstrb[i] ;
    endfunction : get_all_wstrb_flits

    function void set_all_wstrb_flits( axi_sig_wstrb_t wstrb_i []);
      foreach ( wstrb_i[i] ) m_wstrb[i] = wstrb_i[i] ;
    endfunction: set_all_wstrb_flits

    // WSTRB FLIT
    function void get_wstrb_flit ( ref axi_sig_wstrb_t wstrb_o, int index );
      if ( index < m_wstrb.size() ) wstrb_o = m_wstrb[index] ;
      else `uvm_warning(this.name, $sformatf("The index %0d is out of bound of the dynamic array of size %0d", index, m_wstrb.size() ) )
    endfunction : get_wstrb_flit

    function void set_wstrb_flit( axi_sig_wstrb_t wstrb_i , int index);
      if ( index < m_wstrb.size() ) m_wstrb[index] = wstrb_i ;
      else `uvm_warning(this.name, $sformatf("The index %0d is out of bound of the dynamic array of size %0d", index, m_wstrb.size() ) )
    endfunction: set_wstrb_flit

    // ALL LAST FLITS
    function void get_all_last_flits( ref logic last_o [] );
      foreach ( m_last[i] ) last_o[i] = m_last[i] ;
    endfunction : get_all_last_flits

    function void set_all_last_flits( logic [0:0] last_i [] );
      foreach ( last_i[i] ) m_last[i] = last_i[i] ;
    endfunction: set_all_last_flits

    // LAST FLIT
    function void get_last_flit ( ref logic last_o, int index );
      if ( index < m_last.size() ) last_o = m_last[index] ;
      else `uvm_warning(this.name, $sformatf("The index %0d is out of bound of the dynamic array of size %0d", index, m_last.size() ) )
    endfunction : get_last_flit

    function void set_last_flit( logic last_i , int index);
      if ( index < m_last.size() ) m_last[index] = last_i ;
      else `uvm_warning(this.name, $sformatf("The index %0d is out of bound of the dynamic array of size %0d", index, m_last.size() ) )
    endfunction: set_last_flit

    // LEN
    function logic [7:0] get_len();
      get_len = m_len ;
    endfunction : get_len

    function void set_len( logic [7:0] len_i );
      m_len = len_i ;
    endfunction: set_len

    // SIZE
    function axi_dv_size_t get_size();
      get_size = m_size ;
    endfunction : get_size

    function void set_size( axi_dv_size_t size_i );
      m_size = size_i ;
    endfunction: set_size

    // BURST
    function axi_dv_burst_t get_burst();
      get_burst = m_burst ;
    endfunction : get_burst

    function void set_burst( axi_dv_burst_t burst_i );
      m_burst = burst_i ;
    endfunction: set_burst

    // LOCK
    function axi_dv_lock_t get_lock();
      get_lock = m_lock ;
    endfunction : get_lock

    function void set_lock( axi_dv_lock_t lock_i );
      m_lock = lock_i ;
    endfunction: set_lock

    // CACHE
    function axi_sig_cache_t get_cache();
      get_cache = m_cache ;
    endfunction : get_cache

    function void set_cache( axi_sig_cache_t cache_i );
      m_cache = cache_i ;
    endfunction: set_cache

    // PROT
    function axi_dv_prot_t get_prot();
      get_prot = m_prot ;
    endfunction : get_prot

    function void set_prot( axi_dv_prot_t prot_i );
      m_prot = prot_i ;
    endfunction: set_prot

    // QOS
    function logic [3:0] get_qos();
      get_qos = m_qos ;
    endfunction : get_qos

    function void set_qos( logic [3:0] qos_i );
      m_qos = qos_i ;
    endfunction: set_qos

    // REGION
    function logic [3:0] get_region();
      get_region = m_region ;
    endfunction : get_region

    function void set_region( logic [3:0] region_i );
      m_region = region_i ;
    endfunction: set_region

    // USER
    function axi_sig_user_t get_user();
      get_user = m_user ;
    endfunction : get_user

    function void set_user( axi_sig_user_t user_i );
      m_user = user_i ;
    endfunction: set_user

    // ALL RESP FLITS
    function void get_all_resp_flits( ref axi_dv_resp_t resp_o [] );
      foreach ( m_resp[i] ) resp_o[i] = m_resp[i] ;
    endfunction : get_all_resp_flits

    function void set_all_resp_flits( axi_dv_resp_t resp_i [] );
      foreach ( resp_i[i] ) m_resp[i] = resp_i[i] ;
    endfunction: set_all_resp_flits

    // RESP FLIT
    function void get_resp_flit ( ref axi_dv_resp_t resp_o, int index );
      if ( index < m_resp.size() ) resp_o = m_resp[index] ;
      else `uvm_warning(this.name, $sformatf("The index %0d is out of bound of the dynamic array of size %0d", index, m_resp.size() ) )
    endfunction : get_resp_flit

    function void set_resp_flit( axi_dv_resp_t resp_i , int index);
      if ( index < m_resp.size() ) m_resp[index] = resp_i ;
      else `uvm_warning(this.name, $sformatf("The index %0d is out of bound of the dynamic array of size %0d", index, m_resp.size() ) )
    endfunction: set_resp_flit

    // ATOP
    function logic [5:0] get_atop();
      get_atop = m_atop ;
    endfunction : get_atop

    function void set_atop( logic [5:0] atop_i );
      m_atop = atop_i ;
    endfunction: set_atop

    // TRACE
    function logic get_trace();
      get_trace = m_trace ;
    endfunction : get_trace

    function void set_trace( logic trace_i );
      m_trace = trace_i ;
    endfunction: set_trace

    // LOOP
    function axi_sig_loop_t get_loop();
      get_loop = m_loop ;
    endfunction : get_loop

    function void set_loop( axi_sig_loop_t loop_i );
      m_loop = loop_i ;
    endfunction: set_loop

    // MMUSECSID
    function logic get_mmusecsid();
      get_mmusecsid = m_mmusecsid ;
    endfunction : get_mmusecsid

    function void set_mmusecsid( logic mmusecsid_i );
      m_mmusecsid = mmusecsid_i ;
    endfunction: set_mmusecsid

    // MMUSID
    function axi_sig_mmusid_t get_mmusid();
      get_mmusid = m_mmusid ;
    endfunction : get_mmusid

    function void set_mmusid( axi_sig_mmusid_t mmusid_i );
      m_mmusid = mmusid_i ;
    endfunction: set_mmusid

    // MMUSSIDV
    function logic get_mmussidv();
      get_mmussidv = m_mmussidv ;
    endfunction : get_mmussidv

    function void set_mmussidv( logic mmussidv_i );
      m_mmussidv = mmussidv_i ;
    endfunction: set_mmussidv

    // MMUSSID
    function axi_sig_mmussid_t get_mmussid();
      get_mmussid = m_mmussid ;
    endfunction : get_mmussid

    function void set_mmussid( axi_sig_mmussid_t mmussid_i );
      m_mmussid = mmussid_i ;
    endfunction: set_mmussid

    // MMUATST
    function logic get_mmuatst();
      get_mmuatst = m_mmuatst ;
    endfunction : get_mmuatst

    function void set_mmuatst( logic [3:0] mmuatst_i );
      m_mmuatst = mmuatst_i ;
    endfunction: set_mmuatst

    // NSAID
    function logic [3:0] get_nsaid();
      get_nsaid = m_nsaid ;
    endfunction : get_nsaid

    function void set_nsaid( logic [3:0] nsaid_i );
      m_nsaid = nsaid_i ;
    endfunction: set_nsaid

    // IDUNQ
    function logic [3:0] get_idunq();
      get_idunq = m_idunq ;
    endfunction : get_idunq

    function void set_idunq( logic [3:0] idunq_i );
      m_idunq = idunq_i ;
    endfunction: set_idunq

    // DATACHK
    function axi_sig_datachk_t get_datachk();
      get_datachk = m_datachk ;
    endfunction : get_datachk

    function void set_datachk( axi_sig_datachk_t datachk_i );
      m_datachk = datachk_i ;
    endfunction: set_datachk

    // POISON
    function axi_sig_poison_t get_poison();
      get_poison = m_poison ;
    endfunction : get_poison

    function void set_poison( axi_sig_poison_t poison_i );
      m_poison = poison_i ;
    endfunction: set_poison

    // CONFIGURATION
    function axi_superset_txn_cfg_c get_config();
      get_config = m_txn_config  ;
    endfunction : get_config

    function void set_config( axi_superset_txn_cfg_c config_i );
      `uvm_info("SET_TXN_CONFIG",$sformatf("New config %0s", config_i.convert2string() ), UVM_DEBUG)
      m_txn_config = config_i ;
    endfunction: set_config

    // AX DELAY
    function int get_delay_AX();
      get_delay_AX = m_delay_cycle_chan_X  ;
    endfunction : get_delay_AX

    function void set_delay_AX( int delay_AX_i );
      m_delay_cycle_chan_X = delay_AX_i ;
    endfunction: set_delay_AX

    // W DELAY
    function int get_delay_W();
      get_delay_W = m_delay_cycle_chan_W  ;
    endfunction : get_delay_W

    function void set_delay_W( int delay_W_i );
      m_delay_cycle_chan_W = delay_W_i ;
    endfunction: set_delay_W

    // FLITS DELAY
    function void get_delay_flits( ref int delay_flits_o );
      foreach( m_delay_cycle_flits[i] ) delay_flits_o[i] = m_delay_cycle_flits[i] ;
    endfunction : get_delay_flits

    function void set_delay_flits( int delay_flits_i [] );
      foreach( delay_flits_i[i] ) m_delay_cycle_flits[i] = delay_flits_i[i] ;
    endfunction: set_delay_flits

endclass: axi_superset_txn_c
