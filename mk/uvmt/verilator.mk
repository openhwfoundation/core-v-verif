# Copyright (c) 2026 PlanV GmbH
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

# -------------------------------------
# Testbench setup
# -------------------------------------
VERILATOR := verilator
ifdef VERILATOR_ROOT
VERILATOR := $(VERILATOR_ROOT)/bin/verilator
endif

# UVM Tests and libraries
UVM_TEST ?= $(TEST_UVM_TEST)

ifndef UVM_ROOT
$(error UVM_ROOT is not set. Please export UVM_ROOT pointing to a UVM library root containing src/uvm.sv)
endif

# g++ >= 10 required for -fcoroutines (--timing support)
GXX_VER := $(shell g++ -dumpversion 2>/dev/null | cut -d. -f1)
ifeq ($(shell test $(GXX_VER) -lt 10 2>/dev/null && echo yes),yes)
$(error g++ >= 10 required for -fcoroutines support (found: g++ $(GXX_VER)))
endif
VERILOG_DEFINE_FILES ?=
UVM_FILES += ${UVM_ROOT}/src/uvm.sv
VERILOG_INCLUDE_DIRS = ${UVM_ROOT}/src $(DV_UVME_PATH) $(DV_UVMT_PATH)

# -------------------------------------
# Compilation/simulation configuration
# -------------------------------------
SIM_NAME ?= $(RTLSRC_VLOG_TB_TOP)
SIM_DIR := $(SIM_NAME)-sim
COMPILE_ARGS += +define+UVM_ENABLE_DEPRECATED_API
COMPILE_ARGS += --prefix $(SIM_NAME) -o $(SIM_NAME)

INC_ARGS += $(addprefix +incdir+, $(VERILOG_INCLUDE_DIRS))
SRC_ARGS += $(UVM_FILES)
SRC_ARGS += ${UVM_ROOT}/src/dpi/uvm_dpi.cc
UVMT_FLIST     := $(DV_UVMT_PATH)/uvmt_$(CV_CORE_LC).flist
UVMT_FLIST_VLT := $(SIM_DIR)/uvmt_$(CV_CORE_LC)_verilator.flist
ISS_STUBS_VLT  := $(DV_UVMT_PATH)/uvmt_$(CV_CORE_LC)_verilator_iss_stubs.sv
SRC_ARGS +=  -F $(CV_CORE_MANIFEST) -F $(UVMT_FLIST_VLT) $(ISS_STUBS_VLT)
SRC_ARGS += $(addprefix -f , $(VERILOG_DEFINE_FILES))

EXTRA_ARGS += --timescale 1ns/1ps --error-limit 10000 +define+VERILATOR_SIM +define+$(CV_CORE_UC)_TRACE_EXECUTION --vpi
WARNING_ARGS += -Wno-lint \
	-Wno-SYMRSVDWORD \
	-Wno-COVERIGN \
	-Wno-COMBDLY \
	-Wno-UNOPTFLAT \
	-Wno-MULTIDRIVEN

# -------------------------------------
# Some Useful args for debugging
# -------------------------------------
ifeq ($(json_dump),1)
	EXTRA_ARGS += -dump-tree-json
else
endif
ifeq ($(debug),1)
	EXTRA_ARGS += --debug --gdbbt -CFLAGS -DVL_DEBUG=1
else
endif

# -------------------------------------
# Make UVM test with Verilator
# -------------------------------------

.PHONY: verilate comp run simulate clean test

test: VERI_SIM_FLAGS += +firmware=$(SIM_TEST_PROGRAM_RESULTS)/$(TEST_PROGRAM)$(OPT_RUN_INDEX_SUFFIX).hex
# test: VERI_SIM_FLAGS += +elf_file=$(SIM_TEST_PROGRAM_RESULTS)/$(TEST_PROGRAM)$(OPT_RUN_INDEX_SUFFIX).elf
test: hex run

verilate:
	echo "UVM_TEST = $(UVM_TEST)"
	mkdir -p veri_results $(SIM_DIR)
	sed -e '\|svlib_pkg\.flist$$|d' \
	    -e '\|uvmt_cv32e40p_interrupt_assert\.sv$$|d' \
	    -e '\|uvmt_cv32e40p_debug_assert\.sv$$|d' \
	    $(UVMT_FLIST) > $(UVMT_FLIST_VLT)
	$(VERILATOR) --cc --exe --main --trace --trace-structs --timing -Mdir $(SIM_DIR) \
	${COMPILE_ARGS} ${EXTRA_ARGS} \
	${INC_ARGS} \
	${SRC_ARGS} \
	${WARNING_ARGS} > veri_results/verilate.log 2>&1

NPROC_LIMIT ?= 6
NPROC_USE := $(shell nproc=$$(nproc 2>/dev/null || echo $(NPROC_LIMIT)); [ $$nproc -gt $(NPROC_LIMIT) ] && echo $(NPROC_LIMIT) || echo $$nproc)

comp: verilate
	$(MAKE) -j$(NPROC_USE) -C $(SIM_DIR) $(BUILD_ARGS) -f $(SIM_NAME).mk

run: comp
	$(SIM_DIR)/$(SIM_NAME) +UVM_TESTNAME=$(UVM_TEST) $(VERI_SIM_FLAGS) +UVM_VERBOSITY=UVM_LOW

clean:
	rm -rf simv*.daidir csrc
	rm -rf csrc* simv*
	rm -rf $(SIM_DIR)
	rm -rf dump.vcd
