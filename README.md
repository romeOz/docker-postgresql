Independent fork by [sameersbn/docker-postgresql](https://github.com/sameersbn/docker-postgresql).

Table of Contents
-------------------

 * [Installation](#installation)
 * [Quick Start](#quick-start)
 * [Persistence](#persistence)
 * [Creating user and database](#creating-user-and-database-at-launch)
 * [Creating a Snapshot or Slave Database](#creating-a-snapshot-or-slave-database)
 * [Search plain text with accent](#enable-unaccent-search-plain-text-with-accent)
 * [Host UID / GID Mapping](#host-uid--gid-mapping)
 * **[Backup of a PostgreSQL cluster](#backup-of-a-postgresql-cluster)**
 * **[Checking backup](#checking-backup)**
 * **[Restore from backup](#restore-from-backup)**
 * [Dumping database](#dumping-database)
 * [Logging](#logging)
 * [Upgrading](#upgrading)
 
> Bolded features are different from [sameersbn/docker-postgresql](https://github.com/sameersbn/docker-postgresql).


Installation
-------------------

 * [Install Docker](https://docs.docker.com/installation/) or [askubuntu](http://askubuntu.com/a/473720)
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

Run the postgresql image:

```bash
docker run --name postgresql -d romeoz/docker-postgresql
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
  -v /host/to/path/data:/var/lib/postgresql romeoz/postgresql
```

This will make sure that the data stored in the database is not lost when the image is stopped and started again.

Creating User and Database at Launch
-------------------

The image allows you to create a user and database at launch time.

To create a new user you should specify the `DB_USER` and `DB_PASS` variables. The following command will create a new user *dbuser* with the password *dbpass*.

```bash
docker run --name postgresql -d \
  -e 'DB_USER=dbuser' -e 'DB_PASS=dbpass' \
  romeoz/postgresql
```

**NOTE**
- If the password is not specified the user will not be created
- If the user user already exists no changes will be made

Similarly, you can also create a new database by specifying the database name in the `DB_NAME` variable.

```bash
docker run --name postgresql -d \
  -e 'DB_NAME=dbname' romeoz/postgresql
```

You may also specify a comma separated list of database names in the `DB_NAME` variable. The following command creates two new databases named *dbname1* and *dbname2* (p.s. this feature is only available in releases greater than 9.1-1).

```bash
docker run --name postgresql -d \
  -e 'DB_NAME=dbname1,dbname2' \
  romeoz/postgresql
```

If the `DB_USER` and `DB_PASS` variables are also specified while creating the database, then the user is granted access to the database(s).

For example,

```bash
docker run --name postgresql -d \
  -e 'DB_USER=dbuser' -e 'DB_PASS=dbpass' -e 'DB_NAME=dbname' \
  romeoz/postgresql
```

will create a user *dbuser* with the password *dbpass*. It will also create a database named *dbname* and the *dbuser* user will have full access to the *dbname* database.

The `PG_TRUST_LOCALNET` environment variable can be used to configure postgres to trust connections on the same network.  This is handy for other containers to connect without authentication. To enable this behavior, set `PG_TRUST_LOCALNET` to `true`.

For example,

```bash
docker run --name postgresql -d \
  -e 'PG_TRUST_LOCALNET=true' \
  romeoz/postgresql
```

This has the effect of adding the following to the `pg_hba.conf` file:

```
host    all             all             samenet                 trust
```

Creating a Snapshot or Slave Database
-------------------

You may use the `PG_MODE` variable along with `REPLICATION_HOST`, `REPLICATION_PORT`, `REPLICATION_USER` and `REPLICATION_PASS` to create a snapshot of an existing database and enable stream replication.

Your master database must support replication or super-user access for the credentials you specify. The `PG_MODE` variable should be set to `master`, for replication on your master node and `slave` or `snapshot` respectively for streaming replication or a point-in-time snapshot of a running instance.

Create a master instance

```bash
docker run --name='psql-master' -d \
  -e 'PG_MODE=master' -e 'PG_TRUST_LOCALNET=true' \
  -e 'REPLICATION_USER=replicator' -e 'REPLICATION_PASS=replicatorpass' \
  -e 'DB_NAME=dbname' -e 'DB_USER=dbuser' -e 'DB_PASS=dbpass' \
  romeoz/postgresql
```

Create a streaming replication instance

```bash
docker run --name='psql-slave' -d  \
  --link psql-master:psql-master  \
  -e 'PG_MODE=slave' -e 'PG_TRUST_LOCALNET=true' \
  -e 'REPLICATION_HOST=psql-master' -e 'REPLICATION_PORT=5432' \
  -e 'REPLICATION_USER=replicator' -e 'REPLICATION_PASS=replicatorpass' \
  romeoz/postgresql
```

Backup of a PostgreSQL cluster
-------------------

The backup is made over a regular PostgreSQL connection, and uses the replication protocol (used [pg_basebackup](http://www.postgresql.org/docs/9.4/static/app-pgbasebackup.html)).

First we need to raise the master:

```bash
docker run --name='psql-master' -d \
  -e 'PG_MODE=master' -e 'PG_TRUST_LOCALNET=true' \
  -e 'REPLICATION_USER=replicator' -e 'REPLICATION_PASS=replicatorpass' \
  -e 'DB_NAME=dbname' -e 'DB_USER=dbuser' -e 'DB_PASS=dbpass' \
  romeoz/postgresql
```

Next, create a temporary container for backup:

```bash
docker run -it --rm \
  --link psql-master:psql-master \
  -e 'PG_MODE=backup' \
  -e 'REPLICATION_HOST=psql-master' \
  -e 'REPLICATION_PORT=5432' \
  -e 'REPLICATION_USER=replicator' \
  -e 'REPLICATION_PASS=replicatorpass' \
  -e 'PG_TRUST_LOCALNET=true' \
  -v /host/to/path/backup:/tmp/backup \
  romeoz/postgresql
```  
Archive will be available in the `/host/to/path/backup`.

> Algorithm: one backup per week (total 4), one backup per month (total 12) and the last backup. Example: `backup.last.tar.bz2`, `backup.1.tar.bz2` and `/backup.dec.tar.bz2`.


Checking backup
-------------------

Check-data is the name of database `DB_NAME`. 

```bash
docker run --name='backup-check' -it --rm \
  -e 'PG_MODE=check_backup' \
  -e 'DB_NAME=foo' \
  -v /host/to/path/backup:/tmp/backup \
  romeoz/postgresql
```

Default used the last backup. To modify, you must specify a environment variable `PG_BACKUP_FILENAME`.

Restore from backup
-------------------

```bash
docker run --name='db_restore' -d \
  -e 'PG_MODE=restore' \
  -v /host/to/path/backup:/tmp/backup \
  romeoz/postgresql
```

For restore default  used the last backup. To modify, you must specify a environment variable `PG_BACKUP_FILENAME`.

Dumping database
-------------------

Create a database named "foo":

```bash
docker run --name db -d -e 'DB_NAME=foo' \
  -v /to/path/backup:/tmp/backup \
  romeoz/postgresql
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
  romeoz/postgresql
  
docker exec -it restore_db bash -c \
  'lbzip2 -dc -n 2 /tmp/backup/backup.tar.bz2 | $(sudo -u postgres pg_restore --create --verbose -d template1)'  
``` 
>Instead of volumes you can use the command `docker cp /to/path/backup/backup.tar.bz2 restore_db:/tmp/backup/backup.tar.bz2`.


Enable Unaccent (Search plain text with accent)
-------------------

Unaccent is a text search dictionary that removes accents (diacritic signs) from lexemes. It's a filtering dictionary, which means its output is always passed to the next dictionary (if any), unlike the normal behavior of dictionaries. This allows accent-insensitive processing for full text search.

By default unaccent is configure to `false`

```bash
docker run --name postgresql -d \
  -e 'DB_UNACCENT=true' \
  romeoz/postgresql
```

Host UID / GID Mapping
-------------------

Per default the container is configured to run postgres as user and group `postgres` with some unknown `uid` and `gid`. The host possibly uses these ids for different purposes leading to unfavorable effects. From the host it appears as if the mounted data volumes are owned by the host's user/group `[whatever id postgres has in the image]`.

Also the container processes seem to be executed as the host's user/group `[whatever id postgres has in the image]`. The container can be configured to map the `uid` and `gid` of `postgres` to different ids on host by passing the environment variables `USERMAP_UID` and `USERMAP_GID`. The following command maps the ids to user and group `postgres` on the host.

```bash
docker run --name=postgresql -it --rm [options] \
  --env="USERMAP_UID=$(id -u postgres)" --env="USERMAP_GID=$(id -g postgres)" \
  romeoz/postgresql
```

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

Create the file /etc/logrotate.d/docker-containers with the following text inside:

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

Upgrading
-------------------

To upgrade to newer releases, simply follow this 3 step upgrade procedure.

- **Step 1**: Stop the currently running image

```bash
docker stop postgresql
```

- **Step 2**: Update the docker image.

```bash
docker pull romeoz/postgresql
```

- **Step 3**: Start the image

```bash
docker run --name postgresql -d [OPTIONS] romeoz/postgresql
```

Out of the box
-------------------
 * Ubuntu 14.04.3 (LTS)
 * PostgreSQL 9.4.4

License
-------------------

PostgreSQL container image is open-sourced software licensed under the [MIT license](http://opensource.org/licenses/MIT)