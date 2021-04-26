#!/bin/bash
########################################################
# Description : Check Oracle license feature
# Create DATE : 2021.04.20
# Last Update DATE : 2021.04.26 by ashurei
# Copyright (c) Technical Solution, 2021
########################################################

export LANG=C
DATE=$(date '+%Y%m%d')
BIN_DIR="/tmp/oracle_check"
SPOOL="/tmp/result.log"
OUTPUT="${BIN_DIR}/$(hostname)_license_${DATE}.out"
LOG="${BIN_DIR}/$(hostname)_license_${DATE}.log"
GENERAL_RAW="db_general_check.rawdata"
OPTION_RAW="db_check.rawdata"

# ========== Functions ========== #
### OS Check
function Check_OS() {
  HOSTNAME=$(hostname)
  OS_ARCH=$(uname -i)
  OS=$(cat /etc/redhat-release)

  if [ ! -f "/usr/sbin/dmidecode" ]
  then
    echo "'dmidecode' is not exists." >> "${LOG}"
    echo "Please install 'dmidecode'." >> "${LOG}"
    exit 1
  fi

  # Check Virtual Machine
  #VM_TYPE=$(lscpu | grep Hypervisor | awk '{print $3}')
  #if [ -z "${VM_TYPE}" ]
  #then
  #  MACHINE_TYPE=BM
  #else
  #  MACHINE_TYPE=${VM_TYPE}
  #fi

  MACHINE_TYPE=$(sudo dmidecode -s system-product-name | grep -v ^#)

  MEMORY_SIZE=$(grep MemTotal /proc/meminfo | awk '{print $2/1024/1024}')
  HW_VENDOR=$(sudo dmidecode -s system-product-name | grep -v ^# | tail -1)
  PROCESSOR_MANUFACTURER=$(sudo dmidecode -s processor-manufacturer | grep -v ^# | tail -1)
  PROCESSOR_FAMILY=$(sudo dmidecode -s processor-family | grep -v ^# | tail -1)
  PROCESSOR_VERSION=$(sudo dmidecode -s processor-version | grep -v ^# | sed "s/^ //g" | head -1)
  CPU_COUNT_OS=$(grep -c ^processor /proc/cpuinfo)
  CPU_CORE_COUNT_OS=$(grep 'cpu cores' /proc/cpuinfo | tail -1 | awk '{print $4}')
  CPU_SOCKET_COUNT_OS=$(sudo dmidecode -t processor | grep -v ^# | grep -c 'Socket Designation')

  if ! sudo dmidecode -t processor | grep -q HTT
  then
    HYPERTHREDING=0
  else
    HYPERTHREDING=$(sudo dmidecode -t processor | grep HTT | tail -1 | awk '{print $1}')
  fi

  #echo "HOSTNAME : "$HOSTNAME
  #echo "OS : "$OS
  #echo "OS_ARCH : "$OS_ARCH
  #echo "MEMORY_SIZE(GB) : "$MEMORY_SIZE
  #echo "MACHINE_TYPE : "$MACHINE_TYPE
  #echo "HW_VENDOR : "$HW_VENDOR
  #echo "PROCESSOR_MANUFACTURER : "$PROCESSOR_MANUFACTURER
  #echo "PROCESSOR_FAMILY : "$PROCESSOR_FAMILY
  #echo "PROCESSOR_VERSION : "$PROCESSOR_VERSION
  #echo "CPU_COUNT_OS : "$CPU_COUNT_OS
  #echo "CPU_CORE_COUNT_OS : "$CPU_CORE_COUNT_OS
  #echo "CPU_SOCKET_COUNT_OS : "$CPU_SOCKET_COUNT_OS
  #echo "HYPERTHREDING : "$HYPERTHREDING
  #echo

  OS_CHECK_HEADER="HOSTNAME|OS|OS_ARCH|MEMORY_SIZE(GB)|MACHINE_TYPE|HW_VENDOR|PROCESSOR_MANUFACTURER|PROCESSOR_FAMILY|PROCESSOR_VERSION|CPU_COUNT_OS|CPU_CORE_COUNT_OS|CPU_SOCKET_COUNT_OS|HYPERTHREDING|"
  OS_CHECK_RESULT="$HOSTNAME|$OS|$OS_ARCH|$MEMORY_SIZE|$MACHINE_TYPE|$HW_VENDOR|$PROCESSOR_MANUFACTURER|$PROCESSOR_FAMILY|$PROCESSOR_VERSION|$CPU_COUNT_OS|$CPU_CORE_COUNT_OS|$CPU_SOCKET_COUNT_OS|$HYPERTHREDING|"
}

# Get Oracle environment variable
function Get_oracle_env() {
  ORACLE_USER=$(ps aux | grep ora_pmon | grep -v grep | awk '{print $1}')
  ORACLE_SID=$(ps aux | grep ora_pmon | grep -v grep | awk '{print $11}' | cut -d"_" -f3)
  if [ -n "${ORACLE_USER}" ]
  then
    ORACLE_HOME=$(sudo su - "${ORACLE_USER}" -c "env" | grep ^ORACLE_HOME | cut -d"=" -f2)
  else
    echo "Oracle Database is not exists on this server." >> "${LOG}"
    exit 1
  fi
}

### Get Oracle result with sqlplus
function Cmd_sqlplus() {
  GLOGIN="${ORACLE_HOME}/sqlplus/admin/glogin.sql"
  IS_GLOGIN=$(cat ${GLOGIN} | sed '/^$/d' | grep -cv "\-\-")
  if [ "${IS_GLOGIN}" -gt 0 ]
  then
    sudo mv "${GLOGIN}" "${GLOGIN}"_old
  fi

  sudo su - "$1" -c "sqlplus -silent / as sysdba" 2>/dev/null << EOF
set pagesize 0 feedback off verify off heading off echo off timing off line 500
spool ${SPOOL}
$2
exit
EOF

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
    Cmd_sqlplus "${ORACLE_USER}" "@${BIN_DIR}/oracle_general_11.sql" > "${GENERAL_RAW}"
    Print_Oracle_general_result
  elif [ "${ORACLE_MAJOR_VERSION}" -ge 12 ]
  then
    Cmd_sqlplus "${ORACLE_USER}" "@${BIN_DIR}/oracle_general_12.sql" > "${GENERAL_RAW}"
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
    Cmd_sqlplus "${ORACLE_USER}" "@${BIN_DIR}/oracle_check_11.sql" > "${OPTION_RAW}"
    Set_option_var
    Print_Oracle_check_result
  elif [ "${ORACLE_MAJOR_VERSION}" -ge 12 ]
  then
    Cmd_sqlplus "${ORACLE_USER}" "@${BIN_DIR}/oracle_check_12.sql" > "${OPTION_RAW}"
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


# ========== Main ========== #
date > "${LOG}"

Check_OS
Get_oracle_env
Check_version

Check_general
Check_option

Create_output

sudo rm ${SPOOL}
