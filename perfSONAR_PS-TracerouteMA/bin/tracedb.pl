#!/usr/bin/perl -w
# ex: set tabstop=4 ai expandtab softtabstop=4 shiftwidth=4:
# -*- mode: c-basic-indent: 4; tab-width: 4; indent-tabs-mode: nil -*-

use strict;
use warnings;

our $VERSION = 3.1;

=head1 NAME

tracedb.pl - Create traceroute database for perfSONAR-BUOY

=head1 SYNOPSIS

tracedb.pl [ -c configdir ] [ -i | -x ] dba_account_name

=head1 DESCRIPTION

Given some basic parameters, create the database for the traceroute data portion of
perfSONAR-BUOY collection.

=head1 OPTIONS

  -c configuration dir
 
  -i initialize database

  -x destroy database
 
=head1 EXAMPLES

Initialize database as "root" dba (typical for mysql):

  tracedb.pl -c /PATH/TO/CONFIG/DIRECTORY -i root

=cut

use FindBin;

# BEGIN FIXMORE HACK - DO NOT EDIT
# %amidefaults is initialized by fixmore MakeMaker hack
my %amidefaults;

BEGIN {
    %amidefaults = (
        CONFDIR => "$FindBin::Bin/../etc",
        LIBDIR  => "$FindBin::Bin/../lib",
    );
}

# END FIXMORE HACK - DO NOT EDIT

# use amidefaults to find other modules $env('PERL5LIB') still works...
use lib $amidefaults{'LIBDIR'};
use Getopt::Std;
use OWP;
use OWP::Utils;
use OWP::DB;
use Carp qw(cluck);
use DBI;

# setup a few hashes to make adding/removing options for this program easier.
my %options = (
    CONFDIR  => "c:",
    INITDB   => "i:",    # arg is 'admin' username
    DELETEDB => "x:",    # arg is 'admin' username
);
my %optnames = (
    c => "CONFDIR",
    i => "INITDB",
    x => "DELETEDB",
);

# Now combine the options from the hash above, and fetch the opts from argv
my $options = join '', values %options;
my %setopts;
getopts( $options, \%setopts );

foreach ( keys %setopts ) {
    $amidefaults{ $optnames{$_} } = $setopts{$_} if ( defined( $setopts{$_} ) );
}

if ( !exists( $amidefaults{'INITDB'} ) && !exists( $amidefaults{'DELETEDB'} ) ) {
    die "$0: Must specify either -i or -x\n";
}

# Now - fetch the full configuration
my $conf = new OWP::Conf( %amidefaults );

#
# Fetch values that *must* be set so we fail as early as possible.
#
my $dbuser   = $conf->must_get_val( ATTR => 'CentralDBUser', Type => 'Trace' );
my $dbpass   = $conf->must_get_val( ATTR => 'CentralDBPass', Type => 'Trace' );
my $dbdriver = $conf->must_get_val( ATTR => 'CentralDBType', Type => 'Trace' );
my $dbname   = $conf->must_get_val( ATTR => 'CentralDBName', Type => 'Trace' );
my $dbsource = $dbdriver . ":" . $dbname;
my $dbhost = $conf->get_val( ATTR => 'CentralDBHost', Type => 'Trace' ) || "localhost";

$dbsource .= ":" . $dbhost;

init_db(
    CONF     => $conf,
    ToolType => 'Trace'
);

print "Initializing $dbsource\n";

#
# Connect to database
#
my $dbh = DBI->connect(
    $dbsource,
    $dbuser, $dbpass,
    {
        RaiseError => 0,
        PrintError => 1
    }
) || die "Couldn't connect to database";

my ( $sql );

#
# Setup table to keep track of the tables (time periods) that are
# known about.
#
$sql = "CREATE TABLE IF NOT EXISTS DATES (
        year int NOT NULL,
        month INT NOT NULL, 
        day INT NOT NULL,
        PRIMARY KEY(year, month, day)
    )";
$dbh->do( $sql ) || die "Creating Dates table";

$dbh->disconnect;

exit;

__END__

=head1 SEE ALSO

L<FindBin>, L<Getopt::Std>, L<OWP>, L<OWP::Utils>, L<OWP::DB>, L<Carp>, L<DBI>

To join the 'perfSONAR Users' mailing list, please visit:

  https://mail.internet2.edu/wws/info/perfsonar-ps-users

The perfSONAR-PS subversion repository is located at:

  http://anonsvn.internet2.edu/svn/perfSONAR-PS/trunk

Questions and comments can be directed to the author, or the mailing list.
Bugs, feature requests, and improvements can be directed here:

  http://code.google.com/p/perfsonar-ps/issues/list

=head1 VERSION

$Id: tracedb.pl 3670 2009-09-02 13:55:50Z zurawski $

=head1 AUTHOR

Jeff W. Boote <boote@internet2.edu>

=head1 LICENSE

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=head1 COPYRIGHT

Copyright (c) 2004-2009, Internet2

All rights reserved.

=cut
