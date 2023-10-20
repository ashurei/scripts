#!/bin/bash
#####################################################################
# Description : Configure replication
# Create DATE : 2023.10.20
# Last Update DATE : 2023.10.20 by ashurei
# Copyright (c) ashurei@sk.com, 2023
#####################################################################

# Table list
TABLE="db01.t1,db01.t2"

# Primary(Remote)
HOST="60.30.136.192"
PORT="3307"
USER="repl"
PASSWD="Repl1234@"

# Secondary(localhost)
SOCKET="/MARIA/TMP/mariadb.sock"

# Get information of primary node
MARIA_P="/MARIA/mariadb/bin/mariadb --host=${HOST} --port=${PORT} --user=${USER} --password=${PASSWD}"
MASTER_INFO=$(${MARIA_P} -e "show master status\G" | grep -E 'File|Position')
MASTER_FILE=$(echo $MASTER_INFO | cut -d' ' -f2)
MASTER_POS=$(echo $MASTER_INFO | cut -d' ' -f4)

# Configure replication
MARIA_S="/MARIA/mariadb/bin/mariadb --socket=${SOCKET}"
${MARIA_S} -e "set global replicate_do_table='${TABLE}'"
${MARIA_S} -e "change master to master_host='${HOST}', master_port=${PORT}, master_user='${USER}', master_password='${PASSWD}', master_log_file='${MASTER_FILE}', master_log_pos=${MASTER_POS}"
${MARIA_S} -e "start slave"
