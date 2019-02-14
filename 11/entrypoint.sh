#!/bin/bash

set -e

PG_VERSION=${PG_VERSION:-}
PG_USER=${PG_USER:-}
PG_HOME=${PG_HOME:-}
PG_LOG_DIR=${PG_LOG_DIR:-}
PG_DATA_DIR=${PG_DATA_DIR:-}
PG_RUN_DIR=${PG_RUN_DIR:-}
PG_CONF_DIR=${PG_CONF_DIR:-}
PG_BIN_DIR=${PG_BIN_DIR:-}
PG_TZ=${PG_TZ:-"UTC"}

PG_BACKUP_DIR=${PG_BACKUP_DIR:-"/tmp/backup"}
PG_BACKUP_FILENAME=${PG_BACKUP_FILENAME:-"backup.last.tar.bz2"}
PG_ROTATE_BACKUP=${PG_ROTATE_BACKUP:-true}
PG_CHECK=${PG_CHECK:-}
PG_RESTORE=${PG_RESTORE:-}

# set this env variable to true to enable a line in the
# pg_hba.conf file to trust samenet.  this can be used to connect
# from other containers on the same host without authentication
PG_TRUST_LOCALNET=${PG_TRUST_LOCALNET:-false}

DB_NAME=${DB_NAME:-}
DB_USER=${DB_USER:-}
DB_PASS=${DB_PASS:-}
DB_LOCALE=${DB_LOCALE:-"${OS_LOCALE}"}
DB_UNACCENT=${DB_UNACCENT:false}

# set this environment variable to master, slave or snapshot to use replication features.
# "snapshot" will create a point in time backup of a master instance.
PG_MODE=${PG_MODE:-}

REPLICATION_USER=${REPLICATION_USER:-replica}
REPLICATION_PASS=${REPLICATION_PASS:-replica}
REPLICATION_HOST=${REPLICATION_HOST:-}
REPLICATION_PORT=${REPLICATION_PORT:-5432}
PG_WAL_SEGMENTS=${PG_WAL_SEGMENTS:-8}
PG_MAX_WAL_SIZE=${PG_MAX_WAL_SIZE:-"1GB"}
PG_MAX_WAL_SENDERS=${PG_MAX_WAL_SENDERS:-3}

# set this env variable to "require" to enable encryption and "verify-full" for verification.
PG_SSLMODE=${PG_SSLMODE:-disable}

map_postgres_uid() {
  USERMAP_ORIG_UID=$(id -u ${PG_USER})
  USERMAP_ORIG_GID=$(id -g ${PG_USER})
  USERMAP_GID=${USERMAP_GID:-${USERMAP_UID:-$USERMAP_ORIG_GID}}
  USERMAP_UID=${USERMAP_UID:-$USERMAP_ORIG_UID}
  if [[ ${USERMAP_UID} != ${USERMAP_ORIG_UID} ]] || [[ ${USERMAP_GID} != ${USERMAP_ORIG_GID} ]]; then
    echo "Adapting uid and gid for ${PG_USER}:${PG_USER} to $USERMAP_UID:$USERMAP_GID"
    groupmod -g ${USERMAP_GID} ${PG_USER}
    sed -i -e "s/:${USERMAP_ORIG_UID}:${USERMAP_GID}:/:${USERMAP_UID}:${USERMAP_GID}:/" /etc/passwd
  fi
}

create_home_dir() {
  mkdir -p ${PG_HOME}
  chmod -R 0700 ${PG_HOME}
  chown -R ${PG_USER}:${PG_USER} ${PG_HOME}
}

create_data_dir() {
  mkdir -p ${PG_DATA_DIR}
  chmod -R 0700 ${PG_DATA_DIR}
  chown -R ${PG_USER}:${PG_USER} ${PG_DATA_DIR}
}

create_log_dir() {
  mkdir -p ${PG_LOG_DIR}
  chmod -R 1775 ${PG_LOG_DIR}
  chown -R root:${PG_USER} ${PG_LOG_DIR}
}

create_run_dir() {
  mkdir -p ${PG_RUN_DIR} ${PG_RUN_DIR}/${PG_VERSION}-main.pg_stat_tmp
  chmod -R 0755 ${PG_RUN_DIR}
  chmod g+s ${PG_RUN_DIR}
  chown -R ${PG_USER}:${PG_USER} ${PG_RUN_DIR}
}

create_backup_dir() {
  mkdir -p ${PG_BACKUP_DIR}/
  chmod -R 0755 ${PG_BACKUP_DIR}
  chown -R root:${PG_USER} ${PG_BACKUP_DIR}
}

rotate_backup()
{
  echo "Rotate backup..."

  if [[ ${PG_ROTATE_BACKUP} == true ]]; then

    WEEK=$(date +"%V")
    MONTH=$(date +"%b")
    let "INDEX = WEEK % 5" || true
    if [[ ${INDEX} == 0  ]]; then
      INDEX=4
    fi

    test -e ${PG_BACKUP_DIR}/backup.${INDEX}.tar.bz2 && rm ${PG_BACKUP_DIR}/backup.${INDEX}.tar.bz2
    mv ${PG_BACKUP_DIR}/backup.tar.bz2 ${PG_BACKUP_DIR}/backup.${INDEX}.tar.bz2
    echo "Create backup file: ${PG_BACKUP_DIR}/backup.${INDEX}.tar.bz2"

    test -e ${PG_BACKUP_DIR}/backup.${MONTH}.tar.bz2 && rm ${PG_BACKUP_DIR}/backup.${MONTH}.tar.bz2
    ln ${PG_BACKUP_DIR}/backup.${INDEX}.tar.bz2 ${PG_BACKUP_DIR}/backup.${MONTH}.tar.bz2
    echo "Create backup file: ${PG_BACKUP_DIR}/backup.${MONTH}.tar.bz2"

    test -e ${PG_BACKUP_DIR}/backup.last.tar.bz2 && rm ${PG_BACKUP_DIR}/backup.last.tar.bz2
    ln ${PG_BACKUP_DIR}/backup.${INDEX}.tar.bz2 ${PG_BACKUP_DIR}/backup.last.tar.bz2
    echo "Create backup file: ${PG_BACKUP_DIR}/backup.last.tar.bz2"
  else
    mv ${PG_BACKUP_DIR}/backup.tar.bz2 ${PG_BACKUP_DIR}/backup.last.tar.bz2
        echo "Create backup file: ${PG_BACKUP_DIR}/backup.last.tar.bz2"
  fi
}

import_backup()
{
    FILE=$1
    if [[ ${FILE} == default ]]; then
        FILE="${PG_BACKUP_DIR}/${PG_BACKUP_FILENAME}"
    fi
    if [[ ! -f "${FILE}" ]]; then
       echo "Unknown backup: ${FILE}"
      exit 1
    fi
    create_data_dir
    sudo -Hu ${PG_USER} lbzip2 -dc -n 2 ${FILE} | tar -C ${PG_DATA_DIR} -x
}

remove_recovery_file()
{
  if [[ -f "${PG_DATA_DIR}/recovery.conf" ]]; then
    echo "Remove file: '${PG_DATA_DIR}/recovery.conf'"
    rm ${PG_DATA_DIR}/recovery.conf
  fi
}

# Sets a locale
locale-gen ${DB_LOCALE} && dpkg-reconfigure --frontend=noninteractive locales

map_postgres_uid
create_home_dir
create_log_dir
create_run_dir
create_backup_dir

# fix ownership of ${PG_CONF_DIR} (may be necessary if USERMAP_* was set)
chown -R ${PG_USER}:${PG_USER} ${PG_CONF_DIR}

if [[ ! -f /tmp/.CONFIGURE_1  ]]; then
  if [[ ${PG_SSLMODE} == disable ]]; then
    sed 's/ssl = true/#ssl = true/' -i ${PG_CONF_DIR}/postgresql.conf
  fi

  # Change DSM from `posix' to `sysv' if we are inside an lx-brand container
  if [[ $(uname -v) == "BrandZ virtual linux" ]]; then
    sed 's/\(dynamic_shared_memory_type = \)posix/\1sysv/' \
      -i ${PG_CONF_DIR}/postgresql.conf
  fi

  # listen on all interfaces
  cat >> ${PG_CONF_DIR}/postgresql.conf <<EOF
listen_addresses = '*'
EOF

  if [[ ${PG_TRUST_LOCALNET} == true ]]; then
    echo "Enabling trust samenet in pg_hba.conf..."
    cat >> ${PG_CONF_DIR}/pg_hba.conf <<EOF
host    all             all             samenet                 trust
EOF
  fi

  # allow remote connections to postgresql database
  cat >> ${PG_CONF_DIR}/pg_hba.conf <<EOF
host    all             all             0.0.0.0/0               md5
EOF

  # allow replication connections to the database
  if [[ ${PG_MODE} =~ ^master || ${PG_MODE} =~ ^slave ]]; then
    if [[ ${PG_SSLMODE} == disable ]]; then
      cat >> ${PG_CONF_DIR}/pg_hba.conf <<EOF
host    replication     ${REPLICATION_USER}       0.0.0.0/0               md5
EOF
    else
      cat >> ${PG_CONF_DIR}/pg_hba.conf <<EOF
hostssl replication     ${REPLICATION_USER}       0.0.0.0/0               md5
EOF
    fi
  fi

  if [[ ${PG_MODE} =~ ^master || ${PG_MODE} == slave_wal ]]; then
    if [[ -n ${REPLICATION_USER} ]]; then
      echo "Supporting hot standby..."
      cat >> ${PG_CONF_DIR}/postgresql.conf <<EOF
wal_level = hot_standby
max_wal_senders = ${PG_MAX_WAL_SENDERS}
max_wal_size = ${PG_MAX_WAL_SIZE}
wal_keep_segments = ${PG_WAL_SEGMENTS}
EOF
    fi
  fi
  touch /tmp/.CONFIGURE_1
fi

cd ${PG_HOME}

# allow arguments to be passed to pg_basebackup
if [[ ${1:0:1} = '-' ]]; then
    EXTRA_OPTS="$@"
    set --
elif [[ ${1} == mongod || ${1} == $(which mongod) ]]; then
    EXTRA_OPTS="${@:2}"
    set --
fi

 # Export to backup
if [[ ${PG_MODE} == backup ]]; then
  echo "Backup databases..."

  if [[ -d ${PG_DATA_DIR} ]]; then
    echo 'Used host: local'
    sudo -Hu ${PG_USER} \
        ${PG_BIN_DIR}/pg_basebackup \
        -w -X fetch -v -P --format=t ${EXTRA_OPTS} \
        -D - | lbzip2 -n 2 -9 > ${PG_BACKUP_DIR}/backup.tar.bz2
  else
    echo "Used host: ${REPLICATION_HOST}"
    sudo -Hu ${PG_USER} \
        PGPASSWORD=${REPLICATION_PASS} ${PG_BIN_DIR}/pg_basebackup \
        -h ${REPLICATION_HOST} -p ${REPLICATION_PORT} -U ${REPLICATION_USER} -w -X fetch -v -P --format=t ${EXTRA_OPTS} \
        -D - | lbzip2 -n 2 -9 > ${PG_BACKUP_DIR}/backup.tar.bz2
  fi
  rotate_backup
  exit 0
fi

 # Check backup
if [[ -n ${PG_CHECK} ]]; then

  echo "Check backup..."
  if [[ -z ${DB_NAME} ]]; then
    echo "Unknown database. DB_NAME does not null"
    exit 1;
  fi

  if [[ ! -d ${PG_DATA_DIR} ]]; then
    import_backup ${PG_CHECK}
  fi
  remove_recovery_file
  CHECK=$(echo "SELECT datname FROM pg_database WHERE lower(datname) = lower('${DB_NAME}');" | \
    sudo -Hu ${PG_USER} ${PG_BIN_DIR}/postgres --single \
      -D ${PG_DATA_DIR} -c config_file=${PG_CONF_DIR}/postgresql.conf)

  if [[ $(echo ${CHECK} | grep -w ${DB_NAME} | wc -l) == 1 ]]; then
    echo "Success checking backup"
  else
    echo "Fail checking backup"
    exit 1
  fi

  exit 0
fi

# Restore from backup
if [[ ! -d ${PG_DATA_DIR} && -n ${PG_RESTORE} ]]; then
  if [[ -n ${PG_RESTORE} ]]; then
      echo "Import backup..."
      import_backup ${PG_RESTORE}
  fi
fi

if [[ ! -d ${PG_DATA_DIR} && ${PG_MODE} == master_restore ]]; then
  sudo -Hu ${PG_USER} \
    PGPASSWORD=${REPLICATION_PASS} ${PG_BIN_DIR}/pg_basebackup -D ${PG_DATA_DIR} \
    -h ${REPLICATION_HOST} -p ${REPLICATION_PORT} -U ${REPLICATION_USER} -w -X fetch -v -P
fi

# Create snapshot
if [[ ! -d ${PG_DATA_DIR} && ${PG_MODE} == snapshot ]]; then
  echo "Snapshot database..."
  sudo -Hu ${PG_USER} \
    PGPASSWORD=${REPLICATION_PASS} ${PG_BIN_DIR}/pg_basebackup -D ${PG_DATA_DIR} \
    -h ${REPLICATION_HOST} -p ${REPLICATION_PORT} -U ${REPLICATION_USER} -w -X stream -v -P

fi

# Create slave
if [[ ${PG_MODE} =~ ^slave && ! -f /tmp/.CONFIGURE_2 ]]; then
   echo "Replicating database..."
  if [[ ! -d ${PG_DATA_DIR} ]]; then
    # Setup streaming replication.
    sudo -Hu ${PG_USER} \
      PGPASSWORD=${REPLICATION_PASS} ${PG_BIN_DIR}/pg_basebackup -D ${PG_DATA_DIR} \
      -h ${REPLICATION_HOST} -p ${REPLICATION_PORT} -U ${REPLICATION_USER} -w -X stream -v -P
  fi
  echo "Setting up hot standby configuration..."
  cat >> ${PG_CONF_DIR}/postgresql.conf <<EOF
hot_standby = on
EOF
  sudo -Hu ${PG_USER} touch ${PG_DATA_DIR}/recovery.conf
  cat >> ${PG_DATA_DIR}/recovery.conf <<EOF
standby_mode = 'on'
primary_conninfo = 'host=${REPLICATION_HOST} port=${REPLICATION_PORT} user=${REPLICATION_USER} password=${REPLICATION_PASS} sslmode=${PG_SSLMODE}'
trigger_file = '/tmp/postgresql.trigger'
EOF
  touch /tmp/.CONFIGURE_2
fi

# Initializing database
if [[ ! -d ${PG_DATA_DIR} ]]; then
  # check if we need to perform data migration
  PG_OLD_VERSION=$(find ${PG_HOME}/[0-9].[0-9]/main -maxdepth 1 -name PG_VERSION 2>/dev/null | sort -r | head -n1 | cut -d'/' -f5)

  echo "Initializing database..."
  sudo -Hu ${PG_USER} ${PG_BIN_DIR}/initdb --pgdata=${PG_DATA_DIR} \
    --username=${PG_USER} --encoding=unicode --auth=trust >/dev/null
  touch /tmp/.EMPTY_DB
fi

if [[ -n ${PG_OLD_VERSION} ]]; then
  echo "Migrating postgresql ${PG_OLD_VERSION} data..."
  PG_OLD_CONFDIR="/etc/postgresql/${PG_OLD_VERSION}/main"
  PG_OLD_BINDIR="/usr/lib/postgresql/${PG_OLD_VERSION}/bin"
  PG_OLD_DATADIR="${PG_HOME}/${PG_OLD_VERSION}/main"

  # backup ${PG_OLD_DATADIR} to avoid data loss
  PG_BKP_SUFFIX=$(date +%Y%m%d%H%M%S)
  echo "Backing up ${PG_OLD_DATADIR} to ${PG_OLD_DATADIR}.${PG_BKP_SUFFIX}..."
  cp -a ${PG_OLD_DATADIR} ${PG_OLD_DATADIR}.${PG_BKP_SUFFIX}

  echo "Installing postgresql-${PG_OLD_VERSION}..."
  apt-get update
  apt-get install postgresql-${PG_OLD_VERSION} postgresql-client-${PG_OLD_VERSION}
  rm -rf /var/lib/apt/lists/*

  # migrate ${PG_OLD_VERSION} data
  echo "Migration in progress. This could take a while, please be patient..."
  sudo -Hu ${PG_USER} ${PG_BIN_DIR}/pg_upgrade \
    -b ${PG_OLD_BINDIR} -B ${PG_BIN_DIR} \
    -d ${PG_OLD_DATADIR} -D ${PG_DATA_DIR} \
    -o "-c config_file=${PG_OLD_CONFDIR}/postgresql.conf" \
    -O "-c config_file=${PG_CONF_DIR}/postgresql.conf" >/dev/null
fi

# Create databases and users
if [[ -f /tmp/.EMPTY_DB && ( -z ${PG_MODE} || ${PG_MODE} =~ ^master ) ]]; then

  if [[ ${PG_MODE} =~ ^master ]]; then
      remove_recovery_file
      echo "Creating user \"${REPLICATION_USER}\"..."
      echo "CREATE ROLE ${REPLICATION_USER} WITH REPLICATION LOGIN ENCRYPTED PASSWORD '${REPLICATION_PASS}';" |
        sudo -Hu ${PG_USER} ${PG_BIN_DIR}/postgres --single \
          -D ${PG_DATA_DIR} -c config_file=${PG_CONF_DIR}/postgresql.conf >/dev/null
  fi

  if [[ -n ${DB_USER} ]]; then
    if [[ -z ${DB_PASS} ]]; then
      echo ""
      echo "WARNING: "
      echo "  Please specify a password for \"${DB_USER}\". Skipping user creation..."
      echo ""
      DB_USER=
    else
      echo "Creating user \"${DB_USER}\"..."
      echo "CREATE ROLE ${DB_USER} with LOGIN CREATEDB PASSWORD '${DB_PASS}';" |
        sudo -Hu ${PG_USER} ${PG_BIN_DIR}/postgres --single \
          -D ${PG_DATA_DIR} -c config_file=${PG_CONF_DIR}/postgresql.conf >/dev/null
    fi
  fi

  if [[ -n ${DB_NAME} ]]; then
    for db in $(awk -F',' '{for (i = 1 ; i <= NF ; i++) print $i}' <<< "${DB_NAME}"); do
      echo "Creating database \"${db}\"..."

      echo "CREATE DATABASE ${db} ENCODING = 'UTF8' LC_COLLATE = '${DB_LOCALE}' LC_CTYPE = '${DB_LOCALE}' TEMPLATE = template0;" | \
      sudo -Hu ${PG_USER} ${PG_BIN_DIR}/postgres --single \
        -D ${PG_DATA_DIR} -c config_file=${PG_CONF_DIR}/postgresql.conf >/dev/null

      if [[ ${DB_UNACCENT} == true ]]; then
        echo "Installing unaccent extension..."
        echo "CREATE EXTENSION IF NOT EXISTS unaccent;" | \
          sudo -Hu ${PG_USER} ${PG_BIN_DIR}/postgres --single ${db} \
            -D ${PG_DATA_DIR} -c config_file=${PG_CONF_DIR}/postgresql.conf >/dev/null
      fi

      if [[ -n ${DB_USER} ]]; then
        echo "Granting access to database \"${db}\" for user \"${DB_USER}\"..."
        echo "GRANT ALL PRIVILEGES ON DATABASE ${db} to ${DB_USER};" |
          sudo -Hu ${PG_USER} ${PG_BIN_DIR}/postgres --single \
            -D ${PG_DATA_DIR} -c config_file=${PG_CONF_DIR}/postgresql.conf >/dev/null
      fi
    done
  fi

  rm -f /tmp/.EMPTY_DB
fi

echo "Starting PostgreSQL server..."
exec start-stop-daemon --start --chuid ${PG_USER}:${PG_USER} --exec ${PG_BIN_DIR}/postgres -- \
  -D ${PG_DATA_DIR} -c config_file=${PG_CONF_DIR}/postgresql.conf -c timezone=${PG_TZ}