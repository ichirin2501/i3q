package Isucon3::Web;

use strict;
use warnings;
use utf8;
use Kossy;
use DBIx::Sunny;
use JSON qw/ decode_json /;
use Digest::SHA qw/ sha256_hex /;
use DBIx::Sunny;
use File::Temp qw/ tempfile /;
use IO::Handle;
use Encode;
use Time::Piece;
use Redis::Fast;
use Text::Markdown qw/ markdown /;

sub load_config {
    my $self = shift;
    $self->{_config} ||= do {
        my $env = $ENV{ISUCON_ENV} || 'local';
        open(my $fh, '<', $self->root_dir . "/../config/${env}.json") or die $!;
        my $json = do { local $/; <$fh> };
        close($fh);
        decode_json($json);
    };
}

sub dbh {
    my ($self) = @_;
    $self->{_dbh} ||= do {
        my $dbconf = $self->load_config->{database};
        DBIx::Sunny->connect(
            "dbi:mysql:database=${$dbconf}{dbname};host=${$dbconf}{host};port=${$dbconf}{port}", $dbconf->{username}, $dbconf->{password}, {
                RaiseError => 1,
                PrintError => 0,
                AutoInactiveDestroy => 1,
                mysql_enable_utf8   => 1,
                mysql_auto_reconnect => 1,
            },
        );
    };
}

sub redis {
    my ($self) = @_;
    $self->{_redis} ||= Redis::Fast->new;
}

filter 'session' => sub {
    my ($app) = @_;
    sub {
        my ($self, $c) = @_;
        my $sid = $c->req->env->{"psgix.session.options"}->{id};
        $c->stash->{session_id} = $sid;
        $c->stash->{session}    = $c->req->env->{"psgix.session"};
        $app->($self, $c);
    };
};

filter 'get_user' => sub {
    my ($app) = @_;
    sub {
        my ($self, $c) = @_;

        my $user_id = $c->req->env->{"psgix.session"}->{user_id};
        my $user = $self->dbh->select_row(
            'SELECT * FROM users WHERE id=?',
            $user_id,
        );
        $c->stash->{user} = $user;
        $c->res->header('Cache-Control', 'private') if $user;
        $app->($self, $c);
    }
};

filter 'require_user' => sub {
    my ($app) = @_;
    sub {
        my ($self, $c) = @_;
        unless ( $c->stash->{user} ) {
            return $c->redirect('/');
        }
        $app->($self, $c);
    };
};

filter 'anti_csrf' => sub {
    my ($app) = @_;
    sub {
        my ($self, $c) = @_;
        my $sid   = $c->req->param('sid');
        my $token = $c->req->env->{"psgix.session"}->{token};
        if ( $sid ne $token ) {
            return $c->halt(400);
        }
        $app->($self, $c);
    };
};

get '/' => [qw(session get_user)] => sub {
    my ($self, $c) = @_;

    my $total = $self->redis->zcard("memos:public");
    # id desc のみで良い, 日付順は
    my $memos = $self->dbh->select_all(
        'SELECT id,user,is_private,created_at,updated_at,username,SUBSTRING_INDEX(content,\'\n\',1) AS title FROM memos WHERE is_private=0 ORDER BY id DESC LIMIT 100'
    );

    $c->render('index.tx', {
        memos => $memos,
        page  => 0,
        total => $total,
        uri_for_memo_sla => $c->req->uri_for('/memo/'),
    });
};

get '/recent/:page' => [qw(session get_user)] => sub {
    my ($self, $c) = @_;
    my $page  = int $c->args->{page};
    my $total = $self->redis->zcard("memos:public");
    my $offset = $page * 100;
    my $memo_ids = $self->redis->zrevrange("memos:public", $offset, $offset + 100);
    my $memos = [];
    if (scalar(@$memo_ids)) {
        $memos = $self->dbh->select_all("SELECT id,user,is_private,created_at,updated_at,username,SUBSTRING_INDEX(content,\'\n\',1) AS title FROM memos WHERE id IN(" . join(',', @$memo_ids) . ') ORDER BY id DESC');
    }

    if ( @$memos == 0 ) {
        return $c->halt(404);
    }

    $c->render('index.tx', {
        memos => $memos,
        page  => $page,
        total => $total,
        uri_for_memo_sla => $c->req->uri_for('/memo/'),
    });
};

get '/signin' => [qw(session get_user)] => sub {
    my ($self, $c) = @_;
    $c->render('signin.tx', {});
};

post '/signout' => [qw(session get_user require_user anti_csrf)] => sub {
    my ($self, $c) = @_;
    $c->req->env->{"psgix.session.options"}->{change_id} = 1;
    delete $c->req->env->{"psgix.session"}->{user_id};
    $c->redirect('/');
};

post '/signup' => [qw(session anti_csrf)] => sub {
    my ($self, $c) = @_;

    my $username = $c->req->param("username");
    my $password = $c->req->param("password");
    my $user = $self->dbh->select_row(
        'SELECT id, username, password, salt FROM users WHERE username=?',
        $username,
    );
    if ($user) {
        $c->halt(400);
    }
    else {
        my $salt = substr( sha256_hex( time() . $username ), 0, 8 );
        my $password_hash = sha256_hex( $salt, $password );
        $self->dbh->query(
            'INSERT INTO users (username, password, salt) VALUES (?, ?, ?)',
            $username, $password_hash, $salt,
        );
        my $user_id = $self->dbh->last_insert_id;
        $c->req->env->{"psgix.session"}->{user_id} = $user_id;
        $c->redirect('/mypage');
    }
};

post '/signin' => [qw(session)] => sub {
    my ($self, $c) = @_;

    my $username = $c->req->param("username");
    my $password = $c->req->param("password");
    my $user = $self->dbh->select_row(
        'SELECT id, username, password, salt FROM users WHERE username=?',
        $username,
    );
    if ( $user && $user->{password} eq sha256_hex($user->{salt} . $password) ) {
        $c->req->env->{"psgix.session.options"}->{change_id} = 1;
        my $session = $c->req->env->{"psgix.session"};
        $session->{user_id} = $user->{id};
        $session->{token}   = sha256_hex(rand());
        $self->dbh->query(
            'UPDATE users SET last_access=now() WHERE id=?',
            $user->{id},
        );
        return $c->redirect('/mypage');
    }
    else {
        $c->render('signin.tx', {});
    }
};

get '/mypage' => [qw(session get_user require_user)] => sub {
    my ($self, $c) = @_;

    my $memos = $self->dbh->select_all(
        'SELECT id,user,is_private,created_at,updated_at,username,SUBSTRING_INDEX(content,\'\n\',1) AS title FROM memos WHERE user=? ORDER BY created_at DESC',
        $c->stash->{user}->{id},
    );
    $c->render('mypage.tx', {
        memos => $memos,
        uri_for_memo => $c->req->uri_for('/memo'),
        uri_for_memo_sla => $c->req->uri_for('/memo/'),
    });
};

post '/memo' => [qw(session get_user require_user anti_csrf)] => sub {
    my ($self, $c) = @_;

    $self->dbh->query(
        'INSERT INTO memos (user, content, is_private, created_at, username) VALUES (?, ?, ?, now(),?)',
        $c->stash->{user}->{id},
        scalar $c->req->param('content'),
        scalar($c->req->param('is_private')) ? 1 : 0,
        $c->stash->{user}->{username},
    );
    my $memo_id = $self->dbh->last_insert_id;

    # redis
    if (! $c->req->param('is_private')) { # public
        $self->redis->zadd("memos:public", $memo_id, $memo_id);
        $self->redis->zadd(sprintf("memos:user:%d:public", $c->stash->{user}{id}), $memo_id, $memo_id);
    }
    # 公開非公開問わず
    $self->redis->zadd(sprintf("memos:user:%d:all", $c->stash->{user}{id}), $memo_id, $memo_id);

    $c->redirect('/memo/' . $memo_id);
};

get '/memo/:id' => [qw(session get_user)] => sub {
    my ($self, $c) = @_;

    my $user = $c->stash->{user};
    my $memo = $self->dbh->select_row(
        'SELECT id, user, content, is_private, created_at, updated_at FROM memos WHERE id=?',
        $c->args->{id},
    );
    unless ($memo) {
        $c->halt(404);
    }
    if ($memo->{is_private}) {
        if ( !$user || $user->{id} != $memo->{user} ) {
            $c->halt(404);
        }
    }
    $memo->{content_html} = markdown($memo->{content});

    my $is_public_only = 0;
    if ($user && $user->{id} == $memo->{user}) {
        # 公開/非公開問わず
        $is_public_only = 0;
    }
    else {
        # 公開only
        $is_public_only = 1;
    }

    # older/newer のidさえわかればよい
    my $self_id; # ごみ
    my ($newer_id, $older_id);

    # keyが違うだけでロジックは一緒
    my $target_key = "";
    if ($is_public_only == 1) {
        $target_key = sprintf("memos:user:%d:public", $memo->{user});
    } else {
        $target_key = sprintf("memos:user:%d:all", $memo->{user});
    }

    my $rk = $self->redis->zrank($target_key, $memo->{id});
    if ($rk == 0) {
        my $seq = $self->redis->zrange($target_key, 0, 1);
        ($self_id, $newer_id) = @$seq;
    } else {
        my $seq = $self->redis->zrange($target_key, $rk - 1, $rk + 1);
        ($older_id, $self_id, $newer_id) = @$seq;
    }

    $c->render('memo.tx', {
        memo  => $memo,
        older_id => $older_id,
        newer_id => $newer_id,
        uri_for_memo_sla => $c->req->uri_for('/memo/'),
    });
};

1;
