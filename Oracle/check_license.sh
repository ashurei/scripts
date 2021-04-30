#!/bin/bash
########################################################
# Description : Check Oracle license feature
# Create DATE : 2021.04.20
# Last Update DATE : 2021.04.28 by ashurei
# Copyright (c) Technical Solution, 2021
########################################################

BINDIR="/tmp/oracle_license"

export LANG=C
DATE=$(date '+%Y%m%d')
SPOOL="${BINDIR}/result.log"
OUTPUT="${BINDIR}/$(hostname)_license_${DATE}.out"
LOG="${BINDIR}/$(hostname)_license_${DATE}.log"
GENERAL_RAW="db_general_check.rawdata"
OPTION_RAW="db_check.rawdata"

# ========== Functions ========== #
### OS Check
function Check_OS() {
  HOSTNAME=$(hostname)
  OS=$(cat /etc/redhat-release)
  OS_ARCH=$(uname -i)
  MEMORY_SIZE=$(grep MemTotal /proc/meminfo | awk '{printf "%.2f", $2/1024/1024}')
  CPU_MODEL=$(grep 'model name' /proc/cpuinfo | awk -F": " '{print $2}' | tail -1)
  CPU_COUNT=$(grep -c ^processor /proc/cpuinfo)
  CPU_CORE_COUNT=$(grep 'cpu cores' /proc/cpuinfo | awk -F": " '{print $2}' | tail -1)
  CPU_SOCKET_COUNT=$(grep 'physical id' /proc/cpuinfo | sort -u | wc -l)

  # Check Hyperthreading (If siblings is equal cpu_core*2, this server uses hyperthreading.)
  CPU_SIBLINGS=$(grep 'siblings' /proc/cpuinfo | awk -F": " '{print $2}' | tail -1)
  HYPERTHREADING=0
  if [ "${CPU_SIBLINGS}" -eq $((CPU_CORE_COUNT*2)) ]
  then
    HYPERTHREADING="HT"
  fi

  OS_CHECK_HEADER="HOSTNAME|OS|OS_ARCH|MEMORY_SIZE(GB)|CPU_MODEL|CPU_COUNT|CPU_CORE_COUNT|CPU_SOCKET_COUNT|HYPERTHREADING|"
  OS_CHECK_RESULT="$HOSTNAME|$OS|$OS_ARCH|$MEMORY_SIZE|$CPU_MODEL|$CPU_COUNT|$CPU_CORE_COUNT|$CPU_SOCKET_COUNT|$HYPERTHREADING|"
}

# Get Oracle environment variable
function Get_oracle_env() {
  ORACLE_USER=$(ps aux | grep ora_pmon | grep -v grep | awk '{print $1}')
  ORACLE_SID=$(ps aux | grep ora_pmon | grep -v grep | awk '{print $11}' | cut -d"_" -f3)

  # If ${ORACLE_USER} is exist
  if [ -n "${ORACLE_USER}" ]
  then
    ORACLE_HOME=$(env | grep ^ORACLE_HOME | cut -d"=" -f2)
  else
    echo "Oracle Database is not exists on this server." >> "${LOG}"
    exit 1
  fi
}

### Get Oracle result with sqlplus
function Cmd_sqlplus() {
  # If there are options in glogin.sql move the file.
  GLOGIN="${ORACLE_HOME}/sqlplus/admin/glogin.sql"
  IS_GLOGIN=$(sed '/^$/d' "${GLOGIN}" | grep -cv "\-\-")
  if [ "${IS_GLOGIN}" -gt 0 ]
  then
    mv "${GLOGIN}" "${GLOGIN}"_old
  fi

  sqlplus -silent / as sysdba 2>/dev/null << EOF
set pagesize 0 feedback off verify off heading off echo off timing off line 500
spool ${SPOOL}
$2
exit
EOF

  # Recover glogin.sql
  if [ "${IS_GLOGIN}" -gt 0 ]
  then
    sudo mv "${GLOGIN}"_old "${GLOGIN}"
  fi
}

### Check Oracle version
function Check_version() {
  ORACLE_VERSION=$(Cmd_sqlplus "${ORACLE_USER}" "select version from v\$instance;")
  ORACLE_MAJOR_VERSION=$(echo "${ORACLE_VERSION}" | cut -d"." -f1)

  number='[0-9]'
  if ! [[ "${ORACLE_MAJOR_VERSION}" =~ $number ]]
  then
    echo "Error: can't check oracle version. Check oracle environment" >> "${LOG}"
    echo "## Oracle USER : ${ORACLE_USER}" >> "${LOG}"
    echo "## Oracle HOME : ${ORACLE_HOME}" >> "${LOG}"
    echo "## Oracle SID : ${ORACLE_SID}" >> "${LOG}"
    exit
  fi
}

### Check Oracle general configuration
function Check_general () {
  if [ "${ORACLE_MAJOR_VERSION}" == 11 ]
  then
    Cmd_sqlplus "${ORACLE_USER}" "${SQL_ORACLE_GENERAL_11G}" > "${GENERAL_RAW}"
    Print_Oracle_general_result
  elif [ "${ORACLE_MAJOR_VERSION}" -ge 12 ]
  then
    Cmd_sqlplus "${ORACLE_USER}" "${SQL_ORACLE_GENERAL_12G}" > "${GENERAL_RAW}"
    Set_option_var
    Print_Oracle_general_result
 fi
}

function Print_Oracle_general_result() {
  #echo "DB_HOSTNAME|DB_NAME|OPEN_MODE|DATABASE_ROLE|CREATED|DBID|BANNER|MAX_TIMESTAMP|MAX_CPU_COUNT|MAX_CPU_CORE_COUNT|MAX_CPU_SOCKET_COUNT|LAST_TIMESTAMP|LAST_CPU_COUNT|LAST_CPU_CORE_COUNT|LAST_CPU_SOCKET_COUNT|CONTROL_MANAGEMENT_PACK_ACCESS|ENABLE_DDL_LOGGING|CDB|DB_VERSION|DB_PATCH\n"
  #cat ${SPOOL} # | awk -F\| '{print $1,$2,$3,$4,$5,$6,$7,$8}'
  DB_GENERAL_HEADER="DB_HOSTNAME|DB_NAME|OPEN_MODE|DATABASE_ROLE|CREATED|DBID|BANNER|MAX_TIMESTAMP|MAX_CPU_COUNT|MAX_CPU_CORE_COUNT|MAX_CPU_SOCKET_COUNT|LAST_TIMESTAMP|LAST_CPU_COUNT|LAST_CPU_CORE_COUNT|LAST_CPU_SOCKET_COUNT|CONTROL_MANAGEMENT_PACK_ACCESS|ENABLE_DDL_LOGGING|CDB|DB_VERSION|DB_PATCH"
  DB_GENERAL_RESULT=$(sed "s/  //g" ${SPOOL})
}

function Set_option_var() {
  Check_option_var ${SPOOL} ".Database Gateway"                                 "DATABASE_GATEWAY"
  Check_option_var ${SPOOL} ".Exadata"                                          "EXADATA"
  Check_option_var ${SPOOL} ".GoldenGate"                                       "GOLDENGATE"
  Check_option_var ${SPOOL} ".HW"                                               "HW"
  Check_option_var ${SPOOL} ".Pillar Storage"                                   "PILLARSTORAGE"
  Check_option_var ${SPOOL} "Active Data Guard"                                 "ADG"
  Check_option_var ${SPOOL} "Active Data Guard or Real Application Clusters"    "ADG_RAC"
  Check_option_var ${SPOOL} "Advanced Analytics"                                "AA"
  Check_option_var ${SPOOL} "Advanced Compression"                              "AC"
  Check_option_var ${SPOOL} "Advanced Security"                                 "AS"
  Check_option_var ${SPOOL} "Database In-Memory"                                "DIM"
  Check_option_var ${SPOOL} "Database Vault"                                    "DV"
  Check_option_var ${SPOOL} "Diagnostics Pack"                                  "DP"
  Check_option_var ${SPOOL} "Label Security"                                    "LS"
  Check_option_var ${SPOOL} "Multitenant"                                       "MT"
  Check_option_var ${SPOOL} "OLAP"                                              "OLAP"
  Check_option_var ${SPOOL} "Partitioning"                                      "PARTITION"
  Check_option_var ${SPOOL} "RAC or RAC One Node"                               "RAC_ONENODE"
  Check_option_var ${SPOOL} "Real Application Clusters"                         "RAC"
  Check_option_var ${SPOOL} "Real Application Clusters One Node"                "ONENODE"
  Check_option_var ${SPOOL} "Real Application Testing"                          "RAT"
  Check_option_var ${SPOOL} "Spatial and Graph"                                 "SPATIAL"
  Check_option_var ${SPOOL} "Tuning Pack"                                       "TUNING"
}

function Check_option_var() {
  #if [[ -z $(grep "${2}" ${SPOOL} | grep -v "NO_USAGE" ) ]]
  if grep -q "${2}" ${SPOOL} | grep -v "NO_USAGE"
  then
    eval "$3"=0   # NO_USAGE ==> 0
  else
    option=$(grep "${2}" ${SPOOL} | cut -d"|" -f6 | grep -cv "NO_USAGE")
    #eval $3="${#option[@]}"     # Count of options
    eval "$3"="${option}"
  fi
}


### Check Oracle option
function Check_option () {
  if [ "${ORACLE_MAJOR_VERSION}" == 11 ]
  then
    Cmd_sqlplus "${ORACLE_USER}" "${SQL_ORACLE_CHECK_11G}" > "${OPTION_RAW}"
    Set_option_var
    Print_Oracle_check_result
  elif [ "${ORACLE_MAJOR_VERSION}" -ge 12 ]
  then
    Cmd_sqlplus "${ORACLE_USER}" "${SQL_ORACLE_CHECK_12G}" > "${OPTION_RAW}"
    Set_option_var
    Print_Oracle_check_result
  else
    echo "This script is for 11g over." >> "${LOG}"
    exit
  fi
}

function Print_Oracle_check_result() {
  #cat ${SPOOL} | awk -F\| '{
#name=$4;
#detail=$5;
#usage=$6;
#if ( usage=="NO_USAGE" ) color=" \033[0;32m";
#else color=" \033[0;31m";
#print "\033[0m" name "|" detail "|" color usage;
#}' | sort
#printf "\033[0m"

  DB_CHECK_HEADER=$(printf ".Database Gateway|.Exadata|.GoldenGate|.HW|.Pillar Storage|Active Data Guard|Active Data Guard or Real Application Clusters|Advanced Analytics|Advanced Compression|Advanced Security|Database In-Memory|Database Vault|Diagnostics Pack|Label Security|Multitenant|OLAP|Partitioning|RAC or RAC One Node|Real Application Clusters|Real Application Clusters One Node|Real Application Testing|Spatial and Graph|Tuning Pack|")
  DB_CHECK_RESULT="${DATABASE_GATEWAY}|${EXADATA}|${GOLDENGATE}|${HW}|${PILLARSTORAGE}|${ADG}|${ADG_RAC}|${AA}|${AC}|${AS}|${DIM}|${DV}|${DP}|${LS}|${MT}|${OLAP}|${PARTITION}|${RAC_ONENODE}|${RAC}|${ONENODE}|${RAT}|${SPATIAL}|${TUNING}|"
}

function Create_output () {
  printf "%s%s%s\n" "${OS_CHECK_HEADER}" "${DB_CHECK_HEADER}" "${DB_GENERAL_HEADER}" >  "${OUTPUT}"
  printf "%s%s%s"   "${OS_CHECK_RESULT}" "${DB_CHECK_RESULT}" "${DB_GENERAL_RESULT}" >> "${OUTPUT}"
}


# ========== SQL  ========== #
SQL_ORACLE_GENERAL_11G="
SELECT
     HOST_NAME||  '|' ||
     DATABASE_NAME|| '|' ||
     OPEN_MODE || '|' ||
     DATABASE_ROLE || '|' ||
     CREATED|| '|' ||
     DBID|| '|' ||
     BANNER || '|' ||
     MAX_TIMESTAMP|| '|' ||
     MAX_CPU_COUNT|| '|' ||
     MAX_CPU_CORE_COUNT|| '|' ||
     MAX_CPU_SOCKET_COUNT|| '|' ||
     LAST_TIMESTAMP|| '|' ||
     LAST_CPU_COUNT|| '|' ||
     LAST_CPU_CORE_COUNT|| '|' ||
     LAST_CPU_SOCKET_COUNT|| '|' ||
     CONTROL_MANAGEMENT_PACK_ACCESS|| '|' ||
     ENABLE_DDL_LOGGING|| '|' ||
     'NO'|| '|' ||
     VERSION|| '|' ||
     COMMENTS AS \"DB_GENERAL\"
  FROM
 (SELECT I.HOST_NAME,
        D.NAME AS DATABASE_NAME,
        D.OPEN_MODE,
        D.DATABASE_ROLE,
        TO_CHAR(D.CREATED,'YYYY-MM-DD') CREATED,
        D.DBID,
        V.BANNER,
        I.VERSION,
        (SELECT COMMENTS FROM (SELECT * FROM SYS.REGISTRY\$HISTORY WHERE NAMESPACE ='SERVER' ORDER BY 1 DESC) WHERE ROWNUM <2) COMMENTS
   FROM  V\$INSTANCE I, V\$DATABASE D, V\$VERSION V
  WHERE v.BANNER LIKE 'Oracle%' or v.BANNER like 'Personal Oracle%' AND ROWNUM <2) A,
 (SELECT TO_CHAR(TIMESTAMP,'YYYY-MM-DD') MAX_TIMESTAMP, CPU_COUNT MAX_CPU_COUNT, CPU_CORE_COUNT MAX_CPU_CORE_COUNT, CPU_SOCKET_COUNT MAX_CPU_SOCKET_COUNT FROM DBA_CPU_USAGE_STATISTICS
 WHERE TIMESTAMP = (SELECT MAX(TIMESTAMP) FROM DBA_CPU_USAGE_STATISTICS WHERE CPU_COUNT = (SELECT MAX(CPU_COUNT) FROM DBA_CPU_USAGE_STATISTICS))) B,
 (SELECT TO_CHAR(TIMESTAMP,'YYYY-MM-DD') LAST_TIMESTAMP, CPU_COUNT LAST_CPU_COUNT, CPU_CORE_COUNT LAST_CPU_CORE_COUNT, CPU_SOCKET_COUNT LAST_CPU_SOCKET_COUNT FROM DBA_CPU_USAGE_STATISTICS
 WHERE TIMESTAMP = (SELECT MAX(TIMESTAMP) FROM DBA_CPU_USAGE_STATISTICS)) C,
 (SELECT VALUE AS \"CONTROL_MANAGEMENT_PACK_ACCESS\" FROM V\$PARAMETER WHERE LOWER(NAME) IN ('control_management_pack_access')) D,
 (SELECT VALUE AS \"ENABLE_DDL_LOGGING\" FROM V\$PARAMETER WHERE LOWER(NAME) IN ('enable_ddl_logging')) E
;
"

SQL_ORACLE_GENERAL_12G="
SELECT
     HOST_NAME||  '|' ||
     DATABASE_NAME|| '|' ||
     OPEN_MODE || '|' ||
     DATABASE_ROLE || '|' ||
     CREATED|| '|' ||
     DBID|| '|' ||
     BANNER || '|' ||
     MAX_TIMESTAMP|| '|' ||
     MAX_CPU_COUNT|| '|' ||
     MAX_CPU_CORE_COUNT|| '|' ||
     MAX_CPU_SOCKET_COUNT|| '|' ||
     LAST_TIMESTAMP|| '|' ||
     LAST_CPU_COUNT|| '|' ||
     LAST_CPU_CORE_COUNT|| '|' ||
     LAST_CPU_SOCKET_COUNT|| '|' ||
     CONTROL_MANAGEMENT_PACK_ACCESS|| '|' ||
     ENABLE_DDL_LOGGING|| '|' ||
     CDB|| '|' ||
     VERSION|| '|' ||
     COMMENTS AS \"DB_GENERAL\"
  FROM
 (SELECT I.HOST_NAME,
        D.NAME AS DATABASE_NAME,
        D.OPEN_MODE,
        D.DATABASE_ROLE,
        TO_CHAR(D.CREATED,'YYYY-MM-DD') CREATED,
        D.DBID,
        V.BANNER,
        D.CDB,
        I.VERSION,
        (SELECT COMMENTS FROM (SELECT * FROM SYS.REGISTRY\$HISTORY WHERE NAMESPACE ='SERVER' ORDER BY 1 DESC) WHERE ROWNUM <2) COMMENTS
   FROM  V\$INSTANCE I, V\$DATABASE D, V\$VERSION V
  WHERE V.BANNER LIKE 'Oracle%' or V.BANNER like 'Personal Oracle%' AND ROWNUM <2) A,
 (SELECT TO_CHAR(TIMESTAMP,'YYYY-MM-DD') MAX_TIMESTAMP, CPU_COUNT MAX_CPU_COUNT, CPU_CORE_COUNT MAX_CPU_CORE_COUNT, CPU_SOCKET_COUNT MAX_CPU_SOCKET_COUNT FROM DBA_CPU_USAGE_STATISTICS
 WHERE TIMESTAMP = (SELECT MAX(TIMESTAMP) FROM DBA_CPU_USAGE_STATISTICS WHERE CPU_COUNT = (SELECT MAX(CPU_COUNT) FROM DBA_CPU_USAGE_STATISTICS))) B,
 (SELECT TO_CHAR(TIMESTAMP,'YYYY-MM-DD') LAST_TIMESTAMP, CPU_COUNT LAST_CPU_COUNT, CPU_CORE_COUNT LAST_CPU_CORE_COUNT, CPU_SOCKET_COUNT LAST_CPU_SOCKET_COUNT FROM DBA_CPU_USAGE_STATISTICS
 WHERE TIMESTAMP = (SELECT MAX(TIMESTAMP) FROM DBA_CPU_USAGE_STATISTICS)) C,
 (SELECT VALUE AS \"CONTROL_MANAGEMENT_PACK_ACCESS\" FROM V\$PARAMETER WHERE LOWER(NAME) IN ('control_management_pack_access')) D,
 (SELECT VALUE AS \"ENABLE_DDL_LOGGING\" FROM V\$PARAMETER WHERE LOWER(NAME) IN ('enable_ddl_logging')) E
;
"

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
   where USAGE in ('2.NO_LAST_USAGE', '4.PAST_USAGE', '5.PAST_OR_LAST_USAGE', '6.LAST_USAGE')   -- ignore '1.NO_PAST_USAGE', '3.SUPPRESSED_DUE_TO_BUG'
 ;
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
   where USAGE in ('2.NO_LAST_USAGE', '4.PAST_USAGE', '5.PAST_OR_LAST_USAGE', '6.LAST_USAGE')   -- ignore '1.NO_PAST_USAGE', '3.SUPPRESSED_DUE_TO_BUG'
 ;
"


# ========== Main ========== #
date > "${LOG}"

Check_OS
Get_oracle_env
Check_version

Check_general
Check_option

Create_output

rm ${SPOOL}
