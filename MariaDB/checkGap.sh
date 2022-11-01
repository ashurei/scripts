# Get the gap of MariaDB
MARIA="mysql -u root -pimsi00 --socket=/MARIA/data/clustrix/mysql_xpand.sock"
CNT=0

while true
do
  #GAP=$(${MARIA} -e "show slave status 'slave01'\G" | grep "Seconds_Behind_Master" | awk '{print $2}')
  GAP=$(${MARIA} -e "show slave status\G" | grep "Relay_Log_Current_Bytes" | awk '{print $2}')
  # First GAP
  if [[ "${CNT}" == 0 && "${GAP}" > 0 ]]
  then
    echo -ne "Start: $(date '+%H:%M:%S')\n"
    if [ "${CNT}" -eq 0 ]
    then
      TIME_S=$(date '+%s')
      ((CNT++))
      sleep 110
      continue
    fi
  # GAP to 0
  elif [[ "${CNT}" > 0 && "${GAP}" == 0 ]]
  then
    TIME_E=$(date '+%s')
    break
  fi
  sleep 1
done

ELAPSE_TIME=$(( TIME_E - TIME_S ))
echo "Elapse time: ${ELAPSE_TIME}"
