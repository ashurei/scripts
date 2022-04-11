#!/bin/bash
########################################################
# Description : Get Data for Oracle license
# Create DATE : 2022.03.17
# Last Update DATE : 2022.04.11 by ashurei
# Copyright (c) ashurei@sktelecom.com, 2022
########################################################

SCRIPT_VER="2022.04.11.r02"

DIR="/backup1/oracle"
#TODAY=$(date '+%Y%m%d')
TODAY="20220409"
TEMPFILE="${DIR}/result.log"
COLLECT_TIME=$(date '+%Y%m%d_%H%M%S')
LOGFILE="${DIR}/convert_${TODAY}.log"
OUTPUT="${DIR}/oracle_license_${TODAY}.out"
recsep="#############################################################################################"

# ========== Functions ========== #
function Set_value () {
  while read -r line
  do
    VARIABLE=$(echo "$line" | cut -d':' -f1)
    VALUE=$(echo "$line" | cut -d':' -f2-)   # 2번째 필드부터 끝까지
    eval "${VARIABLE}"='${VALUE}'            # ${VALUE} 안에 특수기호(space, '(' 등)가 들어있을 때는 ' ' 로 묶어주면 된다.
  done < "$1"
}

function Process_HA () {
  if [[ -z $1 && -z $2  ]]
  then
    echo "[ERROR] Parameter is null."
    return -1
  fi

  FILE1=$(find "${DIR}" -type f -name $1)
  orgHOST=$(echo ${FILE1} | awk -F'/' '{print $NF}' | cut -d'_' -f2)

  # Copy "BASDB01" => "BASDB02" , "basdb52" => "basdb51"
  if [ "${orgHOST}" = "${2}1" ]
  then
    newHOST="${2}2"
  else
    newHOST="${2}1"
  fi

  newFILE="${DIR}/${TODAY}/DCT_${newHOST}_${TODAY}.out"
  cp ${FILE1} ${newFILE}

  # Modify hostname in file
  sed -i 's/HOSTNAME:'"${orgHOST}"'/HOSTNAME:'"${newHOST}"'/' ${newFILE}
  sed -i 's/HOST_NAME:'"${orgHOST}"'/HOST_NAME:'"${newHOST}"'/' ${newFILE}
}


# ========== Main ========== #
{
  cp /dev/null ${OUTPUT}
  echo $recsep
  echo "### COLLECT_TIME : ${COLLECT_TIME}"

  # Copy same file for Active-Standby (BASDB)
  Process_HA "DCT_BASDB0*0409.out" "BASDB0"
  Process_HA "DCT_basdb5*0409.out" "basdb5"

  # Find output files
  FILES=$(find "${DIR}/${TODAY}" -type f -name "*${TODAY}.out")

  # Convert
  for file in $FILES
  do
    echo "#=== $file ===#"
    #ORACLE_USER=$(grep "ORACLE_USER:" "$file" | cut -d':' -f2)
    echo "### os_common ###"

    if grep -A100 -i "##@ OScommon" "$file" | sed '/#####/q' | grep -v '^#' > ${TEMPFILE}
    then
      Set_value ${TEMPFILE}
      OS_COMMON_RESULT=$(printf "%s|" "$HOSTNAME")
      OS_COMMON_RESULT=${OS_COMMON_RESULT}$(printf "%s|" "$OS")
      OS_COMMON_RESULT=${OS_COMMON_RESULT}$(printf "%s|" "$OS_ARCH")
      OS_COMMON_RESULT=${OS_COMMON_RESULT}$(printf "%s|" "$MEMORY_SIZE")
      OS_COMMON_RESULT=${OS_COMMON_RESULT}$(printf "%s|" "$MACHINE_TYPE")
      OS_COMMON_RESULT=${OS_COMMON_RESULT}$(printf "%s|" "$HW_VENDOR")
      OS_COMMON_RESULT=${OS_COMMON_RESULT}$(printf "%s|" "$PROCESSOR_VERSION")
      OS_COMMON_RESULT=${OS_COMMON_RESULT}$(printf "%s|" "$PHYSICAL_CORES_OS")
      OS_COMMON_RESULT=${OS_COMMON_RESULT}$(printf "%s|" "$LOGICAL_CORES_OS")
      OS_COMMON_RESULT=${OS_COMMON_RESULT}$(printf "%s|" "$CPU_CORE_COUNT_OS")
      OS_COMMON_RESULT=${OS_COMMON_RESULT}$(printf "%s|" "$CPU_SOCKET_COUNT_OS")
      OS_COMMON_RESULT=${OS_COMMON_RESULT}$(printf "%s|" "$HYPERTHREADING")
    fi

    #echo "### collect_info ###"
    #grep -A100 -i "### Data Collection Tool with Oracle" "$file" | sed '/#####/q' | grep -v ^# > ${TEMPFILE}
    #Set_value ${TEMPFILE}
    #Connect_mysql "insert into collect_info values ('$HOSTNAME','$ORACLE_USER','$ORACLE_SID','$SCRIPT_VER','$COLLECT_TIME','$ORACLE_HOME');"

    echo "### ora_option_general ###"
    if grep -A100 -i "##@ ORAoption_general" "$file" | sed '/#####/q' | grep -v '^#' > ${TEMPFILE}
    then
      Set_value ${TEMPFILE}
      DB_GENERAL_RESULT=$(printf "%s|" "${HOSTNAME}")
      DB_GENERAL_RESULT=${DB_GENERAL_RESULT}$(printf "%s|" "${INSTANCE_NAME}")
      DB_GENERAL_RESULT=${DB_GENERAL_RESULT}$(printf "%s|" "${DATABASE_NAME}")
      DB_GENERAL_RESULT=${DB_GENERAL_RESULT}$(printf "%s|" "${OPEN_MODE}")
      DB_GENERAL_RESULT=${DB_GENERAL_RESULT}$(printf "%s|" "${DATABASE_ROLE}")
      DB_GENERAL_RESULT=${DB_GENERAL_RESULT}$(printf "%s|" "${CREATED}")
      DB_GENERAL_RESULT=${DB_GENERAL_RESULT}$(printf "%s|" "${DBID}")
      DB_GENERAL_RESULT=${DB_GENERAL_RESULT}$(printf "%s|" "${VERSION}")
      DB_GENERAL_RESULT=${DB_GENERAL_RESULT}$(printf "%s|" "${BANNER}")
      DB_GENERAL_RESULT=${DB_GENERAL_RESULT}$(printf "%s|" "${PHYSICAL_CPUS_DB}")
      DB_GENERAL_RESULT=${DB_GENERAL_RESULT}$(printf "%s|" "${LOGICAL_CPUS_DB}")
      DB_GENERAL_RESULT=${DB_GENERAL_RESULT}$(printf "%s|" "${LAST_DBA_FUS_DBID}")
      DB_GENERAL_RESULT=${DB_GENERAL_RESULT}$(printf "%s|" "${LAST_DBA_FUS_VERSION}")
      DB_GENERAL_RESULT=${DB_GENERAL_RESULT}$(printf "%s|" "${LAST_DBA_FUS_SAMPLE_DATE}")
      DB_GENERAL_RESULT=${DB_GENERAL_RESULT}$(printf "%s|" "${REMARKS}")
      DB_GENERAL_RESULT=${DB_GENERAL_RESULT}$(printf "%s|" "${CONTROL_MANAGEMENT_PACK_ACCESS}")
      DB_GENERAL_RESULT=${DB_GENERAL_RESULT}$(printf "%s|" "${ENABLE_DDL_LOGGING}")
    fi

    echo "### ora_option_ula ###"
    if grep -A100 -i "##@ ORAoption_ULA" "$file" | sed '/#####/q' | grep -v '^#' > ${TEMPFILE}
    then
      Set_value ${TEMPFILE}
      DB_OPTION_RESULT=$(printf "%s|" "${DATABASE_GATEWAY}")
      DB_OPTION_RESULT=${DB_OPTION_RESULT}$(printf "%s|" "${EXADATA}")
      DB_OPTION_RESULT=${DB_OPTION_RESULT}$(printf "%s|" "${GOLDENGATE}")
      DB_OPTION_RESULT=${DB_OPTION_RESULT}$(printf "%s|" "${HW}")
      DB_OPTION_RESULT=${DB_OPTION_RESULT}$(printf "%s|" "${PILLARSTORAGE}")
      DB_OPTION_RESULT=${DB_OPTION_RESULT}$(printf "%s|" "${ADG}")
      DB_OPTION_RESULT=${DB_OPTION_RESULT}$(printf "%s|" "${ADG_RAC}")
      DB_OPTION_RESULT=${DB_OPTION_RESULT}$(printf "%s|" "${ADVANCED_ANALYTICS}")
      DB_OPTION_RESULT=${DB_OPTION_RESULT}$(printf "%s|" "${ADVANCED_COMPRESSION}")
      DB_OPTION_RESULT=${DB_OPTION_RESULT}$(printf "%s|" "${ADVANCED_SECURITY}")
      DB_OPTION_RESULT=${DB_OPTION_RESULT}$(printf "%s|" "${DATABASE_INMEMORY}")
      DB_OPTION_RESULT=${DB_OPTION_RESULT}$(printf "%s|" "${DATABASE_VAULT}")
      DB_OPTION_RESULT=${DB_OPTION_RESULT}$(printf "%s|" "${DIAGNOSTICS_PACK}")
      DB_OPTION_RESULT=${DB_OPTION_RESULT}$(printf "%s|" "${LABEL_SECURITY}")
      DB_OPTION_RESULT=${DB_OPTION_RESULT}$(printf "%s|" "${MULTITENANT}")
      DB_OPTION_RESULT=${DB_OPTION_RESULT}$(printf "%s|" "${OLAP}")
      DB_OPTION_RESULT=${DB_OPTION_RESULT}$(printf "%s|" "${PARTITION}")
      DB_OPTION_RESULT=${DB_OPTION_RESULT}$(printf "%s|" "${RAC_ONENODE}")
      DB_OPTION_RESULT=${DB_OPTION_RESULT}$(printf "%s|" "${RAC}")
      DB_OPTION_RESULT=${DB_OPTION_RESULT}$(printf "%s|" "${ONENODE}")
      DB_OPTION_RESULT=${DB_OPTION_RESULT}$(printf "%s|" "${RAT}")
      DB_OPTION_RESULT=${DB_OPTION_RESULT}$(printf "%s|" "${SPATIAL}")
      DB_OPTION_RESULT=${DB_OPTION_RESULT}$(printf "%s|" "${TUNING}")
    fi

    #echo "### ora_common ###"
    #if grep -A100 -i "##@ ORAcommon" "$file" | sed '/#####/q' | grep -v ^# > ${TEMPFILE}
    #then
    #  Set_value ${TEMPFILE}
    #fi

    printf "%s%s%s\n" "$OS_COMMON_RESULT" "$DB_OPTION_RESULT" "$DB_GENERAL_RESULT" >> ${OUTPUT}
  done

  echo
} >> "${LOGFILE}" 2>&1

# Symbolic link
SYM="${DIR}/oracle_license.out"
ln -sf "${OUTPUT}" "${SYM}"

if [ -f "${TEMPFILE}" ]
then
  /bin/rm ${TEMPFILE}
fi
