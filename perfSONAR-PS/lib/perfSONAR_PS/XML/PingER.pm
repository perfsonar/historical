#!/usr/bin/env perl

=head1 NAME

PingER - A module that provides basic methods for the creation of perfSONAR XML 
fragments for PingER.

=head1 DESCRIPTION

The purpose of this module simplify the creation of valid XML for the various
perfSONAR_PS fragments related to PingER

=head1 API


=cut


###
### TODO: how to decouple the namespace definitions? they are currently hardwired
###

package perfSONAR_PS::XML::PingER;
use perfSONAR_PS::XML::Base;

use Log::Log4perl qw( get_logger );

our $logger = get_logger("perfSONAR_PS::XML::PingER");

=head2 createData( $doc, $ns, $nsMap, $results, $id, $metadataIdRef )

creates the PingER <data/> xml fragment.
  $doc = LibXML document object
  $ns = namespace hash of key=namespace/value=URI pairs

Do i want it do it this way? it's a bit labourious and repetitive of the above
  $nsMap = mapping of the namespaces for the $ns above
    eg $nsMap->{'topo3'} = 'nmlt3' which is used to determine the correct uri for $ns{'nmlt3'}
  $results = assoc has of key/value pairs, in particular we used the following:
  	my $results = {
		'minRtt' => NUMERIC,
		'maxRtt' => NUMERIC,
		'meanRtt' => NUMERIC,
		'minIpd' => NUMERIC,
		'maxIpd' => NUMERIC,
		'lossPercent' => NUMERIC,
		'iprIpd' => NUMERIC,
		'meanIpd' => NUMERIC,
		'outOfOrder' => 0 | 1,
		'duplicates' => 0 | 1,
		'seqs'	=> ARRAY OF NUMERIC,
		'rtts'	=> ARRAY OF NUMERIC,
		'bytes' => ARRAY OF NUMERIC,
		'ttls'  => ARRAY OF NUMERIC,
		'timeValues' => ARRAY OF NUMEROC
		};
   $id = id attribute of <data/> element
   $metadataIdRef = id of metadata block referencing this <data/>

=cut
sub createData
{
	my $doc = shift;
	my $ns = shift;

#	my $nsMap = shift;

	my $results = shift; # from agent->getResults();

	my $id = shift;
	my $metadataIdRef = shift;

	my $data = $doc->createElement('data');
	$data->setNamespace( $ns->{'nmwg'}, 'nmwg' );
	$data->setAttribute( 'id', $id );
	$data->setAttribute( 'metadataIdRef', $metadataIdRef );

	$logger->debug( "creating real datums" );
	
	# crate the raw ping results
	for( my $i=0; $i < scalar( @{$results->{seqs}} ); $i++ ) {
		   
	   my $datum = $doc->createElement( 'datum' );
	   $datum->setNamespace( $ns->{'pinger'}, 'pinger' );

	   $datum->setAttribute('value', $results->{rtts}->[$i] );
	   $datum->setAttribute('seqNum', $results->{seqs}->[$i] );
	   $datum->setAttribute('numBytes', $results->{bytes}->[$i] );
	   $datum->setAttribute('ttl', $results->{ttls}->[$i] );
	   $datum->setAttribute('timeType', 'unix' );
	   $datum->setAttribute('timeValue', $results->{timeValues}->[$i]);

	   $data->appendChild( $datum );	   

	}

	$logger->debug( "creating derived datums" );	
	while( my ( $k,$v ) = each %$results ) {
		next if (  ! defined $v || $v eq '' || $v =~ /ARRAY/ );
		my $datum = $doc->createElement( 'datum' );
        $datum->setNamespace( $ns->{'pinger'}, 'pinger' );
		$datum->setAttribute( 'name', $k );
		$datum->setAttribute( 'value', $v );
		$data->appendChild( $datum );
	}

	return $data;

}


=head2 createMetaData( $doc, \%ns, $source, $dest, $sourceIP, $destIP, \%params )

Creates the metadata XML fragment from the provided input.
  $doc = LibXML document object
  \%ns = assoc. hash of key=namespace/value=uri pairs
  $source = source dns of the node
  $dest = destination dns of the node
  $sourceIP = source ip address
  $destIP = $destination ip address
  \%params = assoc. hash of key=type/value=value of parameter elements to be provided in the metadata  

=cut
sub createMetaData
{
	my $doc = shift;
	my $ns = shift;

	my $source = shift;
	my $destination = shift;
	my $sourceIP = shift;
	my $destinationIP = shift;

	my $params = shift;	

	#$logger->debug( "creating metadata" );	
	my $metadata = $doc->createElement('metadata');
	$metadata->setAttribute( 'id', '#id' );
	$metadata->setNamespace( $ns->{'nmwg'}, 'nmwg' );

	# subject
	my $subj = &perfSONAR_PS::XML::Base::createSubjectL4( $doc, $ns, 
			'pinger', 'icmp', $source, $destination, $sourceIP, $destinationIP 
	 	);
	$metadata->appendChild( $subj );

	# parameters
	#$logger->debug( "creating params" );
	my $paramsElement = &perfSONAR_PS::XML::Base::createParameters( $doc, $ns,
			'pinger', $params
	 	);
	$metadata->appendChild( $paramsElement );

	return $metadata;
}


1;