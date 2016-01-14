#!/bin/bash

set -e

echo "-- Building PostgreSQL 9.5 image"
docker build -t psg-9.5 ../9.5/

echo
echo "-- Testing PostgreSQL 9.5 is running"
docker run --name base_1 -d psg-9.5; sleep 5
docker run --name base_2 -d --link base_1:base_1 psg-9.5; sleep 10
docker exec -it base_2 bash -c 'pg_isready -h ${BASE_1_PORT_5432_TCP_ADDR} -p 5432 | grep -c "accepting"'
echo
echo "-- Clear"
docker rm -f -v $(sudo docker ps -aq); sleep 5

echo
echo "-- Testing backup/checking on PostgreSQL 9.5"
docker run --name base_1 -d -e 'PG_MODE=master' -e 'DB_NAME=db_1,test_1' psg-9.5; sleep 10
echo "-- Backup"
docker run -it --rm --link base_1:base_1 -e 'PG_MODE=backup' -e 'REPLICATION_HOST=base_1' -e 'REPLICATION_PORT=5432' -v $(pwd)/vol95/backup:/tmp/backup psg-9.5 | grep -wc 'backup completed'; sleep 10
echo "-- Check"
docker run -it --rm -e 'PG_CHECK=default' -e 'DB_NAME=db_1' -v $(pwd)/vol95/backup:/tmp/backup psg-9.5 | tail -n 1 | grep -c 'Success'; sleep 5
docker run -it --rm -e 'PG_CHECK=/tmp/backup/backup.last.tar.bz2' -e 'DB_NAME=test_1' -v $(pwd)/vol95/backup:/tmp/backup psg-9.5 | tail -n 1 | grep -c 'Success'; sleep 5
docker run -it --rm -e 'PG_CHECK=default' -e 'DB_NAME=db' -v $(pwd)/vol95/backup:/tmp/backup psg-9.5 | tail -n 1 | grep -c 'Fail'; sleep 5
echo
echo "-- Clear"
docker rm -f -v $(sudo docker ps -aq); sleep 5
rm -rf vol95*


echo
echo
echo "-- Testing master/slave on PostgreSQL 9.5"
echo
echo "-- Create master"
docker run --name base_1 -d -e 'PG_MODE=master' -e 'DB_NAME=db_1,test_1' psg-9.5; sleep 10
docker exec -it base_1 sudo -u postgres psql test_1 -c "CREATE TABLE foo (id SERIAL, name VARCHAR); INSERT INTO foo (name) VALUES ('Petr');"
echo
echo "-- Create slave"
docker run --name base_2 -d --link base_1:base_1 -e 'PG_MODE=slave' -e 'PG_TRUST_LOCALNET=true' -e 'REPLICATION_HOST=base_1' -e 'REPLICATION_USER=replica' -e 'REPLICATION_PASS=replica' psg-9.5; sleep 10
docker run --name base_3 -d --link base_1:base_1 -e 'PG_MODE=slave' -e 'PG_TRUST_LOCALNET=true' -e 'REPLICATION_HOST=base_1' psg-9.5; sleep 10
docker exec -it base_1 sudo -u postgres psql test_1 -c "INSERT INTO foo (name) VALUES ('Tom');"; sleep 5
docker exec -it base_3 bash -c 'sudo -u postgres psql test_1 -c "SELECT * FROM foo;"  | grep -c -w "Tom"'
echo
echo "-- Backup"
docker run -it --rm --link base_1:base_1 -e 'PG_MODE=backup' -e 'REPLICATION_HOST=base_1' -e 'REPLICATION_PORT=5432' -v $(pwd)/vol95/backup_master:/tmp/backup psg-9.5 | grep -wc 'backup completed'; sleep 10
echo
echo "-- Restore slave from backup-master"
docker run --name base_4 -d --link base_1:base_1 -e 'PG_MODE=slave' -e 'PG_TRUST_LOCALNET=true' -e 'REPLICATION_HOST=base_1' -e 'PG_RESTORE=default'  -v $(pwd)/vol95/backup_master:/tmp/backup psg-9.5; sleep 10
docker exec -it base_1 sudo -u postgres psql test_1 -c "INSERT INTO foo (name) VALUES ('Bob');"; sleep 5
docker exec -it base_3 bash -c 'sudo -u postgres psql test_1 -c "SELECT * FROM foo;"  | grep -c -w "Bob"'
docker exec -it base_4 bash -c 'sudo -u postgres psql test_1 -c "SELECT COUNT(*) FROM foo;" | grep -c -w "3"'
echo
echo "-- Clear"
docker rm -f -v $(sudo docker ps -aq); sleep 5

echo
echo "-- Restore master from backup-master"
docker run --name base_1 -d -e 'PG_MODE=master' -e 'PG_RESTORE=default'  -v $(pwd)/vol95/backup_master:/tmp/backup psg-9.5; sleep 10
docker run --name base_2 -d --link base_1:base_1 -e 'PG_MODE=slave' -e 'PG_TRUST_LOCALNET=true' -e 'REPLICATION_HOST=base_1' psg-9.5; sleep 10
docker exec -it base_1 sudo -u postgres psql test_1 -c "INSERT INTO foo (name) VALUES ('Jack');"; sleep 5
docker exec -it base_2 bash -c 'sudo -u postgres psql test_1 -c "SELECT * FROM foo;"  | grep -c -w "Jack"'
docker exec -it base_2 bash -c 'sudo -u postgres psql test_1 -c "SELECT COUNT(*) FROM foo;" | grep -c -w "3"'

echo
echo "-- Clear"
docker rm -f -v $(sudo docker ps -aq); sleep 5
rm -rf vol95*

echo
echo "-- Create master"
docker run --name base_1 -d -e 'PG_MODE=master' -e 'DB_NAME=db_1,test_1' psg-9.5; sleep 10
docker exec -it base_1 sudo -u postgres psql test_1 -c "CREATE TABLE foo (id SERIAL, name VARCHAR); INSERT INTO foo (name) VALUES ('Petr');"
echo
echo "-- Create slave"
docker run --name base_2 -d --link base_1:base_1 -e 'PG_MODE=slave' -e 'PG_TRUST_LOCALNET=true' -e 'REPLICATION_HOST=base_1' psg-9.5; sleep 10
docker exec -it base_1 sudo -u postgres psql test_1 -c "INSERT INTO foo (name) VALUES ('Chip');"; sleep 5
echo
echo "-- Create slave with WAL"
docker run --name base_3 -d --link base_1:base_1 -e 'PG_MODE=slave_wal' -e 'PG_TRUST_LOCALNET=true' -e 'REPLICATION_HOST=base_1' psg-9.5; sleep 10

echo
echo "-- Backup"
docker run -it --rm --link base_3:base_3 -e 'PG_MODE=backup' -e 'REPLICATION_HOST=base_3' -e 'REPLICATION_PORT=5432' -v $(pwd)/vol95/backup_slave:/tmp/backup psg-9.5 | grep -wc 'backup completed'; sleep 10
echo
echo "-- Restore slave from backup-slave"
docker run --name base_4 -d --link base_1:base_1 -e 'PG_MODE=slave' -e 'PG_TRUST_LOCALNET=true' -e 'REPLICATION_HOST=base_1' -e 'PG_RESTORE=default'  -v $(pwd)/vol95/backup_slave:/tmp/backup psg-9.5; sleep 10
docker exec -it base_1 sudo -u postgres psql test_1 -c "INSERT INTO foo (name) VALUES ('Jack');"; sleep 5
docker exec -it base_4 bash -c 'sudo -u postgres psql test_1 -c "SELECT * FROM foo;"  | grep -c -w "Chip"'
docker exec -it base_4 bash -c 'sudo -u postgres psql test_1 -c "SELECT * FROM foo;"  | grep -c -w "Jack"'
docker exec -it base_4 bash -c 'sudo -u postgres psql test_1 -c "SELECT COUNT(*) FROM foo;" | grep -c -w "3"'
echo
echo "-- Clear"
docker rm -f -v $(sudo docker ps -aq); sleep 5

echo
echo "-- Restore master from backup-slave"
docker run --name base_1 -d -e 'PG_MODE=master' -e 'PG_RESTORE=default'  -v $(pwd)/vol95/backup_slave:/tmp/backup psg-9.5; sleep 10
docker run --name base_2 -d --link base_1:base_1 -e 'PG_MODE=slave' -e 'PG_TRUST_LOCALNET=true' -e 'REPLICATION_HOST=base_1' psg-9.5; sleep 10
docker exec -it base_1 sudo -u postgres psql test_1 -c "INSERT INTO foo (name) VALUES ('Tom');"; sleep 5
docker exec -it base_2 bash -c 'sudo -u postgres psql test_1 -c "SELECT * FROM foo;"  | grep -c -w "Tom"'
docker exec -it base_2 bash -c 'sudo -u postgres psql test_1 -c "SELECT * FROM foo;"  | grep -c -w "Chip"'
docker exec -it base_2 bash -c 'sudo -u postgres psql test_1 -c "SELECT COUNT(*) FROM foo;" | grep -c -w "3"'

echo
echo "-- Clear"
docker rm -f -v $(sudo docker ps -aq); sleep 5
rm -rf vol95*

echo
echo
echo "-- Testing failover master on PostgreSQL 9.5"
echo
echo "-- Create master"
docker run --name master -d -e 'PG_MODE=master' -e 'DB_NAME=db_1,test_1' psg-9.5; sleep 10
echo
echo "-- Create slaves"
docker run --name slave_1 -d --link master:master -e 'PG_MODE=slave' -e 'PG_TRUST_LOCALNET=true' -e 'REPLICATION_HOST=master' psg-9.5; sleep 10
docker run --name slave_2 -d --link master:master -e 'PG_MODE=slave_wal' -e 'PG_TRUST_LOCALNET=true' -e 'REPLICATION_HOST=master' psg-9.5; sleep 10
docker exec -it master sudo -u postgres psql test_1 -c "CREATE TABLE foo (id SERIAL, name VARCHAR); INSERT INTO foo (name) VALUES ('Petr');"; sleep 5
echo
echo "-- Remove master"
docker rm -f -v master; sleep 5

echo
echo "-- Apply trigger"
docker exec -it slave_2 touch /tmp/postgresql.trigger; sleep 10
docker exec -it slave_2 sudo -u postgres psql test_1 -c "INSERT INTO foo (name) VALUES ('Bob');"; sleep 5

echo
echo "-- Restore master"
docker run --name master -d --link slave_2:slave_2 -e 'PG_MODE=master_restore' -e 'PG_TRUST_LOCALNET=true' -e 'REPLICATION_HOST=slave_2' psg-9.5; sleep 10

echo
echo "-- Remove slaves"
docker rm -f -v slave_1; sleep 5
docker rm -f -v slave_2; sleep 5

echo
echo "-- Create slaves"
docker run --name slave_1 -d --link master:master -e 'PG_MODE=slave' -e 'PG_TRUST_LOCALNET=true' -e 'REPLICATION_HOST=master' psg-9.5; sleep 10
docker run --name slave_2 -d --link master:master -e 'PG_MODE=slave_wal' -e 'PG_TRUST_LOCALNET=true' -e 'REPLICATION_HOST=master' psg-9.5; sleep 10
docker exec -it master sudo -u postgres psql test_1 -c "INSERT INTO foo (name) VALUES ('Linda');"; sleep 5

echo
echo "-- Cheking data"
docker exec -it slave_1 bash -c 'sudo -u postgres psql test_1 -c "SELECT * FROM foo;"  | grep -c -w "Linda"'
docker exec -it slave_1 bash -c 'sudo -u postgres psql test_1 -c "SELECT COUNT(*) FROM foo;" | grep -c -w "3"'
docker exec -it slave_2 bash -c 'sudo -u postgres psql test_1 -c "SELECT * FROM foo;"  | grep -c -w "Bob"'
docker exec -it slave_2 bash -c 'sudo -u postgres psql test_1 -c "SELECT COUNT(*) FROM foo;" | grep -c -w "3"'

echo
echo "-- Clear"
docker rm -f -v $(sudo docker ps -aq); sleep 5
docker rmi psg-9.5
rm -rf vol95*

echo
echo "-- Done"
