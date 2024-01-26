#!/bin/bash
#####################################################################
# Description : Monitor CoreOS
# Create DATE : 2023.12.07
# Last Update DATE : 2024.01.25 by ashurei
# Copyright (c) ashurei@sk.com, 2023
#####################################################################

SCRIPT_VER="2024.01.26.r01"

IP="$1"
if [ -z "$IP" ]
then
  echo "[ERROR] Need IP."
  echo "(usage) ./monitorCoreOS.sh 10.0.0.1"
  exit 1
fi

### Define variables
DATE=$(date '+%Y-%m-%d-%H:%M:%S')
LOGDATE=$(date '+%Y%m%d')
SSH="ssh core@${IP}"
LOGDIR="/home/core/log"
LOG="${LOGDIR}/monitorCoreOS_${LOGDATE}.log"
LOG_SSH="${LOGDIR}/sshCoreOS_${LOGDATE}.log"
TMPFILE="/tmp/monitorCoreOS.txt"

### Directory
if [ ! -d "${LOGDIR}" ]
then
  set -e
  mkdir "${LOGDIR}"
  set +e
fi

# ============================================================================================= #
##@ Delete past log file
# ============================================================================================= #
find ${LOGDIR:?}/monitorCoreOS_*.log -mtime +390 -type f -delete 2>&1
find ${LOGDIR:?}/sshCoreOS_*.log -mtime +390 -type f -delete 2>&1


# ============================================================================================= #
##@ Check process count
# ============================================================================================= #
# Define process name
NUMBER=6
P1=("kubelet"          "kubelet --config")
P2=("crio"             "/usr/bin/crio")
P3=("chronyd"          "/usr/sbin/chronyd")
P4=("haproxy"          "/usr/sbin/haproxy")
P5=("openvswitch_conf" "ovsdb-server /etc/openvswitch/conf.db")
P6=("ovs-vswitchd"     "ovs-vswitchd unix")

# Check count of processes
for ((i=1; i<=NUMBER; i++))
do
  name="P$i[0]"
  process="P$i[1]"
  export P${i}_CNT="${!name}",$(${SSH} ps ax | grep "${!process}" | grep -v grep | wc -l)
done

# Merge array to variable
for ((i=1; i<=NUMBER; i++))
do
  process="P${i}_CNT"
  DATA=${DATA}${!process},
done


# ============================================================================================= #
##@ Collect CPU Usage
# ============================================================================================= #
CPU_USAGE=$(${SSH} "vmstat | tail -1 | awk '{print 100-\$15}'")


# ============================================================================================= #
##@ Collect Memory Usage
# ============================================================================================= #
LIST="MemTotal MemFree Buffers Cached Active"
${SSH} "cat /proc/meminfo" > "${TMPFILE}"

for str in ${LIST}
do
  FILTER=$str
  if [ "$str" == "Active" ]
  then
    FILTER="Active(anon)"
  fi
  eval "${str}"=$(grep ^${FILTER} ${TMPFILE} | awk '{print $2}')
  #echo $str ${!str}
done
MEM_USAGE=$(((${MemTotal}-${MemFree}-${Buffers}-${Cached}+${Active})*100/${MemTotal}))

# ============================================================================================= #
##@ Collect sshd log
# ============================================================================================= #
### sshd log
${SSH} "journalctl -u sshd --since '1 min ago' \
        | grep -E '(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])'" >> "${LOG_SSH}"

# ============================================================================================= #
##@ Write Server LOG
# ============================================================================================= #
echo "${DATE},${DATA%?},${CPU_USAGE},${MEM_USAGE}" >> "${LOG}"
