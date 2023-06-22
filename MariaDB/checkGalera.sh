#!/bin/bash
#####################################################################
# Description : HAProxy external script for MariaDB Galera Cluster
# Create DATE : 2023.06.22
# Last Update DATE : 2023.06.23 by ashurei
# Copyright (c) ashurei@sk.com, 2023
#####################################################################

MARIADB_HOST="$3"
MARIADB_PORT="$4"
USERNAME="tcore"
PASSWORD="Tcore12#"
MARIADB_BIN="/usr/bin/mysql"

CMDLINE="${MARIADB_BIN} -u ${USERNAME} -p${PASSWORD} -h ${MARIADB_HOST} -sNE -e"
CHK_STATE=$(${CMDLINE} "show global status where variable_name='wsrep_local_state'" | tail -1)
CHK_INDEX=$(${CMDLINE} "show global status where variable_name='wsrep_local_index'" | tail -1)
#echo $CHK_INDEX $CHK_STATE

# wsrep_local_state=4  & wsrep_local_index=0
if [[ "$CHK_STATE" == 4 && "$CHK_INDEX" == 0 ]]
then
  exit 0
else
  exit 255
fi
