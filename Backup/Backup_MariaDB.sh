#!/bin/bash
#################################################
# Description : MariaDB mysqldump
# Create DATE : 2020.03.11
# Last Update DATE : 2025.01.23 by ashurei
# Copyright (c) Technical Solution, 2025
#################################################

### Set variable
TODAY=$(date '+%Y%m%d')
################################
# Need to modify
BASEDIR="/MARIA/mariadb/bin"
SOCKET="/MARIA/TMP/mariadb.sock"
BACKDIR="/MARIA/BACKUP"
################################
TARGET=${BACKDIR}/${TODAY}

# ========== Functions ========== #
### Get value from Database
function GetValue () {
  VALUE=$(${MARIADB} --socket=${SOCKET} --skip-column-names --silent --execute="$1")
  echo "${VALUE}"
}

### Precheck
function Precheck () {
  local IS_BASE IS_DB IS_CONN
  # Check basedir
  IS_BASE=$(ls "${BASEDIR}/mariadb")
  if [ -z "$IS_BASE" ]
  then
    Print_log "There is no basedir."
    exit 1
  fi

  MARIADB="${BASEDIR}/mariadb"
  if [ -z "$MARIADB" ]; then MARIADB="${BASEDIR}/mysql"; fi
  MARIADUMP="${BASEDIR}/mariadb-dump"
  if [ -z "$MARIADUMP" ]; then MARIADUMP="${BASEDIR}/mysqldump"; fi

  # Check DB process
  IS_DB=$(ps ax | grep -E 'mariadbd-safe|mysqld_safe' | grep -v grep | wc -l)
  if [ "$IS_DB" -lt 1 ]
  then
    Print_log "There is not DB process."
  fi

  IS_CONN=$(GetValue "select 1")
  if [ "${IS_CONN}" != 1 ]
  then
    Print_log "You cannot connect MariaDB server."
    exit 1
  fi

  # Create directory
  if [ ! -d "${TARGET}/dump" ] || [ ! -d "${TARGET}/log" ] || [ ! -d "${TARGET}/conf" ]
  then
    mkdir -p "${TARGET}"/{dump,log,conf}
  fi
}

### Delete old backup
function Delete_backup () {
  Print_log "Delete backup files"
  # Delete backup file 1 days+ ago
  find ${BACKDIR:?} -mtime +1 -type d -regextype posix-extended -regex "${BACKDIR:?}/[0-9]{8}" -print0 | xargs -0 rm -r
  # Delete log file 7 day+ ago
  find ${BACKDIR:?}/mariadb-dump_*.log -mtime +6 -type f -delete
}

### Backup config file
function Backup_config () {
  local CONF
  CONF=$(ps ax | grep -E 'mariadbd-safe|mysqld_safe' | grep -v grep | grep 'defaults-file' | awk -F'defaults-file=' '{print $2}' | awk '{print $1}')
  if [ -z "$CONF" ]
  then
    CONF="/etc/my.cnf"
  fi
  cp "$CONF" "${TARGET}/conf/my.cnf_${TODAY}"
}

### Logging error
function Print_log () {
  local LOG LOGDATE
  LOG="${BACKDIR}/mariadb-dump_${TODAY}.log"

  if [ ! -f "${LOG}" ]
  then
    /bin/touch "${LOG}"
  fi

  LOGDATE="[$(date '+%Y%m%d-%H:%M:%S')]"
  echo "${LOGDATE} $1" >> "${LOG}"
}

# ========== Main ========== #

Precheck
Delete_backup
Backup_config

#==============================================================================================================#
### Start of Backup
TIME_S=$(date '+%s')
Print_log "Backup start."
DATABASE=$(GetValue "show databases")
for db in ${DATABASE}
do
  TIME_1=$(date '+%s')
  OUTPUT="${TARGET}/dump/${db}_${TODAY}.sql"
  LOG="${TARGET}/log/${db}_${TODAY}.log"

  ${MARIADUMP} --socket=${SOCKET} -v --single-transaction --events --routines --triggers "${db}" 2>"${LOG}" > "${OUTPUT}"

  TIME_2=$(date '+%s')
  ELASPED_TIME=$(( TIME_2 - TIME_1 ))

  echo >> "${LOG}"
  echo "Elapse time : ${ELASPED_TIME} sec" >> "${LOG}"
done

#==============================================================================================================#
### Compress backup files
# Do not use absolute path when perform 'tar' for security problem
Print_log "Compress"
cd "${BACKDIR}" || exit
tar cvfzp "${TARGET}/mariadb-dump_${TODAY}".tgz "${TODAY}"/{dump,log,conf}

#==============================================================================================================#
### End of Backup
TIME_E=$(date '+%s')
BACKUP_TIME=$(( TIME_E - TIME_S ))
Print_log "Backup end. (${BACKUP_TIME}sec)"
Print_log ""
