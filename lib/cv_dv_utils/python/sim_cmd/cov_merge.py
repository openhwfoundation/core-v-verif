# Copyright (c) 2026 OpenHW Foundation
# Copyright (c) 2026 Eclipse Foundation
# SPDX-License-Identifier: Apache-2.0

import argparse
import glob
import os

parser = argparse.ArgumentParser(description='merge per-test coverage UCDBs (Questasim only)')
parser.add_argument('--tool'      , dest='tool',      type=str, help='simulator tool, only "questa" supported, default questa')
parser.add_argument('--outdir'    , dest='outdir',    type=str, help='regression output dir containing coverage/, default "output"')
parser.add_argument('--out_file'  , dest='out_file',  type=str, help='merged UCDB filename under {outdir}/coverage, default "merged.ucdb"')
parser.add_argument('--excl_file' , dest='excl_file', type=str, help='optional exclusion .do/.tcl file, sourced against the merged UCDB; produces an additional *_excluded.ucdb, leaving the merged UCDB untouched. Never applied unless explicitly given.')
parser.add_argument('--verbose'   , dest='verbose',   action='store_true', help='print info messages, default False')
args = parser.parse_args()
verbose = args.verbose

tool     = args.tool     if args.tool     is not None else "questa"
outdir   = args.outdir   if args.outdir   is not None else "output"
out_file = args.out_file if args.out_file is not None else "merged.ucdb"

if tool != "questa":
    print("[ERROR]: --tool option is only supported with questa")
    exit(1)

cov_dir = os.path.join(outdir, "coverage")
if os.path.isdir(cov_dir) == False:
    print(f"[ERROR]: coverage directory {cov_dir} does not exist (was --cover 1 used when running tests?)")
    exit(1)

out_path = os.path.join(cov_dir, out_file)
base, ext = os.path.splitext(out_path)
excl_out = f"{base}_excluded{ext}"

# Only this run's own products are skipped; merge products left by runs with a
# different --out_file are indistinguishable from per-test UCDBs and will be merged.
all_ucdb = sorted(glob.glob(os.path.join(cov_dir, "*.ucdb")))
inputs = [f for f in all_ucdb
          if os.path.basename(f) not in (out_file, os.path.basename(excl_out))]

if not inputs:
    print(f"[ERROR]: No per-test UCDB files found under {cov_dir}")
    exit(1)

list_file = os.path.join(cov_dir, ".merge_list.txt")
with open(list_file, "w") as lf:
    lf.write("\n".join(inputs) + "\n")

merge_cmd = f"vcover merge -64 -testassociated -out {out_path} -inputs {list_file}"
if verbose: print(f"[INFO]: Merge command:\n{merge_cmd}")
ret = os.system(merge_cmd)
os.system(f"rm -f {list_file}")
if ret != 0:
    print("[ERROR]: vcover merge failed")
    exit(1)
print(f"[INFO]: Merged UCDB written to {out_path}")

if args.excl_file:
    if os.path.isfile(args.excl_file) == False:
        print(f"[ERROR]: exclusion file {args.excl_file} not found")
        exit(1)
    do_cmd = f'vsim -c -viewcov {out_path} -do "source {args.excl_file}; coverage save {excl_out}; exit"'
    if verbose: print(f"[INFO]: Exclusion command:\n{do_cmd}")
    if os.path.isfile(excl_out):
        os.remove(excl_out)
    ret = os.system(do_cmd)
    if ret != 0 or os.path.isfile(excl_out) == False:
        print(f"[ERROR]: applying exclusions failed -- {excl_out} was not created (see vsim output above)")
        exit(1)
    print(f"[INFO]: Pre-waiver UCDB preserved at {out_path}; post-waiver UCDB written to {excl_out}")
