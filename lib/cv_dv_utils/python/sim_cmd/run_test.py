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
import yaml

parser = argparse.ArgumentParser(description='compile options')
parser.add_argument('--yaml'     ,dest='yaml_file', type=str, help='Top YAML with compile and simulation options')
parser.add_argument('--test_name',dest='test_name', type=str, help='Name of the test')
parser.add_argument('--seed'     , dest='seed',      type=int, help='random seed ex: 3452363, default 1')
parser.add_argument('--debug'    , dest='debug',     type=str, help='UVM_LOW/MEDIUM/HIGH/FULL/DEBUG, default LOW')
parser.add_argument('--batch'    , dest='batch',     type=int, help='1: batch mode, 0:gui default, 1')
parser.add_argument('--dump'     , dest='dump',      type=int, help='1: all signals are logged, 0: nothing is looged, default 1') #FIXME
parser.add_argument('--cover'    , dest='cover',     type=int, help='1: generate coverage file (Questasim only), 0: nothing is done, default 0')
parser.add_argument('--cover_excl_file', dest='cover_excl_file', type=str, help='optional coverage exclusion .do/.tcl file, sourced before the per-test UCDB is saved; only meaningful with --cover 1, never applied unless explicitly given')
parser.add_argument('--designfile', dest='designfile', type=str, help='design.bin file created by vopt -designfile, attached to Visualizer (GUI mode) for schematic/class/assertion views (Questa only), default "design.bin"')
parser.add_argument('--stdout'   , dest='stdout', type=int, help='1: stdout 0: nostdout')
parser.add_argument('--outdir'   , dest='outdir', type=str, help='output dirctory default "output"')
parser.add_argument('--verbose'  , dest='verbose', action='store_true', help='print info messages, default False')
parser.add_argument('--run_time' , dest='run_time', type=str, help='simulation run time ex: 100ns, default -all')

args = parser.parse_args()
verbose = args.verbose
run_time = args.run_time if args.run_time is not None else "-all"


option_ok = 1
#check for the insertion of the yaml top file
if args.yaml_file == None:
   print("[ERROR] Please specify the YAML")
   option_ok = 0
else:
   yaml_file = args.yaml_file

#check for the insertion of the test name   
if args.test_name == None: 
   print("[ERROR] Please specify the testname")
   option_ok = 0
else:
   test_name = args.test_name

#set default values if seed, debug, batch, dump, stdout and outdir are not defined
if args.seed == None:
   if verbose: print("[INFO] Setting default seed = 1")
   seed = 1
else:
   seed = args.seed

if args.debug == None:
   if verbose: print("[INFO] Setting default UVM debug = UVM LOW")
   debug = "UVM_LOW"
else:
   debug = args.debug

if args.batch == None:
   if verbose: print("[INFO] Setting default mode = batch mode")
   batch = 1
else:
   batch = args.batch

if args.dump == None:
   if verbose: print("[INFO] Setting default dump = 0")
   dump = 0
else:
   dump = args.dump

cover = args.cover if args.cover is not None else 0
designfile = args.designfile if args.designfile is not None else "design.bin"

if args.stdout == None:
   if verbose: print("[INFO] Setting default output (-l)")
   stdout = 1
else:
   stdout = args.stdout

if args.outdir == None:
   if verbose: print("[INFO] Setting default output directory = output")
   outdir = "output"
else:
   outdir = args.outdir

#check outdir --> if it is not present create it
if os.path.isdir("{}".format(outdir)) == False:
     os.system("mkdir {}".format(outdir))


if option_ok == 1:
  #Recognize the used tool
   with open(args.yaml_file, 'r') as yaml_top:
     sim_yaml = yaml.safe_load(yaml_top)

   for entry in sim_yaml: 
      # getting the sim options
      if 'compile' in entry:
         comp_entry = entry['compile']
      else:
         comp_entry = ""

      if 'work_lib' in comp_entry:
         worklib = comp_entry['work_lib']
      else:
         worklib = ""

      if 'top_entity' in comp_entry:
         top = comp_entry['top_entity']
      else:
         top = ""      

      if 'sim' in entry:
         sim_entry      = entry['sim']
      else: 
         sim_entry = ""

      if 'sim_option' in sim_entry:
         sim_opt = sim_entry['sim_option']
      else:
         sim_opt = ""

      #Branch the simulation depending on the tool
      if entry['tool'] == "questa":
         #directory that stores dbg files
         dbg_dir = os.path.join(outdir, "questa_db")
         if os.path.isdir("{}".format(dbg_dir)) == False:
            os.system("mkdir {}".format(dbg_dir))

         #Full path to output dbg
         db_file = os.path.join(dbg_dir, f"{test_name}_{seed}.db")

         #directory that stores coverage UCDB files
         if cover == 1:
            cov_dir = os.path.join(outdir, "coverage")
            if os.path.isdir("{}".format(cov_dir)) == False:
               os.system("mkdir {}".format(cov_dir))
            ucdb_file = os.path.join(cov_dir, f"{test_name}_{seed}.ucdb")
         
         #DO
         # Unique per test/seed: a shared "questa_run.do" name races when multiple
         # run_test.py invocations execute concurrently (e.g. --nthreads > 1) from the
         # same working directory, silently misdirecting/losing coverage saves.
         do_file = f"questa_run_{test_name}_{seed}.do"
         if os.path.isfile("{}".format(do_file)) == False:
            if verbose: print("[INFO]: creating new questa_run.do file...")
            os.system("touch {}".format(do_file))
         else:
            if verbose: print("[INFO]: removing old questa_run.do file...")
            os.system("rm {}".format(do_file))
            if verbose: print("[INFO]: creating new questa_run.do file...")
            os.system("touch {}".format(do_file))
         
         if batch == 1:
            batchstr = "-c"
         else:
            batchstr = f"-visualizer=+designfile={designfile}"

         if dump == 1:
            with open(do_file, "w") as do:
               if batch == 1:
                  if cover == 1:
                     if args.cover_excl_file:
                        do.write(f"source {args.cover_excl_file}\n")
                     do.write(f"coverage save -onexit {ucdb_file}\n")
                  do.write(f"run {run_time}\n")
                  do.write("quit -f\n")
               else:
                  do.write("add log -r /*\n")

            dumpstr = f"-qwavedb=+wavefile={db_file}+signal+memory=4096+class+assertion+ignoretxntime+msgmode=both -do {do_file}"

         else:
            with open(do_file, "w") as do:
               if batch == 1:
                  if cover == 1:
                     if args.cover_excl_file:
                        do.write(f"source {args.cover_excl_file}\n")
                     do.write(f"coverage save -onexit {ucdb_file}\n")
                  do.write(f"run {run_time}\n")
                  do.write("quit\n")
               else:
                  do.write("add log -r /*\n")

            dumpstr = f"-do {do_file}"

         if stdout == 0:
            stdoutstr = ">"
         else:
            stdoutstr = "-l"

         coverstr = "-coverage" if cover == 1 else ""

         if verbose: print("[INFO]: Starting simulation with Questasim...")
         sim_cmd = f"vsim -lib {worklib} {sim_opt} {batchstr} {coverstr} {dumpstr} -sv_seed {seed} +UVM_VERBOSITY={debug} +UVM_TESTNAME={test_name} {stdoutstr} {outdir}/{test_name}_{seed}.log"
         if verbose: print("[INFO] Simulation command:\n{}\n".format(sim_cmd))
         os.system(sim_cmd)

         # Clean up the per-test/seed do file now that vsim has consumed it;
         # keeping the unique name (needed to avoid the parallel-run race) but
         # not leaving it behind avoids littering the working directory.
         os.system(f"rm -f {do_file}")

      elif entry['tool'] == "xcelium":
         if cover == 1:
            print("[ERROR]: --cover option is only supported with questa")
            exit(1)
         #directory that stores shm files
         shm_dir = os.path.join(outdir, "xlm_db")
         if os.path.isdir("{}".format(shm_dir)) == False:
            os.system("mkdir {}".format(shm_dir))
         
         #Full path to output shm
         shm_file = os.path.join(shm_dir, f"{test_name}_{seed}.shm")
         
         #TCL
         tcl_file = "xlm_run.tcl"
         if os.path.isfile("{}".format(tcl_file)) == False:
            if verbose: print("[INFO]: creating new xlm_run.tcl file...")
            os.system("touch {}".format(tcl_file))
         else:
            if verbose: print("[INFO]: removing old xlm_run.tcl file...")
            os.system("rm {}".format(tcl_file))
            if verbose: print("[INFO]: creating new xlm_run.tcl file...")
            os.system("touch {}".format(tcl_file))
         

         #options customization
         #DUMPING: batch=1 and dump=0 --> just results on terminal
         #         batch=1 and dump=1 --> create db, probe signals, post proc shm file
         #         batch=0 and dump=0 --> just open the gui without running simulation
         #         batch=0 and dump=1 --> open simulation in gui mode and dump res in .shm file
         if batch == 1:
            batchstr = "-batch"
         else:
            batchstr = "-gui"

         if dump == 1:
            with open(tcl_file, "w") as tcl:
               tcl.write(f"database -open waves -into {shm_file} -default\n")
               tcl.write( "probe -create -all -depth all -database waves\n")
               if batch == 1:
                  tcl.write( "run\n")
                  tcl.write( "exit\n")
         else:
            with open(tcl_file, "w") as tcl:
               if batch == 1:
                  tcl.write("run\n")
                  tcl.write("exit\n")
            
         dumpstr = f"-input {tcl_file}"

         if stdout == 0:
            stdoutstr = ">"
         else:
            stdoutstr = "-l"
            
         if verbose: print("[INFO]: Starting simulation with Xcelium...")
         sim_cmd = f"xrun -r {sim_opt} {batchstr} {dumpstr} -seed {seed} +UVM_VERBOSITY={debug} +UVM_TESTNAME={test_name} {stdoutstr} {outdir}/{test_name}_{seed}.log"
         if verbose: print("[INFO] Simulation command:\n{}\n".format(sim_cmd))
         os.system(sim_cmd)


      elif entry['tool'] == "vcs":
         if cover == 1:
            print("[ERROR]: --cover option is only supported with questa")
            exit(1)
         #directory that stores fsbd files
         fsdb_dir = os.path.join(outdir, "vcs_db")
         if os.path.isdir("{}".format(fsdb_dir)) == False:
            os.system("mkdir {}".format(fsdb_dir))
         
         #Full path to output fsdb
         fsdb_file = os.path.join(fsdb_dir, f"{test_name}_{seed}.fsdb")
         
         #TCL
         tcl_file = "vcs_run.tcl"
         if os.path.isfile("{}".format(tcl_file)) == False:
            if verbose: print("[INFO]: creating new vcs_run.tcl file...")
            os.system("touch {}".format(tcl_file))
         else:
            if verbose: print("[INFO]: removing old vcs_run.tcl file...")
            os.system("rm {}".format(tcl_file))
            if verbose: print("[INFO]: creating new vcs_run.tcl file...")
            os.system("touch {}".format(tcl_file))



         #options customization
         if batch == 1:
            batchstr = "-ucli"
         else:
            batchstr = "-gui"

         if dump == 1:
            with open(tcl_file, "w") as tcl:
               if batch == 1:
                  tcl.write(f"dump -file {fsdb_file} -type FSDB\n")
                  tcl.write( f"dump -add {top} -depth 0 -fid FSDB0\n")
                  tcl.write( "run\n")
                  tcl.write( "quit\n")
               else:
                  #inter.fsdb automatically generated by verdi gui
                  if os.path.isfile("inter.fsdb") == True:
                     os.system(f"cp ./inter.fsdb ./{fsdb_file}")
         else:
            with open(tcl_file, "w") as tcl:
               if batch == 1:
                  tcl.write("run\n")
                  tcl.write("quit\n")
            
         dumpstr = f"-i {tcl_file}"

         if stdout == 0:
            stdoutstr = ">"
         else:
            stdoutstr = "-l"

         if verbose: print("[INFO]: Starting simulation with VCS...")
         sim_cmd = f"./simv {sim_opt} {batchstr} {dumpstr} +ntb_random_seed={seed} +UVM_VERBOSITY={debug} +UVM_TESTNAME={test_name} {stdoutstr} {outdir}/{test_name}_{seed}.log"
         if verbose: print("[INFO] Simulation command:\n{}\n".format(sim_cmd))
         os.system(sim_cmd)
      else:
         print("[ERROR]: Not supported tool")

