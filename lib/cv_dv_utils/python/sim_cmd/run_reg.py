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


import argparse
import os
import random 
import threading
import queue
import yaml

# Import the 'datetime' module to work with date and time
import datetime


#get_cmd_gen.compile
parser = argparse.ArgumentParser(description='Run Regression')
parser.add_argument('--yaml'       ,dest='yaml_file', type=str, help='Top YAML with compile and simulation options')
parser.add_argument('--reg_list'   ,dest='reglist'   , type=str, help='file that contains the regression list, the number of seeds and a default seed')
parser.add_argument('--nthreads'   ,dest='nthreads'  , type=int, help='Number of test run at the same time: default 2')
parser.add_argument('--cover'    , dest='cover',     type=int, help='1: generate coverage file (Questasim only), 0: nothing is done, default 0')
parser.add_argument('--cover_types'   , dest='cover_types',    type=str, help='coverage type letters (e.g. bcfs), forwarded to compile.py; default: bare +cover (all types)')
parser.add_argument('--cover_instance', dest='cover_instance', type=str, help='instance path forwarded to compile.py (instrumentation scope) and to the report step (--cover_report), optional')
parser.add_argument('--cover_merge'   , dest='cover_merge',    type=int, help='1: merge all per-test UCDBs after the regression completes (requires --cover 1), default 0')
parser.add_argument('--cover_excl_file', dest='cover_excl_file', type=str, help='optional exclusion .do/.tcl file, sourced against the merged UCDB post-merge (requires --cover_merge 1); never applied unless explicitly given')
parser.add_argument('--cover_report'  , dest='cover_report',   type=int, help='1: generate an HTML report from the merged UCDB after merging (requires --cover_merge 1), default 0')
parser.add_argument('--comp'       , dest='comp'      , type=int, help='1: compile/elaborate before running (default), 0: skip compilation and reuse an already-compiled design')
parser.add_argument('--define'     , dest='defines'   , action='append', help='Additional +define+<MACRO> forwarded to compile.py, repeatable')
parser.add_argument('--outdir'     , dest='outdir'    , type=str, help='output directory: default regression')
parser.add_argument('--verbose'    , dest='verbose'   , action='store_true', help='print info messages, default False')
args = parser.parse_args()
verbose = args.verbose
cover = args.cover if args.cover is not None else 0
cover_merge  = args.cover_merge  if args.cover_merge  is not None else 0
cover_report = args.cover_report if args.cover_report is not None else 0
comp = args.comp if args.comp is not None else 1

if cover_merge == 1 and cover != 1:
    print("[ERROR]: --cover_merge requires --cover 1")
    exit(1)
if cover_report == 1 and cover_merge != 1:
    print("[ERROR]: --cover_report requires --cover_merge 1")
    exit(1)

#save the environment variables
project_dir = os.environ["PROJECT_DIR"]
scripts_dir = os.environ["SCRIPTS_DIR"]

# Check arguments 
if args.outdir == None:
    outdir = "regression"
else:
    outdir = args.outdir

if args.nthreads == None:
    args.nthreads = 1


def rtest(yaml_file, test, seed):
    run_cmd = f"python3 {scripts_dir}/run_test.py --yaml {yaml_file} --test_name {test} --seed {seed} --debug UVM_NONE --dump 0 --stdout 0 --outdir {outdir} --cover {cover}"
    if verbose: print("[INFO] Simulation command:\n{}".format(run_cmd))
    os.system(run_cmd)
    log = "{}/{}_{}.log".format(outdir, test, seed) 
    pattern = "{}/scripts/patterns/sim_patterns.pat".format(project_dir)
    cmd = "scan_logs.pl -silent -nopreresetwarn {}  -pat {} ".format(log, pattern)
    ret = os.system(cmd)
    et = datetime.datetime.now()
    if ret == 0: 
        print ("passing", test, "seed", seed,  "end time", et.strftime("%Y-%m-%d %H:%M:%S"))
    else:
        if verbose: print(f"RET={ret}")
        print ("failing", test, "seed", seed,  "end time", et.strftime("%Y-%m-%d %H:%M:%S"))

print("[INFO] Starting compilation and elaboration...")
#check the insertion of the top yaml file
if args.yaml_file == None: 
   print("[ERROR] Please provide a Top YAML file")
else:
   if cover == 1:
      with open(args.yaml_file, 'r') as yaml_top:
         reg_yaml = yaml.safe_load(yaml_top)
      for entry in reg_yaml:
         if entry['tool'] != "questa":
            print("[ERROR]: --cover option is only supported with questa")
            exit(1)

   if os.path.isdir("{}".format(outdir)) == False:
     os.system("mkdir {}".format(outdir))

   if comp == 1:
     #call the compilation and elaboration command
     comp_el_cmd = f"python3 {scripts_dir}/compile.py --yaml {args.yaml_file} --cover {cover}"
     if args.cover_types:
       comp_el_cmd += f" --cover_types {args.cover_types}"
     if args.cover_instance:
       comp_el_cmd += f" --cover_instance {args.cover_instance}"
     if args.defines:
       for d in args.defines:
         comp_el_cmd += f" --define {d}"
     if verbose: print("[INFO] Compilation and elaboration command:\n{}".format(comp_el_cmd))
     os.system(comp_el_cmd)
   else:
     if verbose: print("[INFO] --comp 0: skipping compilation/elaboration, reusing existing design")

#queues for test and seed
if args.reglist == None:
    print("[ERROR] Please provide a Regression List")
else:
  tq = queue.Queue()
  sq = queue.Queue()
  
  f = open(args.reglist, "r")
  for x in f:
    line = x.split(" ")
    for y in range(0, int(line[1])):
        seed = random.getrandbits(31)
        sq.put(seed)
        tq.put(line[0])

  threads = []
  while (not tq.empty()):
      if threading.active_count() <= args.nthreads:
        seed = sq.get()
        test = tq.get()
        st = datetime.datetime.now()
        print("running", test, "seed", seed, "start time", st.strftime("%Y-%m-%d %H:%M:%S"))
        t = threading.Thread(target=rtest, args=(args.yaml_file, test, seed))
        t.start()
        threads.append(t)
      # os.system("scan_logs.pl -nopreresetwarn {}/{}_{}.log".format(args.outdir, line[0], seed))

  #wait for the last in-flight batch of tests to finish before any
  #post-regression step (e.g. coverage merge) runs, otherwise it would
  #race against still-running simulations
  for t in threads:
      t.join()

  if cover_merge == 1:
      merge_cmd = f"python3 {scripts_dir}/cov_merge.py --tool questa --outdir {outdir} --out_file merged.ucdb"
      if args.cover_excl_file:
          merge_cmd += f" --excl_file {args.cover_excl_file}"
      if verbose: print(f"[INFO] Coverage merge command:\n{merge_cmd}")
      if os.system(merge_cmd) != 0:
          print("[ERROR]: Coverage merge failed")
          exit(1)

      if cover_report == 1:
          merged_ucdb = os.path.join(outdir, "coverage",
              "merged_excluded.ucdb" if args.cover_excl_file else "merged.ucdb")
          report_cmd = (f"python3 {scripts_dir}/cov_report.py --tool questa --ucdb {merged_ucdb} "
                        f"--outdir {os.path.join(outdir, 'cov_report')} --report_type html")
          if args.cover_types:
              report_cmd += f" --cover_types {args.cover_types}"
          if args.cover_instance:
              report_cmd += f" --instance {args.cover_instance}"
          if verbose: print(f"[INFO] Coverage report command:\n{report_cmd}")
          os.system(report_cmd)
