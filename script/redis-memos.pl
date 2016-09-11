use strict;
use warnings;
use Redis::Fast;

my $redis = Redis::Fast->new;

my $header = <>;
for my $row (<>) {
    chomp $row;
    my ($id, $user, $is_private) = split /\t/, $row;

    if ($is_private == 0) { # public
        $redis->zadd("memos:public", $id, $id, sub {});
        $redis->zadd("memos:user:$user:public", $id, $id, sub {});
    }

    # 公開/非公開すべて
    $redis->zadd("memos:user:$user:all", $id, $id, sub {});
}

$redis->wait_all_responses;

1;
