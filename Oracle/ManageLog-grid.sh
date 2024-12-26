#!/bin/bash
########################################################
# Description : Management of Grid logs for Oracle
# Create DATE : 2021.07.19
# Last Update DATE : 2024.12.26 by ashurei
# Copyright (c) Technical Solution, 2021
########################################################

# This script can only be used on Linux platform.

################################
# Need to modify
GRID_BASE="/oracle/gridbase"
GRID_HOME="/oracle/grid"
RETENTION_DAYS="30"
################################

HOSTNAME=$(hostname)
GRID_USER=$(whoami)
# If user length is equal 8, remove '+' (ex. gridSPA+ => gridSPA)
if [ "${#GRID_USER}" -eq 8 ]
then
  GRID_USER="${GRID_USER:0:-1}"
fi

### Rotate & Remove listener log
LISTENERs=$(ps aux | grep tnslsnr | grep "^${GRID_USER}" | grep -v grep | awk '{print $12}')
for listener in ${LISTENERs}
do
  # Rotate & Remove
  TRACE_PATH="$(lsnrctl status $listener | grep "Listener Log File" | awk '{print $4}' | awk -F'alert' '{print $1}')trace"
  cp "${TRACE_PATH}/${listener,,}.log" "${TRACE_PATH}/${listener,,}.log.$(date '+%Y%m%d')"
  tar cfz "${TRACE_PATH}/${listener,,}.log.$(date '+%Y%m%d')".tgz "${TRACE_PATH}/${listener,,}.log.$(date '+%Y%m%d')" --remove-files
  cp /dev/null "${TRACE_PATH}/${listener,,}.log"
  find "${TRACE_PATH}" -maxdepth 1 -name "${listener,,}*.log.tgz" -mtime +${RETENTION_DAYS} -type f -delete
  
  # Remove
  LISTENER_ALERT="${GRID_BASE}/diag/tnslsnr/${HOSTNAME}/${listener,,}/alert"
  find "${LISTENER_ALERT}" -maxdepth 1 -name "log_[0-9]*.xml" -mtime +${RETENTION_DAYS} -type f -delete
done


### Remove audit and CRS trace
GRID_AUDIT="${GRID_HOME}/rdbms/audit"
find "${GRID_AUDIT}" -maxdepth 1 -name "+ASM1_ora*.aud" -mtime +${RETENTION_DAYS} -type f -delete

CRS_TRACE="${GRID_BASE}/diag/crs/${HOSTNAME}/crs/trace"
find "${CRS_TRACE}"  -maxdepth 1 -name "*[0-9].tr[c,m]" -mtime +${RETENTION_DAYS} -type f -delete


### Remove ASM trace log
isASM=$(ps ax | grep -v grep | grep -c asm_pmon)
if [ "${isASM}" -gt 0 ]
then
  ASM_SID=$(ps ax | grep asm_pmon | grep -v grep | awk '{print $NF}' | cut -d"_" -f3)
  ASM_TRACE="${GRID_BASE}/diag/asm/+asm/${ASM_SID}/trace"
  
  find "${ASM_TRACE}" -maxdepth 1 -name "${ASM_SID}_*.tr[c,m]" -mtime +${RETENTION_DAYS} -type f -delete
fi
