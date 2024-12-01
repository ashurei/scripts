#!/bin/bash
#####################################################################
# Description : HAProxy external script for MariaDB Galera Cluster
# Create DATE : 2024.11.22
# Last Update DATE : 2024.11.28 by ashurei
# Copyright (c) ashurei@sk.com, 2024
#####################################################################
# Target directory의 파일을 하나의 문자로 합친 뒤 한꺼번에 mariadb-import 수행

# $1 : Directory
DIR="$1"
if [ -z "$DIR" ]
then
  echo "Need target directory."
  exit 1
fi

# $2 : Count of threads
THREAD="$2"
if [ -z "$THREAD" ]
then
  THREAD=2
fi

IMP="/MARIA/mariadb/bin/mariadb-import"
DB="rts"
FILES=$(ls "${DIR}"/*)                          # 절대 경로 표시를 위해 /* 추가
COLLECT_TIME=$(date '+%Y%m%d_%H%M%S')
LOGFILE="imp_$(echo ${DIR} | awk -F'/' '{print $NF}')_${COLLECT_TIME}.log"

TIME_S=$(date '+%s')    # Start time
echo "[$(date '+%Y/%m/%d-%H:%M:%S')] Start. " >> "$LOGFILE"

CONCAT=""
for path in $FILES
do
        FILE=$(echo "$path" | awk -F'/' '{print $NF}')  # "RTS." 제거
        if [ $(echo ${FILE:0:4}) == "RTS." ]
        then
                RENAME=$(echo "$FILE" | sed 's/RTS.//')
                mv "${DIR}/${FILE}" "${DIR}/${RENAME}" 2>/dev/null
                path="${DIR}/${RENAME}"
        fi
        #"${IMP}" --use-threads="${THREAD}" --fields-terminated-by='|' --fields-enclosed-by='`' --lines-terminated-by='\n' "${DB}" "${path}" >> "$LOGFILE"

        CONCAT="${CONCAT} ${path}"
done

#echo $CONCAT
"${IMP}" --use-threads="${THREAD}" --fields-terminated-by='|' --fields-enclosed-by='`' --lines-terminated-by='\n' "${DB}" $CONCAT >> "$LOGFILE"

TIME_E=$(date '+%s')    # End time
ELAPSE_TIME=$(( TIME_E - TIME_S ))
echo "[$(date '+%Y/%m/%d-%H:%M:%S')] End. ELAPSE_TIME: ${ELAPSE_TIME} sec" >> "$LOGFILE"
