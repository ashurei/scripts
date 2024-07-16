########################################################
# Description : Create register.sh script for TDIM alarm
# Create DATE : 2024.05.22
# Last Update DATE : 2024.07.16 by ashurei
# Copyright (c) Technical Solution, 2024
#########################################################

### Version: 2024.07.16.r3
# Create files from SIMS REPORT csv file.
#   register_call.sh

import argparse
import csv
import datetime

parser = argparse.ArgumentParser(
        prog="createScript",
        description="Create register.sh script for TDIM alarm.",
        epilog="ashurei@sk.com"
)

parser.add_argument("-f", "--file", help="Input file name.", required=True)
parser.add_argument("-c", "--common", help="Input common IP list.", required=True)
parser.add_argument("-l", "--location", help="Input location. [SS, DS, BD, BR]", required=True)
parser.add_argument("-g", "--group", help="Alarm group ID", required=True)
args = parser.parse_args()

# IP + TDIM info
d_tcore = {}
with open(args.file, "r") as f:
    for line in f:
        list_tcore = []
        # length of line.split() is 4 in normal case.
        list_tcore.append(line.split()[1])     # resourceid
        list_tcore.append(line.split()[2])     # resourcename
        if len(line.split()) == 3:             # NULL check
            list_tcore.append('NULL')
        else:
            list_tcore.append(line.split()[3]) # ostype (3 char)
        d_tcore[line.split()[0]] = list_tcore  # key: SIMS IP

#print(d_tcore)

### Get directory
today = datetime.datetime.now().strftime("%Y%m%d")
outdir = "./output/" + today + "_" + args.location

### IP + Remote IP
d_remote = {}
remote_ip_txt = outdir + "/remote_ip.txt"
with open(remote_ip_txt, "r") as f:
    for line in f:
        d_remote[line.split("\t")[0]] = line.split("\t")[1].replace("\n", "")

#print(d_remote)

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

### Merge common_IP to remote_ip
remote_ip = ""
for ip in common_IP:
    remote_ip = remote_ip + " |" + ip
# ================================================================================================================================================= #

### Create register_call.sh
f = open(outdir + "/register_call.sh", "w")
for k in d_tcore.keys():
    #register = "./register.sh -f /var/log/secure -s \"" + d_remote[k] + "\" -t " + d_tcore[k][0] + " -n \'비인가접속_" + d_tcore[k][1] + "\"\n"
    if d_tcore[k][2] == 'deb':
        target = "/var/log/auth.log"
    elif d_tcore[k][2] == 'sle':
        target = "/var/log/audit/auth.log"
    else:
        target = "/var/log/secure"

    # Use '-s' option when individual IP is exists
    if d_remote[k]:
        register = "./register.sh -f '" + target + "' -g " + args.group + " -c '" + remote_ip[2:] + "' -s '" + d_remote[k] + "' -t " + d_tcore[k][0] + " -o '" + d_tcore[k][2] + "' -n '비인가접속_" + d_tcore[k][1] + "'\n"
    else:
        register = "./register.sh -f '" + target + "' -g " + args.group + " -c '" + remote_ip[2:] + "' -t " + d_tcore[k][0] + " -o '" + d_tcore[k][2] + "' -n '비인가접속_" + d_tcore[k][1] + "'\n"
    f.write(register)
    f.write("sleep 1\n")
f.close()
