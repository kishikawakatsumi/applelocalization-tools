FROM groonga/pgroonga:3.1.3-alpine-15

COPY config/ /var/lib/postgresql/config/

ENV POSTGRES_DB database
ENV POSTGRES_USER postgres
ENV POSTGRES_PASSWORD postgres

EXPOSE 10000
CMD ["docker-entrypoint.sh", "-c", "config_file=/var/lib/postgresql/config/postgresql.conf"]
