#!/bin/bash
########################################################
# Description : Goldilocks Hot Backup
# Create DATE : 2022.07.13
# Last Update DATE : 2025.01.22 by ashurei
# Copyright (c) ashurei@sktelecom.com, 2022
########################################################

SCRIPT_VER="2025.01.22.r01"
TODAY=$(date '+%Y%m%d')

#######################################################
# Need to modify
export GOLDILOCKS_HOME="/home/goldUAP/goldilocks_home"
export GOLDILOCKS_DATA="/home/goldUAP/goldilocks_data"
BACKDIR="/goldilocks/backup"
PASSWORD="SKTelecom!2#4"
#######################################################

TARGETDIR="${BACKDIR}/${TODAY}"
COMMON="
\set linesize 300
\set heading off
\set time off
\set timing off
"

# ========== Functions ========== #
### Get Goldilocks result with sqlplus
function Cmd_gsql () {
  local GSQL
  GSQL="${GOLDILOCKS_HOME}/bin/gsql sys ${PASSWORD} --dsn GOLDILOCKS --no-prompt"
  ${GSQL} "$2" << EOF | sed '/^$/d' | grep -v " selected."
${COMMON}
$1
EOF
}

### Check gsql
function Check_gsql () {
  local CHK
  CHK=$(Cmd_gsql "select 1 from dual;" | grep "ERR-")
  # $CHK is not null
  if [ -n "${CHK}" ]
  then
    Print_log "[ERROR] Cannot connect 'gsql'."
    Print_log "${CHK}"
    exit 1
  fi
}

### Check gmaster process
function Check_gmaster () {
  local CHK
  CHK=$(pgrep -U "$(whoami)" gmaster)
  # $CHK is not null
  if [ -z "${CHK}" ]
  then
    Print_log "[ERROR] There is not goldilocks process."
    exit 1
  fi
}

### Check archive log mode
function Check_archive () {
  local CHK
  CHK=$(Cmd_gsql "select archivelog_mode as mode from v\$archivelog;")
  # no archive log mode
  if [ "${CHK}" == "NOARCHIVELOG" ]
  then
    Print_log "[ERROR] Hot backup needs 'ARCHIVELOG' mode."
    exit 1
  fi
}

### Check begin backup
function Check_begin () {
  local CHK
  CHK=$(Cmd_gsql "select count(*) as C from v\$backup where backup_status='ACTIVE';")
  if [ "${CHK}" -gt 0 ]
  then
    Print_log "[ERROR] There is tablespaces with BEGIN backup mode."
    exit 1
  fi
}

### Get cluster_member_name
function Get_cluster_member_name () {
  Cmd_gsql "select cluster_member_name as cmn from dual@g1n1;"
}

### Check file size
function Check_size () {
  local file FILES SUM SIZE number
  
  # Delete past files
  Delete_backup
  
  # Check filesystem size
  SPACE=$(df -k "${TARGETDIR}" | tail -1 | awk '{print $4}')
  Print_log "${TARGETDIR} available size : $((SPACE/1024/1024))GB"

  FILES=$(Cmd_gsql "select file_name from v\$db_file where file_type in ('Config File', 'Data File','Redo Log File');")

  SUM=0
  number='^[0-9]+([.][0-9]+)?$'
  for file in $FILES
  do
    SIZE=$(stat -c%s "$file" 2>&1)
    if [[ "${SIZE}" =~ $number ]]
    then
      SUM=$((SUM + SIZE))
    fi
  done

  Print_log "The size of backup files is $((SUM/1024/1024/1024))GB."

  if [ "$((SUM / 1024))" -gt "${SPACE}" ]
  then
    Print_log "[ERROR] Backup space is not enough."
    exit 1
  fi
}

### Get tablespace names
function Get_tablespace () {
  Cmd_gsql "select tbs_name from v\$tablespace where tbs_attr != 'MEMORY | TEMPORARY | TEMPORARY';"
}

### Get datafile name
function Get_datafile () {
  # If tablespace name is null, exit
  if [ -z "${1}" ]
  then
    Print_log "Tablespace name is not exist."
    exit 1
  fi

  Cmd_gsql "select datafile_name from v\$datafile where tbs_name='$1';"
}

### Delete old backup
function Delete_backup () {
  # Delete old backup
  find ${BACKDIR:?} -mtime +0 -type d -regextype posix-extended -regex "${BACKDIR}/[0-9]{8}" -print0 | xargs -0 rm -r >/dev/null 2>&1
  # Delete old logs
  find ${BACKDIR:?}/Backup_goldilocks_*.log -mtime +7 -type f -delete 2>&1
}

### Backup controlfile
function Backup_controlfile () {
  local CTRL
  CTRL="${TARGETDIR}/conf/control_backup_${TODAY}.ctl"
  Cmd_gsql "alter database backup controlfile to '${CTRL}';" "--silent"

  if [ -f "${CTRL}" ]
  then
    Print_log "Control file is backup to ${CTRL}."
  else
    Print_log "Control file backup is failed."
  fi
}

### Backup config files
function Backup_config () {
  local file FILES
  FILES=$(Cmd_gsql "select file_name from v\$db_file where file_type='Config File' and file_name like '%.conf';")

  for file in $FILES
  do
    if ! cp "$file" "${TARGETDIR}"/conf/ >/dev/null 2>&1
    then
      Print_log "cp $file is failed."
    fi
  done
}

### Backup datafiles
function Backup_datafile () {
  local file FILES
  # If tablespace name is null, exit
  TBS=$(Get_tablespace)
  if [ -z "${TBS}" ]
  then
    Print_log "[ERROR] Tablespace name is not exist."
    exit 1
  fi

  # Get cluster_member_name
  DBNAME=$(Get_cluster_member_name)

  # Copy data files
  for tbs in $TBS
  do
    # Begin backup
    Cmd_gsql "alter tablespace $tbs begin backup at ${DBNAME};" "--silent"
    Print_log "alter tablespace $tbs begin backup at ${DBNAME};"

    # Copy files
    FILES=$(Get_datafile "$tbs")
    for file in $FILES
    do
      if ! cp "$file" "${TARGETDIR}"/db/ >/dev/null 2>&1
      then
        Print_log "cp $file is failed."
      fi
      #echo "$file"
    done

    # End backup
    Cmd_gsql "alter tablespace $tbs end backup at ${DBNAME};" "--silent"
    Print_log "alter tablespace $tbs end backup at ${DBNAME};"
  done
}

### Backup redo log file
function Backup_redo () {
  local file FILES
  FILES=$(Cmd_gsql "select file_name from v\$db_file where file_type='Redo Log File';")

  for file in $FILES
  do
    if ! cp "$file" "${TARGETDIR}"/wal/ >/dev/null 2>&1
    then
      Print_log "cp $file is failed."
    fi
  done

  Print_log "Redo log files are backed up."
}

### Backup wal file
function Backup_wal () {
  local FILE
  # Copy location file
  FILE=$(Cmd_gsql "select property_value from v\$property@local where property_name='LOCATION_FILE';")

  if cp "$FILE" "${TARGETDIR}"/wal/
  then
    Print_log "location.ctl is backed up."
  else
    Print_log "[ERROR] location.ctl file backup is failed."
  fi

  # Copy commit.log
  WALDIR=$(dirname "$FILE")

  if cp "${WALDIR}"/commit.log "${TARGETDIR}"/wal/
  then
    Print_log "commit.log is backed up."
  else
    Print_log "[ERROR] commit.log file backup is failed."
  fi
}

### Logging error
function Print_log () {
  local LOG LOGDATE
  LOG="${BACKDIR}/Backup_goldilocks_${TODAY}.log"

  if [ ! -f "${LOG}" ]
  then
    /bin/touch "${LOG}"
  fi

  LOGDATE="[$(date '+%Y%m%d-%H:%M:%S')]"
  echo "${LOGDATE} $1" >> "${LOG}"
}

# ========== Main ========== #
# Create target directory
if [ ! -d "${TARGETDIR}" ]
then
  if ! mkdir -p "${TARGETDIR}"/{conf,db,wal}
  then
    Print_log "[ERROR] mkdir failed."
    exit 1
  fi
fi

Print_log "Backup Start."

# Prepare
Check_gmaster
Check_gsql
Check_archive
Check_begin
Check_size

# Backup
Backup_controlfile
Backup_config
Backup_datafile
Backup_redo
Backup_wal

Print_log "Backup End."
