########################################################
# Description : Get remote ip from SIMS REPORT
# Create DATE : 2024.05.21
# Last Update DATE : 2024.07.16 by ashurei
# Copyright (c) Technical Solution, 2024
#########################################################

### Version: 2024.07.16.r2
# Create files from SIMS REPORT csv file.
#   resource_common.sh
#   remote_ip.txt
#   get_tdim_info.sh
#   check_in_tdim.sh

import argparse
import csv
import os
import datetime

parser = argparse.ArgumentParser(
        prog="getInfo",
        description="Get remote ip from SIMS REPORT csv file.",
        epilog="ashurei@sk.com"
)

parser.add_argument("-f", "--file", help="Input CSV file name.", required=True)
parser.add_argument("-c", "--common", help="Input common IP list.", required=True)
parser.add_argument("-l", "--location", help="Input location. [SS, DS, BD, BR]", required=True)
parser.add_argument("-g", "--group", help="Alarm group ID", required=True)
args = parser.parse_args()

### Check location
centers = {'SS':'성수', 'DS':'둔산', 'BD':'분당', 'BR':'보라매'}
if args.location not in centers.keys():
    print("Input location. [SS, DS, BD, BR]")
    exit
center = centers[args.location]

# ================================================================================================================================================= #
### Define common remote IP
common_IP = []
with open(args.common, "r") as f:
    while True:
        line = f.readline().strip()
        if not line: break
        common_IP.append(line)
#print(common_IP)
#exit
# ================================================================================================================================================= #

### Read CSV file
f = open(args.file, "r")
reader = csv.DictReader(f)

### Process information
temp = ""
access_IP = []
d_remote = {}
d_sims = {}

for dict_row in reader:
    # Dictionary for SIMS IP (key,value) = ('장비명','IP'). Use dictionry to prevent duplicate.
    d_sims[dict_row['관리장비명']] = dict_row['SIMS 연동 IP']

    # temp != Machine IP, Initialize LIST because next machine is started.
    if temp != dict_row['SIMS 연동 IP']:
        # access_IP is null means this EQP_ID have only common IP.
        if d_remote and not access_IP:
           d_remote[temp] = 'empty'
        access_IP = []

    # Skip insert remote IP to LIST when access_IP in common_IP
    if dict_row['Remote 접속 IP'] in common_IP:
        temp = dict_row['SIMS 연동 IP']
        continue

    # Insert Remote IP to LIST when access_IP not in common_IP
    access_IP.append(dict_row['Remote 접속 IP'])

    # Insert 'access_IP' to Dictionary 'd_remote' for Remote IP
    d_remote[dict_row['SIMS 연동 IP']] = list(dict.fromkeys(access_IP)) # Remove duplicate

    # Save current row value for next loop
    temp = dict_row['SIMS 연동 IP']

f.close()

#print(len(d_remote))
#print(d_sims)
#print(d_remote)

# ================================================================================================================================================= #
### Create output directory
today = datetime.datetime.now().strftime("%Y%m%d")
outdir = "./output/" + today + "_" + args.location
os.makedirs(outdir, exist_ok=True)

### Create 'remote_ip.txt' from 'd_remote'
filename = outdir + "/remote_ip.txt"
with open(filename, "w") as f:
    for key,value in d_remote.items():
        if value == 'empty':
            f.write(key + "\t\n")
            continue
        # Merge IP of each machine
        remote_ip = ""
        for v in value:
          remote_ip = remote_ip + " |" + v
        f.write(key + "\t" + remote_ip[2:] + "\n")  # Cut left " |"

### Create 'get_tdim_info.sh' from 'd_remote.keys()' to find resourceid, resourcename in TDIM using SIMS IP.
tdim_info = "/tmp/tcore_" + today + "_" + args.location + ".txt"
filename = outdir + "/get_tdim_info.sh"
with open(filename, "w") as f:
    f.write("cp /dev/null " + tdim_info + "\n")
    for key in d_remote.keys():
        #sql = "mysql -u tcore -pTcore12# -h tcore-private-vip -e \"select ip, resourceid, resourcename, ostype from vw_rep_resource_bas where ip='" + value + "'\" -sN tcore_resource >> /tmp/tcore.txt\n"
        sql = "select a.ip, a.resourceid, a.resourcename, lower(substr(b.osname,1,3)) from vw_rep_resource_bas a, vw_rep_resource_management b where a.resourceid = b.resourceid and a.ip='" + key + "'"
        cmd = "mysql -u tcore -pTcore12# -h tcore-private-vip -e \"" + sql + "\" -sN tcore_resource >> " + tdim_info + "\n"
        f.write(cmd)

### Create 'check_in_tdim.sh from 'd_sims'
sims_info = "/tmp/sims_" + today + "_" + args.location + ".txt"
filename = outdir + "/check_in_tdim.sh"
sims_ip = ""
with open(filename, "w") as f:
    # Merge IP
    for key,value in d_sims.items():
        sql = "select ip, resourceid, resourcename from vw_rep_resource_bas where ip = '" + value + "'"
        cmd = "mysql -u tcore -pTcore12# -h tcore-private-vip -e \"" + sql + "\" -sN tcore_resource >> " + sims_info + "\n"
        f.write(cmd)
