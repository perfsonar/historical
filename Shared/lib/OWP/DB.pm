package OWP::DB;

use strict;
use warnings;

our $VERSION = 3.3;

=head1 NAME

DB.pm - DB utility functions

=head1 DESCRIPTION

DB utility functions

=cut

require Exporter;
use vars qw(@ISA @EXPORT $VERSION);
use OWP;
use OWP::Helper;
use OWP::Utils;
use Carp qw(cluck);
use DBI;
use Term::ReadKey;

@ISA    = qw(Exporter);
@EXPORT = qw(init_db);

$DB::REVISION = '$Id$';
$VERSION = $DB::VERSION = '1.0';

sub init_db {
    my ( %args )         = @_;
    my ( @mustargnames ) = qw(CONF);
    my ( @argnames )     = qw(TOOLTYPE);
    if ( !( %args = owpverify_args( \@argnames, \@mustargnames, %args ) ) ) {
        die "init_db: invalid args";
    }

    my $conf  = $args{"CONF"};
    my $ttype = "";
    if ( defined $args{"TOOLTYPE"} ) {
        $ttype = $args{"TOOLTYPE"};
    }

    my $adminuser;
    my $dbinit   = $conf->get_val( ATTR => 'INITDB' );
    my $dbdelete = $conf->get_val( ATTR => 'DELETEDB' );
    $adminuser = $dbdelete;
    $adminuser = $dbinit if ( defined( $dbinit ) );

    if ( !defined( $adminuser ) ) {
        return;
    }

    my $cgiuser  = $conf->get_val( ATTR => 'CGIDBUser',     TYPE => $ttype );
    my $cgipass  = $conf->get_val( ATTR => 'CGIDBPass',     TYPE => $ttype );
    my $dbuser   = $conf->must_get_val( ATTR => 'CentralDBUser', TYPE => $ttype );
    my $dbpass   = $conf->must_get_val( ATTR => 'CentralDBPass', TYPE => $ttype );
    my $dbdriver = $conf->must_get_val( ATTR => 'CentralDBType', TYPE => $ttype );
    my $dbname   = $conf->must_get_val( ATTR => 'CentralDBName', TYPE => $ttype );
    my $dbsource = $dbdriver . ":" . $dbname;
    my $fulldbhost = $conf->get_val( ATTR => 'CentralDBHost', TYPE => $ttype ) || "localhost";
    my ( $dbhost, $dbport ) = split_addr( $fulldbhost );
    $dbsource .= ":" . $dbhost;

    # Initialize the database before creating the tables.
    # Will drop/recreate the database if it already exists!
    # This will only work with mysql! If CentralDBType is not

    my $adminpass;
    my $driver;

    # some of this is only likely to work with mysql...
    # Most of it is DBI stuff that would work, but lets have each new
    # one add something to this 'if' to verify it.
    ( $driver ) = ( $dbdriver =~ m/DBI:(.*)/ );
    if ( !( $driver =~ m/mysql/ ) ) {
        die "Database initialization has not been tried for non-mysql";
    }

    ReadMode( 'noecho' );
    print "Enter $adminuser password: ";
    $adminpass = ReadLine( 0 );
    print "\n";
    ReadMode( 0 );

    chomp $adminpass;

    # List out existing databases
    my %dbattr;
    $dbattr{'host'}     = $dbhost;
    $dbattr{'port'}     = $dbport if ( defined( $dbport ) );
    $dbattr{'user'}     = $adminuser;
    $dbattr{'password'} = $adminpass;

    my $drh = DBI->install_driver( $driver );
    my @databases;
    @databases = DBI->data_sources( $driver, \%dbattr );

    my $ds;
    my $found = 0;
    foreach ( @databases ) {
        ( $ds ) = m/$dbdriver:(.*)/;
        $found = 1 if ( $dbname eq $ds );
    }

    my $createdb = 1;
    if ( $found ) {
        print "Existing database $dbname found. Do you really want to delete it? (y/n) ";
        my $ans = ReadLine( 0 );
        if ( !( $ans =~ m/^y/i ) ) {
            $createdb = 0;
        }
        else {
            print "dropping database $dbname\n";
            $drh->func( 'dropdb', $dbname, $dbhost, $adminuser, $adminpass, 'admin' )
                || die "Unable to drop database $dbname";
        }
    }

    if ( $dbinit && $createdb ) {
        print "creating new database $dbname\n";
        $drh->func( 'createdb', $dbname, $dbhost, $adminuser, $adminpass, 'admin' ) || die "Unable to create database $dbname";
    }

    # Connect to the 'mysql' table. Only a user with permissions to
    # do that can change the grants anyway.
    # TODO:Make portable for non-MySQL db's

    my $dbh = DBI->connect(
        "$dbdriver:$driver",
        $adminuser,
        $adminpass,
        {
            RaiseError => 0,
            PrintError => 1,
        }
    ) || die "Couldn't connect to database ($adminuser)";

    if ( $dbinit ) {
        print "Creating user account $dbuser\n";
        $dbh->do( "grant usage on *.* to $dbuser\@localhost  identified by \'$dbpass\'" ) || die "Unable to create $dbuser\@localhost account";

        print "Granting user $dbuser\@localhost access to $dbname\n";
        $dbh->do( "grant select,insert,update,delete,create,drop,index,alter,create temporary tables on $dbname.* to $dbuser\@localhost" ) || die "Unable to grant permissions to $dbuser for $dbname.*";
        
        if($cgiuser && $cgipass){
            print "Creating user account $cgiuser\n";
            print "Granting user $cgiuser\@localhost read-only access to $dbname\n";
            $dbh->do( "grant select on $dbname.* to $cgiuser\@'localhost' identified by \'$cgipass\'" ) || die "Unable to grant permissions to $cgiuser\@localhost to $dbname.*";
            print "Granting user $cgiuser\@'%' read-only access to $dbname\n";
            $dbh->do( "grant select on $dbname.* to $cgiuser\@'%' identified by \'$cgipass\'" ) || die "Unable to grant permissions to $cgiuser\@\% for $dbname.*";
        }
    }

    elsif ( $dbdelete ) {
        #if user does not exist, quietly move on. likely already deleted.
        local $dbh->{PrintError} = 0;
        print "Remove R/W user '$dbuser'? (y/n) ";
        my $ans;
        $ans = ReadLine( 0 );
        if ( $ans =~ m/^y/i ) {
            print "Revoking user $dbuser permissions\n";
            $dbh->do( "revoke all on $dbname.* from $dbuser\@localhost" );
            $dbh->do( "revoke usage on *.* from $dbuser\@localhost" );
            print "Deleting user $dbuser permissions\n";
            $dbh->do( "drop user $dbuser\@localhost" );
        }
        
        if($cgiuser){
            print "Remove R/O user '$cgiuser'? (y/n) ";
            $ans = ReadLine( 0 );
            if ( $ans =~ m/^y/i ) {
                print "Revoking user $cgiuser permissions\n";
                $dbh->do( "revoke all on $dbname.* from $cgiuser\@localhost" );
                $dbh->do( "revoke all on $dbname.* from $cgiuser\@'%'" );
                $dbh->do( "revoke usage on *.* from $cgiuser\@localhost" );
                $dbh->do( "revoke usage on *.* from $cgiuser\@'%'" );
                print "Deleting user $cgiuser\n";
                $dbh->do( "drop user $cgiuser\@'%'" );
                $dbh->do( "drop user $cgiuser\@localhost" );
            }
        }
        
        exit( 0 );
    }

    $dbh->disconnect;
}

1;

__END__

=head1 SEE ALSO

L<OWP>, L<OWP::Helper>, L<OWP::Utils>, L<Carp>, L<DBI>, L<Term::ReadKey>

To join the 'perfSONAR-PS Users' mailing list, please visit:

  https://lists.internet2.edu/sympa/info/perfsonar-ps-users

The perfSONAR-PS subversion repository is located at:

  http://anonsvn.internet2.edu/svn/perfSONAR-PS/trunk

Questions and comments can be directed to the author, or the mailing list.
Bugs, feature requests, and improvements can be directed here:

  http://code.google.com/p/perfsonar-ps/issues/list

=head1 VERSION

$Id$

=head1 AUTHOR

Jeff Boote, boote@internet2.edu

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
