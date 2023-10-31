# PG Advanced - Домашняя работа 12 - HA Postgres - pg_auto_failover

Создадим high availability кластер постгреса в яндекс-облаке с помощью решения pg_auto_failover от Citus Data.
Для кластера используем три виртуальные машины - одну для мониторинга и две для данных (мастер - реплика), как здесь: https://habr.com/ru/articles/664858/
Постгрес и автофейловер будем поднимать версии 15 в докере.

## Создание виртуалок

- Для мониторинга достаточно 2CPU, 2Gb RAM, 20Gb HDD, для данных - 4CPU, 8Gb RAM, 40Gb HDD
```
yc compute instance create \
  --name otus-db-pg-lesson12-0 \
  --zone ru-central1-b \
  --hostname otus-12-pgaf-mon \
  --network-interface subnet-name=default-ru-central1-b,nat-ip-version=ipv4 \
  --create-boot-disk image-folder-id=standard-images,image-family=ubuntu-2204-lts,type=network-hdd,size=20 \
  --memory 2 \
  --cores 2 \
  --core-fraction 50 \
  --preemptible \
  --metadata-from-file user-data=user-data.yaml

yc compute instance create \
  --name otus-db-pg-lesson12-1 \
  --zone ru-central1-b \
  --hostname otus-12-pgaf-data1 \
  --network-interface subnet-name=default-ru-central1-b,nat-ip-version=ipv4 \
  --create-boot-disk image-folder-id=standard-images,image-family=ubuntu-2204-lts,type=network-hdd,size=40 \
  --memory 8 \
  --cores 4 \
  --core-fraction 50 \
  --preemptible \
  --metadata-from-file user-data=user-data.yaml

yc compute instance create \
  --name otus-db-pg-lesson12-2 \
  --zone ru-central1-b \
  --hostname otus-12-pgaf-data2 \
  --network-interface subnet-name=default-ru-central1-b,nat-ip-version=ipv4 \
  --create-boot-disk image-folder-id=standard-images,image-family=ubuntu-2204-lts,type=network-hdd,size=40 \
  --memory 8 \
  --cores 4 \
  --core-fraction 50 \
  --preemptible \
  --metadata-from-file user-data=user-data.yaml
```

- ставим докер на виртуалки (пример для мониторинга)

```
anton@otus-12-pgaf-mon:~$ sudo apt-get update
anton@otus-12-pgaf-mon:~$ sudo install -m 0755 -d /etc/apt/keyrings
anton@otus-12-pgaf-mon:~$ curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
anton@otus-12-pgaf-mon:~$ sudo chmod a+r /etc/apt/keyrings/docker.gpg
anton@otus-12-pgaf-mon:~$ echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
anton@otus-12-pgaf-mon:~$ sudo apt-get update
anton@otus-12-pgaf-mon:~$ sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

## Установка postgres и pg_auto_failover

- Построим докер-образ на основе debian 11 - [Dockerfile](Dockerfile)

- Для установки постгреса и автофейловера сделаем bash-скрипт - [postgres-install.sh](scripts/postgres-install.sh), установка PG 15 делается без создания кластера, кластер поднимается позже

- В качестве точки входа также будем использовать bash-скрипт - [entrypoint.sh](scripts/entrypoint.sh), на данный момент это просто обертка для команды, передаваемой при старте контейнера, но при желании в нём можно реализовать свою логику старта (TODO)

- Соберем образ:

```
anton@otus-12-pgaf-mon:~/$ mkdir autofailover
... кладем сюда докерфайл
anton@otus-12-pgaf-mon:~/$ cd ~/autofailover
anton@otus-12-pgaf-mon:~/autofailover$ mkdir scripts
... кладем сюда скрипты, даем права на выполнение
anton@otus-12-pgaf-mon:~/autofailover$ chmod +x scripts/*
anton@otus-12-pgaf-mon:~/autofailover$ sudo docker image build --progress=plain --no-cache -t pgaf:15 .
...
#8 68.81 Building PostgreSQL dictionaries from installed myspell/hunspell packages...
#8 68.81 Removing obsolete dictionary files:
#8 68.91 Generating locales (this might take a while)...
#8 68.92   en_US.UTF-8... done
#8 70.95 Generation complete.
#8 DONE 72.2s

#9 exporting to image
#9 exporting layers
#9 exporting layers 67.8s done
#9 writing image sha256:f416e91791e54062e4d9cf5d24ce8590a18cc5e7a33b498a5d51bcc37f50fcf7 done
#9 naming to docker.io/library/pgaf:15 0.0s done
#9 DONE 67.8s
```

- Перекопируем готовый образ pgaf:15 на дата-ноды через локальный комп и импортируем его в докер (ниже пример копирования на otus-12-pgaf-data1, на вторую ноду аналогично)

```
anton@otus-12-pgaf-mon:~/$ sudo docker save -o /data/pgaf.tar pgaf
anton@otus-12-pgaf-mon:~/$ sudo chmod 775 /data/pgaf.tar

anton@aminkin:~$ scp anton@X.X.X.X:/data/pgaf.tar pgaf.tar

anton@otus-12-pgaf-data1:~$ sudo chmod 777 /data

anton@aminkin:~$ scp pgaf.tar anton@X.X.X.X:/data/pgaf.tar

anton@otus-12-pgaf-data1:~$ sudo chmod 755 /data

anton@otus-12-pgaf-data1:~$ sudo docker load -i /data/pgaf.tar
ca791778e800: Loading layer [==================================================>]   2.56kB/2.56kB
9aaf05c215cf: Loading layer [==================================================>]  4.096kB/4.096kB
174623c6c17b: Loading layer [==================================================>]  394.4MB/394.4MB
Loaded image: pgaf:15

anton@otus-12-pgaf-data1:~$ sudo rm /data/pgaf.tar
```

- Перед запуском создадим на каждой виртуалке каталог для постгреса

`sudo mkdir -p /data/postgres`

- Теперь на каждой виртуалке запустим контейнер на основе нашего образа, указав в качестве точки входа команду sleep infinity чтобы можно было зайти в контейнер. При запуске подключим наш каталог для данных, укажем его также в переменной окружения PGDATA.

```
sudo docker run -d \
    --name postgres \
    -p 5432:5432 \
    -v /data/postgres:/var/lib/postgresql/data \
    -e POSTGRES_PASSWORD=P_ssw0rd \
    -e PGDATA=/var/lib/postgresql/data/pgdata \
    pgaf:15 \
    sleep infinity
```

- Зайдем на каждой виртуалке в запущенный контейнер postgres под пользователем root и отдадим каталог data пользователю postgres (TODO: перенести в entrypoint.sh)

```
anton@otus-12-pgaf-mon:~$ sudo docker exec -u root -it postgres bash
root@953bf4959237:/var/lib/postgresql# chown -R postgres:postgres data
root@953bf4959237:/var/lib/postgresql# exit
```

## Настройка ноды мониторинга

- Теперь зайдём в контейнер пользователем postgres, создадим монитор и запустим постгрес в бэкграунде

```
anton@otus-12-pgaf-mon:~$ sudo docker exec -it postgres bash
postgres@a4ba6290f47f:~$ pg_autoctl create monitor --auth md5 --ssl-mode require --ssl-self-signed --pgport 5432 --hostname otus-12-pgaf-mon
12:57:48 20 INFO  Using --ssl-self-signed: pg_autoctl will create self-signed certificates, allowing for encrypted network traffic
12:57:48 20 WARN  Self-signed certificates provide protection against eavesdropping; this setup does NOT protect against Man-In-The-Middle attacks nor Impersonation attacks.
12:57:48 20 WARN  See https://www.postgresql.org/docs/current/libpq-ssl.html for details
12:57:48 20 WARN  Failed to resolve hostname "otus-12-pgaf-mon" to a local IP address, automated pg_hba.conf setup might fail.
12:57:48 20 INFO  Initialising a PostgreSQL cluster at "/var/lib/postgresql/data/pgdata"
12:57:48 20 INFO  /usr/lib/postgresql/15/bin/pg_ctl initdb -s -D /var/lib/postgresql/data/pgdata --option '--auth=trust'
12:57:56 20 INFO   /usr/bin/openssl req -new -x509 -days 365 -nodes -text -out /var/lib/postgresql/data/pgdata/server.crt -keyout /var/lib/postgresql/data/pgdata/server.key -subj "/CN=otus-12-pgaf-mon"
12:57:57 20 INFO  Started pg_autoctl postgres service with pid 40
12:57:57 40 INFO   /usr/bin/pg_autoctl do service postgres --pgdata /var/lib/postgresql/data/pgdata -v
12:57:57 20 INFO  Started pg_autoctl monitor-init service with pid 41
12:57:57 45 INFO   /usr/lib/postgresql/15/bin/postgres -D /var/lib/postgresql/data/pgdata -p 5432 -h *
12:57:57 40 INFO  Postgres is now serving PGDATA "/var/lib/postgresql/data/pgdata" on port 5432 with pid 45
...
12:57:58 85 FATAL Failed to find IP address for hostname "otus-12-pgaf-mon", see above for details
12:57:58 85 WARN  Failed to grant connection to local network.
12:57:58 20 ERROR pg_autoctl service monitor-init exited with exit status 12
12:57:58 20 FATAL pg_autoctl service monitor-init has already been restarted 5 times in the last 0 seconds, stopping now
12:57:58 40 INFO  Postgres controller service received signal SIGTERM, terminating
12:57:58 40 INFO  Stopping pg_autoctl postgres service
12:57:58 40 INFO  /usr/lib/postgresql/15/bin/pg_ctl --pgdata /var/lib/postgresql/data/pgdata --wait stop --mode fast
12:57:59 20 INFO  Waiting for subprocesses to terminate.
12:57:59 20 FATAL Something went wrong in sub-process supervision, stopping now. See above for details.
12:57:59 20 INFO  Stop pg_autoctl
```

- Несмотря на ругательства что не удалось найти IP адрес монитор успешно запускается:

```
postgres@a4ba6290f47f:~$ pg_autoctl run &
[1] 92
postgres@a4ba6290f47f:~$ 13:00:19 92 INFO  Started pg_autoctl postgres service with pid 95
13:00:19 95 INFO   /usr/bin/pg_autoctl do service postgres --pgdata /var/lib/postgresql/data/pgdata -v
13:00:19 92 INFO  Started pg_autoctl listener service with pid 96
13:00:19 96 INFO   /usr/bin/pg_autoctl do service listener --pgdata /var/lib/postgresql/data/pgdata -v
13:00:19 96 INFO  Managing the monitor at postgres://autoctl_node@otus-12-pgaf-mon:5432/pg_auto_failover?sslmode=require
13:00:19 96 INFO  Reloaded the new configuration from "/var/lib/postgresql/.config/pg_autoctl/var/lib/postgresql/data/pgdata/pg_autoctl.cfg"
13:00:19 105 INFO   /usr/lib/postgresql/15/bin/postgres -D /var/lib/postgresql/data/pgdata -p 5432 -h *
13:00:19 95 INFO  Postgres is now serving PGDATA "/var/lib/postgresql/data/pgdata" on port 5432 with pid 105
13:00:21 96 INFO  The version of extension "pgautofailover" is "2.0" on the monitor
13:00:21 96 INFO  Contacting the monitor to LISTEN to its events.
^C
```

- Проверим статус - процесс запущен, в кластере пусто

```
postgres@a4ba6290f47f:~$ pg_autoctl status
13:00:50 119 INFO  pg_autoctl is running with pid 92
13:00:50 119 INFO  Postgres is serving PGDATA "/var/lib/postgresql/data/pgdata" on port 5432 with pid 105
postgres@a4ba6290f47f:~$ pg_autoctl show state
Name |  Node |  Host:Port |  TLI: LSN |   Connection |      Reported State |      Assigned State
-----+-------+------------+-----------+--------------+---------------------+--------------------
```

- После этого можем подключаться к БД мониторинга - pg_auto_failover чтобы задать пароль для пользователя autoctl_node, т.к. он нужен для подключения дата-нод и для самого postgres (TODO: выяснить почему не сработала переменная окружения)

```
postgres@a4ba6290f47f:~$ psql
psql (15.4 (Debian 15.4-2.pgdg110+1))
Type "help" for help.

postgres=# \l
                                                    List of databases
       Name       |  Owner   | Encoding |  Collate   |   Ctype    | ICU Locale | Locale Provider |   Access privileges   
------------------+----------+----------+------------+------------+------------+-----------------+-----------------------
 pg_auto_failover | autoctl  | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            | 
 postgres         | postgres | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            | 
 template0        | postgres | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            | =c/postgres          +
                  |          |          |            |            |            |                 | postgres=CTc/postgres
 template1        | postgres | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            | =c/postgres          +
                  |          |          |            |            |            |                 | postgres=CTc/postgres
(4 rows)

postgres=# \du
                                     List of roles
  Role name   |                         Attributes                         | Member of 
--------------+------------------------------------------------------------+-----------
 autoctl      |                                                            | {}
 autoctl_node |                                                            | {}
 postgres     | Superuser, Create role, Create DB, Replication, Bypass RLS | {}

postgres=# alter user autoctl_node password 'P_ssw0rd';
ALTER ROLE
postgres=# alter user postgres password 'P_ssw0rd';
ALTER ROLE
```

- Кроме этого открываем доступы в /data/postgres/pgdata/postgresql.conf и pg_hba.conf, рестартуем постгрес - pg_autoctl stop и снова pg_autoctl run & (в бекграунде)

```
-- postgresql.conf
listen_addresses = '*'

-- pg_hba.conf
host    all             all             0.0.0.0/0            md5
host    all             all             ::0/0                md5
```

- Проверим снаружи что в БД мониторинга

![Таблицы бд мониторинга pg_autofailover](screen_pgaf_monitor_tables.png)


## Настройка первой дата-ноды

- Подключаемся к ноде и заходим в контейнер (стартован как описано выше), создаём ноду и подключаем её к монитору otus-12-pgaf-mon, здесь как раз испоьзуется пароль от пользователя autoctl_node

```
anton@otus-12-pgaf-data1:~$ sudo docker exec -it postgres bash
postgres@76057efda68a:~$ pg_autoctl create postgres --hostname otus-12-pgaf-data1 --name pgdata1 --auth md5 --ssl-self-signed --monitor 'postgres://autoctl_node:P_ssw0rd@otus-12-pgaf-mon:5432/pg_auto_failover?sslmode=require' --pgport 5432 --pgctl /usr/lib/postgresql/15/bin/pg_ctl
13:13:08 27 INFO  Using default --ssl-mode "require"
13:13:08 27 INFO  Using --ssl-self-signed: pg_autoctl will create self-signed certificates, allowing for encrypted network traffic
13:13:08 27 WARN  Self-signed certificates provide protection against eavesdropping; this setup does NOT protect against Man-In-The-Middle attacks nor Impersonation attacks.
13:13:08 27 WARN  See https://www.postgresql.org/docs/current/libpq-ssl.html for details
13:13:08 27 WARN  Failed to resolve hostname "otus-12-pgaf-data1" to a local IP address, automated pg_hba.conf setup might fail.
13:13:09 27 INFO  Started pg_autoctl postgres service with pid 29
13:13:09 29 INFO   /usr/bin/pg_autoctl do service postgres --pgdata /var/lib/postgresql/data/pgdata -v
13:13:09 27 INFO  Started pg_autoctl node-init service with pid 30
13:13:09 30 INFO  Registered node 1 "pgdata1" (otus-12-pgaf-data1:5432) in formation "default", group 0, state "single"
13:13:09 30 INFO  Writing keeper state file at "/var/lib/postgresql/.local/share/pg_autoctl/var/lib/postgresql/data/pgdata/pg_autoctl.state"
13:13:09 30 INFO  Writing keeper init state file at "/var/lib/postgresql/.local/share/pg_autoctl/var/lib/postgresql/data/pgdata/pg_autoctl.init"
13:13:09 30 INFO  Successfully registered as "single" to the monitor.
13:13:09 30 INFO  FSM transition from "init" to "single": Start as a single node
13:13:09 30 INFO  Initialising postgres as a primary
13:13:09 30 INFO  Initialising a PostgreSQL cluster at "/var/lib/postgresql/data/pgdata"
13:13:09 30 INFO  /usr/lib/postgresql/15/bin/pg_ctl initdb -s -D /var/lib/postgresql/data/pgdata --option '--auth=trust'
13:13:17 30 WARN  Failed to resolve hostname "otus-12-pgaf-data1" to an IP address that resolves back to the hostname on a reverse DNS lookup.
13:13:17 30 WARN  Postgres might deny connection attempts from "otus-12-pgaf-data1", even with the new HBA rules.
13:13:17 30 WARN  Hint: correct setup of HBA with host names requires proper reverse DNS setup. You might want to use IP addresses.
13:13:17 30 WARN  Using IP address "10.129.0.31" in HBA file instead of hostname "otus-12-pgaf-data1"
13:13:17 30 INFO   /usr/bin/openssl req -new -x509 -days 365 -nodes -text -out /var/lib/postgresql/data/pgdata/server.crt -keyout /var/lib/postgresql/data/pgdata/server.key -subj "/CN=otus-12-pgaf-data1"
13:13:17 55 INFO   /usr/lib/postgresql/15/bin/postgres -D /var/lib/postgresql/data/pgdata -p 5432 -h *
13:13:18 30 INFO  The user "postgres" already exists, skipping.
13:13:18 30 INFO  CREATE DATABASE postgres;
13:13:18 30 INFO  The database "postgres" already exists, skipping.
13:13:18 30 INFO  CREATE EXTENSION pg_stat_statements;
13:13:18 29 INFO  Postgres is now serving PGDATA "/var/lib/postgresql/data/pgdata" on port 5432 with pid 55
13:13:18 30 INFO  Disabling synchronous replication
13:13:18 30 INFO  Reloading Postgres configuration and HBA rules
13:13:18 30 INFO   /usr/bin/openssl req -new -x509 -days 365 -nodes -text -out /var/lib/postgresql/data/pgdata/server.crt -keyout /var/lib/postgresql/data/pgdata/server.key -subj "/CN=otus-12-pgaf-data1"
13:13:18 30 INFO  Contents of "/var/lib/postgresql/data/pgdata/postgresql-auto-failover.conf" have changed, overwriting
13:13:18 30 WARN  Failed to resolve hostname "otus-12-pgaf-mon" to an IP address that resolves back to the hostname on a reverse DNS lookup.
13:13:18 30 WARN  Postgres might deny connection attempts from "otus-12-pgaf-mon", even with the new HBA rules.
13:13:18 30 WARN  Hint: correct setup of HBA with host names requires proper reverse DNS setup. You might want to use IP addresses.
13:13:18 30 WARN  Using IP address "10.129.0.24" in HBA file instead of hostname "otus-12-pgaf-mon"
13:13:18 30 INFO  Reloading Postgres configuration and HBA rules
13:13:19 30 INFO  Transition complete: current state is now "single"
13:13:19 30 INFO  keeper has been successfully initialized.
13:13:19 27 WARN  pg_autoctl service node-init exited with exit status 0
13:13:19 29 INFO  Postgres controller service received signal SIGTERM, terminating
13:13:19 29 INFO  Stopping pg_autoctl postgres service
13:13:19 29 INFO  /usr/lib/postgresql/15/bin/pg_ctl --pgdata /var/lib/postgresql/data/pgdata --wait stop --mode fast
13:13:19 27 INFO  Waiting for subprocesses to terminate.
13:13:19 27 INFO  Stop pg_autoctl
postgres@76057efda68a:~$ 
```

- Посмотрим что получилось на мониторинге

```
13:13:09 150 INFO  Registering node 1 "pgdata1" (otus-12-pgaf-data1:5432) to formation "default" with replication quorum true and candidate priority 50 [50]
13:13:09 150 INFO  Setting goal state of node 1 "pgdata1" (otus-12-pgaf-data1:5432) to single as there is no other node.
13:13:09 150 INFO  New state for node 1 "pgdata1" (otus-12-pgaf-data1:5432): init ➜ single
13:13:18 150 INFO  Node node 1 "pgdata1" (otus-12-pgaf-data1:5432) is marked as unhealthy by the monitor
13:13:18 150 INFO  New state for node 1 "pgdata1" (otus-12-pgaf-data1:5432): init ➜ single
13:13:19 150 INFO  New state is reported by node 1 "pgdata1" (otus-12-pgaf-data1:5432): "single"
13:13:19 150 INFO  New state for node 1 "pgdata1" (otus-12-pgaf-data1:5432): single ➜ singl

postgres@a4ba6290f47f:~$ pg_autoctl show state
   Name |  Node |               Host:Port |       TLI: LSN |   Connection |      Reported State |      Assigned State
--------+-------+-------------------------+----------------+--------------+---------------------+--------------------
pgdata1 |     1 | otus-12-pgaf-data1:5432 |   1: 0/15568A0 | read-write ! |              single |              single
```

- Нода подключилась, но не запущена. Теперь запустим постгрес на первой ноде в бэкграунде, предварительно проставив * в postgresql.conf нули в pg_hba чтобы можно было подключаться извне.

```
anton@otus-12-pgaf-data1:~$ sudo docker exec -it postgres bash
postgres@76057efda68a:~$ pg_autoctl run &
[1] 89
postgres@76057efda68a:~$ 13:16:02 89 INFO  Started pg_autoctl postgres service with pid 92
13:16:02 92 INFO   /usr/bin/pg_autoctl do service postgres --pgdata /var/lib/postgresql/data/pgdata -v
13:16:02 89 INFO  Started pg_autoctl node-active service with pid 93
13:16:02 93 INFO   /usr/bin/pg_autoctl do service node-active --pgdata /var/lib/postgresql/data/pgdata -v
13:16:02 93 INFO  Reloaded the new configuration from "/var/lib/postgresql/.config/pg_autoctl/var/lib/postgresql/data/pgdata/pg_autoctl.cfg"
13:16:02 93 INFO  pg_autoctl service is running, current state is "single"
13:16:02 101 INFO   /usr/lib/postgresql/15/bin/postgres -D /var/lib/postgresql/data/pgdata -p 5432 -h *
13:16:03 92 INFO  Postgres is now serving PGDATA "/var/lib/postgresql/data/pgdata" on port 5432 with pid 101
13:16:03 93 WARN  PostgreSQL was not running, restarted with pid 101
13:16:04 93 INFO  New state for this node (node 1, "pgdata1") (otus-12-pgaf-data1:5432): single ➜ single
^C
```

- Проверим состояние на мониторинге

```
13:16:04 150 INFO  Node node 1 "pgdata1" (otus-12-pgaf-data1:5432) is marked as healthy by the monitor
13:16:04 150 INFO  New state for node 1 "pgdata1" (otus-12-pgaf-data1:5432): single ➜ single

postgres@a4ba6290f47f:~$ pg_autoctl show state
   Name |  Node |               Host:Port |       TLI: LSN |   Connection |      Reported State |      Assigned State
--------+-------+-------------------------+----------------+--------------+---------------------+--------------------
pgdata1 |     1 | otus-12-pgaf-data1:5432 |   1: 0/1594B98 |   read-write |              single |              single
```

- Сменим пароль для пользователя репликации на первой ноде чтобы можно было подключить вторую, а также пароль postgres

```
postgres@76057efda68a:~$ psql
psql (15.4 (Debian 15.4-2.pgdg110+1))
Type "help" for help.

postgres=# \du
                                           List of roles
         Role name         |                         Attributes                         | Member of 
---------------------------+------------------------------------------------------------+-----------
 pgautofailover_monitor    | 1 connection                                               | {}
 pgautofailover_replicator | Superuser, Replication                                     | {}
 postgres                  | Superuser, Create role, Create DB, Replication, Bypass RLS | {}

postgres=# alter user pgautofailover_replicator password 'P_ssw0rd';
ALTER ROLE
```

- Подключимся извне через DBeaver, создадим базу otus и создадим табличку в ней, добавим данные

```
CREATE TABLE public.newtable (
	id varchar NOT NULL,
	name text NULL,
	CONSTRAINT newtable_pk PRIMARY KEY (id)
);

INSERT INTO public.newtable (id, "name") VALUES('1', 'First');
```

![Табличка в базе otus](screen_pgaf_node1_table.png)


## Настройка второй дата-ноды

- Подключаемся к ноде и заходим в контейнер, как и на первой ноде - создаём ноду и подключаем её к монитору otus-12-pgaf-mon

```
anton@otus-12-pgaf-data2:~$ sudo docker exec -it postgres bash
postgres@e5ed81bdf96d:~$ pg_autoctl create postgres --hostname otus-12-pgaf-data2 --name pgdata2 --auth md5 --ssl-self-signed --monitor 'postgres://autoctl_node:P_ssw0rd@otus-12-pgaf-mon:5432/pg_auto_failover?sslmode=require' --pgport 5432 --pgctl /usr/lib/postgresql/15/bin/pg_ctl
...
13:31:10 38 INFO  Restarting service node-init
13:31:10 47 INFO  Continuing from a previous `pg_autoctl create` failed attempt
13:31:10 47 INFO  PostgreSQL state at registration time was: PGDATA does not exist
13:31:10 47 INFO  FSM transition from "wait_standby" to "catchingup": The primary is now ready to accept a standby
13:31:10 47 INFO  Initialising PostgreSQL as a hot standby
13:31:10 47 WARN  Failed to connect to "postgres://pgautofailover_replicator@otus-12-pgaf-data1:5432/postgres?", retrying until the server is ready
13:31:13 47 ERROR Connection to database failed: connection to server at "otus-12-pgaf-data1" (10.129.0.31), port 5432 failed: fe_sendauth: no password supplied
13:31:13 47 ERROR Failed to connect to "postgres://pgautofailover_replicator@otus-12-pgaf-data1:5432/postgres?" after 7 attempts in 2790 ms, pg_autoctl stops retrying now
13:31:13 47 ERROR Failed to initialize standby server, see above for details
13:31:13 47 ERROR Failed to transition from state "wait_standby" to state "catchingup", see above.
13:31:13 38 ERROR pg_autoctl service node-init exited with exit status 12
13:31:13 38 FATAL pg_autoctl service node-init has already been restarted 5 times in the last 15 seconds, stopping now
13:31:13 40 INFO  Postgres controller service received signal SIGTERM, terminating
13:31:13 38 FATAL Something went wrong in sub-process supervision, stopping now. See above for details.
13:31:13 38 INFO  Stop pg_autoctl
```

- Посыпались ошибки т.к. не указали пароль для пользователя pgautofailover_replicator. Тем временем на первой ноде в лог сыпется инфа о подключении второй ноды:

```
13:26:06 970 INFO  New state for node 2 "pgdata2" (otus-12-pgaf-data2:5432): wait_standby ➜ wait_standby
13:26:06 970 INFO  Fetched current list of 1 other nodes from the monitor to update HBA rules, including 1 changes.
13:26:06 970 WARN  Failed to resolve hostname "otus-12-pgaf-data2" to an IP address that resolves back to the hostname on a reverse DNS lookup.
13:26:06 970 WARN  Postgres might deny connection attempts from "otus-12-pgaf-data2", even with the new HBA rules.
13:26:06 970 WARN  Hint: correct setup of HBA with host names requires proper reverse DNS setup. You might want to use IP addresses.
13:26:06 970 WARN  Using IP address "10.129.0.27" in HBA file instead of hostname "otus-12-pgaf-data2"
13:26:06 970 INFO  Ensuring HBA rules for node 2 "pgdata2" (10.129.0.27:5432)
13:26:06 970 INFO  Adding HBA rule: hostssl replication "pgautofailover_replicator" 10.129.0.27/32 md5
13:26:06 970 INFO  Adding HBA rule: hostssl "postgres" "pgautofailover_replicator" 10.129.0.27/32 md5
13:26:06 970 INFO  Writing new HBA rules in "/var/lib/postgresql/data/pgdata/pg_hba.conf"
13:26:06 970 INFO  Reloading Postgres configuration and HBA rules
13:26:06 970 INFO  Monitor assigned new state "wait_primary"
13:26:06 970 INFO  Creating replication slot "pgautofailover_standby_2"
13:26:06 970 INFO  FSM transition from "single" to "wait_primary": A new secondary was added
13:26:06 970 INFO  Transition complete: current state is now "wait_primary"
13:26:06 970 INFO  New state for this node (node 1, "pgdata1") (otus-12-pgaf-data1:5432): single ➜ wait_primary
13:26:06 970 INFO  New state for this node (node 1, "pgdata1") (otus-12-pgaf-data1:5432): wait_primary ➜ wait_primary
13:26:06 970 INFO  New state for node 2 "pgdata2" (otus-12-pgaf-data2:5432): wait_standby ➜ catchingup
13:26:15 970 INFO  New state for node 2 "pgdata2" (otus-12-pgaf-data2:5432): wait_standby ➜ catchingup
```

- И на мониторинге также видно лог

```
13:26:06 150 INFO  Registering node 2 "pgdata2" (otus-12-pgaf-data2:5432) to formation "default" with replication quorum true and candidate priority 50 [50]
13:26:06 150 INFO  New state is reported by node 2 "pgdata2" (otus-12-pgaf-data2:5432): "wait_standby"
13:26:06 150 INFO  New state for node 2 "pgdata2" (otus-12-pgaf-data2:5432): wait_standby ➜ wait_standby
13:26:06 150 INFO  Setting goal state of node 1 "pgdata1" (otus-12-pgaf-data1:5432) to wait_primary after node 2 "pgdata2" (otus-12-pgaf-data2:5432) joined.
13:26:06 150 INFO  New state for node 1 "pgdata1" (otus-12-pgaf-data1:5432): single ➜ wait_primary
13:26:06 150 INFO  New state is reported by node 1 "pgdata1" (otus-12-pgaf-data1:5432): "wait_primary"
13:26:06 150 INFO  New state for node 1 "pgdata1" (otus-12-pgaf-data1:5432): wait_primary ➜ wait_primary
13:26:06 150 INFO  Setting goal state of node 2 "pgdata2" (otus-12-pgaf-data2:5432) to catchingup after node 1 "pgdata1" (otus-12-pgaf-data1:5432) converged to wait_primary.
13:26:06 150 INFO  New state for node 2 "pgdata2" (otus-12-pgaf-data2:5432): wait_standby ➜ catchingup
13:26:15 150 INFO  Node node 2 "pgdata2" (otus-12-pgaf-data2:5432) is marked as unhealthy by the monitor
13:26:15 150 INFO  New state for node 2 "pgdata2" (otus-12-pgaf-data2:5432): wait_standby ➜ catchingup
```

- Проверим состояние на мониторинге, первую ноду переключило из single в wait_primary, вторая нода в состоянии wait_standby и catchingup, подключения нет. Подробнее о режимах запуска нод в документации: https://pg-auto-failover.readthedocs.io/en/main/ref/pg_autoctl_create_postgres.html, наш вариант здесь "3. Initialize a secondary node from scratch"


```
postgres@a4ba6290f47f:~$ pg_autoctl show state
   Name |  Node |               Host:Port |       TLI: LSN |   Connection |      Reported State |      Assigned State
--------+-------+-------------------------+----------------+--------------+---------------------+--------------------
pgdata1 |     1 | otus-12-pgaf-data1:5432 |   1: 0/19E0C30 |   read-write |        wait_primary |        wait_primary
pgdata2 |     2 | otus-12-pgaf-data2:5432 |         1: 0/0 |       none ! |        wait_standby |          catchingup
```

- Проставим пароль для pgautofailover_replicator в конфиг второй ноды и зададим в переменной окружения (как указано здесь - https://community.pivotal.io/s/article/5004y00001aqNxl1626336795588?language=en_US)

```
postgres@af62ffdc07dc:~$ pg_autoctl config set replication.password "P_ssw0rd"
P_ssw0rd
postgres@af62ffdc07dc:~$ export PGPASSWORD="P_ssw0rd"
postgres@af62ffdc07dc:~$ pg_autoctl config get
[pg_autoctl]
role = keeper
monitor = postgres://autoctl_node:P_ssw0rd@otus-12-pgaf-mon:5432/pg_auto_failover?sslmode=require
formation = default
group = 0
name = pgdata2
hostname = otus-12-pgaf-data2
nodekind = standalone

[postgresql]
pgdata = /var/lib/postgresql/data/pgdata
pg_ctl = /usr/lib/postgresql/15/bin/pg_ctl
username = postgres
dbname = postgres
host = /var/run/postgresql
port = 5432
proxyport = 0
listen_addresses = *
auth_method = md5
hba_level = minimal

[ssl]
active = 1
sslmode = require

[replication]
maximum_backup_rate = 100M
backup_directory = /var/lib/postgresql/data/backup/node_2
password = P_ssw0rd

[timeout]
network_partition_timeout = 20
prepare_promotion_catchup = 30
prepare_promotion_walreceiver = 5
postgresql_restart_failure_timeout = 20
postgresql_restart_failure_max_retries = 3
listen_notifications_timeout = 0
citus_master_update_node_lock_cooldown = 0
citus_coordinator_wait_max_retries = 0
citus_coordinator_wait_timeout = 0

[citus]
role = primary
```

- Стартуем вторую ноду

```
postgres@af62ffdc07dc:~$ pg_autoctl run &
[1] 89
postgres@af62ffdc07dc:~$ 14:01:13 89 INFO  Started pg_autoctl postgres service with pid 91
14:01:13 91 INFO   /usr/bin/pg_autoctl do service postgres --pgdata /var/lib/postgresql/data/pgdata -v
14:01:13 89 INFO  Started pg_autoctl node-active service with pid 92
14:01:13 92 INFO   /usr/bin/pg_autoctl do service node-active --pgdata /var/lib/postgresql/data/pgdata -v
14:01:13 92 WARN  The `pg_autoctl create` did not complete, completing now.
14:01:13 92 INFO  Continuing from a previous `pg_autoctl create` failed attempt
14:01:13 92 INFO  PostgreSQL state at registration time was: PGDATA does not exist
14:01:13 92 INFO  FSM transition from "wait_standby" to "catchingup": The primary is now ready to accept a standby
14:01:13 92 INFO  Initialising PostgreSQL as a hot standby
14:01:13 92 INFO   /usr/lib/postgresql/15/bin/pg_basebackup -w -d 'application_name=pgautofailover_standby_2 host=otus-12-pgaf-data1 port=5432 user=pgautofailover_replicator sslmode=require' --pgdata /var/lib/postgresql/data/backup/node_2 -U pgautofailover_replicator --verbose --progress --max-rate 100M --wal-method=stream --slot pgautofailover_standby_2
14:01:14 92 INFO  pg_basebackup: initiating base backup, waiting for checkpoint to complete
14:01:15 92 INFO  pg_basebackup: checkpoint completed
14:01:15 92 INFO  pg_basebackup: write-ahead log start point: 0/2000028 on timeline 1
14:01:15 92 INFO  pg_basebackup: starting background WAL receiver
14:01:15 92 INFO     79/30683 kB (0%), 0/1 tablespace (...ta/backup/node_2/postgresql.conf)
14:01:15 92 INFO  30693/30693 kB (100%), 0/1 tablespace (.../backup/node_2/global/pg_control)
14:01:15 92 INFO  30693/30693 kB (100%), 1/1 tablespace                                         
14:01:15 92 INFO  pg_basebackup: write-ahead log end point: 0/2000100
14:01:15 92 INFO  pg_basebackup: waiting for background process to finish streaming ...
14:01:15 92 INFO  pg_basebackup: syncing data to disk ...
14:01:17 92 INFO  pg_basebackup: renaming backup_manifest.tmp to backup_manifest
14:01:17 92 INFO  pg_basebackup: base backup completed
14:01:17 92 INFO  Creating the standby signal file at "/var/lib/postgresql/data/pgdata/standby.signal", and replication setup at "/var/lib/postgresql/data/pgdata/postgresql-auto-failover-standby.conf"
14:01:17 92 INFO  Contents of "/var/lib/postgresql/data/pgdata/postgresql-auto-failover.conf" have changed, overwriting
14:01:17 100 INFO   /usr/lib/postgresql/15/bin/postgres -D /var/lib/postgresql/data/pgdata -p 5432 -h *
14:01:18 92 INFO  PostgreSQL started on port 5432
14:01:18 92 INFO  Fetched current list of 1 other nodes from the monitor to update HBA rules, including 1 changes.
14:01:18 92 WARN  Failed to resolve hostname "otus-12-pgaf-data1" to an IP address that resolves back to the hostname on a reverse DNS lookup.
14:01:18 92 WARN  Postgres might deny connection attempts from "otus-12-pgaf-data1", even with the new HBA rules.
14:01:18 92 WARN  Hint: correct setup of HBA with host names requires proper reverse DNS setup. You might want to use IP addresses.
14:01:18 92 WARN  Using IP address "10.129.0.31" in HBA file instead of hostname "otus-12-pgaf-data1"
14:01:18 92 INFO  Ensuring HBA rules for node 1 "pgdata1" (10.129.0.31:5432)
14:01:18 92 INFO  Adding HBA rule: hostssl replication "pgautofailover_replicator" 10.129.0.31/32 md5
14:01:18 92 INFO  Adding HBA rule: hostssl "postgres" "pgautofailover_replicator" 10.129.0.31/32 md5
14:01:18 92 INFO  Writing new HBA rules in "/var/lib/postgresql/data/pgdata/pg_hba.conf"
14:01:18 92 INFO  Reloading Postgres configuration and HBA rules
14:01:18 91 INFO  Postgres is now serving PGDATA "/var/lib/postgresql/data/pgdata" on port 5432 with pid 100
14:01:18 92 INFO  Transition complete: current state is now "catchingup"
14:01:18 92 INFO  Reloaded the new configuration from "/var/lib/postgresql/.config/pg_autoctl/var/lib/postgresql/data/pgdata/pg_autoctl.cfg"
14:01:18 92 INFO  Reloading Postgres configuration and HBA rules
14:01:18 92 INFO  pg_autoctl service is running, current state is "catchingup"
14:01:18 92 INFO  New state for this node (node 2, "pgdata2") (otus-12-pgaf-data2:5432): catchingup ➜ catchingup
14:01:18 92 INFO  Monitor assigned new state "secondary"
14:01:18 92 INFO  FSM transition from "catchingup" to "secondary": Convinced the monitor that I'm up and running, and eligible for promotion again
14:01:18 92 INFO  Reached timeline 1, same as upstream node 1 "pgdata1" (otus-12-pgaf-data1:5432)
14:01:18 92 INFO  Creating replication slot "pgautofailover_standby_1"
14:01:18 92 INFO  Transition complete: current state is now "secondary"
14:01:19 92 INFO  New state for this node (node 2, "pgdata2") (otus-12-pgaf-data2:5432): catchingup ➜ secondary
14:01:19 92 INFO  New state for this node (node 2, "pgdata2") (otus-12-pgaf-data2:5432): secondary ➜ secondary
14:01:19 92 INFO  New state for node 1 "pgdata1" (otus-12-pgaf-data1:5432): wait_primary ➜ primary
14:01:19 92 INFO  New state for node 1 "pgdata1" (otus-12-pgaf-data1:5432): primary ➜ primary
^C
```

- Видно что использовался pg_basebackup. Логи на первой ноде и на мониторинге

```
14:01:18 970 INFO  New state for node 2 "pgdata2" (otus-12-pgaf-data2:5432): catchingup ➜ catchingup
14:01:18 970 INFO  New state for node 2 "pgdata2" (otus-12-pgaf-data2:5432): catchingup ➜ catchingup
14:01:18 970 INFO  New state for node 2 "pgdata2" (otus-12-pgaf-data2:5432): catchingup ➜ secondary
14:01:19 970 INFO  New state for node 2 "pgdata2" (otus-12-pgaf-data2:5432): secondary ➜ secondary
14:01:19 970 INFO  Monitor assigned new state "primary"
14:01:19 970 INFO  FSM transition from "wait_primary" to "primary": A healthy secondary appeared
14:01:19 970 INFO  Setting synchronous_standby_names to 'ANY 1 (pgautofailover_standby_2)'
14:01:19 970 INFO  Reloading Postgres configuration and HBA rules
14:01:19 970 INFO  Waiting until standby node has caught-up to LSN 0/3000000
14:01:19 970 INFO  Standby reached LSN 0/3000000, thus advanced past LSN 0/3000000
14:01:19 970 INFO  Transition complete: current state is now "primary"
14:01:19 970 INFO  New state for this node (node 1, "pgdata1") (otus-12-pgaf-data1:5432): wait_primary ➜ primary
14:01:19 970 INFO  New state for this node (node 1, "pgdata1") (otus-12-pgaf-data1:5432): primary ➜ primary

14:01:18 150 INFO  New state is reported by node 2 "pgdata2" (otus-12-pgaf-data2:5432): "catchingup"
14:01:18 150 INFO  New state for node 2 "pgdata2" (otus-12-pgaf-data2:5432): catchingup ➜ catchingup
14:01:18 150 INFO  Node node 2 "pgdata2" (otus-12-pgaf-data2:5432) is marked as healthy by the monitor
14:01:18 150 INFO  New state for node 2 "pgdata2" (otus-12-pgaf-data2:5432): catchingup ➜ catchingup
14:01:18 150 INFO  Setting goal state of node 2 "pgdata2" (otus-12-pgaf-data2:5432) to secondary after it caught up.
14:01:18 150 INFO  New state for node 2 "pgdata2" (otus-12-pgaf-data2:5432): catchingup ➜ secondary
14:01:19 150 INFO  New state is reported by node 2 "pgdata2" (otus-12-pgaf-data2:5432): "secondary"
14:01:19 150 INFO  New state for node 2 "pgdata2" (otus-12-pgaf-data2:5432): secondary ➜ secondary
14:01:19 150 INFO  Setting goal state of node 1 "pgdata1" (otus-12-pgaf-data1:5432) to primary now that we have 1 healthy  secondary nodes in the quorum.
14:01:19 150 INFO  New state for node 1 "pgdata1" (otus-12-pgaf-data1:5432): wait_primary ➜ primary
14:01:19 150 INFO  New state is reported by node 1 "pgdata1" (otus-12-pgaf-data1:5432): "primary"
14:01:19 150 INFO  New state for node 1 "pgdata1" (otus-12-pgaf-data1:5432): primary ➜ primary
```

- Проверим состояние на мониторинге

```
postgres@a4ba6290f47f:~$ pg_autoctl show state
   Name |  Node |               Host:Port |       TLI: LSN |   Connection |      Reported State |      Assigned State
--------+-------+-------------------------+----------------+--------------+---------------------+--------------------
pgdata1 |     1 | otus-12-pgaf-data1:5432 |   1: 0/3000148 |   read-write |             primary |             primary
pgdata2 |     2 | otus-12-pgaf-data2:5432 |   1: 0/3000148 |    read-only |           secondary |           secondary
```

- Обе ноды запущены. Попробуем подключиться извне через DBeaver ко второй ноде и добавить данные.

![Ошибка read only для secondary](screen_pgaf_node2_readonly.png)

- Ожидаемо получаем ошибку, т.к. secondary работает только на чтение. Добавим строку через primary и проверим на secondary.

```
anton@otus-12-pgaf-data1:~$ sudo docker exec -it postgres bash
postgres@76057efda68a:~$ psql
psql (15.4 (Debian 15.4-2.pgdg110+1))
Type "help" for help.

postgres=# \c otus
You are now connected to database "otus" as user "postgres".
otus=# INSERT INTO public.newtable (id, "name") VALUES('2', 'Second');
INSERT 0 1

anton@otus-12-pgaf-data2:~$ sudo docker exec -it postgres bash
postgres@af62ffdc07dc:~$ psql
psql (15.4 (Debian 15.4-2.pgdg110+1))
Type "help" for help.

postgres=# \c otus
You are now connected to database "otus" as user "postgres".
otus=# SELECT * FROM public.newtable;
 id |  name  
----+--------
 1  | First
 2  | Second
(2 rows)
```

## Проверка HA

- Теперь попробуем остановить первую ноду и посмотрим что произойдёт

```
postgres@a4ba6290f47f:~$
14:20:16 150 INFO  Node node 1 "pgdata1" (otus-12-pgaf-data1:5432) is marked as unhealthy by the monitor
14:20:16 150 INFO  New state for node 1 "pgdata1" (otus-12-pgaf-data1:5432): primary ➜ primary

postgres@a4ba6290f47f:~$ pg_autoctl show state
   Name |  Node |               Host:Port |       TLI: LSN |   Connection |      Reported State |      Assigned State
--------+-------+-------------------------+----------------+--------------+---------------------+--------------------
pgdata1 |     1 | otus-12-pgaf-data1:5432 |   1: 0/30010F0 | read-write ! |             primary |             primary
pgdata2 |     2 | otus-12-pgaf-data2:5432 |   1: 0/3001168 |    read-only |           secondary |           secondary

postgres@a4ba6290f47f:~$
14:20:27 150 INFO  Setting goal state of node 1 "pgdata1" (otus-12-pgaf-data1:5432) to draining and node 2 "pgdata2" (otus-12-pgaf-data2:5432) to prepare_promotion after node 1 "pgdata1" (otus-12-pgaf-data1:5432) became unhealthy.
14:20:27 150 INFO  New state for node 2 "pgdata2" (otus-12-pgaf-data2:5432): secondary ➜ prepare_promotion
14:20:27 150 INFO  New state for node 1 "pgdata1" (otus-12-pgaf-data1:5432): primary ➜ draining
14:20:27 150 INFO  New state is reported by node 2 "pgdata2" (otus-12-pgaf-data2:5432): "prepare_promotion"
14:20:27 150 INFO  New state for node 2 "pgdata2" (otus-12-pgaf-data2:5432): prepare_promotion ➜ prepare_promotion
14:20:27 150 INFO  Setting goal state of node 1 "pgdata1" (otus-12-pgaf-data1:5432) to demote_timeout and node 2 "pgdata2" (otus-12-pgaf-data2:5432) to stop_replication after node 2 "pgdata2" (otus-12-pgaf-data2:5432) converged to prepare_promotion.
14:20:27 150 INFO  New state for node 2 "pgdata2" (otus-12-pgaf-data2:5432): prepare_promotion ➜ stop_replication
14:20:27 150 INFO  New state for node 1 "pgdata1" (otus-12-pgaf-data1:5432): primary ➜ demote_timeout
14:20:29 150 INFO  New state is reported by node 2 "pgdata2" (otus-12-pgaf-data2:5432): "stop_replication"
14:20:29 150 INFO  New state for node 2 "pgdata2" (otus-12-pgaf-data2:5432): stop_replication ➜ stop_replication

postgres@a4ba6290f47f:~$ pg_autoctl show state
   Name |  Node |               Host:Port |       TLI: LSN |   Connection |      Reported State |      Assigned State
--------+-------+-------------------------+----------------+--------------+---------------------+--------------------
pgdata1 |     1 | otus-12-pgaf-data1:5432 |   1: 0/30010F0 | read-write ! |             primary |      demote_timeout
pgdata2 |     2 | otus-12-pgaf-data2:5432 |   2: 0/3001330 |    read-only |    stop_replication |    stop_replication

postgres@a4ba6290f47f:~$
14:20:58 150 INFO  Setting goal state of node 2 "pgdata2" (otus-12-pgaf-data2:5432) to wait_primary and node 1 "pgdata1" (otus-12-pgaf-data1:5432) to demoted after the demote timeout expired.
14:20:58 150 INFO  New state for node 2 "pgdata2" (otus-12-pgaf-data2:5432): stop_replication ➜ wait_primary
14:20:58 150 INFO  New state for node 1 "pgdata1" (otus-12-pgaf-data1:5432): primary ➜ demoted
14:20:58 150 INFO  New state is reported by node 2 "pgdata2" (otus-12-pgaf-data2:5432): "wait_primary"
14:20:58 150 INFO  New state for node 2 "pgdata2" (otus-12-pgaf-data2:5432): wait_primary ➜ wait_primary

postgres@a4ba6290f47f:~$ pg_autoctl show state
   Name |  Node |               Host:Port |       TLI: LSN |   Connection |      Reported State |      Assigned State
--------+-------+-------------------------+----------------+--------------+---------------------+--------------------
pgdata1 |     1 | otus-12-pgaf-data1:5432 |   1: 0/30010F0 | read-write ! |             primary |             demoted
pgdata2 |     2 | otus-12-pgaf-data2:5432 |   2: 0/3001330 |   read-write |        wait_primary |        wait_primary
```

- Первая нода стала demoted, вторая перешла в wait_primary и стала доступна на запись:

![Записано значение со старой ноды](screen_pgaf_node2_write.png)

- Если теперь запустить первую ноду обратно, она попытается стать secondary и... упадет т.к. пароль от пользователя репликации не задан ни на второй ноде ни на первой в конфиге и окружении.

```
postgres@a4ba6290f47f:~$ pg_autoctl show state
   Name |  Node |               Host:Port |       TLI: LSN |   Connection |      Reported State |      Assigned State
--------+-------+-------------------------+----------------+--------------+---------------------+--------------------
pgdata1 |     1 | otus-12-pgaf-data1:5432 |   1: 0/30010F0 |       none ! |             demoted |          catchingup
pgdata2 |     2 | otus-12-pgaf-data2:5432 |   2: 0/3001898 |   read-write |        wait_primary |        wait_primary
```

- Зададим пароль и стартуем

```
postgres@a4ba6290f47f:~$ pg_autoctl show state
   Name |  Node |               Host:Port |       TLI: LSN |   Connection |      Reported State |      Assigned State
--------+-------+-------------------------+----------------+--------------+---------------------+--------------------
pgdata1 |     1 | otus-12-pgaf-data1:5432 |   2: 0/3002318 |    read-only |           secondary |           secondary
pgdata2 |     2 | otus-12-pgaf-data2:5432 |   2: 0/3002318 |   read-write |             primary |             primary
```

- Ноды поменялись ролями