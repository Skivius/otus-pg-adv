#!/bin/bash

apt-get update
apt-get install -y lsb-release wget gnupg git ca-certificates apt-utils

sh -c 'echo "deb https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -

apt-get update

>&2 echo "Install Postgres"

# bypass initdb of a "main" cluster
apt-get -y --no-install-recommends install postgresql-common
echo 'create_main_cluster = false' | tee -a /etc/postgresql-common/createcluster.conf

apt-get -y --no-install-recommends install postgresql-15

>&2 echo "Install Autofailover"

apt-get install -y pg-auto-failover-cli
apt-get install -y postgresql-15-auto-failover

echo en_US.UTF-8 UTF-8 > /etc/locale.gen
locale-gen en_US.UTF-8