#!/bin/bash
#####################################################################
# Description : Monitor CoreOS
# Create DATE : 2023.12.07
# Last Update DATE : 2023.12.07 by ashurei
# Copyright (c) ashurei@sk.com, 2023
#####################################################################

DATE=$(date '+%Y-%m-%d-%H:%M:%S')
LOGDATE=$(date '+%Y%m%d')
SSH="ssh core@60.30.207.48"
LOG="/home/core/log/checkProcess_${LOGDATE}.log"

### Define process name
NUMBER=6
P1=("kubelet"          "kubelet --config")
P2=("crio"             "/usr/bin/crio")
P3=("chronyd"          "/usr/sbin/chronyd")
P4=("haproxy"          "/usr/sbin/haproxy")
P5=("openvswitch_conf" "ovsdb-server /etc/openvswitch/conf.db")
P6=("ovs-vswitchd"     "ovs-vswitchd unix")

### Check count of processes
for ((i=1; i<=${NUMBER}; i++))
do
  name="P$i[0]"
  process="P$i[1]"
  export P${i}_CNT=${!name},$(${SSH} ps ax | grep "${!process}" | grep -v grep | wc -l)
done

### Merge array to variable
for ((i=1; i<=${NUMBER}; i++))
do
  process="P${i}_CNT"
  DATA=${DATA}${!process},
done

echo "${DATE},${DATA%?}"
