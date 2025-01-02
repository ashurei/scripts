#!/bin/bash
########################################################
# Description : Management of archive logs for Oracle
# Create DATE : 2021.07.23
# Last Update DATE : 2025.01.02 by ashurei
# Copyright (c) ashurei@sktelecom.com, 2021
########################################################

# This script can only be used on Linux platform.

################################
# Need to modify
RETENTION_DAYS="7"
################################

set -o posix
BINDIR="${HOME}/DBA/script/rman"
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
      echo "There is not ORACLE_HOME."
      exit 1
    fi
  else
    echo "Oracle Database is not exists on this server."
    exit 1
  fi
}


# ========== Main ========== #
### Create log directory
if [ ! -d "${BINDIR}" ]
then
  set -e
  mkdir "${BINDIR}"
  set +e
fi

Get_oracle_env

DATE=$(date '+%Y%m%d')

for ORACLE_SID in ${ORACLE_SIDs}
do
  RMANLOG="${BINDIR}/delete_archive_${ORACLE_SID}_${DATE}.log"
  ### Remove output logs
  find "${BINDIR}" -maxdepth 1 -name "delete_archive_${ORACLE_SID}_[0-9]*.log" -mtime +${RETENTION_DAYS} -type f -delete
  
  ### delete archivelog with rman
  "${ORACLE_HOME}"/bin/rman target / > "${RMANLOG}" << EOF
run {
  crosscheck archivelog all;
  delete force noprompt archivelog until time 'SYSDATE-${RETENTION_DAYS}';
  delete noprompt expired archivelog all;
}
exit;
EOF
done
