package perfSONAR_PS::DB::SQL::FT;

use warnings;
use strict;

use version;
our $VERSION = 1.0;

=head1 NAME

perfSONAR_PS::DB::SQL::FT

=head1 DESCRIPTION

A module that provides  data access for FT databases.  This module provides
access to the relevant DBI wrapped methods given the relevant contact points for
the database. 

=head1 METHODS
  
=cut

use Data::Dumper;
use English '-no_match_vars';
use Scalar::Util qw(blessed);
use Log::Log4perl qw( get_logger );

use POSIX qw( strftime );
use perfSONAR_PS::DB::SQL::Base;
use base qw(perfSONAR_PS::DB::SQL::Base);

use constant CLASSPATH => 'perfSONAR_PS::DB::SQL::FT';
use constant METADATA  => {
    'ID'         => 1,
    'EndPointID' => 2,
    'Stripes'    => 3,
    'BufferSize' => 4,
    'BlockSize'  => 5,
    'Program'    => 6,
    'User'       => 7,
    'SrcPath'    => 8,
    'DestPath'   => 9,
    'Streams'    => 10
};
use constant DATA => {
    'ID'           => 1,
    'Metadata_ID'  => 2,
    'TransferTime' => 3,
    'NBytes'       => 4,
    'Duration'     => 5,
};
use constant ENDPOINTS => {
    'ID'           => 1,
    'DestIP'       => 2,
    'SrcIP'        => 3,
};

=head2  soi_metadata

wrapper method to retrieve the relevant   metadata entry given  the parameters hashref
 
     'SrcIP' => 
     'DestIP' =>

	  
     'stripes'    = # Number of Stripes
     'buffer'     = # BufferSize
     'block' 	  = # Data Block Size
     'program'    = # Tool or Software used for transfering Files
     'user' 	  = # User initiating the File transfer	
     'srcpath'    = # Path for the source file
     'destpath'   = # Path for the destination file
     'streams'    = # Number of streams

returns 
    0 = if everything is okay
   -1 = somethign went wrong 

=cut

sub soi_metadata {
    my ( $self, $param ) = @_;

    #$self->LOGGER->info("\n".ref($param)."\n");
    unless ( $param
        && ref($param) eq 'HASH'
        && $self->validateQuery( $param, METADATA ) == 0 )
    {
        $self->LOGGER->error("not a hash ref");

  #        $self->ERRORMSG( "soi_metadata requires single HASH ref parameter" );
        return -1;
    }
    foreach my $name (qw/SrcIP DestIP/) {

        unless ( defined $param->{$name} ) {
            $self->LOGGER->error("$name not found in hash");

        #            $self->ERRORMSG( "soi_metadata requires $name set and  " );
            return -1;
        }
    }
#### picking up EndPoint ID for a given DestIP and SrcIP
    my $queryEP = $self->getFromTable(
	{
            query => [
                'SrcIP'      => { 'eq' => $param->{'SrcIP'} },
                'DestIP'     => { 'eq' => $param->{'DestIP'} },
            ],
            table    => 'EndPoints',
            validate => ENDPOINTS,
            index    => 'ID',
            limit    => 1,
        }
    );

return -1 if !ref($queryEP) && $queryEP < 0;
    my $nEP = scalar( keys %{$queryEP} );
    if ( $nEP == 0 ) {

        return -1;
}


    my $query = $self->getFromTable(
        {
            query => [
                'EndPointID' => { 'eq' => (keys %{$queryEP})[0] },
                'DestIP'     => { 'eq' => $param->{'DestIP'} },
                'Stripes'    => { 'eq' => $param->{'stripes'} },
                'BufferSize' => { 'eq' => $param->{'buffersize'} },
                'BlockSize'  => { 'eq' => $param->{'blocksize'} },
                'Program'    => { 'eq' => $param->{'program'} },
                'User'       => { 'eq' => $param->{'user'} },
                'Streams'    => { 'eq' => $param->{'streams'} },
                'SrcPath'    => { 'eq' => $param->{'srcpath'} },
                'DestPath'   => { 'eq' => $param->{'destpath'} },
            ],
            table    => 'Metadata',
            validate => METADATA,
            index    => 'ID',
            limit    => 1
        }
    );

    #print($query."\n");
    return -1 if !ref($query) && $query < 0;
    my $n = scalar( keys %{$query} );
    if ( $n == 0 ) {

        return -1;

        # ID is serial number so it will return ID or -1

    }
    $self->LOGGER->debug( "found host "
          . $param->{SrcIP} . "/ "
          . $param->{DestIP} . " ID="
          . ( keys %{$query} )[0] );
    return ( keys %{$query} )[0];

}

=head2 getEPID

helper method to get sorted list of EndPoint IDs.

Input = query to fetch EndPoint(hash).

Output = EndPointID.

=cut

sub getEPbyID {
    my ( $self, $ID ) = @_;

    my $results = $self->getFromTable(
        {
            query    => [ 'ID' => { 'eq' => $ID } ],
            table    => 'EndPoints',
            validate => ENDPOINTS,
            index    => 'ID',
            limit    => 1,
        }
    );

    return $results;
}

=head2 getEPs

helper method to get SrcIP and DestIP

Input = query to fetch data from EndPoints table.
      = number of results to return.

Output = EndPoints in a hash, with ID as keys.

=cut

sub getEPs {
    my ( $self, $param, $limit ) = @_;

    my $results = $self->getFromTable(
        {
            query    => $param,
            table    => 'EndPoints',
            validate => ENDPOINTS,
            index    => 'ID',
            limit    => $limit,
        }
    );
    return $results;
}

=head2 getMetaID
 
helper method to get sorted list of IDs.

Input = query to fetch Metadata in a hash.
        number of results to be returned.

Output = results sorted on ID field of Metadata in a sorted array or a hash. Returns multiple results.
  
=cut

sub getMetaID {
    my ( $self, $param, $limit ) = @_;

    my $results = $self->getFromTable(
        {
            query    => $param,
            table    => 'Metadata',
            validate => METADATA,
            index    => 'ID',
            limit    => $limit,
        }
    );

    return sort { $a <=> $b } keys %{$results}
      if ( $results && ref($results) eq 'HASH' );

    return $results;
}

=head2 getMeta
 
helper method to get Metadata

Input = query to fetch data from Metadata table, in a hash.
      = number of results to return.

Output = Metadata in a hash, with ID as keys.
 
=cut

sub getMeta {
    my ( $self, $param, $limit ) = @_;

    my $results = $self->getFromTable(
        {
            query    => $param,
            table    => 'Metadata',
            validate => METADATA,
            index    => 'ID',
            limit    => $limit,
        }
    );
#$self->LOGGER->info("Results=".Dumper($results));
    return $results;
}

=head2 getData

helper method to get data

Input = query to fetch data in a hash.
        tablename from which to get data.
        number of results to return.
Output = Hash containing Data, with Metadata_ID as keys for the hash.

=cut

sub getData {
    my ( $self, $param, $table, $limit ) = @_;
    unless ( $param && ref($param) eq 'ARRAY' ) {
        $self->LOGGER->error(" getData requires query parameter");
        return -1;
    }
    unless ($table) {
        $self->LOGGER->debug("Table field not set, setting it to Data");
        $table = 'Data';
    }
    my $iterator_local = {};

    my $objects = $self->getFromTable(
        {
            query    => $param,
            table    => $table,
            validate => DATA,
            index    => 'ID',
            limit    => $limit,
        }
    );
    $self->LOGGER->logdie( $self->ERRORMSG ) if ( $self->ERRORMSG );
    if ( $objects && ( ref($objects) eq 'HASH' ) && %{$objects} ) {
        $iterator_local->{$_} = $objects->{$_} for keys %{$objects};
        $self->LOGGER->debug(
            " Added data rows ..... ......: " . scalar %{$objects} );
    }
    else {
        $self->LOGGER->debug(
            " ...............No  data rows  .....from " . $table );
    }

    return $iterator_local;
}

1;

__END__


=head1 SEE ALSO

To join the 'perfSONAR Users' mailing list, please visit:

  https://mail.internet2.edu/wws/info/perfsonar-user

The perfSONAR-PS subversion repository is located at:

  http://anonsvn.internet2.edu/svn/perfSONAR-PS/trunk

Questions and comments can be directed to the author, or the mailing list.
Bugs, feature requests, and improvements can be directed here:

  http://code.google.com/p/perfsonar-ps/issues/list

=head1 AUTHOR

Fahad Satti


