#!/bin/bash
########################################################
# Description : Put Data for Oracle license
# Create DATE : 2021.08.19
# Last Update DATE : 2023.02.17 by ashurei
# Copyright (c) ashurei@sktelecom.com, 2022
########################################################

SCRIPT_VER="2023.02.17.r03"

DIR="$1"
if [ -z "$DIR" ]
then
  echo "Insert directory name."
  exit 1
fi

TEMPFILE="temp.out"
COLLECT_TIME=$(date '+%Y%m%d_%H%M%S')
LOGFILE="put_${COLLECT_TIME}.log"
recsep="#############################################################################################"

# ========== Functions ========== #
function Set_value () {
  while read -r line
  do
    VARIABLE=$(echo "$line" | cut -d':' -f1)
    VALUE=$(echo "$line" | cut -d':' -f2)
    eval "${VARIABLE}"='${VALUE}'       # ${VALUE} 안에 특수기호(space, '(' 등)가 들어있을 때는 ' ' 로 묶어주면 된다.
  done < "$1"
}

function Connect_mariadb () {
  local MARIA DB
  DB="dct_oracle"
  MARIA="/MARIA/mariadb/bin/mariadb"
  "${MARIA}" -u dct -pdct --socket '/MARIA/TMP/mariadb.sock' ${DB} -s -N -e "$1"
}

# ========== Main ========== #
{
  FILES=$(ls "${DIR}"/*.out)
  echo $recsep
  echo "### COLLECT_TIME : ${COLLECT_TIME}"

  for file in $FILES
  do
    echo "#======== $file ========#"
    /usr/bin/dos2unix "$file" >/dev/null 2>&1  # Convert unix mode
    # Modify fault
    ORACLE_USER=$(grep "ORACLE_USER:" "$file" | cut -d':' -f2)

    echo "### os_common ###"
    grep -A100 -i "##@ OScommon" "$file" | sed '/#####/q' | grep -v '^#' > ${TEMPFILE}
    if [ -s ${TEMPFILE} ]
    then
      Set_value ${TEMPFILE}

      # If $UPTIME is not only number, UPTIME=-1
      if ! [[ "$UPTIME" =~ ^[0-9]+$ ]]
      then
        UPTIME=-1
      fi
	  
      if [ "${HYPERTHREADING}" == "ON" ]
      then
        HYPERTHREADING=1
      else
        HYPERTHREADING=0
      fi
	  
	  # 16384 Megabytes ==> 16384*1024
	  if [[ "${MEMORY_SIZE}" == *" "* ]]
	  then
	    MEMORY_SIZE=$(echo ${MEMORY_SIZE} | cut -d' ' -f1)
		MEMORY_SIZE=$((MEMORY_SIZE*1024))
	  fi

      Connect_mariadb "insert into os_common values (
        '$HOSTNAME'
       ,'$OS'
       ,'$OS_ARCH'
       ,'$MEMORY_SIZE'
       ,'$MACHINE_TYPE'
       ,'$HW_VENDOR'
       ,'$PROCESSOR_VERSION'
       ,'$PHYSICAL_CORES_OS'
       ,'$LOGICAL_CORES_OS'
       ,'$CPU_CORE_COUNT_OS'
       ,'$CPU_SOCKET_COUNT_OS'
       ,'$HYPERTHREADING'
       ,'$SELINUX'
       ,'$UPTIME');"
    fi
    
    echo "### collect_info ###"
    grep -A100 -i "### Data Collection Tool with Oracle" "$file" | sed '/#####/q' | grep -v '^#' > ${TEMPFILE}
	if [ -s ${TEMPFILE} ]
    then
      Set_value ${TEMPFILE}
      Connect_mariadb "insert into collect_info values ('$HOSTNAME','$ORACLE_USER','$ORACLE_SID','$SCRIPT_VER','$COLLECT_TIME','$ORACLE_HOME');"
    fi

    echo "### ora_option_general ###"
    grep -A100 -i "##@ ORAoption_general" "$file" | sed '/#####/q' | grep -v '^#' | grep -Ev 'DBA_FEATURE_USAGE_STATISTICS|ERROR|ORA-01219|\*' > ${TEMPFILE}
    if [ -s ${TEMPFILE} ]
    then
      Set_value ${TEMPFILE}
      
      if [[ -z "${PHYSICAL_CPUS_DB}" || "${PHYSICAL_CPUS_DB}" == "NONE" ]]
      then
        PHYSICAL_CPUS_DB=0
      fi

      if [[ -z "${LOGICAL_CPUS_DB}" || "${LOGICAL_CPUS_DB}" == "NONE" ]]
      then
        LOGICAL_CPUS_DB=0
      fi
	  
      Connect_mariadb "insert into ora_option_general values (
        '$HOSTNAME'
       ,'$ORACLE_USER'
       ,'$ORACLE_SID'
       ,'$INSTANCE_NAME'
       ,'$DATABASE_NAME'
       ,'$OPEN_MODE'
       ,'$DATABASE_ROLE'
       ,'$CREATED'
       ,'$DBID'
       ,'$VERSION'
       ,'$BANNER'
       ,'$PHYSICAL_CPUS_DB'
       ,'$LOGICAL_CPUS_DB'
       ,'$LAST_DBA_FUS_DBID'
       ,'$LAST_DBA_FUS_VERSION'
       ,'$LAST_DBA_FUS_SAMPLE_DATE'
       ,'$REMARK'
       ,'$CONTROL_MANAGEMENT_PACK_ACCESS'
       ,'$ENABLE_DDL_LOGGING');"
    fi

    echo "### ora_option_ula ###"
    grep -A100 -i "##@ ORAoption_ULA" "$file" | sed '/#####/q' | grep -v '^#' > ${TEMPFILE}
    if [ -s ${TEMPFILE} ]
    then
      Set_value ${TEMPFILE}
      Connect_mariadb "insert into ora_option_ula values (
       '$HOSTNAME'
      ,'$ORACLE_USER'
      ,'$ORACLE_SID'
      ,'$DATABASE_GATEWAY'
      ,'$EXADATA'
      ,'$GOLDENGATE'
      ,'$HW'
      ,'$PILLARSTORAGE'
      ,'$ADG'
      ,'$ADG_RAC'
      ,'$ADVANCED_ANALYTICS'
      ,'$ADVANCED_COMPRESSION'
      ,'$ADVANCED_SECURITY'
      ,'$DATABASE_INMEMORY'
      ,'$DATABASE_VAULT'
      ,'$DIAGNOSTICS_PACK'
      ,'$LABEL_SECURITY'
      ,'$MULTITENANT'
      ,'$OLAP'
      ,'$PARTITION'
      ,'$RAC_ONENODE'
      ,'$RAC'
      ,'$ONENODE'
      ,'$RAT'
      ,'$SPATIAL'
      ,'$TUNING');"
    fi

    echo "### ora_common ###"
    grep -A100 -i "##@ ORAcommon" "$file" | sed '/#####/q' | grep -v '^#' | grep -Eiv 'from|ERROR|ORA-|^$|^ |\*' > ${TEMPFILE}
    if [ -s ${TEMPFILE} ]
    then
      Set_value ${TEMPFILE}
	  
      if [ "${RAC}" == "Y" ]
      then
        RAC=1
      else
        RAC=0
      fi
	  
      if [ "${OSWATCHER}" == "Y" ]
      then
        OSWATCHER=1
      else
        OSWATCHER=0
      fi
	  
	  if [ -z "${ACTIVE_SESSION_COUNT}" ]
      then
        ACTIVE_SESSION_COUNT=0
      fi

      if [ -z "${HARD_PARSE_COUNT}" ]
      then
        HARD_PARSE_COUNT=0
      fi
	  
      if [ -z "${ARCHIVELOG_1DAY_MBYTES}" ]
      then
        ARCHIVELOG_1DAY_MBYTES=0
      fi
      
      Connect_mariadb "insert into ora_common values (
        '$HOSTNAME'
       ,'$ORACLE_USER'
       ,'$ORACLE_SID'
       ,'$VERSION'
       ,'$COLLECTION_DAY'
       ,'$INSTANCE_NAME'
       ,'$INSTANCE_NUMBER'
       ,'$RAC'
       ,'$DB_CREATED_TIME'
       ,'$INSTANCE_STARTUP_TIME'
       ,'$INSTANCE_STARTUP_DAYS'
       ,'$INSTANCE_ROLE'
       ,'$DBNAME'
       ,'$CONTROLFILE_SEQ'
       ,'$LOG_MODE'
       ,'$OPEN_MODE'
       ,'$CONTROLFILE_COUNT'
       ,'$LOGFILE_COUNT'
       ,'$MIN_LOG_MEMBER_COUNT'
       ,'$ACTIVE_SESSION_COUNT'
       ,'$HARD_PARSE_COUNT'
       ,'$LOG_ARCHIVE_DEST'
       ,'$LOG_ARCHIVE_DEST_1'
       ,'$ARCHIVELOG_1DAY_MBYTES'
       ,'$OSWATCHER'
       ,'$AUDIT_FILE_COUNT'
       ,'$MAXIMUM_SCN'
       ,'$CURRENT_SCN'
       ,'$HEADROOM'
       ,'$ASM');"
    fi

    echo "### crs_common ###"
    MAJOR_VERSION=$(echo "$VERSION" | cut -d'.' -f1)
    if [ "${MAJOR_VERSION}" -ge 11 ]
    then
      grep -A100 -i "##@ CRScommon" "$file" | sed '/#####/q' | grep -v '^#' \
	   | grep -Ei 'misscount|disktimeout|autostart|client_log_count|chm|cluster_version|cluster_status|cluster_name|cluster_nodename|cluster_nodes' \
	   > ${TEMPFILE}
      if [ -s ${TEMPFILE} ]
      then
        Set_value ${TEMPFILE}

        if [ -z "${MISSCOUNT}" ]
        then
          MISSCOUNT=-1
        fi

        if [ -z "${DISKTIMEOUT}" ]
        then
          DISKTIMEOUT=-1
        fi

        Connect_mariadb "insert into crs_common values (
          '$HOSTNAME'
         ,'$ORACLE_USER'
         ,'$ORACLE_SID'
         ,'$MISSCOUNT'
         ,'$DISKTIMEOUT'
         ,'$AUTOSTART'
         ,'$CLIENT_LOG_COUNT'
         ,'$CHM'
         ,'$CLUSTER_VERSION'
         ,'$CLUSTER_STATUS'
         ,'$CLUSTER_NAME'
         ,'$CLUSTER_NODENAME'
         ,'$CLUSTER_NODES');"
      fi
    fi
	
    echo "### asm_lsdg ###"
    if [ "${MAJOR_VERSION}" -ge 11 ]
    then
      grep -A100 -i "##@ ASMlsdg" "$file" | sed '/#####/q' | grep -v '^#' \
           | grep "MOUNTED" | awk '{print $(NF),$(NF-3),$(NF-6)}' \
           > ${TEMPFILE}
      if [ -s ${TEMPFILE} ]
      then
        while read LINE
        do
          DG_NAME=$(echo $LINE | cut -d' ' -f1)
          DG_USABLE=$(echo $LINE | cut -d' ' -f2)
          DG_TOTAL=$(echo $LINE | cut -d' ' -f3)
          Connect_mariadb "insert into asm_lsdg values (
            '$HOSTNAME'
           ,'$DG_NAME'
           ,'$DG_USABLE'
           ,'$DG_TOTAL'
          );"
        done < ${TEMPFILE}
      fi
    fi
  done

  echo
} >> "${LOGFILE}" 2>&1

if [ -f "${TEMPFILE}" ]
then
  /bin/rm ${TEMPFILE}
fi
