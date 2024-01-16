#!/bin/bash
# moving partition for specified period to cold storage

# cold storage connection string (password must be stored in .pgpass)
conn_str="host=c-c9qjdcidpvm091khmh9b.rw.mdb.yandexcloud.net port=6432 sslmode=disable dbname=finance user=developer target_session_attrs=read-write"

# sql for loading data (use pre created postgres_fdw objects - server, tables)
sql_file="copy_data_to_cold.sql"

# retention months back from current date
months="$1"
if [ -z "$1" ]
  then
    months="24"
fi

# connecting to cold storage and copying all data older than $months
psql "$conn_str" -w -f "$sql_file" -v m="$months"

# connecting to main database (local) and removing partitions which data was copied to cold (with partman)
psql -d finance << EOF
-- set retention
update partman.part_config set
    retention = '$months month', 
    retention_keep_index = 'f', -- do not save indexes or partitions
    retention_keep_table = 'f'
where parent_table = 'public.acc_data';

-- clearing
select partman.run_maintenance('public.acc_data');
EOF
