# PG Advanced - Домашняя работа 3 - установка и настройка PostgteSQL в контейнере Docker

# создание виртуалки

## user-data.yaml

```
#cloud-config
users:
  - name: anton
    groups: sudo
    shell: /bin/bash
    sudo: [ 'ALL=(ALL) NOPASSWD:ALL' ]
    ssh-authorized-keys:
    - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC9B5ZFis6NR4cTTXiDcEGUdZEhm+1crZ7x5H6zmcHpXkd6jpaOm6NDY7qJpJl+tO9AeqWd0x/yl/esVupBk7X+VIJwKIf4ZwUoB1851sBHnaFWhmHPhPyfNqZjwRJBpwXi/yKPzVxXlFHyX7p/K3+a8r+JQknwm1zU34tW0l0ORj5PniOa5sE+O9X71X0l3slf4ahIpenUNgIg2es8Qt21EUpV6RvtkLsRSenXpNNvhT2Wdo91cuA0kzMDExwcyxAHYq18/HO9CDFpQ0/Q09MaGsL0ocVF6MymCjFNGTwm8vWYT1kKQ4mWz3eM4P7P9evsBm9j4D911r3xqeJNzwg7bMLNtyFxXXkRfM3S2XytyHcHi8MKYH3+hmPoSL+Y9xrbOGeeDLG6CfJYEAToC7ttWAw3WvnDdq4vHdzQ1p/VOJwo0bKJzseD/kjauHmLznrQ6GQ1HrB72o2X3iHZTuW0FdbHk1ZKwrlH6vnlKnjZqkUz4Fl8ht+BXlgtQDxttBs= anton@ant
```

## запуск

```
yc compute instance create \
  --name otus-db-pg-lesson3 \
  --zone ru-central1-b \
  --network-interface subnet-name=default-ru-central1-b,nat-ip-version=ipv4 \
  --create-boot-disk image-folder-id=standard-images,image-family=ubuntu-2204-lts,type=network-hdd,size=20 \
  --memory 4 \
  --core-fraction 50 \
  --preemptible \
  --metadata-from-file user-data=user-data.yaml
```

<details>
<summary>Результат создания</summary>
```
done (1m10s)
id: epdrsdaerbgh2r14hm1j
folder_id: b1ggfiad3opmftvi9r55
created_at: "2023-09-13T07:31:14Z"
name: otus-db-pg-lesson3
zone_id: ru-central1-b
platform_id: standard-v2
resources:
  memory: "4294967296"
  cores: "2"
  core_fraction: "50"
status: RUNNING
metadata_options:
  gce_http_endpoint: ENABLED
  aws_v1_http_endpoint: ENABLED
  gce_http_token: ENABLED
  aws_v1_http_token: DISABLED
boot_disk:
  mode: READ_WRITE
  device_name: epdki0qt81m3n1e5tse4
  auto_delete: true
  disk_id: epdki0qt81m3n1e5tse4
network_interfaces:
  - index: "0"
    mac_address: d0:0d:1b:e3:54:ed
    subnet_id: e2l536n8s81f5jpo1ao2
    primary_v4_address:
      address: 10.129.0.34
      one_to_one_nat:
        address: 158.160.80.124
        ip_version: IPV4
gpu_settings: {}
fqdn: epdrsdaerbgh2r14hm1j.auto.internal
scheduling_policy:
  preemptible: true
network_settings:
  type: STANDARD
placement_policy: {}
```
</details>


# установка докера в виртуальной машине YC

- подключаемся к виртуалке `ssh anton@158.160.80.124`
- ставим в соответствии с https://docs.docker.com/engine/install/ubuntu/

```
anton@epdrsdaerbgh2r14hm1j:~$ sudo apt-get update
anton@epdrsdaerbgh2r14hm1j:~$ sudo install -m 0755 -d /etc/apt/keyrings
anton@epdrsdaerbgh2r14hm1j:~$ curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
anton@epdrsdaerbgh2r14hm1j:~$ sudo chmod a+r /etc/apt/keyrings/docker.gpg
anton@epdrsdaerbgh2r14hm1j:~$ echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
anton@epdrsdaerbgh2r14hm1j:~$ sudo apt-get update
anton@epdrsdaerbgh2r14hm1j:~$ sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
anton@epdrsdaerbgh2r14hm1j:~$ sudo docker run hello-world
Unable to find image 'hello-world:latest' locally
latest: Pulling from library/hello-world
719385e32844: Pull complete 
Digest: sha256:4f53e2564790c8e7856ec08e384732aa38dc43c52f02952483e3f003afbf23db
Status: Downloaded newer image for hello-world:latest

Hello from Docker!
...
```

- ставим композ
`anton@epdrsdaerbgh2r14hm1j:~$ sudo apt install docker-compose`


# запуск постгреса в контейнере

- создание каталога для данных
`anton@epdrsdaerbgh2r14hm1j:~$ sudo mkdir /var/lib/postgres`

- создание docker-compose.yaml для потсгреса согласно https://hub.docker.com/_/postgres

```
version: '3.1'

services:
  pg_db:
    image: postgres:15.4
    name: mypg
    restart: always
    environment:
      - POSTGRES_PASSWORD=postgres
      - POSTGRES_USER=postgres
      - POSTGRES_DB=stage
      - PGDATA=/var/lib/postgresql/data/pgdata
    volumes:
      - ${POSTGRES_DIR:-/var/lib/postgres}:/var/lib/postgresql/data
    ports:
      - ${POSTGRES_PORT:-5432}:5432
```

- старт контейнера
```
anton@epdrsdaerbgh2r14hm1j:~$ sudo docker-compose up -d
Creating network "anton_default" with the default driver
Pulling pg_db (postgres:15.4)...
15.4: Pulling from library/postgres
360eba32fa65: Pull complete
6987678f9780: Pull complete
42299245e905: Pull complete
afcda32ad76a: Pull complete
23d81c750666: Pull complete
c7813914a8b7: Pull complete
876fecb4c432: Pull complete
0a8727713246: Pull complete
bd55a69456f7: Pull complete
e8a9c6f88b3a: Pull complete
4f8b906dc57f: Pull complete
6fa3ed8d5047: Pull complete
5ae8c52f2732: Pull complete
Digest: sha256:d0c68cd506cde10ddd890e77f98339a4f05810ffba99c881061a12b30a0525c9
Status: Downloaded newer image for postgres:15.4
Creating mypg ... done

anton@epdrsdaerbgh2r14hm1j:~$ sudo docker ps
CONTAINER ID   IMAGE           COMMAND                  CREATED          STATUS          PORTS                                       NAMES
2f078d79ea3b   postgres:15.4   "docker-entrypoint.s…"   24 seconds ago   Up 22 seconds   0.0.0.0:5432->5432/tcp, :::5432->5432/tcp   mypg
```

# запуск клиента psql в контейнере и наполнение БД

## создание контейнера

- создаём докерфайл
```
FROM alpine:3.18
RUN apk --no-cache add postgresql15-client
ENTRYPOINT [ "psql" ]
```

- билдим образ
```
anton@epdrsdaerbgh2r14hm1j:~$ sudo docker build -t pg-client .
[+] Building 5.5s (6/6) FINISHED                                                                                                                                             docker:default
 => [internal] load build definition from Dockerfile                                                                                                                                   0.2s
 => => transferring dockerfile: 118B                                                                                                                                                   0.0s
 => [internal] load .dockerignore                                                                                                                                                      0.2s
 => => transferring context: 2B                                                                                                                                                        0.0s
 => [internal] load metadata for docker.io/library/alpine:3.18                                                                                                                         2.0s
 => [1/2] FROM docker.io/library/alpine:3.18@sha256:7144f7bab3d4c2648d7e59409f15ec52a18006a128c733fcff20d3a4a54ba44a                                                                   0.7s
 => => resolve docker.io/library/alpine:3.18@sha256:7144f7bab3d4c2648d7e59409f15ec52a18006a128c733fcff20d3a4a54ba44a                                                                   0.1s
 => => sha256:c5c5fda71656f28e49ac9c5416b3643eaa6a108a8093151d6d1afc9463be8e33 528B / 528B                                                                                             0.0s
 => => sha256:7e01a0d0a1dcd9e539f8e9bbd80106d59efbdf97293b3d38f5d7a34501526cdb 1.47kB / 1.47kB                                                                                         0.0s
 => => sha256:7264a8db6415046d36d16ba98b79778e18accee6ffa71850405994cffa9be7de 3.40MB / 3.40MB                                                                                         0.3s
 => => sha256:7144f7bab3d4c2648d7e59409f15ec52a18006a128c733fcff20d3a4a54ba44a 1.64kB / 1.64kB                                                                                         0.0s
 => => extracting sha256:7264a8db6415046d36d16ba98b79778e18accee6ffa71850405994cffa9be7de                                                                                              0.1s
 => [2/2] RUN apk --no-cache add postgresql15-client                                                                                                                                   2.0s
 => exporting to image                                                                                                                                                                 0.3s
 => => exporting layers                                                                                                                                                                0.3s
 => => writing image sha256:1c36681183fd9e5d932cd70140ecccff2d4eb5a20cf4933b68157cb4eed41735                                                                                           0.0s 
 => => naming to docker.io/library/pg-client                                
 ```

- создадим файл с переменными окружения .env_pg согласно https://www.postgresql.org/docs/current/libpq-envars.html
```
PGDATABASE=stage
PGHOST=127.0.0.1
PGPORT=5432
PGUSER=postgres
PGPASSWORD=postgres
```

- запускаем клиентский контейнер в интерактивном режиме
```
anton@epdrsdaerbgh2r14hm1j:~$ sudo docker run --env-file=.env_pg --name=mypgclient --network="host" -it pg-client
psql (15.4)
Type "help" for help.

stage=#
```

## наполнение бд

- создание таблицы и контент

```
stage=# create table test(s text);
CREATE TABLE
stage=# insert into test(s) select gen_random_uuid () from generate_series(1,10);
INSERT 0 10
stage=# select * from test;
                  s                   
--------------------------------------
 7d643618-472f-44ba-b645-3f0d0c750df6
 78160b04-4487-4e88-8e05-130bf4ea1f83
 8efbe2f6-e8bc-4aef-9103-2dfcf295ade2
 03322eff-0ecc-46c6-be73-c7ef5a20089b
 efa1684e-37a9-4730-b689-9d1dead577d4
 9e02049e-45f5-4206-b19c-295403b50839
 2e3cf6ae-9bdc-4099-8056-4d0f990421f9
 34032890-accb-4821-969e-9e52f52cbf26
 0deb0e91-05fd-463f-b7c1-805abfef88d8
 f00f0b7f-8ec4-4093-b12a-bb5be5c088ca
(10 rows)
```

- проверка таблицы на диске на хосте (вне докера)

```
stage=# select pg_relation_filepath('test');
 pg_relation_filepath 
----------------------
 base/16384/16389
(1 row)

anton@epdrsdaerbgh2r14hm1j:~$ sudo ls -la /var/lib/postgres/pgdata/base/16384 | grep 16389
-rw------- 1 lxd docker   8192 Sep 13 09:11 16389
```

# проверка подключения извне облака

```
anton@aminkin:/mnt/dev/sdb1/Education/PgAdvanced/otus-pg-adv$ psql -h 158.160.80.124 -U postgres -d stage
Пароль пользователя postgres: 
psql (11.17 (Debian 11.17-astra.se1+b1), сервер 15.4 (Debian 15.4-1.pgdg120+1))
ПРЕДУПРЕЖДЕНИЕ: psql имеет базовую версию 11, а сервер - 15.
                Часть функций psql может не работать.
Введите "help", чтобы получить справку.

stage=# select count(*) from test;
 count 
-------
    10
(1 строка)
```

# пересоздание контейнера с сервером

- пересоздаём

```
anton@epdrsdaerbgh2r14hm1j:~$ sudo docker container ls -a
CONTAINER ID   IMAGE           COMMAND                  CREATED          STATUS                      PORTS                                       NAMES
fe2b7a231b02   pg-client       "psql"                   24 minutes ago   Exited (0) 22 minutes ago                                               mypgclient
2f078d79ea3b   postgres:15.4   "docker-entrypoint.s…"   2 hours ago      Up 2 hours                  0.0.0.0:5432->5432/tcp, :::5432->5432/tcp   mypg
anton@epdrsdaerbgh2r14hm1j:~$ sudo docker stop mypg
mypg
anton@epdrsdaerbgh2r14hm1j:~$ sudo docker rm mypg
mypg
anton@epdrsdaerbgh2r14hm1j:~$ sudo docker container ls -a
CONTAINER ID   IMAGE       COMMAND   CREATED          STATUS                      PORTS     NAMES
fe2b7a231b02   pg-client   "psql"    25 minutes ago   Exited (0) 23 minutes ago             mypgclient
anton@epdrsdaerbgh2r14hm1j:~$ sudo docker container ls -a
CONTAINER ID   IMAGE       COMMAND   CREATED          STATUS                      PORTS     NAMES
fe2b7a231b02   pg-client   "psql"    25 minutes ago   Exited (0) 23 minutes ago             mypgclient
anton@epdrsdaerbgh2r14hm1j:~$ sudo docker-compose up -d
Creating mypg ... done
```

- подключаемся клиентским контейнером (тоже пересоздаем, т.к. контейнер имеет фиксированное имя) и проверяем данные
```
anton@epdrsdaerbgh2r14hm1j:~$ sudo docker rm mypgclient
mypgclient
anton@epdrsdaerbgh2r14hm1j:~$ sudo docker run --env-file=.env_pg --name=mypgclient --network="host" -it pg-client
psql (15.4)
Type "help" for help.

stage=# select * from test;
                  s                   
--------------------------------------
 7d643618-472f-44ba-b645-3f0d0c750df6
 78160b04-4487-4e88-8e05-130bf4ea1f83
 8efbe2f6-e8bc-4aef-9103-2dfcf295ade2
 03322eff-0ecc-46c6-be73-c7ef5a20089b
 efa1684e-37a9-4730-b689-9d1dead577d4
 9e02049e-45f5-4206-b19c-295403b50839
 2e3cf6ae-9bdc-4099-8056-4d0f990421f9
 34032890-accb-4821-969e-9e52f52cbf26
 0deb0e91-05fd-463f-b7c1-805abfef88d8
 f00f0b7f-8ec4-4093-b12a-bb5be5c088ca
(10 rows)
```

