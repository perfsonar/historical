#!/bin/env perl

#######################################################################
# dns loc api to get info about location of an ip address
#######################################################################

use gmaps::Location;
use utils::addresses;
use perfSONAR_PS::DB::SQL;

package gmaps::Location::SQLite;
@ISA = ( 'gmaps::Location' );
our $logger = Log::Log4perl::get_logger( 'gmaps::Location::SQLite' );

use strict;

# constructor
sub new
{
	my $classpath = shift;
	my $dbfile = shift;
	my $self = $classpath->SUPER::new( @_ );

    # set up db
	$self->{DB} = perfSONAR_PS::DB::SQL->new();


	@{$self->{DBSCHEMA}} = ( 'urn', 'latitude', 'longitude', 'last_updated' );
	$self->{DBTABLE} = 'data';

	$self->{DB}->setName( name => 'DBI:SQLite:dbname=' . $dbfile );
	$self->{DB}->setSchema( schema => \@{$self->{DBSCHEMA}} );

	#$logger->debug( "database: " . $self->{DB} );
	# open db
	my $result = $self->{DB}->openDB();
	if ( $result == 0 ) {

		# create the table and db if not exist
		my $table = $self->{DB}->query( query => 'SELECT name FROM SQLite_Master WHERE name=\'' . $self->{DBTABLE} . "'"  );

		$logger->debug( "TABLE EXISTS? " . scalar @$table );
		if ( scalar @$table == 0 ) {
			my $res = $self->{DB}->query( query => "CREATE TABLE " . $self->table() . " ( urn TEXT PRIMARY KEY, latitude DOUBLE, longitude DOUBLE, last_updated DATE ); " );
			$logger->debug( "Creating table." );
		}
		return $self;
	} else {
	    $logger->error( "could not open db " );
		return undef;
	}
}

sub db
{
	my $self = shift;
	return $self->{DB};
}

sub table
{
	my $self = shift;
	return $self->{DBTABLE};
}


sub getLatLong
{
	my $self = shift;
	
	my $urn = shift;
	my $libXml = shift; # not used.
	
	my $dns = shift; # not used
	my $ip = shift; # not used
	
	my $domain = undef;
	my $host = undef;


    if ($self->db()->openDB == -1) {
      $logger->fatal( "Error opening database" );
    }

    my $result = $self->db()->query( query => "SELECT latitude, longitude FROM " . $self->table() . "  WHERE urn='$urn'" );
    while ( my $row = shift @{$result} ) {
	return ( $row->[0], $row->[1] );
    }

   return ( undef, undef );

}


# try an update, if not then do insert
sub setLatLong{
	my $self = shift;
	my $insert = {
		'urn' => shift,
		'latitude' => shift,
		'longitude' => shift,
		'last_updated' => 'NOW()',
	};

	# count
	my $count = $self->db()->count( query => "SELECT * from " . $self->table() . " WHERE urn='" . $insert->{urn} . "'" );
	$logger->debug( "Count " . $count );
	
	# insert
	if ( $count == 0 ) {
		my $status = $self->db()->insert( table => $self->table(), argvalues => $insert );
		if ( $status == -1 ) {
			$logger->warn( "Error inserting urn '" . $insert->{urn} . "'" );
			return undef;
		}
		return 1;

	} else {
	# update
		my $urn = $insert->{urn};
		delete $insert->{urn};
		while ( my ( $k,$v ) = each %$insert ) {
			$insert->{$k} = "'" . $v . "'";	
		}
		if ( $self->db()->update( table => $self->table(), wherevalues =>  { 'urn' => "'" . $urn . "'" }, updatevalues => $insert )  == -1 ) {
			$logger->warn( "Error updating urn '" . $urn . "'" );
			return undef;
		}
		return 1;
	}
}


sub DESTROY
{
	my $self = shift;
	return $self->db()->closeDB();

}

1;
