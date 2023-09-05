# Добавление диска к VM в Yandex Cloud

1. добавление через UI Yandex
- создаём диск hdd-dop, размер 20Gb
- присоединяем к виртуалке как disc2

2. проверка диска и подключение

```
> ssh anton@158.160.74.200
anton@otus-db-pg-vm-1:~$ lsblk
NAME   MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
loop0    7:0    0  63.3M  1 loop /snap/core20/1822
loop1    7:1    0 111.9M  1 loop /snap/lxd/24322
loop2    7:2    0  49.8M  1 loop /snap/snapd/18357
vda    252:0    0    40G  0 disk 
├─vda1 252:1    0     1M  0 part 
└─vda2 252:2    0    40G  0 part /
vdb    252:16   0    20G  0 disk 

anton@otus-db-pg-vm-1:~$ sudo parted /dev/vdb mklabel gpt
Information: You may need to update /etc/fstab.

anton@otus-db-pg-vm-1:~$ sudo parted -a opt /dev/vdb mkpart primary ext4 0% 100%
Information: You may need to update /etc/fstab.

anton@otus-db-pg-vm-1:~$ sudo lsblk
NAME   MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
loop0    7:0    0  63.3M  1 loop /snap/core20/1822
loop1    7:1    0 111.9M  1 loop /snap/lxd/24322
loop2    7:2    0  49.8M  1 loop /snap/snapd/18357
vda    252:0    0    40G  0 disk 
├─vda1 252:1    0     1M  0 part 
└─vda2 252:2    0    40G  0 part /
vdb    252:16   0    20G  0 disk 
└─vdb1 252:17   0    20G  0 part 

anton@otus-db-pg-vm-1:~$ sudo mkfs.ext4 -L newpgdrive /dev/vdb1
mke2fs 1.46.5 (30-Dec-2021)
Creating filesystem with 5242368 4k blocks and 1310720 inodes
Filesystem UUID: 5cd9f137-450b-49b4-99a7-0a358dd4e721
Superblock backups stored on blocks: 
	32768, 98304, 163840, 229376, 294912, 819200, 884736, 1605632, 2654208, 
	4096000

Allocating group tables: done                            
Writing inode tables: done                            
Creating journal (32768 blocks): done
Writing superblocks and filesystem accounting information: done 

anton@otus-db-pg-vm-1:~$ sudo lsblk --fs
NAME   FSTYPE   FSVER LABEL      UUID                                 FSAVAIL FSUSE% MOUNTPOINTS
loop0  squashfs 4.0                                                         0   100% /snap/core20/1822
loop1  squashfs 4.0                                                         0   100% /snap/lxd/24322
loop2  squashfs 4.0                                                         0   100% /snap/snapd/18357
vda                                                                                  
├─vda1                                                                               
└─vda2 ext4     1.0              ed465c6e-049a-41c6-8e0b-c8da348a3577   33.3G    11% /
vdb                                                                                  
└─vdb1 ext4     1.0   newpgdrive 5cd9f137-450b-49b4-99a7-0a358dd4e721                

```

- создаем каталог sudo mkdir -p /mnt/pgdata
- добавляем в /etc/fstab строку: `LABEL=newpgdrive /mnt/pgdata ext4 defaults 0 2`

```
anton@otus-db-pg-vm-1:~$ sudo mount -a
anton@otus-db-pg-vm-1:~$ df -lh
Filesystem      Size  Used Avail Use% Mounted on
tmpfs           392M  1.1M  391M   1% /run
/dev/vda2        40G  4.4G   34G  12% /
tmpfs           2.0G     0  2.0G   0% /dev/shm
tmpfs           5.0M     0  5.0M   0% /run/lock
tmpfs           392M  4.0K  392M   1% /run/user/1000
/dev/vdb1        20G   24K   19G   1% /mnt/pgdata
```


# Наполнение БД

```
anton@otus-db-pg-vm-1:~$ sudo su - postgres
postgres@otus-db-pg-vm-1:~$ psql
psql (15.4 (Ubuntu 15.4-1.pgdg22.04+1))
Type "help" for help.

postgres=# \c postgres
You are now connected to database "postgres" as user "postgres".
postgres=# create table test as select gen_random_uuid() as c1 from generate_series(1,1000);
SELECT 1000
postgres=# vacuum analyze test;
VACUUM
postgres=# table test;
postgres=# select * from pg_stat_user_tables where relname = 'test' \gx
-[ RECORD 1 ]-------+------------------------------
relid               | 16395
schemaname          | public
relname             | test
seq_scan            | 1
seq_tup_read        | 1000
idx_scan            | 
idx_tup_fetch       | 
n_tup_ins           | 1000
n_tup_upd           | 0
n_tup_del           | 0
n_tup_hot_upd       | 0
n_live_tup          | 1000
n_dead_tup          | 0
n_mod_since_analyze | 0
n_ins_since_vacuum  | 0
last_vacuum         | 2023-09-05 11:30:05.887296+00
last_autovacuum     | 
last_analyze        | 2023-09-05 11:30:06.473409+00
last_autoanalyze    | 
vacuum_count        | 1
autovacuum_count    | 0
analyze_count       | 1
autoanalyze_count   | 0
```

# Перенос данных

- Остановка кластера
`anton@otus-db-pg-vm-1:~$ sudo pg_ctlcluster 15 main stop`

- Создание каталога на новом диске
```
root@otus-db-pg-vm-1:/mnt/pgdata# chown postgres:postgres postgresql/
root@otus-db-pg-vm-1:/mnt/pgdata# ls -la
total 28
drwxr-xr-x 4 root     root      4096 Sep  5 11:53 .
drwxr-xr-x 3 root     root      4096 Sep  5 11:47 ..
drwx------ 2 root     root     16384 Sep  5 11:46 lost+found
drwxr-xr-x 2 postgres postgres  4096 Sep  5 11:53 postgresql
```

- Переносим данные с помощью mc под пользователем постгрес (sudo -u postgres mc). В итоге:
```
postgres@otus-db-pg-vm-1:/mnt/pgdata/postgresql$ ls -la
total 44
drwxr-xr-x 6 postgres postgres 4096 Sep  5 11:54 .
drwxr-xr-x 4 root     root     4096 Sep  5 11:53 ..
drwxr-xr-x 3 postgres postgres 4096 Sep  1 10:59 15
-rw------- 1 postgres postgres  237 Sep  5 11:36 .bash_history
drwx------ 3 postgres postgres 4096 Sep  1 11:12 .cache
drwx------ 3 postgres postgres 4096 Sep  1 11:12 .config
-rw------- 1 postgres postgres   20 Sep  5 11:31 .lesshst
drwx------ 3 postgres postgres 4096 Sep  1 11:12 .local
-rw-rw-r-- 1 postgres postgres   25 Sep  5 11:28 postgres
-rw------- 1 postgres postgres  216 Sep  5 11:36 .psql_history
-rw-rw-r-- 1 postgres postgres   72 Sep  1 11:13 .selected_editor
```

- Пытаемся стартовать кластер
```
anton@otus-db-pg-vm-1:/$ sudo pg_ctlcluster 15 main start
Error: /var/lib/postgresql/15/main is not accessible or does not exist
```

# Перенастройка кластера на новое местоположение

- выставляем новый путь в postgresql.conf - `data_directory = '/mnt/pgdata/postgresql/15/main'`
- стартуем, всё успешно

```
anton@otus-db-pg-vm-1:/$ sudo pg_ctlcluster 15 main start
anton@otus-db-pg-vm-1:/$ sudo pg_ctlcluster 15 main status
pg_ctl: server is running (PID: 2308)
/usr/lib/postgresql/15/bin/postgres "-D" "/mnt/pgdata/postgresql/15/main" "-c" "config_file=/etc/postgresql/15/main/postgresql.conf"
```

- проверяем данные

```
anton@otus-db-pg-vm-1:/$ sudo -u postgres psql
psql (15.4 (Ubuntu 15.4-1.pgdg22.04+1))
Type "help" for help.

postgres=# \c postgres
You are now connected to database "postgres" as user "postgres".
postgres=# select * from test limit 5;
                  c1                  
--------------------------------------
 ddea3c3a-3d13-4e80-ba02-c553fd60b419
 d9297170-f511-49c9-a4e7-ae3d0b3b08e0
 a9b74929-6836-4ca7-bd33-9fa70beb0d13
 eab8ea45-9b97-44ed-8827-10df68c05719
 ba7c12e0-febd-46c0-96dc-a984710d8daf
(5 rows)
```

# Перекидваем диск на вторую VM

- Остановка кластера на первой машине
`anton@otus-db-pg-vm-1:/$ sudo pg_ctlcluster 15 main stop`

- Выключение первой машины
- Создание второй машины в кластере - otus-db-pg-vm-2
- Подключение диска hdd-dop ко второй машине через UI Yandex Cloud (отключение от первой, подключение ко второй)

```
anton@otus-db-pg-vm-2:~$ lsblk --fs
NAME   FSTYPE   FSVER LABEL      UUID                                 FSAVAIL FSUSE% MOUNTPOINTS
loop0  squashfs 4.0                                                         0   100% /snap/core20/1822
loop1  squashfs 4.0                                                         0   100% /snap/lxd/24322
loop2  squashfs 4.0                                                         0   100% /snap/snapd/18357
loop3                                                                       0   100% /snap/snapd/20092
vda                                                                                  
├─vda1                                                                               
└─vda2 ext4     1.0              ed465c6e-049a-41c6-8e0b-c8da348a3577   14.4G    22% /
vdb                                                                                  
└─vdb1 ext4     1.0   newpgdrive 5cd9f137-450b-49b4-99a7-0a358dd4e721
```

- Установка Postgres на второй машине (через приложенный к курсу postgresql.sh)
```
anton@otus-db-pg-vm-2:~$ sudo su - postgres
postgres@otus-db-pg-vm-2:~$ psql
psql (15.4 (Ubuntu 15.4-1.pgdg22.04+1))
Type "help" for help.
```

- Остановим свежесозданный кластер
anton@otus-db-pg-vm-2:~$ sudo pg_ctlcluster 15 main stop

- Удаляем все данные в /var/lib/postgresql
- Правим postgresql.conf также как и на первой машине - `data_directory = '/mnt/pgdata/postgresql/15/main'`
- Создаем каталог sudo mkdir -p /mnt/pgdata
- Добавляем в /etc/fstab строку для нового диска и монтируем его

```
anton@otus-db-pg-vm-2:~$ sudo sh -c 'echo "LABEL=newpgdrive /mnt/pgdata ext4 defaults 0 2" >> /etc/fstab'
anton@otus-db-pg-vm-2:~$ cat /etc/fstab 
# /etc/fstab: static file system information.
#
# Use 'blkid' to print the universally unique identifier for a
# device; this may be used with UUID= as a more robust way to name devices
# that works even if disks are added and removed. See fstab(5).
#
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
# / was on /dev/vda2 during curtin installation
/dev/disk/by-uuid/ed465c6e-049a-41c6-8e0b-c8da348a3577 / ext4 defaults 0 1
LABEL=newpgdrive /mnt/pgdata ext4 defaults 0 2
anton@otus-db-pg-vm-2:~$ sudo mount -a
anton@otus-db-pg-vm-2:~$ ls -la /mnt/pgdata
total 28
drwxr-xr-x 4 root     root      4096 Sep  5 11:53 .
drwxr-xr-x 3 root     root      4096 Sep  5 12:33 ..
drwx------ 2 root     root     16384 Sep  5 11:46 lost+found
drwxr-xr-x 6 postgres postgres  4096 Sep  5 11:54 postgresql
```

- Стартуем кластер и проверяем данные

```
anton@otus-db-pg-vm-2:~$ sudo pg_ctlcluster 15 main start
anton@otus-db-pg-vm-2:~$ sudo -u postgres psql
could not change directory to "/home/anton": Permission denied
psql (15.4 (Ubuntu 15.4-1.pgdg22.04+1))
Type "help" for help.

postgres=# \c postgres
You are now connected to database "postgres" as user "postgres".
postgres=# select * from test order by random() limit 5;
                  c1                  
--------------------------------------
 3e9d56db-0e67-42f5-b4ce-dece01a2c1b4
 c2c5b0fc-3915-4067-9cf9-552846ec2272
 848eb40a-75ab-48e1-b628-7946296051d4
 ff1669a2-9acc-43ca-b5da-83a2554d2ab5
 3f43f977-b1ed-4e9a-ab37-2f6a59d242c0
(5 rows)
```