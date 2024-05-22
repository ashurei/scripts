########################################################
# Description : Create register.sh script for TDIM alarm
# Create DATE : 2024.05.22
# Last Update DATE : 2024.05.22 by ashurei
# Copyright (c) Technical Solution, 2024
#########################################################

import argparse
import csv

parser = argparse.ArgumentParser(
        prog="createScript",
        description="Create register.sh script for TDIM alarm.",
        epilog="ashurei@sk.com"
)

parser.add_argument("-f", "--file", help="Input file name.", required=True)
args = parser.parse_args()

# IP + TDIM info
d_tcore = {}
with open(args.file, "r") as f:
    for line in f:
        #print(line.split()[0] + " " + line.split()[1])
        #d_tcore[line.split()[0]] = [ line.split()[1], line.split[2] ]
        list_tcore = []
        list_tcore.append(line.split()[1])
        list_tcore.append(line.split()[2])
        d_tcore[line.split()[0]] = list_tcore

#print(d_tcore)

# IP + Remote IP
d_remote = {}
remote_ip_txt = "output/remote_ip.txt"
with open(remote_ip_txt, "r") as f:
    for line in f:
        #print(line.split()[0] + " " + line.split()[1] + " " + line.split()[2])
        #print(line.split("\t")[0] + " " + line.split("\t")[1].replace("\n", ""))
        d_remote[line.split("\t")[0]] = line.split("\t")[1].replace("\n", "")

#print(d_remote)

# Create register_call.sh
f = open("./output/register_call.sh", "w")
for k in d_tcore.keys():
    register = "./register.sh -f /var/log/secure -s \"" + d_remote[k] + "\" -t " + d_tcore[k][0] + " -n \'비인가접속_" + d_tcore[k][1] + "\"\n"
    f.write(register)
f.close()
