#!/bin/bash
########################################################
# Description : Rman Backup Script
# Create DATE : 2023.02.06
# Last Update DATE : 2023.04.12 by ashurei
# Copyright (c) ashurei@sktelecom.com, 2023
########################################################

DATE=$(date '+%Y%m%d')
################################
# Need to modify
export ORACLE_HOME="/oracle/database/product/19"
export ORACLE_SID="RTS2"
LOGDIR="${HOME}/DBA/script/log"
RMANLOG="${LOGDIR}/rman_${ORACLE_SID}_${DATE}.log"
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
find ${LOGDIR:?}/rman_"${ORACLE_SID}"_*.log -mtime +30 -type f -delete 2>&1

### rman backup
"${ORACLE_HOME}"/bin/rman target / > "${RMANLOG}" << EOF
run {
  configure retention policy to redundancy 2;
  configure controlfile autobackup on;
  configure controlfile autobackup format for device type disk to '${BACKDIR}/autobackup_%F.ctl';
  configure snapshot controlfile name to '+ARCH/RTS/CONTROLFILE/snapcf_${ORACLE_SID}.f';

  allocate channel dch1 device type disk format '${BACKDIR}/%d_%U_%T' maxopenfiles 1;
  allocate channel dch2 device type disk format '${BACKDIR}/%d_%U_%T' maxopenfiles 1;
  allocate channel dch3 device type disk format '${BACKDIR}/%d_%U_%T' maxopenfiles 1;
  allocate channel dch4 device type disk format '${BACKDIR}/%d_%U_%T' maxopenfiles 1;

  crosscheck backup;
  delete noprompt expired backup;

  report obsolete;
  delete noprompt obsolete;

  backup tag = '${ORACLE_SID}_DATA'
  as compressed backupset
  incremental level 0
  database
  include current controlfile
  plus archivelog;

  release channel dch1;
  release channel dch2;
  release channel dch3;
  release channel dch4;
}
EOF
