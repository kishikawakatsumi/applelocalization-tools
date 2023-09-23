#!/bin/sh
set -ex

mkdir temp
split -b 90M data.sql temp/data.sql.
