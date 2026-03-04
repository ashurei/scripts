########################################################
# Description : Get elapsed time
# Create DATE : 2026.03.04
# Last Update DATE : 2026.03.04 by ashurei
# Copyright (c) Technical Solution, 2026
#########################################################

### Sample
#[00:00:00:686042][Info   ] SubsProcessing  | TID[2026022700000001] MDN[01031342671] DATA[L601031342671 ...(skip)
#[00:00:00:701051][Info   ] Job             | Do Success

import argparse
import csv
import os
#import datetime
from datetime import datetime

parser = argparse.ArgumentParser(
        prog="getInfo",
        description="Get elapsed time.",
        epilog="ashurei@sk.com"
)

parser.add_argument("-f", "--file", help="Log file name.", required=True)
args = parser.parse_args()

### Read log file
f = open(args.file, "r", encoding="utf-8", errors="replace")
#reader = csv.DictReader(f)

startTime = ""
endTime = ""
delta = ""
fmt = "%H:%M:%S:%f"

### Split
for line in f:
    line = line.rstrip("\n")
    if not line:
        continue
    arr1 = line.split("|")
    #print(arr1[0])

    # Pass "Warning"
    if arr1[0].split("[")[2].split("]")[0] == "Warning":
        continue

    # Get time
    time = arr1[0].split("]")[0].lstrip("[")

    # Get type
    type = arr1[0].split()[2]
    #print(type,time)

    # Set start/end time
    if type == "SubsProcessing":
        startTime = time
    elif type == "Job":
        endTime = time

    # Calcurate elaspe time between startTime and endTime
    if startTime != "" and endTime != "":
        #print("sTime: " + startTime + " / eTime:" + endTime)
        t1 = datetime.strptime(startTime, fmt)
        t2 = datetime.strptime(endTime, fmt)
        delta = t2 - t1
        #print("startTime: " + startTime + " / elapsedTime : " + elapsedTime)
        print("startTime/diff_sec: " + startTime + " / " + str(delta.total_seconds()))

        # Initiate time
        startTime = ""
        endTime = ""
