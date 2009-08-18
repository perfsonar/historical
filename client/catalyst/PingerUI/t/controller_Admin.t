use strict;
use warnings;
use Test::More tests => 3;

BEGIN { use_ok 'Catalyst::Test', 'PingerUI' }
BEGIN { use_ok 'PingerUI::Controller::Admin' }

ok( request('/admin')->is_success, 'Request should succeed' );


