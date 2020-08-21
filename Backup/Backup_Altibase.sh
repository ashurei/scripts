#!/bin/bash
#################################################
# Description : Altibase aexport
# Create DATE : 2020.03.12
# Last Update DATE : 2020.08.21 by ashurei
# Copyright (c) Technical Solution, 2020
#################################################

### Set variable
################################
# Need to modify
SERVICE="SKB"
SYS_ID="u1"
SYS_PW="u1"
PORT="20301"
BACKDIR="/ALTIBASE/BACKUP/aexport"
################################
DATE=$(date '+%Y%m%d')
BACKLOG=${BACKDIR}/altibase_aexport_${DATE}.log
TARGET=${BACKDIR}/${DATE}/${SYS_ID}
LOG="${TARGET}/log/aexport_${DATE}.log"
DIV="#############################################################################################"

### Check DB process
IS_EXIST_DB=$(ps aux | grep "altibase -p" | grep -v grep | wc -l)
if [ "${IS_EXIST_DB}" -lt 1 ]
then
	echo "[DB BACKUP] There is not DB process."
	exit 1
fi

### Create directory
if [ ! -d "${TARGET}/dump" ] || [ ! -d "${TARGET}/log" ] || [ ! -d "${TARGET}/conf" ]
then
	mkdir -p "${TARGET}"/dump
	mkdir -p "${TARGET}"/log
	mkdir -p "${TARGET}"/conf
fi

#==============================================================================================================#
### Backup config files
cp "${ALTIBASE_HOME}"/conf/* "${TARGET}"/conf/ > "${LOG}" 2>&1


#==============================================================================================================#
### Delete backup files
{
echo "[${DATE} $(date '+%H:%M:%S')] Delete backup files"
# Delete backup file 1 days+ ago
find ${BACKDIR:?} -mmin +1440 -type d -regextype posix-extended -regex "./[0-9]{8}" -print0 | xargs -0 rm -r
# Delete log file 7 day+ ago
find ${BACKDIR:?}/*_backup_*.log -mtime +6 -type f -delete
} >> "${BACKLOG}" 2>&1


#==============================================================================================================#
### Start of Backup
TIME_S=$(date '+%s')
echo "[${DATE} $(date '+%H:%M:%S')] Backup start." >> "${BACKLOG}"

cd "${TARGET}"/dump >> "${LOG}" 2>&1 || exit
{
echo $DIV
echo "[${DATE} $(date '+%H:%M:%S')] aexport"
"${ALTIBASE_HOME}"/bin/aexport -s localhost -u ${SYS_ID} -p ${SYS_PW} -port ${PORT}
echo $DIV
echo "[${DATE} $(date '+%H:%M:%S')] run_il_out.sh"
sh run_il_out.sh
} >> "${LOG}" 2>&1


#==============================================================================================================#
### tar backup files
cd "${BACKDIR}" >> "${LOG}" 2>&1 || exit
{
echo $DIV
echo "[${DATE} $(date '+%H:%M:%S')] Compress"
tar cvfzp "${BACKDIR}"/"${DATE}"/aexport_"${SERVICE}"_"${SYS_ID}"_"${DATE}".tar.gz "${DATE}"
} >> "${LOG}" 2>&1


#==============================================================================================================#
### End of Backup
TIME_E=$(date '+%s')
BACKUP_TIME=$(( TIME_E - TIME_S ))
echo "[${DATE} $(date '+%H:%M:%S')] Backup end. (${BACKUP_TIME}sec)" >> "${BACKLOG}"
