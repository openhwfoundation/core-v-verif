// Copyright 2023 OpenHW Group
//
// Licensed under the Solderpad Hardware Licence, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://solderpad.org/licenses/
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

`ifndef __RVFI_SPIKE_SV__
`define __RVFI_SPIKE_SV__

import "DPI-C" function int spike_create(string filename);
import "DPI-C" function void spike_delete();

import "DPI-C" function void spike_set_param_uint64_t(string base, string name, longint unsigned value);
import "DPI-C" function void spike_set_param_str(string base, string name, string value);
import "DPI-C" function void spike_set_param_bool(string base, string name, bit value);
import "DPI-C" function longint unsigned spike_get_param_uint64_t(string base, string name);
import "DPI-C" function string spike_get_param_str(string base, string name);
import "DPI-C" function bit spike_get_param_bool(string base, string name);
import "DPI-C" function void spike_set_default_params(string profile);
import "DPI-C" function void spike_set_params_from_file(string paramFilePath);

import "DPI-C" function void spike_step_svLogic(inout vector_rvfi core, inout vector_rvfi reference_model);
import "DPI-C" function void spike_step_struct(inout st_rvfi core, inout st_rvfi reference_model);

import "DPI-C" function void spike_get_csr(input longint unsigned proc_id,
    input longint unsigned csr_addr, inout longint unsigned value);

import "DPI-C" function void spike_put_csr(input longint unsigned proc_id,
    input longint unsigned csr_addr, input longint unsigned value);

    function automatic void rvfi_initialize_spike(string core_name, st_core_cntrl_cfg core_cfg);
        string binary, config_file;
        string rtl_isa, rtl_priv;
        string base;
        longint unsigned boot_addr;

        base = $sformatf("/top/core/%0d/", core_cfg.mhartid);

        if ($value$plusargs("elf_file=%s", binary))
            `uvm_info("spike_tandem", $sformatf("Setting up Spike with binary %s...", binary), UVM_LOW);

        if (binary == "") begin
            `uvm_error("spike_tandem", "We need a preloaded binary for tandem verification");
        end

        void'(spike_set_default_params(core_name));

        rtl_isa = get_isa_str(core_cfg);
        rtl_priv = get_priv_str(core_cfg);

        if ($value$plusargs("config_file=%s", config_file)) begin
            void'(spike_set_params_from_file(config_file));
            // If core address is not set or is zero (FORNOW no way to discriminate
            // between these conditions), take the "/top/cores/boot_addr" value
            // (possibly equal to zero).
            boot_addr = spike_get_param_uint64_t(base, "boot_addr");
            if (boot_addr == 0)
                boot_addr = spike_get_param_uint64_t("/top/cores/", "boot_addr");

        end else begin

            if (core_cfg.ext_cv32a60x_supported) begin
                void'(spike_set_param_str("/top/core/0/", "extensions", "cv32a60x"));
            end

            void'(spike_set_param_uint64_t("/top/", "num_procs", 64'h1));

            void'(spike_set_param_bool("/top/", "misaligned", core_cfg.unaligned_access_supported));

            void'(spike_set_param_uint64_t(base, "pmpregions_max", core_cfg.pmp_regions));
            void'(spike_set_param_uint64_t(base, "pmpregions_writable", core_cfg.pmp_regions));
            void'(spike_set_param_bool(base, "misaligned", core_cfg.unaligned_access_supported));

            void'(spike_set_param_uint64_t("/top/", "num_procs", 64'h1));

            void'(spike_set_param_uint64_t(base, "mhartid_override_mask", 64'hFFFFFFFF));
            void'(spike_set_param_uint64_t(base, "mhartid_override_value", core_cfg.mhartid));

            void'(spike_set_param_uint64_t(base, "marchid_override_mask", 64'hFFFFFFFF));
            void'(spike_set_param_uint64_t(base, "marchid_override_value", core_cfg.marchid));

            void'(spike_set_param_uint64_t(base, "mvendorid_override_mask", 64'hFFFFFFFF));
            void'(spike_set_param_uint64_t(base, "mvendorid_override_value", core_cfg.mvendorid));

            void'(spike_set_param_bool(base, "csr_counters_injection", 1'h1));

            if (core_cfg.dram_valid) begin
                void'(spike_set_param_bool("/top/", "dram_enable", core_cfg.dram_valid));
                void'(spike_set_param_uint64_t("/top/", "dram_base", core_cfg.dram_base));
                void'(spike_set_param_uint64_t("/top/", "dram_size", core_cfg.dram_size));
            end
            void'(spike_set_param_bool(base, "unified_traps", core_cfg.unified_traps));

            // FORNOW FIXME TODO: Hardcoded bootrom base address
            boot_addr = 64'h10000;
        end

        // Keep the ISA string of the configuration file when there is one:
        // get_isa_str() only lists the base extensions and a few Z extensions.
        if (config_file == "") begin
            void'(spike_set_param_str("/top/", "isa", rtl_isa));
            void'(spike_set_param_str(base, "isa", rtl_isa));
        end
        void'(spike_set_param_str("/top/", "priv", rtl_priv));
        void'(spike_set_param_str(base, "priv", rtl_priv));

        // Override default boot address with the address from UVM config.
        if (core_cfg.boot_addr_valid) begin
	    if (boot_addr != core_cfg.boot_addr) begin
                `uvm_info("SPIKE tandem",
                         $sformatf("Overriding default boot address 0x%08h with UVM setting: 0x%08h",
                                   boot_addr, core_cfg.boot_addr), UVM_NONE);
                boot_addr = core_cfg.boot_addr;
            end
        end

        void'(spike_set_param_uint64_t(base, "boot_addr", boot_addr));
        `uvm_info("spike_tandem", $sformatf("core_name: %s", core_name), UVM_LOW);
        `uvm_info("spike_tandem", $sformatf("boot_addr: 0x%08h", boot_addr), UVM_LOW);
        `uvm_info("spike_tandem", $sformatf("isa: '%s'", rtl_isa), UVM_LOW);

        if (core_name == "cve2") begin
            void'(spike_set_param_uint64_t(base, "mtvec_override_mask", 64'h1));
            void'(spike_set_param_uint64_t(base, "mtvec_override_value", 64'h1));
            void'(spike_set_param_uint64_t(base, "mtvec_write_mask", 64'hFFFFFFFE));
            void'(spike_set_param_uint64_t(base, "mstatus_override_mask", 64'hFFFFFFFF));
            void'(spike_set_param_uint64_t(base, "mstatus_override_value", 64'h1800));
            void'(spike_set_param_uint64_t(base, "tdata1_override_mask", 64'hFFFFFFFF));
            void'(spike_set_param_uint64_t(base, "tdata1_override_value", 64'h28001048));
            void'(spike_set_param_bool(base, "tdata1_we", 1'h0));
            void'(spike_set_param_bool(base, "tdata1_we_enable", 1'h1));
            void'(spike_set_param_bool(base, "non_standard_interrupts", 1'h1));
            void'(spike_set_param_bool(base, "tinfo_presence", 1'h0));
            void'(spike_set_param_uint64_t(base, "trigger_count", 64'h0001));
        end

        void'(spike_create(binary));

    endfunction : rvfi_initialize_spike

    function automatic void rvfi_spike_step(ref st_rvfi s_core, ref st_rvfi s_reference_model);

        union_rvfi u_core;
        union_rvfi u_reference_model;
        bit [ST_NUM_WORDS-1:0][63:0] a_core;
        bit [ST_NUM_WORDS-1:0][63:0] a_reference_model;

        u_core.rvfi = s_core;

        a_core = u_core.array;

        spike_step_svLogic(a_core, a_reference_model);

        u_reference_model.array = a_reference_model;

        s_reference_model = u_reference_model.rvfi;

    endfunction : rvfi_spike_step

`endif

