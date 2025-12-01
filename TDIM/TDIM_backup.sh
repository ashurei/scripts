#!/bin/bash
########################################################
# Description : TDIM backup script
# Create DATE : 2025.12.01
# Last Update DATE : 2025.12.01 by ashurei
# Copyright (c) Technical Solution, 2025
########################################################

########################################################
BASEDIR="/home/tcore/backup"
########################################################
### Set variable
TODAY=$(date '+%Y%m%d')
BACKDIR="${BASEDIR}/${TODAY}"
LOGFILE="${BASEDIR}/backup_${TODAY}.log"

{
if [ -d "$BACKDIR" ]
then
  echo "[ERROR] Backup directory is exists."
  exit 1
else
  mkdir -p "$BACKDIR"
fi

### Backup target directory
echo "+ Backup S/W files..."
cp -pr --parents /home/tcore/tcore_dist/sbin "$BACKDIR"/
cp -pr --parents /home/tcore/tcore_dist/apps/bin "$BACKDIR"/
cp -pr --parents /home/tcore/tcore_dist/apps/conf "$BACKDIR"/
cp -pr --parents /data/tcore-apps/bin "$BACKDIR"/
cp -pr --parents /data/tcore-apps/conf "$BACKDIR"/
cp -pr --parents /home/tcore/sw/druid/conf "$BACKDIR"/
cp -pr --parents /home/tcore/sw/elasticsearch/config "$BACKDIR"/
cp -pr --parents /home/tcore/sw/hadoop/etc "$BACKDIR"/
cp -pr --parents /home/tcore/sw/kafka/config "$BACKDIR"/

if [ -x "/home/tcore/sw/redis/bin/redis_cli" ]
then
  cp -pr --parents /home/tcore/sw/redis/data/7001/redis-7001.conf "$BACKDIR"/
  cp -pr --parents /home/tcore/sw/redis/data/7002/redis-7002.conf "$BACKDIR"/
fi

cp -pr --parents /home/tcore/sw/spark/conf "$BACKDIR"/
cp -pr --parents /home/tcore/sw/spark/sbin "$BACKDIR"/

if [ -d "/home/tcore/sw/zookeeper" ]
then
  cp -pr --parents /home/tcore/sw/zookeeper/conf "$BACKDIR"/
fi

# Docker
cp -pr --parents /data/shared/tcore-ic-swarm/container-oracle* "$BACKDIR"/
cp -p --parents /data/tcore-apps/bin/kafka-ui/docker-compose.yml "$BACKDIR"/

### Backup master config of other user
if [[ $(hostname) =~ -master(01|02)$ ]]
then
  echo "+ Backup master config of other user..."
  cp -pr --parents /home/tcore/sw/kibana/config "$BACKDIR"/
  sudo cp -p --parents /etc/keepalived/keepalived.conf "$BACKDIR"/  # root:root
  sudo cp -p --parents /etc/haproxy/haproxy.cfg "$BACKDIR"/         # root:root
  sudo cp -p --parents /etc/nginx/conf.d/repo.conf "$BACKDIR"/      # root:root
  sudo cp -p --parents /etc/nginx/conf.d/tcore.conf "$BACKDIR"/     # root:root
  sudo cp -p --parents /etc/my.cnf "$BACKDIR"/                      # root:maria
  sudo cp -p --parents /etc/grafana/grafana.ini "$BACKDIR"/         # root:grafana
fi

### Backup DB
if [ -x "/MARIA/mariadb/bin/mariadb" ]
then
  DBDIR="${BACKDIR}/MariaDB"
  mkdir -p "$DBDIR"
  echo "+ Backup MariaDB..."
  mariadb-dump --single-transaction \
    --ignore-table=tcore_alarm.vw_alarm_exception_bas tcore_alarm > "$DBDIR"/tcore_alarm.sql
  mariadb-dump --single-transaction tcore_collector > "$DBDIR"/tcore_collector.sql
  mariadb-dump --single-transaction \
    --ignore-table=tcore_common.vw_com_user_bas tcore_common > "$DBDIR"/tcore_common.sql
  mariadb-dump --single-transaction tcore_data > "$DBDIR"/tcore_data.sql
  mariadb-dump --single-transaction tcore_iautomation> "$DBDIR"/tcore_iautomation.sql
  mariadb-dump --single-transaction \
    --ignore-table=tcore_resource.vw_rep_resource_spec_tune \
    --ignore-table=tcore_resource.vw_rep_resource_asset \
    --ignore-table=tcore_resource.vw_rep_resource_bas \
    --ignore-table=tcore_resource.vw_rep_resource_hypervisors \
    --ignore-table=tcore_resource.vw_rep_resource_management \
    --ignore-table=tcore_resource.vw_rep_resource_spec \
    --ignore-table=tcore_resource.vw_rep_resource_staff \
    tcore_resource > "$DBDIR"/tcore_resource.sql
  mariadb-dump --single-transaction tcore_ui > "$DBDIR"/tcore_ui.sql
fi

### Compress
echo "+ chown Backup directory"
sudo chown -R tcore:tcore "$BACKDIR"
tar cfz "${BASEDIR}/TDIM_${TODAY}.tgz" "$BACKDIR"

} >> "$LOGFILE" 2>&1
