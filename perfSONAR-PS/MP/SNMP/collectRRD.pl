#!/usr/bin/perl -w -I ../../lib
# ################################################ #
#                                                  #
# Name:		collectRRD.pl                      #
# Author:	Jason Zurawski                     #
# Contact:	zurawski@eecis.udel.edu            #
# Args:		N/A                                #
# Purpose:	Given some conf files, gather and  #
#               store SNMP data in a database.     #
#                                                  #
# ################################################ #
use strict;
use threads;
use threads::shared;
use Thread::Semaphore; 

use Time::HiRes qw( gettimeofday );
use POSIX qw( setsid );
use Data::Dumper;

use perfSONAR_PS::Common;
use perfSONAR_PS::Transport;
use perfSONAR_PS::DB::File;
use perfSONAR_PS::DB::XMLDB;
use perfSONAR_PS::DB::RRD;
use perfSONAR_PS::DB::SQL;
use perfSONAR_PS::MP::SNMP;
use perfSONAR_PS::MA::SNMP;

my $DEBUG = 0;
if($#ARGV == 0) {
  if($ARGV[0] eq "-v" || $ARGV[0] eq "-V") {
    $DEBUG = 1;
  }
}

my $LOGFILE ="./log/perfSONAR-PS-error.log";
my $CONFFILE = "./collectRRD.conf";

my %ns = (
  nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
  netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
  nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
  snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/",
  select => "http://ggf.org/ns/nmwg/ops/select/2.0/"
);

		# Read in configuration information
my %hash = ();
%hash = readConfiguration($CONFFILE, \%hash);

		# Read in the appropriate metadata to be
		# polling for, this relates to the choices
		# in the configuration file.  
my %metadata = ();
my %markMetadata = ();
%metadata = readValues(\%metadata, \%ns, "//nmwg:metadata");
%metadata = chainMetadata(\%metadata);

		# Read in the appropriate data to be
		# polling for, this also relates to the 
		# choices in the configuration file.  
my %data = ();
%data = readValues(\%data, \%ns, "//nmwg:data");

		# remove md that were used just for 
		# chaining purposes (i.e. if a md has 
		# at least 1 data trigger, we should 
		# keep it).
foreach my $m (keys %metadata) {
  foreach my $d (keys %data) {
    if($m eq $data{$d}{"nmwg:data-metadataIdRef"}) {
      if($markMetadata{$m}) {
        $markMetadata{$m} = $markMetadata{$m} + 1;
      }
      else {
        $markMetadata{$m} = 1;
      }
      if($DEBUG) {
        print "Increasing mark count on '".$m."' to '".$markMetadata{$m}."'.\n";
      }      
    }
  }
  if(!$markMetadata{$m}) {
    if($DEBUG) {
      print "Removing '".$m."' from the Metadata list.\n";
    }
    delete $metadata{$m};  
  }
}

		# this is a shortcut hash that will map
		# OIDs (from the MD) to the proper rrd 
		# information (from the data).  We also
		# will always be requesting the upTime
		# so we can keep a synchronization with
		# the remote clock.
my %lookup = ();
$lookup{"1.3.6.1.2.1.1.3.0"} = "timeticks";

		# Prepare an rrd object for each
		# rrd file that was seen (we have the 
		# potential to map multiple data blocks 
		# to a single rrd object
my %datadb = ();
foreach my $d (keys %data) {
  if($DEBUG) {
    print $d , " - " , Dumper($data{$d}) , "\n";
  }
  
  if($data{$d}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "rrd") {
    if(!defined $datadb{$data{$d}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-file"}}) { 
      $datadb{$data{$d}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-file"}} = new perfSONAR_PS::DB::RRD(
        $hash{"DATA_DB_NAME"} , 
        $data{$d}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-file"},
        "",
        1
      );
    }
  		# load in the data sources
    $datadb{$data{$d}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-file"}}->setVariable($data{$d}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-dataSource"});
  }
  elsif($data{$d}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "sqlite") {
    print "We do not support this data type right now, sorry.\n";

    my $mark = removeMetadata(\%metadata, $data{$d}{"nmwg:data-metadataIdRef"});
    if($mark) {
      $markMetadata{$mark} = $markMetadata{$mark} - 1;
      if($markMetadata{$mark} == 0) {
        delete $markMetadata{$mark};
	delete $metadata{$mark};
        if($DEBUG) {
	  print "Removing '".$mark."' from the Metadata list.\n";
        }	
      }
    }
    
  }
  elsif($data{$d}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "mysql") {
    print "We do not support this data type right now, sorry.\n";

    my $mark = removeMetadata(\%metadata, $data{$d}{"nmwg:data-metadataIdRef"});
    if($mark) {
      $markMetadata{$mark} = $markMetadata{$mark} - 1;
      if($markMetadata{$mark} == 0) {
        delete $markMetadata{$mark};
	delete $metadata{$mark};
        if($DEBUG) {
	  print "Removing '".$mark."' from the Metadata list.\n";
        }	
      }
    }

  }
  else {
    print "We do not support this data type right now, sorry.\n";

    my $mark = removeMetadata(\%metadata, $data{$d}{"nmwg:data-metadataIdRef"});
    if($mark) {
      $markMetadata{$mark} = $markMetadata{$mark} - 1;
      if($markMetadata{$mark} == 0) {
        delete $markMetadata{$mark};
	delete $metadata{$mark};
        if($DEBUG) {
	  print "Removing '".$mark."' from the Metadata list.\n";
        }	
      }
    }
    
  }  
}
		# Prepare an SNMP object for each host, this
		# could mean multiple metadata instances share
		# the same snmp object.
my %snmp = ();
foreach my $m (keys %metadata) {
  if($markMetadata{$m}) {
    if($DEBUG) {
      print $m , " - " , Dumper($metadata{$m}) , "\n";
    }
    
    my $hostName = "";  
    my $ifIndex = ""; 
    my $snmpVersion = "";
    my $snmpCommunity = "";
    my $eventType = "";
    foreach my $m2 (keys %{$metadata{$m}}) {
      if($m2 =~ m/.*hostName$/) {
        $hostName = $m2;
      }
      elsif($m2 =~ m/.*ifIndex$/) {
        $ifIndex = $m2;
      }
      elsif($m2 =~ m/.*nmwg:eventType$/) {
        $eventType = $m2;
      }
      elsif($m2 =~ m/.*nmwg:parameter-SNMPVersion$/) {
        $snmpVersion = $m2;
      }
      elsif($m2 =~ m/.*nmwg:parameter-SNMPCommunity$/) {
        $snmpCommunity = $m2;
      }
    }  

    $metadata{$m}{$eventType} =~ s/snmp\.//;
  
    if(!defined $snmp{$metadata{$m}{$hostName}}) {    	  
      $snmp{$metadata{$m}{$hostName}} = new perfSONAR_PS::MP::SNMP(
        $metadata{$m}{$hostName}, 
        "" ,
        $metadata{$m}{$snmpVersion},
        $metadata{$m}{$snmpCommunity},
        "");
    }
    $snmp{$metadata{$m}{$hostName}}->setVariable($metadata{$m}{$eventType}.".".$metadata{$m}{$ifIndex});
  
		# map the lookup information
    foreach my $d (keys %data) {
      if($data{$d}{"nmwg:data-metadataIdRef"} eq $m) {
        $lookup{$metadata{$m}{$hostName}."-".$metadata{$m}{$eventType}.".".$metadata{$m}{$ifIndex}} = $d;
        last;
      }
    }
  }
}



if(!$DEBUG) {
		# flush the buffer
  $| = 1;
		# start the daemon
  &daemonize;
}



if($DEBUG) {
  print "Starting '".threads->tid()."' as main\n";
}

my $reval:shared = 0;
my $sem = Thread::Semaphore->new(1);

#my $mpThread = threads->new(\&measurementPoint, $DEBUG, $hash{"MP_SAMPLE_RATE"});
my $mpThread = threads->new(\&registerLS, $DEBUG, $hash{"LS_REGISTRATION_INTERVAL"}, $hash{"LS_INSTANCE"});

my $maThread = threads->new(\&measurementArchive, $DEBUG, $hash{"PORT"}, $hash{"ENDPOINT"});
my $regThread = threads->new(\&registerLS, $DEBUG, $hash{"LS_REGISTRATION_INTERVAL"}, $hash{"LS_INSTANCE"});

if(!defined $mpThread || !defined $maThread || !defined $regThread) {
  print "Thread creation has failed...exiting...\n";
  exit(1);
}

$mpThread->join();
$maThread->join();
$regThread->join();







# ################################################ #
# Sub:		measurementPoint                   #
# Args:		N/A                                #
# Purpose:	Performs measurements at a         #
#               periodic rate as specified in the  #
#               storage medium                     #
# ################################################ #
sub measurementPoint {
  my($DEBUG, $sampleRate) = @_;
  if($DEBUG) {
    print "Starting '".threads->tid()."' as MP\n";
  }
		# Pre-Loop tasks include:
		#
		# 1) Set up the SNMP connections
		#
		# 2) Set up the time keeping mechanism for 
		#    each host

  my($sec, $frac) = Time::HiRes::gettimeofday;
  my $time = $sec.".".$frac;
  
  my %hostTicks = ();
  my %refTime = ();
  foreach my $s (keys %snmp) {
    $refTime{$s} = $time;
    $hostTicks{$s} = 0;
    $snmp{$s}->setSession;
    		# each host needs to grap the timeticks, 
		# so we can set that here.
    $snmp{$s}->setVariable("1.3.6.1.2.1.1.3.0");
  }

		# Main loop, we need to do the following 
		# things:
		#
		# 1) For each SNMP object, collect the data
		#
		# 2) Do some bookeeping on each time value
		#    to ensure that we are keeping synch
		#    with the time on the remote host (as 
		#    best as we can)
		# 
		# 3) insert into the resulting data into
		#    the rrd file
		#
		# 4) sleep, then start again
					
  while(1) {
  
    if($reval) {
      		# a change has been made to the MD 
		# structure (by the MA thread) so we
		# need to re-eval all of our objects 
		# (md, d, and snmp) to respect this 
		# change.


      # do stuff...
      

      		# Make sure the flag variable is 
		# not in use, then reset the flag 
		# value.
      $sem->down;
      {
        lock($reval);
        $reval = 0;
      }
      $sem->up;
    }  
  
    foreach my $s (keys %snmp) {
      if($DEBUG) {
        print "Collecting for '" , $s , "'.\n";
      }
    
      my %results = ();
      %results = $snmp{$s}->collectVariables;

		# if there is some sort of problem with
		# the target, see if you can re-establish
		# the session
      if(defined $results{"error"} && $results{"error"} == -1) {  
        $snmp{$s}->closeSession;  
        $snmp{$s}->setSession;
      }
      else {     
		# The first issue is to do bookeeping on 
		# the time info for the particular host 
		# we have just polled.  Update the 'remote'
		# time based on the timeticks we get back
		# in the SNMP packet.
        my $diff = 0;
        my $newHostTicks = 0;
        foreach my $r (keys %results) {
          if($lookup{$r} && $lookup{$r} eq "timeticks") {
	    if($hostTicks{$s} == 0) {
	      $hostTicks{$s} = $results{$r}/100;
	      $newHostTicks = $results{$r}/100;
	    }
	    else {	    
	      $newHostTicks = $results{$r}/100;	    
	    }
	    last;
	  }
        }    
      		# Calculate the difference, update, and adjust
		# this new time.
        $diff = $newHostTicks - $hostTicks{$s};
        $hostTicks{$s} = $newHostTicks;  
        $refTime{$s} += $diff;

		# 'insert' the results as they come in to 
		# the RRD object, note that this isn't final
		# until after all SNMP objects have been 
		# polled     
        foreach my $r (keys %results) { 
          if($lookup{$s."-".$r} && $lookup{$s."-".$r} ne "timeticks") {
	    if($DEBUG) {
	      print "inserting: " , $refTime{$s}  , "," , $data{$lookup{$s."-".$r}}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-dataSource"} , "," , $results{$r} , "\n";
	    }				
            $datadb{$data{$lookup{$s."-".$r}}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-file"}}->insert($refTime{$s}, 
	                                                                                                         $data{$lookup{$s."-".$r}}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-dataSource"},
			  				                                                         $results{$r});
	  }
        }
      }
    }
		# No we commit, by doing this at the end
		# we ensure that ALL possible DS values for
		# the RRD files are updated at once for a 
		# given time value (we can't update the same
		# time value, even with different DS values
		# more than once.
    my @result = ();
    foreach my $db (keys %datadb) {
      $datadb{$db}->openDB;
      @result = $datadb{$db}->insertCommit;
      $datadb{$db}->closeDB;
    }
  
    sleep($sampleRate); 
  }

  foreach my $s (keys %snmp) {
    $snmp{$s}->closeSession;
  }
}


# ################################################ #
# Sub:		measurementArchive                 #
# Args:		N/A                                #
# Purpose:	Implements the WS functionality of #
#               an MA by listening on a port for   #
#               messages and responding            #
#               accordingly.                       #
# ################################################ #
sub measurementArchive {
  my($DEBUG, $port, $endPoint) = @_;
  if($DEBUG) {
    print "Starting '".threads->tid()."' as MA on port '".$port."' and endpoint '".$endPoint."'.\n";
  }

  my $listener = new perfSONAR_PS::Transport($port, $endPoint, "", "", "");  
  $listener->startDaemon;
  
  my $responseHeader = "<nmwg:message xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\" type=\"response\">\n  ";
  my $responseFooter = "</nmwg:message>\n";
  
  my $MDId = genuid();
  my $DId = genuid();
    
  my $errorMDHeader = "<nmwg:metadata id=\"result-code-".$MDId."\">\n";
  $errorMDHeader = $errorMDHeader . "<nmwg:eventType>\n";
  my $errorMDFooter = "</nmwg:eventType>\n";
  $errorMDFooter = $errorMDFooter . "</nmwg:metadata>\n";

  my $errorDHeader = "<nmwg:data id=\"result-code-description-".$DId."\" metadataIdRef=\"result-code-".$MDId."\">\n";
  $errorDHeader = $errorDHeader . "<nmwgr:datum xmlns:nmwgr=\"http://ggf.org/ns/nmwg/result/2.0/\">\n";
  my $errorDFooter = "</nmwgr:datum>\n";  
  $errorDFooter = $errorDFooter . "</nmwg:data>\n";  
								
  while(1) {
    if($listener->acceptCall == 1) {
      
      print "REQUEST:\n" , $listener->getRequest , "\n";

      my %messagemd = ();
      my %markMessagemd = ();
      %messagemd = parse($listener->getRequest, \%messagemd, \%ns, "//nmwg:metadata");            ;
      %messagemd = chainMetadata(\%messagemd);
     
      my %messaged = ();
      %messaged = parse($listener->getRequest, \%messaged, \%ns, "//nmwg:data");      

		# remove md that were used just for 
		# chaining purposes (i.e. if a md has 
		# at least 1 data trigger, we should 
		# keep it).
      foreach my $m (keys %messagemd) {
        foreach my $d (keys %messaged) {
          if($m eq $messaged{$d}{"nmwg:data-metadataIdRef"}) {
            if($markMessagemd{$m}) {
              $markMessagemd{$m} = $markMessagemd{$m} + 1;
            }
            else {
              $markMessagemd{$m} = 1;
            }   
          }
        }
        if(!$markMessagemd{$m}) {
          delete $messagemd{$m};  
        }
      }
      
      if($DEBUG) {
        print "\n\n\n" , Dumper(%messagemd) , "\n"; 
        print "\n\n\n" , Dumper(%messaged) , "\n";
      }
      
      if($hash{"METADATA_DB_TYPE"} eq "mysql") {
        my $msg = "'METADATA_DB_TYPE' of '".$hash{"METADATA_DB_TYPE"}."' is not yet supported.";
    	printError($LOGFILE, $msg);

	my $response = $listener->makeEnvelope($responseHeader.$errorMDHeader."error.mp.snmp".$errorMDFooter.$errorDHeader."Internal Database Error.".$errorDFooter.$responseFooter);
	$listener->setResponse($response);  
      }
      elsif($hash{"METADATA_DB_TYPE"} eq "xmldb") {  

        my $responseString = "";

		# Now we only want to return results for data
		# elements, look at each one, and match it's
		# md reference to the store.	If we get a total/
		# partial match, we are good.
	my $qs = "/nmwg:metadata[";
	my $qf = 0;
        foreach my $d (keys %messaged) {
          my @mdid = ();
	  foreach my $m (keys %messagemd) {
	    if($messaged{$d}{"nmwg:data-metadataIdRef"} eq $m) {
	      
	      	# handle the time parameters for the data section
              my $start = "";
	      my $end = "";
	      foreach my $m2 (keys %{$messagemd{$m}}) {
	        if($m2 =~ m/^.*select:parameter-time-gte$/) {
                  $start = $messagemd{$m}{$m2};
		}
		elsif($m2 =~ m/^.*select:parameter-time-gt$/) {
                  $start = $messagemd{$m}{$m2}+1;
		}
		elsif($m2 =~ m/^.*select:parameter-time-lte$/) {
		  $end = $messagemd{$m}{$m2};
		}
		elsif($m2 =~ m/^.*select:parameter-time-lt$/) {
		  $end = $messagemd{$m}{$m2}+1;
		}
		elsif($m2 =~ m/^.*select:parameter-time-eq$/) {
                  $start = $messagemd{$m}{$m2};
		  $end = $messagemd{$m}{$m2};
		}				
              }	      
	      
	      	# ifAddress/type are handled special for now
		# this needs to change in the future ...
	      my $ifAddressType = "";
              my $ifAddress = "";
	      my $disp = "";  
	      foreach my $m2 (keys %{$messagemd{$m}}) {
	        if($m2 =~ m/^.*ifAddress$/) {
                  $ifAddress = $messagemd{$m}{$m2};	        
	          $disp = $m2;
	          $disp =~ s/nmwg:metadata\///;  
		}
	        elsif($m2 =~ m/^.*ifAddress-type$/) {
                  $ifAddressType = $messagemd{$m}{$m2};
	          $disp = $m2;
	          $disp =~ s/nmwg:metadata\///; 
	          $disp =~ s/-type//; 
	        }
	      }
	    
	      if($ifAddress) {
	        $qs = $qs . $disp . "[text()='" . $ifAddress;
	        if($ifAddressType) {
	          $qs = $qs . "' and \@type='" . $ifAddressType . "']";
		}
	        else {
	          $qs = $qs . "']";
		}	 
		$qf++;     
	      }
	      else {
	        if($ifAddressType) {
	          $qs = $qs . $disp . "[\@type='" . $ifAddressType . "']";
		  $qf++;
		}
	      }
	    
		# everything else that is not an id, a parameter,
		# or the ifAddress...
	      foreach my $m2 (keys %{$messagemd{$m}}) {
	        if(!($m2 =~ m/^.*parameter.*$/) &&
	           !($m2 =~ m/^.*-id$/) &&
	           !($m2 =~ m/^.*-metadataIdRef$/) &&
		   !($m2 =~ m/^.*ifAddress.*$/)) {
		 
	          my $disp = $m2;
	          $disp =~ s/nmwg:metadata\///;
	          my @attr = split(/-/, $m2);

	          if(!($qf)) {
	            if($#attr) {
	              $disp =~ s/-.*//;
	              $qs = $qs . $disp . "[\@" . $attr[1] . "='" . $messagemd{$m}{$m2} . "']";
	            }
	            else {
	              $qs = $qs . $disp . "[text()='" . $messagemd{$m}{$m2} . "']";
	            }
	            $qf++;
	          }
	          else {
	            if($#attr) {
	              $disp =~ s/-.*//;
	              $qs = $qs . " and " . $disp . "[\@" . $attr[1] . "='" . $messagemd{$m}{$m2} . "']";
	            }
	            else {
	              $qs = $qs . " and " . $disp . "[text()='" . $messagemd{$m}{$m2} . "']";
	            }
	          }
	        }
	      }
	      $qs = $qs . "]/\@id";
	      
	      my $metadatadb = new perfSONAR_PS::DB::XMLDB(
                $hash{"METADATA_DB_NAME"}, 
                $hash{"METADATA_DB_FILE"},
                \%ns
              );

              $metadatadb->openDB;              
	      my @resultsString = $metadatadb->query($qs);   
	      if($#resultsString != -1) {    
                for(my $x = 0; $x <= $#resultsString; $x++) {	
                  $resultsString[$x] =~ s/\{\}id=//;
                  $resultsString[$x] =~ s/\"//g;
                  $resultsString[$x] =~ s/\n//;
		  		  		  
                  $qs = "/nmwg:data[\@metadataIdRef='".$resultsString[$x]."']";
                  my @dataResultsString = $metadatadb->query($qs);
	          if($#dataResultsString != -1) {    
		  
                    $qs = "/nmwg:metadata[\@id='".$resultsString[$x]."']";
                    my @metadataResultsString = $metadatadb->query($qs);		  
		    if($DEBUG) {
		      print $metadataResultsString[0] , "\n";
                    }		  
		    $responseString = $responseString . $metadataResultsString[0]; 		  
		  
                    my %dresults = ();
		    for(my $y = 0; $y <= $#dataResultsString; $y++) {		  
	              print $dataResultsString[$y] , "\n";
		      %dresults = parse($dataResultsString[$x], \%dresults, \%ns, "//nmwg:data");  
		      foreach my $r (keys %dresults) {

                        my $datadb = new perfSONAR_PS::DB::RRD(
                          $hash{"DATA_DB_NAME"} , 
                          $dresults{$r}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-file"},
                          "",
                          1
                        );
		      
                        $datadb->openDB();
                        my %rrd_result = $datadb->query(
                          "AVERAGE", 
                          "", 
                          $start, 
                          $end
                        );
                        if($datadb->getErrorMessage()) {
                          print "Query Error: " , $datadb->getErrorMessage() , "; query returned: " , $rrd_result{ANSWER} , "\n";
                        }
                        else {
                          my @keys = keys(%rrd_result);
			  $responseString = $responseString . "  <nmwg:data id=\"".$DId."\" metadataIdRef=\"".$resultsString[$x]."\">\n";
                          foreach $a (sort(keys(%rrd_result))) {
                            foreach $b (sort(keys(%{$rrd_result{$a}}))) {
			      if($b eq $dresults{$r}{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-dataSource"}) {
                                if($DEBUG) {
				  print $a , "\t-->" , $rrd_result{$a}{$b} , "<--\n"; 
                                }
				$responseString = $responseString . "    <nmwg:datum time=\"".$a."\" value=\"".$rrd_result{$a}{$b}."\"/>\n";
			      }
			    }
			    if($DEBUG) {
                              print "\n";
                            }
			  }
			  $responseString = $responseString . "  </nmwg:data>\n";
                        }
			$datadb->closeDB();	
		      }
		    }
		  }
                  else {
                    printError($LOGFILE, "XMLDB returned 0 results for data search.");  
                  }
	        }
              }
              else {
                printError($LOGFILE, "XMLDB returned 0 results for metadata search.");  
              }
	    }
 	  }
        }


	my $response = "";
	if($responseString) {
	  $response = $listener->makeEnvelope($responseHeader.$responseString.$responseFooter);
	}
	else {
	  $response = $listener->makeEnvelope($responseHeader.$errorMDHeader."error.mp.snmp".$errorMDFooter.$errorDHeader."No Results Returned.".$errorDFooter.$responseFooter);
	}
	$listener->setResponse($response); 
      }
      elsif($hash{"METADATA_DB_TYPE"} eq "file") {      
        my $msg = "'METADATA_DB_TYPE' of '".$hash{"METADATA_DB_TYPE"}."' is not yet supported.";
    	printError($LOGFILE, $msg);

	my $response = $listener->makeEnvelope($responseHeader.$errorMDHeader."error.mp.snmp".$errorMDFooter.$errorDHeader."Internal Database Error.".$errorDFooter.$responseFooter);
	$listener->setResponse($response); 
      }
      else {
        my $msg = "'METADATA_DB_TYPE' of '".$hash{"METADATA_DB_TYPE"}."' is not yet supported.";
    	printError($LOGFILE, $msg);
	
	my $response = $listener->makeEnvelope($responseHeader.$errorMDHeader."error.mp.snmp".$errorMDFooter.$errorDHeader."Internal Database Error.".$errorDFooter.$responseFooter);
	$listener->setResponse($response);     
      }      
    }
    else {
      my $msg = "Sent Request has was not expected: ".
                 $listener->{REQUEST}->uri.", ".$listener->{REQUEST}->method.", ".
		 $listener->{REQUEST}->headers->{"soapaction"}.".";
      printError($LOGFILE, $msg); 
      my $response = $listener->makeEnvelope($responseHeader.$errorMDHeader."error.transport.soap".$errorMDFooter.$errorDHeader.$msg.$errorDFooter.$responseFooter);
      $listener->setResponse($response); 		 	  
    }
    $listener->closeCall;
  }
  return;
}



# ################################################ #
# Sub:		registerLS                         #
# Args:		N/A                                #
# Purpose:	Periodically registers with a      #
#               specified LS instance.             #
# ################################################ #
sub registerLS {
  my($DEBUG, $registerRate, $lsInstance) = @_;
  if($DEBUG) {
    print "Starting '".threads->tid()."' as to register with LS '".$lsInstance."'.\n";
  }
  return
}







# ################################################ #
# Sub:		daemonize                          #
# Args:		N/A                                #
# Purpose:	Background process		   #
# ################################################ #
sub daemonize {
  chdir '/' or die "Can't chdir to /: $!";
  open STDIN, '/dev/null' or die "Can't read /dev/null: $!";
  open STDOUT, '>>/dev/null' or die "Can't write to /dev/null: $!";
  open STDERR, '>>/dev/null' or die "Can't write to /dev/null: $!";
  defined(my $pid = fork) or die "Can't fork: $!";
  exit if $pid;
  setsid or die "Can't start a new session: $!";
  umask 0;
}



# ################################################ #
# Sub:		readValues                         #
# Args:		$sent - flattened hash of          #
#                       structure values passed    #
#                       through the recursion.     #
# Purpose:	Process each 'xpath' block in the  #
#               xmldb store.                       #
# ################################################ #
sub readValues {
  my($sent, $sentns, $xpath) = @_;
  my %struct = %{$sent};
  my %ns = %{$sentns};
  
  if($hash{"METADATA_DB_TYPE"} eq "mysql") {
    my $msg = "'METADATA_DB_TYPE' of '".$hash{"METADATA_DB_TYPE"}."' is not yet supported.";
    printError($LOGFILE, $msg);
    exit(1);  
  }
  elsif($hash{"METADATA_DB_TYPE"} eq "xmldb") {  
    my $metadatadb = new perfSONAR_PS::DB::XMLDB(
      $hash{"METADATA_DB_NAME"}, 
      $hash{"METADATA_DB_FILE"},
      \%ns
    );

    $metadatadb->openDB;
    my @resultsString = $metadatadb->query($xpath);   
    if($#resultsString != -1) {    
      for(my $x = 0; $x <= $#resultsString; $x++) {	
        %struct = parse($resultsString[$x], \%struct, \%ns, $xpath);
      }
    }
    else {
      printError($LOGFILE, "XMLDB returned 0 results.");  
      exit(1);
    }  
  }
  elsif($hash{"METADATA_DB_TYPE"} eq "file") {
    my $xml = readXML($hash{"METADATA_DB_FILE"});
    %struct = parse($xml, \%struct, \%ns, $xpath);
  }
  else {
    printError($LOGFILE, "'METADATA_DB_TYPE' of '".$hash{"METADATA_DB_TYPE"}."' is invalid.");
    exit(1);     
  }
  
  return %struct;
}



# ################################################ #
# Sub:		removeMetadata                     #
# Args:		$sentmd - flattened hash of md     #
#                       values.                    #
#               $metadataIdRef - ref to a data     #
#                                block             #
# Purpose:	Find the metadata block for a      #
#               given data block, and return the   #
#               ID value.                          #
# ################################################ #
sub removeMetadata {
  my($sentmd, $metadataIdRef) = @_;
  my %metadata = %{$sentmd};
  foreach my $m (keys %metadata) {
    if($m eq $metadataIdRef) {
      return $m;      
    }
  }
  return 0;
}
