#!/bin/bash

set -ex

# 実際にbenchのDBリセット直後に実行されるスクリプト

cd $(dirname $0)
cd ..
# root

# ALTER, etc
mysql -uroot -proot isucon -e 'source /home/isucon/webapp/perl/config/alter.sql'

# redis init
redis-cli flushdb
mysql -uroot -proot isucon -e 'SELECT id FROM memos WHERE is_private = 0 ORDER BY id' | ./env.sh carton exec -- perl script/redis-memos.pl
