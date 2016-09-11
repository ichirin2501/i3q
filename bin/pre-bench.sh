#!/bin/bash

set -ex

# 実際にbenchのDBリセット直後に実行されるスクリプト

cd $(dirname $0)
cd ..
# root

# ALTER
mysql -uroot -proot -e 'ALTER TABLE memos ADD INDEX `idx_is_private_created_at` (`is_private`, `created_at`)'
mysql -uroot -proot -e 'ALTER TABLE memos ADD INDEX `idx_user_created_at` (`user`, `created_at`)'
