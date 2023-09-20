#!/bin/sh

docker exec -it postgres pg_dump -U postgres -w database > postgresql-$(date +"%Y%m%d").sql
split -b 90M data.sql data.sql.
