-- Создание объектов бд Finance
-- DDL (CREATE TABLE, ALTER TABLE и пр) выполняется только на координаторе 

-- =============== Словари ===============
-- 1) организации
CREATE TABLE dct_companies(
    company_id integer,
    company_name varchar(100),
    company_description TEXT,
    company_inn varchar(12),
    company_kpp varchar(12),
    parent_company_id integer,
    dttm_start timestamptz DEFAULT '1900-01-01 00:00:00'::timestamp,
    dttm_end   timestamptz DEFAULT '3000-12-31 00:00:00'::timestamp
);
ALTER TABLE dct_companies ADD CONSTRAINT pk_dct_companies PRIMARY KEY (company_id);
COMMENT ON TABLE dct_companies IS 'Словарь организаций';
COMMENT ON COLUMN dct_companies.company_id IS 'Словарь организаций - идентификатор';
COMMENT ON COLUMN dct_companies.company_name IS 'Словарь организаций - наименование';
COMMENT ON COLUMN dct_companies.company_description IS 'Словарь организаций - описание';
COMMENT ON COLUMN dct_companies.company_inn IS 'Словарь организаций - ИНН';
COMMENT ON COLUMN dct_companies.company_kpp IS 'Словарь организаций - КПП';
COMMENT ON COLUMN dct_companies.parent_company_id IS 'Словарь организаций - родительская организация';
COMMENT ON COLUMN dct_companies.dttm_start IS 'Словарь организаций - действует с';
COMMENT ON COLUMN dct_companies.dttm_end IS 'Словарь организаций - действует по';

-- шардируем как референсную таблицу (копия на каждый воркер) - выполняется на координаторе
SELECT create_reference_table('dct_companies');

-- если вдруг DDL выполнялись вручную на всех узлах, то будет ошибка:
-- finance=# SELECT create_reference_table('dct_companies');
-- ERROR:  relation "dct_companies" already exists
-- CONTEXT:  while executing command on citus-worker-1:5432

/*
-- проверим создание на координаторе

 finance=# \dt+
                                             List of relations
 Schema |     Name      | Type  |  Owner   | Persistence | Access method |    Size    |     Description     
--------+---------------+-------+----------+-------------+---------------+------------+---------------------
 public | dct_companies | table | postgres | permanent   | heap          | 8192 bytes | Словарь организаций
(1 row)

-- проверим на воркере - ок, но описания не подтягиваются
finance=# \dt+
                                         List of relations
 Schema |     Name      | Type  |  Owner   | Persistence | Access method |    Size    | Description 
--------+---------------+-------+----------+-------------+---------------+------------+-------------
 public | dct_companies | table | postgres | permanent   | heap          | 8192 bytes | 
(1 row)
*/

/*
-- если при запросах к системным представлениям появляется ошибка fe_sendauth

finance=# select * from citus_tables;
WARNING:  connection to the remote node citus-coord:5432 failed with the following error: fe_sendauth: no password supplied

-- то делаем файлик .pgpass в домашнем каталоге пользователя postgres с правами 600 в который прописываем пароль для хоста citus-coord

[postgres@citus-coord ~]$ cat ~/.pgpass 
citus-coord:5432:finance:postgres:AoU9k=[W++

finance=# select * from citus_tables;
  table_name   | citus_table_type | distribution_column | colocation_id | table_size | shard_count | table_owner | access_method 
---------------+------------------+---------------------+---------------+------------+-------------+-------------+---------------
 dct_companies | reference        | <none>              |             2 | 48 kB      |           1 | postgres    | heap
(1 row)
*/

-- 2) счета
CREATE TABLE dct_accounts(
    account_id varchar(20),
    parent_account_id varchar(20),
    account_description varchar(200)
);
ALTER TABLE dct_accounts ADD CONSTRAINT pk_dct_accounts PRIMARY KEY (account_id);
COMMENT ON TABLE dct_accounts IS 'План счетов МСФО';
COMMENT ON COLUMN dct_accounts.account_id IS 'План счетов - идентификатор счета';
COMMENT ON COLUMN dct_accounts.parent_account_id IS 'План счетов - наименование';
COMMENT ON COLUMN dct_accounts.account_description IS 'План счетов - описание';
SELECT create_reference_table('dct_accounts');

/*
finance=# SELECT create_reference_table('dct_accounts');
 create_reference_table 
------------------------
 
(1 row)

finance=# \dt+
                                             List of relations
 Schema |     Name      | Type  |  Owner   | Persistence | Access method |    Size    |     Description     
--------+---------------+-------+----------+-------------+---------------+------------+---------------------
 public | dct_accounts  | table | postgres | permanent   | heap          | 0 bytes    | План счетов МСФО
 public | dct_companies | table | postgres | permanent   | heap          | 8192 bytes | Словарь организаций
(2 rows)

finance=# select * from citus_tables;
  table_name   | citus_table_type | distribution_column | colocation_id | table_size | shard_count | table_owner | access_method 
---------------+------------------+---------------------+---------------+------------+-------------+-------------+---------------
 dct_accounts  | reference        | <none>              |             2 | 24 kB      |           1 | postgres    | heap
 dct_companies | reference        | <none>              |             2 | 48 kB      |           1 | postgres    | heap
(2 rows)

 */


-- =============== Данные ===============
-- 1) основная таблица операций
CREATE TABLE acc_data(
    transaction_id  bigint       NOT NULL,
    transaction_dt  date         NOT NULL,
    company_id      integer      NOT NULL,
    company_id_src  integer,
    account_id      varchar(20)  NOT NULL,
    account_id_src  varchar(20),
    operation_type  varchar(20),
    amount          numeric      NOT NULL,
    currency_code   varchar(3)   NOT NULL,
    custom_1        varchar(20),
    custom_2        varchar(20),
    custom_3        varchar(20),
    custom_4        varchar(20),
    custom_5        varchar(20)
) PARTITION BY RANGE (transaction_dt);
CREATE INDEX ON acc_data(transaction_dt);
ALTER TABLE acc_data ADD CONSTRAINT pk_acc_data PRIMARY KEY (company_id, transaction_id, transaction_dt);
COMMENT ON TABLE acc_data IS 'Операции по счетам';
COMMENT ON COLUMN acc_data.transaction_id   IS 'Операции по счетам - идентификатор операции';
COMMENT ON COLUMN acc_data.transaction_dt   IS 'Операции по счетам - дата операции';
COMMENT ON COLUMN acc_data.company_id       IS 'Операции по счетам - орагнизация';
COMMENT ON COLUMN acc_data.company_id_src   IS 'Операции по счетам - организация источник средств';
COMMENT ON COLUMN acc_data.account_id       IS 'Операции по счетам - счёт';
COMMENT ON COLUMN acc_data.account_id_src   IS 'Операции по счетам - счёт источник';
COMMENT ON COLUMN acc_data.operation_type   IS 'Операции по счетам - тип операции';
COMMENT ON COLUMN acc_data.amount           IS 'Операции по счетам - сумма';
COMMENT ON COLUMN acc_data.currency_code    IS 'Операции по счетам - валюта';
COMMENT ON COLUMN acc_data.custom_1 IS 'Операции по счетам - аналитика 1 уровня';
COMMENT ON COLUMN acc_data.custom_2 IS 'Операции по счетам - аналитика 2 уровня';
COMMENT ON COLUMN acc_data.custom_3 IS 'Операции по счетам - аналитика 3 уровня';
COMMENT ON COLUMN acc_data.custom_4 IS 'Операции по счетам - аналитика 4 уровня';
COMMENT ON COLUMN acc_data.custom_5 IS 'Операции по счетам - аналитика 5 уровня';

/*
finance=# \dt+
                                                   List of relations
 Schema |     Name      |       Type        |  Owner   | Persistence | Access method |    Size    |     Description     
--------+---------------+-------------------+----------+-------------+---------------+------------+---------------------
 public | acc_data      | partitioned table | postgres | permanent   |               | 0 bytes    | Операции по счетам
 public | dct_accounts  | table             | postgres | permanent   | heap          | 0 bytes    | План счетов МСФО
 public | dct_companies | table             | postgres | permanent   | heap          | 8192 bytes | Словарь организаций
(3 rows)

finance=# \d acc_data
                   Partitioned table "public.acc_data"
     Column     |         Type          | Collation | Nullable | Default 
----------------+-----------------------+-----------+----------+---------
 transaction_id | bigint                |           | not null | 
 transaction_dt | date                  |           | not null | 
 company_id     | integer               |           | not null | 
 company_id_src | integer               |           |          | 
 account_id     | character varying(20) |           | not null | 
 account_id_src | character varying(20) |           |          | 
 operation_type | character varying(20) |           |          | 
 amount         | numeric               |           | not null | 
 currency_code  | character varying(3)  |           | not null | 
 custom_1       | character varying(20) |           |          | 
 custom_2       | character varying(20) |           |          | 
 custom_3       | character varying(20) |           |          | 
 custom_4       | character varying(20) |           |          | 
 custom_5       | character varying(20) |           |          | 
Partition key: RANGE (transaction_dt)
Indexes:
    "pk_acc_data" PRIMARY KEY, btree (company_id, transaction_id, transaction_dt)
    "acc_data_transaction_dt_idx" btree (transaction_dt)
Number of partitions: 0
 */

-- сначала шардируем согласно доке, родительские таблицы появляются на воркерах
-- https://citus-doc.readthedocs.io/en/latest/use_cases/timeseries.html#automating-partition-creation
SELECT create_distributed_table('acc_data', 'company_id');

/*
finance=# SELECT create_distributed_table('acc_data', 'company_id');
 create_distributed_table 
--------------------------
 
(1 row
 */

-- теперь добавляем в партман, который сам создаст партиции для данных
-- https://github.com/pgpartman/pg_partman/blob/master/doc/pg_partman_howto.md#simple-time-based-1-partition-per-day
-- согласно доке citus "Citus will propagate partition creation to all the shards, creating a partition for each shard."
SELECT partman.create_parent(
      p_parent_table := 'public.acc_data'
    , p_control      := 'transaction_dt'
    , p_interval     := '1 month'
);

-- если нужно почистить - DELETE FROM partman.part_config WHERE parent_table = 'public.acc_data'; DROP TABLE partman.template_public_acc_data;

-- по доке параметр партмана p_premake по умолчанию = 4 что означает автоматическое создание 4 партиций до и после текущего момента
-- https://github.com/pgpartman/pg_partman/blob/master/doc/pg_partman.md

/*
finance=# SELECT partman.create_parent(
finance(#       p_parent_table := 'public.acc_data'
finance(#     , p_control      := 'transaction_dt'
finance(#     , p_interval     := '1 month'
finance(# );
 create_parent 
---------------
 t
(1 row)

finance=# \d+ acc_data
                                                                 Partitioned table "public.acc_data"
     Column     |         Type          | Collation | Nullable | Default | Storage  | Compression | Stats target |                    Description                    
----------------+-----------------------+-----------+----------+---------+----------+-------------+--------------+---------------------------------------------------
 transaction_id | bigint                |           | not null |         | plain    |             |              | Операции по счетам - идентификатор операции
 transaction_dt | date                  |           | not null |         | plain    |             |              | Операции по счетам - дата операции
 company_id     | integer               |           | not null |         | plain    |             |              | Операции по счетам - орагнизация
 company_id_src | integer               |           |          |         | plain    |             |              | Операции по счетам - организация источник средств
 account_id     | character varying(20) |           | not null |         | extended |             |              | Операции по счетам - счёт
 account_id_src | character varying(20) |           |          |         | extended |             |              | Операции по счетам - счёт источник
 operation_type | character varying(20) |           |          |         | extended |             |              | Операции по счетам - тип операции
 amount         | numeric               |           | not null |         | main     |             |              | Операции по счетам - сумма
 currency_code  | character varying(3)  |           | not null |         | extended |             |              | Операции по счетам - валюта
 custom_1       | character varying(20) |           |          |         | extended |             |              | Операции по счетам - аналитика 1 уровня
 custom_2       | character varying(20) |           |          |         | extended |             |              | Операции по счетам - аналитика 2 уровня
 custom_3       | character varying(20) |           |          |         | extended |             |              | Операции по счетам - аналитика 3 уровня
 custom_4       | character varying(20) |           |          |         | extended |             |              | Операции по счетам - аналитика 4 уровня
 custom_5       | character varying(20) |           |          |         | extended |             |              | Операции по счетам - аналитика 5 уровня
Partition key: RANGE (transaction_dt)
Indexes:
    "pk_acc_data" PRIMARY KEY, btree (company_id, transaction_id, transaction_dt)
    "acc_data_transaction_dt_idx" btree (transaction_dt)
Partitions: acc_data_p20230901 FOR VALUES FROM ('2023-09-01') TO ('2023-10-01'),
            acc_data_p20231001 FOR VALUES FROM ('2023-10-01') TO ('2023-11-01'),
            acc_data_p20231101 FOR VALUES FROM ('2023-11-01') TO ('2023-12-01'),
            acc_data_p20231201 FOR VALUES FROM ('2023-12-01') TO ('2024-01-01'),
            acc_data_p20240101 FOR VALUES FROM ('2024-01-01') TO ('2024-02-01'),
            acc_data_p20240201 FOR VALUES FROM ('2024-02-01') TO ('2024-03-01'),
            acc_data_p20240301 FOR VALUES FROM ('2024-03-01') TO ('2024-04-01'),
            acc_data_p20240401 FOR VALUES FROM ('2024-04-01') TO ('2024-05-01'),
            acc_data_p20240501 FOR VALUES FROM ('2024-05-01') TO ('2024-06-01'),
            acc_data_default DEFAULT

 */



-- 2) Агрегированные данные
CREATE TABLE acc_aggregate(
    company_id      integer     NOT NULL,
    account_id      varchar(20) NOT NULL,
    period_dt       date        NOT NULL,
    amount          numeric     NOT NULL,
    currency_code   varchar(3)  NOT NULL
) PARTITION BY RANGE (period_dt);
CREATE INDEX ON acc_aggregate(period_dt);
ALTER TABLE acc_aggregate ADD CONSTRAINT pk_acc_aggregate PRIMARY KEY (company_id, account_id, period_dt, currency_code);
COMMENT ON TABLE acc_aggregate IS 'Суммы по счетам';
COMMENT ON COLUMN acc_aggregate.company_id       IS 'Суммы по счетам - орагнизация';
COMMENT ON COLUMN acc_aggregate.account_id       IS 'Суммы по счетам - счёт';
COMMENT ON COLUMN acc_aggregate.period_dt        IS 'Суммы по счетам - период';
COMMENT ON COLUMN acc_aggregate.amount           IS 'Суммы по счетам - сумма';
COMMENT ON COLUMN acc_aggregate.currency_code    IS 'Суммы по счетам - валюта';
SELECT create_distributed_table('acc_aggregate', 'company_id');
SELECT partman.create_parent(
      p_parent_table := 'public.acc_aggregate'
    , p_control      := 'period_dt'
    , p_interval     := '1 month'
);

/*
finance=# SELECT create_distributed_table('acc_aggregate', 'company_id');
 create_distributed_table 
--------------------------
 
(1 row)

finance=# SELECT partman.create_parent(
finance(#       p_parent_table := 'public.acc_aggregate'
finance(#     , p_control      := 'period_dt'
finance(#     , p_interval     := '1 month'
finance(# );
 create_parent 
---------------
 t
(1 row)

finance=# \dt+
                                                        List of relations
 Schema |          Name           |       Type        |  Owner   | Persistence | Access method |    Size    |     Description     
--------+-------------------------+-------------------+----------+-------------+---------------+------------+---------------------
 public | acc_aggregate           | partitioned table | postgres | permanent   |               | 0 bytes    | Суммы по счетам
 public | acc_aggregate_default   | table             | postgres | permanent   | heap          | 8192 bytes | 
 public | acc_aggregate_p20230901 | table             | postgres | permanent   | heap          | 8192 bytes | 
 public | acc_aggregate_p20231001 | table             | postgres | permanent   | heap          | 8192 bytes | 
 public | acc_aggregate_p20231101 | table             | postgres | permanent   | heap          | 8192 bytes | 
 public | acc_aggregate_p20231201 | table             | postgres | permanent   | heap          | 8192 bytes | 
 public | acc_aggregate_p20240101 | table             | postgres | permanent   | heap          | 8192 bytes | 
 public | acc_aggregate_p20240201 | table             | postgres | permanent   | heap          | 8192 bytes | 
 public | acc_aggregate_p20240301 | table             | postgres | permanent   | heap          | 8192 bytes | 
 public | acc_aggregate_p20240401 | table             | postgres | permanent   | heap          | 8192 bytes | 
 public | acc_aggregate_p20240501 | table             | postgres | permanent   | heap          | 8192 bytes | 
 public | acc_data                | partitioned table | postgres | permanent   |               | 0 bytes    | Операции по счетам
 public | acc_data_default        | table             | postgres | permanent   | heap          | 8192 bytes | 
 public | acc_data_p20230901      | table             | postgres | permanent   | heap          | 8192 bytes | 
 public | acc_data_p20231001      | table             | postgres | permanent   | heap          | 8192 bytes | 
 public | acc_data_p20231101      | table             | postgres | permanent   | heap          | 8192 bytes | 
 public | acc_data_p20231201      | table             | postgres | permanent   | heap          | 8192 bytes | 
 public | acc_data_p20240101      | table             | postgres | permanent   | heap          | 8192 bytes | 
 public | acc_data_p20240201      | table             | postgres | permanent   | heap          | 8192 bytes | 
 public | acc_data_p20240301      | table             | postgres | permanent   | heap          | 8192 bytes | 
 public | acc_data_p20240401      | table             | postgres | permanent   | heap          | 8192 bytes | 
 public | acc_data_p20240501      | table             | postgres | permanent   | heap          | 8192 bytes | 
 public | dct_accounts            | table             | postgres | permanent   | heap          | 0 bytes    | План счетов МСФО
 public | dct_companies           | table             | postgres | permanent   | heap          | 8192 bytes | Словарь организаций
(24 rows)

finance=# select * from citus_tables;
       table_name        | citus_table_type | distribution_column | colocation_id | table_size | shard_count | table_owner | access_method 
-------------------------+------------------+---------------------+---------------+------------+-------------+-------------+---------------
 acc_aggregate           | distributed      | company_id          |             3 | 0 bytes    |          32 | postgres    | 
 acc_aggregate_default   | distributed      | company_id          |             3 | 768 kB     |          32 | postgres    | heap
 acc_aggregate_p20230901 | distributed      | company_id          |             3 | 768 kB     |          32 | postgres    | heap
 acc_aggregate_p20231001 | distributed      | company_id          |             3 | 768 kB     |          32 | postgres    | heap
 acc_aggregate_p20231101 | distributed      | company_id          |             3 | 768 kB     |          32 | postgres    | heap
 acc_aggregate_p20231201 | distributed      | company_id          |             3 | 768 kB     |          32 | postgres    | heap
 acc_aggregate_p20240101 | distributed      | company_id          |             3 | 768 kB     |          32 | postgres    | heap
 acc_aggregate_p20240201 | distributed      | company_id          |             3 | 768 kB     |          32 | postgres    | heap
 acc_aggregate_p20240301 | distributed      | company_id          |             3 | 768 kB     |          32 | postgres    | heap
 acc_aggregate_p20240401 | distributed      | company_id          |             3 | 768 kB     |          32 | postgres    | heap
 acc_aggregate_p20240501 | distributed      | company_id          |             3 | 768 kB     |          32 | postgres    | heap
 acc_data                | distributed      | company_id          |             3 | 0 bytes    |          32 | postgres    | 
 acc_data_default        | distributed      | company_id          |             3 | 768 kB     |          32 | postgres    | heap
 acc_data_p20230901      | distributed      | company_id          |             3 | 768 kB     |          32 | postgres    | heap
 acc_data_p20231001      | distributed      | company_id          |             3 | 768 kB     |          32 | postgres    | heap
 acc_data_p20231101      | distributed      | company_id          |             3 | 768 kB     |          32 | postgres    | heap
 acc_data_p20231201      | distributed      | company_id          |             3 | 768 kB     |          32 | postgres    | heap
 acc_data_p20240101      | distributed      | company_id          |             3 | 768 kB     |          32 | postgres    | heap
 acc_data_p20240201      | distributed      | company_id          |             3 | 768 kB     |          32 | postgres    | heap
 acc_data_p20240301      | distributed      | company_id          |             3 | 768 kB     |          32 | postgres    | heap
 acc_data_p20240401      | distributed      | company_id          |             3 | 768 kB     |          32 | postgres    | heap
 acc_data_p20240501      | distributed      | company_id          |             3 | 768 kB     |          32 | postgres    | heap
 dct_accounts            | reference        | <none>              |             2 | 24 kB      |           1 | postgres    | heap
 dct_companies           | reference        | <none>              |             2 | 48 kB      |           1 | postgres    | heap
(24 rows)

finance=# select logicalrelid, count(*) from pg_dist_shard group by logicalrelid order by 1;
      logicalrelid       | count 
-------------------------+-------
 dct_companies           |     1
 dct_accounts            |     1
 acc_data                |    32
 acc_data_p20230901      |    32
 acc_data_p20231001      |    32
 acc_data_p20231101      |    32
 acc_data_p20231201      |    32
 acc_data_p20240101      |    32
 acc_data_p20240201      |    32
 acc_data_p20240301      |    32
 acc_data_p20240401      |    32
 acc_data_p20240501      |    32
 acc_data_default        |    32
 acc_aggregate           |    32
 acc_aggregate_p20230901 |    32
 acc_aggregate_p20231001 |    32
 acc_aggregate_p20231101 |    32
 acc_aggregate_p20231201 |    32
 acc_aggregate_p20240101 |    32
 acc_aggregate_p20240201 |    32
 acc_aggregate_p20240301 |    32
 acc_aggregate_p20240401 |    32
 acc_aggregate_p20240501 |    32
 acc_aggregate_default   |    32
(24 rows)

 */

/*
Ссылочная целостность (FK) в citus поддерживается слабо, в частности:
 - ключи поддерживаются только в рамках инстанса (воркера), отсюда:
 - ссылки из распределенной таблицы на локальную не поддерживаются, т.к. распределенная таблица лежит на воркерах а локальная на координаторе
 - ссылки из распределенной таблицы на другие распределённые поддерживаются только если они со-распределены, тогда если например у нас 32 шарда в каждой из соединяемых таблиц, то будет создано 32 ключа
 - ссылки из распределенной таблицы на справочники поддерживаются, но убивают паралеллизм при запросах к распределенной таблице (citus автоматом переходит в последовательный режим)
подробнее: https://www.youtube.com/watch?v=xReWGcSg7sc
поэтому не будем создавать ключи между таблицами
*/
