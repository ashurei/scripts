#!/bin/ksh
########################################################
# Description : Data Collection Tool with Oracle
# Create DATE : 2021.04.20
# Last Update DATE : 2022.05.31 by ashurei
# Copyright (c) ashurei@sktelecom.com, 2021
########################################################

# This script was created for UNIX environment.
# This script was created to be run by the Oracle user. 

# Requirements : Shell   : Korn Shell
#                OS User : DBMS Install User
#                DB User : SYSDBA
#              
# Refer to     : Database Options/Management Packs Usage Reporting for Oracle Databases 11.2 and later (Doc ID 1317265.1)
#                Place Holder For Feature Usage Tracking Bugs (Doc ID 1309070.1)
#              
# Applies to   : Oracle Database # 9i, 10gR2, 11gR2, 12c, 19c
#                This script has a few limitations : version 11.1 and lower may yield incorrect results.
#                Container Databases(CDB) Possible
#              
# Platform     : Solaris, HP-UX
#              
# Description  : This script provides usage statistics for Database Options, Management Packs their corresponding features.
#                Information is extracted from DBA_FEATURE_USAGE_STATISTICS view.

BINDIR="/tmp/DCT-oracle"
SCRIPT_VER="2022.05.31.r01"

# Get environment from Oracle user for crontab.
. ~/.profile

LANG=C
export LANG
COLLECT_DATE=`date '+%Y%m%d'`
COLLECT_TIME=`date '+%Y%m%d_%H%M%S'`
HOSTNAME=`hostname`
WHOAMI=`id | awk '{print $1}' | cut -d"(" -f2 | sed 's/)//'`
RESULT="${BINDIR}/result.log"
recsep="#####################################################################################################################################################"
COMMON_VAL="set line 500 pagesize 0 feedback off verify off heading off echo off timing off"
COLLECT_VAL="set line 200 pages 10000 feedback off verify off echo off"

PLATFORM=`uname`
if [ "${PLATFORM}" = "SunOS" ]
then
  PATH=/usr/xpg4/bin:${PATH}
  export PATH
  AWK="/usr/bin/nawk"
else
  AWK="/usr/bin/awk"
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
  ORACLE_USER=`ps -ef | grep ora_pmon | sed 's/^ *//' | grep -w "^${WHOAMI}" | grep -v grep | head -1 | "${AWK}" '{print $1}'`
  ORACLE_SIDs=`ps -ef | grep ora_pmon | sed 's/^ *//' | grep -w "^${WHOAMI}" | grep -v grep | "${AWK}" '{print $NF}' | cut -d"_" -f3`

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
  GRID_USER=`ps -ef | grep ocssd.bin | grep -v grep | "${AWK}" '{print $1}'`
  # If $GRID_USER is exist
  if [ -n "${GRID_USER}" ]
  then
    # If user length is equal 8, remove '+' (ex. gridSPA+ => gridSPA)
    if [ "${#GRID_USER}" -eq 8 ]
    then
      GRID_USER="${GRID_USER:0:-1}"
    fi
    GRID_HOME=`ps -ef | grep crsd.bin | grep -v grep | "${AWK}" -F"/bin/crsd.bin" '{print $1}' | grep -v awk | "${AWK}" '{print $NF}'`
    CRSCTL="${GRID_HOME}/bin/crsctl"
    SRVCTL="${GRID_HOME}/bin/srvctl"
  fi
  
  # Check ASM environment
  isASM=`ps -ef | grep -v grep | grep -c asm_pmon`
}

### Create output file
Create_output () {
  typeset DEL_LOG DEL_OUT
  # Delete log files 390 days+ ago
  DEL_LOG=`find ${BINDIR:?}/DCT_"${HOSTNAME}"_*.log -mtime +390 -type f -exec rm -f {} \; 2>&1`
  if [ -n "${DEL_LOG}" ]   # If $DEL_LOG is exists write to Print_log.
  then
    Print_log "${DEL_LOG}"
  fi
  
  # Delete output files 14 days+ ago
  DEL_OUT=`find ${BINDIR:?}/DCT_"${HOSTNAME}"_*.out -mtime +14 -type f -exec rm -f {} \; 2>&1`
  if [ -n "${DEL_OUT}" ]
  then
    Print_log "${DEL_OUT}"
  fi

  # OUTPUT file name
  umask 0022
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
  
  case "${PLATFORM}" in
  "HP-UX")
    MACHINFO="/usr/contrib/bin/machinfo"
    
    OS=`${MACHINFO} | grep "Release" | "${AWK}" '{print $2,$3}'`
    OS_ARCH=`uname -m`
    
    HPVM_TYPE=`cat -s /etc/rc.config.d/hpvmconf | grep -i "HPVM_ENABLE" | cut -d '=' -f2`
    if [ "${HPVM_TYPE}" -eq '1' ]
    then
      MACHINE_TYPE=VM
    else
      MACHINE_TYPE=Unknown
    fi
    
    MEMORY_SIZE=`${MACHINFO} | grep "Memory" | "${AWK}" '{print $2,$3}'`
    HW_VENDOR=`${MACHINFO} | grep "Model:" | cut -d '"' -f2`
    PROCESSOR_VERSION=`${MACHINFO} | grep -i processor | head -1 | sed 's/^ *//'`
    
    vTMP=`${MACHINFO} | grep '[0-9] cores.*logical'`
    PHYSICAL_CORES_OS=`${MACHINFO} | grep "[0-9] cores (" | "${AWK}" '{print $1}'`
    LOGICAL_CORES_OS=`echo ${vTMP} | "${AWK}" '{print $3}'`
    CPU_CORE_COUNT_OS=`echo ${vTMP} | "${AWK}" '{print $1}'`
    CPU_SOCKET_COUNT_OS=`${MACHINFO} | grep "[0-9] socket" | "${AWK}" '{print $1}'`
    
    if [ "${PHYSICAL_CORES_OS}" -eq "${LOGICAL_CORES_OS}" ]
    then
      HYPERTHREADING=OFF
    else
      HYPERTHREADING=ON
    fi
	;;
  "SunOS")
    OS=`/usr/bin/showrev | grep 'Kernel version' | "${AWK}" '{print $3,$4}'`
    OS_ARCH=`uname -i`
    MACHINE_TYPE=`uname -v`
    MEMORY_SIZE=`/usr/sbin/prtconf 2>/dev/null | grep "Memory size" | "${AWK}" '{print $3,$4}'`
    HW_VENDOR=`/usr/bin/showrev | grep 'Hardware provider' | "${AWK}" '{print $3}'`
    PROCESSOR_VERSION=`/usr/sbin/psrinfo -pv | grep -v "physical processor" | head -1 | "${AWK}" '{print $1}'`
    PHYSICAL_CORES_OS=`/usr/bin/kstat -m cpu_info | grep -w core_id | uniq | wc -l | sed 's/ //g'`
    
    if [ "${PHYSICAL_CORES_OS}" -eq 0 ]
    then
      PHYSICAL_CORES_OS=`/usr/sbin/psrinfo | wc -l | sed 's/ //g'`
    fi
    
    LOGICAL_CORES_OS=`/usr/sbin/psrinfo | wc -l | sed 's/ //g'`
    CPU_SOCKET_COUNT_OS=`/usr/sbin/psrinfo -p`
    CPU_CORE_COUNT_OS=`expr ${PHYSICAL_CORES_OS} \/ ${CPU_SOCKET_COUNT_OS}`
	
    if [ "${PHYSICAL_CORES_OS}" -eq "${LOGICAL_CORES_OS}" ]
    then
      HYPERTHREADING=OFF
    else
      HYPERTHREADING=ON
    fi
	;;
  "AIX")
    echo "AIX is not support."
	exit
	;;
  *)
    echo "ERROR: Unknown operation system."
	exit -1
	;;
  esac
  
  # Uptime (days)
  UPTIME=`uptime | "${AWK}" '{print $3}'`

  { # Insert to output file
    echo $recsep
    echo "##@ OScommon"
    echo "HOSTNAME:${HOSTNAME}"
    echo "OS:${OS}"
    echo "OS_ARCH:${OS_ARCH}"
    echo "MEMORY_SIZE:${MEMORY_SIZE}"
    echo "MACHINE_TYPE:${MACHINE_TYPE}"
	echo "HW_VENDOR:${HW_VENDOR}"
    echo "PROCESSOR_VERSION:${PROCESSOR_VERSION}"
    echo "PHYSICAL_CORES_OS:${PHYSICAL_CORES_OS}"
    echo "LOGICAL_CORES_OS:${LOGICAL_CORES_OS}"
    echo "CPU_CORE_COUNT_OS:${CPU_CORE_COUNT_OS}"
    echo "CPU_SOCKET_COUNT_OS:${CPU_SOCKET_COUNT_OS}"
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
    if [ "${PLATFORM}" = "HP-UX" ]
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
    echo "#$ /etc/hosts"
    /bin/cat /etc/hosts
  } >> "${OUTPUT}" 2>&1
}

### Network information
OSnetwork () {
  { # Insert to output file
    echo $recsep
    echo "##@ OSnetwork"
    echo "#$ ifconfig -a"
    /sbin/ifconfig -a
    echo "#$ netstat -ni"
    /bin/netstat -in
    echo "#$ netstat -nr"
    /bin/netstat -rn
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
  typeset SQLoracle_general_9i SQLoracle_general_10gR2 SQLoracle_general_11R2_later
  
  SQLoracle_general_9i="
   SELECT HOST_NAME      || '|' ||
          INSTANCE_NAME  || '|' ||
          DATABASE_NAME  || '|' ||
          OPEN_MODE      || '|' ||
          DATABASE_ROLE  || '|' ||
          CREATED        || '|' ||
          DBID           || '|' ||
          VERSION        || '|' ||
          BANNER         || '|' ||
          'NONE'         || '|' ||
          'NONE'         || '|' ||
          'NONE'         || '|' ||
          'NONE'         || '|' ||
          'NONE'         || '|' ||
          'NONE'         || '|' ||
          'NONE'         || '|' ||
          'NONE' AS \"DB_GENERAL\"
      FROM
        (SELECT I.HOST_NAME
	          , i.INSTANCE_NAME
	    	  , D.NAME AS DATABASE_NAME
	    	  , D.OPEN_MODE
	    	  , D.DATABASE_ROLE
	    	  , D.CREATED
	    	  , D.DBID
	    	  , I.VERSION
	    	  , V.BANNER
           FROM V\$INSTANCE I, V\$DATABASE D, V\$VERSION V
          WHERE V.BANNER LIKE 'Oracle%' or V.BANNER like 'Personal Oracle%' AND ROWNUM < 2
	    );
   "
  
  SQLoracle_general_10gR2="
   ALTER SESSION SET NLS_DATE_FORMAT='YYYY-MM-DD HH24:MI:SS';
   define DCID=-1
   SELECT HOST_NAME                || '|' ||
          INSTANCE_NAME            || '|' ||
          DATABASE_NAME            || '|' ||
          OPEN_MODE                || '|' ||
          DATABASE_ROLE            || '|' ||
          CREATED                  || '|' ||
          DBID                     || '|' ||
          VERSION                  || '|' ||
          BANNER                   || '|' ||
          PHYSICAL_CPUS            || '|' ||
          LOGICAL_CPUS             || '|' ||
          LAST_DBA_FUS_DBID        || '|' ||
          LAST_DBA_FUS_VERSION     || '|' ||
          LAST_DBA_FUS_SAMPLE_DATE || '|' ||
          REMARKS                  || '|' ||
          'NONE'                   || '|' ||
          'NONE' AS \"DB_GENERAL\"
     FROM
       (SELECT I.HOST_NAME
             , i.INSTANCE_NAME
             , D.NAME AS DATABASE_NAME
             , D.OPEN_MODE
             , D.DATABASE_ROLE
             , D.CREATED
             , D.DBID
             , I.VERSION
             , V.BANNER
          FROM V\$INSTANCE I, V\$DATABASE D, V\$VERSION V
         WHERE V.BANNER LIKE 'Oracle%' or V.BANNER like 'Personal Oracle%' AND ROWNUM < 2) A,
       (SELECT CPU_CORE_COUNT_CURRENT as \"PHYSICAL_CPUS\", CPU_COUNT_CURRENT as \"LOGICAL_CPUS\" FROM V\$LICENSE) B,
       (select distinct &&DCID as CON_ID,
               first_value (DBID            ) over (partition by &&DCID order by last_sample_date desc nulls last) as last_dba_fus_dbid,
               first_value (VERSION         ) over (partition by &&DCID order by last_sample_date desc nulls last) as last_dba_fus_version,
               first_value (LAST_SAMPLE_DATE) over (partition by &&DCID order by last_sample_date desc nulls last) as last_dba_fus_sample_date,
               sysdate,
               case when (select trim(max(LAST_SAMPLE_DATE) || max(TOTAL_SAMPLES)) from DBA_FEATURE_USAGE_STATISTICS) = '0'
                    then 'NEVER SAMPLED !!!'
                    else ''
               end as REMARKS
          from DBA_FEATURE_USAGE_STATISTICS
	   ) C;
   "
  
  SQLoracle_general_11R2_later="
   ALTER SESSION SET NLS_DATE_FORMAT='YYYY-MM-DD HH24:MI:SS';   
   define DCID=-1
   SELECT HOST_NAME                      || '|' ||
          INSTANCE_NAME                  || '|' ||
          DATABASE_NAME                  || '|' ||
          OPEN_MODE                      || '|' ||
          DATABASE_ROLE                  || '|' ||
          CREATED                        || '|' ||
          DBID                           || '|' ||
          VERSION                        || '|' ||
          BANNER                         || '|' ||
          PHYSICAL_CPUS                  || '|' ||
          LOGICAL_CPUS                   || '|' ||
          LAST_DBA_FUS_DBID              || '|' ||
          LAST_DBA_FUS_VERSION           || '|' ||
          LAST_DBA_FUS_SAMPLE_DATE       || '|' ||
          REMARKS                        || '|' ||
          CONTROL_MANAGEMENT_PACK_ACCESS || '|' ||
          ENABLE_DDL_LOGGING AS \"DB_GENERAL\"
     FROM
       (SELECT I.HOST_NAME
             , i.INSTANCE_NAME
             , D.NAME AS DATABASE_NAME
             , D.OPEN_MODE
             , D.DATABASE_ROLE
             , D.CREATED
             , D.DBID
             , I.VERSION
             , V.BANNER
          FROM V\$INSTANCE I, V\$DATABASE D, V\$VERSION V
         WHERE V.BANNER LIKE 'Oracle%' or V.BANNER like 'Personal Oracle%' AND ROWNUM < 2) A,
       (SELECT CPU_CORE_COUNT_CURRENT as \"PHYSICAL_CPUS\", CPU_COUNT_CURRENT as \"LOGICAL_CPUS\" FROM V\$LICENSE) B,
       (select distinct &&DCID as CON_ID,
               first_value (DBID            ) over (partition by &&DCID order by last_sample_date desc nulls last) as last_dba_fus_dbid,
               first_value (VERSION         ) over (partition by &&DCID order by last_sample_date desc nulls last) as last_dba_fus_version,
               first_value (LAST_SAMPLE_DATE) over (partition by &&DCID order by last_sample_date desc nulls last) as last_dba_fus_sample_date,
               sysdate,
               case when (select trim(max(LAST_SAMPLE_DATE) || max(TOTAL_SAMPLES)) from DBA_FEATURE_USAGE_STATISTICS) = '0'
                    then 'NEVER SAMPLED !!!'
                    else ''
               end as REMARKS
          from DBA_FEATURE_USAGE_STATISTICS) C,
       (SELECT VALUE AS \"CONTROL_MANAGEMENT_PACK_ACCESS\" FROM V\$PARAMETER WHERE LOWER(NAME) IN ('control_management_pack_access')) D,
      (SELECT VALUE AS \"ENABLE_DDL_LOGGING\" FROM V\$PARAMETER WHERE LOWER(NAME) IN ('enable_ddl_logging')) E;
   "

  if [ "${ORACLE_MAJOR_VERSION}" -eq 9 ]
  then
    Cmd_sqlplus "${COMMON_VAL}" "${SQLoracle_general_9i}" > ${RESULT}
  elif [ "${ORACLE_MAJOR_VERSION}" -eq 10 ]
  then
    Cmd_sqlplus "${COMMON_VAL}" "${SQLoracle_general_10gR2}" > ${RESULT}
  elif [ "${ORACLE_MAJOR_VERSION}" -ge 11 ]
  then
    Cmd_sqlplus "${COMMON_VAL}" "${SQLoracle_general_11R2_later}" > ${RESULT}
  else
    Print_log "This script is for 9.2 and later."
    exit
  fi

  # Result to Value
  Set_general_var

  { # Insert to output file
    echo $recsep
    echo "##@ ORAoption_general"
	echo "HOST_NAME:$HOST_NAME"                     
	echo "INSTANCE_NAME:$INSTANCE_NAME"                 
	echo "DATABASE_NAME:$DATABASE_NAME"                 
	echo "OPEN_MODE:$OPEN_MODE"                     
	echo "DATABASE_ROLE:$DATABASE_ROLE"                 
	echo "CREATED:$CREATED"                       
	echo "DBID:$DBID"                          
	echo "VERSION:$VERSION"                       
	echo "BANNER:$BANNER"                        
	echo "PHYSICAL_CPUS_DB:$PHYSICAL_CPUS_DB"              
	echo "LOGICAL_CPUS_DB:$LOGICAL_CPUS_DB"               
	echo "LAST_DBA_FUS_DBID:$LAST_DBA_FUS_DBID"             
	echo "LAST_DBA_FUS_VERSION:$LAST_DBA_FUS_VERSION"          
	echo "LAST_DBA_FUS_SAMPLE_DATE:$LAST_DBA_FUS_SAMPLE_DATE"      
	echo "REMARKS:$REMARKS"                       
	echo "CONTROL_MANAGEMENT_PACK_ACCESS:$CONTROL_MANAGEMENT_PACK_ACCESS"
	echo "ENABLE_DDL_LOGGING:$ENABLE_DDL_LOGGING"
  } >> "${OUTPUT}" 2>&1
}

Set_general_var () {
  Check_general_var ${RESULT} "HOST_NAME"                       1
  Check_general_var ${RESULT} "INSTANCE_NAME"                   2
  Check_general_var ${RESULT} "DATABASE_NAME"                   3
  Check_general_var ${RESULT} "OPEN_MODE"                       4
  Check_general_var ${RESULT} "DATABASE_ROLE"                   5
  Check_general_var ${RESULT} "CREATED"                         6
  Check_general_var ${RESULT} "DBID"                            7
  Check_general_var ${RESULT} "VERSION"                         8
  Check_general_var ${RESULT} "BANNER"                          9
  Check_general_var ${RESULT} "PHYSICAL_CPUS_DB"               10
  Check_general_var ${RESULT} "LOGICAL_CPUS_DB"                11
  Check_general_var ${RESULT} "LAST_DBA_FUS_DBID"              12
  Check_general_var ${RESULT} "LAST_DBA_FUS_VERSION"           13
  Check_general_var ${RESULT} "LAST_DBA_FUS_SAMPLE_DATE"       14
  Check_general_var ${RESULT} "REMARKS"                        15
  Check_general_var ${RESULT} "CONTROL_MANAGEMENT_PACK_ACCESS" 16
  Check_general_var ${RESULT} "ENABLE_DDL_LOGGING"             17
}

Check_general_var () {
  typeset option
  option=`cut -d"|" -f"${3}" ${RESULT}`
  eval "$2"='"${option}"'    # Insert "\" because the space of ${option}
}

### Check Oracle ULA option
ORAoption_ULA () {
  typeset SQLoracle_option_9i SQLoracle_option_10R2_later
  
  SQLoracle_option_9i="
   ALTER SESSION SET NLS_DATE_FORMAT='YYYY-MM-DD HH24:MI:SS';
   SELECT SYSDATE                                                                        || '|' ||
          '0'                                                                            || '|' ||
          '0'                                                                            || '|' ||
          (SELECT HOST_NAME FROM V\$INSTANCE)                                            || '|' ||
          DECODE(PARAMETER,
                 'OLAP',                      'OLAP',
                 'Partitioning',              'Partitioning',
                 'Real Application Clusters', 'Real Application Clusters',
                 'Spatial',                   'Spatial and Graph'
                )                                                                        || '|' ||
          DECODE(VALUE, 'TRUE', 'PAST_OR_CURRENT_USAGE', 'FALSE', 'NO_USAGE', 'UNKNOWN') || '|' ||
          '0' AS \"DB_OPTION\"
     FROM V\$OPTION
    WHERE PARAMETER IN ('OLAP', 'Partitioning', 'Real Application Clusters', 'Spatial')
    ORDER BY VALUE;
   "
  
  SQLoracle_option_10R2_later="
   ALTER SESSION SET NLS_DATE_FORMAT='YYYY-MM-DD HH24:MI:SS';
   
   with
   MAP as (
   -- mapping between features tracked by DBA_FUS and their corresponding database products (options or packs)
   select '' PRODUCT, '' feature, '' MVERSION, '' CONDITION from dual union all
   SELECT 'Active Data Guard'                                   , 'Active Data Guard - Real-Time Query on Physical Standby' , '^10\.2|^11\.2|^1[289]\.|^2[0-9]\.'            , ' '       from dual union all
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
   SELECT 'Advanced Security'                                   , 'ASO native encryption and checksumming'                  , '^10\.2|^11\.2|^1[289]\.|^2[0-9]\.'            , 'INVALID' from dual union all -- no longer part of Advanced Security
   SELECT 'Advanced Security'                                   , 'Backup Encryption'                                       , '^10\.2|^11\.2'                                , ' '       from dual union all
   SELECT 'Advanced Security'                                   , 'Backup Encryption'                                       , '^1[289]\.|^2[0-9]\.'                          , 'INVALID' from dual union all -- licensing required only by encryption to disk
   SELECT 'Advanced Security'                                   , 'Data Redaction'                                          , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Advanced Security'                                   , 'Encrypted Tablespaces'                                   , '^10\.2|^11\.2|^1[289]\.|^2[0-9]\.'            , ' '       from dual union all
   SELECT 'Advanced Security'                                   , 'Oracle Utility Datapump (Export)'                        , '^10\.2|^11\.2|^1[289]\.|^2[0-9]\.'            , 'C002'    from dual union all
   SELECT 'Advanced Security'                                   , 'Oracle Utility Datapump (Import)'                        , '^10\.2|^11\.2|^1[289]\.|^2[0-9]\.'            , 'C002'    from dual union all
   SELECT 'Advanced Security'                                   , 'SecureFile Encryption (user)'                            , '^10\.2|^11\.2|^1[289]\.|^2[0-9]\.'            , ' '       from dual union all
   SELECT 'Advanced Security'                                   , 'Transparent Data Encryption'                             , '^10\.2|^11\.2|^1[289]\.|^2[0-9]\.'            , ' '       from dual union all
   SELECT 'Change Management Pack'                              , 'Change Management Pack'                                  , '^10\.2|^11\.2'                                , ' '       from dual union all
   SELECT 'Configuration Management Pack for Oracle Database'   , 'EM Config Management Pack'                               , '^10\.2|^11\.2'                                , ' '       from dual union all
   SELECT 'Data Masking Pack'                                   , 'Data Masking Pack'                                       , '^10\.2|^11\.2'                                , ' '       from dual union all
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
   SELECT 'Database Vault'                                      , 'Oracle Database Vault'                                   , '^10\.2|^11\.2|^1[289]\.|^2[0-9]\.'            , ' '       from dual union all
   SELECT 'Database Vault'                                      , 'Privilege Capture'                                       , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Diagnostics Pack'                                    , 'ADDM'                                                    , '^10\.2|^11\.2|^1[289]\.|^2[0-9]\.'            , ' '       from dual union all
   SELECT 'Diagnostics Pack'                                    , 'AWR Baseline'                                            , '^10\.2|^11\.2|^1[289]\.|^2[0-9]\.'            , ' '       from dual union all
   SELECT 'Diagnostics Pack'                                    , 'AWR Baseline Template'                                   , '^10\.2|^11\.2|^1[289]\.|^2[0-9]\.'            , ' '       from dual union all
   SELECT 'Diagnostics Pack'                                    , 'AWR Report'                                              , '^10\.2|^11\.2|^1[289]\.|^2[0-9]\.'            , ' '       from dual union all
   SELECT 'Diagnostics Pack'                                    , 'Automatic Workload Repository'                           , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Diagnostics Pack'                                    , 'Baseline Adaptive Thresholds'                            , '^10\.2|^11\.2|^1[289]\.|^2[0-9]\.'            , ' '       from dual union all
   SELECT 'Diagnostics Pack'                                    , 'Baseline Static Computations'                            , '^10\.2|^11\.2|^1[289]\.|^2[0-9]\.'            , ' '       from dual union all
   SELECT 'Diagnostics Pack'                                    , 'Diagnostic Pack'                                         , '^10\.2|^11\.2'                                , ' '       from dual union all
   SELECT 'Diagnostics Pack'                                    , 'EM Performance Page'                                     , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT '.Exadata'                                            , 'Cloud DB with EHCC'                                      , '^10\.2|^11\.2|^1[289]\.|^2[0-9]\.'            , ' '       from dual union all
   SELECT '.Exadata'                                            , 'Exadata'                                                 , '^10\.2|^11\.2|^1[289]\.|^2[0-9]\.'            , ' '       from dual union all
   SELECT '.GoldenGate'                                         , 'GoldenGate'                                              , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT '.HW'                                                 , 'Hybrid Columnar Compression'                             , '^12\.1'                                       , 'BUG'     from dual union all
   SELECT '.HW'                                                 , 'Hybrid Columnar Compression'                             , '^12\.[2-9]|^1[89]\.|^2[0-9]\.'                , ' '       from dual union all
   SELECT '.HW'                                                 , 'Hybrid Columnar Compression Conventional Load'           , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT '.HW'                                                 , 'Hybrid Columnar Compression Row Level Locking'           , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT '.HW'                                                 , 'ODA Infrastructure'                                       , '^1[9]\.|^2[0-9]\.'                           , ' '       from dual union all
   SELECT '.HW'                                                 , 'Sun ZFS with EHCC'                                       , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT '.HW'                                                 , 'ZFS Storage'                                             , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT '.HW'                                                 , 'Zone maps'                                               , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Label Security'                                      , 'Label Security'                                          , '^10\.2|^11\.2|^1[289]\.|^2[0-9]\.'            , ' '       from dual union all
   SELECT 'Multitenant'                                         , 'Oracle Multitenant'                                      , '^1[28]\.'                                     , 'C003'    from dual union all -- licensing required only when more than one PDB containers are created
   SELECT 'Multitenant'                                         , 'Oracle Multitenant'                                      , '^1[9]\.|^2[0-9]\.'                            , 'C005'    from dual union all -- licensing required only when more than three PDB containers are created
   SELECT 'Multitenant'                                         , 'Oracle Pluggable Databases'                              , '^1[28]\.'                                     , 'C003'    from dual union all -- licensing required only when more than one PDB containers are created
   SELECT 'OLAP'                                                , 'OLAP - Analytic Workspaces'                              , '^10\.2|^11\.2|^1[289]\.|^2[0-9]\.'            , ' '       from dual union all
   SELECT 'OLAP'                                                , 'OLAP - Cubes'                                            , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Partitioning'                                        , 'Partitioning (user)'                                     , '^10\.2|^11\.2|^1[289]\.|^2[0-9]\.'            , ' '       from dual union all
   SELECT 'Partitioning'                                        , 'Zone maps'                                               , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT '.Pillar Storage'                                     , 'Pillar Storage'                                          , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT '.Pillar Storage'                                     , 'Pillar Storage with EHCC'                                , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT '.Provisioning and Patch Automation Pack'             , 'EM Standalone Provisioning and Patch Automation Pack'    , '^10\.2|^11\.2'                                , ' '       from dual union all
   SELECT 'Provisioning and Patch Automation Pack for Database' , 'EM Database Provisioning and Patch Automation Pack'      , '^10\.2|^11\.2'                                , ' '       from dual union all
   SELECT 'RAC or RAC One Node'                                 , 'Quality of Service Management'                           , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Real Application Clusters'                           , 'Real Application Clusters (RAC)'                         , '^10\.2|^11\.2|^1[289]\.|^2[0-9]\.'            , ' '       from dual union all
   SELECT 'Real Application Clusters One Node'                  , 'Real Application Cluster One Node'                       , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Real Application Testing'                            , 'Database Replay: Workload Capture'                       , '^11\.2|^1[289]\.|^2[0-9]\.'                   , 'C004'    from dual union all
   SELECT 'Real Application Testing'                            , 'Database Replay: Workload Replay'                        , '^11\.2|^1[289]\.|^2[0-9]\.'                   , 'C004'    from dual union all
   SELECT 'Real Application Testing'                            , 'SQL Performance Analyzer'                                , '^11\.2|^1[289]\.|^2[0-9]\.'                   , 'C004'    from dual union all
   SELECT '.Secure Backup'                                      , 'Oracle Secure Backup'                                    , '^1[289]\.|^2[0-9]\.'                          , 'INVALID' from dual union all  -- does not differentiate usage of Oracle Secure Backup Express, which is free
   SELECT 'Spatial and Graph'                                   , 'Spatial'                                                 , '^10\.2|^11\.2'                                , 'INVALID' from dual union all  -- does not differentiate usage of Locator, which is free
   SELECT 'Spatial and Graph'                                   , 'Spatial'                                                 , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Tuning Pack'                                         , 'Automatic Maintenance - SQL Tuning Advisor'              , '^1[289]\.|^2[0-9]\.'                          , 'INVALID' from dual union all  -- system usage in the maintenance window
   SELECT 'Tuning Pack'                                         , 'Automatic SQL Tuning Advisor'                            , '^10\.2|^11\.2|^1[289]\.|^2[0-9]\.'            , 'INVALID' from dual union all  -- system usage in the maintenance window
   SELECT 'Tuning Pack'                                         , 'Real-Time SQL Monitoring'                                , '^10\.2|^11\.2'                                , ' '       from dual union all
   SELECT 'Tuning Pack'                                         , 'Real-Time SQL Monitoring'                                , '^1[289]\.|^2[0-9]\.'                          , 'INVALID' from dual union all  -- default
   SELECT 'Tuning Pack'                                         , 'SQL Access Advisor'                                      , '^10\.2|^11\.2|^1[289]\.|^2[0-9]\.'            , ' '       from dual union all
   SELECT 'Tuning Pack'                                         , 'SQL Monitoring and Tuning pages'                         , '^1[289]\.|^2[0-9]\.'                          , ' '       from dual union all
   SELECT 'Tuning Pack'                                         , 'SQL Profile'                                             , '^10\.2|^11\.2|^1[289]\.|^2[0-9]\.'            , ' '       from dual union all
   SELECT 'Tuning Pack'                                         , 'SQL Tuning Advisor'                                      , '^10\.2|^11\.2|^1[289]\.|^2[0-9]\.'            , ' '       from dual union all
   SELECT 'Tuning Pack'                                         , 'SQL Tuning Set (user)'                                   , '^1[289]\.|^2[0-9]\.'                          , 'INVALID' from dual union all -- no longer part of Tuning Pack
   SELECT 'Tuning Pack'                                         , 'Tuning Pack'                                             , '^10\.2|^11\.2'                                , ' '       from dual union all
   SELECT '.WebLogic Server Management Pack Enterprise Edition' , 'EM AS Provisioning and Patch Automation Pack'            , '^10\.2|^11\.2'                                , ' '       from dual union all
   select '' PRODUCT, '' FEATURE, '' MVERSION, '' CONDITION from dual
   ),
   FUS as (
   -- the current data set to be used: DBA_FEATURE_USAGE_STATISTICS or CDB_FEATURE_USAGE_STATISTICS for Container Databases(CDBs)
   select
       0 as CON_ID,
       (select host_name  from v\$instance) as CON_NAME,
       -- Detect and mark with Y the current DBA_FUS data set = Most Recent Sample based on LAST_SAMPLE_DATE
         case when DBID || '#' || VERSION || '#' || to_char(LAST_SAMPLE_DATE, 'YYYYMMDDHH24MISS') =
                   first_value (DBID    )         over (partition by 0 order by LAST_SAMPLE_DATE desc nulls last, DBID desc) || '#' ||
                   first_value (VERSION )         over (partition by 0 order by LAST_SAMPLE_DATE desc nulls last, DBID desc) || '#' ||
                   first_value (to_char(LAST_SAMPLE_DATE, 'YYYYMMDDHH24MISS'))
                                                  over (partition by 0 order by LAST_SAMPLE_DATE desc nulls last, DBID desc)
              then 'Y'
              else 'N'
       end as CURRENT_ENTRY,
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
   WHERE LAST_SAMPLE_PERIOD <> 0
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
             when     detected_usages > 0                 -- some usage detection - current or past
                  and CURRENTLY_USED = 'TRUE'             -- usage at LAST_SAMPLE_DATE
                  and CURRENT_ENTRY  = 'Y'                -- current record set
                  and (    trim(CONDITION) is null        -- no extra conditions
                        or CONDITION_MET     = 'TRUE'     -- extra condition is met
                       and CONDITION_COUNTER = 'FALSE' )  -- extra condition is not based on counter
                  then '6.CURRENT_USAGE'
             when     detected_usages > 0                 -- some usage detection - current or past
                  and CURRENTLY_USED = 'TRUE'             -- usage at LAST_SAMPLE_DATE
                  and CURRENT_ENTRY  = 'Y'                -- current record set
                  and (    CONDITION_MET     = 'TRUE'     -- extra condition is met
                       and CONDITION_COUNTER = 'TRUE'  )  -- extra condition is     based on counter
                  then '5.PAST_OR_CURRENT_USAGE'          -- FEATURE_INFO counters indicate current or past usage
             when     detected_usages > 0                 -- some usage detection - current or past
                  and (    trim(CONDITION) is null        -- no extra conditions
                        or CONDITION_MET     = 'TRUE'  )  -- extra condition is met
                  then '4.PAST_USAGE'
             when CURRENT_ENTRY = 'Y'
                  then '2.NO_CURRENT_USAGE'   -- detectable feature shows no current usage
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
                when CONDITION = 'C005' and CON_ID=1 and AUX_COUNT > 3
                     then 'TRUE'  -- more than three PDBs are created
                when CONDITION = 'C004' and 'OCS'= 'N'
                     then 'TRUE'  -- not in oracle cloud
                else 'FALSE'
          end as CONDITION_MET,
          -- check if the extra conditions are based on FEATURE_INFO counters. They indicate current or past usage.
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
               when CONDITION = 'C005'
                    then   'AUX_COUNT=' || AUX_COUNT
               when CONDITION = 'C004' and 'OCS'= 'Y'
                    then   'feature included in Oracle Cloud Services Package'
               else ''
          end as EXTRA_FEATURE_INFO,
          f.CON_ID          ,
          f.CON_NAME        ,
          f.CURRENT_ENTRY   ,
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
       and not (CONDITION in ('C003', 'C005') and CON_ID not in (0, 1))  -- multiple PDBs are visible only in CDB\$ROOT; PDB level view is not relevant
   )
   select
       to_char(sysdate,'yyyy-mm-dd hh24:mi:ss') || '|' ||
       grouping_id(CON_ID) || '|' ||
       CON_ID || '|' ||
       decode(grouping_id(CON_ID), 1, '--ALL--', max(CON_NAME)) || '|' ||
       PRODUCT || '|' ||
       decode(max(USAGE),
             '1.NO_PAST_USAGE'        , 'NO_USAGE'             ,
             '2.NO_CURRENT_USAGE'     , 'NO_USAGE'             ,
             '3.SUPPRESSED_DUE_TO_BUG', 'SUPPRESSED_DUE_TO_BUG',
             '4.PAST_USAGE'           , 'PAST_USAGE'           ,
             '5.PAST_OR_CURRENT_USAGE', 'PAST_OR_CURRENT_USAGE',
             '6.CURRENT_USAGE'        , 'CURRENT_USAGE'        ,
             'UNKNOWN') || '|' ||
       max(LAST_SAMPLE_DATE) || '|' ||
       min(FIRST_USAGE_DATE) || '|' ||
       max(LAST_USAGE_DATE) AS \"DB_OPTION\"
     from PFUS
     where USAGE in ('2.NO_CURRENT_USAGE', '4.PAST_USAGE', '5.PAST_OR_CURRENT_USAGE', '6.CURRENT_USAGE')   -- ignore '1.NO_PAST_USAGE', '3.SUPPRESSED_DUE_TO_BUG'
     group by rollup(CON_ID), PRODUCT
     having not (max(CON_ID) in (-1, 0) and grouping_id(CON_ID) = 1)            -- aggregation not needed for non-container databases
     ;
   "
  
  if [ "${ORACLE_MAJOR_VERSION}" -eq 9 ]
  then
    Cmd_sqlplus "${COMMON_VAL}" "${SQLoracle_option_9i}" > ${RESULT}
  elif [ "${ORACLE_MAJOR_VERSION}" -ge 10 ]
  then
    Cmd_sqlplus "${COMMON_VAL}" "${SQLoracle_option_10R2_later}" > ${RESULT}
  else
    Print_log "This script is for 9.2 and later."
    exit
  fi

  # Result to Value
  Set_option_var

  { # Insert to output file
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
    echo "ADVANCED_COMPRESSION:${AC}"
    echo "ADVANCED_SECURITY:${AS}"
    echo "DATABASE_INMEMORY:${DIM}"
    echo "DATABASE_VAULT:${DV}"
    echo "DIAGNOSTICS_PACK:${DP}"
    echo "LABEL_SECURITY:${LS}"
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
	if [ "${PLATFORM}" = "SunOS" ]
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

### Oracle Listener
ORAlistener () {
  typeset LISTENERs LISTENER_USER LISTENER_NAME ORACLE_HOME IFS

  { # Insert to output file
    echo $recsep
    echo "##@ ORAlistener"
    # (USER):(BINARY_PATH):(LISTENER_NAME)
    IFS=$'
	'	# IFS=$'\n' can be used POSIX
    LISTENERs=`ps -ef | grep tnslsnr | grep -v grep`
    for listener in ${LISTENERs}
    do
      LISTENER_USER=`echo "${listener}" | "${AWK}" '{print $1}'`
      LISTENER_NAME=`echo "${listener}" | "${AWK}" -F"/bin" '{print $2}' | "${AWK}" '{print $2}'`
      ORACLE_HOME=`echo "${listener}" | "${AWK}" -F"/bin" '{print $1}' | "${AWK}" '{print $NF}'`
      echo "#$ ${LISTENER_USER}:${ORACLE_HOME}:${LISTENER_NAME}"
      "${ORACLE_HOME}"/bin/lsnrctl status "${LISTENER_NAME}"
      echo
    done
  } >> "${OUTPUT}" 2>&1
}

### Oracle Listener Configuration
ORAlistener_ora () {
  { # Insert to output file
    echo $recsep
    echo "##@ ORAlistener_ora"
	# $GRID_USER is not null
    if [ -n "${GRID_USER}" ]
    then
      echo "#$ listener.ora"
      /bin/cat "${GRID_HOME}"/network/admin/listener.ora
      echo "#$ sqlnet.ora"
      /bin/cat "${GRID_HOME}"/network/admin/sqlnet.ora
      echo "#$ tnsnames.ora"
      /bin/cat "${GRID_HOME}"/network/admin/tnsnames.ora
    fi
	
    echo "#$ listener.ora"
    /bin/cat "${ORACLE_HOME}"/network/admin/listener.ora
    echo "#$ sqlnet.ora"
    /bin/cat "${ORACLE_HOME}"/network/admin/sqlnet.ora
    echo "#$ tnsnames.ora"
    /bin/cat "${ORACLE_HOME}"/network/admin/tnsnames.ora
  } >> "${OUTPUT}" 2>&1
}

### Collect parameter file
ORApfile () {
  typeset SQLspfile SQLcreate_pfile SPFILE
  
  SQLspfile="select value from v\$parameter where name='spfile';"
  SQLcreate_pfile="create pfile='${RESULT}' from spfile;"
  SPFILE=`Cmd_sqlplus "${COMMON_VAL}" "${SQLspfile}"`

  { # Insert to output file
    echo $recsep
    echo "##@ ORApfile"
    echo "SPFILE:$SPFILE"
    echo
  } >> "${OUTPUT}" 2>&1
  
  # Create pfile if spfile mode
  if [ -n "${SPFILE}" ]
  then
    Cmd_sqlplus "${COMMON_VAL}" "${SQLcreate_pfile}"
    /bin/cat "${RESULT}" >> "${OUTPUT}" 2>&1
  # Copy pfile if pfile mode
  else
    /bin/cat "${ORACLE_HOME}/dbs/init${ORACLE_SID}.ora" >> "${OUTPUT}" 2>&1
  fi
}

### Backup control file
ORAcontrol () {
  typeset SQLbackup
  
  SQLbackup="alter database backup controlfile to trace as '${RESULT}' reuse;"
  Cmd_sqlplus "${COMMON_VAL}" "${SQLbackup}"

  { # Insert to output file
    echo $recsep
    echo "##@ ORAcontrol"
    grep -v '^--' "${RESULT}"
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
  prompt #$ Datafiles
  $SQLdatafile
  prompt #$ Tempfiles
  $SQLtempfile
  prompt #$ Total free
  $SQLtotal_free
  prompt #$ Temp free
  $SQLtemp_free
  exit
EOF
}

### Collect database users
ORAdbuser () {
  typeset SQLusers
  SQLusers="
   col username for a25
   col default_tablespace for a15
   col temporary_tablespace for a10
   col account_status for a17
   select username
        , default_tablespace
        , temporary_tablespace
        , account_status
     from dba_users
     order by 1;
   "

  { # Insert to output file
    echo $recsep
    echo "##@ ORAdbuser"
    Cmd_sqlplus "${COLLECT_VAL}" "${SQLusers}"
  } >> "${OUTPUT}" 2>&1
}

### Collect redo log files
ORAredo () {
  typeset SQLredo
  SQLredo="
   col member for a50
   col status for a10
   select b.thread#
        , a.group#
        , a.member
        , b.bytes/1024/1024 MB
        , b.status
        , b.sequence#
     from v\$logfile a
        , v\$log b
    where a.group#=b.group#
    order by 1,2; 
   "

  { # Insert to output file
    echo $recsep
    echo "##@ ORAredo"
    Cmd_sqlplus "${COLLECT_VAL}" "${SQLredo}"
  } >> "${OUTPUT}" 2>&1
}

### Collect redo switch count
ORAredo_switch () {
  typeset SQLredo_switch
  SQLredo_switch="
col \"Day\" for a10
col \"00\" for 999
col \"01\" for 999
col \"02\" for 999
col \"03\" for 999
col \"04\" for 999
col \"05\" for 999
col \"06\" for 999
col \"07\" for 999
col \"08\" for 999
col \"09\" for 999
col \"10\" for 999
col \"11\" for 999
col \"12\" for 999
col \"13\" for 999
col \"14\" for 999
col \"15\" for 999
col \"16\" for 999
col \"17\" for 999
col \"18\" for 999
col \"19\" for 999
col \"20\" for 999
col \"21\" for 999
col \"22\" for 999
col \"23\" for 999
col \"Per Day\" for 9999
select to_char(first_time,'YYYY/MM/DD') \"Day\", 
decode(sum(decode(substr(to_char(first_time,'HH24'),1,2),'00',1,0)),0,0,sum(decode(substr(to_char(first_time,'HH24'),1,2),'00',1,0))) \"00\", 
decode(sum(decode(substr(to_char(first_time,'HH24'),1,2),'01',1,0)),0,0,sum(decode(substr(to_char(first_time,'HH24'),1,2),'01',1,0))) \"01\", 
decode(sum(decode(substr(to_char(first_time,'HH24'),1,2),'02',1,0)),0,0,sum(decode(substr(to_char(first_time,'HH24'),1,2),'02',1,0))) \"02\", 
decode(sum(decode(substr(to_char(first_time,'HH24'),1,2),'03',1,0)),0,0,sum(decode(substr(to_char(first_time,'HH24'),1,2),'03',1,0))) \"03\", 
decode(sum(decode(substr(to_char(first_time,'HH24'),1,2),'04',1,0)),0,0,sum(decode(substr(to_char(first_time,'HH24'),1,2),'04',1,0))) \"04\", 
decode(sum(decode(substr(to_char(first_time,'HH24'),1,2),'05',1,0)),0,0,sum(decode(substr(to_char(first_time,'HH24'),1,2),'05',1,0))) \"05\", 
decode(sum(decode(substr(to_char(first_time,'HH24'),1,2),'06',1,0)),0,0,sum(decode(substr(to_char(first_time,'HH24'),1,2),'06',1,0))) \"06\", 
decode(sum(decode(substr(to_char(first_time,'HH24'),1,2),'07',1,0)),0,0,sum(decode(substr(to_char(first_time,'HH24'),1,2),'07',1,0))) \"07\", 
decode(sum(decode(substr(to_char(first_time,'HH24'),1,2),'08',1,0)),0,0,sum(decode(substr(to_char(first_time,'HH24'),1,2),'08',1,0))) \"08\", 
decode(sum(decode(substr(to_char(first_time,'HH24'),1,2),'09',1,0)),0,0,sum(decode(substr(to_char(first_time,'HH24'),1,2),'09',1,0))) \"09\", 
decode(sum(decode(substr(to_char(first_time,'HH24'),1,2),'10',1,0)),0,0,sum(decode(substr(to_char(first_time,'HH24'),1,2),'10',1,0))) \"10\", 
decode(sum(decode(substr(to_char(first_time,'HH24'),1,2),'11',1,0)),0,0,sum(decode(substr(to_char(first_time,'HH24'),1,2),'11',1,0))) \"11\", 
decode(sum(decode(substr(to_char(first_time,'HH24'),1,2),'12',1,0)),0,0,sum(decode(substr(to_char(first_time,'HH24'),1,2),'12',1,0))) \"12\", 
decode(sum(decode(substr(to_char(first_time,'HH24'),1,2),'13',1,0)),0,0,sum(decode(substr(to_char(first_time,'HH24'),1,2),'13',1,0))) \"13\", 
decode(sum(decode(substr(to_char(first_time,'HH24'),1,2),'14',1,0)),0,0,sum(decode(substr(to_char(first_time,'HH24'),1,2),'14',1,0))) \"14\", 
decode(sum(decode(substr(to_char(first_time,'HH24'),1,2),'15',1,0)),0,0,sum(decode(substr(to_char(first_time,'HH24'),1,2),'15',1,0))) \"15\", 
decode(sum(decode(substr(to_char(first_time,'HH24'),1,2),'16',1,0)),0,0,sum(decode(substr(to_char(first_time,'HH24'),1,2),'16',1,0))) \"16\", 
decode(sum(decode(substr(to_char(first_time,'HH24'),1,2),'17',1,0)),0,0,sum(decode(substr(to_char(first_time,'HH24'),1,2),'17',1,0))) \"17\", 
decode(sum(decode(substr(to_char(first_time,'HH24'),1,2),'18',1,0)),0,0,sum(decode(substr(to_char(first_time,'HH24'),1,2),'18',1,0))) \"18\", 
decode(sum(decode(substr(to_char(first_time,'HH24'),1,2),'19',1,0)),0,0,sum(decode(substr(to_char(first_time,'HH24'),1,2),'19',1,0))) \"19\", 
decode(sum(decode(substr(to_char(first_time,'HH24'),1,2),'20',1,0)),0,0,sum(decode(substr(to_char(first_time,'HH24'),1,2),'20',1,0))) \"20\", 
decode(sum(decode(substr(to_char(first_time,'HH24'),1,2),'21',1,0)),0,0,sum(decode(substr(to_char(first_time,'HH24'),1,2),'21',1,0))) \"21\", 
decode(sum(decode(substr(to_char(first_time,'HH24'),1,2),'22',1,0)),0,0,sum(decode(substr(to_char(first_time,'HH24'),1,2),'22',1,0))) \"22\", 
decode(sum(decode(substr(to_char(first_time,'HH24'),1,2),'23',1,0)),0,0,sum(decode(substr(to_char(first_time,'HH24'),1,2),'23',1,0))) \"23\", 
decode(sum(1),0,0,sum(1)) \"Per Day\" 
from v\$log_history 
where first_time >= trunc(sysdate-31) 
group by to_char(first_time,'YYYY/MM/DD')
order by to_char(first_time,'YYYY/MM/DD') desc;
"

  { # Insert to output file
    echo $recsep
    echo "##@ ORAredo_switch"
    Cmd_sqlplus "${COLLECT_VAL}" "${SQLredo_switch}"
  } >> "${OUTPUT}" 2>&1
}

### Collect count of event per day
ORAevent_count () {
  typeset SQLevent_count
  SQLevent_count="
   col sample_time for a12
   select to_char(SAMPLE_TIME,'yyyymmdd') ||':'|| count(*)
     from dba_hist_active_sess_history
	where sample_time > sysdate-7
    group by to_char(SAMPLE_TIME,'yyyymmdd')
    order by 1;
   "

  { # Insert to output file
    echo $recsep
    echo "##@ ORAevent_count"
    Cmd_sqlplus "${COMMON_VAL}" "${SQLevent_count}"
  } >> "${OUTPUT}" 2>&1
}

### Collect count of event
ORAevent_group () {
  typeset SQLevent_group
  SQLevent_group="
   select event ||'---'|| count(*)
     from dba_hist_active_sess_history
    where sample_time > sysdate-7
      and event is not null
    group by event
	having count(*) > 10
    order by count(*) desc;
   "

  { # Insert to output file
    echo $recsep
    echo "##@ ORAevent_group"
    Cmd_sqlplus "${COMMON_VAL}" "${SQLevent_group}"
  } >> "${OUTPUT}" 2>&1
}

### Oracle alert log (100 lines)
ORAalert () {
  typeset DIAG_DEST ALERT_LOG
  DIAG_DEST=`Cmd_sqlplus "${COMMON_VAL}" "select value from v\\\$parameter where name='diagnostic_dest';"`
  DATABASE_NAME=`Cmd_sqlplus "${COMMON_VAL}" "select name from v\\\$database;" | tr '[:upper:]' '[:lower:]'`
  ALERT_LOG="${DIAG_DEST}/diag/rdbms/${DATABASE_NAME}/${ORACLE_SID}/trace/alert_${ORACLE_SID}.log"
  
  { # Insert to output file
    echo $recsep
    echo "##@ ORAalert"
    if [ -f "${ALERT_LOG}" ]
    then
      /usr/bin/tail -100 "${ALERT_LOG}"
    fi
  } >> "${OUTPUT}" 2>&1
}

### Collect hidden parameter
ORAparameter () {
  typeset SQLparameter
  SQLparameter="select ksppinm||' '||ksppstvl from x\$ksppi a, x\$ksppsv b where a.indx=b.indx order by ksppinm;"

  { # Insert to output file
    echo $recsep
    echo "##@ ORAparameter"
    Cmd_sqlplus "${COMMON_VAL}" "${SQLparameter}"
  } >> "${OUTPUT}" 2>&1
}

### OS information
OSinfo () {
  { # Insert to output file
    echo $recsep
    echo "##@ OSinfo"
	if [ "${PLATFORM}" = "SunOS" ]
    then
	  echo "#$ psrinfo"
      /usr/sbin/psrinfo -pv
	  echo "\n#$ prtconf"
	  /usr/sbin/prtconf
    elif [ "${PLATFORM}" = "HP-UX" ]
	then
      /usr/contrib/bin/machinfo -v
    fi
  } >> "${OUTPUT}" 2>&1
}

### Logging error
Print_log () {
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
  OSnetwork
  #OSlimits
  #OSkernel_parameter
  #OSrpm
  #OSntp
  #OSnsswitch
  
  Check_sqlplus
  Check_version
  
  ORAoption_general
  ORAoption_ULA
  ORAcommon
  ORAosuser
  ORApatch
  #ORAprivilege
  #ORAjob
  #ORAcapacity
  #ORAetc
  ORAlistener
  ORAlistener_ora
  ORApfile
  ORAcontrol
  ORAfile
  ORAredo
  ORAredo_switch
  ORAevent_count
  ORAevent_group
  ORAalert
  ORAparameter
  
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
