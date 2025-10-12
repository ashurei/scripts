########################################################
# Description : Check replication gap of MariaDB
# Create DATE : 2022
# Last Update DATE : 2025.10.13 by ashurei
# Copyright (c) ashurei@sktelecom.com, 2025
########################################################

# Get the gap of MariaDB
#MARIA="mysql -u root -pimsi00 --socket=/MARIA/data/clustrix/mysql_xpand.sock"
MARIA="/MARIA/mariadb/bin/mariadb -S /MARIA/TMP/mariadb.sock"
CNT=0

while true
do
  GAP=$(${MARIA} -e "show slave status\G" | grep "Seconds_Behind_Master" | awk '{print $2}')
  #GAP=$(${MARIA} -e "show slave status\G" | grep "Relay_Log_Current_Bytes" | awk '{print $2}')
  # First GAP
  if [[ "${CNT}" == 0 && "${GAP}" > 0 ]]
  then
    echo -ne "Start: $(date '+%H:%M:%S')\n"
    if [ "${CNT}" -eq 0 ]
    then
      TIME_S=$(date '+%s')
      ((CNT++))
      sleep 110
      #sleep 23
      continue
    fi
  # CNT++ when GAP touch first time (CNT=2)
  elif [[ "${CNT}" == 1 && "${GAP}" == 0 ]]
  then
    ((CNT++))
  # CNT-- when CNT==2 and GAP not 0 (CNT=1)
  elif [[ "${CNT}" > 1 && "${GAP}" > 0 ]]
  then
    ((CNT--))
  # CNT++ when CNT==3 and GAP ==0
  elif [[ "${CNT}" > 2 && "${GAP}" == 0 ]]
  then
    TIME_E=$(date '+%s')
    break
  fi
  sleep 1.5
done

ELAPSE_TIME=$(( TIME_E - TIME_S ))
echo "Elapse time: ${ELAPSE_TIME}"
