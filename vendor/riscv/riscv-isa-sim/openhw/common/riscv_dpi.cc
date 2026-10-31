#include <fesvr/elf.h>
#include <fesvr/memif.h>

#include "Simulation.h"
#include "Types.h"
#include "riscv/mmu.h"
#include "YamlParamSetter.h"

#include "svdpi.h"
#include <vpi_user.h>

#include <fcntl.h>
#include <memory>
#include <stdio.h>
#include <stdlib.h>
#include <string>
#include <stdexcept>
#include <sys/mman.h>
#include <sys/stat.h>
#include <vector>

#include <assert.h>
#include <iostream>
#include <map>
#include <unistd.h>

using namespace openhw;

Simulation *sim;
std::vector<std::pair<reg_t, mem_t *>> mem_cuts;

#define SHT_PROGBITS 0x1
#define SHT_GROUP 0x11

#define BOOTROM_BASE 0x10000
#define BOOTROM_SIZE 0x1000

std::vector<mem_cfg_t> memory_map;
Params params;
std::unique_ptr<YamlParamSetter> paramSetter;

extern "C" void spike_set_default_params(const char *profile) {
  if (strncmp(profile, "cv64a", 5) == 0) {
    params.set_string("/top/", "isa", std::string("RV64GC"));
    params.set_string("/top/", "priv", std::string(DEFAULT_PRIV)); // MSU
    params.set_string("/top/cores/", "isa", std::string("RV64GC"));
  } else if ((strncmp(profile, "cv32a", 5) == 0) || (strcmp(profile, "hwconfig") == 0)) {
    // FIXME TODO: We assume hwconfig is a 32b configuration.
    // params.set_string("/top/", "isa", std::string("RV32IMC"));
    params.set_string("/top/", "priv", std::string("M"));
    params.set_string("/top/cores/", "isa", std::string("RV32IMC"));
  } else if (strncmp(profile, "cve2", 4) == 0) {
  } else  {
    std::cerr << "[SPIKE] spike_set_default_params(): UNSUPPORTED target config '" << profile << "', cannot continue!\n";
    exit(1);
  }
  params.set_string("/top/core/0/", "name", std::string(profile));
  params.set_uint64_t("/top/", "num_procs", 0x1UL);
  params.set_bool("/top/", "bootrom", true);
  params.set_bool("/top/", "generic_core_config", false);
  params.set_uint64_t("/top/", "bootrom_base", 0x10000UL);
  params.set_uint64_t("/top/", "bootrom_size", 0x1000UL);
  params.set_uint64_t("/top/", "dram_base", 0x80000000UL);
  params.set_uint64_t("/top/", "dram_size", 0x400UL * 1024 * 1024);
  params.set_bool("/top/", "max_steps_enabled", false);
  params.set_uint64_t("/top/", "max_steps", 2000000UL);

  Simulation::default_params(params);
}

extern "C" void spike_set_param_uint64_t(const char *base, const char *name,
                                         uint64_t value) {
  params.set_uint64_t(base, name, value);
}

extern "C" void spike_set_param_str(const char *base, const char *name,
                                    const char *value) {
  params.set_string(base, name, std::string(value));
}

extern "C" void spike_set_param_bool(const char *base, const char *name,
                                     bool value) {
  params.set_bool(base, name, value);
}

extern "C" uint64_t spike_get_param_uint64_t(const char *base, const char *name)
{
  return params.get(base, name).a_uint64_t;
}

extern "C" const char *spike_get_param_str(const char *base, const char *name)
{
  return params.get(base, name).a_string.c_str();
}

extern "C" bool spike_get_param_bool(const char *base, const char *name)
{
  return params.get(base, name).a_bool;
}

extern "C" void spike_set_params_from_file(const char *yaml_config_path) {
  cerr << "[SPIKE] Setting parameters from file : " << yaml_config_path << endl;
  paramSetter = std::make_unique<YamlParamSetter>(&params, yaml_config_path);
  paramSetter->setParams();
}

extern "C" void spike_delete() {
    delete sim;
}

extern "C" void spike_create(const char *filename) {
  std::cerr << "[SPIKE] Starting 'spike_create'...\n";
  // TODO parse params from yaml
  string isa_str = (params["/top/core/0/isa"]).a_string;
  string priv_str = (params["/top/core/0/priv"]).a_string;

  cfg_t *config = new cfg_t(
      /*default_initrd_bounds=*/std::make_pair((reg_t)0, (reg_t)0),
      /*default_bootargs=*/nullptr,
      /*default_isa=*/isa_str.c_str(), // Built from the RTL configuration
      /*default_priv=*/priv_str.c_str(),   // TODO FIXME Ditto
      /*default_varch=*/DEFAULT_VARCH, // TODO FIXME Ditto
      /*default_misaligned=*/false,
      /*default_endianness*/ endianness_little,
      /*default_pmpregions=*/16,
      /*default_mem_layout=*/memory_map,
      /*default_hartids=*/std::vector<size_t>(),
      /*default_real_time_clint=*/false,
      /*default_trigger_count=*/4);

  // Define the default set of harts with their associated IDs.
  // If there are multiple IDs, the vector must be sorted in ascending
  // order and w/o duplicates, see 'parse_hartids' in spike_main/spike.cc.

  // FIXME FORNOW only a single hart with ID 0.
  std::vector<size_t> default_hartids;
  default_hartids.reserve(1); // Reserve nprocs() slots.
  default_hartids.push_back(0);
  config->hartids = default_hartids;

  if (!sim) {
    std::vector<std::string> htif_args;
    htif_args.push_back(std::string(filename));

    std::cerr << "[SPIKE] htif_args = {\n";
    for (auto s : htif_args)
      std::cerr << "  " << s << ",\n";
    std::cerr << "}\n";

    Param a_num_procs = params["/top/num_procs"];
    uint64_t num_procs = (a_num_procs).a_uint64_t
                             ? (a_num_procs).a_uint64_t
                             : config->nprocs();
    Param a_generic_config = params["/top/generic_core_config"];
    bool generic_config = (a_generic_config).a_bool;

    mapParam coreParams = params.get_base("/top/cores/");

    std::vector<uint64_t> hartids = params.get_hartids();
    std::sort(hartids.begin(), hartids.end());

    uint64_t next_id =
        (hartids.size() == 0 ? 0 : hartids[hartids.size() - 1] + 1);

    for (size_t i = 0; i < (num_procs - hartids.size()); i++) {
      hartids.push_back(next_id + i);
    }

    config->hartids = hartids;

    if (generic_config) {
      for (size_t i = 0; i < num_procs; i++) {
        string base = "/top/core/" + std::to_string(hartids[i]) + "/";
        for (auto p : coreParams) {
          params.set(base, p.first, p.second);
        }
      }
    }

    sim = new Simulation((const cfg_t *)config, filename, params);

    // Disable the debug mode.
    sim->sim_t::set_debug(false);
  }
}

// Convert svOpenArrayHandle -> st_rvfi
void sv2rvfi(st_rvfi &rvfi, svLogicVecVal* svOpen) {
  size_t size = sizeof(st_rvfi) / 8;
  uint64_t *array_ptr = (uint64_t *)(svOpen);
  uint64_t *rvfi_ptr = (uint64_t *)&rvfi;

  for (size_t i = 0; i < size; i++) {
    rvfi_ptr[i] = array_ptr[size - i - 1];
  }
}

// Convert st_rvfi -> svOpenArrayHandle
void rvfi2sv(st_rvfi &rvfi, svLogicVecVal* svOpen) {
  size_t size = sizeof(st_rvfi) / 8;
  uint64_t *array_ptr = (uint64_t *)(svOpen);
  uint64_t *rvfi_ptr = (uint64_t *)&rvfi;

  for (size_t i = 0; i < size; i++) {
      array_ptr[size - i - 1] = rvfi_ptr[i];
  }
}

extern "C" void spike_step_struct(st_rvfi &reference, st_rvfi &spike) {
  std::vector<st_rvfi> vreference, vspike;
  vreference.push_back(reference);
  vspike = sim->step(1, vreference);
  spike = vspike[0];
}

// Keep Spike in sync with an RTL hart reset during tandem simulation.
extern "C" void spike_reset_hart(uint64_t hart_id) {
  if (!sim)
    throw std::runtime_error("spike_reset_hart called before spike_create");
  auto* proc = sim->get_core_by_id(hart_id);
  if (!proc)
    throw std::runtime_error("spike_reset_hart called with an unknown hart ID");
  proc->reset();
}

extern "C" void spike_step_svLogic(svLogicVecVal* reference,
                                       svLogicVecVal* spike) {
  st_rvfi reference_rvfi, spike_rvfi;

  sv2rvfi(reference_rvfi, reference);
  spike_step_struct(reference_rvfi, spike_rvfi);
  rvfi2sv(spike_rvfi, spike);
}

extern "C" void spike_get_csr(uint64_t proc_id, uint64_t csr_addr, uint64_t &value) {
  auto proc = sim->get_core_by_id(proc_id);
  if (proc != nullptr)
    value = proc->get_csr(csr_addr);
}

extern "C" void spike_put_csr(uint64_t proc_id, uint64_t csr_addr, uint64_t value) {
  auto proc = sim->get_core_by_id(proc_id);
  if (proc != nullptr)
    proc->put_csr(csr_addr, value);
}
