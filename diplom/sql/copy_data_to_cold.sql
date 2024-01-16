-- loading all data before specified month from citus
-- TODO: check if data was copied once before
insert into archdata.acc_data(
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
select
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
from   citus_acc_data
where  transaction_dt <  date_trunc('month', now()) - (:'m' || ' month')::interval;

-- create partitions
call partition_data_proc('archdata.acc_data');

-- check copied data for one last month
select min(transaction_dt) mindt, max(transaction_dt) maxdt, count(*) cnt
from archdata.acc_data
where  transaction_dt >= date_trunc('month', now()) - ((:'m' + 1) || ' month')::interval
and    transaction_dt <  date_trunc('month', now()) - (:'m' || ' month')::interval;