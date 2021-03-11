#!/bin/bash
##############################################################
# Description : [MySQL] Get grants for mysqldump recovery
# Create DATE : 2020.08.27
# Last Update DATE : 2020.11.16 by ashurei
# Copyright (c) Technical Solution, 2020
##############################################################

#==============================================================================================================#
### usage
function usage ()
{
    echo "Usage: ./get_grant.sql [-u <db username> -p <password> -o <output file> [-S <socket>] ]"
}

### Get value from Database
function getValue()
{
    VALUE=$(mysql --user="${MYSQL_ID}" --password="${MYSQL_PW}" ${MYSQL_SOCK} \
                  --skip-column-names --silent --execute="$1")
    echo "${VALUE}"
}
#==============================================================================================================#


### Read arguments
while [ $# -gt 0 ]
do
    case "$1" in
    -u) MYSQL_ID=$2
        shift
        shift
        ;;
    -p) MYSQL_PW=$2
        shift
        shift
        ;;
    -o) OUTPUT=$2
        shift
        shift
        ;;
    -S) SOCKET=$2
        shift
        shift
        ;;
    -h|*)  usage
        exit 1
        ;;
    esac
done

### Create socket option
if [ -n "${SOCKET}" ]
then
    MYSQL_SOCK="--socket=${SOCKET}"
fi

### Check necessary arguments
if [[ -z ${MYSQL_ID} || -z ${MYSQL_PW} || -z ${OUTPUT} ]]
then
        usage
        exit 1
fi

### Check connection to mysql server
IS_CONN=$(getValue "select 1")
if [ "${IS_CONN}" != 1 ]
then
        echo "[${DATE} $(date '+%H:%M:%S')] You cannot connect mysql server."
        exit 1
fi

### Initialize OUTPUT file
if [ ! -f "${OUTPUT}" ]
then
    cp /dev/null "${OUTPUT}"
else
    echo "OUTPUT file is exists."
    exit 1
fi

#==============================================================================================================#
### Get user, host list
USERS=$(getValue "select concat('''',user,'''','@','''',host,'''') from mysql.user")


### Create grant command to OUTPUT
for user in ${USERS}
do
    GRANT_SQL="show grants for ${user}"
    getValue "${GRANT_SQL}" >> "${OUTPUT}"
done


### Add ";"
sed -i 's/$/;/g' "${OUTPUT}"


### Add "flush privileges'
echo "flush privileges;" >> "${OUTPUT}"
