#!/bin/bash
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
sudo wget -qO- https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo tee /etc/apt/trusted.gpg.d/pgdg.asc &>/dev/null 
sudo apt update
sudo apt install postgresql-15 postgresql-client-15 -y
sudo sh -c 'echo "listen_addresses = '"'*'"'" >> /etc/postgresql/15/main/postgresql.conf'
sudo sh -c 'echo "host    all             all             0.0.0.0/0              scram-sha-256" >> /etc/postgresql/15/main/pg_hba.conf'
sudo sed -i 's|host    all             all             127.0.0.1/32            scram-sha-256|host    all             all             127.0.0.1/32            trust|g' /etc/postgresql/15/main/pg_hba.conf
sudo systemctl restart postgresql.service
#sudo psql -U postgres -h 127.0.0.1 -c "alter user postgres with password 'postgres';"
#sudo wget https://edu.postgrespro.ru/demo-medium.zip -O /tmp/demo-medium.zip
#sudo  unzip /tmp/demo-medium.zip -d /tmp/
#sudo psql -U postgres -h 127.0.0.1 < /tmp/demo-medium-20170815.sql