#!/bin/bash
########################################################
# Description : Monitor PostgreSQL with log
# Create DATE : 2023.07.07
# Last Update DATE : 2023.07.07 by ashurei
# Copyright (c) ashurei@sktelecom.com, 2023
########################################################

PSQL="/usr/bin/psql"
export PGDATA="/data/pgsql/data"
export PGPORT=5444

DATE=$(date "+%Y%m%d")
DATE_S=$(date '+%Y-%m-%d %H:%M:%S')
LOGDIR="$HOME/script/log"
LOGFILE="${LOGDIR}/pg_session_${DATE}.log"
if [ ! -d "$LOGDIR" ]
then
  mkdir -p "$LOGDIR"
fi

# Get usage of connection
SESSION=$("$PSQL" -At -c "select count(*) from pg_stat_activity")
MAX_CON=$("$PSQL" -At -c "select setting from pg_settings where name='max_connections'")

# Get gap of replication (minute)
GAP=$("$PSQL" -At -c "select replay_lag from pg_stat_replication" | awk -F':' '{print $1*60+$2}')

# Delete logfiles 14 ago
find "${LOGDIR:?}"/pg_session_*.log -mtime +14 -type f -delete 2>&1

# Generate log (ex. 2023-07-07 16:16:00,20,0)
echo "$SESSION" "$MAX_CON" | awk -v v1="$DATE_S" -v v2="$GAP" '{printf("%s,%.0f,%d\n", v1, $1/$2*100, v2)}' >> "$LOGFILE"

