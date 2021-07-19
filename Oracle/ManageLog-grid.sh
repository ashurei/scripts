#!/bin/bash
########################################################
# Description : Management of Grid logs for Oracle
# Create DATE : 2021.07.19
# Last Update DATE : 2021.07.19 by ashurei
# Copyright (c) Technical Solution, 2021
########################################################

HOSTNAME=$(hostname)
################################
# Need to modify
GRID_BASE="/oracle/gridbase"
GRID_HOME="/oracle/grid"
RETENTION_DAYS="30"
################################

GRID_USER=$(whoami)
# If user length is equal 8, remove '+' (ex. gridSPA+ => gridSPA)
if [ "${#GRID_USER}" -eq 8 ]
then
  GRID_USER="${GRID_USER:0:-1}"
fi

### Remove listener log
LISTENERs=$(ps aux | grep tnslsnr | grep "^${GRID_USER}" | grep -v grep | awk '{print $12}')
for listener in ${LISTENERs}
do
  LISTENER_TRACE="${GRID_BASE}/diag/tnslsnr/${HOSTNAME}/${listener,,}/trace"
  LISTENER_ALERT="${GRID_BASE}/diag/tnslsnr/${HOSTNAME}/${listener,,}/alert"
  
  find "${LISTENER_TRACE}" -maxdepth 1 -name "${listener,,}_[0-9]*.log" -mtime +${RETENTION_DAYS} -type f -delete
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
