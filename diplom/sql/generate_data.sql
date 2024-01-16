-- для начала сгенерируем данные за прошлый год (2023)

INSERT INTO public.acc_data (
    transaction_id,
    transaction_dt,
    company_id,
    company_id_src,
    account_id,
    account_id_src,
    operation_type,
    amount,
    currency_code,
    custom_1,
    custom_2,
    custom_3,
    custom_4,
    custom_5
)
WITH t_grid AS (
    -- пересечение компаний и счетов
    SELECT dc.company_id, da.account_id
    FROM dct_accounts da
    CROSS JOIN dct_companies dc
),
t_days AS (
    -- дни за период
    SELECT date_trunc('day', dd)::date transaction_dt
    FROM generate_series
        ( '2023-01-01'::timestamp 
        , '2023-12-31'::timestamp
        , '1 day'::interval) dd
)
, t_data AS (
    -- случайные суммы
    SELECT
        td.transaction_dt,
        tg.company_id,
        tg.account_id,
        round(random() * 1000000) * 100 AS amount,
        CASE WHEN random() > 0.25 THEN 1 ELSE 0 END AS ok,
        random() AS ar1,
        random() AS ar2,
        random() AS ar3
    FROM t_grid tg, t_days td, generate_series(1,10) gs
)
SELECT
    ROW_NUMBER() OVER() AS transaction_id,
    transaction_dt,
    company_id,
    NULL AS company_id_src,
    account_id,
    NULL AS account_id_src,
    '' AS operation_type,
    amount,
    'RUR' AS currency_code,
    CASE floor(ar1 * 4)
        WHEN 0 THEN 'A'
        WHEN 1 THEN 'B'
        WHEN 2 THEN 'C'
        ELSE null
    END  AS custom_1,
    CASE
        WHEN floor(ar2 * 10) > 5 THEN 'XX'
        WHEN floor(ar2 * 10) > 8 THEN 'ZZ'
        ELSE NULL
    END  AS custom_2,
    CASE WHEN floor(ar3 * 10) > 9 THEN 'RARE' END AS custom_3,
    NULL AS custom_4,
    NULL AS custom_5
FROM t_data
WHERE ok = 1;

-- \timing on
-- INSERT 0 1915304
-- Time: 13908.837 ms (00:13.909)

/*
-- после вставки:
-- 1) автоматически не создались партиции до 2023-09-01, большинство данных упало в acc_data_default

 finance=# SELECT logicalrelid AS name,
       pg_size_pretty(citus_table_size(logicalrelid)) AS size
  FROM pg_dist_partition WHERE logicalrelid::text like 'acc_data%';
        name        |  size   
--------------------+---------
 acc_data           | 0 bytes
 acc_data_p20230901 | 12 MB
 acc_data_p20231001 | 12 MB
 acc_data_p20231101 | 12 MB
 acc_data_p20231201 | 12 MB
 acc_data_p20240101 | 256 kB
 acc_data_p20240201 | 256 kB
 acc_data_p20240301 | 256 kB
 acc_data_p20240401 | 256 kB
 acc_data_p20240501 | 256 kB
 acc_data_default   | 96 MB
(11 rows)

-- 2) данные по организациям разлеглись неравномерно - на 9 шардов вместо 10 (по умолчанию создалось 32 шарда, из них 23 остались пусты),
-- т.е. в один из шардов попали две компании, хотя есть свободные - видимо это особенности алгоритма хеширования...

finance=# SELECT * FROM citus_shards where table_name::text like 'acc_data_def%' and shard_size > 25000;
    table_name    | shardid |       shard_name        | citus_table_type | colocation_id |    nodename    | nodeport | shard_size 
------------------+---------+-------------------------+------------------+---------------+----------------+----------+------------
 acc_data_default |  102331 | acc_data_default_102331 | distributed      |             3 | citus-worker-1 |     5432 |   16326656
 acc_data_default |  102332 | acc_data_default_102332 | distributed      |             3 | citus-worker-2 |     5432 |   16334848
 acc_data_default |  102335 | acc_data_default_102335 | distributed      |             3 | citus-worker-1 |     5432 |   16359424
 acc_data_default |  102337 | acc_data_default_102337 | distributed      |             3 | citus-worker-1 |     5432 |   16343040
 acc_data_default |  102339 | acc_data_default_102339 | distributed      |             3 | citus-worker-1 |     5432 |   36077568
 acc_data_default |  102346 | acc_data_default_102346 | distributed      |             3 | citus-worker-2 |     5432 |   16351232
 acc_data_default |  102351 | acc_data_default_102351 | distributed      |             3 | citus-worker-1 |     5432 |   16343040
 acc_data_default |  102355 | acc_data_default_102355 | distributed      |             3 | citus-worker-1 |     5432 |   16334848
 acc_data_default |  102359 | acc_data_default_102359 | distributed      |             3 | citus-worker-1 |     5432 |   16334848
(9 rows)
 */

/*
-- решаем первую проблему запуском функции партмана, которая создаст недостающие партиции и перенесет данные из default
finance=# call partman.partition_data_proc('public.acc_data');
NOTICE:  Loop: 1, Rows moved: 162897
NOTICE:  Loop: 2, Rows moved: 146892
NOTICE:  Loop: 3, Rows moved: 162773
NOTICE:  Loop: 4, Rows moved: 157443
NOTICE:  Loop: 5, Rows moved: 162969
NOTICE:  Loop: 6, Rows moved: 157308
NOTICE:  Loop: 7, Rows moved: 162634
NOTICE:  Loop: 8, Rows moved: 162567
NOTICE:  Total rows moved: 1275483
NOTICE:  Ensure to VACUUM ANALYZE the parent (and source table if used) after partitioning data
CALL
Time: 28139.298 ms (00:28.139)

finance=# SELECT partman.show_partitions('public.acc_data');
       show_partitions       
-----------------------------
 (public,acc_data_p20230101)
 (public,acc_data_p20230201)
 (public,acc_data_p20230301)
 (public,acc_data_p20230401)
 (public,acc_data_p20230501)
 (public,acc_data_p20230601)
 (public,acc_data_p20230701)
 (public,acc_data_p20230801)
 (public,acc_data_p20230901)
 (public,acc_data_p20231001)
 (public,acc_data_p20231101)
 (public,acc_data_p20231201)
 (public,acc_data_p20240101)
 (public,acc_data_p20240201)
 (public,acc_data_p20240301)
 (public,acc_data_p20240401)
 (public,acc_data_p20240501)
(17 rows)

Time: 4.631 ms

-- теперь запустим вакуум и аналайз по очереди - https://docs.citusdata.com/en/stable/admin_guide/table_management.html#vacuuming-distributed-tables
finance=# vacuum acc_data;
VACUUM
Time: 143.565 ms
finance=# analyze acc_data;
ANALYZE
Time: 1495.606 ms (00:01.496)

-- данные разлеглись как надо

finance=# SELECT logicalrelid AS name,
finance-#        pg_size_pretty(citus_table_size(logicalrelid)) AS size
finance-#   FROM pg_dist_partition WHERE logicalrelid::text like 'acc_data%';
        name        |  size   
--------------------+---------
 acc_data           | 0 bytes
 acc_data_p20230901 | 12 MB
 acc_data_p20231001 | 12 MB
 acc_data_p20231101 | 12 MB
 acc_data_p20231201 | 12 MB
 acc_data_p20240101 | 256 kB
 acc_data_p20240201 | 256 kB
 acc_data_p20240301 | 256 kB
 acc_data_p20240401 | 256 kB
 acc_data_p20240501 | 256 kB
 acc_data_default   | 400 kB
 acc_data_p20230101 | 12 MB
 acc_data_p20230201 | 11 MB
 acc_data_p20230301 | 12 MB
 acc_data_p20230401 | 12 MB
 acc_data_p20230501 | 12 MB
 acc_data_p20230601 | 12 MB
 acc_data_p20230701 | 12 MB
 acc_data_p20230801 | 12 MB
(19 rows)

Time: 73.150 ms

 */

-- теперь привяжем данные головной организации (company_id = 1) к выделенному шарду, посмотрим на каком воркере он расположен и перенесём остальные шарды на другой
-- https://docs.citusdata.com/en/stable/admin_guide/cluster_management.html#tenant-isolation
SELECT isolate_tenant_to_new_shard('acc_data', 1); -- 

-- finance=# SELECT isolate_tenant_to_new_shard('acc_data', 1);
-- ERROR:  cannot isolate tenant because "acc_data" has colocated tables
-- HINT:  Use CASCADE option to isolate tenants for the colocated tables too. Example usage: isolate_tenant_to_new_shard('acc_data', '1', 'CASCADE')

-- судя по всему есть colocated таблицы, пробуем каскадную изоляцию

SELECT isolate_tenant_to_new_shard('acc_data', '1', 'CASCADE');

-- finance=# SELECT isolate_tenant_to_new_shard('acc_data', '1', 'CASCADE');
-- ERROR:  connection to the remote node localhost:5432 failed with the following error: fe_sendauth: no password supplied
-- решаем добавлением строки для localhost в pgpass на всех нодах, однако появляется другая ошибка:

-- finance=# SELECT isolate_tenant_to_new_shard('acc_data', '1', 'CASCADE');
-- WARNING:  logical decoding requires wal_level >= logical
-- ERROR:  ERROR:  logical decoding requires wal_level >= logical
-- CONTEXT:  while executing command on citus-worker-2:5432

-- придется включать wal_level = logical в конфиге на всех нодах
-- теперь выполнилось успешно:

/*
finance=# show wal_level;
 wal_level 
-----------
 logical
(1 row)

finance=# SELECT isolate_tenant_to_new_shard('acc_data', '1', 'CASCADE');
 isolate_tenant_to_new_shard 
-----------------------------
                      103062
(1 row)

finance=# SELECT get_shard_id_for_distribution_column('acc_data', 1);
 get_shard_id_for_distribution_column 
--------------------------------------
                               103062
(1 row)

*/

-- в таблицах стало по 34 шарда (было 32)
/*
finance=# select table_name, count(*) as shards_cnt from citus_shards where table_name::text like 'acc_data%' group by table_name order by 1;
     table_name     | shards_cnt 
--------------------+------------
 acc_data           |         34
 acc_data_p20230901 |         34
 acc_data_p20231001 |         34
 acc_data_p20231101 |         34
 acc_data_p20231201 |         34
 acc_data_p20240101 |         34
 acc_data_p20240201 |         34
 acc_data_p20240301 |         34
 acc_data_p20240401 |         34
 acc_data_p20240501 |         34
 acc_data_default   |         34
 acc_data_p20230101 |         34
 acc_data_p20230201 |         34
 acc_data_p20230301 |         34
 acc_data_p20230401 |         34
 acc_data_p20230501 |         34
 acc_data_p20230601 |         34
 acc_data_p20230701 |         34
 acc_data_p20230801 |         34
(19 rows)

-- видно что шард 103062 состоит из одного значения (один шард разбили на три части, итого +2 шарда)

finance=# select * from pg_dist_shard where logicalrelid = 'acc_data'::regclass;
 logicalrelid | shardid | shardstorage | shardminvalue | shardmaxvalue 
--------------+---------+--------------+---------------+---------------
 acc_data     |  102011 | t            | -2147483648   | -2013265921
 acc_data     |  102013 | t            | -1879048192   | -1744830465
 ...
 acc_data     |  102042 | t            | 2013265920    | 2147483647
 acc_data     |  103061 | t            | -2013265920   | -1905060027
 acc_data     |  103062 | t            | -1905060026   | -1905060026
 acc_data     |  103063 | t            | -1905060025   | -1879048193
(34 rows)

-- аналогично во всех партициях (в 2023-01-01 - шард 103128 и т.д.)

finance=# select * from pg_dist_shard where logicalrelid = 'acc_data_p20230101'::regclass;
    logicalrelid    | shardid | shardstorage | shardminvalue | shardmaxvalue 
--------------------+---------+--------------+---------------+---------------
 acc_data_p20230101 |  102715 | t            | -2147483648   | -2013265921
 acc_data_p20230101 |  102717 | t            | -1879048192   | -1744830465
 ...
 acc_data_p20230101 |  102746 | t            | 2013265920    | 2147483647
 acc_data_p20230101 |  103127 | t            | -2013265920   | -1905060027
 acc_data_p20230101 |  103128 | t            | -1905060026   | -1905060026
 acc_data_p20230101 |  103129 | t            | -1905060025   | -1879048193
(34 rows)

-- посмотрим план запроса на выборку по company_id = 1: explain_main_company_select.txt 
*/
 
-- посмотрим размеры шардов с выделенным tenant
SELECT pr.partition_tablename, pr.shardid, nd.nodename, cs.shard_size
FROM (
  SELECT partition_tablename, get_shard_id_for_distribution_column(partition_tablename,1) AS shardid
  FROM partman.show_partitions('public.acc_data')
) pr
JOIN pg_dist_placement  pl ON pl.shardid = pr.shardid
JOIN pg_dist_node       nd ON pl.groupid = nd.groupid AND nd.noderole = 'primary'
JOIN citus_shards       cs ON cs.shardid = pr.shardid
ORDER BY 1;
   
/*
finance=# SELECT pr.partition_tablename, pr.shardid, nd.nodename, cs.shard_size
FROM (
  SELECT partition_tablename, get_shard_id_for_distribution_column(partition_tablename,1) AS shardid
  FROM partman.show_partitions('public.acc_data')
) pr
JOIN pg_dist_placement  pl ON pl.shardid = pr.shardid
JOIN pg_dist_node       nd ON pl.groupid = nd.groupid AND nd.noderole = 'primary'
JOIN citus_shards       cs ON cs.shardid = pr.shardid
ORDER BY 1;
 partition_tablename | shardid |    nodename    | shard_size 
---------------------+---------+----------------+------------
 acc_data_p20230101  |  103128 | citus-worker-2 |    2088960
 acc_data_p20230201  |  103131 | citus-worker-2 |    1892352
 acc_data_p20230301  |  103134 | citus-worker-2 |    2105344
 acc_data_p20230401  |  103137 | citus-worker-2 |    2023424
 acc_data_p20230501  |  103140 | citus-worker-2 |    2080768
 acc_data_p20230601  |  103143 | citus-worker-2 |    2023424
 acc_data_p20230701  |  103146 | citus-worker-2 |    2097152
 acc_data_p20230801  |  103149 | citus-worker-2 |    2080768
 acc_data_p20230901  |  103065 | citus-worker-2 |    2023424
 acc_data_p20231001  |  103068 | citus-worker-2 |    2072576
 acc_data_p20231101  |  103071 | citus-worker-2 |    2023424
 acc_data_p20231201  |  103074 | citus-worker-2 |    2088960
 acc_data_p20240101  |  103077 | citus-worker-2 |      24576
 acc_data_p20240201  |  103080 | citus-worker-2 |      24576
 acc_data_p20240301  |  103083 | citus-worker-2 |      24576
 acc_data_p20240401  |  103086 | citus-worker-2 |      24576
 acc_data_p20240501  |  103089 | citus-worker-2 |      24576
(17 rows)
 */

-- т.к. выделенный шард расположен на втором воркере, то перенесём остальные шарды которые лежат на втором воркере на первый, таковых 17 штук

/*
finance=# select * from citus_shards where table_name::text like 'acc_data' and shardid != 103062 and nodename != 'citus-worker-1';
 table_name | shardid |   shard_name    | citus_table_type | colocation_id |    nodename    | nodeport | shard_size 
------------+---------+-----------------+------------------+---------------+----------------+----------+------------
 acc_data   |  102014 | acc_data_102014 | distributed      |             3 | citus-worker-2 |     5432 |          0
 acc_data   |  102016 | acc_data_102016 | distributed      |             3 | citus-worker-2 |     5432 |          0
 acc_data   |  102018 | acc_data_102018 | distributed      |             3 | citus-worker-2 |     5432 |          0
 acc_data   |  102020 | acc_data_102020 | distributed      |             3 | citus-worker-2 |     5432 |          0
 acc_data   |  102022 | acc_data_102022 | distributed      |             3 | citus-worker-2 |     5432 |          0
 acc_data   |  102024 | acc_data_102024 | distributed      |             3 | citus-worker-2 |     5432 |          0
 acc_data   |  102026 | acc_data_102026 | distributed      |             3 | citus-worker-2 |     5432 |          0
 acc_data   |  102028 | acc_data_102028 | distributed      |             3 | citus-worker-2 |     5432 |          0
 acc_data   |  102030 | acc_data_102030 | distributed      |             3 | citus-worker-2 |     5432 |          0
 acc_data   |  102032 | acc_data_102032 | distributed      |             3 | citus-worker-2 |     5432 |          0
 acc_data   |  102034 | acc_data_102034 | distributed      |             3 | citus-worker-2 |     5432 |          0
 acc_data   |  102036 | acc_data_102036 | distributed      |             3 | citus-worker-2 |     5432 |          0
 acc_data   |  102038 | acc_data_102038 | distributed      |             3 | citus-worker-2 |     5432 |          0
 acc_data   |  102040 | acc_data_102040 | distributed      |             3 | citus-worker-2 |     5432 |          0
 acc_data   |  102042 | acc_data_102042 | distributed      |             3 | citus-worker-2 |     5432 |          0
 acc_data   |  103061 | acc_data_103061 | distributed      |             3 | citus-worker-2 |     5432 |          0
 acc_data   |  103063 | acc_data_103063 | distributed      |             3 | citus-worker-2 |     5432 |          0
(17 rows)
*/

SELECT citus_move_shard_placement(shardid, 'citus-worker-2', 5432, 'citus-worker-1', 5432) FROM citus_shards where table_name::text like 'acc_data' and shardid != 103062 and nodename != 'citus-worker-1';

-- ERROR:  moving multiple shard placements via logical replication in the same transaction is currently not supported
-- HINT:  If you wish to move multiple shard placements in a single transaction set the shard_transfer_mode to 'block_writes'.
-- Time: 3249.100 ms (00:03.249)

-- попробуем замувить один шард

/*
finance=# SELECT citus_move_shard_placement(102014, 'citus-worker-2', 5432, 'citus-worker-1', 5432);
 citus_move_shard_placement 
----------------------------
 
(1 row)

Time: 3036.612 ms (00:03.037)
*/

-- их осталось 16, при желании можно написать процедуру переноса (TODO)

/*
finance=# select count(*) from citus_shards where table_name::text like 'acc_data' and shardid != 103062 and nodename != 'citus-worker-1';
 count 
-------
    16
(1 row)
*/

-- добавим данных по головной организации за текущий год (чтобы проверить создание новых партиций в будущем и убедиться что все они попали на выделенный воркер)

INSERT INTO public.acc_data (
    transaction_id,
    transaction_dt,
    company_id,
    company_id_src,
    account_id,
    account_id_src,
    operation_type,
    amount,
    currency_code,
    custom_1,
    custom_2,
    custom_3,
    custom_4,
    custom_5
)
WITH t_grid AS (
    -- по головной компании
    SELECT 1 AS company_id, da.account_id
    FROM dct_accounts da
),
t_days AS (
    -- дни за период
    SELECT date_trunc('day', dd)::date transaction_dt
    FROM generate_series
        ( '2024-01-01'::timestamp 
        , '2024-12-31'::timestamp
        , '1 day'::interval) dd
)
, t_data AS (
    SELECT
        td.transaction_dt,
        tg.company_id,
        tg.account_id,
        round(random() * 1000000) * 100 AS amount,
        CASE WHEN random() > 0.25 THEN 1 ELSE 0 END AS ok,
        random() AS ar1,
        random() AS ar2,
        random() AS ar3
    FROM t_grid tg, t_days td, generate_series(1,10) gs
)
SELECT
    ROW_NUMBER() OVER() + (SELECT max(transaction_id) FROM acc_data) AS transaction_id,
    transaction_dt,
    company_id,
    NULL AS company_id_src,
    account_id,
    NULL AS account_id_src,
    '' AS operation_type,
    amount,
    'RUR' AS currency_code,
    CASE floor(ar1 * 4)
        WHEN 0 THEN 'A'
        WHEN 1 THEN 'B'
        WHEN 2 THEN 'C'
        ELSE null
    END  AS custom_1,
    CASE
        WHEN floor(ar2 * 10) > 5 THEN 'XX'
        WHEN floor(ar2 * 10) > 8 THEN 'ZZ'
        ELSE NULL
    END  AS custom_2,
    CASE WHEN floor(ar3 * 10) > 9 THEN 'RARE' END AS custom_3,
    NULL AS custom_4,
    NULL AS custom_5
FROM t_data
WHERE ok = 1;

-- INSERT 0 192508
-- Time: 1277.822 ms (00:01.278)

-- новых партиций не появилось, опять всё (после мая 2024) упало в default

/*
finance=# select * from citus_shards where table_name::text like 'acc_data%' order by shard_size desc;
     table_name     | shardid |        shard_name         | citus_table_type | colocation_id |    nodename    | nodeport | shard_size 
--------------------+---------+---------------------------+------------------+---------------+----------------+----------+------------
 acc_data_default   |  102339 | acc_data_default_102339   | distributed      |             3 | citus-worker-1 |     5432 |   16580608
 acc_data_default   |  103092 | acc_data_default_103092   | distributed      |             3 | citus-worker-2 |     5432 |   14565376
 acc_data_default   |  102335 | acc_data_default_102335   | distributed      |             3 | citus-worker-1 |     5432 |    6299648
 acc_data_default   |  102346 | acc_data_default_102346   | distributed      |             3 | citus-worker-2 |     5432 |    6291456
 acc_data_default   |  102351 | acc_data_default_102351   | distributed      |             3 | citus-worker-1 |     5432 |    6283264
 acc_data_default   |  102337 | acc_data_default_102337   | distributed      |             3 | citus-worker-1 |     5432 |    6283264
 acc_data_default   |  102355 | acc_data_default_102355   | distributed      |             3 | citus-worker-1 |     5432 |    6275072
 acc_data_default   |  102359 | acc_data_default_102359   | distributed      |             3 | citus-worker-1 |     5432 |    6275072
 acc_data_default   |  102331 | acc_data_default_102331   | distributed      |             3 | citus-worker-1 |     5432 |    6266880
 acc_data_p20230501 |  102851 | acc_data_p20230501_102851 | distributed      |             3 | citus-worker-1 |     5432 |    4669440

*/

SELECT pr.partition_tablename, pr.shardid, nd.nodename, cs.shard_size
FROM (
  SELECT partition_tablename, get_shard_id_for_distribution_column(partition_tablename,1) AS shardid
  FROM partman.show_partitions('public.acc_data')
  UNION
  SELECT 'acc_data_default' AS partition_tablename, get_shard_id_for_distribution_column('acc_data_default',1) AS shardid
) pr
JOIN pg_dist_placement  pl ON pl.shardid = pr.shardid
JOIN pg_dist_node       nd ON pl.groupid = nd.groupid AND nd.noderole = 'primary'
JOIN citus_shards       cs ON cs.shardid = pr.shardid
ORDER BY 1;

/*
 partition_tablename | shardid |    nodename    | shard_size 
---------------------+---------+----------------+------------
 acc_data_default    |  103092 | citus-worker-2 |   14565376
 acc_data_p20230101  |  103128 | citus-worker-2 |    2088960
 acc_data_p20230201  |  103131 | citus-worker-2 |    1892352
 acc_data_p20230301  |  103134 | citus-worker-2 |    2105344
 acc_data_p20230401  |  103137 | citus-worker-2 |    2023424
 acc_data_p20230501  |  103140 | citus-worker-2 |    2080768
 acc_data_p20230601  |  103143 | citus-worker-2 |    2023424
 acc_data_p20230701  |  103146 | citus-worker-2 |    2097152
 acc_data_p20230801  |  103149 | citus-worker-2 |    2080768
 acc_data_p20230901  |  103065 | citus-worker-2 |    2023424
 acc_data_p20231001  |  103068 | citus-worker-2 |    2072576
 acc_data_p20231101  |  103071 | citus-worker-2 |    2023424
 acc_data_p20231201  |  103074 | citus-worker-2 |    2088960
 acc_data_p20240101  |  103077 | citus-worker-2 |    2113536
 acc_data_p20240201  |  103080 | citus-worker-2 |    1982464
 acc_data_p20240301  |  103083 | citus-worker-2 |    2105344
 acc_data_p20240401  |  103086 | citus-worker-2 |    2039808
 acc_data_p20240501  |  103089 | citus-worker-2 |    2170880
(18 rows)

-- сделаем ещё раз создание партиций с помощью партмана
finance=# call partman.partition_data_proc('public.acc_data');
NOTICE:  Loop: 1, Rows moved: 15754
NOTICE:  Loop: 2, Rows moved: 16333
NOTICE:  Loop: 3, Rows moved: 16369
NOTICE:  Loop: 4, Rows moved: 15724
NOTICE:  Loop: 5, Rows moved: 16381
NOTICE:  Loop: 6, Rows moved: 15770
NOTICE:  Loop: 7, Rows moved: 16210
NOTICE:  Total rows moved: 112541
NOTICE:  Ensure to VACUUM ANALYZE the parent (and source table if used) after partitioning data
CALL
Time: 12139.940 ms (00:12.140)
finance=# vacuum acc_data;
VACUUM
Time: 153.009 ms
finance=# analyze acc_data;
ANALYZE
Time: 1550.566 ms (00:01.551)

-- новое распределение

 partition_tablename | shardid |    nodename    | shard_size 
---------------------+---------+----------------+------------
 acc_data_default    |  103092 | citus-worker-2 |    5554176
 acc_data_p20230101  |  103128 | citus-worker-2 |    2088960
 acc_data_p20230201  |  103131 | citus-worker-2 |    1892352
 acc_data_p20230301  |  103134 | citus-worker-2 |    2105344
 acc_data_p20230401  |  103137 | citus-worker-2 |    2023424
 acc_data_p20230501  |  103140 | citus-worker-2 |    2080768
 acc_data_p20230601  |  103143 | citus-worker-2 |    2023424
 acc_data_p20230701  |  103146 | citus-worker-2 |    2097152
 acc_data_p20230801  |  103149 | citus-worker-2 |    2080768
 acc_data_p20230901  |  103065 | citus-worker-2 |    2023424
 acc_data_p20231001  |  103068 | citus-worker-2 |    2072576
 acc_data_p20231101  |  103071 | citus-worker-2 |    2023424
 acc_data_p20231201  |  103074 | citus-worker-2 |    2088960
 acc_data_p20240101  |  103077 | citus-worker-2 |    2113536
 acc_data_p20240201  |  103080 | citus-worker-2 |    1982464
 acc_data_p20240301  |  103083 | citus-worker-2 |    2105344
 acc_data_p20240401  |  103086 | citus-worker-2 |    2039808
 acc_data_p20240501  |  103089 | citus-worker-2 |    2097152
 acc_data_p20240601  |  103153 | citus-worker-2 |    2039808
 acc_data_p20240701  |  103187 | citus-worker-2 |    2113536
 acc_data_p20240801  |  103221 | citus-worker-2 |    2113536
 acc_data_p20240901  |  103255 | citus-worker-2 |    2039808
 acc_data_p20241001  |  103289 | citus-worker-2 |    2129920
 acc_data_p20241101  |  103323 | citus-worker-2 |    2031616
 acc_data_p20241201  |  103357 | citus-worker-2 |    2105344
(25 rows)

Time: 47.107 ms
*/