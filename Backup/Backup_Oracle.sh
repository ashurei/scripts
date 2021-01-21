#!/bin/bash
#################################################
# Description : Oracle expdp
# Create DATE : 2019.12.11
# Last Update DATE : 2021.01.15 by ashurei
# Copyright (c) Technical Solution, 2020
#################################################

### Set variable
################################
# Need to modify
export ORACLE_SID="APCS01"
export ORACLE_HOME="/oracle/database/product/19"
BACKDIR="/oracle/backup/expdp"
USER="system"
PASSWD="passwd"
################################
DATE=$(date '+%Y%m%d')
BACKLOG=${BACKDIR}/oracle_expdp_${DATE}.log
DIR_DUMP="DIR_DUMP"
DIR_LOG="DIR_LOG"
OUTPUT="expdp_${ORACLE_SID}_${DATE}"

### Check DB process
IS_EXIST_DB=$(ps aux | grep "ora_pmon_${ORACLE_SID}" | grep -v grep | wc -l)
if [ "${IS_EXIST_DB}" -lt 1 ]
then
	echo "[DB BACKUP] There is not DB process."
	exit 1
fi

### Create directorys
if [ ! -d "${BACKDIR}/dump" ] || [ ! -d "${BACKDIR}/log" ] || [ ! -d "${BACKDIR}/conf" ]
then
	mkdir -p "${BACKDIR}/{dump,log,conf}"
fi


#==============================================================================================================#
### Backup config files
### Backup config files
sqlplus / as sysdba << EOF
create pfile='${BACKDIR}/conf/init${ORACLE_SID}.ora_${DATE}' from spfile;
EOF


#==============================================================================================================#
### Delete backup files
{
echo "[${DATE} $(date '+%H:%M:%S')] Delete backup files"
# Delete backup file 1 days+ ago
find ${BACKDIR:?}/dump/*.dmp -mmin +1440 -type f -delete
# Delete log file 7 day+ ago
find ${BACKDIR:?}/*_backup_*.log -mtime +6 -type f -delete
find ${BACKDIR:?}/conf/init${ORACLE_SID}.ora* -mtime +6 -type f -delete
find ${BACKDIR:?}/log/*.log -mtime +6 -type f -delete
} >> "${BACKLOG}" 2>&1


#==============================================================================================================#
### Execute expdp
echo "[${DATE} $(date '+%H:%M:%S')] Backup start." >> "${BACKLOG}"
$ORACLE_HOME/bin/expdp ${USER}/${PASSWD} dumpfile=${DIR_DUMP}:"${OUTPUT}".dmp logfile=${DIR_LOG}:"${OUTPUT}".log job_name="${OUTPUT}" full=y
echo "[${DATE} $(date '+%H:%M:%S')] Backup end." >> "${BACKLOG}"
