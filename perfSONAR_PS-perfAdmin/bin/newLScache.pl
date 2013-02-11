#!/usr/bin/perl -w

use strict;
use warnings;

=head1 NAME

cache.pl - Build a cache of information from the sLS infrastructure

=head1 DESCRIPTION

Contact the sLS to get a list of services.  Store the list in text files where they can be used by other applications.

=cut

use FindBin qw($RealBin);

use lib "$RealBin/../lib";
use Carp;

use SimpleLookupService::Records::Network::Service;
use perfSONAR_PS::Client::LS::PSClient::PSQuery;
use SimpleLookupService::Client::SimpleLS;
use perfSONAR_PS::Client::LS::PSQueryObjects::PSServiceQueryObject;
use perfSONAR_PS::Client::LS::PSRecords::PSService;

use SimpleLookupService::Client::Bootstrap;

use URI;

use Data::Dumper;

my $basedir = "$RealBin";

my $base =  "/var/lib/perfsonar/perfAdmin/cachenewLS";
#my $base     = "$basedir/cache";
my $EXP_TIME = time - 3600 * 24;    #expire after 24 hours

my $query =
  perfSONAR_PS::Client::LS::PSQueryObjects::PSServiceQueryObject->new();
$query->init();

my $bootstrap = SimpleLookupService::Client::Bootstrap->new();
$bootstrap->init();
my $serverlist = $bootstrap->query_urls();

#print @{$serverlist};
my @result = ();
my %resultList;
my %LSKeywords = ();
foreach my $s ( @{$serverlist} ) {
	my %keywordCount;
	my $url      = URI->new($s);
	my $hostname = $url->host();
	my $port     = $url->port();

	my $server = SimpleLookupService::Client::SimpleLS->new();
	$server->init( { host => $hostname, port => $port } );
	$server->connect();

	if ( $server->getStatus() eq "alive" ) {
		my $client = perfSONAR_PS::Client::LS::PSClient::PSQuery->new();
		$client->init( { server => $server, query => $query } );

		my $response = $client->query();
		push @result, @{$response};

		#extract required fields from result and store in a hash
	  SERVICE: foreach my $service ( @{$response} ) {
	  		
			my %service = ();
			my $key     = '';
			my @et      = @{ $service->getServiceEventType() };

			if (@et) {
				if ( $et[0] eq
					   "http://ggf.org/ns/nmwg/characteristic/utilization/2.0"
					or $et[0] eq "http://ggf.org/ns/nmwg/tools/snmp/2.0"
					or $et[0] eq "utilization" )
				{
					$key = "list.snmpma";
				}
				elsif ($et[0] eq "http://ggf.org/ns/nmwg/tools/pinger/2.0/"
					or $et[0] eq "http://ggf.org/ns/nmwg/tools/pinger/2.0" )
				{
					$key = "list.pinger";
				}
				elsif ( $et[0] eq
"http://ggf.org/ns/nmwg/characteristics/bandwidth/acheiveable/2.0"
					or $et[0] eq
"http://ggf.org/ns/nmwg/characteristics/bandwidth/achieveable/2.0"
					or $et[0] eq
"http://ggf.org/ns/nmwg/characteristics/bandwidth/achievable/2.0"
					or $et[0] eq "http://ggf.org/ns/nmwg/tools/iperf/2.0" )
				{
					$key = "list.psb.bwctl";
				}
				elsif ($et[0] eq "http://ggf.org/ns/nmwg/tools/owamp/2.0"
					or $et[0] eq
"http://ggf.org/ns/nmwg/characteristic/delay/summary/20070921"
				  )
				{
					$key = "list.psb.owamp";
				}
				elsif ( $et[0] eq "http://ggf.org/ns/nmwg/tools/bwctl/1.0" ) {
					$key = "list.bwctl";
				}
				elsif (
					$et[0] eq "http://ggf.org/ns/nmwg/tools/traceroute/1.0" )
				{
					$key = "list.traceroute";
				}
				elsif ( $et[0] eq "http://ggf.org/ns/nmwg/tools/npad/1.0" ) {
					$key = "list.npad";
				}
				elsif ( $et[0] eq "http://ggf.org/ns/nmwg/tools/ndt/1.0" ) {
					$key = "list.ndt";
				}
				elsif ( $et[0] eq "http://ggf.org/ns/nmwg/tools/owamp/1.0" ) {
					$key = "list.owamp";
				}
				elsif ( $et[0] eq "http://ggf.org/ns/nmwg/tools/ping/1.0" ) {
					$key = "list.ping";
				}
				elsif ( $et[0] eq "http://ggf.org/ns/nmwg/topology/20070809" ) {
					$key = "list.ts";
				}
				elsif ( $et[0] eq "http://ggf.org/ns/nmwg/tools/phoebus/1.0" ) {
					$key = "list.phoebus";
				}
				elsif (
					$et[0] eq "http://ggf.org/ns/nmwg/tools/traceroute/2.0" )
				{
					$key = "list.traceroute_ma";
				}
				elsif ( $et[0] eq "http://ggf.org/ns/nmwg/tools/gridftp/1.0" ) {
					$key = "list.gridftp";
				}
				elsif ( $et[0] eq "http://docs.oasis-open.org/wsn/br-2" ) {
					$key = "list.idcnb";
				}
				elsif ( $et[0] eq "http://oscars.es.net/OSCARS" ) {
					$key = "list.idc";
				}
			}

			my @servicename = @{ $service->getServiceName() };
			if (@servicename) {
				$service{'service-name'} = $servicename[0];
			}
			else {
				$service{'service-name'} = '';
			}

			my @servicetype = @{ $service->getServiceType() };
			if (@servicetype) {
				$service{'service-type'} = $servicetype[0];
			}
			else {
				$service{'service-type'} = '';
			}

			my $servicelocation = '';
			if ( $service->getSiteName() ) {
				$servicelocation .= $service->getSiteName()->[0];
			}

			if ( $service->getCity() ) {
				$servicelocation .= $service->getCity()->[0];
			}

			if ( $service->getRegion() ) {
				$servicelocation .= $service->getRegion()->[0];
			}

			if ( $service->getCountry() ) {
				$servicelocation .= $service->getCountry()->[0];
			}

			$service{'service-location'} = $servicelocation;
			
			
			my @communities=();
			if ($service->getCommunities()){
			    push @communities, @{$service->getCommunities()};
			}

			my $first_kw    = 1;
			my $keyword     = '';
			foreach my $community (@communities) {
				if ($first_kw) {
					$first_kw = 0;
				}
				else {
					$keyword .= ",";
				}
				$keyword .= "project:" . $community;
				$keywordCount{$community} = 1;
			}

			$service{'service-keyword'} = $keyword;

			my @serviceLocators = @{ $service->getServiceLocators() };
			foreach my $serviceLocator (@serviceLocators) {
				my %serviceval = %service;
				$serviceval{'service-locator'} = $serviceLocator;
				if ($key) {
					push @{ $resultList{$key} }, \%serviceval;
				}
			}

		}
	}
	
	$LSKeywords{$s}->{"KEYWORDS"} = \%keywordCount ;
}

#print Dumper(%LSKeywords);

my %counter              = ();
my %list = ();
foreach my $file ( keys %resultList ) {
	my $serviceref           = $resultList{$file};
	my %file_service_tracker = ();
	#my %counter              = ();

	print "\n", $file, "\n";

	#OPEN FILE AND KEEP UNEXPIRED
	my %cached_hosts = ();
	if ( -e $base . "/" . $file ) {
		open( IN, "< " . $base . "/" . $file )
		  or croak "can't open $base/$file for reading.";

		while (<IN>) {
			chomp;
			my @fields = split /\|/;
			if ( @fields < 6 ) {
				print "Invalid line in $base/$file\n";
				next;
			}

			my @tmpKws = split( /\,/, $fields[4] );
			if ( $fields[5] && $fields[5] =~ /\d+/ && $fields[5] > $EXP_TIME ) {
				$cached_hosts{ $fields[0] } = {
					CONTACT   => $fields[0],
					NAME      => $fields[1],
					TYPE      => $fields[2],
					DESC      => $fields[3],
					KEYWORDS  => \@tmpKws,
					TIMESTAMP => $fields[5]
				};
			}
		}
		close(IN);
	}

	my $writetype = ">";
	$writetype = ">>" if exists $counter{$file};
	$counter{$file} = 1;

	open( OUT, $writetype . $base . "/" . $file )
	  or croak "can't open $base/$file for writing.";
	foreach my $serv ( @{$serviceref} ) {
		my %service = %{$serv};
		my $serviceLocator = $service{'service-locator'};
		if ( defined $cached_hosts{$serviceLocator}
			&& $cached_hosts{$serviceLocator} )
		{
			delete $cached_hosts{$serviceLocator};
		}
		if ( exists $file_service_tracker{ $serviceLocator . $file } ) {
			next;
		}

		$file_service_tracker{ $serviceLocator . $file } = 1;
		print OUT $serviceLocator, "|";
		print OUT $service{'service-name'} if $service{'service-name'};
		print OUT "|";
		print OUT $service{'service-type'} if $service{'service-type'};
		print OUT "|";
		print OUT $service{'service-location'} if $service{'service-location'};
		print OUT "|";
		print OUT $service{'service-keyword'} if $service{'service-keyword'};
		print OUT "|";
		print OUT time;
		print OUT "\n";
		print $file , " - ", $serviceLocator, "\n";

	}

	#write any remaining hash elements
	foreach my $cache_key ( keys %cached_hosts ) {

		print OUT $cached_hosts{$cache_key}->{"CONTACT"}, "|";
		print OUT $cached_hosts{$cache_key}->{"NAME"}
		  if $cached_hosts{$cache_key}->{"NAME"};
		print OUT "|";
		print OUT $cached_hosts{$cache_key}->{"TYPE"}
		  if $cached_hosts{$cache_key}->{"TYPE"};
		print OUT "|";
		print OUT $cached_hosts{$cache_key}->{"DESC"}
		  if $cached_hosts{$cache_key}->{"DESC"};
		print OUT "|";
		my $first_kw = 1;

		foreach my $kw ( @{ $cached_hosts{$cache_key}->{"KEYWORDS"} } ) {
			if ($first_kw) {
				$first_kw = 0;
			}
			else {
				print OUT ",";
			}
			print OUT $kw;
		}
		print OUT "|";
		print OUT $cached_hosts{$cache_key}->{"TIMESTAMP"}
		  if $cached_hosts{$cache_key}->{"TIMESTAMP"};
		print OUT "\n";
		print $file , " - ", $cached_hosts{$cache_key}->{"CONTACT"},
		  " (cached)\n";
	}
	close(OUT);

}


#cache keywords in case some are missing
if( -e $base . "/list.keywords"){
    open( KEYWORDS, "<" . $base . "/list.keywords" ) or croak "can't open keyword list";
    while( <KEYWORDS> ){
        chomp;
        my @fields = split /\|/;
        if( @fields != 3 ){
            next;
        }
        if($fields[2] < $EXP_TIME || !$fields[1]){
            next;
        }
        $LSKeywords{$fields[0]}{"KEYWORDS"}{$fields[1]} = 1;
        print "Cached Keyword: " . $fields[0] . " -> " . $fields[1] . "\n";
    }
    close KEYWORDS;
}


# should we do some verification/validation here?
open( KEYWORDS, ">" . $base . "/list.keywords" ) or croak "can't open keyword list";
foreach my $h ( keys %LSKeywords ) {

    if ( exists $LSKeywords{$h}{"KEYWORDS"} and $LSKeywords{$h}{"KEYWORDS"} ) {

        foreach my $k ( keys %{ $LSKeywords{$h}{"KEYWORDS"} } ) {
            print KEYWORDS "$h|$k|" . time . "\n";
        }
    }

}
close( KEYWORDS );


