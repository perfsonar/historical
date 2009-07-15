#!/usr/bin/perl -w
# ex: set tabstop=4 ai expandtab softtabstop=4 shiftwidth=4:
# -*- mode: c-basic-indent: 4; tab-width: 4; indent-tabs-mode: nil -*-
#
#      $Id$
#
#########################################################################
#                                                                       #
#                       Copyright (C)  2009                             #
#                           Internet2                                   #
#                       All Rights Reserved                             #
#                                                                       #
#########################################################################
#
#    File:          owdb.pl
#
#    Author:        Jeff W. Boote
#                   Internet2
#
#    Date:          Tue Jun 30 12:45:58 MDT 2009
#
#    Description:    
#
#    Usage:
#
#    Environment:
#
#    Files:
#
#    Options:
#
use strict;
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

foreach (keys %setopts){
    $amidefaults{ $optnames{$_} } = $setopts{$_} if(defined($setopts{$_}));
}

if (!exists($amidefaults{'INITDB'}) && !exists($amidefaults{'DELETEDB'})){
    die "$0: Must specify either -i or -x (argument is db admin account)\n";
}

# Now - fetch the full configuration
my $conf = new OWP::Conf(%amidefaults);

#
# Fetch values that *must* be set so we fail as early as possible.
#
my $dbuser   = $conf->must_get_val( ATTR => 'CentralDBUser',Type=>'OWP' );
my $dbpass   = $conf->must_get_val( ATTR => 'CentralDBPass',Type=>'OWP' );
my $dbdriver = $conf->must_get_val( ATTR => 'CentralDBType',Type=>'OWP' );
my $dbname   = $conf->must_get_val( ATTR => 'CentralDBName',Type=>'OWP' );
my $dbsource = $dbdriver . ":" . $dbname;
my $dbhost = $conf->get_val( ATTR => 'CentralDBHost',Type=>'OWP' ) || "localhost";

$dbsource .= ":" . $dbhost;

init_db(
    CONF     => $conf,
    ToolType => 'OWP'
);

print "Initializing $dbsource\n";

#
# Connect to database
#
my $dbh = DBI->connect($dbsource,$dbuser, $dbpass,
                        {   RaiseError => 0,
                            PrintError => 1
                        }) || die "Couldn't connect to database";

my ($sql);

#
# Setup table to keep track of the tables (time periods) that are
# known about.
#
$sql = "CREATE TABLE IF NOT EXISTS DATES (
        year INTEGER NOT NULL,
        month INTEGER NOT NULL,
        day INTEGER NOT NULL,
        PRIMARY KEY (year,month,day)
        )";
$dbh->do($sql) || die "Creating Dates table";


$dbh->disconnect;

exit;
