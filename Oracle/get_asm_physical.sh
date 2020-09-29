#!/bin/bash
#################################################
# Description : Oracle ASM disk with physical disk
# Create DATE : 2020.09.29
# Last Update DATE : 2020.09.29 by ashurei
# Copyright (c) Technical Solution, 2020
#################################################

# Insert to array per line
IFS=$'\n' DISKS=$(ls -l /dev/oracleasm/disks/* | awk '{print $5,$6,$10}')

# Loop with oracleasm disks
for list in $DISKS
do
        A=$(echo ${list} | awk '{print $1}')
        B=$(echo ${list} | awk '{print $2}')
        DISK=$(echo ${list} | awk '{print $3}' | awk -F"/" '{print $5}')
        DEVICE=$(ls -l /dev/* | grep ${A} | grep ${B} | awk '{print $10}')

        # Print oracleasm disk and block device (ex. DATA01 /dev/sdb1)
        echo -e "${DISK}\t${DEVICE}"
done
