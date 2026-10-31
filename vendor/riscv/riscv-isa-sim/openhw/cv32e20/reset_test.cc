// See LICENSE for license details.

#include "Proc.h"
#include "cfg.h"
#include "csrs.h"
#include "debug_defines.h"
#include "debug_module.h"
#include "isa_parser.h"
#include "simif.h"

#include <array>
#include <cstring>
#include <iostream>
#include <map>
#include <string>
#include <vector>

namespace {

constexpr reg_t kSecureSeed = 0x7c1;

class test_sim_t : public simif_t {
 public:
  explicit test_sim_t(const cfg_t &cfg) : cfg_(cfg) { memory_.fill(0); }

  void attach(processor_t *hart) { harts_[0] = hart; }
  char *addr_to_mem(reg_t addr) override {
    return addr < memory_.size() ? reinterpret_cast<char *>(&memory_[addr]) : nullptr;
  }
  bool mmio_load(reg_t, size_t, uint8_t *) override { return false; }
  bool mmio_store(reg_t, size_t, const uint8_t *) override { return false; }
  void proc_reset(unsigned) override { ++reset_count; }
  const cfg_t &get_cfg() const override { return cfg_; }
  const std::map<size_t, processor_t *> &get_harts() const override { return harts_; }
  const char *get_symbol(uint64_t) override { return nullptr; }

  void write32(size_t addr, uint32_t value) {
    for (unsigned i = 0; i < 4; ++i) memory_.at(addr + i) = value >> (8 * i);
  }
  void write16(size_t addr, uint16_t value) {
    for (unsigned i = 0; i < 2; ++i) memory_.at(addr + i) = value >> (8 * i);
  }
  unsigned reset_count = 0;

 private:
  const cfg_t &cfg_;
  std::map<size_t, processor_t *> harts_;
  std::array<uint8_t, 4096> memory_;
};

bool expect(bool condition, const std::string &message)
{
  if (!condition)
    std::cerr << "FAILED: " << message << '\n';
  return condition;
}

bool present(openhw::Processor &hart, reg_t address)
{
  return hart.get_state()->csrmap.count(address) != 0;
}

class reset_test_processor_t : public openhw::Processor {
 public:
  using openhw::Processor::Processor;

  void write_hpm_counter(size_t index, reg_t value)
  {
    hpm_counters().at(index)->backdoor_write(value);
  }

  void dirty_transient_state()
  {
    taken_trap = true;
    taken_debug = true;
    which_trap = 1;
    which_debug = 1;
    nmi_inject = true;
    cve2_trigger_execute = true;
  }

  bool transient_state_is_reset() const
  {
    return !taken_trap && !taken_debug && which_trap == 0 &&
           which_debug == 0 && !nmi_inject && !cve2_trigger_execute;
  }

 private:
  std::array<std::shared_ptr<basic_csr_t>, 6> hpm_counters() const
  {
    return {hpm_loads, hpm_stores, hpm_jumps, hpm_branches,
            hpm_branches_taken, hpm_instret_c};
  }
};

bool check_cve2_reset_state(reset_test_processor_t &hart,
                            const std::string &phase, bool mutate = true)
{
  static constexpr std::array<reg_t, 6> hpm_low = {
      CSR_MHPMCOUNTER5, CSR_MHPMCOUNTER6, CSR_MHPMCOUNTER7,
      CSR_MHPMCOUNTER8, CSR_MHPMCOUNTER9, CSR_MHPMCOUNTER10};
  static constexpr std::array<reg_t, 6> hpm_high = {
      CSR_MHPMCOUNTER5H, CSR_MHPMCOUNTER6H, CSR_MHPMCOUNTER7H,
      CSR_MHPMCOUNTER8H, CSR_MHPMCOUNTER9H, CSR_MHPMCOUNTER10H};

  bool ok = true;
  auto check = [&](bool condition, const std::string &message) {
    ok = expect(condition, phase + ": " + message) && ok;
  };

  check(!present(hart, CSR_TINFO), "tinfo must not be implemented");
  check(present(hart, CSR_MSCONTEXT), "mscontext must be implemented");
  check(present(hart, CSR_SCONTEXT), "scontext must be implemented");
  check(present(hart, kSecureSeed), "secureseed must be implemented");
  check(present(hart, CSR_MCOUNTINHIBIT),
        "mcountinhibit must be implemented");
  check(hart.transient_state_is_reset(),
        "CV32E20 transient state must have reset values");

  if (present(hart, kSecureSeed))
    check(hart.get_csr(kSecureSeed) == 0, "secureseed must reset to zero");
  if (present(hart, CSR_MCOUNTINHIBIT)) {
    check(hart.get_csr(CSR_MCOUNTINHIBIT) == 0,
          "mcountinhibit must reset to zero");
    if (mutate) {
      hart.put_csr(CSR_MCOUNTINHIBIT, 0x7e0);
      check(hart.get_csr(CSR_MCOUNTINHIBIT) == 0x7e0,
            "mcountinhibit must remain writable");
    }
  }

  if (mutate && present(hart, CSR_MSCONTEXT) && present(hart, CSR_SCONTEXT)) {
    hart.put_csr(CSR_SCONTEXT, 0);
    hart.put_csr(CSR_MSCONTEXT, 0x5a);
    check(hart.get_csr(CSR_SCONTEXT) == 0x5a,
          "mscontext must remain an alias of scontext");
  }

  for (size_t i = 0; i < hpm_low.size(); ++i) {
    check(present(hart, hpm_low[i]),
          "HPM counter low half " + std::to_string(i + 5) + " is missing");
    check(present(hart, hpm_high[i]),
          "HPM counter high half " + std::to_string(i + 5) + " is missing");
    if (!present(hart, hpm_low[i]) || !present(hart, hpm_high[i]))
      continue;

    check(hart.get_csr(hpm_low[i]) == 0 && hart.get_csr(hpm_high[i]) == 0,
          "HPM counter " + std::to_string(i + 5) + " must reset to zero");
    const reg_t value = (reg_t(i + 1) << 32) | (0x100 + i);
    if (mutate) {
      hart.write_hpm_counter(i, value);
      check(hart.get_csr(hpm_low[i]) == (value & 0xffffffffU) &&
                hart.get_csr(hpm_high[i]) == (value >> 32),
            "HPM counter " + std::to_string(i + 5) +
                " must remain connected to its readable CSR halves");
    }
  }

  if (mutate) hart.dirty_transient_state();
  return ok;
}

bool check_instruction_counters(reset_test_processor_t &hart, test_sim_t &sim,
                                bool inhibit)
{
  // lw, sw, jal, taken beq, c.nop: one retirement for each event counter.
  sim.write32(0x00, 0x00012183);  // lw x3, 0(x2)
  sim.write32(0x04, 0x00312223);  // sw x3, 4(x2)
  sim.write32(0x08, 0x0040006f);  // jal x0, 4
  sim.write32(0x0c, 0x00000263);  // beq x0, x0, 4
  sim.write16(0x10, 0x0001);      // c.nop
  sim.write32(0x100, 0x12345678);
  hart.get_state()->pc = 0;
  hart.get_state()->XPR.write(2, 0x100);
  hart.put_csr(CSR_MCOUNTINHIBIT, inhibit ? 0x7e0 : 0);

  st_rvfi reference{};
  reference.csr_addr[CSR_MSTATUS] = CSR_MSTATUS;
  const std::array<reg_t, 5> pcs = {0, 4, 8, 12, 16};
  bool ok = true;
  for (reg_t pc : pcs) {
    const st_rvfi retired = hart.step(1, reference);
    ok = expect(retired.pc_rdata == pc && retired.trap == 0,
                "instruction must retire without a trap at PC " +
                    std::to_string(pc)) && ok;
  }
  const std::array<reg_t, 6> counters = {
      CSR_MHPMCOUNTER5, CSR_MHPMCOUNTER6, CSR_MHPMCOUNTER7,
      CSR_MHPMCOUNTER8, CSR_MHPMCOUNTER9, CSR_MHPMCOUNTER10};
  for (size_t i = 0; i < counters.size(); ++i)
    ok = expect(hart.get_csr(counters[i]) == (inhibit ? 0 : 1),
                "instruction counter " + std::to_string(i + 5) +
                    (inhibit ? " must be inhibited" : " must increment")) && ok;
  return ok;
}

}  // namespace

int main()
{
  // The CV32E20 constructor installs its own ISA parser after base setup.
  isa_parser_t isa("RV32IMC", "M");
  cfg_t cfg({0, 0}, nullptr, "RV32IMC", "M", DEFAULT_VARCH, false,
            endianness_little, 16, std::vector<mem_cfg_t>{},
            std::vector<size_t>{0}, false, 4);
  openhw::Params params;
  test_sim_t sim(cfg);
  reset_test_processor_t hart(&isa, &cfg, &sim, 0, false, nullptr,
                              std::cerr, params);
  sim.attach(&hart);

  bool ok = check_cve2_reset_state(hart, "after construction");

  // debug_module_t stores harts as processor_t pointers.  Repeated calls
  // through that base type exercise both virtual dispatch and reset stability.
  processor_t *debug_hart = &hart;
  for (unsigned reset = 1; reset <= 3; ++reset) {
    debug_hart->reset();
    ok = check_cve2_reset_state(
             hart, "after base-pointer reset " + std::to_string(reset)) &&
         ok;
  }

  hart.reset();
  ok = check_instruction_counters(hart, sim, false) && ok;
  hart.reset();
  ok = check_cve2_reset_state(hart, "after instruction reset", false) && ok;
  ok = check_instruction_counters(hart, sim, true) && ok;

  debug_module_config_t dm_config{};
  dm_config.progbufsize = 2;
  dm_config.max_sba_data_width = 32;
  debug_module_t dm(&sim, dm_config);
  for (uint32_t reset_bit : {uint32_t(DM_DMCONTROL_HARTRESET),
                             uint32_t(DM_DMCONTROL_NDMRESET)}) {
    const unsigned resets_before = sim.reset_count;
    ok = expect(dm.dmi_write(DM_DMCONTROL,
                             DM_DMCONTROL_DMACTIVE | reset_bit),
                "debug module reset command must succeed") && ok;
    ok = expect(sim.reset_count == resets_before + 1,
                "debug module must reset the hart exactly once") && ok;
    ok = check_cve2_reset_state(hart, reset_bit == DM_DMCONTROL_HARTRESET
                                         ? "after hartreset" : "after ndmreset",
                                false) && ok;
    ok = check_instruction_counters(hart, sim, false) && ok;
    dm.dmi_write(DM_DMCONTROL, DM_DMCONTROL_DMACTIVE);
  }

  if (!ok)
    return 1;

  std::cout << "PASS: CV32E20 CSR and HPM state is reset-stable\n";
  return 0;
}
