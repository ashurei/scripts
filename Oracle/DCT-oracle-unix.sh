#!/bin/ksh
########################################################
# Description : Data Collection Tool with Oracle
# Create DATE : 2021.08.09
# Last Update DATE : 2021.08.26 by ashurei
# Copyright (c) ashurei@sktelecom.com, 2021
########################################################

# This script was created for UNIX environment.
# This script was created to be run by the Oracle user. 

BINDIR="/tmp/DCT-oracle"
SCRIPT_VER="2021.08.26.r01"

# Get environment from Oracle user for crontab.
#source ~/.profile

LANG=C
export LANG
COLLECT_DATE=`date '+%Y%m%d'`
COLLECT_TIME=`date '+%Y%m%d_%H%M%S'`
HOSTNAME=`hostname`
WHOAMI=`id | awk '{print $1}' | cut -d"(" -f2 | sed 's/)//'`
RESULT="${BINDIR}/result.log"
recsep="#############################################################################################"
COMMON_VAL="set line 500 pagesize 0 feedback off verify off heading off echo off timing off"
COLLECT_VAL="set line 200 pages 10000 feedback off verify off echo off"

OS_NAME=`uname`
if [ "${OS_NAME}" = "SunOS" ]
then
  PATH=/usr/xpg4/bin:${PATH}
  export PATH
fi

# ========== Functions ========== #
### Get Oracle environment variable
Get_oracle_env () {
  #local thisUSER_LENGTH thisUSER
  # If user length is greater than 8, change '+' (ex. oraSPAMDB => oraSPAM+)
  #thisUSER_LENGTH="${#WHOAMI}"
  #thisUSER="${WHOAMI}"
  #if [ "${thisUSER_LENGTH}" -gt 8 ]
  #then
  #  thisUSER="${thisUSER:0:7}+"
  #fi

  # If there is one more ora_pmon process, get only one because this script is for license check.
  ORACLE_USER=`ps -ef | grep ora_pmon | sed 's/^ *//' | grep -w "^${WHOAMI}" | grep -v grep | head -1 | awk '{print $1}'`
  ORACLE_SIDs=`ps -ef | grep ora_pmon | sed 's/^ *//' | grep -w "^${WHOAMI}" | grep -v grep | awk '{print $NF}' | cut -d"_" -f3`

  # If $ORACLE_USER is exist
  if [ -n "${ORACLE_USER}" ]
  then
    ORACLE_HOME=`env | grep ORACLE_HOME | cut -d"=" -f2`
	# If $ORACLE_HOME is not directory or null
    if [ ! -d "${ORACLE_HOME}" ] || [ -z "${ORACLE_HOME}" ]
    then
      Print_log "There is not ORACLE_HOME."
      exit 1
    fi
  else
    Print_log "Oracle Database is not exists on this server."
    exit 1
  fi
  
  # Check CRS environment
  GRID_USER=`ps -ef | grep ocssd.bin | grep -v grep | awk '{print $1}'`
  # If $GRID_USER is exist
  if [ -n "${GRID_USER}" ]
  then
    # If user length is equal 8, remove '+' (ex. gridSPA+ => gridSPA)
    if [ "${#GRID_USER}" -eq 8 ]
    then
      GRID_USER="${GRID_USER:0:-1}"
    fi
    GRID_HOME=`ps -ef | grep crsd.bin | grep -v grep | awk -F"/bin/crsd.bin" '{print $1}' | grep -v awk | awk '{print $NF}'`
    CRSCTL="${GRID_HOME}/bin/crsctl"
    SRVCTL="${GRID_HOME}/bin/srvctl"
  fi
  
  # Check ASM environment
  isASM=`ps -ef | grep -v grep | grep -c asm_pmon`
}

### Create output file
Create_output () {
  #local DEL_LOG DEL_OUT
  # Delete log files 390 days+ ago
  #DEL_LOG=`find ${BINDIR:?}/DCT_"${HOSTNAME}"_*.log -mtime +390 -type f -exec rm -f {}; 2>&1`
  #if [ -n "${DEL_LOG}" ]   # If $DEL_LOG is exists write to Print_log.
  #then
  #  Print_log "${DEL_LOG}"
  #fi

  # Delete output files 14 days+ ago
  #DEL_OUT=`find ${BINDIR:?}/DCT_"${HOSTNAME}"_*.out -mtime +14 -type f -exec rm -f {}; 2>&1`
  #if [ -n "${DEL_OUT}" ]   # If $DEL_OUT is exists write to Print_log.
  #then
  #  Print_log "${DEL_OUT}"
  #fi

  # OUTPUT file name
  OUTPUT="${BINDIR}/DCT_${HOSTNAME}_${ORACLE_SID}_${COLLECT_DATE}.out"
  { # Insert to output file
    echo "### Data Collection Tool with Oracle"
    echo "ORACLE_USER:${WHOAMI}"
    echo "SCRIPT_VER:${SCRIPT_VER}"
    echo "COLLECT_TIME:${COLLECT_TIME}"
    echo "ORACLE_SID:${ORACLE_SID}"
    echo "ORACLE_HOME:${ORACLE_HOME}"
  } > "${OUTPUT}" 2>&1
}

### OS Check
OScommon () {
  typeset OS MEMORY_SIZE CPU_MODEL CPU_SOCKET_COUNT CPU_CORE_COUNT CPU_COUNT
  typeset CPU_SIBLINGS HYPERTHREADING MACHINE_TYPE UPTIME
  OS=`uname -a`
  #OS_ARCH=`uname -i`
  #MEMORY_SIZE=$(grep MemTotal /proc/meminfo | awk '{printf "%.2f", $2/1024/1024}')
  
  # CPU
  if [ "$OS_NAME" = "HP-UX" ]
  then
    CPU_MODEL=`/usr/bin/model`
	OS_VERSION=`uname -a | awk -F"B." '{print $2}' | awk '{print $1}'`
    CPU_COUNT=`/usr/sbin/ioscan -fknC processor | grep processor | wc -l`
    
	# Check Hyperthreading (kctune lcpu_attr)
	HYPERTHREADING=0
	if [ "`/usr/sbin/kctune | grep lcpu_attr |awk '{print $2}'`" -eq "1" ]
    then
  	  HYPERTHREADING=1
    fi

    if /usr/bin/test -x /usr/contrib/bin/machinfo
    then
	  CPU_SOCKET_COUNT=`/usr/contrib/bin/machinfo | grep '[0-9] socket' | awk '{print $1}' | sed 's/ //g'`
      CPU_CORE_COUNT=`/usr/contrib/bin/machinfo | grep '[0-9] per socket' | tail -1 | cut -d"(" -f2 | awk '{print $1}' | sed 's/ //g'`
	  
      # If $CPU_PER_SOCKET is not exists, per socket is 1.
      if [ -z "${CPU_CORE_COUNT}" ]
      then
        CPU_CORE_COUNT=1
      fi
    fi
  elif [ "$OS_NAME" = "SunOS" ]
  then
    CPU_MODEL=`/usr/sbin/psrinfo -pv | grep -v "physical processor" | awk '{print $1}' | sort -u`
    OS_VERSION=`uname -r | cut -d"." -f2`
    if [ "$OS_VERSION" -gt 9 ]
    then
      CPU_SOCKET_COUNT=`/usr/sbin/psrinfo -p`
	else
	  CPU_SOCKET_COUNT=1
    fi
	CPU_COUNT=`/usr/bin/kstat cpu_info | grep core_id | uniq | wc -l | sed 's/ //g'`
	CPU_CORE_COUNT=`expr $CPU_COUNT \/ $CPU_SOCKET_COUNT`
  fi
  
  # Memory
  if [ "$OS_NAME" = "HP-UX" ]
  then
    MEMORY_SIZE=`/usr/contrib/bin/machinfo | grep ^Memory | awk -F":|=" '{print $2}' | awk '{print $1/1024}'`
  elif [ "$OS_NAME" = "SunOS" ]
  then
    MEMORY_SIZE=`/usr/sbin/prtconf 2>/dev/null | grep "Memory size" | awk '{print $3/1024}'`
  fi
  
  # Uptime (days)
  UPTIME=`uptime | awk '{print $3}'`

  { # Insert to output file
    echo $recsep
    echo "##@ OScommon"
    echo "HOSTNAME:${HOSTNAME}"
    echo "OS:${OS}"
    #echo "OS_ARCH:${OS_ARCH}"
    echo "MEMORY_SIZE:${MEMORY_SIZE}"
    echo "CPU_MODEL:${CPU_MODEL}"
    echo "MACHINE_TYPE:${MACHINE_TYPE}"
    echo "CPU_SOCKET_COUNT:${CPU_SOCKET_COUNT}"
    echo "CPU_CORE_COUNT:${CPU_CORE_COUNT}"
    echo "CPU_COUNT:${CPU_COUNT}"
    echo "HYPERTHREADING:${HYPERTHREADING}"
    #echo "SELINUX:${SELINUX}"
    echo "UPTIME:${UPTIME}"
  } >> "${OUTPUT}" 2>&1
}

### df -h
OSdf () {
  { # Insert to output file
    echo $recsep
    echo "##@ OSdf"
    if [ "${OS_NAME}" = "HP-UX" ]
    then
      /usr/bin/bdf
    else
      /bin/df -h
	fi
  } >> "${OUTPUT}" 2>&1
}

### /etc/hosts
OShosts () {
  { # Insert to output file
    echo $recsep
    echo "##@ OShosts"
    echo "# /etc/hosts"
    /bin/cat /etc/hosts
  } >> "${OUTPUT}" 2>&1
}

### Get Oracle result with sqlplus
Cmd_sqlplus () {
  sqlplus -silent / as sysdba 2>/dev/null << EOF
$1
$2
exit
EOF
}

### Check sqlplus
Check_sqlplus () {
  typeset SQLcheck_sqlplus chkSQLPLUS
  SQLcheck_sqlplus=`Cmd_sqlplus "${COMMON_VAL}" "select 1 from dual;"`
  chkSQLPLUS=`echo "${SQLcheck_sqlplus}" | grep -c "ORA-01017"`
  if [ "${chkSQLPLUS}" -ge 1 ]
  then
    Print_log "[ERROR] Cannot connect 'sqlplus / as sysdba'. Check sqlnet.ora."
    exit 1
  fi
}

### Check Oracle version
Check_version () {
  ORACLE_VERSION=`Cmd_sqlplus "${COMMON_VAL}" "select version from v\\\$instance;"`
  ORACLE_VERSION_NUM=`echo "${ORACLE_VERSION}" | tr -d "."`
  ORACLE_MAJOR_VERSION=`echo "${ORACLE_VERSION}" | cut -d"." -f1`

  #number='[0-9]'
  #if ! [[ "${ORACLE_MAJOR_VERSION}" =~ $number ]]
  #then
  #  Print_log "Error: can't check oracle version. Check oracle environment"
  #  Print_log "## Oracle USER : ${ORACLE_USER}"
  #  Print_log "## Oracle HOME : ${ORACLE_HOME}"
  #  Print_log "## Oracle SID : ${ORACLE_SID}"
  #  exit
  #fi
}

### Check Oracle general configuration
ORAoption_general () {
  typeset SQL_ORACLE_GENERAL_11G SQL_ORACLE_GENERAL_12G
  SQL_ORACLE_GENERAL_11G="
   SELECT HOST_NAME                      || '|' ||
          DATABASE_NAME                  || '|' ||
          OPEN_MODE                      || '|' ||
          DATABASE_ROLE                  || '|' ||
          CREATED                        || '|' ||
          DBID                           || '|' ||
          BANNER                         || '|' ||
          MAX_TIMESTAMP                  || '|' ||
          MAX_CPU_COUNT                  || '|' ||
          MAX_CPU_CORE_COUNT             || '|' ||
          MAX_CPU_SOCKET_COUNT           || '|' ||
          LAST_TIMESTAMP                 || '|' ||
          LAST_CPU_COUNT                 || '|' ||
          LAST_CPU_CORE_COUNT            || '|' ||
          LAST_CPU_SOCKET_COUNT          || '|' ||
          CONTROL_MANAGEMENT_PACK_ACCESS || '|' ||
          ENABLE_DDL_LOGGING             || '|' ||
          'NO'                           || '|' ||   -- No CDB lower than 11g.
          VERSION                        || '|' ||
          COMMENTS AS \"DB_GENERAL\"
     FROM
       (SELECT I.HOST_NAME
             , D.NAME AS DATABASE_NAME
             , D.OPEN_MODE
             , D.DATABASE_ROLE
             , TO_CHAR(D.CREATED,'YYYY-MM-DD') CREATED
             , D.DBID
             , V.BANNER
             , I.VERSION
             , (SELECT COMMENTS FROM (SELECT * FROM SYS.REGISTRY\$HISTORY WHERE NAMESPACE ='SERVER' ORDER BY 1 DESC) WHERE ROWNUM <2) COMMENTS
          FROM V\$INSTANCE I, V\$DATABASE D, V\$VERSION V
         WHERE v.BANNER LIKE 'Oracle%' or v.BANNER like 'Personal Oracle%' AND ROWNUM <2) A
	  ,(SELECT TO_CHAR(TIMESTAMP,'YYYY-MM-DD') MAX_TIMESTAMP, CPU_COUNT MAX_CPU_COUNT, CPU_CORE_COUNT MAX_CPU_CORE_COUNT, CPU_SOCKET_COUNT MAX_CPU_SOCKET_COUNT
	      FROM DBA_CPU_USAGE_STATISTICS
         WHERE TIMESTAMP = (SELECT MAX(TIMESTAMP) FROM DBA_CPU_USAGE_STATISTICS WHERE CPU_COUNT = (SELECT MAX(CPU_COUNT) FROM DBA_CPU_USAGE_STATISTICS))) B
	  ,(SELECT TO_CHAR(TIMESTAMP,'YYYY-MM-DD') LAST_TIMESTAMP, CPU_COUNT LAST_CPU_COUNT, CPU_CORE_COUNT LAST_CPU_CORE_COUNT, CPU_SOCKET_COUNT LAST_CPU_SOCKET_COUNT
	      FROM DBA_CPU_USAGE_STATISTICS
         WHERE TIMESTAMP = (SELECT MAX(TIMESTAMP) FROM DBA_CPU_USAGE_STATISTICS)) C
	  ,(SELECT VALUE AS \"CONTROL_MANAGEMENT_PACK_ACCESS\" FROM V\$PARAMETER WHERE LOWER(NAME) IN ('control_management_pack_access')) D
	  ,(SELECT VALUE AS \"ENABLE_DDL_LOGGING\" FROM V\$PARAMETER WHERE LOWER(NAME) IN ('enable_ddl_logging')) E;
   "
  SQL_ORACLE_GENERAL_12G="
   SELECT HOST_NAME                      || '|' ||
          DATABASE_NAME                  || '|' ||
          OPEN_MODE                      || '|' ||
          DATABASE_ROLE                  || '|' ||
          CREATED                        || '|' ||
          DBID                           || '|' ||
          BANNER                         || '|' ||
          MAX_TIMESTAMP                  || '|' ||
          MAX_CPU_COUNT                  || '|' ||
          MAX_CPU_CORE_COUNT             || '|' ||
          MAX_CPU_SOCKET_COUNT           || '|' ||
          LAST_TIMESTAMP                 || '|' ||
          LAST_CPU_COUNT                 || '|' ||
          LAST_CPU_CORE_COUNT            || '|' ||
          LAST_CPU_SOCKET_COUNT          || '|' ||
          CONTROL_MANAGEMENT_PACK_ACCESS || '|' ||
          ENABLE_DDL_LOGGING             || '|' ||
          CDB                            || '|' ||
          VERSION                        || '|' ||
          COMMENTS AS \"DB_GENERAL\"
     FROM
       (SELECT I.HOST_NAME
             , D.NAME AS DATABASE_NAME
             , D.OPEN_MODE
             , D.DATABASE_ROLE
             , TO_CHAR(D.CREATED,'YYYY-MM-DD') CREATED
             , D.DBID
             , V.BANNER
             , D.CDB
             , I.VERSION
             , (SELECT COMMENTS FROM (SELECT * FROM SYS.REGISTRY\$HISTORY WHERE NAMESPACE ='SERVER' ORDER BY 1 DESC) WHERE ROWNUM <2) COMMENTS
          FROM V\$INSTANCE I, V\$DATABASE D, V\$VERSION V
         WHERE V.BANNER LIKE 'Oracle%' or V.BANNER like 'Personal Oracle%' AND ROWNUM <2) A
      ,(SELECT TO_CHAR(TIMESTAMP,'YYYY-MM-DD') MAX_TIMESTAMP, CPU_COUNT MAX_CPU_COUNT, CPU_CORE_COUNT MAX_CPU_CORE_COUNT, CPU_SOCKET_COUNT MAX_CPU_SOCKET_COUNT
	      FROM DBA_CPU_USAGE_STATISTICS
         WHERE TIMESTAMP = (SELECT MAX(TIMESTAMP) FROM DBA_CPU_USAGE_STATISTICS WHERE CPU_COUNT = (SELECT MAX(CPU_COUNT) FROM DBA_CPU_USAGE_STATISTICS))) B
      ,(SELECT TO_CHAR(TIMESTAMP,'YYYY-MM-DD') LAST_TIMESTAMP, CPU_COUNT LAST_CPU_COUNT, CPU_CORE_COUNT LAST_CPU_CORE_COUNT, CPU_SOCKET_COUNT LAST_CPU_SOCKET_COUNT
          FROM DBA_CPU_USAGE_STATISTICS
         WHERE TIMESTAMP = (SELECT MAX(TIMESTAMP) FROM DBA_CPU_USAGE_STATISTICS)) C
      ,(SELECT VALUE AS \"CONTROL_MANAGEMENT_PACK_ACCESS\" FROM V\$PARAMETER WHERE LOWER(NAME) IN ('control_management_pack_access')) D
      ,(SELECT VALUE AS \"ENABLE_DDL_LOGGING\" FROM V\$PARAMETER WHERE LOWER(NAME) IN ('enable_ddl_logging')) E;
   "

  if [ "${ORACLE_MAJOR_VERSION}" -eq 11 ]
  then
    Cmd_sqlplus "${COMMON_VAL}" "${SQL_ORACLE_GENERAL_11G}" > ${RESULT}
  elif [ "${ORACLE_MAJOR_VERSION}" -ge 12 ]
  then
    Cmd_sqlplus "${COMMON_VAL}" "${SQL_ORACLE_GENERAL_12G}" > ${RESULT}
  else
    Print_log "This script is for 11g over."
    exit
  fi

  Set_general_var

  # Insert to output file
  {
    echo $recsep
    echo "##@ ORAoption_general"
    #echo "HOST_NAME:$HOST_NAME"
    echo "DATABASE_NAME:$DATABASE_NAME"
    echo "OPEN_MODE:$OPEN_MODE"
    echo "DATABASE_ROLE:$DATABASE_ROLE"
    echo "CREATED:$CREATED"
    echo "DBID:$DBID"
    echo "BANNER:$BANNER"
    echo "MAX_TIMESTAMP:$MAX_TIMESTAMP"
    echo "MAX_CPU_COUNT:$MAX_CPU_COUNT"
    echo "MAX_CPU_CORE_COUNT:$MAX_CPU_CORE_COUNT"
    echo "MAX_CPU_SOCKET_COUNT:$MAX_CPU_SOCKET_COUNT"
    echo "LAST_TIMESTAMP:$LAST_TIMESTAMP"
    echo "LAST_CPU_COUNT:$LAST_CPU_COUNT"
    echo "LAST_CPU_CORE_COUNT:$LAST_CPU_CORE_COUNT"
    echo "LAST_CPU_SOCKET_COUNT:$LAST_CPU_SOCKET_COUNT"
    echo "CONTROL_MANAGEMENT_PACK_ACCESS:$CONTROL_MANAGEMENT_PACK_ACCESS"
    echo "ENABLE_DDL_LOGGING:$ENABLE_DDL_LOGGING"
    echo "CDB:$CDB"
    echo "VERSION:$VERSION"
    echo "DB_PATCH:$DB_PATCH"
  } >> "${OUTPUT}" 2>&1
}

Set_general_var () {
  Check_general_var ${RESULT} "HOST_NAME"                       1
  Check_general_var ${RESULT} "DATABASE_NAME"                   2
  Check_general_var ${RESULT} "OPEN_MODE"                       3
  Check_general_var ${RESULT} "DATABASE_ROLE"                   4
  Check_general_var ${RESULT} "CREATED"                         5
  Check_general_var ${RESULT} "DBID"                            6
  Check_general_var ${RESULT} "BANNER"                          7
  Check_general_var ${RESULT} "MAX_TIMESTAMP"                   8
  Check_general_var ${RESULT} "MAX_CPU_COUNT"                   9
  Check_general_var ${RESULT} "MAX_CPU_CORE_COUNT"             10
  Check_general_var ${RESULT} "MAX_CPU_SOCKET_COUNT"           11
  Check_general_var ${RESULT} "LAST_TIMESTAMP"                 12
  Check_general_var ${RESULT} "LAST_CPU_COUNT"                 13
  Check_general_var ${RESULT} "LAST_CPU_CORE_COUNT"            14
  Check_general_var ${RESULT} "LAST_CPU_SOCKET_COUNT"          15
  Check_general_var ${RESULT} "CONTROL_MANAGEMENT_PACK_ACCESS" 16
  Check_general_var ${RESULT} "ENABLE_DDL_LOGGING"             17
  Check_general_var ${RESULT} "CDB"                            18
  Check_general_var ${RESULT} "VERSION"                        19
  Check_general_var ${RESULT} "DB_PATCH"                       20
}

Check_general_var () {
  typeset option
  option=`cut -d"|" -f"${3}" ${RESULT}`
  eval "$2"='"${option}"'    # Insert "\" because the space of ${option}
}

### Check Oracle ULA option
ORAoption_ULA () {
  typeset SQL_ORACLE_CHECK_11G SQL_ORACLE_CHECK_12G
  SQL_ORACLE_CHECK_11G="
   with
   MAP as (
   -- mapping between features tracked by DBA_FUS and their corresponding database products (options or packs)
   select '' PRODUCT, '' feature, '' MVERSION, '' CONDITION from dual union all
   SELECT 'Active Data Guard'                                   , 'Active Data Guard - Real-Time Query on Physical Standby' , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Active Data Guard'                                   , 'Global Data Services'                                    , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Active Data Guard or Real Application Clusters'      , 'Application Continuity'                                  , '^1[89]\.|^2[0-9]\.'                           , ' '       from dual union all
   SELECT 'Advanced Analytics'                                  , 'Data Mining'                                             , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Advanced Compression'                                , 'ADVANCED Index Compression'                              , '^12\.'                                        , 'BUG'     from dual union all
   SELECT 'Advanced Compression'                                , 'Advanced Index Compression'                              , '^12\.'                                        , 'BUG'     from dual union all
   SELECT 'Advanced Compression'                                , 'Advanced Index Compression'                              , '^1[89]\.|^2[0-9]\.'                           , ' '       from dual union all
   SELECT 'Advanced Compression'                                , 'Backup HIGH Compression'                                 , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Advanced Compression'                                , 'Backup LOW Compression'                                  , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Advanced Compression'                                , 'Backup MEDIUM Compression'                               , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Advanced Compression'                                , 'Backup ZLIB Compression'                                 , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Advanced Compression'                                , 'Data Guard'                                              , '^11\.2|^1[289]\.|^2[0-9]\.'                   , 'C001'    from dual union all
   SELECT 'Advanced Compression'                                , 'Flashback Data Archive'                                  , '^11\.2\.0\.[1-3]\.'                           , ' '       from dual union all
   SELECT 'Advanced Compression'                                , 'Flashback Data Archive'                                  , '^(11\.2\.0\.[4-9]\.|1[289]\.|2[0-9]\.)'       , 'INVALID' from dual union all -- licensing required by Optimization for Flashback Data Archive
   SELECT 'Advanced Compression'                                , 'HeapCompression'                                         , '^11\.2|^12\.1'                                , 'BUG'     from dual union all
   SELECT 'Advanced Compression'                                , 'HeapCompression'                                         , '^12\.[2-9]|^1[89]\.|^2[0-9]\.'                , ' '       from dual union all
   SELECT 'Advanced Compression'                                , 'Heat Map'                                                , '^12\.1'                                       , 'BUG'     from dual union all
   SELECT 'Advanced Compression'                                , 'Heat Map'                                                , '^12\.[2-9]|^1[89]\.|^2[0-9]\.'                , ' '       from dual union all
   SELECT 'Advanced Compression'                                , 'Hybrid Columnar Compression Row Level Locking'           , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Advanced Compression'                                , 'Information Lifecycle Management'                        , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Advanced Compression'                                , 'Oracle Advanced Network Compression Service'             , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Advanced Compression'                                , 'Oracle Utility Datapump (Export)'                        , '^11\.2|^1[289]\.|^2[0-9]\.'                   , 'C001'    from dual union all
   SELECT 'Advanced Compression'                                , 'Oracle Utility Datapump (Import)'                        , '^11\.2|^1[289]\.|^2[0-9]\.'                   , 'C001'    from dual union all
   SELECT 'Advanced Compression'                                , 'SecureFile Compression (user)'                           , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Advanced Compression'                                , 'SecureFile Deduplication (user)'                         , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Advanced Security'                                   , 'ASO native encryption and checksumming'                  , '^11\.2|^1[289]\.|^2[0-9]\.'                   , 'INVALID' from dual union all -- no longer part of Advanced Security
   SELECT 'Advanced Security'                                   , 'Backup Encryption'                                       , '^11\.2'                                       , ' '       from dual union all
   SELECT 'Advanced Security'                                   , 'Backup Encryption'                                       , '^1[289]\.|^2[0-9]\.'                          , 'INVALID' from dual union all -- licensing required only by encryption to disk
   SELECT 'Advanced Security'                                   , 'Data Redaction'                                          , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Advanced Security'                                   , 'Encrypted Tablespaces'                                   , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Advanced Security'                                   , 'Oracle Utility Datapump (Export)'                        , '^11\.2|^1[289]\.|^2[0-9]\.'                   , 'C002'    from dual union all
   SELECT 'Advanced Security'                                   , 'Oracle Utility Datapump (Import)'                        , '^11\.2|^1[289]\.|^2[0-9]\.'                   , 'C002'    from dual union all
   SELECT 'Advanced Security'                                   , 'SecureFile Encryption (user)'                            , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Advanced Security'                                   , 'Transparent Data Encryption'                             , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Change Management Pack'                              , 'Change Management Pack'                                  , '^11\.2'                                       , ' '       from dual union all
   SELECT 'Configuration Management Pack for Oracle Database'   , 'EM Config Management Pack'                               , '^11\.2'                                       , ' '       from dual union all
   SELECT 'Data Masking Pack'                                   , 'Data Masking Pack'                                       , '^11\.2'                                       , ' '       from dual union all
   SELECT '.Database Gateway'                                   , 'Gateways'                                                , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT '.Database Gateway'                                   , 'Transparent Gateway'                                     , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Database In-Memory'                                  , 'In-Memory ADO Policies'                                  , '^1[89]\.|^2[0-9]\.'                           , ' '       from dual union all -- part of In-Memory Column Store
   SELECT 'Database In-Memory'                                  , 'In-Memory Aggregation'                                   , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Database In-Memory'                                  , 'In-Memory Column Store'                                  , '^12\.1\.0\.2\.'                               , 'BUG'     from dual union all
   SELECT 'Database In-Memory'                                  , 'In-Memory Column Store'                                  , '^12\.1\.0\.[3-9]\.|^12\.2|^1[89]\.|^2[0-9]\.' , ' '       from dual union all
   SELECT 'Database In-Memory'                                  , 'In-Memory Distribute For Service (User Defined)'         , '^1[89]\.|^2[0-9]\.'                           , ' '       from dual union all -- part of In-Memory Column Store
   SELECT 'Database In-Memory'                                  , 'In-Memory Expressions'                                   , '^1[89]\.|^2[0-9]\.'                           , ' '       from dual union all -- part of In-Memory Column Store
   SELECT 'Database In-Memory'                                  , 'In-Memory FastStart'                                     , '^1[89]\.|^2[0-9]\.'                           , ' '       from dual union all -- part of In-Memory Column Store
   SELECT 'Database In-Memory'                                  , 'In-Memory Join Groups'                                   , '^1[89]\.|^2[0-9]\.'                           , ' '       from dual union all -- part of In-Memory Column Store
   SELECT 'Database Vault'                                      , 'Oracle Database Vault'                                   , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Database Vault'                                      , 'Privilege Capture'                                       , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Diagnostics Pack'                                    , 'ADDM'                                                    , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Diagnostics Pack'                                    , 'AWR Baseline'                                            , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Diagnostics Pack'                                    , 'AWR Baseline Template'                                   , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Diagnostics Pack'                                    , 'AWR Report'                                              , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Diagnostics Pack'                                    , 'Automatic Workload Repository'                           , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Diagnostics Pack'                                    , 'Baseline Adaptive Thresholds'                            , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Diagnostics Pack'                                    , 'Baseline Static Computations'                            , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Diagnostics Pack'                                    , 'Diagnostic Pack'                                         , '^11\.2'                                       , ' '       from dual union all
   SELECT 'Diagnostics Pack'                                    , 'EM Performance Page'                                     , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT '.Exadata'                                            , 'Cloud DB with EHCC'                                      , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT '.Exadata'                                            , 'Exadata'                                                 , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT '.GoldenGate'                                         , 'GoldenGate'                                              , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT '.HW'                                                 , 'Hybrid Columnar Compression'                             , '^12\.1'                                       , 'BUG'     from dual union all
   SELECT '.HW'                                                 , 'Hybrid Columnar Compression'                             , '^12\.[2-9]|^1[89]\.|^2[0-9]\.'                , ' '       from dual union all
   SELECT '.HW'                                                 , 'Hybrid Columnar Compression Conventional Load'           , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT '.HW'                                                 , 'Hybrid Columnar Compression Row Level Locking'           , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT '.HW'                                                 , 'Sun ZFS with EHCC'                                       , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT '.HW'                                                 , 'ZFS Storage'                                             , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT '.HW'                                                 , 'Zone maps'                                               , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Label Security'                                      , 'Label Security'                                          , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Multitenant'                                         , 'Oracle Multitenant'                                      , '^1[289]\.|^2[0-9]\.'                          , 'C003'    from dual union all -- licensing required only when more than one PDB containers are created
   SELECT 'Multitenant'                                         , 'Oracle Pluggable Databases'                              , '^1[289]\.|^2[0-9]\.'                          , 'C003'    from dual union all -- licensing required only when more than one PDB containers are created
   SELECT 'OLAP'                                                , 'OLAP - Analytic Workspaces'                              , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'OLAP'                                                , 'OLAP - Cubes'                                            , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Partitioning'                                        , 'Partitioning (user)'                                     , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Partitioning'                                        , 'Zone maps'                                               , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT '.Pillar Storage'                                     , 'Pillar Storage'                                          , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT '.Pillar Storage'                                     , 'Pillar Storage with EHCC'                                , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT '.Provisioning and Patch Automation Pack'             , 'EM Standalone Provisioning and Patch Automation Pack'    , '^11\.2'                                       , ' '       from dual union all
   SELECT 'Provisioning and Patch Automation Pack for Database' , 'EM Database Provisioning and Patch Automation Pack'      , '^11\.2'                                       , ' '       from dual union all
   SELECT 'RAC or RAC One Node'                                 , 'Quality of Service Management'                           , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Real Application Clusters'                           , 'Real Application Clusters (RAC)'                         , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Real Application Clusters One Node'                  , 'Real Application Cluster One Node'                       , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Real Application Testing'                            , 'Database Replay: Workload Capture'                       , '^11\.2|^1[289]\.|^2[0-9]\.'                   , 'C004'    from dual union all
   SELECT 'Real Application Testing'                            , 'Database Replay: Workload Replay'                        , '^11\.2|^1[289]\.|^2[0-9]\.'                   , 'C004'    from dual union all
   SELECT 'Real Application Testing'                            , 'SQL Performance Analyzer'                                , '^11\.2|^1[289]\.|^2[0-9]\.'                   , 'C004'    from dual union all
   SELECT '.Secure Backup'                                      , 'Oracle Secure Backup'                                    , '^1[289]\.|^2[0-9]\.'                          , 'INVALID' from dual union all  -- does not differentiate usage of Oracle Secure Backup Express, which is free
   SELECT 'Spatial and Graph'                                   , 'Spatial'                                                 , '^11\.2'                                       , 'INVALID' from dual union all  -- does not differentiate usage of Locator, which is free
   SELECT 'Spatial and Graph'                                   , 'Spatial'                                                 , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Tuning Pack'                                         , 'Automatic Maintenance - SQL Tuning Advisor'              , '^1[289]\.|^2[0-9]\.'                          , 'INVALID' from dual union all  -- system usage in the maintenance window
   SELECT 'Tuning Pack'                                         , 'Automatic SQL Tuning Advisor'                            , '^11\.2|^1[289]\.|^2[0-9]\.'                   , 'INVALID' from dual union all  -- system usage in the maintenance window
   SELECT 'Tuning Pack'                                         , 'Real-Time SQL Monitoring'                                , '^11\.2'                                       , ' '       from dual union all
   SELECT 'Tuning Pack'                                         , 'Real-Time SQL Monitoring'                                , '^1[289]\.|^2[0-9]\.'                          , 'INVALID' from dual union all  -- default
   SELECT 'Tuning Pack'                                         , 'SQL Access Advisor'                                      , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Tuning Pack'                                         , 'SQL Monitoring and Tuning pages'                         , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Tuning Pack'                                         , 'SQL Profile'                                             , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Tuning Pack'                                         , 'SQL Tuning Advisor'                                      , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Tuning Pack'                                         , 'SQL Tuning Set (user)'                                   , '^1[289]\.|^2[0-9]\.'                          , 'INVALID' from dual union all -- no longer part of Tuning Pack
   SELECT 'Tuning Pack'                                         , 'Tuning Pack'                                             , '^11\.2'                                       , ' '       from dual union all
   SELECT '.WebLogic Server Management Pack Enterprise Edition' , 'EM AS Provisioning and Patch Automation Pack'            , '^11\.2'                                       , ' '       from dual union all
   select '' PRODUCT, '' FEATURE, '' MVERSION, '' CONDITION from dual
   ),
   FUS as (
   -- the LAST data set to be used: DBA_FEATURE_USAGE_STATISTICS or CDB_FEATURE_USAGE_STATISTICS for Container Databases(CDBs)
   select
       0 as CON_ID,
       (select host_name  from v\$instance) as CON_NAME,
       -- Detect and mark with Y the LAST DBA_FUS data set = Most Recent Sample based on LAST_SAMPLE_DATE
         case when DBID || '#' || VERSION || '#' || to_char(LAST_SAMPLE_DATE, 'YYYYMMDDHH24MISS') =
                   first_value (DBID    )         over (partition by 0 order by LAST_SAMPLE_DATE desc nulls last, DBID desc) || '#' ||
                   first_value (VERSION )         over (partition by 0 order by LAST_SAMPLE_DATE desc nulls last, DBID desc) || '#' ||
                   first_value (to_char(LAST_SAMPLE_DATE, 'YYYYMMDDHH24MISS'))
                                                  over (partition by 0 order by LAST_SAMPLE_DATE desc nulls last, DBID desc)
              then 'Y'
              else 'N'
       end as LAST_ENTRY,
       NAME            ,
       LAST_SAMPLE_DATE,
       DBID            ,
       VERSION         ,
       DETECTED_USAGES ,
       TOTAL_SAMPLES   ,
       CURRENTLY_USED  ,
       FIRST_USAGE_DATE,
       LAST_USAGE_DATE ,
       AUX_COUNT       ,
       FEATURE_INFO
   from DBA_FEATURE_USAGE_STATISTICS xy
   ),
   PFUS as (
   -- Product-Feature Usage Statitsics = DBA_FUS entries mapped to their corresponding database products
   select
       CON_ID,
       CON_NAME,
       PRODUCT,
       NAME as FEATURE_BEING_USED,
       case  when CONDITION = 'BUG'
                  --suppressed due to exceptions/defects
                  then '3.SUPPRESSED_DUE_TO_BUG'
             when     detected_usages > 0                 -- some usage detection - LAST or past
                  and CURRENTLY_USED = 'TRUE'             -- usage at LAST_SAMPLE_DATE
                  and LAST_ENTRY  = 'Y'                -- LAST record set
                  and (    trim(CONDITION) is null        -- no extra conditions
                        or CONDITION_MET     = 'TRUE'     -- extra condition is met
                       and CONDITION_COUNTER = 'FALSE' )  -- extra condition is not based on counter
                  then '6.LAST_USAGE'
             when     detected_usages > 0                 -- some usage detection - LAST or past
                  and CURRENTLY_USED = 'TRUE'             -- usage at LAST_SAMPLE_DATE
                  and LAST_ENTRY  = 'Y'                -- LAST record set
                  and (    CONDITION_MET     = 'TRUE'     -- extra condition is met
                       and CONDITION_COUNTER = 'TRUE'  )  -- extra condition is     based on counter
                  then '5.PAST_OR_LAST_USAGE'          -- FEATURE_INFO counters indicate LAST or past usage
             when     detected_usages > 0                 -- some usage detection - LAST or past
                  and (    trim(CONDITION) is null        -- no extra conditions
                        or CONDITION_MET     = 'TRUE'  )  -- extra condition is met
                  then '4.PAST_USAGE'
             when LAST_ENTRY = 'Y'
                  then '2.NO_LAST_USAGE'   -- detectable feature shows no LAST usage
             else '1.NO_PAST_USAGE'
       end as USAGE,
       LAST_SAMPLE_DATE,
       DBID            ,
       VERSION         ,
       DETECTED_USAGES ,
       TOTAL_SAMPLES   ,
       CURRENTLY_USED  ,
       case  when CONDITION like 'C___' and CONDITION_MET = 'FALSE'
                  then to_date('')
             else FIRST_USAGE_DATE
       end as FIRST_USAGE_DATE,
       case  when CONDITION like 'C___' and CONDITION_MET = 'FALSE'
                  then to_date('')
             else LAST_USAGE_DATE
       end as LAST_USAGE_DATE,
       EXTRA_FEATURE_INFO
   from (
   select m.PRODUCT, m.CONDITION, m.MVERSION,
          -- if extra conditions (coded on the MAP.CONDITION column) are required, check if entries satisfy the condition
          case
                when CONDITION = 'C001' and (   regexp_like(to_char(FEATURE_INFO), 'compression[ -]used:[ 0-9]*[1-9][ 0-9]*time', 'i')
                                            and FEATURE_INFO not like '%(BASIC algorithm used: 0 times, LOW algorithm used: 0 times, MEDIUM algorithm used: 0 times, HIGH algorithm used: 0 times)%' -- 12.1 bug - Doc ID 1993134.1
                                             or regexp_like(to_char(FEATURE_INFO), 'compression[ -]used: *TRUE', 'i')                 )
                     then 'TRUE'  -- compression has been used
                when CONDITION = 'C002' and (   regexp_like(to_char(FEATURE_INFO), 'encryption used:[ 0-9]*[1-9][ 0-9]*time', 'i')
                                             or regexp_like(to_char(FEATURE_INFO), 'encryption used: *TRUE', 'i')                  )
                     then 'TRUE'  -- encryption has been used
                when CONDITION = 'C003' and CON_ID=1 and AUX_COUNT > 1
                     then 'TRUE'  -- more than one PDB are created
                when CONDITION = 'C004' and 'OCS'= 'N'
                     then 'TRUE'  -- not in oracle cloud
                else 'FALSE'
          end as CONDITION_MET,
          -- check if the extra conditions are based on FEATURE_INFO counters. They indicate LAST or past usage.
          case
                when CONDITION = 'C001' and     regexp_like(to_char(FEATURE_INFO), 'compression[ -]used:[ 0-9]*[1-9][ 0-9]*time', 'i')
                                            and FEATURE_INFO not like '%(BASIC algorithm used: 0 times, LOW algorithm used: 0 times, MEDIUM algorithm used: 0 times, HIGH algorithm used: 0 times)%' -- 12.1 bug - Doc ID 1993134.1
                     then 'TRUE'  -- compression counter > 0
                when CONDITION = 'C002' and     regexp_like(to_char(FEATURE_INFO), 'encryption used:[ 0-9]*[1-9][ 0-9]*time', 'i')
                     then 'TRUE'  -- encryption counter > 0
                else 'FALSE'
          end as CONDITION_COUNTER,
          case when CONDITION = 'C001'
                    then   regexp_substr(to_char(FEATURE_INFO), 'compression[ -]used:(.*?)(times|TRUE|FALSE)', 1, 1, 'i')
               when CONDITION = 'C002'
                    then   regexp_substr(to_char(FEATURE_INFO), 'encryption used:(.*?)(times|TRUE|FALSE)', 1, 1, 'i')
               when CONDITION = 'C003'
                    then   'AUX_COUNT=' || AUX_COUNT
               when CONDITION = 'C004' and 'OCS'= 'Y'
                    then   'feature included in Oracle Cloud Services Package'
               else ''
          end as EXTRA_FEATURE_INFO,
          f.CON_ID          ,
          f.CON_NAME        ,
          f.LAST_ENTRY   ,
          f.NAME            ,
          f.LAST_SAMPLE_DATE,
          f.DBID            ,
          f.VERSION         ,
          f.DETECTED_USAGES ,
          f.TOTAL_SAMPLES   ,
          f.CURRENTLY_USED  ,
          f.FIRST_USAGE_DATE,
          f.LAST_USAGE_DATE ,
          f.AUX_COUNT       ,
          f.FEATURE_INFO
     from MAP m
     join FUS f on m.FEATURE = f.NAME and regexp_like(f.VERSION, m.MVERSION)
     where nvl(f.TOTAL_SAMPLES, 0) > 0                        -- ignore features that have never been sampled
   )
     where nvl(CONDITION, '-') != 'INVALID'                   -- ignore features for which licensing is not required without further conditions
       and not (CONDITION = 'C003' and CON_ID not in (0, 1))  -- multiple PDBs are visible only in CDB$ROOT; PDB level view is not relevant
   )
   select
       to_char(sysdate,'yyyy-mm-dd hh24:mi:ss') || '|' ||
        (select 'NO' from DUAL) || '|' ||
       VERSION  || '|' ||
       PRODUCT  || '|' ||
       FEATURE_BEING_USED|| '|' ||
       decode(USAGE,
             '1.NO_PAST_USAGE'        , 'NO_USAGE'             ,
             '2.NO_LAST_USAGE'     , 'NO_USAGE'             ,
             '3.SUPPRESSED_DUE_TO_BUG', 'SUPPRESSED_DUE_TO_BUG',
             '4.PAST_USAGE'           , 'PAST_USAGE'           ,
             '5.PAST_OR_LAST_USAGE', 'PAST_OR_LAST_USAGE',
             '6.LAST_USAGE'        , 'LAST_USAGE'        ,
             'UNKNOWN') || '|' ||
       LAST_SAMPLE_DATE|| '|' ||
       FIRST_USAGE_DATE|| '|' ||
       LAST_USAGE_DATE AS \"DB_OPTION\"
     from PFUS
     where USAGE in ('2.NO_LAST_USAGE', '4.PAST_USAGE', '5.PAST_OR_LAST_USAGE', '6.LAST_USAGE')   -- ignore '1.NO_PAST_USAGE', '3.SUPPRESSED_DUE_TO_BUG';
   "
  SQL_ORACLE_CHECK_12G="
   with
   MAP as (
   -- mapping between features tracked by DBA_FUS and their corresponding database products (options or packs)
   select '' PRODUCT, '' feature, '' MVERSION, '' CONDITION from dual union all
   SELECT 'Active Data Guard'                                   , 'Active Data Guard - Real-Time Query on Physical Standby' , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Active Data Guard'                                   , 'Global Data Services'                                    , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Active Data Guard or Real Application Clusters'      , 'Application Continuity'                                  , '^1[89]\.|^2[0-9]\.'                           , ' '       from dual union all
   SELECT 'Advanced Analytics'                                  , 'Data Mining'                                             , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Advanced Compression'                                , 'ADVANCED Index Compression'                              , '^12\.'                                        , 'BUG'     from dual union all
   SELECT 'Advanced Compression'                                , 'Advanced Index Compression'                              , '^12\.'                                        , 'BUG'     from dual union all
   SELECT 'Advanced Compression'                                , 'Advanced Index Compression'                              , '^1[89]\.|^2[0-9]\.'                           , ' '       from dual union all
   SELECT 'Advanced Compression'                                , 'Backup HIGH Compression'                                 , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Advanced Compression'                                , 'Backup LOW Compression'                                  , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Advanced Compression'                                , 'Backup MEDIUM Compression'                               , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Advanced Compression'                                , 'Backup ZLIB Compression'                                 , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Advanced Compression'                                , 'Data Guard'                                              , '^11\.2|^1[289]\.|^2[0-9]\.'                   , 'C001'    from dual union all
   SELECT 'Advanced Compression'                                , 'Flashback Data Archive'                                  , '^11\.2\.0\.[1-3]\.'                           , ' '       from dual union all
   SELECT 'Advanced Compression'                                , 'Flashback Data Archive'                                  , '^(11\.2\.0\.[4-9]\.|1[289]\.|2[0-9]\.)'       , 'INVALID' from dual union all -- licensing required by Optimization for Flashback Data Archive
   SELECT 'Advanced Compression'                                , 'HeapCompression'                                         , '^11\.2|^12\.1'                                , 'BUG'     from dual union all
   SELECT 'Advanced Compression'                                , 'HeapCompression'                                         , '^12\.[2-9]|^1[89]\.|^2[0-9]\.'                , ' '       from dual union all
   SELECT 'Advanced Compression'                                , 'Heat Map'                                                , '^12\.1'                                       , 'BUG'     from dual union all
   SELECT 'Advanced Compression'                                , 'Heat Map'                                                , '^12\.[2-9]|^1[89]\.|^2[0-9]\.'                , ' '       from dual union all
   SELECT 'Advanced Compression'                                , 'Hybrid Columnar Compression Row Level Locking'           , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Advanced Compression'                                , 'Information Lifecycle Management'                        , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Advanced Compression'                                , 'Oracle Advanced Network Compression Service'             , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Advanced Compression'                                , 'Oracle Utility Datapump (Export)'                        , '^11\.2|^1[289]\.|^2[0-9]\.'                   , 'C001'    from dual union all
   SELECT 'Advanced Compression'                                , 'Oracle Utility Datapump (Import)'                        , '^11\.2|^1[289]\.|^2[0-9]\.'                   , 'C001'    from dual union all
   SELECT 'Advanced Compression'                                , 'SecureFile Compression (user)'                           , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Advanced Compression'                                , 'SecureFile Deduplication (user)'                         , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Advanced Security'                                   , 'ASO native encryption and checksumming'                  , '^11\.2|^1[289]\.|^2[0-9]\.'                   , 'INVALID' from dual union all -- no longer part of Advanced Security
   SELECT 'Advanced Security'                                   , 'Backup Encryption'                                       , '^11\.2'                                       , ' '       from dual union all
   SELECT 'Advanced Security'                                   , 'Backup Encryption'                                       , '^1[289]\.|^2[0-9]\.'                          , 'INVALID' from dual union all -- licensing required only by encryption to disk
   SELECT 'Advanced Security'                                   , 'Data Redaction'                                          , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Advanced Security'                                   , 'Encrypted Tablespaces'                                   , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Advanced Security'                                   , 'Oracle Utility Datapump (Export)'                        , '^11\.2|^1[289]\.|^2[0-9]\.'                   , 'C002'    from dual union all
   SELECT 'Advanced Security'                                   , 'Oracle Utility Datapump (Import)'                        , '^11\.2|^1[289]\.|^2[0-9]\.'                   , 'C002'    from dual union all
   SELECT 'Advanced Security'                                   , 'SecureFile Encryption (user)'                            , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Advanced Security'                                   , 'Transparent Data Encryption'                             , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Change Management Pack'                              , 'Change Management Pack'                                  , '^11\.2'                                       , ' '       from dual union all
   SELECT 'Configuration Management Pack for Oracle Database'   , 'EM Config Management Pack'                               , '^11\.2'                                       , ' '       from dual union all
   SELECT 'Data Masking Pack'                                   , 'Data Masking Pack'                                       , '^11\.2'                                       , ' '       from dual union all
   SELECT '.Database Gateway'                                   , 'Gateways'                                                , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT '.Database Gateway'                                   , 'Transparent Gateway'                                     , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Database In-Memory'                                  , 'In-Memory ADO Policies'                                  , '^1[89]\.|^2[0-9]\.'                           , ' '       from dual union all -- part of In-Memory Column Store
   SELECT 'Database In-Memory'                                  , 'In-Memory Aggregation'                                   , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Database In-Memory'                                  , 'In-Memory Column Store'                                  , '^12\.1\.0\.2\.'                               , 'BUG'     from dual union all
   SELECT 'Database In-Memory'                                  , 'In-Memory Column Store'                                  , '^12\.1\.0\.[3-9]\.|^12\.2|^1[89]\.|^2[0-9]\.' , ' '       from dual union all
   SELECT 'Database In-Memory'                                  , 'In-Memory Distribute For Service (User Defined)'         , '^1[89]\.|^2[0-9]\.'                           , ' '       from dual union all -- part of In-Memory Column Store
   SELECT 'Database In-Memory'                                  , 'In-Memory Expressions'                                   , '^1[89]\.|^2[0-9]\.'                           , ' '       from dual union all -- part of In-Memory Column Store
   SELECT 'Database In-Memory'                                  , 'In-Memory FastStart'                                     , '^1[89]\.|^2[0-9]\.'                           , ' '       from dual union all -- part of In-Memory Column Store
   SELECT 'Database In-Memory'                                  , 'In-Memory Join Groups'                                   , '^1[89]\.|^2[0-9]\.'                           , ' '       from dual union all -- part of In-Memory Column Store
   SELECT 'Database Vault'                                      , 'Oracle Database Vault'                                   , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Database Vault'                                      , 'Privilege Capture'                                       , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Diagnostics Pack'                                    , 'ADDM'                                                    , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Diagnostics Pack'                                    , 'AWR Baseline'                                            , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Diagnostics Pack'                                    , 'AWR Baseline Template'                                   , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Diagnostics Pack'                                    , 'AWR Report'                                              , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Diagnostics Pack'                                    , 'Automatic Workload Repository'                           , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Diagnostics Pack'                                    , 'Baseline Adaptive Thresholds'                            , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Diagnostics Pack'                                    , 'Baseline Static Computations'                            , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Diagnostics Pack'                                    , 'Diagnostic Pack'                                         , '^11\.2'                                       , ' '       from dual union all
   SELECT 'Diagnostics Pack'                                    , 'EM Performance Page'                                     , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT '.Exadata'                                            , 'Cloud DB with EHCC'                                      , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT '.Exadata'                                            , 'Exadata'                                                 , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT '.GoldenGate'                                         , 'GoldenGate'                                              , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT '.HW'                                                 , 'Hybrid Columnar Compression'                             , '^12\.1'                                       , 'BUG'     from dual union all
   SELECT '.HW'                                                 , 'Hybrid Columnar Compression'                             , '^12\.[2-9]|^1[89]\.|^2[0-9]\.'                , ' '       from dual union all
   SELECT '.HW'                                                 , 'Hybrid Columnar Compression Conventional Load'           , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT '.HW'                                                 , 'Hybrid Columnar Compression Row Level Locking'           , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT '.HW'                                                 , 'Sun ZFS with EHCC'                                       , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT '.HW'                                                 , 'ZFS Storage'                                             , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT '.HW'                                                 , 'Zone maps'                                               , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Label Security'                                      , 'Label Security'                                          , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Multitenant'                                         , 'Oracle Multitenant'                                      , '^1[289]\.|^2[0-9]\.'                          , 'C003'    from dual union all -- licensing required only when more than one PDB containers are created
   SELECT 'Multitenant'                                         , 'Oracle Pluggable Databases'                              , '^1[289]\.|^2[0-9]\.'                          , 'C003'    from dual union all -- licensing required only when more than one PDB containers are created
   SELECT 'OLAP'                                                , 'OLAP - Analytic Workspaces'                              , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'OLAP'                                                , 'OLAP - Cubes'                                            , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Partitioning'                                        , 'Partitioning (user)'                                     , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Partitioning'                                        , 'Zone maps'                                               , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT '.Pillar Storage'                                     , 'Pillar Storage'                                          , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT '.Pillar Storage'                                     , 'Pillar Storage with EHCC'                                , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT '.Provisioning and Patch Automation Pack'             , 'EM Standalone Provisioning and Patch Automation Pack'    , '^11\.2'                                       , ' '       from dual union all
   SELECT 'Provisioning and Patch Automation Pack for Database' , 'EM Database Provisioning and Patch Automation Pack'      , '^11\.2'                                       , ' '       from dual union all
   SELECT 'RAC or RAC One Node'                                 , 'Quality of Service Management'                           , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Real Application Clusters'                           , 'Real Application Clusters (RAC)'                         , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Real Application Clusters One Node'                  , 'Real Application Cluster One Node'                       , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Real Application Testing'                            , 'Database Replay: Workload Capture'                       , '^11\.2|^1[289]\.|^2[0-9]\.'                   , 'C004'    from dual union all
   SELECT 'Real Application Testing'                            , 'Database Replay: Workload Replay'                        , '^11\.2|^1[289]\.|^2[0-9]\.'                   , 'C004'    from dual union all
   SELECT 'Real Application Testing'                            , 'SQL Performance Analyzer'                                , '^11\.2|^1[289]\.|^2[0-9]\.'                   , 'C004'    from dual union all
   SELECT '.Secure Backup'                                      , 'Oracle Secure Backup'                                    , '^1[289]\.|^2[0-9]\.'                          , 'INVALID' from dual union all  -- does not differentiate usage of Oracle Secure Backup Express, which is free
   SELECT 'Spatial and Graph'                                   , 'Spatial'                                                 , '^11\.2'                                       , 'INVALID' from dual union all  -- does not differentiate usage of Locator, which is free
   SELECT 'Spatial and Graph'                                   , 'Spatial'                                                 , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Tuning Pack'                                         , 'Automatic Maintenance - SQL Tuning Advisor'              , '^1[289]\.|^2[0-9]\.'                          , 'INVALID' from dual union all  -- system usage in the maintenance window
   SELECT 'Tuning Pack'                                         , 'Automatic SQL Tuning Advisor'                            , '^11\.2|^1[289]\.|^2[0-9]\.'                   , 'INVALID' from dual union all  -- system usage in the maintenance window
   SELECT 'Tuning Pack'                                         , 'Real-Time SQL Monitoring'                                , '^11\.2'                                       , ' '       from dual union all
   SELECT 'Tuning Pack'                                         , 'Real-Time SQL Monitoring'                                , '^1[289]\.|^2[0-9]\.'                          , 'INVALID' from dual union all  -- default
   SELECT 'Tuning Pack'                                         , 'SQL Access Advisor'                                      , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Tuning Pack'                                         , 'SQL Monitoring and Tuning pages'                         , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Tuning Pack'                                         , 'SQL Profile'                                             , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Tuning Pack'                                         , 'SQL Tuning Advisor'                                      , '^11\.2|^1[289]\.|^2[0-9]\.'                   , ' '       from dual union all
   SELECT 'Tuning Pack'                                         , 'SQL Tuning Set (user)'                                   , '^1[289]\.|^2[0-9]\.'                          , 'INVALID' from dual union all -- no longer part of Tuning Pack
   SELECT 'Tuning Pack'                                         , 'Tuning Pack'                                             , '^11\.2'                                       , ' '       from dual union all
   SELECT '.WebLogic Server Management Pack Enterprise Edition' , 'EM AS Provisioning and Patch Automation Pack'            , '^11\.2'                                       , ' '       from dual union all
   select '' PRODUCT, '' FEATURE, '' MVERSION, '' CONDITION from dual
   ),
   FUS as (
   -- the LAST data set to be used: DBA_FEATURE_USAGE_STATISTICS or CDB_FEATURE_USAGE_STATISTICS for Container Databases(CDBs)
   select
       0 as CON_ID,
       (select host_name  from v\$instance) as CON_NAME,
       -- Detect and mark with Y the LAST DBA_FUS data set = Most Recent Sample based on LAST_SAMPLE_DATE
         case when DBID || '#' || VERSION || '#' || to_char(LAST_SAMPLE_DATE, 'YYYYMMDDHH24MISS') =
                   first_value (DBID    )         over (partition by 0 order by LAST_SAMPLE_DATE desc nulls last, DBID desc) || '#' ||
                   first_value (VERSION )         over (partition by 0 order by LAST_SAMPLE_DATE desc nulls last, DBID desc) || '#' ||
                   first_value (to_char(LAST_SAMPLE_DATE, 'YYYYMMDDHH24MISS'))
                                                  over (partition by 0 order by LAST_SAMPLE_DATE desc nulls last, DBID desc)
              then 'Y'
              else 'N'
       end as LAST_ENTRY,
       NAME            ,
       LAST_SAMPLE_DATE,
       DBID            ,
       VERSION         ,
       DETECTED_USAGES ,
       TOTAL_SAMPLES   ,
       CURRENTLY_USED  ,
       FIRST_USAGE_DATE,
       LAST_USAGE_DATE ,
       AUX_COUNT       ,
       FEATURE_INFO
   from DBA_FEATURE_USAGE_STATISTICS xy
   ),
   PFUS as (
   -- Product-Feature Usage Statitsics = DBA_FUS entries mapped to their corresponding database products
   select
       CON_ID,
       CON_NAME,
       PRODUCT,
       NAME as FEATURE_BEING_USED,
       case  when CONDITION = 'BUG'
                  --suppressed due to exceptions/defects
                  then '3.SUPPRESSED_DUE_TO_BUG'
             when     detected_usages > 0                 -- some usage detection - LAST or past
                  and CURRENTLY_USED = 'TRUE'             -- usage at LAST_SAMPLE_DATE
                  and LAST_ENTRY  = 'Y'                -- LAST record set
                  and (    trim(CONDITION) is null        -- no extra conditions
                        or CONDITION_MET     = 'TRUE'     -- extra condition is met
                       and CONDITION_COUNTER = 'FALSE' )  -- extra condition is not based on counter
                  then '6.LAST_USAGE'
             when     detected_usages > 0                 -- some usage detection - LAST or past
                  and CURRENTLY_USED = 'TRUE'             -- usage at LAST_SAMPLE_DATE
                  and LAST_ENTRY  = 'Y'                -- LAST record set
                  and (    CONDITION_MET     = 'TRUE'     -- extra condition is met
                       and CONDITION_COUNTER = 'TRUE'  )  -- extra condition is     based on counter
                  then '5.PAST_OR_LAST_USAGE'          -- FEATURE_INFO counters indicate LAST or past usage
             when     detected_usages > 0                 -- some usage detection - LAST or past
                  and (    trim(CONDITION) is null        -- no extra conditions
                        or CONDITION_MET     = 'TRUE'  )  -- extra condition is met
                  then '4.PAST_USAGE'
             when LAST_ENTRY = 'Y'
                  then '2.NO_LAST_USAGE'   -- detectable feature shows no LAST usage
             else '1.NO_PAST_USAGE'
       end as USAGE,
       LAST_SAMPLE_DATE,
       DBID            ,
       VERSION         ,
       DETECTED_USAGES ,
       TOTAL_SAMPLES   ,
       CURRENTLY_USED  ,
       case  when CONDITION like 'C___' and CONDITION_MET = 'FALSE'
                  then to_date('')
             else FIRST_USAGE_DATE
       end as FIRST_USAGE_DATE,
       case  when CONDITION like 'C___' and CONDITION_MET = 'FALSE'
                  then to_date('')
             else LAST_USAGE_DATE
       end as LAST_USAGE_DATE,
       EXTRA_FEATURE_INFO
   from (
   select m.PRODUCT, m.CONDITION, m.MVERSION,
          -- if extra conditions (coded on the MAP.CONDITION column) are required, check if entries satisfy the condition
          case
                when CONDITION = 'C001' and (   regexp_like(to_char(FEATURE_INFO), 'compression[ -]used:[ 0-9]*[1-9][ 0-9]*time', 'i')
                                            and FEATURE_INFO not like '%(BASIC algorithm used: 0 times, LOW algorithm used: 0 times, MEDIUM algorithm used: 0 times, HIGH algorithm used: 0 times)%' -- 12.1 bug - Doc ID 1993134.1
                                             or regexp_like(to_char(FEATURE_INFO), 'compression[ -]used: *TRUE', 'i')                 )
                     then 'TRUE'  -- compression has been used
                when CONDITION = 'C002' and (   regexp_like(to_char(FEATURE_INFO), 'encryption used:[ 0-9]*[1-9][ 0-9]*time', 'i')
                                             or regexp_like(to_char(FEATURE_INFO), 'encryption used: *TRUE', 'i')                  )
                     then 'TRUE'  -- encryption has been used
                when CONDITION = 'C003' and CON_ID=1 and AUX_COUNT > 1
                     then 'TRUE'  -- more than one PDB are created
                when CONDITION = 'C004' and 'OCS'= 'N'
                     then 'TRUE'  -- not in oracle cloud
                else 'FALSE'
          end as CONDITION_MET,
          -- check if the extra conditions are based on FEATURE_INFO counters. They indicate LAST or past usage.
          case
                when CONDITION = 'C001' and     regexp_like(to_char(FEATURE_INFO), 'compression[ -]used:[ 0-9]*[1-9][ 0-9]*time', 'i')
                                            and FEATURE_INFO not like '%(BASIC algorithm used: 0 times, LOW algorithm used: 0 times, MEDIUM algorithm used: 0 times, HIGH algorithm used: 0 times)%' -- 12.1 bug - Doc ID 1993134.1
                     then 'TRUE'  -- compression counter > 0
                when CONDITION = 'C002' and     regexp_like(to_char(FEATURE_INFO), 'encryption used:[ 0-9]*[1-9][ 0-9]*time', 'i')
                     then 'TRUE'  -- encryption counter > 0
                else 'FALSE'
          end as CONDITION_COUNTER,
          case when CONDITION = 'C001'
                    then   regexp_substr(to_char(FEATURE_INFO), 'compression[ -]used:(.*?)(times|TRUE|FALSE)', 1, 1, 'i')
               when CONDITION = 'C002'
                    then   regexp_substr(to_char(FEATURE_INFO), 'encryption used:(.*?)(times|TRUE|FALSE)', 1, 1, 'i')
               when CONDITION = 'C003'
                    then   'AUX_COUNT=' || AUX_COUNT
               when CONDITION = 'C004' and 'OCS'= 'Y'
                    then   'feature included in Oracle Cloud Services Package'
               else ''
          end as EXTRA_FEATURE_INFO,
          f.CON_ID          ,
          f.CON_NAME        ,
          f.LAST_ENTRY   ,
          f.NAME            ,
          f.LAST_SAMPLE_DATE,
          f.DBID            ,
          f.VERSION         ,
          f.DETECTED_USAGES ,
          f.TOTAL_SAMPLES   ,
          f.CURRENTLY_USED  ,
          f.FIRST_USAGE_DATE,
          f.LAST_USAGE_DATE ,
          f.AUX_COUNT       ,
          f.FEATURE_INFO
     from MAP m
     join FUS f on m.FEATURE = f.NAME and regexp_like(f.VERSION, m.MVERSION)
     where nvl(f.TOTAL_SAMPLES, 0) > 0                        -- ignore features that have never been sampled
   )
     where nvl(CONDITION, '-') != 'INVALID'                   -- ignore features for which licensing is not required without further conditions
       and not (CONDITION = 'C003' and CON_ID not in (0, 1))  -- multiple PDBs are visible only in CDB$ROOT; PDB level view is not relevant
   )
   select
       to_char(sysdate,'yyyy-mm-dd hh24:mi:ss') || '|' ||
        (select CDB from V\$DATABASE) || '|' ||
       VERSION  || '|' ||
       PRODUCT  || '|' ||
       FEATURE_BEING_USED|| '|' ||
       decode(USAGE,
             '1.NO_PAST_USAGE'        , 'NO_USAGE'             ,
             '2.NO_LAST_USAGE'     , 'NO_USAGE'             ,
             '3.SUPPRESSED_DUE_TO_BUG', 'SUPPRESSED_DUE_TO_BUG',
             '4.PAST_USAGE'           , 'PAST_USAGE'           ,
             '5.PAST_OR_LAST_USAGE', 'PAST_OR_LAST_USAGE',
             '6.LAST_USAGE'        , 'LAST_USAGE'        ,
             'UNKNOWN') || '|' ||
       LAST_SAMPLE_DATE|| '|' ||
       FIRST_USAGE_DATE|| '|' ||
       LAST_USAGE_DATE AS \"DB_OPTION\"
     from PFUS
     where USAGE in ('2.NO_LAST_USAGE', '4.PAST_USAGE', '5.PAST_OR_LAST_USAGE', '6.LAST_USAGE')   -- ignore '1.NO_PAST_USAGE', '3.SUPPRESSED_DUE_TO_BUG';
   "

  if [ "${ORACLE_MAJOR_VERSION}" -eq 11 ]
  then
    Cmd_sqlplus "${COMMON_VAL}" "${SQL_ORACLE_CHECK_11G}" > ${RESULT}
  elif [ "${ORACLE_MAJOR_VERSION}" -ge 12 ]
  then
    Cmd_sqlplus "${COMMON_VAL}" "${SQL_ORACLE_CHECK_12G}" > ${RESULT}
  else
    Print_log "This script is for 11g over."
    exit
  fi

  Set_option_var

  # Insert to output file
  {
    echo $recsep
    echo "##@ ORAoption_ULA"
    echo "DATABASE_GATEWAY:${DATABASE_GATEWAY}"
    echo "EXADATA:${EXADATA}"
    echo "GOLDENGATE:${GOLDENGATE}"
    echo "HW:${HW}"
    echo "PILLARSTORAGE:${PILLARSTORAGE}"
    echo "ADG:${ADG}"
    echo "ADG_RAC:${ADG}"
    echo "ADVANCED_ANALYTICS:${AA}"
    echo "ADVANCED_COMPRESIION:${AC}"
    echo "ADVANCED_SECURITY:${AS}"
    echo "DATABASE_INMEMORY:${DIM}"
    echo "DATABASE_VAULT:${DV}"
    echo "DIAGNOSTICS_PACK:${DP}"
    echo "LABEL_SECURIRY:${LS}"
    echo "MULTITENANT:${MT}"
    echo "OLAP:${OLAP}"
    echo "PARTITION:${PARTITION}"
    echo "RAC_ONENODE:${RAC_ONENODE}"
    echo "RAC:${RAC}"
    echo "ONENODE:${ONENODE}"
    echo "RAT:${RAT}"
    echo "SPATIAL:${SPATIAL}"
    echo "TUNING:${TUNING}"
  } >> "${OUTPUT}" 2>&1
}

Set_option_var() {
  Check_option_var ${RESULT} ".Database Gateway"                                 "DATABASE_GATEWAY"
  Check_option_var ${RESULT} ".Exadata"                                          "EXADATA"
  Check_option_var ${RESULT} ".GoldenGate"                                       "GOLDENGATE"
  Check_option_var ${RESULT} ".HW"                                               "HW"
  Check_option_var ${RESULT} ".Pillar Storage"                                   "PILLARSTORAGE"
  Check_option_var ${RESULT} "Active Data Guard"                                 "ADG"
  Check_option_var ${RESULT} "Active Data Guard or Real Application Clusters"    "ADG_RAC"
  Check_option_var ${RESULT} "Advanced Analytics"                                "AA"
  Check_option_var ${RESULT} "Advanced Compression"                              "AC"
  Check_option_var ${RESULT} "Advanced Security"                                 "AS"
  Check_option_var ${RESULT} "Database In-Memory"                                "DIM"
  Check_option_var ${RESULT} "Database Vault"                                    "DV"
  Check_option_var ${RESULT} "Diagnostics Pack"                                  "DP"
  Check_option_var ${RESULT} "Label Security"                                    "LS"
  Check_option_var ${RESULT} "Multitenant"                                       "MT"
  Check_option_var ${RESULT} "OLAP"                                              "OLAP"
  Check_option_var ${RESULT} "Partitioning"                                      "PARTITION"
  Check_option_var ${RESULT} "RAC or RAC One Node"                               "RAC_ONENODE"
  Check_option_var ${RESULT} "Real Application Clusters"                         "RAC"
  Check_option_var ${RESULT} "Real Application Clusters One Node"                "ONENODE"
  Check_option_var ${RESULT} "Real Application Testing"                          "RAT"
  Check_option_var ${RESULT} "Spatial and Graph"                                 "SPATIAL"
  Check_option_var ${RESULT} "Tuning Pack"                                       "TUNING"
}

Check_option_var() {
  typeset option
  if grep -q "${2}" ${RESULT} | grep -v "NO_USAGE"
  then
    eval "$3"=0   # NO_USAGE ==> 0
  else
    option=`grep "${2}" ${RESULT} | cut -d"|" -f6 | grep -cv "NO_USAGE"`
    #eval $3="${#option[@]}"     # Count of options
    eval "$3"="${option}"
  fi
}

### Oracle Common information
ORAcommon () {
  typeset SQLcollection_day SQLinstance_number SQLrac_yn SQLdb_created_time SQLinstance_startup_time SQLinstance_startup_days SQLinstance_role SQLdbname
  typeset SQLcontrolfile_seq SQLlog_mode SQLopen_mode SQLcontrolfile_count SQLlogfile_count SQLmin_log_member_count SQLactive_session_count SQLhard_parse
  typeset SQLlog_archive_dest SQLlog_archive_dest_1 SQLarchivelog_1day_mbytes

  SQLcollection_day="select 'COLLECTION_DAY:' || to_char(sysdate,'yymmdd') from dual;"
  SQLinstance_name="select 'INSTANCE_NAME:' || INSTANCE_NAME from v\$instance;"
  SQLinstance_number="select 'INSTANCE_NUMBER:' || INSTANCE_NUMBER from v\$instance;"
  SQLrac_yn="select 'RAC:'||decode(PARALLEL,'YES','Y','N') from v\$instance;"
  SQLdb_created_time="select 'DB_CREATED_TIME:' || to_char(CREATED,'YYYYMMDD') from v\$database;"
  SQLinstance_startup_time="select 'INSTANCE_STARTUP_TIME:' || to_char(STARTUP_TIME,'YYYYMMDD') from v\$instance;"
  SQLinstance_startup_days="select 'INSTANCE_STARTUP_DAYS:' || round(sysdate-STARTUP_TIME) from v\$instance;"
  SQLinstance_role="select 'INSTANCE_ROLE:' || INSTANCE_ROLE from v\$instance;"
  SQLdbname="select 'DBNAME:' || NAME from v\$database;"

  SQLcontrolfile_seq="select 'CONTROLFILE_SEQ:' || to_char(max(FHCSQ)) from x\$kcvfh;"
  SQLlog_mode="select 'LOG_MODE:' || LOG_MODE from v\$database;"
  SQLopen_mode="select 'OPEN_MODE:' || OPEN_MODE from v\$database;"

  SQLcontrolfile_count="select 'CONTROLFILE_COUNT:' || count(*) from v\$controlfile;"
  SQLlogfile_count="select 'LOGFILE_COUNT:'||count(*) from v\$logfile;"
  SQLmin_log_member_count="
   select 'MIN_LOG_MEMBER_COUNT:'||min(a.member)
     from (select count(*) member
             from v\$logfile
            where status is null and type not in ('STANDBY')
            group by group#) a;
   "
  SQLactive_session_count="
   SELECT 'ACTIVE_SESSION_COUNT:' || ACTIVE_SESSION_COUNT
     FROM (SELECT round(avg(average/100),2) as active_session_count
             FROM dba_hist_sysmetric_summary
            WHERE begin_time > sysdate-8
              and average < 100000
			  and METRIC_NAME in ('Database Time Per Sec')
			  and instance_number = (select instance_number from v\$instance)
		  );
   "
  SQLhard_parse="
   SELECT 'HARD_PARSE_COUNT:' || round(avg(average))
     FROM dba_hist_sysmetric_summary
    WHERE begin_time > sysdate-8
      and average < 500
      and METRIC_NAME in ('Hard Parse Count Per Sec')
      and instance_number = (select instance_number from v\$instance);
   "
  SQLlog_archive_dest="select 'LOG_ARCHIVE_DEST:'||replace(value,'?','$ORACLE_HOME') from v\$parameter where name='log_archive_dest';"
  SQLlog_archive_dest_1="select 'LOG_ARCHIVE_DEST_1:'||replace(value,'?','$ORACLE_HOME') from v\$parameter where name='log_archive_dest_1';"
  SQLarchivelog_1day_mbytes="
   select 'ARCHIVELOG_1DAY_MBYTES:'||round(sum(blocks*block_size)/1024/1024/7,1)
     from v\$archived_log
    where thread# = (select thread# from v\$instance)
	  and COMPLETION_TIME > sysdate -7;
   "
   
  # Insert to output file
  {
    echo $recsep
    echo "##@ ORAcommon"
    echo "VERSION:${ORACLE_VERSION}"
  } >> "${OUTPUT}"
  
  sqlplus -silent / as sysdba 2>/dev/null >> "${OUTPUT}" << EOF
  $COMMON_VAL
  $SQLcollection_day
  $SQLinstance_name
  $SQLinstance_number
  $SQLrac_yn
  $SQLdb_created_time
  $SQLinstance_startup_time
  $SQLinstance_startup_days
  $SQLinstance_role
  $SQLdbname
  $SQLcontrolfile_seq
  $SQLlog_mode
  $SQLopen_mode
  $SQLcontrolfile_count
  $SQLlogfile_count
  $SQLmin_log_member_count
  $SQLactive_session_count
  $SQLhard_parse
  $SQLlog_archive_dest
  $SQLlog_archive_dest_1
  $SQLarchivelog_1day_mbytes
  exit
EOF

  typeset isOSW OSWATCHER AUDIT_FILE_DEST AUDIT_FILE_COUNT SQLheadroom SCN MAXIMUM_SCN CURRENT_SCN HEADROOM
  # OS Watcher
  isOSW=`ps -ef | grep -v grep | grep -c OSW`
  if [ "${isOSW}" -ge 0 ]
  then
    OSWATCHER="Y"
  else
    OSWATCHER="N"
  fi

  # Audit file
  AUDIT_FILE_DEST=`Cmd_sqlplus "${COMMON_VAL}" "select value from v\\\$parameter where name='audit_file_dest';"`
  AUDIT_FILE_COUNT=`find "${AUDIT_FILE_DEST}" -type f -name "*.aud" | wc -l | sed 's/ //g'`
  
  # Headroom
  SQLheadroom="
   set numwidth 14
   select maximum_scn ||':'|| current_scn ||':'||
       trunc((maximum_scn - current_scn)/(16384*3600*24),1) headroom
     from (select dbms_flashback.get_system_change_number current_scn,
              ((((to_number(to_char(sysdate, 'YYYY'))-1988)*372)+
                ((to_number(to_char(sysdate,'MM'))-1)*31)+
                ((to_number(to_char(sysdate,'DD'))-1)))*86400+
                 (to_number(to_char(sysdate,'HH24'))*3600)+
                 (to_number(to_char(sysdate,'MI'))*60)+
                  to_number(to_char(sysdate,'SS')))*16384 maximum_scn
            from dual) scn_stat;
   "
  SCN=`Cmd_sqlplus "${COMMON_VAL}" "${SQLheadroom}"`
  MAXIMUM_SCN=`echo "${SCN}" | cut -d":" -f1`
  CURRENT_SCN=`echo "${SCN}" | cut -d":" -f2`
  HEADROOM=`echo "${SCN}" | cut -d":" -f3`
  
  { # Insert to output file
    echo "OSWATCHER:$OSWATCHER"
	echo "AUDIT_FILE_COUNT:$AUDIT_FILE_COUNT"
	echo "MAXIMUM_SCN:$MAXIMUM_SCN"
	echo "CURRENT_SCN:$CURRENT_SCN"
	echo "HEADROOM:$HEADROOM"
    echo "ASM:$isASM"
  } >> "${OUTPUT}" 2>&1
}

### Oracle user resource limit
ORAosuser () {
  { # Insert to output file
    echo $recsep
    echo "##@ ORAosuser"
	if [ "${OS_NAME}" = "SunOS" ]
    then
      /usr/xpg4/bin/ulimit -a
    else
      /usr/bin/ulimit -a
    fi
  } >> "${OUTPUT}" 2>&1
}

### Oracle Database Patch
ORApatch () {
  { # Insert to output file
    echo $recsep
    echo "##@ ORApatch"
    "${ORACLE_HOME}/OPatch/opatch" lsinventory -oh "${ORACLE_HOME}"
  } >> "${OUTPUT}" 2>&1
}

### Oracle Datafiles
ORAfile () {
  typeset SQLdatafile SQLtempfile SQLtotal_free SQLtemp_free
  SQLdatafile="
   col file_name for a60
   col tablespace_name for a20
   select file_id, file_name, tablespace_name, bytes/1024/1024 MB, autoextensible from dba_data_files order by file_name;
  "
  SQLtempfile="
   col file_name for a60
   col tablespace_name for a20
   select file_id, file_name, tablespace_name, bytes/1024/1024 MB, autoextensible from dba_temp_files;
  "
  SQLtotal_free="
   column tn   format a20            heading 'TableSpace|Name'
   column Tot  format 999,999,999.99 heading 'Total|(Mb)'
   column Free format 999,999,999.99 heading 'Free|(Mb)'
   column Used format 999,999,999.99 heading 'Used|(Mb)'
   column Pct  format 999,999,999.99 heading 'Pct|(%)'
   SELECT  t.tn,
           t.sizes Tot,
           (t.sizes - f.sizes ) Used,
           (t.sizes - f.sizes) /t.sizes * 100 Pct,
           f.sizes Free
   FROM    ( SELECT tablespace_name tn,
                    sum(bytes)/1024/1024 Sizes
             FROM   dba_data_files
             GROUP  BY tablespace_name) t,
           ( SELECT tablespace_name tn,
                    sum(bytes)/1024/1024 sizes
             FROM   dba_free_space
             GROUP BY tablespace_name) f
   WHERE t.tn = f.tn
   ORDER BY Pct desc;
  "
  SQLtemp_free="
   col tablespace_name for a20
   col total_m for	999,999,999.99 heading 'TOTAL (MB)'
   col free_m for	999,999,999.99 heading 'FREE (MB)'
   col pct_used for	999,999,999.99 heading 'PCT (%)'
   select a.tablespace_name, a.total_M, b.free_M, round((b.used_M/a.total_M)*100,2) pct_used
   from ( select tablespace_name, sum(bytes/1024/1024) total_M from dba_temp_files
    group by tablespace_name ) a,
    ( select tablespace_name, sum(bytes_free/1024/1024) free_M, sum(bytes_used/1024/1024) used_M
      from v\$temp_space_header
      group by tablespace_name ) b
   where a.tablespace_name = b.tablespace_name;
  "
  
  { # Insert to output file
    echo $recsep
    echo "##@ ORAfile"
  } >> "${OUTPUT}" 2>&1
  
  sqlplus -silent / as sysdba 2>/dev/null >> "${OUTPUT}" << EOF
  $COLLECT_VAL
  prompt # Datafiles
  $SQLdatafile
  prompt # Tempfiles
  $SQLtempfile
  prompt # Total free
  $SQLtotal_free
  prompt # Temp free
  $SQLtemp_free
  exit
EOF
}

### OS information
OSinfo () {
  { # Insert to output file
    echo $recsep
    echo "##@ OSinfo"
	if [ "${OS_NAME}" = "SunOS" ]
    then
	  echo "# psrinfo"
      /usr/sbin/psrinfo -pv
	  echo "\n# prtconf"
	  /usr/sbin/prtconf
    elif [ "${OS_NAME}" = "HP-UX" ]
	then
      /usr/contrib/bin/machinfo -v
    fi
  } >> "${OUTPUT}" 2>&1
}

### Logging error
Print_log() {
  typeset LOG LOGDATE COLLECT_YEAR
  COLLECT_YEAR=`date '+%Y'`
  LOG="${BINDIR}/DCT_${HOSTNAME}_${COLLECT_YEAR}.log"
  
  # Create file with '664' permission for multiple Oracle users.
  if [ ! -f "${LOG}" ]
  then
    /bin/touch "${LOG}"
    chmod 664 "${LOG}"
  fi
  
  LOGDATE="[`date '+%Y%m%d-%H:%M:%S'`]"
  echo "${LOGDATE} $1" >> "${LOG}"
}


# ========== Main ========== #
# Create target directory
if [ ! -d "${BINDIR}" ]
then
  set -e
  mkdir "${BINDIR}"
  set +e
fi

# Get Oracle environment data
Get_oracle_env
Print_log "(${ORACLE_USER}) Start collect"

### Oracle Database
for ORACLE_SID in ${ORACLE_SIDs}
do
  # If there are options in glogin.sql move the file.
  GLOGIN="${ORACLE_HOME}/sqlplus/admin/glogin.sql"
  isGLOGIN=`sed '/^$/d' "${GLOGIN}" | grep -cv "\-\-"`
  if [ "${isGLOGIN}" -gt 0 ]
  then
    /bin/mv "${GLOGIN}" "${GLOGIN}"_old
  fi
  
  Create_output
  OScommon
  OSdf
  OShosts
  #OSlimits
  #OSkernel_parameter
  #OSrpm
  #OSntp
  #OSnsswitch
  
  Check_sqlplus
  Check_version
  
  # Check ULA option when Oracle version is above 11g.
  if [ "${ORACLE_MAJOR_VERSION}" -ge "11" ]
  then
    ORAoption_general
    ORAoption_ULA
  fi
  
  ORAcommon
  ORAosuser
  ORApatch
  ORAfile
  #ORAprivilege
  #ORAjob
  #ORAcapacity
  #ORAetc
  #ORAlistener
  #ORApfile
  #ORAredo
  #ORAredo_switch
  #ORAevent_count
  #ORAevent_group
  #ORAash
  #ORAalert
  #ORAparameter
  OSinfo
  
  # Recover glogin.sql
  if [ "${isGLOGIN}" -gt 0 ]
  then
    /bin/mv "${GLOGIN}"_old "${GLOGIN}"
  fi
done

if [ -f "${RESULT}" ]
then
  /bin/rm ${RESULT}
fi

Print_log "(${ORACLE_USER}) End collect"
