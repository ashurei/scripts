# Updated 2024.05.22

import argparse
import csv

parser = argparse.ArgumentParser(
        prog="get_remote_ip",
        description="Get remote ip from SIMS REPORT file.",
        epilog="ashurei@sk.com"
)

parser.add_argument("-f", "--file", help="Input file name.", required=True)
args = parser.parse_args()

f = open(args.file, "r")
reader = csv.DictReader(f)

temp = ""
list_IP = []
d = {}

for dict_row in reader:
    # temp == Machine IP, Initialize LIST
    if temp != dict_row['관리장비명']:
        list_IP = []

    # Insert IP to LIST
    list_IP.append(dict_row['Remote 접속 IP'])
    #print(list_IP)

    # Insert LIST to Dictionary
    d[dict_row['관리장비명']] = list_IP

    # Save current row value for next loop
    temp = dict_row['관리장비명']

f.close()

#print(d)

for key,value in d.items():
    remote_ip = ""
    for v in value:
        remote_ip = remote_ip + " " + v
    remote_ip_bar = remote_ip.lstrip().replace(" ", " |")
    #print(key + " " + remote_ip_bar)
    print(remote_ip_bar)
