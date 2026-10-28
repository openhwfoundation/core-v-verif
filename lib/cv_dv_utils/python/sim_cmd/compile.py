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
import re

parser = argparse.ArgumentParser(description='compile options')
parser.add_argument('--yaml'     ,dest='yaml_file', type=str, help='Top YAML with compile and simulation options')
parser.add_argument('--outdir'   ,dest='outdir',    type=str, help='Logs are directed to outdir: default output')
parser.add_argument('--cover'    ,dest='cover',     type=int, help='1: instrument for coverage (adds +cover to vopt), 0: no coverage, default 0')
parser.add_argument('--cover_types'  , dest='cover_types',   type=str, help='coverage types for vopt +cover=<types> (e.g. "bcfs" = branch/condition/statement/FSM); only meaningful with --cover 1, default: bare +cover (all types)')
parser.add_argument('--cover_instance', dest='cover_instance', type=str, help='instance path to scope coverage instrumentation, appended as +cover=<types>+<instance>.; only meaningful with --cover 1, default: whole design')
parser.add_argument('--define'   ,dest='defines',    action='append', help='Additional +define+<MACRO> to pass to the compiler, repeatable')
args = parser.parse_args()

cover = args.cover if args.cover is not None else 0

   

if args.outdir==None:
    outdir = "output"
else:
    outdir = args.outdir
  
if os.path.isdir("{}".format(outdir)) == False:
     os.system("mkdir {}".format(outdir))




if args.yaml_file == None: 
   print("[ERROR] Please provide a Top YAML file")
else:
  
   with open(args.yaml_file, 'r') as yaml_top:
     sim_yaml = yaml.safe_load(yaml_top)
  
   for entry in sim_yaml:
    #Getting the yaml options
    if 'compile' in entry:
      comp      = entry['compile']
    else: 
      comp = ""

    if 'work_lib' in comp:
      work_lib  = comp['work_lib']
    else:
      work_lib = "work"

    #refresh work library
    if os.path.isdir("{}".format(work_lib)) == True:
      print("[INFO] Eliminating existing worklib {}...".format(work_lib))
      os.system("rm -r {}".format(work_lib))

    #create a fresh work library; required for non-default library names, and
    #avoids vopt silently reusing/misreading a stale library directory
    os.system("vlib {}".format(work_lib))

    if 'filelist' in comp:
      filelist  = comp['filelist']
      #Generating the filelist with Bender dependencies
      print("[INFO]: Updating Bender dependencies...")
      os.system("bender update")
      print("[INFO]: Creating Bender filelist...")
      bender_filelist=f"bender script flist-plus -t cv64a60ax_cvfpu_uvm -t cvfpu_uvm > {filelist}"
      os.system(bender_filelist)  
      
    else:
      filelist = ""    

    if 'comp_option' in comp:
      comp_opt  = comp['comp_option']
    else:
      comp_opt = ""

    if args.defines:
      comp_opt += "".join(f" +define+{d}" for d in args.defines)

    if 'elab_option' in comp:
       elab_opt = comp['elab_option']
    else:
       elab_opt = ""

    if cover == 1:
      cover_opt = f"+cover={args.cover_types}" if args.cover_types else "+cover"
      if args.cover_instance:
        cover_opt += f"+{args.cover_instance}."
    else:
      cover_opt = ""
      if args.cover_types or args.cover_instance:
        print("[INFO]: --cover_types/--cover_instance ignored because --cover is not set to 1")

    if 'top_entity' in comp:
      top  = comp['top_entity']
    else:
      top = "top"

  
    #Branch the compilation depending on the tool
    if entry['tool'] == "questa":
        print("[INFO]: Starting compilation with Questasim...")
        comp_cmd = f"vlog {comp_opt} -f {filelist} -work {work_lib} -logfile {outdir}/questa_compile.log"
        print("[INFO]: Compilation command:\n{}".format(comp_cmd))
        os.system(comp_cmd)

        print("[INFO]: Starting elaboration with Questasim...")
        elab_cmd = f"vopt {cover_opt} {elab_opt} -work {work_lib} {top} -o opt"
        print("[INFO] Elaboration command:\n{}".format(elab_cmd))
        os.system(elab_cmd)

    elif entry['tool'] == "xcelium":
        if cover == 1:
            print("[ERROR]: --cover option is only supported with questa")
            exit(1)
        print("[INFO]: Starting compilation with Xcelium...")
        comp_cmd = f"xrun -compile {comp_opt} -f {filelist} -work {work_lib} -logfile {outdir}/xcelium_compile.log"
        print("[INFO] Compilation command:\n{}".format(comp_cmd))
        os.system(comp_cmd)

        print("[INFO]: Starting elaboration with Xcelium...")
        elab_cmd = f"xrun -elaborate {elab_opt} -work {work_lib} -top {top} -logfile {outdir}/xcelium_elab.log"
        print("[INFO] Elaboration command:\n{}".format(elab_cmd))
        os.system(elab_cmd)

    elif entry['tool'] == "vcs":
        if cover == 1:
            print("[ERROR]: --cover option is only supported with questa")
            exit(1)
        print("[INFO]: Starting compilation and elaboration with VCS...")
        #removing existing timestamp for recompilation
        if os.path.isfile("simv.daidir/.vcs.timestamp") == True:
          os.system("rm simv.daidir/.vcs.timestamp")
          
        comp_cmd = f"vcs -Mdir={work_lib} {comp_opt} -f {filelist} -l {outdir}/vcs_compile.log"
        if comp_cmd != "vcs ":
          os.system(comp_cmd)
    else:
        print("[ERROR]: Not supported tool")