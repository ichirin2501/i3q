use FindBin;
use lib "$FindBin::Bin/extlib/lib/perl5";
use lib "$FindBin::Bin/lib";
use File::Basename;
use Plack::Builder;
use Isucon3::Web;
use Plack::Session::Store::Cache;
use Plack::Session::State::Cookie;
use Cache::Memcached::Fast;

my @nytprof_opts = qw(addpid=1 start=no sigexit=1 blocks=1 file=/tmp/nytprof.out);
$ENV{"NYTPROF"} = join ":", @nytprof_opts;
require Devel::NYTProf;

my $root_dir = File::Basename::dirname(__FILE__);

my $app = Isucon3::Web->psgi($root_dir);
builder {
    enable 'ReverseProxy';
    enable 'Static',
        path => qr!^/(?:(?:css|js|img)/|favicon\.ico$)!,
        root => $root_dir . '/public';
    enable 'Session',
        store => Plack::Session::Store::Cache->new(
            cache => Cache::Memcached::Fast->new({
                servers => [ "localhost:11212" ],
            }),
        ),
        state => Plack::Session::State::Cookie->new(
            httponly    => 1,
            session_key => "isucon_session",
        ),
    ;
    $app;
};
