# 2021.11.18 Modified by ashurei@sk.com
# NODE 1
PGDATA="/data/pgsql/data"
PGARCH="/data/pgsql/arch"
TARGET="hola-db-01"
SLOT="hola_db02"

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
rm -rf "${PGDATA}"
rm -f "${PGARCH}"/*

# Perform pg_basebackup
pg_basebackup -h "${TARGET}" -U replication -p 5444 -D "${PGDATA}" -Xs -P -R

# Config postgresql.auto.conf
cp ./postgresql.auto.conf ${PGDATA}

# Delete old logs
rm -f "${PGDATA}"/log/*.log

# Start cluster
pg_ctl start

# Create replication slot
psql -c "select pg_create_physical_replication_slot('${SLOT}')"
