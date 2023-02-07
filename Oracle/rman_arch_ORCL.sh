#!/bin/bash
########################################################
# Description : Rman Backup Script
# Create DATE : 2023.02.06
# Last Update DATE : 2023.02.07 by ashurei
# Copyright (c) ashurei@sktelecom.com, 2023
########################################################

###################################################
# Need to modify
export ORACLE_HOME="/oracle/database/product/19"
export ORACLE_SID="ORCL2"
###################################################

export NLS_DATE_FORMAT="YYYY/MM/DD HH24:MI:SS"
DATE=$(date '+%Y%m%d')
RMANLOG="~/DBA/script/rman/rman_arch_${ORACLE_SID}_${DATE}.log"
BACKDIR="/rman/${ORACLE_SID}"

### Create backup directory
if [ ! -d "${BACKDIR}" ]
then
  set -e
  mkdir "${BACKDIR}"
  set +e
fi

"${ORACLE_HOME}"/bin/rman target / > "${RMANLOG}" << EOF
run {
  configure retention policy to recovery window of 3 days;

  crosscheck backup of archivelog all;
  backup tag='${ORACLE_SID}_ARCH' format '${BACKDIR}/ARCH_%d_%U_%T'
  as compressed backupset
  archivelog all delete all input;
}
EOF
