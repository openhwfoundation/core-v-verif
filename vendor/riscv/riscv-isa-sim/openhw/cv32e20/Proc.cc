#include "Proc.h"
#include "mmu.h"
#include "disasm.h"
#include "extension.h"
#include "arith.h"
#include "common.h"
#include "config.h"
#include "decode_macros.h"
#include <algorithm>
#include <assert.h>
#include <cinttypes>
#include <cmath>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <limits.h>
#include <stdexcept>
#include <string>

// Note: there are multiple references in this file to 'register forwarding',
//       or just simply 'forwarding'.  This is a process by which the state
//       of certain CSRs in the RTL is written (forwarded) to the equivalent
//       CSR in the Spike model.  In all cases, the reason for doign so will
//       be justified.  In some cases, additional verification, that does not
//       relay on this model, will be necessary.

namespace openhw {
st_rvfi Processor::step(size_t n, st_rvfi reference_) {
  st_rvfi rvfi;

  this->reference = & reference_;
  this->step_rvfi = & rvfi;

  bool unified_traps = (this->params[base + "unified_traps"]).a_bool;
  bool interrupts_injection = (this->params[base + "interrupts_injection"]).a_bool;
  bool debug_injection = (this->params[base + "debug_injection"]).a_bool;
  // Use mstatus as a reference
  bool inverse_csr_access = (reference->csr_addr[0x300] != 0x300);

#define INDEX_CSR(INDEX) (inverse_csr_access) ? CSR_MAX_SIZE-1-INDEX : INDEX

  memset(&rvfi, 0, sizeof(st_rvfi));

  do {

    if (this->is_waiting_for_interrupt())
        this->clear_waiting_for_interrupt();

    bool inject_interrupt = ((this->reference->intr & 0b111) == 0b101);

    if (inject_interrupt && interrupts_injection && !this->taken_trap) {
        // We need to ensure this is an interrupt to inject mip
        uint64_t mcause = reference->csr_rdata[INDEX_CSR(CSR_MCAUSE)];
        if (mcause >> 31) {
            uint64_t mip = this->mcause_to_mip(mcause);
            this->get_state()->mip->backdoor_write(mip);
            this->step_rvfi->intr = 0b101; // Interrupt
            this->step_rvfi->intr |= ((mcause & 0x3FF) << 3);
            uint64_t nmi_mcause = (this->params[base + "nmi_mcause"]).a_uint64_t;
            if (nmi_mcause == (mcause & 0x3FF))
                this->nmi_inject = true;
        }
    }

    if (reference->dbg && !this->get_state()->debug_mode && debug_injection && !this->halted()) {
        uint64_t cause = reference->dbg;
        if (cause) {
            enter_debug_mode(cause);
            rvfi.dbg = cause;
            // Do NOT preset rvfi.trap: CVE2 reports plain trap=0 on a
            // debug-entry retirement (dbg/dbg_mode carry the entry signal
            // instead). Presetting it here left nothing to clear it when
            // step() below retires cleanly, mismatching every haltreq entry.
        }
    }

    if (this->taken_trap && !(this->which_trap >> 31)) {
        rvfi.intr = 0b011;
    }

    if (this->taken_debug) {
        rvfi.dbg = this->which_debug;
    }

    this->taken_trap = false;
    this->which_trap = 0;
    this->taken_debug = false;
    this->which_debug = 0;

    rvfi.pc_rdata = this->get_state()->pc;

    // Snapshot before step(): dret clears debug_mode as part of its own
    // execution (riscv/insns/dret.h), so dret's own retirement must report
    // debug_mode=1 (the context it ran under), not the post-effect value --
    // same convention as rvfi.mode/last_inst_priv below.
    bool debug_mode_before_step = this->get_state()->debug_mode;

    processor_t::step(n);

    if (this->taken_trap && (this->which_trap >> 31))
        this->get_state()->mip->backdoor_write(0);

    // First intr of the trap handler
    if ((this->taken_trap || this->taken_debug) && !(this->which_trap >> 31)) {
        rvfi.trap = 1;
        if (this->get_state()->debug_mode) {
            rvfi.trap |= 0x4;
            rvfi.trap |= (this->which_debug & 0x7) << 0x9;
        } else if (this->which_trap >> 31) {
            rvfi.trap |= 0x2;
            rvfi.trap |= (this->which_trap & 0x3F) << 0x3;
        }
    }

    rvfi.dbg_mode = debug_mode_before_step;

    rvfi.mode = this->get_state()->last_inst_priv;
    rvfi.insn =
        (uint32_t)(this->get_state()->last_inst_fetched.bits() & 0xffffffffULL);

    // TODO FIXME Handle multiple/zero writes in a single insn.
    auto &reg_commits = this->get_state()->log_reg_write;
    int xlen = this->get_state()->last_inst_xlen;
    int flen = this->get_state()->last_inst_flen;

    // Bump the independently-modeled HPM counters (mhpmcounter5..10, see
    // Proc.h) for this retirement, gated on mcountinhibit like real hardware.
    if (!rvfi.trap) {
      reg_t mcountinhibit = get_state()->csrmap[CSR_MCOUNTINHIBIT]->read();
      uint32_t insn = rvfi.insn;
      bool compressed = (insn & 0x3) != 0x3;
      reg_t insn_len = compressed ? 2 : 4;
      reg_t pc_before = rvfi.pc_rdata;
      reg_t pc_after = this->get_state()->pc;
      reg_t pc_mask = (this->get_xlen() == 32) ? 0xffffffffULL : ~0ULL;
      bool sequential = ((pc_after & pc_mask) == ((pc_before + insn_len) & pc_mask));

      bool is_jump =
          (insn & MASK_JAL)    == MATCH_JAL    ||
          (insn & MASK_JALR)   == MATCH_JALR   ||
          (insn & MASK_C_J)    == MATCH_C_J    ||
          (insn & MASK_C_JAL)  == MATCH_C_JAL  ||
          (insn & MASK_C_JR)   == MATCH_C_JR   ||
          (insn & MASK_C_JALR) == MATCH_C_JALR;

      bool is_base_branch =
          (insn & MASK_BEQ)    == MATCH_BEQ    ||
          (insn & MASK_BNE)    == MATCH_BNE    ||
          (insn & MASK_BLT)    == MATCH_BLT    ||
          (insn & MASK_BGE)    == MATCH_BGE    ||
          (insn & MASK_BLTU)   == MATCH_BLTU   ||
          (insn & MASK_BGEU)   == MATCH_BGEU;
      bool is_compressed_branch =
          (insn & MASK_C_BEQZ) == MATCH_C_BEQZ ||
          (insn & MASK_C_BNEZ) == MATCH_C_BNEZ;
      bool is_branch = is_base_branch || is_compressed_branch;

      // "Taken" comes from the branch condition, not PC comparison: a
      // branch whose target equals the fall-through PC (e.g. "beq x0, x0,
      // 1f" with "1:" right after -- hpmcounter_basic_test does this) is
      // still taken even though the PC doesn't change. Evaluate the real
      // condition for base-ISA branches; compressed C.BEQZ/C.BNEZ fall back
      // to the PC-comparison heuristic (untested simplification).
      bool taken;
      if (is_base_branch) {
        reg_t rs1 = this->get_state()->last_inst_fetched.rs1();
        reg_t rs2 = this->get_state()->last_inst_fetched.rs2();
        reg_t v1 = this->get_XPR(rs1);
        reg_t v2 = this->get_XPR(rs2);
        uint32_t funct3 = (insn >> 12) & 0x7;
        switch (funct3) {
          case 0: taken = (v1 == v2); break;                    // BEQ
          case 1: taken = (v1 != v2); break;                    // BNE
          case 4: taken = ((sreg_t)v1 <  (sreg_t)v2); break;     // BLT
          case 5: taken = ((sreg_t)v1 >= (sreg_t)v2); break;     // BGE
          case 6: taken = (v1 <  v2); break;                    // BLTU
          case 7: taken = (v1 >= v2); break;                    // BGEU
          default: taken = !sequential; break;
        }
      } else {
        taken = !sequential;
      }

      // log_mem_read/log_mem_write need get_log_commits_enabled(), which
      // this DPI flow never sets -- detect loads/stores by opcode instead.
      // Doesn't implement the "misaligned = two accesses" rule from
      // doc/03_reference/performance_counters.rst (untested simplification).
      bool is_load =
          (insn & MASK_LB)     == MATCH_LB     ||
          (insn & MASK_LBU)    == MATCH_LBU    ||
          (insn & MASK_LH)     == MATCH_LH     ||
          (insn & MASK_LHU)    == MATCH_LHU    ||
          (insn & MASK_LW)     == MATCH_LW     ||
          (insn & MASK_C_LW)   == MATCH_C_LW   ||
          (insn & MASK_C_LWSP) == MATCH_C_LWSP;

      bool is_store =
          (insn & MASK_SB)     == MATCH_SB     ||
          (insn & MASK_SH)     == MATCH_SH     ||
          (insn & MASK_SW)     == MATCH_SW     ||
          (insn & MASK_C_SW)   == MATCH_C_SW   ||
          (insn & MASK_C_SWSP) == MATCH_C_SWSP;

      // basic_csr_t has no bump() -- increment via read()+write(log=false)
      // so this doesn't get mistaken for a CSR write by log_reg_write.
      auto incr = [](std::shared_ptr<basic_csr_t> &c, reg_t n) {
        c->write(c->read() + n, false);
      };
      if (is_load  && !((mcountinhibit >> 5)  & 1)) incr(this->hpm_loads, 1);
      if (is_store && !((mcountinhibit >> 6)  & 1)) incr(this->hpm_stores, 1);
      if (is_jump  && !((mcountinhibit >> 7)  & 1)) incr(this->hpm_jumps, 1);
      if (is_branch) {
        if (!((mcountinhibit >> 8) & 1)) incr(this->hpm_branches, 1);
        if (taken && !((mcountinhibit >> 9) & 1)) incr(this->hpm_branches_taken, 1);
      }
      if (compressed && !((mcountinhibit >> 10) & 1)) incr(this->hpm_instret_c, 1);

      // Store verification: independently compute the store
      // address/mask/data from Spike's own decode + register file.
      // Allows a scoreboard component such as "spike_tandem" to check it
      // against the RTL's self-reported rvfi_mem_addr/wmask/wdata.
      if (is_store) {
        auto &insn_obj = this->get_state()->last_inst_fetched;
        reg_t base_addr, wdata;
        uint64_t wmask;

        if ((insn & MASK_C_SW) == MATCH_C_SW) {
          base_addr = this->get_XPR(insn_obj.rvc_rs1s()) + insn_obj.rvc_lw_imm();
          wdata     = this->get_XPR(insn_obj.rvc_rs2s());
          wmask     = 0xF;
        } else if ((insn & MASK_C_SWSP) == MATCH_C_SWSP) {
          base_addr = this->get_XPR(2 /* x2 = sp; CSS format has no base field */) + insn_obj.rvc_swsp_imm();
          wdata     = this->get_XPR(insn_obj.rvc_rs2());
          wmask     = 0xF;
        } else {
          // SB/SH/SW share the S-type format.
          base_addr = this->get_XPR(insn_obj.rs1()) + insn_obj.s_imm();
          wdata     = this->get_XPR(insn_obj.rs2());
          wmask     = ((insn & MASK_SW) == MATCH_SW) ? 0xF
                     : ((insn & MASK_SH) == MATCH_SH) ? 0x3 : 0x1;
        }

        rvfi.mem_addr  = base_addr;
        rvfi.mem_wmask = wmask;
        rvfi.mem_wdata = wdata;
      } else {
        // The outer memset() only runs once before this function's
        // do-while loop, not per iteration -- without an explicit clear
        // here, a non-store instruction retired on a later loop iteration
        // (e.g. the jump following a trap handler's epilogue store, under
        // unified_traps) would otherwise inherit a stale nonzero
        // mem_addr/wmask/wdata left behind by an earlier iteration's real
        // store.
        rvfi.mem_addr  = 0;
        rvfi.mem_wmask = 0;
        rvfi.mem_wdata = 0;
      }
    }

    rvfi.rs1_addr = this->get_state()->last_inst_fetched.rs1();
    rvfi.rs1_rdata = this->get_XPR(reference->rs1_addr);
    rvfi.rs2_addr = this->get_state()->last_inst_fetched.rs2();
    rvfi.rs2_rdata = this->get_XPR(reference->rs2_addr);

    bool got_commit = false;

    if (rvfi.intr) {
        for (auto &reg : last_log_reg_write) {
            reg_t addr = reg.first >> 4;
            rvfi.csr_valid[INDEX_CSR(addr)] = 1;
            rvfi.csr_addr [INDEX_CSR(addr)] = addr;
            rvfi.csr_wdata[INDEX_CSR(addr)] = reg.second.v[0];
            rvfi.csr_wmask[INDEX_CSR(addr)] = -1;
        }
    }
    last_log_reg_write.clear();

    for (auto &reg : reg_commits) {
        if ((reg.first >> 4) > 32) {
            if (rvfi.trap) {
                last_log_reg_write[reg.first] = reg.second;
            }
            else if ((reg.first >> 4) < 0xFFF) {
                reg_t addr = reg.first >> 4;
                rvfi.csr_valid[INDEX_CSR(addr)] = 1;
                rvfi.csr_addr [INDEX_CSR(addr)] = addr;
                rvfi.csr_wdata[INDEX_CSR(addr)] = reg.second.v[0];
                rvfi.csr_wmask[INDEX_CSR(addr)] = -1;
            }
        }
        else {
            // TODO FIXME Take into account the XLEN/FLEN for int/FP values.
            rvfi.rd1_addr = reg.first >> 4;
            rvfi.rd1_wdata = reg.second.v[0];
            // TODO FIXME Handle multiple register commits per cycle.
            // TODO FIXME This must be handled on the RVFI side as well.
        }
    }

    if (csr_counters_injection & !rvfi.trap) {
      // Inject values comming from the reference
      if ((rvfi.insn & MASK_CSRRS) == MATCH_CSRRS ||
          (rvfi.insn & MASK_CSRRSI) == MATCH_CSRRSI ||
          (rvfi.insn & MASK_CSRRC) == MATCH_CSRRC ||
          (rvfi.insn & MASK_CSRRCI) == MATCH_CSRRCI ||
          (rvfi.insn & MASK_CSRRW) == MATCH_CSRRW ||
          (rvfi.insn & MASK_CSRRWI) == MATCH_CSRRWI ) {

          reg_t read_csr = this->get_state()->last_inst_fetched.csr();
          // mhpmcounter5..10 and CSR_MIP are excluded here -- independently
          // modeled below/in Proc.h instead of forwarded, so a real mismatch
          // can be caught instead of trusting the RTL's own value.
          bool counter_csr =
              read_csr == 0xC00      || // cycle
              read_csr == 0xC80      || // cycleh
              read_csr == CSR_MCYCLE || // mcycle
              read_csr == CSR_MCYCLEH || // mcycleh
              (read_csr >= CSR_MHPMCOUNTER3  && read_csr <= CSR_MHPMCOUNTER4)   || // NumCyclesLSU/IF (timing - forwarded)
              (read_csr >= CSR_MHPMCOUNTER11 && read_csr <= CSR_MHPMCOUNTER31)  || // NumCyclesWFI/DivWait (timing) + unused/reserved
              (read_csr >= CSR_MHPMCOUNTER3H && read_csr <= CSR_MHPMCOUNTER4H)  ||
              (read_csr >= CSR_MHPMCOUNTER11H && read_csr <= CSR_MHPMCOUNTER31H) ||
              (read_csr >= CSR_MHPMEVENT3    && read_csr <= CSR_MHPMEVENT31);      // mhpmevent3..31 (hardwired selectors)
          if (counter_csr) {

            if (reference->rd1_addr) {
              this->set_XPR(reference->rd1_addr, this->xlen_format(reference->rd1_wdata));
              rvfi.rd1_wdata = reference->rd1_wdata;
            }

            // If it is set or clear we need to inject also the value in the CSR
            if (this->get_state()->last_inst_fetched.rs1()) {
                if ((rvfi.insn & MASK_CSRRC) == MATCH_CSRRC   ||
                    (rvfi.insn & MASK_CSRRS) == MATCH_CSRRS   ||
                    (rvfi.insn & MASK_CSRRCI) == MATCH_CSRRCI ||
                    (rvfi.insn & MASK_CSRRSI) == MATCH_CSRRSI) {

                    if (reference->csr_valid[INDEX_CSR(read_csr)]) {
                        this->put_csr(read_csr, this->xlen_format(reference->csr_wdata[INDEX_CSR(read_csr)]));
                        rvfi.csr_wdata[INDEX_CSR(read_csr)] = reference->csr_wdata[INDEX_CSR(read_csr)];
                    }
                }
            }
            if ((rvfi.insn & MASK_CSRRW) == MATCH_CSRRW   ||
                (rvfi.insn & MASK_CSRRWI) == MATCH_CSRRWI) {

                if (reference->csr_valid[INDEX_CSR(read_csr)]) {
                    this->put_csr(read_csr, this->xlen_format(reference->csr_wdata[INDEX_CSR(read_csr)]));
                    rvfi.csr_wdata[INDEX_CSR(read_csr)] = reference->csr_wdata[INDEX_CSR(read_csr)];
                }
            }
          } else if (read_csr == CSR_MIP) {
            // mip is a pure combinational reflection of the external IRQ
            // lines (read-only, no software write path). Trusting the RTL's
            // own readback would make this tautological, so compute it
            // independently from the raw pre-DUT IRQ lines smuggled into
            // reference->csr_rdata[CSR_MIP] by spike_tandem.sv (same
            // mechanism as mcause above).
            if (reference->rd1_addr) {
              reg_t expected_mip = reference->csr_rdata[INDEX_CSR(CSR_MIP)];
              this->set_XPR(reference->rd1_addr, this->xlen_format(expected_mip));
              rvfi.rd1_wdata = expected_mip;
            }
          } else if (read_csr == CSR_TDATA1) {
            // Independently model CVE2's fixed-function trigger CSR instead of
            // trusting Spike's generic, reconfigurable trigger module. Mirrors
            // cve2 tmatch_control_rdata bit-for-bit
            reg_t tmatch_control = (2ULL << 28) | (1ULL << 27) | (1ULL << 12) |
                                   (1ULL << 6) | (this->cve2_trigger_execute ? (1ULL << 2) : 0);

            if (reference->rd1_addr) {
              this->set_XPR(reference->rd1_addr, this->xlen_format(tmatch_control));
              rvfi.rd1_wdata = tmatch_control;
            }

            // The RTL only latches bit 2 of the fully-computed write value,
            // and only in debug mode (tmatch_control_we's debug_mode_i gate)
            // -- replicate that arithmetic instead of trusting Spike's own
            // CSR-write path.
            uint32_t insn = rvfi.insn;
            bool is_imm = (insn & MASK_CSRRWI) == MATCH_CSRRWI ||
                          (insn & MASK_CSRRSI) == MATCH_CSRRSI ||
                          (insn & MASK_CSRRCI) == MATCH_CSRRCI;
            reg_t rs1_field = this->get_state()->last_inst_fetched.rs1();
            reg_t operand = is_imm ? rs1_field : this->get_XPR(rs1_field);
            bool is_rw  = (insn & MASK_CSRRW)  == MATCH_CSRRW  || (insn & MASK_CSRRWI) == MATCH_CSRRWI;
            bool is_set = (insn & MASK_CSRRS)  == MATCH_CSRRS  || (insn & MASK_CSRRSI) == MATCH_CSRRSI;
            bool is_clr = (insn & MASK_CSRRC)  == MATCH_CSRRC  || (insn & MASK_CSRRCI) == MATCH_CSRRCI;
            bool does_write = is_rw || ((is_set || is_clr) && operand != 0);

            if (does_write && this->get_state()->debug_mode) {
              reg_t new_val = tmatch_control;
              if (is_rw)       new_val = operand;
              else if (is_set) new_val = tmatch_control | operand;
              else if (is_clr) new_val = tmatch_control & ~operand;
              this->cve2_trigger_execute = (new_val >> 2) & 1;
            }
          } else if (read_csr == CSR_MTVAL) {
            // [RVpriv] permits mtval to be either 0 or the EBREAK's PC on a
            // breakpoint exception. The CV32E20 User Manual states:
            // "...For all other exceptions, mtval is 0." Ebreak
            // is neither a load-store error nor illegal instruction, so 0 is
            // the documented, correct value here. Spike's own default
            // (ebreak.h: always the PC) must be overridden (forwarded).
            reg_t mcause_now = this->get_csr(CSR_MCAUSE);
            if (mcause_now == CAUSE_BREAKPOINT && reference->rd1_addr) {
              this->set_XPR(reference->rd1_addr, this->xlen_format(0));
              rvfi.rd1_wdata = 0;
            }
          }
      }
    }

    // The testbench is assumed to support a free-running TICKS counter and
    // CLINT mtime/mtimeh CSRs that increment every RTL clock cycle -- unlike
    // mip/tdata1/mtval above, this is testbench infrastructure, not DUT
    // logic, so forwarding carries no risk.
    {
      // TODO: pass these values at compile or run-time (not hardcoded like this!).
      constexpr reg_t MMADDR_TICKS  = 0x15001004ULL;
      constexpr reg_t MMADDR_MTIME  = 0x0200BFF8ULL;
      constexpr reg_t MMADDR_MTIMEH = 0x0200BFFCULL;
      if (csr_counters_injection && !rvfi.trap &&
          (reference->mem_addr == MMADDR_TICKS ||
           reference->mem_addr == MMADDR_MTIME ||
           reference->mem_addr == MMADDR_MTIMEH)) {
        bool is_word_load =
            (rvfi.insn & MASK_LW)     == MATCH_LW     ||
            (rvfi.insn & MASK_C_LW)   == MATCH_C_LW   ||
            (rvfi.insn & MASK_C_LWSP) == MATCH_C_LWSP;
        if (is_word_load && reference->rd1_addr) {
          this->set_XPR(reference->rd1_addr, this->xlen_format(reference->rd1_wdata));
          rvfi.rd1_wdata = reference->rd1_wdata;
        }
      }
    }

    // Remove sign extension applied by Spike in 32b mode.
    if (this->get_xlen() == 32) {
      rvfi.pc_rdata &= 0xffffffffULL;
      rvfi.rd1_wdata &= 0xffffffffULL;
      rvfi.mem_addr &= 0xffffffffULL;
      rvfi.mem_wdata &= 0xffffffffULL;
    }

  } while (unified_traps && this->taken_trap && (this->which_trap >> 31));

  return rvfi;
}

Processor::Processor(
    const isa_parser_t *isa, const cfg_t *cfg, simif_t *sim, uint32_t id,
    bool halt_on_reset, FILE *log_file, std::ostream &sout_,
    Params &params_) // because of command line option --log and -s we need both
    : processor_t::processor_t(isa, cfg, sim, id, halt_on_reset, log_file,
                               sout_) {

  std::map<string, bool> registered_extensions_v;
  registered_extensions_v["cv32a60x"] = false;
  registered_extensions_v["cvxif"] = false;

  base = "/top/core/" + std::to_string(id) + "/";
  Processor::default_params(base, this->params, this);
  Params::parse_params(base, this->params, params_);

  string isa_str = this->params[base + "isa"].a_string;
  string priv_str = this->params[base + "priv"].a_string;
  this->isa =
      (const isa_parser_t *)new isa_parser_t(isa_str.c_str(), priv_str.c_str());
  std::cout << "[SPIKE] Proc 0 | ISA: " << isa_str << " PRIV: " << priv_str << std::endl;
  std::cout << "[SPIKE]     Non standard interrupts " << this->params[base + "non_standard_interrupts"].a_bool << std::endl;

  uint64_t pmpregions_max = this->params[base + "pmpregions_max"].a_uint64_t;
  std::cout << "[SPIKE]                 PMP Regions " << std::hex << pmpregions_max << std::endl;
  processor_t::set_pmp_num(pmpregions_max);

  uint64_t pmp_granularity = this->params[base + "pmp_granularity"].a_uint64_t;
  std::cout << "[SPIKE]                 PMP Granularity " << pmp_granularity;
  // PMP granularity must be at least 4 and a power of two.
  if (pmp_granularity < 4 || (pmp_granularity & (pmp_granularity - 1)) != 0)
    std::cout << " is INVALID, will be IGNORED." << std::endl;
  else {
    std::cout << std::endl;
    processor_t::set_pmp_granularity(pmp_granularity);
  }

  ((cfg_t *)cfg)->priv = priv_str.c_str();

  uint64_t trigger_count = this->params[base + "trigger_count"].a_uint64_t;
  ((cfg_t *)cfg)->trigger_count = trigger_count;

  if (disassembler != NULL)
      delete disassembler;

  this->disassembler = new disassembler_t(this->isa);

  // Extensions specified in the ISA string.
  for (auto e : this->isa->get_extensions()) {
    if (e.second && e.second->name()) {
      e.second->set_Proc(this);
      std::cerr << "### [SPIKE] Processor::Processor(): registering and resetting extension '" << e.second->name() << "' in Processor context..." << std::endl;
      register_extension(e.second);
      e.second->reset();
    }
  }

  ((cfg_t *)cfg)->misaligned =
      (this->params[base + "misaligned"]).a_bool;

  // Allow/disallow memory accesses to unmapped addresses (single common flag
  // for FETCH, LOAD, and STORE).
  // If the param is missing in the Yaml file or there is no Yaml file at all,
  // the value will be 'false' (default for missing Boolean param).
  this->mmu->set_unmapped((this->params[base + "allow_unmapped_mem_access"]).a_bool);

  this->csr_counters_injection =
      (this->params[base + "csr_counters_injection"]).a_bool;

  // Initialize extensions specified in Yaml 'extensions:' entry.
  string extensions_str =
      (this->params[base + "extensions"]).a_string;

  string delimiter = ",";

  extensions_str = extensions_str + delimiter;

  size_t found = extensions_str.find(delimiter);

  while (found != string::npos) {
    string token = extensions_str.substr(0, found);
    extensions_str = extensions_str.substr(found + delimiter.length(), extensions_str.length());
    if (token != "") {
      auto it = registered_extensions_v.find(token);
      if (it != registered_extensions_v.end()) {
        std::cout << "[SPIKE] Activating extension: " << token << std::endl;
        it->second = true;
      }
      else
        std::cout << "[SPIKE] Extension \"" << token << "\" can not be registered"
                  << std::endl;
    }
    found = extensions_str.rfind(delimiter);
  }

  for (auto ext : registered_extensions_v) {
    if (ext.second) {
      // Register the extension and reset it.
      extension_t *extension = find_extension(ext.first.c_str())();
      std::cerr << "### [SPIKE] Registering Yaml-specified extension '" << extension->name() << "'..." << std::endl;
      extension->set_Proc(this);
      register_extension(extension);
      extension->reset();
    }
  }

  std::cerr << "### [SPIKE] Calling Processor::reset() on hart " << std::dec << this->get_id() << "..." << std::endl;
  this->reset();
}

void Processor::take_trap(trap_t &t, reg_t epc) {
  this->taken_trap = true;
  this->which_trap = t.cause();

  processor_t::take_trap(t, epc);

  if (state.debug_mode) {
    uint64_t debug_handler_addr = (this->params[base + "debug_handler_addr"]).a_uint64_t;
    uint64_t debug_exception_handler_addr = (this->params[base + "debug_exception_handler_addr"]).a_uint64_t;
    if (this->which_trap == 0x3) {
        state.pc = debug_handler_addr;
        this->which_trap = 0x1; // Debug breakpoint on debug mode
    }
    else
        state.pc = debug_exception_handler_addr;
  }
}

Processor::~Processor() {
    delete this->isa;
    for (auto e : this->custom_extensions)
        delete e.second;
}

void Processor::default_params(string base, openhw::Params &params, Processor *proc) {
  params.set_string(base, "isa", "RV32GC", "RV32GC",
             "ISA");
  params.set_string(base, "priv", DEFAULT_PRIV, DEFAULT_PRIV, "Privilege Level");
  params.set_uint64_t(base, "boot_addr", 0x80000000UL, "0x80000000UL",
             "First PC of the core");
  params.set_string(base, "mmu_mode", "sv39", "sv39",
             "Memory virtualization mode");

  if (!params.exist(base, "pmpregions_max"))
    params.set_uint64_t(base, "pmpregions_max", 0x0UL, "0x0",
                        "Number of PMP regions");
  if (!params.exist(base, "pmpregions_writable"))
    params.set_uint64_t(base, "pmpregions_writable", 0x0UL, "0x0",
                        "Number of PMP regions");
  if (!params.exist(base, "pmp_granularity"))
    params.set_uint64_t(base, "pmp_granularity", 0x8UL, "0x8",
                        "Granularity of PMP addresses in bytes");
  if (!params.exist(base, "pmpaddr0"))
    params.set_uint64_t(base, "pmpaddr0", 0x0UL, "0x0",
			"Default PMPADDR0 value");
  if (!params.exist(base, "pmpcfg0"))
    params.set_uint64_t(base, "pmpcfg0", 0x0UL, "0x0",
			"Default PMPCFG0 value");
  if (!params.exist(base, "marchid"))
    params.set_uint64_t(base, "marchid", 0x3UL, "0x3", "MARCHID value");
  if (!params.exist(base, "mhartid"))
    params.set_uint64_t(base, "mhartid", 0x0UL, "0x0", "MHARTID value");
  if (!params.exist(base, "mvendorid"))
    params.set_uint64_t(base, "mvendorid", 0x00000602UL, "0x00000602UL",
			"MVENDORID value");

  if (!params.exist(base, "debug_handler_addr"))
    params.set_uint64_t(base, "debug_handler_addr", 0x1a110800, "0x1a110800",
			"Debug handler Address");

  if (!params.exist(base, "debug_exception_handler_addr"))
    params.set_uint64_t(base, "debug_exception_handler_addr", 0x1A140000, "0x1A140000",
			"Debug handler Address");

  if (!params.exist(base, "extensions"))
    params.set_string(base, "extensions", "", "", "Possible extensions: cv32a60x, cvxif");

  if (!params.exist(base, "misaligned"))
    params.set_bool(base, "misaligned", false, "false",
		    "Support for misaligned memory operations");

  if (!params.exist(base, "csr_counters_injection"))
    params.set_bool(base, "csr_counters_injection", false, "false",
		    "Allow to set CSRs getting values from DPI");

  if (!params.exist(base, "interrupts_injection"))
    params.set_bool(base, "interrupts_injection", true, "true",
		    "Allow to set MIP csr with values from DPI");

  if (!params.exist(base, "debug_injection"))
    params.set_bool(base, "debug_injection", true, "true",
		    "Allow to enter in debug mode with values from DPI");

  if (!params.exist(base, "hide_csrs_based_on_priv"))
    params.set_bool(base, "hide_csrs_based_on_priv", false, "false",
		    "Allow to hide CSRs based on priv modes available.");

  if (!params.exist(base, "mtvec_vectored_alignment"))
    params.set_uint64_t(base, "mtvec_vectored_alignment", 0x4UL, "0x4",
			"Default alignment for mtvec when vector mode active");

  if (!params.exist(base, "override_custom_extensions"))
    params.set_bool(base, "override_custom_extensions", true, "false",
		    "Allow to override custom extensions value.");

  if (!params.exist(base, "override_custom_extensions_value"))
    params.set_bool(base, "override_custom_extensions_value", false, "false",
		    "Value for the custom extensions override.");

 if (!params.exist(base, "non_standard_interrupts"))
     params.set_bool(base, "non_standard_interrupts", false, "false",
		     "Value for the custom extensions override.");

  if (!params.exist(base, "unified_traps"))
    params.set_bool(base, "unified_traps", false, "false",
		    "Unify all kind of traps with the exceptions.");

  if (!params.exist(base, "nmi_mcause"))
    params.set_uint64_t(base, "nmi_mcause", 0x00000020, "0x00000020",
			"Value of MCAUSE in case of NMI. It does not include the interrupt bit.");

  for (auto it = proc->get_state()->csrmap.begin(); it != proc->get_state()->csrmap.end(); it++) {
      string csr_name = it->second.get()->get_name();
      if (csr_name != "noname") {
        params.set_uint64_t(base, csr_name + "_override_value", (0x0UL), "0x0",
                    csr_name + " CSR override value");
        params.set_uint64_t(base, csr_name + "_override_mask", (0x0UL), "0x0",
                    csr_name + " CSR override mask");
        params.set_bool(base, csr_name + "_accessible", true, "true",
                    csr_name + " CSR accessible");
        params.set_bool(base, csr_name + "_implemented", true, "true",
                    csr_name + " CSR implemented");
        params.set_bool(base, csr_name + "_we_enable", false, "false",
                    csr_name +" CSR Write Enable param enable");
        params.set_bool(base, csr_name + "_we", false, "false",
                    csr_name + " CSR Write Enable value");
        params.set_uint64_t(base, csr_name + "_write_mask", ((uint64_t) -1ULL), "0xFFFFFFFF",
                        csr_name + " CSR write mask");
      }
  }

  if (!params.exist(base, "trigger_count"))
    params.set_uint64_t(base, "trigger_count", 0x0000004, "0x00000004",
			"Number of enabled triggers");
}

inline uint64_t Processor::get_XPR(reg_t num) {
  return this->state.XPR[num];
}

inline void Processor::set_XPR(reg_t num, reg_t value) {
  this->state.XPR.write(num, value);
}

inline void Processor::set_FPR(reg_t num, float128_t value) {
  this->state.FPR.write(num, value);
}

void Processor::put_csr(int which, reg_t val)
{
  val = zext_xlen(val);
  auto search = state.csrmap.find(which);
  if (search != state.csrmap.end()) {
    search->second->write(val);
    return;
  }
}

reg_t Processor::get_csr(int which)
{
    return this->get_csr(which, 0, 0, 1);
}

reg_t Processor::get_csr(int which, insn_t insn, bool write, bool peek)
{
  auto search = get_state()->csrmap.find(which);
  if (search != state.csrmap.end()) {
    search->second->custom_checks(insn, write);
    if (!peek) {
      search->second->verify_permissions(insn, write);
    }
    return search->second->read();
  }
  // If we get here, the CSR doesn't exist.  Unimplemented CSRs always throw
  // illegal-instruction exceptions, not virtual-instruction exceptions.
  throw trap_illegal_instruction(insn.bits());
}

void Processor::reset()
{
    processor_t::reset();

    this->taken_trap = false;
    this->taken_debug = false;
    this->which_trap = 0;
    this->which_debug = 0;
    this->nmi_inject = false;
    this->cve2_trigger_execute = false;
    this->last_log_reg_write.clear();

    uint64_t new_pc = (this->params[base + "boot_addr"]).a_uint64_t;
    this->state.pc = new_pc;

    this->put_csr(CSR_PMPADDR0, (this->params[base + "pmpaddr0"]).a_uint64_t);
    this->put_csr(CSR_PMPCFG0, (this->params[base + "pmpcfg0"]).a_uint64_t);

    uint64_t max_misa = this->isa->get_max_isa();
    this->state.csrmap[CSR_MISA] = this->state.misa =
        std::make_shared<misa_csr_t>(this, CSR_MISA, max_misa);

    this->get_state()->csrmap[CSR_MSCONTEXT] = std::make_shared<proxy_csr_t>(this, CSR_MSCONTEXT, this->get_state()->csrmap[CSR_MCONTEXT]);

    this->get_state()->debug_mode = 1;

    auto it = this->get_state()->csrmap.begin();
    while (it != this->get_state()->csrmap.end()) {

        openhw::reg* p_csr = (openhw::reg*) it->second.get();
        std::string csr_name = reg::addr2name(it->first);
        if (csr_name != "") {
            p_csr->set_name(csr_name);

            uint64_t override_mask = (this->params[base + csr_name + "_override_mask"]).a_uint64_t;
            uint64_t override_value = (this->params[base + csr_name + "_override_value"]).a_uint64_t;

            uint64_t val = p_csr->unlogged_read();
            val = (~override_mask & val) | (override_mask & override_value);
            // Write the value to the CSR
            p_csr->backdoor_write(val);
            // Affect possible dependencies
            if (val != p_csr->read())
                p_csr->write(val);

            string write_mask_string = base + csr_name + "_write_mask";
            uint64_t write_mask = (this->params[base + csr_name + "_write_mask"]).a_uint64_t;
            p_csr->set_param_write_mask(write_mask);

            bool implemented = (this->params[base + csr_name + "_implemented"]).a_bool;
            p_csr->set_param_implemented(implemented);
            if (!implemented) {
                p_csr->set_param_write_mask(0x0);
                p_csr->backdoor_write(0x0);
                if (p_csr->read())
                    p_csr->write(0);
            }

            bool accessible = (this->params[base + csr_name + "_accessible"]).a_bool;
            p_csr->set_param_accessible(accessible);
            if (!accessible)
                state.csrmap.erase(it++);
            else
                it++;

        }
        else
            it++;
    }

    this->get_state()->debug_mode = 0;

    // Hide CSR Priv param implementation
    bool hide_csr_priv = (this->params[base + "hide_csrs_based_on_priv"]).a_bool;
    std::string s = this->get_cfg().priv();
    if (hide_csr_priv) {
        auto it = this->get_state()->csrmap.begin();
        while(it != this->get_state()->csrmap.end()) {
            bool legal = false;
            for (size_t i = 0 ; i < s.length() && !legal; i++) {
                std::tuple <uint64_t, uint64_t> range = Processor::priv_ranges[s[i]];
                if (std::get<0>(range) <= it->first && it->first < get<1>(range)) {
                    legal = true;
                }
            }
            if (!legal)
                this->get_state()->csrmap.erase(it++);
            else
                it++;
        }
    }

    uint64_t pmpregions_writable = this->params[base + "pmpregions_writable"].a_uint64_t;
    uint64_t pmpregions_max = this->params[base + "pmpregions_max"].a_uint64_t;

    for (uint64_t i = pmpregions_writable; i < pmpregions_max; i++) {
        uint64_t csr_pmpaddr = CSR_PMPADDR0 + i;
        uint64_t csr_pmpcfg = CSR_PMPCFG0 + (i/4);

        auto addr_it = this->get_state()->csrmap.find(csr_pmpaddr);
        if (addr_it != this->get_state()->csrmap.end()) {
            openhw::reg* p_csr = (openhw::reg*) addr_it->second.get();
            p_csr->set_param_write_mask(0x0);
            p_csr->set_param_implemented(0x0);

        }
        auto cfg_it = this->get_state()->csrmap.find(csr_pmpcfg);
        if (cfg_it != this->get_state()->csrmap.end()) {
            openhw::reg* p_csr = (openhw::reg*) cfg_it->second.get();
            p_csr->set_param_implemented(0x0);
        }
    }

    // CVE2's tdata1.type is hardwired (not writable) -- per the Debug spec
    // (riscv-debug-v1.0.0-stable.pdf §5.5.5), tinfo "is optional if ... type
    // is not writable", and CVE2 does not implement it, so we expect an illegal
    // instruction here.
    get_state()->csrmap.erase(CSR_TINFO);

    // Spike registers "mcontext" (0x7A8) as a proxy alias for hcontext (Debug
    // spec §5.5.9) but never registers mscontext (0x7AA), even though §5.5.10
    // says it's an alias for scontext the same way -- a plain Spike omission,
    // not a CVE2 carve-out. CVE2 does implement this address.
    get_state()->csrmap[CSR_MSCONTEXT] = std::make_shared<proxy_csr_t>(
        this, CSR_MSCONTEXT, get_state()->csrmap[CSR_SCONTEXT]);

    // CVE2-custom "secureseed" CSR (0x7C1) is not standard RISC-V, so Spike has
    // no knowledge of it and throws an illegal-instruction trap. Not an RTL defect
    // (no RVpriv existence rule applies, same category as tinfo above).
    get_state()->csrmap[0x7C1] = std::make_shared<const_csr_t>(this, 0x7C1, 0);

    // Give mhpmcounter5..10 a real backing register (see Proc.h) so
    // Processor::step() can increment them on qualifying retirements.
    auto install_hpm_counter = [this](reg_t addr, reg_t addrh,
                                      std::shared_ptr<basic_csr_t> &slot) {
      slot = std::make_shared<basic_csr_t>(this, addr, 0);
      if (this->get_xlen() == 32) {
        get_state()->csrmap[addr] =
            std::make_shared<rv32_low_csr_t>(this, addr, slot);
        get_state()->csrmap[addrh] =
            std::make_shared<rv32_high_csr_t>(this, addrh, slot);
      } else {
        get_state()->csrmap[addr] = slot;
      }
    };
    install_hpm_counter(CSR_MHPMCOUNTER5, CSR_MHPMCOUNTER5H, this->hpm_loads);
    install_hpm_counter(CSR_MHPMCOUNTER6, CSR_MHPMCOUNTER6H, this->hpm_stores);
    install_hpm_counter(CSR_MHPMCOUNTER7, CSR_MHPMCOUNTER7H, this->hpm_jumps);
    install_hpm_counter(CSR_MHPMCOUNTER8, CSR_MHPMCOUNTER8H, this->hpm_branches);
    install_hpm_counter(CSR_MHPMCOUNTER9, CSR_MHPMCOUNTER9H,
                        this->hpm_branches_taken);
    install_hpm_counter(CSR_MHPMCOUNTER10, CSR_MHPMCOUNTER10H,
                        this->hpm_instret_c);

    // Real backing register for mcountinhibit (base Spike hardwires it
    // read-only-0) so the shadow counters above honor software's inhibit
    // bits, matching CVE2's documented gating (performance_counters.rst).
    get_state()->csrmap[CSR_MCOUNTINHIBIT] =
        std::make_shared<basic_csr_t>(this, CSR_MCOUNTINHIBIT, 0);
}

void Processor::take_pending_interrupt() {
    uint64_t mie = (state.mie->read());
    uint64_t mip = (state.mip->read());
    take_interrupt(mip & mie);
}

void Processor::take_interrupt(reg_t pending_interrupts) {

  processor_t::take_interrupt(pending_interrupts);

  if (this->nmi_inject && !this->taken_trap && pending_interrupts == 0) {
    this->nmi_inject = false;
    uint64_t nmi_mcause = (this->params[base + "nmi_mcause"]).a_uint64_t;
    throw trap_t(((reg_t)1 << (isa->get_max_xlen() - 1)) | nmi_mcause);
  }

  return;
}

uint32_t Processor::mcause_to_mip(uint32_t mcause) {
    // Check if the cause is an interrupt (MSB = 1)
    if (mcause >> 31) {
        uint32_t interrupt_id = mcause & 0x7FFFFFFF; // Mask out the interrupt bit to get the ID
        switch (interrupt_id) {
            case 3: return MIP_MSIP;   // Software interrupt
            case 7: return MIP_MTIP;   // Timer interrupt
            case 11: return MIP_MEIP;  // External interrupt
            default:
                if (32 > interrupt_id && interrupt_id > 15) {
                    return 1 << (interrupt_id);
                }
                return 0;         // Unknown or unhandled interrupt
        }
    }
    return 0; // Not an interrupt
}

void Processor::enter_debug_mode(uint8_t cause) {
    processor_t::enter_debug_mode(cause);

    uint64_t debug_handler_addr = (this->params[base + "debug_handler_addr"]).a_uint64_t;
    state.pc = debug_handler_addr;
    state.mtval->write(0x0);

    this->taken_debug = true;
    this->which_debug = cause;

}

uint64_t Processor::xlen_format(uint64_t value) {
    if (this->get_xlen() == 32) {
        return sreg_t((int32_t) value);
    } else {
        return value;
    }
}

std::unordered_map<char, std::tuple<uint64_t,uint64_t>> Processor::priv_ranges = {
    { 'M',  {0x300, 0xFFF} },
    { 'S',  {0x100, 0x200} },
    { 'U',  {0x0  , 0x100} },
};

} // namespace openhw
