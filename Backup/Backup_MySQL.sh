#!/bin/bash
#################################################
# Description : MySQL/MariaDB mysqldump
# Create DATE : 2020.03.11
# Last Update DATE : 2020.08.27 by ashurei
# Copyright (c) Technical Solution, 2020
#################################################

### Set variable
MYSQL_ID="root"
################################
# Need to modify
SERVICE="test"
MYSQL_PW="imsi00"
SOCKET="/tmp/mysql-test.sock"
BACKDIR="/home/mysql/mysqldump"
################################
DATE=$(date '+%Y%m%d')
BACKLOG=${BACKDIR}/mysql_mysqldump_${DATE}.log
TARGET=${BACKDIR}/${DATE}
DIV="#############################################################################################"


#==============================================================================================================#
### Get mysql path
# SKT standard
if [ -f "/MYSQL/mysql/bin/mysql" ]
then
        MYSQL_DIR="/MYSQL/mysql/bin"
# MySQL or MariaDB rpm client
elif [ -f "/usr/bin/mysql" ]
then
        MYSQL_DIR="/usr/bin"
# MySQL or MariaDB binary install version
elif [ -f "/usr/local/mysql/bin/mysql" ]
then
        MYSQL_DIR="/usr/local/mysql/bin"
# Find with 'which'
elif [ "$(which mysql 2>/dev/null)" ]
then
        MYSQL_DIR=$(which mysql)
else
        echo "[${DATE}] (ERROR) Not setted MySQL execute path." | tee -a "${BACKLOG}"
        exit 1
fi

MYSQL=${MYSQL_DIR}/mysql
MYSQLDUMP=${MYSQL_DIR}/mysqldump


#==============================================================================================================#
### Get value from Database
function getValue()
{
        VALUE=$(${MYSQL} --user="${MYSQL_ID}" --password="${MYSQL_PW}" --socket=${SOCKET} \
                        --skip-column-names --silent --execute="$1")
        echo "${VALUE}"
}


#==============================================================================================================#
### Prepare Backup process
# Check DB process
IS_EXIST_DB=$(ps aux | grep "mysqld" | grep -v "mysqld_safe" | grep -v grep | wc -l)
if [ "${IS_EXIST_DB}" -lt 1 ]
then
        echo "[${DATE} $(date '+%H:%M:%S')] There is not DB process." | tee -a "${BACKLOG}"
        exit 1
fi

# Check connection to mysql server
IS_CONN=$(getValue "select 1")
if [ "${IS_CONN}" != 1 ]
then
        echo "[${DATE} $(date '+%H:%M:%S')] You cannot connect mysql server." | tee -a "${BACKLOG}"
        exit 1
fi

# Check exist backup
if [ -d "${TARGET}" ]
then
        echo "[${DATE} $(date '+%H:%M:%S')] There is already DB Backup today." | tee -a "${BACKLOG}"
        exit 1
fi

# Create directory
if [ ! -d "${TARGET}/dump" ] || [ ! -d "${TARGET}/log" ] || [ ! -d "${TARGET}/conf" ]
then
        mkdir -p "${TARGET}"/{dump,log,conf}
fi


#==============================================================================================================#
### Backup config files
cp /etc/my.cnf "${TARGET}"/conf/my.cnf_"${DATE}" >> "${BACKLOG}" 2>&1


#==============================================================================================================#
### Get list of databases
DATABASE=$(getValue "show databases")


#==============================================================================================================#
### Delete backup files
{
echo "[${DATE} $(date '+%H:%M:%S')] Delete backup files"
# Delete backup file 1 days+ ago
find ${BACKDIR:?} -mmin +1440 -type d -regextype posix-extended -regex "${BACKDIR:?}/[0-9]{8}" -print0 | xargs -0 rm -r
# Delete log file 7 day+ ago
find ${BACKDIR:?}/mysql_mysqldump_*.log -mtime +6 -type f -delete
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
        ${MYSQLDUMP} --user=${MYSQL_ID} --password=${MYSQL_PW} --socket=${SOCKET} -v \
                        --single-transaction --events --routines --triggers "${db}" 2>"${LOG}" > "${OUTPUT}"

        TIME_2=$(date '+%s')
        ELASPED_TIME=$(( TIME_2 - TIME_1 ))

        echo >> "${LOG}"
        echo "Elapse time : ${ELASPED_TIME} sec" >> "${LOG}"
done


#==============================================================================================================#
### tar backup files
# Do not use absolute path when perform 'tar' for security problem
cd "${BACKDIR}" >> "${BACKLOG}" 2>&1 || exit
{
echo "[${DATE} $(date '+%H:%M:%S')] Compress"
tar cvfzp "${TARGET}"/mysqldump_"${SERVICE}"_"${DATE}".tar.gz "${DATE}"/{dump,log,conf}
} >> "${BACKLOG}" 2>&1


#==============================================================================================================#
### End of Backup
TIME_E=$(date '+%s')
BACKUP_TIME=$(( TIME_E - TIME_S ))
{
echo $DIV
echo "[${DATE} $(date '+%H:%M:%S')] Backup end. (${BACKUP_TIME}sec)"
} >> "${BACKLOG}"
