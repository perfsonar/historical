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

my $basedir = "$RealBin";
#my $base =  "/var/lib/perfsonar/perfAdmin/cache";
#should change base directory before moving to production
my $base = "$basedir/cache";
my $EXP_TIME = time - 3600*24;#expire after 24 hours

my $query = perfSONAR_PS::Client::LS::PSQueryObjects::PSServiceQueryObject->new();
$query->init();

my $bootstrap =  SimpleLookupService::Client::Bootstrap->new();
$bootstrap->init({file => "$basedir/../etc/service_url" });
my $serverlist = $bootstrap->query_urls();

print @{$serverlist};
foreach my $s (@{$serverlist}){
	my $url = URI->new($s);
    my $hostname = $url->host();
    my $port = $url->port();
    
    my $server = SimpleLookupService::Client::SimpleLS->new();
	$server->init({host=>$hostname, port=>$port});
	$server->connect();
	
	if($server->getStatus() eq "alive"){
	my $client = perfSONAR_PS::Client::LS::PSClient::PSQuery->new();
	$client->init({server=>$server, query=>$query});

	my $response = $client->query();
	print scalar @{$response}, "\n";
	
	my %servicelist = ();
	foreach my $service (@{$response}){
		my @et = @{$service->getServiceEventType()};
		my @servicearray = ();
		if (exists $servicelist{$et[0]}){
			@servicearray = @{$servicelist{$et[0]}};
		}
		
		push @servicearray, $service;
		$servicelist{$et[0]} = \@servicearray;
	}
	
	my %list = ();
	foreach my $servicetypekey (keys %servicelist){
	   my $serviceref = $servicelist{$servicetypekey};	
	   my %file_service_tracker = ();
	   my %counter = ();
		my @keywords = ();
		
		my $et = $servicetypekey;
		my $file = q{};
			if ( $et eq "http://ggf.org/ns/nmwg/characteristic/utilization/2.0" or $et eq "http://ggf.org/ns/nmwg/tools/snmp/2.0" or $et eq "utilization" ) {
        		$file = "list.snmpma";
    		}
    		elsif ( $et eq "http://ggf.org/ns/nmwg/tools/pinger/2.0/" or $et eq "http://ggf.org/ns/nmwg/tools/pinger/2.0" ) {
        		$file = "list.pinger";
    		}
    		elsif ( $et eq "http://ggf.org/ns/nmwg/characteristics/bandwidth/acheiveable/2.0" or $et eq "http://ggf.org/ns/nmwg/characteristics/bandwidth/achieveable/2.0" or $et eq "http://ggf.org/ns/nmwg/characteristics/bandwidth/achievable/2.0" or $et eq "http://ggf.org/ns/nmwg/tools/iperf/2.0" ) {
        		$file = "list.psb.bwctl";
    		}
    		elsif ( $et eq "http://ggf.org/ns/nmwg/tools/owamp/2.0" or $et eq "http://ggf.org/ns/nmwg/characteristic/delay/summary/20070921" ) {
        		$file = "list.psb.owamp";
    		}
    		elsif ( $et eq "http://ggf.org/ns/nmwg/tools/bwctl/1.0" ) {
        		$file = "list.bwctl";
    		}
    		elsif ( $et eq "http://ggf.org/ns/nmwg/tools/traceroute/1.0" ) {
        		$file = "list.traceroute";
    		}
    		elsif ( $et eq "http://ggf.org/ns/nmwg/tools/npad/1.0" ) {
        		$file = "list.npad";
    		}
    		elsif ( $et eq "http://ggf.org/ns/nmwg/tools/ndt/1.0" ) {
       			$file = "list.ndt";
    		}
    		elsif ( $et eq "http://ggf.org/ns/nmwg/tools/owamp/1.0" ) {
        		$file = "list.owamp";
    		}
    		elsif ( $et eq "http://ggf.org/ns/nmwg/tools/ping/1.0" ) {
        		$file = "list.ping";
    		}
    		elsif ( $et eq "http://ggf.org/ns/nmwg/topology/20070809" ) {
        		$file = "list.ts";
    		}
    		elsif ( $et eq "http://ggf.org/ns/nmwg/tools/phoebus/1.0" ) {
        		$file = "list.phoebus";
    		}
    		elsif ( $et eq "http://ggf.org/ns/nmwg/tools/traceroute/2.0" ) {
        		$file = "list.traceroute_ma";
    		}elsif ( $et eq "http://ggf.org/ns/nmwg/tools/gridftp/1.0" ) {
        		$file = "list.gridftp";
    		}
    		elsif ( $et eq "http://docs.oasis-open.org/wsn/br-2" ) {
        		$file = "list.idcnb";
    		}
    		elsif ( $et eq "http://oscars.es.net/OSCARS" ) {
        		$file = "list.idc";
    		}
    		next unless $file;
    		print "\n",$file,"\n";
    			
			#OPEN FILE AND KEEP UNEXPIRED
			my %cached_hosts = ();
			if(-e $base . "/" . $file){
				open( IN, "< ". $base . "/" . $file) or croak "can't open $base/$file for reading.";
							        
				while( <IN>){
					chomp;
					my @fields = split /\|/;
					if( @fields < 6 ){
						print "Invalid line in $base/$file\n";
						next;
					}
					
					my @tmpKws = split( /\,/, $fields[4] );
					if($fields[5] && $fields[5] =~ /\d+/ && $fields[5] > $EXP_TIME){
						$cached_hosts{ $fields[0] } = { CONTACT => $fields[0], NAME => $fields[1], TYPE => $fields[2], DESC => $fields[3], KEYWORDS => \@tmpKws, TIMESTAMP => $fields[5] };
					}
				}
				close ( IN );
			}

			my $writetype = ">";
			$writetype = ">>" if exists $counter{$file};
			$counter{$file} = 1;
			    
			open( OUT, $writetype . $base . "/" . $file ) or croak "can't open $base/$file for writing.";
			foreach my $service (@{$serviceref}){
			    foreach my $serviceLocator (@{$service->getServiceLocators()}){
			    	if(defined $cached_hosts{ $serviceLocator } && $cached_hosts{ $serviceLocator }){
			            delete $cached_hosts{ $serviceLocator };
			        }
			        if(exists $file_service_tracker{$serviceLocator . $file}){
			            next;
			        }
			        
			        $file_service_tracker{$serviceLocator . $file} = 1;
			        print OUT $serviceLocator, "|";
			        print OUT @{$service->getServiceName()} if $service->getServiceName();
			        print OUT "|";
			        print OUT @{$service->getServiceType()} if $service->getServiceType();
			        print OUT "|";
			        print OUT @{$service->getSiteName()} if $service->getSiteName();
			        print OUT "|";
			        
			        my $first_kw = 1;
			        
			        foreach my $project (@{$service->getValue('group-communities')}){
			        	if($first_kw){
			                $first_kw = 0;
			            }else{
			                print OUT ",";
			            }
						print OUT "project:", $project;
					}

			        print OUT "|";
			        print OUT time;
			        print OUT "\n";
			        print $file , " - ", $serviceLocator, "\n";
			    }	   	    
			}
			#write any remaining hash elements
			foreach my $cache_key ( keys %cached_hosts ) {
			    	
				print OUT $cached_hosts{$cache_key}->{"CONTACT"}, "|";
			    print OUT $cached_hosts{$cache_key}->{"NAME"} if $cached_hosts{$cache_key}->{"NAME"};
		        print OUT "|";
		        print OUT $cached_hosts{$cache_key}->{"TYPE"} if $cached_hosts{$cache_key}->{"TYPE"};
		        print OUT "|";
		        print OUT $cached_hosts{$cache_key}->{"DESC"} if $cached_hosts{$cache_key}->{"DESC"};
		        print OUT "|";
		        my $first_kw = 1;
		        foreach my $kw(@{ $cached_hosts{$cache_key}->{"KEYWORDS"} }){
	 	           if($first_kw){
	 	               $first_kw = 0;
		           }else{
    	               print OUT ",";
	               }
			       print OUT $kw;
			     }
			     print OUT "|";
			     print OUT $cached_hosts{$cache_key}->{"TIMESTAMP"} if $cached_hosts{$cache_key}->{"TIMESTAMP"};
			     print OUT "\n";
			     print $file , " - ", $cached_hosts{$cache_key}->{"CONTACT"}, " (cached)\n";			
			}
			close( OUT );
	
		}
	}
}
