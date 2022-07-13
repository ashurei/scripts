#!/bin/bash
########################################################
# Description : Goldilocks Hot Backup
# Create DATE : 2022.07.13
# Last Update DATE : 2022.07.13 by ashurei
# Copyright (c) ashurei@sktelecom.com, 2021
########################################################

SCRIPT_VER="2022.07.14.r08"
TODAY=$(date '+%Y%m%d')
BACKDIR="/goldilocks_data/backup"
TARGETDIR="${BACKDIR}/${TODAY}"
GSQL="gsql sys gliese --dsn GOLDILOCKS --no-prompt"
COMMON="
\set linesize 300
\set heading off
\set time off
\set timing off
"

# ========== Functions ========== #
### Get Goldilocks result with sqlplus
function Cmd_gsql () {
  ${GSQL} "$2" << EOF | head -n -2 | sed '/^$/d'
  ${COMMON}
  $1
EOF
}

### Check gmaster process
function Check_gmaster () {
  local CHK
  CHK=$(ps ax | grep gmaster | grep -v grep)
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
  Cmd_gsql "select cluster_member_name as cmn from dual;"
}

### Check file size
function Check_size () {
  local file FILES SUM SIZE
  # Check filesystem size
  SPACE=$(df -k "${TARGETDIR}" | tail -1 | awk '{print $4}')
  Print_log "${TARGETDIR} available size : $((SPACE/1024/1024))GB"

  FILES=$(Cmd_gsql "select file_name from v\$db_file where file_type in ('Config File', 'Data File','Redo Log File');")

  SUM=0
  for file in $FILES
  do
    SIZE=$(ls -al "$file" | awk '{print $5}')
    SUM=$((SUM + SIZE))
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

### Backup controlfile
function Backup_controlfile () {
  CTRL="${TARGETDIR}/control_backup_${TODAY}.ctl"
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
  FILE=$(Cmd_gsql "select file_name from v\$db_file where file_type='Config File';")

  for file in $FILES
  do
    cp "$file" "${TARGETDIR}"/conf/
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
      cp "$file" "${TARGETDIR}"/db/
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
    cp "$file" "${TARGETDIR}"/wal/
  done
  
  Print_log "Redo log files are backed up."
}

### Backup wal file
function Backup_wal () {
  local FILE
  # Copy location file
  FILE=$(Cmd_gsql "select property_value from v\$property@local where property_name='LOCATION_FILE';")
  cp "$FILE" "${TARGETDIR}"/wal/
  
  if [ "$?" -eq 0 ]
  then
    Print_log "location.ctl is backed up."
  else
    Print_log "[ERROR] location.ctl file backup is failed."
  fi

  # Copy commit.log
  WALDIR=$(dirname "$FILE")
  cp "${WALDIR}"/commit.log "${TARGETDIR}"/wal/
  
  if [ "$?" -eq 0 ]
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
  mkdir -p "${TARGETDIR}"/{conf,db,wal,trc}
fi

Print_log "Backup Start."

# Prepare
Check_gmaster
Check_archive
Check_size
Check_begin

# Backup
Backup_controlfile
Backup_config
Backup_datafile
Backup_redo
Backup_wal

Print_log "Backup End."
