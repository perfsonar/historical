#!/usr/bin/perl -w

use strict;
use warnings;

=head1 NAME

pinger_cache.pl - Build a pinger cache of information from the global gLS infrastructure 
                   and store it as json data structure

=head1 DESCRIPTION

Contact the gLS's to gain a list of hLS instances (for now double up to be sure
we get things that may not have spun yet).  After this, contact each and get a
list of services.  Then contact each PingEr MA and get all metadata details and store it on disk.

=cut

use FindBin qw($RealBin);
my $basedir = "$RealBin/";
use lib "$RealBin/../lib";

use XML::LibXML;
use Carp;
use Getopt::Long;
use Data::Dumper;
use Data::Validate::IP qw(is_ipv4);
use Data::Validate::Domain qw( is_domain );
use Net::IPv6Addr;
use Net::CIDR;
use JSON::XS;
use File::Copy;
use perfSONAR_PS::Client::PingER; 
use English;
use perfSONAR_PS::Utils::DNS qw/reverse_dns resolve_address/;


use perfSONAR_PS::Common qw( extract find unescapeString escapeString );
use perfSONAR_PS::Client::gLS;

my $DEBUGFLAG   = q{};
my $HELP        = q{};

my $status = GetOptions(
    'verbose'   => \$DEBUGFLAG,
    'help'      => \$HELP
);

if ( $HELP ) {
    print "$0: starts the gLS cache script.\n";
    print "\t$0 [--verbose --help]\n";
    exit(1);
}

my $parser = XML::LibXML->new();
my $hints  = "http://www.perfsonar.net/gls.root.hint";

my @private_list = ( "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16" );

my $base   = "/var/lib/perfsonar/";

my %hls = ();
my %matrix1 = ();
my %matrix2 = ();
my %dns_cache =();
my $gls = perfSONAR_PS::Client::gLS->new( { url => $hints } );

croak "roots not found" unless ( $#{ $gls->{ROOTS} } > -1 );

for my $root ( @{ $gls->{ROOTS} } ) {
    print "Root:\t" , $root , "\n" if $DEBUGFLAG;
    my $result = $gls->getLSQueryRaw(
        {
            ls => $root,
            xquery => "declare namespace perfsonar=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/\";\n declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"; \ndeclare namespace psservice=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/\";\n/nmwg:store[\@type=\"LSStore\"]/nmwg:metadata[./perfsonar:subject/psservice:service/psservice:serviceType[text()=\"LS\" or text()=\"hLS\" or text()=\"ls\" or text()=\"hls\"]]"
        }
    );
    if ( exists $result->{eventType} and not( $result->{eventType} =~ m/^error/ ) ) {
        print "\tEventType:\t" , $result->{eventType} , "\n" if $DEBUGFLAG;
        my $doc = $parser->parse_string( $result->{response} ) if exists $result->{response};
        my $service = find( $doc->getDocumentElement, ".//*[local-name()='service']", 0 );

        foreach my $s ( $service->get_nodelist ) {

            my $accessPoint = extract( find( $s, ".//*[local-name()='accessPoint']", 1 ), 0 );
            my $serviceName = extract( find( $s, ".//*[local-name()='serviceName']", 1 ), 0 );
            my $serviceType = extract( find( $s, ".//*[local-name()='serviceType']", 1 ), 0 );
            my $serviceDescription = extract( find( $s, ".//*[local-name()='serviceDescription']", 1 ), 0 );

            if ( $accessPoint ) {
                print "\t\thLS:\t" , $accessPoint , "\n" if $DEBUGFLAG;
                my $test = $accessPoint;
                $test =~ s/^http:\/\///;
                my ( $unt_test ) = $test =~ /^(.+):/;
                if ( $unt_test and is_ipv4( $unt_test ) ) {
                    if ( Net::CIDR::cidrlookup( $unt_test, @private_list ) ) {
                        print "\t\t\tReject:\t" , $unt_test , "\n" if $DEBUGFLAG;
                    }
                    else {
                        $hls{$accessPoint}{"INFO"} = $accessPoint."|".$serviceName."|".$serviceType."|".$serviceDescription;
                        $matrix1{$root}{$accessPoint} = 1;
                    }
                }
                elsif ( $unt_test and &Net::IPv6Addr::is_ipv6( $unt_test ) ) {
                    # do noting (for now)
                    $hls{$accessPoint}{"INFO"} = $accessPoint."|".$serviceName."|".$serviceType."|".$serviceDescription;
                    $matrix1{$root}{$accessPoint} = 1;
                }
                else {
                    if ( is_domain( $unt_test ) ) {
                        if ( $unt_test =~ m/^localhost/ ) {
                            print "\t\t\tReject:\t" , $unt_test , "\n" if $DEBUGFLAG;
                        }
                        else {
                            $hls{$accessPoint}{"INFO"} = $accessPoint."|".$serviceName."|".$serviceType."|".$serviceDescription;
                            $matrix1{$root}{$accessPoint} = 1;
                        }  
                    }
                    else {
                        print "\t\t\tReject:\t" , $unt_test , "\n" if $DEBUGFLAG;
                    }
                }
            }
        }
    }
    else {
        if ( $DEBUGFLAG ) {
            print "\tResult:\t" , Dumper($result) , "\n";
        }
    }
}

print "\n" if $DEBUGFLAG;

my %list = ();
my %dups = ();
foreach my $h ( keys %hls ) {
    print "hLS:\t" , $h , "\n" if $DEBUGFLAG;

    my $ls = new perfSONAR_PS::Client::LS( { instance => $h } );
    my $result = $ls->queryRequestLS(
        {
            query     => "declare namespace perfsonar=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/\";\n declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"; \ndeclare namespace psservice=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/\";\n/nmwg:store[\@type=\"LSStore\"]\n",
            eventType => "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/discovery/xquery/2.0",
            format    => 1
        }
    );

    if ( exists $result->{eventType} and $result->{eventType} eq "error.ls.query.ls_output_not_accepted" ) {
        # java hLS case...

        # XXX: JZ 10/13
        #
        # Need to use this eT:
        #
        # http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/discovery/xquery/2.0

        $result = $ls->queryRequestLS(
            {
                query     => "declare namespace perfsonar=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/\";\n declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"; \ndeclare namespace psservice=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/\";\n/nmwg:store[\@type=\"LSStore\"]\n",
                eventType => "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/discovery/xquery/2.0"
            }
        );
    }
    
    if ( exists $result->{eventType} and not( $result->{eventType} =~ m/^error/ ) ) {
        print "\tEventType:\t" , $result->{eventType} , "\n" if $DEBUGFLAG;
        $result->{response} = unescapeString( $result->{response} );
        my $doc;
	eval {
            $doc = $parser->parse_string( $result->{response} ) if exists $result->{response};
        };
        if($EVAL_ERROR) {
	   print "This hls $h failed, skipping";
           next;
        }
        my $md = find( $doc->getDocumentElement, "./nmwg:store/nmwg:metadata", 0 );
        my $d  = find( $doc->getDocumentElement, "./nmwg:store/nmwg:data",     0 );
        my %keyword_hash = ();
        foreach my $m1 ( $md->get_nodelist ) {
            my $id = $m1->getAttribute("id");            
            my $contactPoint = extract( find( $m1, "./*[local-name()='subject']//*[local-name()='accessPoint']", 1 ), 0 );
            unless ( $contactPoint ) {
                $contactPoint = extract( find( $m1, "./*[local-name()='subject']//*[local-name()='address']", 1 ), 0 );
                next unless $contactPoint;
            }
            my $serviceName = extract( find( $m1, "./*[local-name()='subject']//*[local-name()='serviceName']", 1 ), 0 );
            unless ( $serviceName ) {
                $serviceName = extract( find( $m1, "./*[local-name()='subject']//*[local-name()='name']", 1 ), 0 );
            }
            my $serviceType = extract( find( $m1, "./*[local-name()='subject']//*[local-name()='serviceType']", 1 ), 0 );
            unless ( $serviceType ) {
                $serviceType = extract( find( $m1, "./*[local-name()='subject']//*[local-name()='type']", 1 ), 0 );
            }
            my $serviceDescription = extract( find( $m1, "./*[local-name()='subject']//*[local-name()='serviceDescription']", 1 ), 0 );
            unless ( $serviceDescription ) {
                $serviceDescription = extract( find( $m1, "./*[local-name()='subject']//*[local-name()='description']", 1 ), 0 );
            }
            foreach my $d1 ( $d->get_nodelist ) {
                my $metadataIdRef = $d1->getAttribute("metadataIdRef");
                next unless $id eq $metadataIdRef;
                # get the keywords
                my $keywords = find( $d1, "./nmwg:metadata/summary:parameters/nmwg:parameter", 0 );		
                foreach my $k ( $keywords->get_nodelist ) {
                    my $name = $k->getAttribute("name");
                    next unless $name eq "keyword";
                    my $value = extract( $k, 0 );
                    $keyword_hash{$value} = 1 if ( $value );
                }
                # get the eventTypes
                my $eventTypes = find( $d1, "./nmwg:metadata/nmwg:eventType", 0 );
		my @found_keywords = keys %keyword_hash; 
                foreach my $e ( $eventTypes->get_nodelist ) {
                    my $value = extract( $e, 0 );
                    if ( $value ) {
                        if ( $value eq "http://ggf.org/ns/nmwg/tools/pinger/2.0/" ||
			     $value eq "http://ggf.org/ns/nmwg/tools/pinger/2.0"  ) {
                            $value = "http://ggf.org/ns/nmwg/tools/pinger/2.0";
                        }                       
# we should be tracking things here, eliminate duplicates
                        unless ( exists $dups{$value}{$contactPoint} and $dups{$value}{$contactPoint} ) {
                            $dups{$value}{$contactPoint} = 1;
                            $matrix2{$h}{$contactPoint} = 1;

                            if ( exists $list{$value} ) {
                                push @{ $list{$value} }, { CONTACT => $contactPoint, NAME => $serviceName, TYPE => $serviceType, KEYWORDS => \@found_keywords,
				                           DESC => $serviceDescription };
                            }
                            else {
                                my @temp = ( { CONTACT => $contactPoint, NAME => $serviceName, TYPE => $serviceType, KEYWORDS => \@found_keywords, DESC => $serviceDescription } );
                                $list{$value} = \@temp;
                            }
                        }
                    }
                }
		push @{ $list{'http://ggf.org/ns/nmwg/tools/pinger/2.0'} }, { CONTACT =>  'http://lhc-dmz-latency.deemz.net:8075/perfSONAR_PS/services/pinger/ma', 
		                                                              KEYWORDS => [ qw/LHC LHCOPN USCMS/],
		                                                              NAME => 'PingER MA', TYPE => 'MA', 
									      DESC => 'Fermilab Tier-1 USCMS in Batavia, IL, public access' };
                push @{ $list{'http://ggf.org/ns/nmwg/tools/pinger/2.0'} }, { CONTACT =>  'http://lhc-cms-latency.fnal.gov:8075/perfSONAR_PS/services/pinger/ma', 
		                                                             KEYWORDS => [ qw/LHC LHCOPN USCMS/],
		                                                              NAME => 'PingER MA', TYPE => 'MA', 
									      DESC => 'Fermilab Tier-1 USCMS in Batavia, IL, local or LHCOPN only access' };
               last;   		 
            }
        }
        
        # store the keywords
        $hls{$h}{"KEYWORDS"} = \%keyword_hash;    
    }
    else {
        delete $hls{$h};
        if ( $DEBUGFLAG ) {
            print "\tResult:\t" , Dumper($result) , "\n";
        }
    }
}

open( FILE, ">" . $base . "/list.glsmap" ) or croak "can't open glsmap list";
foreach my $g ( keys %matrix1 ) {
    print FILE $g;
    my $counter = 0;
    foreach my $h ( keys %{ $matrix1{ $g } } ) {
        if ( $counter ) {
            print FILE "," , $h;
        }
        else {
            print FILE "|" , $h;
        }
        $counter++;
    }
    print FILE "\n";
}
close(FILE);

open( FILE2, ">" . $base . "/list.hlsmap" ) or croak "can't open hls list";
foreach my $h ( keys %matrix2 ) {
    print FILE2 $h;
    my $counter = 0;
    foreach my $s ( keys %{ $matrix2{ $h } } ) {
        if ( $counter ) {
            print FILE2 "," , $s;
        }
        else {
            print FILE2 "|" , $s;
        }
        $counter++;
    }
    print FILE2 "\n";
}
close(FILE2);

# should we do some verification/validation here?
open( HLS, ">" . $base . "/list.hls" ) or croak "can't open hls list";
foreach my $h ( keys %hls ) {
    print HLS $hls{$h}{"INFO"};
    if ( exists $hls{$h}{"KEYWORDS"} and $hls{$h}{"KEYWORDS"} ) {
        my $counter = 0;
        foreach my $k ( keys %{ $hls{$h}{"KEYWORDS"} } ) {
            if( $counter ) {
                print HLS "," , $k;
            }
            else {
                print HLS "|" , $k;
            }
            $counter++;
        }
    }
    print HLS "\n";
}
close(HLS);

my %counter = ();
my %lookup_url = ();
foreach my $et ( keys %list ) {
    my $file = q{};
    if ( $et eq "http://ggf.org/ns/nmwg/tools/pinger/2.0/" or $et eq "http://ggf.org/ns/nmwg/tools/pinger/2.0" ) {
        $file = "list.pinger";
    }
    next unless $file;

    my $writetype = ">";
    $writetype = ">>" if exists $counter{$file};
    $counter{$file} = 1;

    my @results_json = ();
    my $print_string = ''; 
    foreach my $host ( @{ $list{$et} } ) {
        next if $lookup_url{$host->{CONTACT}};
	$lookup_url{$host->{CONTACT}}++;     
	my $metaids = {};
	eval {
            my $ma = new perfSONAR_PS::Client::PingER( { instance =>  $host->{CONTACT}} );
	    print " MA  $host->{CONTACT}  connected: " . Dumper $ma;
            my $result = $ma->metadataKeyRequest();
	    print ' result from ma: ' . Dumper $result; 
	    $metaids = $ma->getMetaData($result);
	};
	if($EVAL_ERROR) {
	   croak(" Problem with MA $EVAL_ERROR ");
	}
        print ' Metaids: ' . Dumper $metaids; 
	#
	#   this is how $meta  looks like:
	#
	# 'lhc-dmz-latency.deemz.net:tier2.ihepa.ufl.edu:1000' => {
        #  	  'keys' => [
        #  		      '13'
        #  		    ],
        #  	  'packetSize' => '1000',
        #  	  'dst_name' => 'tier2.ihepa.ufl.edu',
        #  	  'src_name' => 'lhc-dmz-latency.deemz.net',
        #  	  'metaIDs' => [
        #  			 'meta9'
        #  		       ]
        #  	}

        foreach  my $meta  (keys %{$metaids}) { 
	    if($metaids->{$meta}{src_name} =~ /^\d+\./) {
	        my $ip_address = $metaids->{$meta}{src_name}; 
		my   $dns_name;
		unless($dns_cache{$ip_address}) { 
	      	    $dns_name = reverse_dns($ip_address);
                    $dns_cache{$ip_address } = $dns_name if ($dns_name); 
	        }
		 # merge keys with correct meta if found hostname
		if($dns_cache{$ip_address}) {
		    foreach my  $meta2 (keys %{$metaids})  {
	               if($metaids->{$meta2}{src_name} eq $dns_cache{$ip_address} &&
		          $metaids->{$meta2}{dst_name} eq $metaids->{$meta}{dst_name} &&
			  $metaids->{$meta2}{packetSize} eq   $metaids->{$meta}{packetSize}) {
		          push @{$metaids->{$meta2}{keys}}, @{$metaids->{$meta}{keys}};
			  push @{$metaids->{$meta2}{metaIDs}}, @{$metaids->{$meta}{metaIDs}};
			  delete $metaids->{$meta};
			  last;
		       }
		    }
		}
	    }      
        } 
	if(%{$metaids}) {
	    my %hash_toadd = ($host->{CONTACT} => \%{$metaids});
	    $hash_toadd{name} = $host->{NAME} if $host->{NAME};  
            $hash_toadd{type} = $host->{TYPE} if $host->{TYPE};    
            $hash_toadd{desc} = $host->{DESC} if $host->{DESC};
            $hash_toadd{keywords} = $host->{KEYWORDS} if $host->{KEYWORDS} && ref $host->{KEYWORDS}  && @{$host->{KEYWORDS}};
            push  @results_json,  \%hash_toadd; 
	}
    }
    my $tmpfile = "/tmp/$file" . time();
    copy($base . "/" . $file, $tmpfile);
    open( OUT, "$writetype$tmpfile"  ) or croak "$! : can't open $tmpfile";
    print OUT encode_json \@results_json if @results_json;
    close(OUT);
    carp(" Renaming $tmpfile ->   $base$file ");
    move($tmpfile ,  $base . $file);

}

=head1 SEE ALSO

L<XML::LibXML>, L<perfSONAR_PS::Common>, L<perfSONAR_PS::Client::gLS>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS

Questions and comments can be directed to the author, or the mailing list.  Bugs,
feature requests, and improvements can be directed here:

  http://code.google.com/p/perfsonar-ps/issues/list

=head1 VERSION

$Id: $

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu
Maxim Grigoriev, AKA "the_butcher", maxim_at_fnal_gov

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework along
with this software.  If not, see <http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2008-2009, Internet2

All rights reserved.

=cut

