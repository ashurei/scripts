########################################################
# Description : Get remote ip from SIMS REPORT
# Create DATE : 2024.05.21
# Last Update DATE : 2024.06.21 by ashurei
# Copyright (c) Technical Solution, 2024
#########################################################

# Version: 2024.05.21.r5
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

### Define common remote IP
common_IP = []
with open(args.common, "r") as f:
    while True:
        line = f.readline().strip()
        if not line: break
        common_IP.append(line)
#print(common_IP)
#exit

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
    if temp != dict_row['EQP_ID']:
        access_IP = []

    # Skip insert remote IP to LIST when access_IP in common_IP
    if dict_row['Remote 접속 IP'] in common_IP:
        temp = dict_row['EQP_ID']
        continue

    # Insert Remote IP to LIST when access_IP not in common_IP
    access_IP.append(dict_row['Remote 접속 IP'])

    # Insert 'access_IP' to Dictionary 'd_remote' for Remote IP
    d_remote[dict_row['SIMS 연동 IP']] = list(dict.fromkeys(access_IP)) # Remove duplicate

    # Save current row value for next loop
    temp = dict_row['EQP_ID']

f.close()
