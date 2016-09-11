#!/bin/bash

set -ex

if [ -e /var/log/nginx/isucon.access_log.tsv ]; then
  alp -f /var/log/nginx/isucon.access_log.tsv --aggregates "/memo/\d+,/recent/\d+" | tee /tmp/alp_latest.txt
fi

if [ -e /var/lib/mysql/mysqld-slow.log ]; then
  cp /var/lib/mysql/mysqld-slow.log /tmp/mysqld-slow_latest.log
  chmod 644 /tmp/mysqld-slow_latest.log
fi

