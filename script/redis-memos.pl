use strict;
use warnings;
use Redis::Fast;

my $redis = Redis::Fast->new;

my $header = <>;
for my $id (<>) {
    chomp $id;
    $redis->zadd("memos:public", $id, $id, sub {});
}

$redis->wait_all_responses;

1;
