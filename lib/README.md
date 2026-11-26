## LIB: Library of reusable verification components

Verification Components for the CORE-V verification environments.  Examples
include UVM Agents for various physical interfaces, memory models, scoreboards, etc.

## corev-dv
corev-dv is the general name for the customization layer of SystemVerilog developed by OpenHW contributors to
customize and enhance the Google RISCV-DV generator https://github.com/google/riscv-dv.
This directory contains general corev-dv code shared by all OpenHW core.  Each core includes its own corev-dv directory in its env/ directory containing core-specific customziations.

## cv_dv_utils
Library of Design Verification components and utilties contrbuted by CEA.  See [cv_dv_utils/README.md](cv_dv_utils/README.md) for more information.

## dpi_dasm
Library for disassembling/decoding instruction binaries, based on sources from Spike.  (Note: not recommended for new verification environments.)

## mem_regions_gen
Model of PMA memory regions.

## sim_libs
Library of behavioral simulation models of non-RTL functions and other non-UVM verification components


## uvm_agents
Collection of UVM Agents.  Note that currently our AXI Agent is located at [cv_dv_utils/uvm/axi_superset_agent](cv_dv_utils/uvm/axi_superset_agent).

## uvm_components
Library of UVM components.

## uvm_libs
All other UVM verification components



