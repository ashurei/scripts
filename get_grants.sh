#!/bin/bash
##############################################################
# Description : [MySQL] Get grants for mysqldump recovery
# Create DATE : 2020.09.03
# Last Update DATE : 2020.08.27 by ashurei
# Copyright (c) Technical Solution, 2020
##############################################################
usage ()
{
        echo "Usage: ./get_grant.sql [-u <db username> -p <password> -o <output file> [-s <socket>] ]"
}

### Read arguments
while [ $# -gt 0 ]
do
        case "$1" in
        -u)     MYSQL_USER=$2
                shift
                shift
                ;;
        -p)     MYSQL_PASSWD=$2
                shift
                shift
                ;;
        -o)     OUTPUT=$2
                shift
                shift
                ;;
        -s)     SOCKET=$2
                shift
                shift
                ;;
        -h|*)   usage
                exit 1
                ;;
        esac
done


### Check necessary arguments
if [[ -z ${MYSQL_USER} || -z ${MYSQL_PASSWD} || -z ${OUTPUT} ]]
then
        usage
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

### Get user, host list
USERS=$(mysql -u "${MYSQL_USER}" -p"${MYSQL_PASSWD}" -N -s -e "select concat('''',user,'''','@','''',host,'''') from user" mysql)


### Create grant command to OUTPUT
for user in ${USERS}
do
  GRANT_SQL="show grants for ${user}"
  mysql -u "${MYSQL_USER}" -p"${MYSQL_PASSWD}" -N -s -e "${GRANT_SQL}" mysql >> "${OUTPUT}"
done


### Add ";"
sed -i 's/$/;/g' "${OUTPUT}"


### Add "flush privileges'
echo "flush privileges;" >> "${OUTPUT}"
