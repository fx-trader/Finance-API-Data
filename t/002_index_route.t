use strict;
use warnings;

use Finance::API::Data;
use Test::More tests => 1;
use Plack::Test;
use HTTP::Request::Common;

my $app = Finance::API::Data->to_app;
is( ref $app, 'CODE', 'Got app' );

my $test = Plack::Test->create($app);
#my $res  = $test->request( GET '/parse' );

#ok( $res->is_success, '[GET /parse] successful' );
