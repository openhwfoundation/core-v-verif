# Copyright (c) 2026 OpenHW Foundation
# Copyright (c) 2026 Eclipse Foundation
# SPDX-License-Identifier: Apache-2.0

import argparse
import os
import re

parser = argparse.ArgumentParser(description='generate a coverage report from a UCDB (Questasim only)')
parser.add_argument('--ucdb'            , dest='ucdb',            type=str, help='path to the UCDB to report on, required')
parser.add_argument('--tool'            , dest='tool',            type=str, help='simulator tool, only "questa" supported, default questa')
parser.add_argument('--outdir'          , dest='outdir',          type=str, help='report output directory, default "cov_report"')
parser.add_argument('--cover_types'     , dest='cover_types',     type=str, help='coverage type letters for -code, e.g. bcfs; omit to use tool default (all types)')
parser.add_argument('--instance'        , dest='instance',        type=str, help='instance path for -instance=<value>. scoping (trailing dot appended automatically), optional')
parser.add_argument('--report_type'     , dest='report_type',     type=str, choices=['html', 'text', 'holes', 'holes_details', 'trl5_code_metrics'], help='default html')
parser.add_argument('--holes_threshold' , dest='holes_threshold', type=int, help='percentage cutoff for holes/holes_details reports (-below), default 100')
parser.add_argument('--gui'             , dest='gui',             action='store_true', help='open the UCDB interactively in Visualizer (-viewcov) instead of generating a batch report')
parser.add_argument('--designfile'      , dest='designfile',      type=str, help='design.bin file created by vopt -designfile, attached to Visualizer for schematic/class/assertion views; only meaningful with --gui, default "design.bin"')
parser.add_argument('--details'         , dest='details',         action='store_true', help='add -details to the report; already always on for html/holes_details (needed there for source-level drill-down), so only meaningful for text')
parser.add_argument('--recursive'       , dest='recursive',       action='store_true', help='add -recursive to the report')
parser.add_argument('--verbose'         , dest='verbose',         action='store_true', help='print info messages, default False')
args = parser.parse_args()
verbose = args.verbose

tool = args.tool if args.tool is not None else "questa"
if tool != "questa":
    print("[ERROR]: --tool option is only supported with questa")
    exit(1)

if args.ucdb is None or os.path.isfile(args.ucdb) == False:
    print("[ERROR]: Please specify a valid --ucdb file")
    exit(1)

outdir          = args.outdir          if args.outdir          is not None else "cov_report"
report_type     = args.report_type     if args.report_type     is not None else "html"
holes_threshold = args.holes_threshold if args.holes_threshold is not None else 100

code_opt    = f"-code {args.cover_types}"  if args.cover_types else ""
inst_opt    = f"-instance={args.instance}." if args.instance   else ""
details_opt = "-details"                   if args.details         else ""
recur_opt   = "-recursive"                 if args.recursive       else ""

if args.gui:
    designfile = args.designfile if args.designfile is not None else "design.bin"
    cmd = f"visualizer -designfile {designfile} -viewcov {args.ucdb}"
    if verbose: print(f"[INFO]: Coverage GUI command:\n{cmd}")
    os.system(cmd)
    exit(0)

os.system(f"mkdir -p {outdir}")

if report_type == "html":
    cmd = f"vcover report -html {code_opt} {inst_opt} -details -annotate -precision 2 {recur_opt} -showexcluded -output {outdir} {args.ucdb}"
elif report_type == "text":
    cmd = f"vcover report {code_opt} {inst_opt} {details_opt} -precision 2 {recur_opt} -showexcluded -output {outdir}/report.txt {args.ucdb}"
elif report_type == "holes":
    cmd = f"vcover report {code_opt} {inst_opt} {recur_opt} -precision 2 -below {holes_threshold} -output {outdir}/holes.txt {args.ucdb}"
elif report_type == "holes_details":
    cmd = f"vcover report {code_opt} {inst_opt} -below {holes_threshold} -details -annotate -precision 2 -output {outdir}/holes_details.txt {args.ucdb}"
elif report_type == "trl5_code_metrics":
    metric_map = {'s': 'statement', 'b': 'branch', 'c': 'condition', 'f': 'fsm'}
    types = args.cover_types if args.cover_types else "sbcf"
    metrics_out = os.path.join(outdir, "trl5_code_metrics.txt")
    lines = []
    for letter in types:
        metric = metric_map.get(letter)
        if metric is None:
            continue
        tmp_out = os.path.join(outdir, f".summary_{letter}.txt")
        cmd = f"vcover report -code {letter} {inst_opt} -summary -output {tmp_out} {args.ucdb}"
        if verbose: print(f"[INFO]: TRL5 code metrics command ({metric}):\n{cmd}")
        os.system(cmd)
        content = ""
        if os.path.isfile(tmp_out):
            with open(tmp_out) as tf:
                content = tf.read().strip()
            os.system(f"rm -f {tmp_out}")
        lines.append(f"{metric.upper()}: {content if content else '<no result -- see command output above>'}")
    with open(metrics_out, "w") as mf:
        mf.write("\n".join(lines) + "\n")
    print(f"[INFO]: TRL5 code metrics summary written to {metrics_out}")
    for l in lines:
        print(l)
    exit(0)

if verbose: print(f"[INFO]: Report command:\n{cmd}")
ret = os.system(cmd)
if ret != 0:
    print("[ERROR]: vcover report failed")
    exit(1)
print(f"[INFO]: Report written to {outdir}")
