#!/usr/bin/perl -w

use strict;

our $VERSION = 3.3;

=head1 NAME

check_pSB_db.pl - Repairs the tables in the pSB database

=head1 DESCRIPTION

This script runs "REPAIR TABLE" on the tables in the perfSONAR-BUOY database.
It accepts a number of options such as using owmesh.conf to get the database
info or it may be provided directly via the command-line.

=head1 SYNOPSIS

clean_pSB_db.pl [I<options>]
clean_pSB_db.pl [B<--dbuser> username][B<--dbpassword> password][B<--dbhost> hostname][B<--dbname> database] [I<options>]
clean_pSB_db.pl [B<--owmesh-dir> owmeshdir][B<--dbtype> owamp|bwctl|traceroute] [I<options>]

=over

=item B<-h,--help>

displays this message.

=item B<--dbtype> owamp|bwctl|traceroute

indicates type of data in database. Valid value are 'owamp', 'bwctl', or 'traceroute'. Defaults to 'owamp'.

=item B<--dbname> name

name of database to access. Defaults to 'owamp'.

=item B<--dbuser> user

name of database user. Defaults to root.

=item B<--dbpassword> password

password to access database. Defaults to empty string.

=item B<--dbhost> host

database host to access. Defaults to localhost.

=item B<--owmesh-dir> dir

location of owmesh.conf file with database username and password.

overrides dbuser, dbpassword, dbhost and dbname.

=item B<--verbose>

increase amount of output from program

=back

=cut

use FindBin;
use lib "$FindBin::Bin/../lib";

use DBI;
use Getopt::Long;
use Time::Local;
use perfSONAR_PS::Config::OWP::Conf;
use POSIX;

#var definitions
my $DEFAULT_DB_HOST = 'localhost';
my %OW_TYPES = ( 'owamp' => 'OWP', 'bwctl' => 'BW', 'traceroute' => 'TRACE');
my %valid_tables = ();

#Set option default
my $dbtype = "owamp";
my $dbname = "owamp";
my $dbuser = "root";
my $dbpassword = "";
my $dbhost= $DEFAULT_DB_HOST;
my $help = 0;
my $verbose = 0;
my $owmesh_dir = "/opt/perfsonar_ps/perfsonarbuoy_ma/etc";

#Retrieve options
my $result = GetOptions (
    "h|help"   => \$help,
    "owmesh-dir=s" => \$owmesh_dir,
    "dbtype=s" => \$dbtype,
    "dbname=s" => \$dbname,
    "dbuser=s" => \$dbuser,
    "dbpassword=s" => \$dbpassword,
    "dbhost=s" => \$dbhost,
    "v|verbose" => \$verbose
);

# Error handling for options
unless ( $result ){
    &usage();
    exit 1;
}

if( $dbtype ne "owamp" && $dbtype ne "bwctl" && $dbtype ne "traceroute"){
    print STDERR "Option 'dbtype' must be 'owamp', 'bwctl', or 'traceroute'\n";
    &usage();
    exit 1;
}

# print help if help option given
if( $help ){
    &usage();
    exit 0;
}

# open owmesh.conf
if($owmesh_dir){
    my $owmesh_type = $OW_TYPES{$dbtype};
    my %defaults = (
        DBHOST  => $DEFAULT_DB_HOST,
        CONFDIR => $owmesh_dir
    );
    my $conf = new perfSONAR_PS::Config::OWP::Conf( %defaults );
    $dbuser = $conf->must_get_val( ATTR => 'CentralDBUser', TYPE => $owmesh_type );
    $dbpassword = $conf->must_get_val( ATTR => 'CentralDBPass', TYPE => $owmesh_type );
    $dbhost = $conf->get_val( ATTR => 'CentralDBHost', TYPE => $owmesh_type ) || $DEFAULT_DB_HOST;
    $dbname = $conf->must_get_val( ATTR => 'CentralDBName', TYPE => $owmesh_type );
}

#connect to database
my $start_time = time;
my $dbh = DBI->connect("DBI:mysql:$dbname;host=$dbhost", $dbuser, $dbpassword) or die $DBI::errstr;

#Determine tables to clean
my $show_sth = $dbh->prepare("SHOW TABLES") or die $dbh->errstr;
$show_sth->execute() or die $show_sth->errstr;

my @tables = ();
while(my $show_row = $show_sth->fetchrow_arrayref){
    push @tables, $show_row->[0];
}

foreach my $table (@tables) {
    my $repair_sth = $dbh->prepare("REPAIR TABLE $table");
    print "Checking table $table\n" if ($verbose);
    $repair_sth->execute()or die $repair_sth->errstr;
}
my $end_time = time;

$dbh->disconnect();
print "Success (Checked ".scalar(@tables)." tables) in ".($end_time-$start_time)." seconds\n";

#
# print command usage
#
sub usage() {
    print "clean_pSB_db.pl <options>\n";
    print "    -h,--help                            displays this message.\n";
    print "    --dbtype type                        Indicates type of data in database. Valid value are 'owamp' or 'bwctl'. Defaults to 'owamp'.\n";
    print "    --dbname name                        name of database to access. Defaults to 'owamp'.\n";
    print "    --dbuser user                        name of database user. Defaults to root.\n";
    print "    --dbpassword password                password to access database. Defaults to empty string.\n";
    print "    --dbhost host                        database host to access. Defaults to localhost.\n";
    print "    --owmesh-dir dir                     location of owmesh.conf file with database username and password.\n";
    print "                                         overrides dbuser, dbpassword, dbhost and dbname.\n";
    print "    --verbose                            increase amount of output from program\n";
}

__END__

=head1 SEE ALSO
L<DBI>, L<Getopt::Long>, L<Time::Local>, L<POSIX>,
L<perfSONAR_PS::Config::OWP::Conf>

To join the 'perfSONAR Users' mailing list, please visit:

  https://lists.internet2.edu/sympa/info/perfsonar-ps-users

The perfSONAR-PS subversion repository is located at:

  http://anonsvn.internet2.edu/svn/perfSONAR-PS/trunk

Questions and comments can be directed to the author, or the mailing list.
Bugs, feature requests, and improvements can be directed here:

  http://code.google.com/p/perfsonar-ps/issues/list

=head1 VERSION

$Id$

=head1 AUTHOR

Andy Lake, andy@es.net
Aaron Brown, aaron@internet2.edu

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

Copyright (c) 2007-2010, Internet2

All rights reserved.

=cut
