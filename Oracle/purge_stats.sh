#!/bin/bash
########################################################
# Description : Purge statistics in SYSTEM tablespace
# Create DATE : 2021.07.19
# Last Update DATE : 2021.10.04 by ashurei
# Copyright (c) ashurei@sktelecom.com, 2021
########################################################

# This script can only be used on Linux platform.

source ~/.bash_profile
################################
# Need to modify
ORACLE_SID="ORCL"
PURGEDATE="31"
################################

set -o posix
BINDIR="${HOME}/DBA/script/purge"

### Create log directory
if [ ! -d "${BINDIR}" ]
then
  set -e
  mkdir "${BINDIR}"
  set +e
fi

"${ORACLE_HOME}"/bin/sqlplus -silent / as sysdba  > "${BINDIR}/purge_stats_${ORACLE_SID}.log" << EOF
exec dbms_stats.purge_stats(sysdate-${PURGEDATE});
exit
EOF
