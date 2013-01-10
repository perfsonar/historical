#!/usr/bin/perl -w

use strict;
use warnings;

use FindBin qw($RealBin);
use lib ("$RealBin/../lib");
use YAML::Syck;
use URI;
use Getopt::Long;
use LWP::Simple;
use SimpleLookupService::Client::SimpleLS;
use JSON qw( encode_json decode_json);


my $basedir     = "$RealBin/";
my $configdir   = "$basedir/../etc";
my $configfile = "$configdir/hosts.yml";
my $outputFile = "$configdir/activehosts.json";
my $defaultPriority = 100;


my $mode ='';
my $result = GetOptions ("mode=s" => \$mode, # string
                       );
                       
if($mode eq '' || ($mode !~ m/server|client/i )){
	print "Error! Missing mode parameter";
	exit(1);
}else{
	my $string = YAML::Syck::LoadFile($configfile);

	my @hosts = @{$string->{'hosts'}};
	
	if($mode =~ m/server/i){
		my @hostsoutput;
		if (@hosts){
			
			foreach my $host(@hosts){
				my $locator = $host->{'locator'};
				
				if(defined $locator){
					my $url = URI->new($locator);
					my $hostname = $url->host();
					my $port = $url->port();
					
					my $ls = SimpleLookupService::Client::SimpleLS->new();
					my $ret = $ls->init({host=>$hostname, port=>$port});
					if($ret==0){
						$ls->connect();
						my $status = $ls->getStatus();
						my $hostpriority;
						
						if(defined $host->{'priority'}){
							$hostpriority = $host->{'priority'};
						}else{
							$hostpriority = $defaultPriority;
						}
						
						my $hostref = {
										locator => $locator,
										status => $status,
										priority => $hostpriority
										};
										
						push (@hostsoutput, $hostref); 
					}
				}
				
			}
		}
		
		if(@hostsoutput){
			my $outputhash = {hosts => \@hostsoutput};
			#YAML::Syck::DumpFile($outputFile, $outputhash);
			open FILEHANDLE, ">", $outputFile;		
			print FILEHANDLE encode_json($outputhash);
			close FILEHANDLE;
			exit(0);
		}
	}elsif($mode =~ m/client/i){
		my @hostsoutput;
		if (@hosts){
			
			LOOP:foreach my $host(@hosts){
				my $locator = $host->{'locator'};
				my $file = "lslist.yml";
				
				if(defined $locator){
					my $res = getstore($locator,$file);
					
					
					#my $activehostlist =  YAML::Syck::LoadFile($file);
					open FILEHANDLE, "<", $file;
					my @lines = <FILEHANDLE>;
					print @lines;
					my $json = new JSON;
					$json = $json->relaxed;
					my $activehostlist = $json->decode(@lines);
					my @activeHosts = @{$activehostlist->{'hosts'}};
				
					my $minPriority = 100;
					my $minPriorityHost = "";
					foreach my $activehost(@activeHosts){
						my $priority = $activehost->{'priority'};
						my $status = $activehost->{'status'};
						
						if(defined $status && $status eq "alive" && defined $priority && $priority<=$minPriority){
							$minPriority = 	$priority;
							$minPriorityHost = $activehost->{'locator'};
							
						}
					}
					
					if($minPriorityHost ne ""){
						
						print $minPriorityHost;
						exit(0);
					}else{
						print "Error! No active LS found!";
						exit(-1);
					}
					
				
				}
				
			}
		}
	}
}



