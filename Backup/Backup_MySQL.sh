#!/bin/bash
#################################################
# Description : MySQL/MariaDB mysqldump
# Create DATE : 2020.03.11
# Last Update DATE : 2020.04.29 by ashurei
# Copyright (c) Technical Solution, 2020
#################################################

### Set variable
MYSQL_ID="root"
################################
# Need to modify
SERVICE="DNS"
MYSQL_PW="password"
PORT="3307"
SOCKET="/tmp/mysql.sock"
BACKDIR="/MYSQL/BACKUP/mysqldump"
################################
DATE=$(date '+%Y%m%d')
BACKLOG=${BACKDIR}/mysql_mysqldump_${DATE}.log
TARGET=${BACKDIR}/${DATE}
DIV="#############################################################################################"

### Check DB process
IS_EXIST_DB=$(ps aux | grep "mysqld" | grep -v "mysqld_safe" | grep -v grep | wc -l)
if [ "${IS_EXIST_DB}" -lt 1 ]
then
	echo "[DB BACKUP] There is not DB process."
	exit 1
fi

### Create directory
if [ ! -d "${TARGET}/dump" ] || [ ! -d "${TARGET}/log" ] || [ ! -d "${TARGET}/conf" ]
then
	{
	mkdir -p "${TARGET}"/dump
	mkdir -p "${TARGET}"/log
	mkdir -p "${TARGET}"/conf
	} >> "${BACKLOG}" 2>&1
fi


#==============================================================================================================#
### Backup config files
cp /etc/my.cnf "${TARGET}"/conf/my.cnf_"${DATE}" >> "${BACKLOG}" 2>&1


#==============================================================================================================#
### Get mysql directory
# MySQL or MariaDB yum install version
if [ -f "/usr/bin/mysql" ]
then
	MYSQL_DIR="/usr/bin"
# MySQL or MariaDB binary install version
elif [ -f "/usr/local/mysql/bin/mysql" ]
then
	MYSQL_DIR="/usr/local/mysql/bin"
# SKT standard
elif [ -f "/MYSQL/mysql/bin/mysql" ]
then
	MYSQL_DIR="/MYSQL/mysql/bin"
# Find with 'which'
elif [ "$(which mysql 2>dev/null)" ]
then
	MYSQL_DIR=$(which mysql)
else
	echo "[${DATE}] (ERROR) Not setted MySQL execute path." >> "${BACKLOG}"
	exit 1
fi

MYSQL=${MYSQL_DIR}/mysql
MYSQLDUMP=${MYSQL_DIR}/mysqldump


#==============================================================================================================#
### Get value from Database
function getValue()
{
	VALUE=$(${MYSQL} --user="${MYSQL_ID}" --password="${MYSQL_PW}" --port=${PORT} --socket=${SOCKET} \
		--skip-column-names \
		--silent \
		--execute="$1")
	echo "${VALUE}"
}


#==============================================================================================================#
### Get 'log_bin' option
LOG_BIN=$(getValue "show variables like 'log_bin'")
LOG_BIN=$(echo "${LOG_BIN}" | awk '{print $2}')


#==============================================================================================================#
### Get list of databases
DATABASE=$(getValue "show databases")


#==============================================================================================================#
### Set 'MASTER_DATA'
if [ "${LOG_BIN}" = "ON" ]
then
	MASTER="--master-data=2"
fi


#==============================================================================================================#
### Delete backup files
{
echo "[${DATE} $(date '+%H:%M:%S')] Delete backup files"
# Delete backup file 1 days+ ago
find ${BACKDIR:?}/* -mmin +1440 -type d -regextype egrep -regex ".*/[0-9]{8}" -print0 | xargs -0 rm -r
# Delete log file 7 day+ ago
find ${BACKDIR:?}/*_backup_*.log -mtime +6 -type f -delete
} >> "${BACKLOG}" 2>&1


#==============================================================================================================#
### Start of Backup
TIME_S=$(date '+%s')
echo "[${DATE} $(date '+%H:%M:%S')] Backup start." >> "${BACKLOG}"
for db in ${DATABASE}
do
	TIME_1=$(date '+%s')
	OUTPUT="${TARGET}/dump/${db}_${DATE}.sql"
	LOG="${TARGET}/log/${db}_${DATE}.log"
	${MYSQLDUMP} --user=${MYSQL_ID} --password=${MYSQL_PW} -v ${MASTER} --single-transaction "${db}" 2>"${LOG}" > "${OUTPUT}"

	TIME_2=$(date '+%s')
	ELASPED_TIME=$(( TIME_2 - TIME_1 ))

	echo >> "${LOG}"
	echo "Elapse time : ${ELASPED_TIME} sec" >> "${LOG}"
done


#==============================================================================================================#
### tar backup files
cd "${BACKDIR}" >> "${BACKLOG}" 2>&1 || exit
{
echo "[${DATE} $(date '+%H:%M:%S')] Compress"
tar cvfzp "${TARGET}"/mysqldump_"${SERVICE}"_"${DATE}".tar.gz "${DATE}"
} >> "${BACKLOG}" 2>&1


#==============================================================================================================#
### End of Backup
TIME_E=$(date '+%s')
BACKUP_TIME=$(( TIME_E - TIME_S ))
{
echo $DIV
echo "[${DATE} $(date '+%H:%M:%S')] Backup end. (${BACKUP_TIME}sec)"
} >> "${BACKLOG}"
