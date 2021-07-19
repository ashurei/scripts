#!/bin/bash
########################################################
# Description : Management of Database logs for Oracle
# Create DATE : 2021.07.19
# Last Update DATE : 2021.07.19 by ashurei
# Copyright (c) Technical Solution, 2021
########################################################

HOSTNAME=$(hostname)
################################
# Need to modify
DIAG_DEST="/oracle/database"		# diagnostic_dest
RETENTION_DAYS="30"
################################

ORACLE_USER=$(whoami)
# If user length is equal 8, remove '+' (ex. oraSPAM+ => oraSPAM)
if [ "${#ORACLE_USER}" -eq 8 ]
then
  ORACLE_USER="${ORACLE_USER:0:-1}"
fi

### Remove listener log
LISTENERs=$(ps aux | grep tnslsnr | grep "^${ORACLE_USER}" | grep -v grep | awk '{print $12}')
for listener in ${LISTENERs}
do
  LISTENER_TRACE="${DIAG_DEST}/diag/tnslsnr/${HOSTNAME}/${listener,,}/trace"
  LISTENER_ALERT="${DIAG_DEST}/diag/tnslsnr/${HOSTNAME}/${listener,,}/alert"
  
  find "${LISTENER_TRACE}" -maxdepth 1 -name "${listener,,}_[0-9]*.log" -mtime +${RETENTION_DAYS} -type f -delete
  find "${LISTENER_ALERT}" -maxdepth 1 -name "log_[0-9]*.xml" -mtime +${RETENTION_DAYS} -type f -delete
done


### Remove audit and Database trace
ORACLE_SIDs=$(ps aux | grep ora_pmon | grep -w "^${ORACLE_USER}" | grep -v grep | awk '{print $NF}' | cut -d"_" -f3)
for ORACLE_SID in ${ORACLE_SIDs}
do
  DATABASE_NAME="${ORACLE_SID:0:-1}"
  DATABASE_NAME_LOWER=$(echo "${DATABASE_NAME}" | tr '[:upper:]' '[:lower:]')
  TRACE="${DIAG_DEST}/diag/rdbms/${DATABASE_NAME_LOWER}/${ORACLE_SID}/trace"
  find "${TRACE}" -maxdepth 1 -name "*[0-9].tr[c,m]" -mtime +${RETENTION_DAYS} -type f -delete
  
  AUDIT="${DIAG_DEST}/admin/${DATABASE_NAME}/adump"
  find "${AUDIT}" -maxdepth 1 -name "${ORACLE_SID}_ora_*.aud" -mtime +${RETENTION_DAYS} -type f -delete
done
