ALTER TABLE memos ADD COLUMN username varchar(255) NOT NULL,
                  ADD INDEX `idx_is_private_id` (`is_private`, `id`), 
                  ADD INDEX `idx_user_created_at` (`user`, `created_at`),
                  ADD INDEX `idx_user_is_private_created_at` (`user`, `is_private`, `created_at`);

UPDATE memos JOIN users ON memos.user = users.id SET memos.username = users.username;
