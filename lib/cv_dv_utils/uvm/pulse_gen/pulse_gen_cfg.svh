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
//  Description : 
//               configuration class to customize the generation of a pulse  
//                
// 
// ----------------------------------------------------------------------------

class pulse_gen_cfg  extends uvm_object;



    //////////////////////////////////////////////////////
    // Configuration Parameters
    /////////////////////////////////////////////////////
    //////////////////////////////////////////////////////
    // generate a pulse only if m_enable = 1 
    /////////////////////////////////////////////////////
    rand bit unsigned                m_pulse_enable;
    
    //////////////////////////////////////////////////////
    // if 1: Generate a pulse synchronous to a clock
    //    0: Generate an asynchronos pulse  
    /////////////////////////////////////////////////////
    rand bit unsigned                m_pulse_clock_based;

    //////////////////////////////////////////////////////
    // if m_pulse_clock_based: 1:  the time in clock cycle between 2 pulses 
    // if m_pulse_clock_based: 0:  the time in ps between 2 pulses 
    /////////////////////////////////////////////////////
    rand int unsigned                m_pulse_period;

    //////////////////////////////////////////////////////
    // total number of pulses 
    /////////////////////////////////////////////////////
    rand int unsigned                m_pulse_num;

    //////////////////////////////////////////////////////
    // if m_pulse_clock_based: 1:  width of a pulse in clock cycles 
    // if m_pulse_clock_based: 0:  width of a pulse in ps 
    /////////////////////////////////////////////////////
    rand int unsigned                m_pulse_width; 

    //////////////////////////////////////////////////////
    // if m_pulse_clock_based: 1:  phase shift of a pulse with respect to a clock in %
    // --> ex: 25 -> 25*clock_period/100 ps of delay after posedge of a clock 
    // --> first cycle after reset is used to calculate the clock frequency 
    //
    // if m_pulse_clock_based: 0:  not used 
    /////////////////////////////////////////////////////
    rand int unsigned                m_pulse_phase_shift; 

    // ------------------------------------------------------------------------
    // Utilities for the variables
    // ------------------------------------------------------------------------
    `uvm_object_utils_begin( pulse_gen_cfg )
        `uvm_field_int( m_pulse_enable,                 UVM_DEFAULT | UVM_UNSIGNED)
        `uvm_field_int( m_pulse_clock_based,            UVM_DEFAULT | UVM_UNSIGNED)
        `uvm_field_int( m_pulse_num,                    UVM_DEFAULT | UVM_UNSIGNED)
        `uvm_field_int( m_pulse_width,                  UVM_DEFAULT | UVM_UNSIGNED)
        `uvm_field_int( m_pulse_period,                 UVM_DEFAULT | UVM_UNSIGNED)
        `uvm_field_int( m_pulse_phase_shift,            UVM_DEFAULT | UVM_UNSIGNED)
    `uvm_object_utils_end

    function new( string name ="" );
        super.new( name );
    endfunction

    // ------------------------------------------------------------------------
    // Convert2String
    //
    // Return configuration in a pretty, one-line format
    // ------------------------------------------------------------------------
    virtual function string convert2string();
       string s = "";
       
       s = { s, $sformatf( "ENABLE=%0d, ", m_pulse_enable) };
       s = { s, $sformatf( "SYNCHRONOUS=%0d, ", m_pulse_clock_based) };
       s = { s, $sformatf( "PERIOD=%0d, ", m_pulse_period) };
       s = { s, $sformatf( "WIDTH=%0d, " , m_pulse_width) };
       s = { s, $sformatf( "NUMBER=%0d, ", m_pulse_num) };
       s = { s, $sformatf( "PHASE_SHIFT=%0d, ", m_pulse_phase_shift) };
      
       return s;
    endfunction : convert2string

    // Phase shift shall never be > 100% 
    constraint c_pulse_phase_shift {m_pulse_phase_shift <= 100;};

    // to read back the configured total number of pulses
    function int unsigned get_pulse_num();
       return m_pulse_num;
    endfunction

    // -----------------------------------------------------------
    // APIs to configure pulse generator
    //
    // to ebabke ir disable pulse generator
    // -----------------------------------------------------------
    function void set_pulse_enable (int unsigned enable);
       m_pulse_enable = enable;
       `uvm_info("PULSE GEN CFG", $sformatf("Pulse Gen Enable %0x(x)", m_pulse_enable), UVM_DEBUG);
    endfunction

    // to set synchronous or asynchoronous pulse generation
    function void set_pulse_clock_based (int unsigned clock_based);
       m_pulse_clock_based = clock_based;
       `uvm_info("PULSE GEN CFG", $sformatf("Pulse Gen Clock Based %0x(x)", m_pulse_clock_based), UVM_DEBUG);
    endfunction 

    // to set number of pulse to be generated 
    function void set_pulse_num (int unsigned num);
       m_pulse_num = num;
       `uvm_info("PULSE GEN CFG", $sformatf("Pulse Gen Num %0x(x)", m_pulse_num), UVM_DEBUG);
    endfunction 

    // to set pulse width to be generated 
    function void set_pulse_width (int unsigned width);
       m_pulse_width = width;
       `uvm_info("PULSE GEN CFG", $sformatf("Pulse Gen Width %0x(x)", m_pulse_width), UVM_DEBUG);
    endfunction 

    // to set pulse period 
    function void set_pulse_period (int unsigned period);
       m_pulse_period = period;
       `uvm_info("PULSE GEN CFG", $sformatf("Pulse Gen Period %0x(x)", m_pulse_period), UVM_DEBUG);
    endfunction 

    // to set pulse phase shift with respect to a clock
    // 25 -> 25%clock_period 
    function void set_pulse_phase_shift (int unsigned phase_shift);
       if(phase_shift > 100) begin
         `uvm_fatal("PULSE GEN CFG", $sformatf("Pulse Gen Phase Shift is %0x(x) > 100", m_pulse_phase_shift));
       end
       m_pulse_phase_shift = phase_shift;
       `uvm_info("PULSE GEN CFG", $sformatf("Pulse Gen Phase Shift %0x(x)", m_pulse_phase_shift), UVM_DEBUG);
    endfunction 
endclass : pulse_gen_cfg


