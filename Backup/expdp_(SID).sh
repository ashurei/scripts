#!/bin/bash
#################################################
# Description : Oracle expdp
# Create DATE : 2019.12.11
# Last Update DATE : 2021.11.12 by ashurei
# Copyright (c) ashurei@sk.com, 2021
#################################################

### Set variable
################################
# Need to modify
export ORACLE_SID="UAPDB1"
export ORACLE_HOME="/oracle/database/product/19"
BACKDIR="/oracle/backup/expdp"
USER="system"
PASSWD="SKTelecom!2#4"
################################
DATE=$(date '+%Y%m%d')
BACKLOG=${BACKDIR}/oracle_expdp_${DATE}.log
DIR_DUMP="DIR_DUMP"
DIR_LOG="DIR_LOG"
OUTPUT="expdp_${ORACLE_SID}_${DATE}"

### Check DB process
IS_EXIST_DB=$(ps ax | grep "ora_pmon_${ORACLE_SID}" | grep -v grep | wc -l)
if [ "${IS_EXIST_DB}" -lt 1 ]
then
  echo "[DB BACKUP] There is not DB process."
  exit 1
fi

### Create directorys
if [ ! -d "${BACKDIR}/dump" ] || [ ! -d "${BACKDIR}/log" ] || [ ! -d "${BACKDIR}/conf" ]
then
  mkdir -p "${BACKDIR}"/{dump,log,conf}
fi

#==============================================================================================================#
### Backup config files
GRID_HOME=$(ps ax | grep ocssd.bin | grep -v grep | awk '{print $5}' | awk -F'/bin' '{print $1}')
if [ -n "${GRID_HOME}" ]
then
  NETCONF="${GRID_HOME}/network/admin"
else
  NETCONF="${ORACLE_HOME}/network/admin"
fi

{
  echo "[${DATE} $(date '+%H:%M:%S')] Backup pfile and network config"
  cp "${NETCONF}"/listener.ora "${BACKDIR}"/conf/listener.ora_"${ORACLE_SID}"_"${DATE}"
  cp "${NETCONF}"/sqlnet.ora "${BACKDIR}"/conf/sqlnet.ora_"${ORACLE_SID}"_"${DATE}"
  $ORACLE_HOME/bin/sqlplus -S / as sysdba <<< "create pfile='${BACKDIR}/conf/init${ORACLE_SID}.ora_${DATE}' from spfile;"
  
  ### Delete backup files
  echo "[${DATE} $(date '+%H:%M:%S')] Delete backup files"
  # Delete dump and log file 7 day+ ago
  find ${BACKDIR:?}/dump/expdp_${ORACLE_SID}_*.dmp -mmin +1440 -type f -delete
  find ${BACKDIR:?}/oracle_expdp_*.log -mtime +6 -type f -delete
  find ${BACKDIR:?}/conf/init${ORACLE_SID}.ora* -mtime +6 -type f -delete
  find ${BACKDIR:?}/conf/listener.ora* -mtime +6 -type f -delete
  find ${BACKDIR:?}/conf/sqlnet.ora* -mtime +6 -type f -delete
  find ${BACKDIR:?}/conf/tnsnames.ora* -mtime +6 -type f -delete
  find ${BACKDIR:?}/log/*.log -mtime +6 -type f -delete
} >> "${BACKLOG}" 2>&1

#==============================================================================================================#
### Execute expdp
echo "[${DATE} $(date '+%H:%M:%S')] Backup start." >> "${BACKLOG}"
$ORACLE_HOME/bin/expdp ${USER}/${PASSWD} dumpfile=${DIR_DUMP}:"${OUTPUT}".dmp logfile=${DIR_LOG}:"${OUTPUT}".log job_name="${OUTPUT}" full=y
echo "[${DATE} $(date '+%H:%M:%S')] Backup end." >> "${BACKLOG}"
