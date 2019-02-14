Table of Contents
-------------------

 * [Installation](#installation)
 * [Quick Start](#quick-start)
 * [Persistence](#persistence)
 * [Creating user and database](#creating-user-and-database-at-run)
 * [Creating Database with specified locale](#creating-database-with-specified-locale-at-run)  
 * [Backuping](#backuping)
 * [Checking backup](#checking-backup)
 * [Restore from backup](#restore-from-backup)
 * [Dumping database](#dumping-database)
 * [Replication - Master/Slave](#replication---masterslave)
 * [Search plain text with accent](#enable-unaccent-search-plain-text-with-accent)
 * [Host UID / GID Mapping](#host-uid--gid-mapping)
 * [Environment variables](#environment-variables)
 * [Logging](#logging) 
 * [Out of the box](#out-of-the-box)
 
Installation
-------------------

 * [Install Docker 1.9+](https://docs.docker.com/installation/) or [askubuntu](http://askubuntu.com/a/473720)
 * Pull the latest version of the image.
 
```bash
docker pull romeoz/docker-postgresql
```

Alternately you can build the image yourself.

```bash
git clone https://github.com/romeoz/docker-postgresql.git
cd docker-postgresql
docker build -t="$USER/postgresql" .
```

Quick Start
-------------------

Run the postgresql container:

```bash
docker run --name postgresql -d -p 5432:5432 romeoz/docker-postgresql
```

The simplest way to login to the postgresql container as the administrative `postgres` user is to use the `docker exec` command to attach a new process to the running container and connect to the postgresql server over the unix socket.

```bash
docker exec -it postgresql sudo -u postgres psql
```

Persistence
-------------------

For data persistence a volume should be mounted at `/var/lib/postgresql`.

SELinux users are also required to change the security context of the mount point so that it plays nicely with selinux.

```bash
mkdir -p /to/path/data
sudo chcon -Rt svirt_sandbox_file_t /to/path/data
```

The updated run command looks like this.

```bash
docker run --name postgresql -d \
  -v /host/to/path/data:/var/lib/postgresql romeoz/docker-postgresql
```

This will make sure that the data stored in the database is not lost when the container is stopped and started again.

Creating User and Database at run
-------------------

The container allows you to create a user and database at run time.

To create a new user you should specify the `DB_USER` and `DB_PASS` variables. The following command will create a new user *dbuser* with the password *dbpass*.

```bash
docker run --name postgresql -d \
  -e 'DB_USER=dbuser' -e 'DB_PASS=dbpass' \
  romeoz/docker-postgresql
```

**NOTE**
- If the password is not specified the user will not be created
- If the user user already exists no changes will be made

Similarly, you can also create a new database by specifying the database name in the `DB_NAME` variable.

```bash
docker run --name postgresql -d \
  -e 'DB_NAME=dbname' romeoz/docker-postgresql
```

You may also specify a comma separated list of database names in the `DB_NAME` variable. The following command creates two new databases named *dbname1* and *dbname2* (p.s. this feature is only available in releases greater than 9.1-1).

```bash
docker run --name postgresql -d \
  -e 'DB_NAME=dbname1,dbname2' \
  romeoz/docker-postgresql
```

If the `DB_USER` and `DB_PASS` variables are also specified while creating the database, then the user is granted access to the database(s).

For example,

```bash
docker run --name postgresql -d \
  -e 'DB_USER=dbuser' -e 'DB_PASS=dbpass' -e 'DB_NAME=dbname' \
  romeoz/docker-postgresql
```

will create a user *dbuser* with the password *dbpass*. It will also create a database named *dbname* and the *dbuser* user will have full access to the *dbname* database.

The `PG_TRUST_LOCALNET` environment variable can be used to configure postgres to trust connections on the same network.  This is handy for other containers to connect without authentication. To enable this behavior, set `PG_TRUST_LOCALNET` to `true`.

For example,

```bash
docker run --name postgresql -d \
  -e 'PG_TRUST_LOCALNET=true' \
  romeoz/docker-postgresql
```

This has the effect of adding the following to the `pg_hba.conf` file:

```
host    all             all             samenet                 trust
```

Creating Database with specified locale at run
-------------------

```bash
docker run --name postgresql -d \
  -e 'PG_LOCALE=ru_RU.UTF-8' -e 'DB_NAME=dbname' romeoz/docker-postgresql
```

or after run container

```bash
docker run --name postgresql -d \
  -e 'PG_LOCALE=ru_RU.UTF-8' romeoz/docker-postgresql

docker exec -it postgresql bash -c 'sudo -u postgres psql'
CREATE DATABASE dbname ENCODING = 'UTF8'  LC_COLLATE = 'ru_RU.UTF-8' LC_CTYPE = 'ru_RU.UTF-8' TEMPLATE = template0; 
```

Backuping
-------------------

The backup is made over a regular PostgreSQL connection, and uses the replication protocol (used [pg_basebackup](http://www.postgresql.org/docs/9.5/static/app-pgbasebackup.html)).

First we need to raise the master:

```bash
docker network create pg_net

docker run --name='psql-master' -d \
  --net pg_net
  -e 'PG_MODE=master' \
  -e 'DB_NAME=dbname' \
  -e 'PG_TRUST_LOCALNET=true' \
  romeoz/docker-postgresql
```

Next, create a temporary container for backup:

```bash
docker run -it --rm \
  --net pg_net \
  -e 'PG_MODE=backup' \
  -e 'REPLICATION_HOST=psql-master' \
  -e 'PG_TRUST_LOCALNET=true' \
  -v /host/to/path/backup:/tmp/backup \
  romeoz/docker-postgresql
```  
Archive will be available in the `/host/to/path/backup`.

> Algorithm: one backup per week (total 4), one backup per month (total 12) and the last backup. Example: `backup.last.tar.bz2`, `backup.1.tar.bz2` and `/backup.dec.tar.bz2`.

You can disable the rotation by using env `PG_ROTATE_BACKUP=false`.
 	
Backuping slave requires that the slave was created with the WAL-settings.

```bash
docker run --name psql-slave -d \
  --net pg_net \
  -e 'PG_MODE=slave_wal' -e 'PG_TRUST_LOCALNET=true' -e 'REPLICATION_HOST=psql-master' \
  romeoz/docker-postgresql
```

>So, you can used for restoring master

Next, create a temporary container for backup:

```bash
docker run -it --rm \
  --net pg_net \
  -e 'PG_MODE=backup' -e 'REPLICATION_HOST=psql-slave' 
  -v -v /host/to/path/backup_slave:/tmp/backup \
  romeoz/docker-postgresql
```

Checking backup
-------------------

As the check-parameter is used a database name `DB_NAME`.

```bash
docker run -it --rm \
    -e 'PG_CHECK=default' \
    -e 'DB_NAME=foo' \
    -v /host/to/path/backup:/tmp/backup \
    romeoz/docker-postgresql
```

Default used the `/tmp/backup/backup.last.bz2`.

Restore from backup
-------------------

###Restore from backup file

```bash
docker run --name='psql-master' -d \
  -e 'PG_MODE=master' \
  -e 'PG_RESTORE=default' \
  -v /host/to/path/backup_master:/tmp/backup \
  romeoz/docker-postgresql
```

or for slave

```bash
docker run --name='psql-slave' -d \
  -e 'PG_MODE=slave' \
  -e 'PG_RESTORE=default' \
  -v /host/to/path/backup_master:/tmp/backup \
  romeoz/docker-postgresql
```

>Can be used files backup-master or backup-slave.

###Restore master from slave with WAL

```bash
docker run --name master -d \
  --net pg_net \
  -e 'PG_MODE=master_restore' \
  -e 'PG_TRUST_LOCALNET=true' -e 'REPLICATION_HOST=slave_wal' \
  romeoz/docker-postgresql
```

Dumping database
-------------------

Create a database named "foo":

```bash
docker run --name db -d -e 'DB_NAME=foo' \
  -v /to/path/backup:/tmp/backup \
  romeoz/docker-postgresql
```  
  
Dumping database to /tmp/backup/:

```bash
docker exec -it db bash -c \
  'sudo -u postgres pg_dump --dbname=foo --format=tar | lbzip2 -n 2 -9 > /tmp/backup/backup.tar.bz2'
```

Restore database:

```bash
docker run --name restore_db -d \
  -v /to/path/backup:/tmp/backup \
  romeoz/docker-postgresql
  
docker exec -it restore_db bash -c \
  'lbzip2 -dc -n 2 /tmp/backup/backup.tar.bz2 | $(sudo -u postgres pg_restore --create --verbose -d template1)'  
``` 
>Instead of volumes you can use the command `docker cp /to/path/backup/backup.tar.bz2 restore_db:/tmp/backup/backup.tar.bz2` (support Docker 1.8+).

Replication - Master/Slave
-------------------------

You may use the `PG_MODE` variable along with `REPLICATION_HOST`, `REPLICATION_PORT`, `REPLICATION_USER` and `REPLICATION_PASS` to create a snapshot of an existing database and enable stream replication.

Your master database must support replication or super-user access for the credentials you specify. The `PG_MODE` variable should be set to `master`, for replication on your master node and `slave` or `snapshot` respectively for streaming replication or a point-in-time snapshot of a running instance.

Create a master instance

```bash
docker network create pg_net

docker run --name='psql-master' -d \
  --net pg_net \
  -e 'PG_MODE=master' -e 'PG_TRUST_LOCALNET=true' \
  -e 'REPLICATION_USER=replicator' -e 'REPLICATION_PASS=replicatorpass' \
  -e 'DB_NAME=dbname' -e 'DB_USER=dbuser' -e 'DB_PASS=dbpass' \
  romeoz/docker-postgresql
```

Create a slave instance + fast import backup from master

```bash
docker run --name='psql-slave' -d  \
  --net pg_net  \
  -e 'PG_MODE=slave' -e 'PG_TRUST_LOCALNET=true' \
  -e 'REPLICATION_HOST=psql-master' -e 'REPLICATION_PORT=5432' \
  -e 'REPLICATION_USER=replicator' -e 'REPLICATION_PASS=replicatorpass' \
  romeoz/docker-postgresql
```

Enable Unaccent (Search plain text with accent)
-------------------

Unaccent is a text search dictionary that removes accents (diacritic signs) from lexemes. It's a filtering dictionary, which means its output is always passed to the next dictionary (if any), unlike the normal behavior of dictionaries. This allows accent-insensitive processing for full text search.

By default unaccent is configure to `false`

```bash
docker run --name postgresql -d \
  -e 'DB_UNACCENT=true' \
  romeoz/docker-postgresql
```

Host UID / GID Mapping
-------------------

Per default the container is configured to run postgres as user and group `postgres` with some unknown `uid` and `gid`. The host possibly uses these ids for different purposes leading to unfavorable effects. From the host it appears as if the mounted data volumes are owned by the host's user/group `[whatever id postgres has in the image]`.

Also the container processes seem to be executed as the host's user/group `[whatever id postgres has in the image]`. The container can be configured to map the `uid` and `gid` of `postgres` to different ids on host by passing the environment variables `USERMAP_UID` and `USERMAP_GID`. The following command maps the ids to user and group `postgres` on the host.

```bash
docker run --name=postgresql -it --rm [options] \
  --env="USERMAP_UID=$(id -u postgres)" --env="USERMAP_GID=$(id -g postgres)" \
  romeoz/docker-postgresql
```

Environment variables
---------------------

`PG_USER`: Set a specific username for the admin account (default "postgres").

`PG_LOCALE` (alias `OS_LOCALE`): Set a locale DB (default "en_US.UTF-8").

`PG_TZ`:  Set a timezone DB (default "UTC").

`PG_MODE`: Set a specific mode. Takes on the values `master`, `slave` or `backup`.

`PG_BACKUP_DIR`: Set a specific backup directory (default "/tmp/backup").

`PG_BACKUP_FILENAME`: Set a specific filename backup (default "backup.last.bz2").

`PG_CHECK`: Defines name of backup-file to initialize the database. Note that the backup must be inside the container, so you may need to mount them. You can specify as `default` that is equivalent to the `/tmp/backup/backup.last.bz2`

`PG_RESTORE`: Defines name of backup-file to initialize the database. Note that the backup must be inside the container, so you may need to mount them. You can specify as `default` that is equivalent to the `/tmp/backup/backup.last.bz2`

`PG_ROTATE_BACKUP`: Determines whether to use the rotation of backups (default "true").

`REPLICATION_PORT`: Set a specific replication port for the master instance (default "5432").

`REPLICATION_USER`: Set a specific replication username for the master instance (default "replica").

`REPLICATION_PASS`: Set a specific replication password for the master instance (default "replica").

`PG_TRUST_LOCALNET`: Set this env variable to true to enable a line in the pg_hba.conf file to trust samenet. This can be used to connect from other containers on the same host without authentication (default "false").

`PG_SSLMODE`: Set this env variable to "require" to enable encryption and "verify-full" for verification (default "disable").

Logging
-------------------

All the logs are forwarded to stdout and sterr. You have use the command `docker logs`.

```bash
docker logs postgresql
```

####Split the logs

You can then simply split the stdout & stderr of the container by piping the separate streams and send them to files:

```bash
docker logs postgresql > stdout.log 2>stderr.log
cat stdout.log
cat stderr.log
```

or split stdout and error to host stdout:

```bash
docker logs postgresql > -
docker logs postgresql 2> -
```

####Rotate logs

Create the file `/etc/logrotate.d/docker-containers` with the following text inside:

```
/var/lib/docker/containers/*/*.log {
    rotate 31
    daily
    nocompress
    missingok
    notifempty
    copytruncate
}
```
> Optionally, you can replace `nocompress` to `compress` and change the number of days.

Out of the box
-------------------
 * Ubuntu 16.04/18.04 LTS
 * PostgreSQL 9.3, 9.4, 9.5, 9.6, 10 or 11

License
-------------------

PostgreSQL docker image is open-sourced software licensed under the [MIT license](http://opensource.org/licenses/MIT)