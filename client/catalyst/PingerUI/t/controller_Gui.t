use strict;
use warnings;
use Test::More tests => 3;

BEGIN { use_ok 'Catalyst::Test', 'PingerUI' }
BEGIN { use_ok 'PingerUI::Controller::Gui' }

ok( request('/gui')->is_success, 'Request should succeed' );


