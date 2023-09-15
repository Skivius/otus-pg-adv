# PG Advanced - Домашняя работа 4 - тюнинг Postgres

## Создание виртуалки

```
yc compute instance create \
  --name otus-db-pg-lesson4 \
  --zone ru-central1-b \
  --hostname otus-db-pg-vm-4 \
  --network-interface subnet-name=default-ru-central1-b,nat-ip-version=ipv4 \
  --create-boot-disk image-folder-id=standard-images,image-family=ubuntu-2204-lts,type=network-hdd,size=20 \
  --memory 4 \
  --core-fraction 50 \
  --preemptible \
  --metadata-from-file user-data=user-data.yaml
```

## Установка Postgres

```
anton@aminkin:/mnt/dev/sdb1/Education/PgAdvanced/otus-pg-adv/lesson_4$ yc compute instance list
+----------------------+--------------------+---------------+---------+--------------+-------------+
|          ID          |        NAME        |    ZONE ID    | STATUS  | EXTERNAL IP  | INTERNAL IP |
+----------------------+--------------------+---------------+---------+--------------+-------------+
| epdvo100ovdgqp1rhskb | otus-db-pg-lesson4 | ru-central1-b | RUNNING | 158.160.80.2 | 10.129.0.20 |
+----------------------+--------------------+---------------+---------+--------------+-------------+
anton@aminkin:/mnt/dev/sdb1/Education/PgAdvanced/otus-pg-adv/lesson_4$ ssh anton@158.160.80.2

anton@otus-db-pg-vm-4:~$ cat > postgresql.sh
...
anton@otus-db-pg-vm-4:~$ chmod +x postgresql.sh
anton@otus-db-pg-vm-4:~$ ./postgresql.sh
...
```

## Тестирование pgbench

- инициализация
```
postgres@otus-db-pg-vm-4:~$ pgbench -i -s 10
dropping old tables...
NOTICE:  table "pgbench_accounts" does not exist, skipping
NOTICE:  table "pgbench_branches" does not exist, skipping
NOTICE:  table "pgbench_history" does not exist, skipping
NOTICE:  table "pgbench_tellers" does not exist, skipping
creating tables...
generating data (client-side)...
1000000 of 1000000 tuples (100%) done (elapsed 5.26 s, remaining 0.00 s)
vacuuming...
creating primary keys...
done in 7.61 s (drop tables 0.00 s, create tables 0.01 s, client-side generate 5.67 s, vacuum 0.16 s, primary keys 1.77 s).
```
- начальный тест
```
postgres@otus-db-pg-vm-4:~$ pgbench -P 1 -T 10
pgbench (16.0 (Ubuntu 16.0-1.pgdg22.04+1))
starting vacuum...end.
progress: 1.0 s, 253.0 tps, lat 3.930 ms stddev 3.000, 0 failed
progress: 2.0 s, 253.0 tps, lat 3.941 ms stddev 2.952, 0 failed
progress: 3.0 s, 154.0 tps, lat 6.509 ms stddev 3.279, 0 failed
progress: 4.0 s, 92.0 tps, lat 10.694 ms stddev 5.003, 0 failed
progress: 5.0 s, 208.0 tps, lat 4.892 ms stddev 3.779, 0 failed
progress: 6.0 s, 192.0 tps, lat 5.190 ms stddev 23.410, 0 failed
progress: 7.0 s, 367.0 tps, lat 2.734 ms stddev 2.553, 0 failed
progress: 8.0 s, 295.0 tps, lat 3.382 ms stddev 2.468, 0 failed
progress: 9.0 s, 341.0 tps, lat 2.933 ms stddev 2.549, 0 failed
progress: 10.0 s, 201.0 tps, lat 4.943 ms stddev 3.753, 0 failed
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 10
query mode: simple
number of clients: 1
number of threads: 1
maximum number of tries: 1
duration: 10 s
number of transactions actually processed: 2357
number of failed transactions: 0 (0.000%)
latency average = 4.240 ms
latency stddev = 7.499 ms
initial connection time = 3.992 ms
tps = 235.778349 (without initial connection time)
```

## Тюнинг

https://pgconfigurator.cybertec.at/

параметры не требующие рестарта:

- ALTER SYSTEM SET synchronous_commit TO off;
- ALTER SYSTEM SET work_mem TO '32 MB';
- ALTER SYSTEM SET maintenance_work_mem TO '320 MB';
- ALTER SYSTEM SET track_io_timing TO on;
- ALTER SYSTEM SET track_functions TO 'pl';
- ALTER SYSTEM SET checkpoint_timeout TO '15 min';
- ALTER SYSTEM SET maintenance_io_concurrency TO 1;

`SELECT pg_reload_conf();`

параметры требующие рестарта:

- ALTER SYSTEM SET shared_buffers TO '1024 MB';
- ALTER SYSTEM SET huge_pages TO off;
- ALTER SYSTEM SET shared_preload_libraries TO 'pg_stat_statements';
- ALTER SYSTEM SET max_worker_processes TO 2;
- ALTER SYSTEM SET max_parallel_workers_per_gather TO 1;
- ALTER SYSTEM SET max_parallel_maintenance_workers TO 1;
- ALTER SYSTEM SET max_parallel_workers TO 2;

`sudo systemctl restart postgresql.service`

## Тестирование pgbench после тюнинга

```
postgres@otus-db-pg-vm-4:~$ pgbench -P 1 -T 10
pgbench (16.0 (Ubuntu 16.0-1.pgdg22.04+1))
starting vacuum...end.
progress: 1.0 s, 1885.0 tps, lat 0.528 ms stddev 0.187, 0 failed
progress: 2.0 s, 1952.0 tps, lat 0.512 ms stddev 0.166, 0 failed
progress: 3.0 s, 2056.9 tps, lat 0.486 ms stddev 0.194, 0 failed
progress: 4.0 s, 1891.0 tps, lat 0.529 ms stddev 0.096, 0 failed
progress: 5.0 s, 1835.1 tps, lat 0.545 ms stddev 0.129, 0 failed
progress: 6.0 s, 2222.0 tps, lat 0.450 ms stddev 0.070, 0 failed
progress: 7.0 s, 2233.1 tps, lat 0.448 ms stddev 0.095, 0 failed
progress: 8.0 s, 1784.0 tps, lat 0.560 ms stddev 0.107, 0 failed
progress: 9.0 s, 1911.9 tps, lat 0.523 ms stddev 0.067, 0 failed
progress: 10.0 s, 2001.0 tps, lat 0.500 ms stddev 0.094, 0 failed
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 10
query mode: simple
number of clients: 1
number of threads: 1
maximum number of tries: 1
duration: 10 s
number of transactions actually processed: 19772
number of failed transactions: 0 (0.000%)
latency average = 0.505 ms
latency stddev = 0.133 ms
initial connection time = 4.361 ms
tps = 1978.001882 (without initial connection time)
```
- количество транзакций в секунду увеличилось с 235 до 1978 (прирост больше чем х8)

## Небезопасный тюнинг

https://postgrespro.ru/docs/postgresql/15/runtime-config-wal

согласно документации отключение этих параметров: `может привести к неисправимому повреждению или незаметной порче данных после сбоя системы`

- ALTER SYSTEM SET fsync TO off;
- ALTER SYSTEM SET full_page_writes TO off;

`SELECT pg_reload_conf();`

```
postgres@otus-db-pg-vm-4:~$ pgbench -P 1 -T 10
pgbench (16.0 (Ubuntu 16.0-1.pgdg22.04+1))
starting vacuum...end.
progress: 1.0 s, 2195.0 tps, lat 0.454 ms stddev 0.055, 0 failed
progress: 2.0 s, 2273.0 tps, lat 0.440 ms stddev 0.035, 0 failed
progress: 3.0 s, 2306.9 tps, lat 0.433 ms stddev 0.033, 0 failed
progress: 4.0 s, 2304.9 tps, lat 0.434 ms stddev 0.040, 0 failed
progress: 5.0 s, 2248.1 tps, lat 0.445 ms stddev 0.050, 0 failed
progress: 6.0 s, 1972.0 tps, lat 0.507 ms stddev 0.089, 0 failed
progress: 7.0 s, 1926.0 tps, lat 0.519 ms stddev 0.058, 0 failed
progress: 8.0 s, 1994.0 tps, lat 0.501 ms stddev 0.178, 0 failed
progress: 9.0 s, 1993.0 tps, lat 0.502 ms stddev 0.050, 0 failed
progress: 10.0 s, 1977.1 tps, lat 0.505 ms stddev 0.042, 0 failed
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 10
query mode: simple
number of clients: 1
number of threads: 1
maximum number of tries: 1
duration: 10 s
number of transactions actually processed: 21191
number of failed transactions: 0 (0.000%)
latency average = 0.472 ms
latency stddev = 0.081 ms
initial connection time = 3.440 ms
tps = 2119.697331 (without initial connection time)
```

- количество транзакций в секунду увеличилось до 2119 (приросто почти х10 с первоначальным вариантом)