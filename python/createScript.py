########################################################
# Description : Create register.sh script for TDIM alarm
# Create DATE : 2024.05.22
# Last Update DATE : 2024.06.20 by ashurei
# Copyright (c) Technical Solution, 2024
#########################################################

import argparse
import csv
import datetime

parser = argparse.ArgumentParser(
        prog="createScript",
        description="Create register.sh script for TDIM alarm.",
        epilog="ashurei@sk.com"
)

parser.add_argument("-f", "--file", help="Input file name.", required=True)
parser.add_argument("-g", "--group", help="Alarm group ID", required=True)
args = parser.parse_args()

# IP + TDIM info
d_tcore = {}
with open(args.file, "r") as f:
    for line in f:
        list_tcore = []
        list_tcore.append(line.split()[1])     # resourceid
        list_tcore.append(line.split()[2])     # resourcename
        if len(line.split()) == 3:            # NULL check
            list_tcore.append('NULL')
        else:
            list_tcore.append(line.split()[3]) # ostype (3 char)
        d_tcore[line.split()[0]] = list_tcore  # key: SIMS IP

#print(d_tcore)

### Get today
today = datetime.datetime.now().strftime("%Y%m%d")

### IP + Remote IP
d_remote = {}
remote_ip_txt = "output/" + today + "/remote_ip.txt"
with open(remote_ip_txt, "r") as f:
    for line in f:
        d_remote[line.split("\t")[0]] = line.split("\t")[1].replace("\n", "")

#print(d_remote)

### Create register_call.sh
f = open("./output/" + today + "/register_call.sh", "w")
for k in d_tcore.keys():
    #register = "./register.sh -f /var/log/secure -s \"" + d_remote[k] + "\" -t " + d_tcore[k][0] + " -n \'비인가접속_" + d_tcore[k][1] + "\"\n"
    if d_tcore[k][2] == 'deb':
        target = "/var/log/auth.log"
    elif d_tcore[k][2] == 'sle':
        target = "/var/log/audit/auth.log"
    else:
        target = "/var/log/secure"

    register = "./register.sh -f '" + target + "' -g " + args.group + " -s '" + d_remote[k] + "' -t " + d_tcore[k][0] + " -o '" + d_tcore[k][2] + "' -n '비인가접속_" + d_tcore[k][1] + "'\n"
    f.write(register)
    f.write("sleep 1\n")
f.close()
