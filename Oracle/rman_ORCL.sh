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
RMANLOG="~/DBA/script/rman/rman_${ORACLE_SID}_${DATE}.log"
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
  configure controlfile autobackup on;
  configure controlfile autobackup format for device type disk to '${BACKDIR}/autobackup_%F.ctl';
  
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
