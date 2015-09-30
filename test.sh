#!/bin/bash

set -e

echo "-- Building PostgreSQL 9.4 image"
docker build -t psg-9.4 9.4/

echo ""
echo "-- Testing PostgreSQL 9.4 is running"
docker run --name base_1 -d psg-9.4; sleep 5
docker run --name base_2 -d --link base_1:base_1 psg-9.4; sleep 10
docker exec -it base_2 bash -c 'pg_isready -h ${BASE_1_PORT_5432_TCP_ADDR} -p 5432 | grep -c "accepting"'
echo ""
echo "-- Clear"
docker rm -f -v $(sudo docker ps -aq); sleep 5

echo ""
echo "-- Testing backup/checking on PostgreSQL 9.4"
docker run --name base_1 -d -e 'PG_MODE=master' -e 'DB_NAME=db_1,test_1' psg-9.4; sleep 10
echo "--- Backup"
docker run -it --rm --link base_1:base_1 -e 'PG_MODE=backup' -e 'REPLICATION_HOST=base_1' -e 'REPLICATION_PORT=5432' -v $(pwd)/vol94/backup:/tmp/backup psg-9.4 | grep -wc 'backup completed'; sleep 10
echo "--- Check"
docker run -it --rm -e 'PG_CHECK=default' -e 'DB_NAME=db_1' -v $(pwd)/vol94/backup:/tmp/backup psg-9.4 | tail -n 1 | grep -c 'Success'; sleep 5
docker run -it --rm -e 'PG_CHECK=/tmp/backup/backup.last.tar.bz2' -e 'DB_NAME=test_1' -v $(pwd)/vol94/backup:/tmp/backup psg-9.4 | tail -n 1 | grep -c 'Success'; sleep 5
docker run -it --rm -e 'PG_CHECK=default' -e 'DB_NAME=db' -v $(pwd)/vol94/backup:/tmp/backup psg-9.4 | tail -n 1 | grep -c 'Fail'; sleep 5
echo ""
echo "-- Clear"
docker rm -f -v $(sudo docker ps -aq); sleep 5
rm -rf vol94*


echo ""
echo ""
echo "-- Testing master/slave on PostgreSQL 9.4"
echo ""
echo "--- Create master"
docker run --name base_1 -d -e 'PG_MODE=master' -e 'DB_NAME=db_1,test_1' psg-9.4; sleep 10
docker exec -it base_1 sudo -u postgres psql test_1 -c "CREATE TABLE foo (id SERIAL, name VARCHAR); INSERT INTO foo (name) VALUES ('Petr');"
echo ""
echo "--- Create slave"
docker run --name base_2 -d --link base_1:base_1 -e 'PG_MODE=slave' -e 'PG_TRUST_LOCALNET=true' -e 'REPLICATION_HOST=base_1' -e 'REPLICATION_USER=replica' -e 'REPLICATION_PASS=replica' psg-9.4; sleep 10
docker run --name base_3 -d --link base_1:base_1 -e 'PG_MODE=slave' -e 'PG_TRUST_LOCALNET=true' -e 'REPLICATION_HOST=base_1' psg-9.4; sleep 10
docker exec -it base_1 sudo -u postgres psql test_1 -c "INSERT INTO foo (name) VALUES ('Tom');"; sleep 5
docker exec -it base_3 bash -c 'sudo -u postgres psql test_1 -c "SELECT * FROM foo;"  | grep -c -w "Tom"'
echo ""
echo "--- Backup"
docker run -it --rm --link base_1:base_1 -e 'PG_MODE=backup' -e 'REPLICATION_HOST=base_1' -e 'REPLICATION_PORT=5432' -v $(pwd)/vol94/backup_master:/tmp/backup psg-9.4 | grep -wc 'backup completed'; sleep 10
echo ""
echo "--- Recovery slave from backup-master"
docker run --name base_4 -d --link base_1:base_1 -e 'PG_MODE=slave' -e 'PG_TRUST_LOCALNET=true' -e 'REPLICATION_HOST=base_1' -e 'PG_IMPORT=default'  -v $(pwd)/vol94/backup_master:/tmp/backup psg-9.4; sleep 10
docker exec -it base_1 sudo -u postgres psql test_1 -c "INSERT INTO foo (name) VALUES ('Bob');"; sleep 5
docker exec -it base_3 bash -c 'sudo -u postgres psql test_1 -c "SELECT * FROM foo;"  | grep -c -w "Bob"'
docker exec -it base_4 bash -c 'sudo -u postgres psql test_1 -c "SELECT COUNT(*) FROM foo;" | grep -c -w "3"'
echo ""
echo "-- Clear"
docker rm -f -v $(sudo docker ps -aq); sleep 5

echo ""
echo "--- Recovery master from backup-master"
docker run --name base_1 -d -e 'PG_MODE=master' -e 'PG_IMPORT=default'  -v $(pwd)/vol94/backup_master:/tmp/backup psg-9.4; sleep 10
docker run --name base_2 -d --link base_1:base_1 -e 'PG_MODE=slave' -e 'PG_TRUST_LOCALNET=true' -e 'REPLICATION_HOST=base_1' psg-9.4; sleep 10
docker exec -it base_1 sudo -u postgres psql test_1 -c "INSERT INTO foo (name) VALUES ('Jack');"; sleep 5
docker exec -it base_2 bash -c 'sudo -u postgres psql test_1 -c "SELECT * FROM foo;"  | grep -c -w "Jack"'
docker exec -it base_2 bash -c 'sudo -u postgres psql test_1 -c "SELECT COUNT(*) FROM foo;" | grep -c -w "3"'

echo ""
echo "-- Clear"
docker rm -f -v $(sudo docker ps -aq); sleep 5
rm -rf vol94*

echo ""
echo "--- Create master"
docker run --name base_1 -d -e 'PG_MODE=master' -e 'DB_NAME=db_1,test_1' psg-9.4; sleep 10
docker exec -it base_1 sudo -u postgres psql test_1 -c "CREATE TABLE foo (id SERIAL, name VARCHAR); INSERT INTO foo (name) VALUES ('Petr');"
docker run --name base_2 -d --link base_1:base_1 -e 'PG_MODE=slave' -e 'PG_TRUST_LOCALNET=true' -e 'REPLICATION_HOST=base_1' psg-9.4; sleep 10
docker exec -it base_1 sudo -u postgres psql test_1 -c "INSERT INTO foo (name) VALUES ('Chip');"; sleep 5
echo ""
echo "--- Create backup-slave"
docker run --name base_3 -d --link base_1:base_1 -e 'PG_MODE=slave_wal' -e 'PG_TRUST_LOCALNET=true' -e 'REPLICATION_HOST=base_1' psg-9.4; sleep 10

echo ""
echo "--- Backup"
docker run -it --rm --link base_3:base_3 -e 'PG_MODE=backup' -e 'REPLICATION_HOST=base_3' -e 'REPLICATION_PORT=5432' -v $(pwd)/vol94/backup_slave:/tmp/backup psg-9.4 | grep -wc 'backup completed'; sleep 10
echo ""
echo "--- Recovery slave from backup-slave"
docker run --name base_4 -d --link base_1:base_1 -e 'PG_MODE=slave' -e 'PG_TRUST_LOCALNET=true' -e 'REPLICATION_HOST=base_1' -e 'PG_IMPORT=default'  -v $(pwd)/vol94/backup_slave:/tmp/backup psg-9.4; sleep 10
docker exec -it base_1 sudo -u postgres psql test_1 -c "INSERT INTO foo (name) VALUES ('Jack');"; sleep 5
docker exec -it base_4 bash -c 'sudo -u postgres psql test_1 -c "SELECT * FROM foo;"  | grep -c -w "Chip"'
docker exec -it base_4 bash -c 'sudo -u postgres psql test_1 -c "SELECT * FROM foo;"  | grep -c -w "Jack"'
docker exec -it base_4 bash -c 'sudo -u postgres psql test_1 -c "SELECT COUNT(*) FROM foo;" | grep -c -w "3"'
echo ""
echo "-- Clear"
docker rm -f -v $(sudo docker ps -aq); sleep 5

echo ""
echo "--- Recovery master from backup-slave"
docker run --name base_1 -d -e 'PG_MODE=master' -e 'PG_IMPORT=default'  -v $(pwd)/vol94/backup_slave:/tmp/backup psg-9.4; sleep 10
docker run --name base_2 -d --link base_1:base_1 -e 'PG_MODE=slave' -e 'PG_TRUST_LOCALNET=true' -e 'REPLICATION_HOST=base_1' psg-9.4; sleep 10
docker exec -it base_1 sudo -u postgres psql test_1 -c "INSERT INTO foo (name) VALUES ('Tom');"; sleep 5
docker exec -it base_2 bash -c 'sudo -u postgres psql test_1 -c "SELECT * FROM foo;"  | grep -c -w "Tom"'
docker exec -it base_2 bash -c 'sudo -u postgres psql test_1 -c "SELECT * FROM foo;"  | grep -c -w "Chip"'
docker exec -it base_2 bash -c 'sudo -u postgres psql test_1 -c "SELECT COUNT(*) FROM foo;" | grep -c -w "3"'

echo ""
echo "-- Clear"
docker rm -f -v $(sudo docker ps -aq); sleep 5
docker rmi psg-9.4
rm -rf vol94*



echo ""
echo ""
echo "-- Building PostgreSQL 9.3 image"
docker build -t psg-9.3 9.3/

echo ""
echo "-- Testing PostgreSQL 9.3 is running"
docker run --name base_1 -d psg-9.3; sleep 5
docker run --name base_2 -d --link base_1:base_1 psg-9.3; sleep 10
docker exec -it base_2 bash -c 'pg_isready -h ${BASE_1_PORT_5432_TCP_ADDR} -p 5432 | grep -c "accepting"'
echo ""
echo "-- Clear"
docker rm -f -v $(sudo docker ps -aq); sleep 5

echo ""
echo "-- Testing backup/checking on PostgreSQL 9.3"
docker run --name base_1 -d -e 'PG_MODE=master' -e 'DB_NAME=db_1,test_1' psg-9.3; sleep 10
echo "--- Backup"
docker run -it --rm --link base_1:base_1 -e 'PG_MODE=backup' -e 'REPLICATION_HOST=base_1' -e 'REPLICATION_PORT=5432' -v $(pwd)/vol93/backup:/tmp/backup psg-9.3 | grep -wc 'backup completed'; sleep 10
echo "--- Check"
docker run -it --rm -e 'PG_CHECK=default' -e 'DB_NAME=db_1' -v $(pwd)/vol93/backup:/tmp/backup psg-9.3 | tail -n 1 | grep -c 'Success'; sleep 5
docker run -it --rm -e 'PG_CHECK=/tmp/backup/backup.last.tar.bz2' -e 'DB_NAME=test_1' -v $(pwd)/vol93/backup:/tmp/backup psg-9.3 | tail -n 1 | grep -c 'Success'; sleep 5
docker run -it --rm -e 'PG_CHECK=default' -e 'DB_NAME=db' -v $(pwd)/vol93/backup:/tmp/backup psg-9.3 | tail -n 1 | grep -c 'Fail'; sleep 5
echo ""
echo "-- Clear"
docker rm -f -v $(sudo docker ps -aq); sleep 5
rm -rf vol93*


echo ""
echo ""
echo "-- Testing master/slave on PostgreSQL 9.3"
echo ""
echo "--- Create master"
docker run --name base_1 -d -e 'PG_MODE=master' -e 'DB_NAME=db_1,test_1' psg-9.3; sleep 10
docker exec -it base_1 sudo -u postgres psql test_1 -c "CREATE TABLE foo (id SERIAL, name VARCHAR); INSERT INTO foo (name) VALUES ('Petr');"
echo ""
echo "--- Create slave"
docker run --name base_2 -d --link base_1:base_1 -e 'PG_MODE=slave' -e 'PG_TRUST_LOCALNET=true' -e 'REPLICATION_HOST=base_1' -e 'REPLICATION_USER=replica' -e 'REPLICATION_PASS=replica' psg-9.3; sleep 10
docker run --name base_3 -d --link base_1:base_1 -e 'PG_MODE=slave' -e 'PG_TRUST_LOCALNET=true' -e 'REPLICATION_HOST=base_1' psg-9.3; sleep 10
docker exec -it base_1 sudo -u postgres psql test_1 -c "INSERT INTO foo (name) VALUES ('Tom');"; sleep 5
docker exec -it base_3 bash -c 'sudo -u postgres psql test_1 -c "SELECT * FROM foo;"  | grep -c -w "Tom"'
echo ""
echo "--- Backup"
docker run -it --rm --link base_1:base_1 -e 'PG_MODE=backup' -e 'REPLICATION_HOST=base_1' -e 'REPLICATION_PORT=5432' -v $(pwd)/vol93/backup_master:/tmp/backup psg-9.3 | grep -wc 'backup completed'; sleep 10
echo ""
echo "--- Recovery slave from backup-master"
docker run --name base_4 -d --link base_1:base_1 -e 'PG_MODE=slave' -e 'PG_TRUST_LOCALNET=true' -e 'REPLICATION_HOST=base_1' -e 'PG_IMPORT=default'  -v $(pwd)/vol93/backup_master:/tmp/backup psg-9.3; sleep 10
docker exec -it base_1 sudo -u postgres psql test_1 -c "INSERT INTO foo (name) VALUES ('Bob');"; sleep 5
docker exec -it base_3 bash -c 'sudo -u postgres psql test_1 -c "SELECT * FROM foo;"  | grep -c -w "Bob"'
docker exec -it base_4 bash -c 'sudo -u postgres psql test_1 -c "SELECT COUNT(*) FROM foo;" | grep -c -w "3"'
echo ""
echo "-- Clear"
docker rm -f -v $(sudo docker ps -aq); sleep 5

echo ""
echo "--- Recovery master from backup-master"
docker run --name base_1 -d -e 'PG_MODE=master' -e 'PG_IMPORT=default'  -v $(pwd)/vol93/backup_master:/tmp/backup psg-9.3; sleep 10
docker run --name base_2 -d --link base_1:base_1 -e 'PG_MODE=slave' -e 'PG_TRUST_LOCALNET=true' -e 'REPLICATION_HOST=base_1' psg-9.3; sleep 10
docker exec -it base_1 sudo -u postgres psql test_1 -c "INSERT INTO foo (name) VALUES ('Jack');"; sleep 5
docker exec -it base_2 bash -c 'sudo -u postgres psql test_1 -c "SELECT * FROM foo;"  | grep -c -w "Jack"'
docker exec -it base_2 bash -c 'sudo -u postgres psql test_1 -c "SELECT COUNT(*) FROM foo;" | grep -c -w "3"'

echo ""
echo "-- Clear"
docker rm -f -v $(sudo docker ps -aq); sleep 5
rm -rf vol93*

echo ""
echo "--- Create master"
docker run --name base_1 -d -e 'PG_MODE=master' -e 'DB_NAME=db_1,test_1' psg-9.3; sleep 10
docker exec -it base_1 sudo -u postgres psql test_1 -c "CREATE TABLE foo (id SERIAL, name VARCHAR); INSERT INTO foo (name) VALUES ('Petr');"
docker run --name base_2 -d --link base_1:base_1 -e 'PG_MODE=slave' -e 'PG_TRUST_LOCALNET=true' -e 'REPLICATION_HOST=base_1' psg-9.3; sleep 10
docker exec -it base_1 sudo -u postgres psql test_1 -c "INSERT INTO foo (name) VALUES ('Chip');"; sleep 5
echo ""
echo "--- Create backup-slave"
docker run --name base_3 -d --link base_1:base_1 -e 'PG_MODE=slave_wal' -e 'PG_TRUST_LOCALNET=true' -e 'REPLICATION_HOST=base_1' psg-9.3; sleep 10

echo ""
echo "--- Backup"
docker run -it --rm --link base_3:base_3 -e 'PG_MODE=backup' -e 'REPLICATION_HOST=base_3' -e 'REPLICATION_PORT=5432' -v $(pwd)/vol93/backup_slave:/tmp/backup psg-9.3 | grep -wc 'backup completed'; sleep 10
echo ""
echo "--- Recovery slave from backup-slave"
docker run --name base_4 -d --link base_1:base_1 -e 'PG_MODE=slave' -e 'PG_TRUST_LOCALNET=true' -e 'REPLICATION_HOST=base_1' -e 'PG_IMPORT=default'  -v $(pwd)/vol93/backup_slave:/tmp/backup psg-9.3; sleep 10
docker exec -it base_1 sudo -u postgres psql test_1 -c "INSERT INTO foo (name) VALUES ('Jack');"; sleep 5
docker exec -it base_4 bash -c 'sudo -u postgres psql test_1 -c "SELECT * FROM foo;"  | grep -c -w "Chip"'
docker exec -it base_4 bash -c 'sudo -u postgres psql test_1 -c "SELECT * FROM foo;"  | grep -c -w "Jack"'
docker exec -it base_4 bash -c 'sudo -u postgres psql test_1 -c "SELECT COUNT(*) FROM foo;" | grep -c -w "3"'
echo ""
echo "-- Clear"
docker rm -f -v $(sudo docker ps -aq); sleep 5

echo ""
echo "--- Recovery master from backup-slave"
docker run --name base_1 -d -e 'PG_MODE=master' -e 'PG_IMPORT=default'  -v $(pwd)/vol93/backup_slave:/tmp/backup psg-9.3; sleep 10
docker run --name base_2 -d --link base_1:base_1 -e 'PG_MODE=slave' -e 'PG_TRUST_LOCALNET=true' -e 'REPLICATION_HOST=base_1' psg-9.3; sleep 10
docker exec -it base_1 sudo -u postgres psql test_1 -c "INSERT INTO foo (name) VALUES ('Tom');"; sleep 5
docker exec -it base_2 bash -c 'sudo -u postgres psql test_1 -c "SELECT * FROM foo;"  | grep -c -w "Tom"'
docker exec -it base_2 bash -c 'sudo -u postgres psql test_1 -c "SELECT * FROM foo;"  | grep -c -w "Chip"'
docker exec -it base_2 bash -c 'sudo -u postgres psql test_1 -c "SELECT COUNT(*) FROM foo;" | grep -c -w "3"'

echo ""
echo "-- Clear"
docker rm -f -v $(sudo docker ps -aq); sleep 5
docker rmi psg-9.3
rm -rf vol93*

echo ""
echo "-- Done"