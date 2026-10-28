<!--- 
## ----------------------------------------------------------------------------
##Copyright 2023 CEA*
##*Commissariat a l'Energie Atomique et aux Energies Alternatives (CEA)
##
##Licensed under the Apache License, Version 2.0 (the "License");
##you may not use this file except in compliance with the License.
##You may obtain a copy of the License at
##
##    http://www.apache.org/licenses/LICENSE-2.0
##
##Unless required by applicable law or agreed to in writing, software
##distributed under the License is distributed on an "AS IS" BASIS,
##WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
##See the License for the specific language governing permissions and
##limitations under the License.
##[END OF HEADER]
## ----------------------------------------------------------------------------
--->

# SIM CMD
## Introduction
Python scripts to compile, elaborate, and run UVM tests. Supports waveform dumping and coverage collection. Compatible with Questasim, Xcelium, and VCS.

# Usage

## Compilation

To compile and elaborate a design:
```
python3 compile.py --yaml yaml_file.yaml [--outdir output_dir] [--cover 0/1]
```

| Option | Description | Default |
|--------|-------------|---------|
| `--yaml` | Top YAML file with compile and simulation options | required |
| `--outdir` | Directory for compilation logs | `output` |
| `--cover` | `1`: instrument for coverage during elaboration (Questasim only); `0`: no coverage | `0` |
| `--cover_types` | Coverage type letters for `vopt +cover=<types>` (e.g. `bcfs` = branch/condition/statement/FSM); only meaningful with `--cover 1` | bare `+cover` (all types) |
| `--cover_instance` | Instance path to scope coverage instrumentation (`+cover=<types>+<instance>.`); only meaningful with `--cover 1` | whole design |

## Running a single test

```
python3 run_test.py --yaml yaml_file.yaml --test_name name_of_the_test --seed n_seed [options]
```

| Option | Description | Default |
|--------|-------------|---------|
| `--yaml` | Top YAML file with compile and simulation options | required |
| `--test_name` | Name of the UVM test to run | required |
| `--seed` | Random seed | `1` |
| `--debug` | UVM verbosity: `UVM_NONE/LOW/MEDIUM/HIGH/DEBUG` | `UVM_LOW` |
| `--batch` | `1`: batch mode; `0`: GUI mode (Questasim: live Visualizer, attached to `--designfile`) | `1` |
| `--dump` | `1`: log all signals to waveform database; `0`: no dump | `0` |
| `--cover` | `1`: enable coverage collection (Questasim only); `0`: disabled | `0` |
| `--cover_excl_file` | Coverage exclusion `.do`/`.tcl` file, sourced before the per-test UCDB is saved; only meaningful with `--cover 1`. Opt-in, never applied unless explicitly given -- see [Coverage](#coverage-questasim-only) | none |
| `--designfile` | `design.bin` (from `vopt -designfile`) attached to Visualizer in GUI mode (`--batch 0`, Questasim only) for schematic/class/assertion views, on top of the raw waveform | `design.bin` |
| `--stdout` | `1`: print log to stdout; `0`: redirect to log file | `1` |
| `--outdir` | Output directory for logs and databases | `output` |
| `--run_time` | Simulation run time (e.g. `100ns`) | `-all` |
| `--verbose` | Print informational messages | `False` |

## Running a regression

```
python3 run_reg.py --yaml yaml_file.yaml --reg_list reg_list_file [--nthreads n] [--cover 0/1] [--outdir output_dir]
```

| Option | Description | Default |
|--------|-------------|---------|
| `--yaml` | Top YAML file with compile and simulation options | required |
| `--reg_list` | File listing tests and number of seeds | required |
| `--nthreads` | Number of parallel simulation instances | `1` |
| `--comp` | `1`: compile/elaborate before running; `0`: skip compilation and reuse an already-compiled design (e.g. to re-run with new seeds while chasing coverage holes) | `1` |
| `--cover` | `1`: enable coverage for all tests (Questasim only); `0`: disabled | `0` |
| `--cover_types` | Coverage type letters, forwarded to `compile.py` | bare `+cover` (all types) |
| `--cover_instance` | Instance path, forwarded to `compile.py` (instrumentation scope) and to the report step (`--cover_report`) | whole design |
| `--cover_merge` | `1`: merge all per-test UCDBs after the regression completes (requires `--cover 1`) | `0` |
| `--cover_excl_file` | Exclusion `.do`/`.tcl` file, sourced against the merged UCDB post-merge (requires `--cover_merge 1`); never applied unless explicitly given | none |
| `--cover_report` | `1`: generate an HTML report from the merged UCDB after merging (requires `--cover_merge 1`) | `0` |
| `--outdir` | Output directory | `regression` |
| `--verbose` | Print informational messages | `False` |

## Coverage (Questasim only)

Coverage flows in four stages, each opt-in and independently usable:

1. **Instrument + collect (per test)**: pass `--cover 1` to `compile.py` (optionally with `--cover_types`/`--cover_instance`) and to `run_test.py`/`run_reg.py`. Each test saves its own UCDB: `{outdir}/coverage/{test_name}_{seed}.ucdb`. `run_test.py --cover_excl_file <path>` optionally sources a project-supplied exclusion file live during the run, before the UCDB is saved.
2. **Merge**: `cov_merge.py` (or `run_reg.py --cover_merge 1`) merges every per-test UCDB under `{outdir}/coverage/` into one `merged.ucdb`.
3. **Waive (optional)**: pass `--excl_file <path>` to `cov_merge.py` (or `run_reg.py --cover_excl_file <path>` together with `--cover_merge 1`) to source a project-supplied exclusion file against the merged UCDB and save a second, post-waiver UCDB (`merged_excluded.ucdb`) -- the pre-waiver `merged.ucdb` is left untouched, so both are always available. An exclusion file is only ever applied when explicitly passed; there is no default/baked-in exclusion file.
4. **Report**: `cov_report.py` (or `run_reg.py --cover_report 1`, HTML only) turns a UCDB into a report. `--report_type` selects `html` (full annotated report), `text` (flat), `holes`/`holes_details` (only what's below `--holes_threshold`, e.g. `100` for "anything not fully covered"), or `trl5_code_metrics` (a compact per-type percentage summary, one line per coverage type). `--gui` opens the UCDB interactively in `vsim -viewcov` instead of generating a batch report.

### `cov_merge.py`

```
python3 cov_merge.py --outdir regression [--tool questa] [--out_file merged.ucdb] [--excl_file exclude.do] [--verbose]
```

| Option | Description | Default |
|--------|-------------|---------|
| `--tool` | Simulator tool, only `questa` supported | `questa` |
| `--outdir` | Directory containing `coverage/` with the per-test UCDBs (same `--outdir` used for the regression) | `output` |
| `--out_file` | Merged UCDB filename, written under `{outdir}/coverage/` | `merged.ucdb` |
| `--excl_file` | Optional exclusion `.do`/`.tcl` file, sourced against the merged UCDB; produces `merged_excluded.ucdb` alongside the untouched merged UCDB | none |
| `--verbose` | Print informational messages | `False` |

### `cov_report.py`

```
python3 cov_report.py --ucdb regression/coverage/merged.ucdb [--outdir cov_report] [--cover_types bcfs] [--instance /top/dut] [--report_type html] [--verbose]
```

| Option | Description | Default |
|--------|-------------|---------|
| `--ucdb` | UCDB file to report on | required |
| `--tool` | Simulator tool, only `questa` supported | `questa` |
| `--outdir` | Report output directory | `cov_report` |
| `--cover_types` | Coverage type letters for `-code` | tool default (all types) |
| `--instance` | Instance path for `-instance=<value>.` scoping (trailing dot appended automatically) | whole design |
| `--report_type` | `html`, `text`, `holes`, `holes_details`, or `trl5_code_metrics` | `html` |
| `--holes_threshold` | Percentage cutoff for `holes`/`holes_details` (`-below`) | `100` |
| `--gui` | Open the UCDB interactively in Visualizer (`visualizer -viewcov`) instead of a batch report | off |
| `--designfile` | `design.bin` (from `vopt -designfile`) attached to Visualizer for schematic/class/assertion views; only meaningful with `--gui` | `design.bin` |
| `--details` / `--recursive` | Passed through to `vcover report` | off |
| `--verbose` | Print informational messages | `False` |

## Waveform and coverage inspection (post_proc.py)

The user can also use post_proc.py after batch mode simulations with dumping option enabled for inspecting the DUT waveforms, or to browse a coverage UCDB, dispatched by `--db_file`'s extension:
```
python3 ${SCRIPTS_DIR}/post_proc.py --tool user_tool --db_file ./path/to/db/file [--designfile design.bin]
```

| Option | Description | Default |
|--------|-------------|---------|
| `--tool` | `questa`, `xcelium`, or `vcs` | required |
| `--db_file` | Database file to open: `.db` or `.ucdb` for Questasim, `.shm` for Xcelium, `.fsdb` for VCS | required |
| `--designfile` | `design.bin` (from `vopt -designfile`) attached to Visualizer, for schematic/class/assertion views alongside the waveform or coverage data (Questasim only) | `design.bin` |

For Questasim, `.db` files (from `run_test.py --dump 1`) open Visualizer on the waveform (`visualizer -designfile ... -wavefile ...`); `.ucdb` files (e.g. from `run_test.py --cover 1` or `cov_merge.py`) open Visualizer directly on the coverage database (`visualizer -designfile ... -viewcov ...`), same underlying command as `cov_report.py --gui` -- use `post_proc.py` as the generic "launch a GUI on this database file" entry point, or `cov_report.py --gui` when the UCDB is already at hand from that script's merge/waive/report flow.

The templates of yaml files are provided with the script, which can be used to compile and run the test with Questasim, Xcelium and VCS.
