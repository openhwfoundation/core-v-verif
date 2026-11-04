# Copyright 2025 Fondazione Chips-IT
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

import argparse
import os
from pathlib import Path

parser = argparse.ArgumentParser(description='post processing options')
parser.add_argument('--tool'     ,dest='tool_name', type=str, help='set the tool for post-processing analysis')
parser.add_argument('--db_file'     ,dest='db_file', type=str, help='db file to launch in GUI mode for post processing')
parser.add_argument('--designfile'  ,dest='designfile', type=str, help='design.bin file created by vopt -designfile, attached to Visualizer for schematic/class/assertion views (Questa only), default "design.bin"')

args = parser.parse_args()
designfile = args.designfile if args.designfile is not None else "design.bin"

def check_extension(filename, ext):
    return Path(filename).suffix.lower() == ext.lower()


option_ok = 1
#check for the insertion of the tool name
if args.tool_name == None:
   print("[ERROR]: Please specify the supported tool (questa|xcelium|vcs)")
   option_ok = 0
else:
    #check if the tool is among the supported ones
    if args.tool_name == "questa" or args.tool_name == "xcelium" or args.tool_name == "vcs":
        tool_name = args.tool_name
    else:
        print("[ERROR]: Inserted tool is not supported")
        option_ok = 0

#check for the insertion of the db file
if args.db_file == None:
   print("[ERROR]: Please specify the database file")
   option_ok = 0
else:
    #check if the file exists
    if args.tool_name == "questa" or args.tool_name == "vcs":
        if os.path.isfile(f"{args.db_file}") == True:
            db_file = args.db_file
        else:
            print("[ERROR]: Inserted db file does not exist")
            option_ok = 0
    else:
        if os.path.isdir(f"{args.db_file}") == True:
            db_file = args.db_file
        else:
            print("[ERROR]: Inserted db file does not exist")
            option_ok = 0       

if option_ok == 1:
    if tool_name == "questa":
        print("[INFO]: Starting post-processing analysis with Questa Visualizer...")
        if check_extension(db_file, ".db"):
            cmd = f"visualizer -designfile {designfile} -wavefile {db_file}"
            os.system(cmd)
        elif check_extension(db_file, ".ucdb"):
            cmd = f"visualizer -designfile {designfile} -viewcov {db_file}"
            os.system(cmd)
        else:
            print("[ERROR]: Wrong kind of file for this tool")

    elif tool_name == "xcelium":
        print("[INFO]: Starting post-processing analysis with Simvision...")
        if check_extension(db_file, ".shm"):
            cmd = f"simvision -debugdb {db_file}"
            os.system(cmd)
        else:
            print("[ERROR]: Wrong kind of file for this tool")

    elif tool_name == "vcs":
        print("[INFO]: Starting post-processing analysis with Verdi...")
        if check_extension(db_file, ".fsdb"):
            cmd = f"verdi -ssf {db_file} -nologo"
            os.system(cmd)
        else:
            print("[ERROR]: Wrong kind of file for this tool")

    else:
        print("[ERROR]: Error while parsing")

