-- =========== создание объектов в кластере холодного хранения
-- сервер и внешняя таблица
CREATE SERVER citus_fin
FOREIGN DATA WRAPPER postgres_fdw
OPTIONS (host '10.0.0.15', port '5432', dbname 'finance');

CREATE USER MAPPING FOR developer
SERVER citus_fin
OPTIONS (user 'postgres', password 'AoU9k=[W++');

CREATE FOREIGN TABLE citus_acc_data(
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
)
SERVER citus_fin
OPTIONS (schema_name 'public', table_name 'acc_data');

-- схема с архивными данными
create schema archdata;
SET search_path TO archdata;
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

-- подключение к партману
-- здесь почему-то у функции create_parent есть обязательный 3-й параметр type, хотя по документации партмана он не обязателен
-- вероятно в облаке не последняя версия расширения pg_partman
-- при попытке задать соаглсно доке единственный поддерживаемый вариант type = range ругается
-- ERROR:  range is not a valid partitioning type for pg_partman
-- как выяснилось, при PARTITION BY RANGE нужно указывать его равным native
SELECT create_parent('archdata.acc_data', 'transaction_dt', 'native', '1 month');

/*
finance=> SELECT create_parent('archdata.acc_data', 'transaction_dt', 'native', '1 month');
 create_parent 
---------------
 t
(1 row)
*/