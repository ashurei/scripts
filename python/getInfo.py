########################################################
# Description : Get remote ip from SIMS REPORT
# Create DATE : 2024.05.21
# Last Update DATE : 2024.05.22 by ashurei
# Copyright (c) Technical Solution, 2024
#########################################################

# Create remote_ip.txt file from SIMS REPORT csv file.
# Create resource.sql  file from SIMS REPORT csv file.

import argparse
import csv

parser = argparse.ArgumentParser(
        prog="getInfo",
        description="Get remote ip from SIMS REPORT csv file.",
        epilog="ashurei@sk.com"
)

parser.add_argument("-f", "--file", help="Input file name.", required=True)
args = parser.parse_args()

# Read csv file
f = open(args.file, "r")
reader = csv.DictReader(f)

# Process information
temp = ""
list_IP = []
d_remote = {}
d_sims = {}

for dict_row in reader:
    # temp != Machine IP, Initialize LIST because next machine is started.
    if temp != dict_row['관리장비명']:
        list_IP = []

    # Insert IP to LIST
    list_IP.append(dict_row['Remote 접속 IP'])
    # Insert LIST to Dictionary for Remote IP
    d_remote[dict_row['SIMS 연동 IP']] = list_IP
    # Dictionary for SIMS IP
    d_sims[dict_row['SIMS 연동 IP']] = dict_row['SIMS 연동 IP']

    # Save current row value for next loop
    temp = dict_row['관리장비명']

f.close()

# Create TXT for remote ip
f = open("./output/remote_ip.txt", "w")
for key,value in d_remote.items():
    remote_ip = ""
    for v in value:
        remote_ip = remote_ip + " " + v
    remote_ip_bar = remote_ip.lstrip().replace(" ", " |")
    f.write(key + "\t" + remote_ip_bar + "\n")
f.close()

# Create SQL to find resourceid, resourcename in TDIM
f = open("./output/resource.sql", "w")
f.write("cp /dev/null /tmp/tcore.txt\n")
for key,value in d_sims.items():
    sql = "mysql -u tcore -pTcore12# -h tcore-private-vip -e \"select ip, resourceid, resourcename from vw_rep_resource_bas where ip='" + value + "'\" -sN tcore_resource >> /tmp/tcore.txt\n"
    f.write(sql)
f.close()
