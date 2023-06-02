#!/bin/bash
########################################################
# Description : Rman Archive log Backup Script
# Create DATE : 2023.02.06
# Last Update DATE : 2023.06.02 by ashurei
# Copyright (c) ashurei@sktelecom.com, 2023
########################################################

DATE=$(date '+%Y%m%d_%H')
################################
# Need to modify
export ORACLE_HOME="/oracle/database/product/19"
export ORACLE_SID="ORCL2"
LOGDIR="${HOME}/DBA/script/log"
RMANLOG="${LOGDIR}/rman_arch_${ORACLE_SID}_${DATE}.log"
BACKDIR="/rman/${ORACLE_SID}"
################################

export NLS_DATE_FORMAT="YYYY/MM/DD HH24:MI:SS"

### Create backup directory
if [ ! -d "${LOGDIR}" ]
then
  set -e
  mkdir -p "${LOGDIR}"
  set +e
fi

if [ ! -d "${BACKDIR}" ]
then
  echo "Backup directory is not exists."
fi

### Delete log
find ${LOGDIR:?}/rman_arch_"${ORACLE_SID}"_*.log -mtime +30 -type f -delete 2>&1

### rman backup
"${ORACLE_HOME}"/bin/rman target / > "${RMANLOG}" << EOF
run {
  configure snapshot controlfile name to '+ARCH/RTS/CONTROLFILE/snapcf_${ORACLE_SID}.f';
  crosscheck backup of archivelog all;
  backup tag='${ORACLE_SID}_ARCH' format '${BACKDIR}/ARCH_%d_%U_%T'
  as compressed backupset
  archivelog all delete all input;
}
EOF
