#!/bin/bash
########################################################
# Description : Management of Database logs for Oracle
# Create DATE : 2021.07.19
# Last Update DATE : 2024.12.26 by ashurei
# Copyright (c) ashurei@sktelecom.com, 2021
########################################################

# This script can only be used on Linux platform.

################################
# Need to modify
DIAG_DEST="/oracle/database"                # diagnostic_dest
RETENTION_DAYS="30"
################################

set -o posix
HOSTNAME=$(hostname)
WHOAMI=$(whoami)
source ~/.bash_profile

# ========== Functions ========== #
### Get Oracle environment variable
function Get_oracle_env() {
  local thisUSER_LENGTH thisUSER
  # If user length is greater than 8, change '+' (ex. oraSPAMDB => oraSPAM+)
  thisUSER_LENGTH="${#WHOAMI}"
  thisUSER="${WHOAMI}"
  if [ "${thisUSER_LENGTH}" -gt 8 ]
  then
    thisUSER="${thisUSER:0:7}+"
  fi

  # If there is one more ora_pmon process, get only one because this script is for license check.
  ORACLE_USER=$(ps aux | grep ora_pmon | grep -w "^${thisUSER}" | grep -v grep | head -1 | awk '{print $1}')
  ORACLE_SIDs=$(ps aux | grep ora_pmon | grep -w "^${thisUSER}" | grep -v grep | awk '{print $NF}' | cut -d'_' -f3-)

  # If $ORACLE_USER is exist
  if [ -n "${ORACLE_USER}" ]
  then
    ORACLE_HOME=$(env | grep ^ORACLE_HOME | cut -d'=' -f2)
    # If $ORACLE_HOME is not directory or null
    if [[ ! -d "${ORACLE_HOME}" || -z "${ORACLE_HOME}" ]]
    then
      Print_log "There is not ORACLE_HOME."
      exit 1
    fi
  else
    Print_log "Oracle Database is not exists on this server."
    exit 1
  fi
}

### Logging error
function Print_log() {
  local LOG LOGDATE COLLECT_YEAR
  COLLECT_YEAR=$(date '+%Y')
  LOG="${BINDIR}/rman_${HOSTNAME}_${COLLECT_YEAR}.log"
  LOGDATE="[$(date '+%Y%m%d-%H:%M:%S')]"
  echo "${LOGDATE} $1" >> "${LOG}"
}


# ========== Main ========== #
Get_oracle_env

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
for ORACLE_SID in ${ORACLE_SIDs}
do
  GRID_USER=$(ps aux | grep ocssd.bin | grep -v grep | awk '{print $1}')
  # If $GRID_USER is exist
  if [ -n "${GRID_USER}" ]
  then
    DATABASE_NAME="${ORACLE_SID:0:-1}"
  else
    DATABASE_NAME="${ORACLE_SID}"
  fi

  # Remove rdbms trace
  DATABASE_NAME_LOWER=$(echo "${DATABASE_NAME}" | tr '[:upper:]' '[:lower:]')
  TRACE="${DIAG_DEST}/diag/rdbms/${DATABASE_NAME_LOWER}/${ORACLE_SID}/trace"
  find "${TRACE}" -maxdepth 1 -name "*[0-9].tr[c,m]" -mtime +${RETENTION_DAYS} -type f -delete

  # Rotate alert log
  cp ${TRACE}/alert_${ORACLE_SID}.log ${TRACE}/alert_${ORACLE_SID}.log.$(date '+%Y%m%d')
  cp /dev/null ${TRACE}/alert_${ORACLE_SID}.log

  # Remove audit file
  AUDIT="${DIAG_DEST}/admin/${DATABASE_NAME}/adump"
  find "${AUDIT}" -maxdepth 1 -name "${ORACLE_SID}_ora_*.aud" -mtime +${RETENTION_DAYS} -type f -delete
done
