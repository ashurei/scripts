#!/bin/bash
########################################################
# Description : Create PostgreSQL streaming replication
# Create DATE : 2021.11.18
# Last Update DATE : 2021.11.19 by ashurei
# Copyright (c) ashurei@sktelecom.com, 2021
########################################################

# This script can only be used on Linux platform and cannot support 'csh' with cronjob.
# This script was created to be run by the PostgreSQL user. Excute with postgres user.
# You need to ready with 'postgresql.auto.conf'

# NODE 1
PGDATA="/data/pgsql/data"
PGPORT="5444"
PGARCH="/data/pgsql/arch"
TARGET="hola-db-02"
SLOT="hola_db01"

# Confirm creating secondary node.
read -s -n 1 -p "$(hostname) will be removed. Confirm (y/n): " INPUT
if ! [[ "${INPUT}" =~ [Yy] ]]
then
  echo "${INPUT}"
  exit 0
fi
echo "${INPUT}"

# Delete data
pg_ctl stop -mf
rm -rf "${PGDATA}"/*
rm -rf "${PGARCH}"/*

# Perform pg_basebackup
pg_basebackup -h "${TARGET}" -U replication -D "${PGDATA}" -p "${PGPORT}" -Xs -P -R

# Config postgresql.auto.conf
cp ./postgresql.auto.conf ${PGDATA}

# Delete old logs
rm -f "${PGDATA}"/log/*.log

# Start cluster
pg_ctl start -D "${PGDATA}" -p "${PGPORT}"

# Create replication slot
psql -c "select pg_create_physical_replication_slot('${SLOT}')"
