FROM debian:bullseye-slim
WORKDIR /var/lib/postgresql

ADD ./scripts /scripts
RUN /scripts/postgres-install.sh

USER postgres
ENV PGUSER=postgres
ENV PGHOST /var/run/postgresql
ENV PGPORT 5432
ENV PGDATA /var/lib/postgresql/data
ENV PATH="$PATH:/usr/lib/postgresql/15/bin:/scripts"
ENV LANG en_US.utf8

STOPSIGNAL SIGINT
ENTRYPOINT ["/scripts/entrypoint.sh"]