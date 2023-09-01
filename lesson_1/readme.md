# Создание виртуалки в Yandex Cloud

параметры: otus-db-pg-vm-1, Intel Ice Lake, 2 CPU, доля 50%, 4 ГБ RAM, прерываемая, зона ru-central1-b, 01.09.2023 13:44
ip внут: 10.129.0.9
ip внеш: 158.160.82.81
id: epdjg56h6jbv6vf04dtu

- публичный ключ для anton добавлен через интерфейс при создании

> ssh anton@158.160.82.81

anton@otus-db-pg-vm-1:~$ cat /etc/os-release
PRETTY_NAME="Ubuntu 22.04.3 LTS

# Установка PG

```
sudo apt update && sudo apt upgrade -y
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt-get update
sudo apt-get -y install postgresql
```

anton@otus-db-pg-vm-1:~$ sudo su - postgres

postgres@otus-db-pg-vm-1:~$ pg_lsclusters
Ver Cluster Port Status Owner    Data directory              Log file
15  main    5432 online postgres /var/lib/postgresql/15/main /var/log/postgresql/postgresql-15-

postgres@otus-db-pg-vm-1:~$ psql
psql (15.4 (Ubuntu 15.4-1.pgdg22.04+1))
Type "help" for help.

postgres=# \password
Enter new password for user "postgres": 
Enter it again: 
postgres=# \q

-- P@ssw0rd

# Настройка

- postgresql.conf
listen_addresses = '*'

- pg_hba.conf
host    all             all             0.0.0.0/0               scram-sha-256
host    all             all             ::/0                    scram-sha-256

sudo pg_ctlcluster 15 main restart

# Подключение с локальной машины

anton@aminkin:~$ psql -h 158.160.82.81 -U postgres
Пароль пользователя postgres: 
psql (11.17 (Debian 11.17-astra.se1+b1), сервер 15.4 (Ubuntu 15.4-1.pgdg22.04+1))
ПРЕДУПРЕЖДЕНИЕ: psql имеет базовую версию 11, а сервер - 15.
                Часть функций psql может не работать.
SSL-соединение (протокол: TLSv1.3, шифр: TLS_AES_256_GCM_SHA384, бит: 256, сжатие: выкл.)
Введите "help", чтобы получить справку.

postgres=#

# Уровни изоляции

## read committed

### сессия 1

postgres=# \set AUTOCOMMIT off
postgres=# select txid_current();
 txid_current 
--------------
          736
(1 строка)

postgres=# create table persons(id serial, first_name text, second_name text);
CREATE TABLE
postgres=# insert into persons(first_name, second_name) values('ivan', 'ivanov');
INSERT 0 1
postgres=# insert into persons(first_name, second_name) values('petr', 'petrov');
INSERT 0 1
postgres=# commit;
COMMIT

postgres=# show transaction isolation level;
 transaction_isolation 
-----------------------
 read committed
(1 строка)

postgres=# begin;
BEGIN
postgres=# select txid_current();
 txid_current 
--------------
          738
(1 строка)

postgres=# 
postgres=# insert into persons(first_name, second_name) values('sergey', 'sergeev');
INSERT 0 1

### сессия 2

postgres=# select txid_current();
 txid_current 
--------------
          737
(1 строка)

postgres=# select * from persons;
 id | first_name | second_name 
----+------------+-------------
  1 | ivan       | ivanov
  2 | petr       | petrov
(2 строки)

-- commit в первой сессии, начинаем видеть зафиксированное

postgres=# select * from persons;
 id | first_name | second_name 
----+------------+-------------
  1 | ivan       | ivanov
  2 | petr       | petrov
  3 | sergey     | sergeev
(3 строки)

## repeatable read

### сессия 1

postgres=# set transaction isolation level repeatable read;
SET
postgres=# select txid_current();
 txid_current 
--------------
          739
(1 строка)

postgres=# show transaction isolation level;
 transaction_isolation 
-----------------------
 repeatable read
(1 строка)

postgres=# insert into persons(first_name, second_name) values('sveta', 'svetova');
INSERT 0 1


### сессия 2

postgres=# set transaction isolation level repeatable read;
SET
postgres=# select * from persons;
 id | first_name | second_name 
----+------------+-------------
  1 | ivan       | ivanov
  2 | petr       | petrov
  3 | sergey     | sergeev
(3 строки)

-- svetova не видна, делаем commit в первой транзакции

postgres=# select * from persons;
 id | first_name | second_name 
----+------------+-------------
  1 | ivan       | ivanov
  2 | petr       | petrov
  3 | sergey     | sergeev
(3 строки)

-- все равно не видна, т.к. выводятся данные из снимка на начало транзакции, а в этот момент svetova ещё не была добавлена

postgres=# commit;
COMMIT
postgres=# select * from persons;
 id | first_name | second_name 
----+------------+-------------
  1 | ivan       | ivanov
  2 | petr       | petrov
  3 | sergey     | sergeev
  4 | sveta      | svetova
(4 строки)

-- а теперь svetova видна, т.к. была зафиксирована на момент начала транзакции