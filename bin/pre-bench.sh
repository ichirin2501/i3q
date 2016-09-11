#!/bin/bash

set -ex

# 実際にbenchのDBリセット直後に実行されるスクリプト

cd $(dirname $0)
cd ..
# root

# ALTER
mysql -uroot -proot isucon -e 'ALTER TABLE memos ADD INDEX `idx_is_private_id` (`is_private`, `id`)'
mysql -uroot -proot isucon -e 'ALTER TABLE memos ADD INDEX `idx_user_created_at` (`user`, `created_at`)'

# redis init
redis-cli flushdb
mysql -uroot -proot isucon -e 'SELECT id FROM memos WHERE is_private = 0 ORDER BY id' | ./env.sh carton exec -- perl script/redis-memos.pl
