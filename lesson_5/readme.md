# PG Advanced - Домашняя работа 5 - бакапы Postgres

## Создание виртуалки

```
yc compute instance create \
  --name otus-db-pg-lesson5 \
  --zone ru-central1-b \
  --hostname otus-db-pg-vm-5 \
  --network-interface subnet-name=default-ru-central1-b,nat-ip-version=ipv4 \
  --create-boot-disk image-folder-id=standard-images,image-family=ubuntu-2204-lts,type=network-hdd,size=20 \
  --memory 4 \
  --core-fraction 50 \
  --preemptible \
  --metadata-from-file user-data=user-data.yaml
```
[user-data.yaml](user-data.yaml)

## Установка СУБД, pg_probackup и наполнение

### Установка PG

- установка 15-й версии (т.к. pg_probackup для 16-й ещё не вышел)
```
anton@aminkin:/mnt/dev/sdb1/Education/PgAdvanced/otus-pg-adv/lesson_5$ yc compute instance list
+----------------------+--------------------+---------------+---------+----------------+-------------+
|          ID          |        NAME        |    ZONE ID    | STATUS  |  EXTERNAL IP   | INTERNAL IP |
+----------------------+--------------------+---------------+---------+----------------+-------------+
| epdg14jkf1n54p4p77b0 | otus-db-pg-lesson5 | ru-central1-b | RUNNING | 158.160.79.153 | 10.129.0.21 |
+----------------------+--------------------+---------------+---------+----------------+-------------+

anton@aminkin:/mnt/dev/sdb1/Education/PgAdvanced/otus-pg-adv/lesson_5$ ssh anton@158.160.79.153

anton@otus-db-pg-vm-5:~$ cat > postgresql-15.sh
...
anton@otus-db-pg-vm-5:~$ chmod +x postgresql-15.sh
anton@otus-db-pg-vm-5:~$ ./postgresql-15.sh
...
```
[postgresql-15.sh](postgresql-15.sh)

- включим чексуммы
```
anton@otus-db-pg-vm-5:~$ sudo su - postgres
postgres@otus-db-pg-vm-5:~$ pg_ctlcluster 15 main stop
postgres@otus-db-pg-vm-5:~$ /usr/lib/postgresql/15/bin/pg_checksums -D /var/lib/postgresql/15/main --enable
postgres@otus-db-pg-vm-5:~$ pg_ctlcluster 15 main start
```

### Установка pg_probackup

```
anton@otus-db-pg-vm-5:~$ sudo sh -c 'echo "deb [arch=amd64] https://repo.postgrespro.ru/pg_probackup/deb/ $(lsb_release -cs) main-$(lsb_release -cs)" > /etc/apt/sources.list.d/pg_probackup.list'
anton@otus-db-pg-vm-5:~$ sudo wget -O - https://repo.postgrespro.ru/pg_probackup/keys/GPG-KEY-PG_PROBACKUP | sudo apt-key add - && sudo apt-get update
anton@otus-db-pg-vm-5:~$ sudo apt-get install pg-probackup-15
anton@otus-db-pg-vm-5:~$ sudo apt-get install pg-probackup-15-dbg
```

### Наполнение через pgbench

```
anton@otus-db-pg-vm-5:~$ sudo su - postgres
postgres@otus-db-pg-vm-5:~$ pgbench -i -s 50
dropping old tables...
NOTICE:  table "pgbench_accounts" does not exist, skipping
NOTICE:  table "pgbench_branches" does not exist, skipping
NOTICE:  table "pgbench_history" does not exist, skipping
NOTICE:  table "pgbench_tellers" does not exist, skipping
creating tables...
generating data (client-side)...
5000000 of 5000000 tuples (100%) done (elapsed 36.16 s, remaining 0.00 s)
vacuuming...
creating primary keys...
done in 48.31 s (drop tables 0.00 s, create tables 0.02 s, client-side generate 36.47 s, vacuum 0.32 s, primary keys 11.51 s).
```

## Снятие бакапа

### Настройка pg_probackup

- создаём каталог для бакапов (+ добавим его в .bash_profile)
```
anton@otus-db-pg-vm-5:~$ sudo mkdir -p /backup/pg
anton@otus-db-pg-vm-5:~$ sudo chown postgres:postgres /backup/pg
anton@otus-db-pg-vm-5:~$ sudo su - postgres
postgres@otus-db-pg-vm-5:~$ touch .bash_profile
postgres@otus-db-pg-vm-5:~$ echo 'export BACKUP_PATH=/backup/pg' >> .bash_profile 
postgres@otus-db-pg-vm-5:~$ . ~/.bash_profile
```

- инициализация
`postgres@otus-db-pg-vm-5:~$ pg_probackup-15 init -B ${BACKUP_PATH}`
INFO: Backup catalog '/backup/pg' successfully initialized

- добавляем инстанс (имя любое, главное путь к PGDATA)
`postgres@otus-db-pg-vm-5:~$ pg_probackup-15 add-instance -D /var/lib/postgresql/15/main --instance pg15`
INFO: Instance 'pg15' successfully initialized

- добавляем в кластер роль backup с правами

```
postgres@otus-db-pg-vm-5:~$ psql
...
postgres=# BEGIN;
CREATE ROLE backup WITH LOGIN;
GRANT USAGE ON SCHEMA pg_catalog TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.current_setting(text) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.set_config(text, text, boolean) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_is_in_recovery() TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_backup_start(text, boolean) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_backup_stop(boolean) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_create_restore_point(text) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_switch_wal() TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_last_wal_replay_lsn() TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.txid_current() TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.txid_current_snapshot() TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.txid_snapshot_xmax(txid_snapshot) TO backup;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_control_checkpoint() TO backup;
COMMIT;
...
postgres=# ALTER ROLE backup WITH REPLICATION;
postgres=# alter role backup with password 'backup';
...
```

- пароль положим в pgpass (причем обязательно для бд replication!)

```
postgres@otus-db-pg-vm-5:~$ echo "localhost:5432:postgres:backup:backup" >> ~/.pgpass
postgres@otus-db-pg-vm-5:~$ echo "localhost:5432:replication:backup:backup" >> ~/.pgpass
postgres@otus-db-pg-vm-5:~$ chmod 600 .pgpass
```

- добавим пользователя backup в bg_hba (тоже бд replication! +ipv6)
```
host    replication     backup          0.0.0.0/0               scram-sha-256
host    replication     backup          ::0/0                   scram-sha-256
host    all             backup          0.0.0.0/0               scram-sha-256
host    all             backup          ::0/0                   scram-sha-256
```

### Запуск нагрузки

- 5 клиентов, 4 потока, 15 мин, прогресс раз в 10 сек

```
postgres@otus-db-pg-vm-5:~$ pgbench -c 5 -j 4 -T 900 -P 10
pgbench (15.4 (Ubuntu 15.4-2.pgdg22.04+1))
starting vacuum...end.
progress: 10.0 s, 715.4 tps, lat 6.978 ms stddev 17.057, 0 failed
progress: 20.0 s, 572.1 tps, lat 8.715 ms stddev 24.215, 0 failed
...
```

- просмотр работы нагрузки через pg_top
```
    PID USERNAME    SIZE   RES STATE   XTIME  QTIME  %CPU LOCKS COMMAND
  10042 postgres    216M  136M active   0:00   0:00   6.9     9 postgres: 15/main: postgres postgres [local] COMMIT
  10046 postgres    216M  136M active   0:00   0:00   5.9     9 postgres: 15/main: postgres postgres [local] COMMIT
  10044 postgres    216M  136M active   0:00   0:00   7.9     9 postgres: 15/main: postgres postgres [local] COMMIT
  10045 postgres    216M  136M active   0:00   0:00   6.9     9 postgres: 15/main: postgres postgres [local] COMMIT
  10043 postgres    216M  135M active   0:00   0:00   7.9     9 postgres: 15/main: postgres postgres [local] COMMIT
  10055 postgres    217M   20M active   0:00   0:00   0.0     8 postgres: 15/main: postgres postgres [local] idle
```

### Получение бакапа

- запуск полного бакапа на инстансе pg15, со сжатием, в 4 потока из под пользователя backup
```
postgres@otus-db-pg-vm-5:~$ pg_probackup-15 backup \
    --instance pg15 \
    -h localhost \
    -U backup \
    -b FULL \
    --compress-algorithm=zlib \
    --compress-level=5 \
    -j 4 \
    --progress \
    --stream \
    --temp-slot \
    -w

INFO: Backup start, pg_probackup version: 2.5.12, instance: pg15, backup ID: S18KY7, backup mode: FULL, wal mode: STREAM, remote: false, compress-algorithm: zlib, compress-level: 5
INFO: This PostgreSQL instance was initialized with data block checksums. Data block corruption will be detected
INFO: Database backup start
INFO: wait for pg_backup_start()
INFO: Wait for WAL segment /backup/pg/backups/pg15/S18KY7/database/pg_wal/00000001000000010000001B to be streamed
INFO: PGDATA size: 795MB
INFO: Current Start LSN: 1/1B187D20, TLI: 1
INFO: Start transferring data files
INFO: Progress: (1/1000). Process file "base/5/1417"
INFO: Progress: (1/1000). Process file "base/5/1417"
INFO: Progress: (2/1000). Process file "base/4/4157"
...
INFO: Progress: (1001/1008). Validate file "backup_label"
INFO: Progress: (1002/1008). Validate file "pg_wal/00000001000000010000001B"
INFO: Progress: (1003/1008). Validate file "pg_wal/00000001000000010000001C"
INFO: Progress: (1004/1008). Validate file "pg_wal/00000001000000010000001D"
INFO: Progress: (1005/1008). Validate file "pg_wal/00000001000000010000001E"
INFO: Progress: (1006/1008). Validate file "pg_wal/00000001000000010000001F"
INFO: Progress: (1007/1008). Validate file "pg_wal/000000010000000100000020"
INFO: Progress: (1008/1008). Validate file "database_map"
INFO: Backup S18KY7 data files are valid
INFO: Backup S18KY7 resident size: 188MB
INFO: Backup S18KY7 completed
```

- проверим список бакапов
```
postgres@otus-db-pg-vm-5:~$ pg_probackup-15 show

BACKUP INSTANCE 'pg15'
==================================================================================================================================
 Instance  Version  ID      Recovery Time           Mode  WAL Mode  TLI  Time  Data   WAL  Zratio  Start LSN   Stop LSN    Status 
==================================================================================================================================
 pg15      15       S18KY7  2023-09-19 14:16:14+00  FULL  STREAM    1/0   46s  92MB  96MB    8.65  1/1B187D20  1/1F05B0E8  OK     
```

- пока снимали бакап нагрузка накидала данных, снимем дельту
```
pg_probackup-15 backup \
    --instance pg15 \
    -h localhost \
    -U backup \
    -b DELTA \
    --compress-algorithm=zlib \
    --compress-level=5 \
    -j 4 \
    --progress \
    --stream \
    --temp-slot \
    -w
INFO: Backup start, pg_probackup version: 2.5.12, instance: pg15, backup ID: S18L2M, backup mode: DELTA, wal mode: STREAM, remote: false, compress-algorithm: zlib, compress-level: 5
INFO: This PostgreSQL instance was initialized with data block checksums. Data block corruption will be detected
INFO: Database backup start
INFO: wait for pg_backup_start()
INFO: Parent backup: S18KY7
INFO: Wait for WAL segment /backup/pg/backups/pg15/S18L2M/database/pg_wal/000000010000000100000033 to be streamed
INFO: PGDATA size: 798MB
INFO: Current Start LSN: 1/33004568, TLI: 1
INFO: Parent Start LSN: 1/1B187D20, TLI: 1
INFO: Start transferring data files
INFO: Progress: (2/1000). Process file "base/4/4157"
INFO: Progress: (2/1000). Process file "base/4/4157"
...
INFO: Progress: (1001/1006). Validate file "backup_label"
INFO: Progress: (1002/1006). Validate file "pg_wal/000000010000000100000033"
INFO: Progress: (1003/1006). Validate file "pg_wal/000000010000000100000034"
INFO: Progress: (1004/1006). Validate file "pg_wal/000000010000000100000035"
INFO: Progress: (1005/1006). Validate file "pg_wal/000000010000000100000036"
INFO: Progress: (1006/1006). Validate file "database_map"
INFO: Backup S18L2M data files are valid
INFO: Backup S18L2M resident size: 95MB
INFO: Backup S18L2M completed
```

- обновим список бакапов
```
postgres@otus-db-pg-vm-5:~$ pg_probackup-15 show

BACKUP INSTANCE 'pg15'
===================================================================================================================================
 Instance  Version  ID      Recovery Time           Mode   WAL Mode  TLI  Time  Data   WAL  Zratio  Start LSN   Stop LSN    Status 
===================================================================================================================================
 pg15      15       S18L2M  2023-09-19 14:18:38+00  DELTA  STREAM    1/1   19s  31MB  64MB   11.21  1/33004568  1/35D40250  OK     
 pg15      15       S18KY7  2023-09-19 14:16:14+00  FULL   STREAM    1/0   46s  92MB  96MB    8.65  1/1B187D20  1/1F05B0E8  OK     
```

## Восстановление в новый кластер

### Созадем кластер и включаем чексуммы
```
postgres@otus-db-pg-vm-5:~$ pg_createcluster 15 new
Creating new PostgreSQL cluster 15/new ...
/usr/lib/postgresql/15/bin/initdb -D /var/lib/postgresql/15/new --auth-local peer --auth-host scram-sha-256 --no-instructions
The files belonging to this database system will be owned by user "postgres".
This user must also own the server process.

The database cluster will be initialized with locale "en_US.UTF-8".
The default database encoding has accordingly been set to "UTF8".
The default text search configuration will be set to "english".

Data page checksums are disabled.

fixing permissions on existing directory /var/lib/postgresql/15/new ... ok
creating subdirectories ... ok
selecting dynamic shared memory implementation ... posix
selecting default max_connections ... 100
selecting default shared_buffers ... 128MB
selecting default time zone ... Etc/UTC
creating configuration files ... ok
running bootstrap script ... ok
performing post-bootstrap initialization ... ok
syncing data to disk ... ok
Warning: systemd does not know about the new cluster yet. Operations like "service postgresql start" will not handle it. To fix, run:
  sudo systemctl daemon-reload
Ver Cluster Port Status Owner    Data directory             Log file
15  new     5433 down   postgres /var/lib/postgresql/15/new /var/log/postgresql/postgresql-15-new.log

postgres@otus-db-pg-vm-5:~$ /usr/lib/postgresql/15/bin/pg_checksums -D /var/lib/postgresql/15/new --enable
Checksum operation completed
Files scanned:   946
Blocks scanned:  2798
Files written:  778
Blocks written: 2798
pg_checksums: syncing data directory
pg_checksums: updating control file
Checksums enabled in cluster
```

### Восстанавливаем бакап в новый кластер
- т.к. конкретный бакап не указывали, берется последняя актуальная копия + инкременты (S18KY7 + S18L2M)
```
postgres@otus-db-pg-vm-5:~$ rm -r /var/lib/postgresql/15/new
postgres@otus-db-pg-vm-5:~$ pg_probackup-15 restore \
    --instance pg15 \
    -D /var/lib/postgresql/15/new \
    -j 4

INFO: Validating parents for backup S18L2M
INFO: Validating backup S18KY7
INFO: Backup S18KY7 data files are valid
INFO: Validating backup S18L2M
INFO: Backup S18L2M data files are valid
INFO: Backup S18L2M WAL segments are valid
INFO: Backup S18L2M is valid.
INFO: Restoring the database from backup at 2023-09-19 14:18:22+00
INFO: Start restoring backup files. PGDATA size: 862MB
INFO: Backup files are restored. Transfered bytes: 862MB, time elapsed: 25s
INFO: Restore incremental ratio (less is better): 100% (862MB/862MB)
INFO: Syncing restored files to disk
INFO: Restored backup files are synced, time elapsed: 15s
INFO: Restore of backup S18L2M completed.
```

### Стартуем новый кластер и проверяем данные
```
postgres@otus-db-pg-vm-5:~$ pg_lsclusters
Ver Cluster Port Status Owner    Data directory              Log file
15  main    5432 online postgres /var/lib/postgresql/15/main /var/log/postgresql/postgresql-15-main.log
15  new     5433 down   postgres /var/lib/postgresql/15/new  /var/log/postgresql/postgresql-15-new.log

postgres@otus-db-pg-vm-5:~$ pg_ctlcluster 15 new start
Warning: the cluster will not be running as a systemd service. Consider using systemctl:
  sudo systemctl start postgresql@15-new

postgres@otus-db-pg-vm-5:~$ psql -p 5433

postgres=# \dt+
                                         List of relations
 Schema |       Name       | Type  |  Owner   | Persistence | Access method |  Size  | Description 
--------+------------------+-------+----------+-------------+---------------+--------+-------------
 public | pgbench_accounts | table | postgres | permanent   | heap          | 651 MB | 
 public | pgbench_branches | table | postgres | permanent   | heap          | 232 kB | 
 public | pgbench_history  | table | postgres | permanent   | heap          | 17 MB  | 
 public | pgbench_tellers  | table | postgres | permanent   | heap          | 272 kB | 
(4 rows)

postgres=# select * from pgbench_history order by mtime desc limit 1 \gx
-[ RECORD 1 ]----------------------
tid    | 290
bid    | 25
aid    | 4661522
delta  | 618
mtime  | 2023-09-19 14:18:39.807854
filler | 
```

- видно, что время изменения в таблице pgbench_history - 14:18:38 соответствует времени снятия последнего инкрементального бакапа