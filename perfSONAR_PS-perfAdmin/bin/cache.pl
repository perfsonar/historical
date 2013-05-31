#!/usr/bin/perl -w

use strict;
use warnings;

=head1 NAME

cache.pl - Build a cache of information from the global gLS infrastructure

=head1 DESCRIPTION

Contact the gLSs to gain a list of hLS instances (for now double up to be sure
we get things that may not have spun yet).  After this, contact each and get a
list of services.  Store the list in text files where they can be used by other
applications.

=cut

use XML::LibXML;
use Carp;
use Getopt::Long;
use Data::Validate::IP qw(is_ipv4);
use Data::Validate::Domain qw( is_domain );
use Net::IP;
use Net::CIDR;
use LWP::Simple;
use English qw( -no_match_vars );

use FindBin qw($RealBin);
my $basedir = "$RealBin/";
use lib "$RealBin/../lib";

use perfSONAR_PS::Common qw( extract find unescapeString escapeString );
use perfSONAR_PS::Utils::ParameterValidation;
use perfSONAR_PS::Client::Parallel::LS;

my $DEBUGFLAG = q{};
my $HELP      = q{};
my $EXP_TIME = time - 3600*24;#expire after 24 hours

my $status = GetOptions(
    'verbose' => \$DEBUGFLAG,
    'help'    => \$HELP
);

if ( $HELP ) {
    print "$0: starts the gLS cache script.\n";
    print "\t$0 [--verbose --help]\n";
    exit( 1 );
}

my %gls_mappings = ();

my $parser = XML::LibXML->new();
my $hints  = "http://www.perfsonar.net/gls.root.hints";

my @private_list = ( "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16" );

my $base =  "/var/lib/perfsonar/perfAdmin/cache";

my %hls     = ();
my %matrix1 = ();
my %matrix2 = ();
my %ma_tests     = ();

my @roots   = ();
my $content = get $hints;
if ( $content ) {
    @roots = split( /\n/, $content );
}

use Log::Log4perl qw(:easy);

my $output_level = $INFO;

my %logger_opts = (
    level  => $output_level,
    layout => '%d (%P) %p> %F{1}:%L %M - %m%n',
    file   => "/var/log/perfsonar/cache.log",
);

Log::Log4perl->easy_init( \%logger_opts );

my $logger = get_logger( "cache" );

my $gls = perfSONAR_PS::Client::Parallel::LS->new();
$gls->init();

croak "roots not found" unless ( scalar( @roots ) > 0 );

print "Number of GLS queried:", scalar @roots . "\n";
foreach my $root ( @roots ) {
    print "Trying root '" . $root . "'\n" if $DEBUGFLAG;

    # XXX
    # JZ: 7/8/09
    # Do we need to even look for a type?  Only hLS services are registered into
    #   the gLS...

    my $cookie = $gls->add_query(
        {
            url => $root,
            xquery =>
                "declare namespace perfsonar=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/\";\n declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"; \ndeclare namespace psservice=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/\";\n/nmwg:store[\@type=\"LSStore\"]/nmwg:metadata[./perfsonar:subject/psservice:service/psservice:serviceType[text()=\"LS\" or text()=\"hLS\" or text()=\"ls\" or text()=\"hls\"]]",
            event_type => "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/discovery/xquery/2.0",
            format     => 1,
            timeout    => 10,
        }
    );

    $gls_mappings{$cookie} = $root;
}

my $results = $gls->wait_all( { timeout => 60, parallelism => 8 } );
my @gls_stats = ();
print "Total GLS reponse received:" . scalar keys %{$results} . "\n";
foreach my $key ( keys %{$results} ) {
    my $response_info = $results->{$key};

    my $root = $gls_mappings{ $response_info->{cookie} };

    my $request_duration = $response_info->{request_duration};
    my $total_duration   = $response_info->{total_duration};

    $request_duration = -1 unless ( defined $request_duration );
    $total_duration   = -1 unless ( defined $total_duration );

    my $error_msg;
    unless ( $response_info->{event_type} and $response_info->{event_type} !~ m/^error/ ) {
        if ( $response_info->{event_type} ) {
            $error_msg = $response_info->{event_type};
        }
        elsif ( $response_info->{error_msg} ) {
            $error_msg = $response_info->{error_msg};
        }
        else {
            $error_msg = "Unknown error";
        }
    }
    $error_msg = q{} unless ( defined $error_msg );

    my %stats = (
        url              => $root,
        request_duration => $request_duration,
        total_duration   => $total_duration,
        error_msg        => $error_msg,
    );

    push @gls_stats, \%stats;
}

foreach my $key ( keys %{$results} ) {
    my $response_info = $results->{$key};

    # Skip any errors
    next unless ( $response_info->{event_type} and $response_info->{event_type} !~ m/^error/ );

    # Skip any bad responses
    next unless ( $response_info->{cookie} and $gls_mappings{ $response_info->{cookie} } );

    $logger->debug( "Found mapped element: " . $response_info->{cookie} . "\n" );

    my $root = $gls_mappings{ $response_info->{cookie} };

    my $response_message = $response_info->{content};

    my $service = find( $response_message, ".//*[local-name()='service']", 0 );

    $logger->debug( "Searching for Services: " . $response_message->toString . "\n" );
    foreach my $s ( $service->get_nodelist ) {
        my $accessPoint        = extract( find( $s, ".//*[local-name()='accessPoint']",        1 ), 0 );
        my $serviceName        = extract( find( $s, ".//*[local-name()='serviceName']",        1 ), 0 );
        my $serviceType        = extract( find( $s, ".//*[local-name()='serviceType']",        1 ), 0 );
        my $serviceDescription = extract( find( $s, ".//*[local-name()='serviceDescription']", 1 ), 0 );

        print "Service: " . $accessPoint . "\n" if $DEBUGFLAG;

        if ( $accessPoint ) {
            print "\t\thLS:\t" . $accessPoint . "\n" if $DEBUGFLAG;
            my $test = $accessPoint;
            $test =~ s/^http:\/\///;
            my ( $unt_test ) = $test =~ /^(.+):/;
            if ( $unt_test and is_ipv4( $unt_test ) ) {
                if ( Net::CIDR::cidrlookup( $unt_test, @private_list ) ) {
                    print "\t\t\tReject:\t" . $unt_test . "\n" if $DEBUGFLAG;
                }
                else {
                    $hls{$accessPoint}{"INFO"} = $accessPoint . "|" . $serviceName . "|" . $serviceType . "|" . $serviceDescription;
                    $matrix1{$root}{$accessPoint} = 1;
                }
            }
            elsif ( $unt_test and &Net::IP::ip_is_ipv6( $unt_test ) ) {

                # do nothing (for now)
                $hls{$accessPoint}{"INFO"} = $accessPoint . "|" . $serviceName . "|" . $serviceType . "|" . $serviceDescription;
                $matrix1{$root}{$accessPoint} = 1;
            }
            else {
                if ( is_domain( $unt_test ) ) {
                    if ( $unt_test =~ m/^localhost/ ) {
                        print "\t\t\tReject:\t" . $unt_test . "\n" if $DEBUGFLAG;
                    }
                    else {
                        $hls{$accessPoint}{"INFO"} = $accessPoint . "|" . $serviceName . "|" . $serviceType . "|" . $serviceDescription;
                        $matrix1{$root}{$accessPoint} = 1;
                    }
                }
                else {
                    print "\t\t\tReject:\t" . $unt_test . "\n" if $DEBUGFLAG;
                }
            }
        }
    }
}

print "\n Contacting hLSs\n" if $DEBUGFLAG;

my %list = ();
my %dups = ();

my $ls = perfSONAR_PS::Client::Parallel::LS->new();
$ls->init();

my %hls_results = ();
my @hlses       = keys %hls;
print "\n Number of HLS queried:" . scalar @hlses .  "\n";
$results = query_hlses( { hlses => \@hlses, event_type => "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xquery/1.0", format => 1 } );

my @java_hlses = ();

foreach my $h ( keys %{$results} ) {
    print "Trying '" . $h . "'\n" if $DEBUGFLAG;
    my $result_info = $results->{$h};
    if ( exists $result_info->{event_type} and $result_info->{event_type} eq "error.ls.query.ls_output_not_accepted" ) {
        print "\t\tskipping...\n" if $DEBUGFLAG;
        push @java_hlses, $h;
        next;
    }
    $hls_results{$h} = $results->{$h};
}

## The Java hLS doesn't like the format parameter, treat it 'special'
if ( scalar( @java_hlses ) > 0 ) {
    $results = query_hlses( { hlses => \@java_hlses, event_type => "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/discovery/xquery/2.0", format => 0 } );
    foreach my $h ( keys %{$results} ) {
        print "Trying '" . $h . "'\n" if $DEBUGFLAG;
        my $result_info = $results->{$h};
        if ( exists $result_info->{event_type} and $result_info->{event_type} =~ m/^error/ ) {
            print "\t\tskipping...\n" if $DEBUGFLAG;
            next;
        }
        else {
            $results->{$h}->{content} = unescapeString( $results->{$h}->{content}->toString );
            $hls_results{$h} = $results->{$h};
        }
    }
}

my %stats = ();

foreach my $h ( keys %hls_results ) {

    print "decoding: '" . $h . "'\n" if $DEBUGFLAG;

    my $response_info = $hls_results{$h};

    # Skip any errors
    unless ( $response_info->{event_type} and $response_info->{event_type} !~ m/^error/ ) {
        if ( $response_info->{event_type} ) {
            $logger->debug( "Response info error: $h: " . $response_info->{event_type} . "\n" );
        }
        elsif ( $response_info->{error_msg} ) {
            $logger->debug( "Response info error: $h: " . $response_info->{error_msg} . "\n" );
        }
        else {
            $logger->debug( "Response info error: $h" );
        }
        print "\tSkipping\n" if $DEBUGFLAG;
        next;
    }

    $logger->debug( "Handling $h" );

    my $response_message = $response_info->{content};

    unless ( UNIVERSAL::isa( $response_message, "SCALAR" ) ) {
        print "\tConvert to LibXML object\n" if $DEBUGFLAG;
        my $doc;
        eval { $doc = $parser->parse_string( $response_message ); };
        if ( $EVAL_ERROR ) {
            $logger->debug( "Failed to parse " . $h . ": " . $EVAL_ERROR );
            next;
        }
        $response_message = $doc->getDocumentElement;
    }

    my $md = find( $response_message, "./nmwg:store/nmwg:metadata", 0 );
    my $d  = find( $response_message, "./nmwg:store/nmwg:data",     0 );
    my %keywords = ();
    foreach my $m1 ( $md->get_nodelist ) {
        my $id = $m1->getAttribute( "id" );
        
        my @contactPoints = ();
        my $contactPoint = extract( find( $m1, "./*[local-name()='subject']//*[local-name()='accessPoint']", 1 ), 0 );
        if ( $contactPoint ) {
             push @contactPoints, $contactPoint;
        } else {
            my $contactPointElems = find( $m1, "./*[local-name()='subject']//*[local-name()='address']", 0 );
            next unless ($contactPointElems && $contactPointElems->size() > 0);
            for(my $i = 1; $i <= $contactPointElems->size(); $i++){
                push @contactPoints, extract( $contactPointElems->get_node($i) , 0);
            }
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
            my $metadataIdRef = $d1->getAttribute( "metadataIdRef" );
            next unless $id eq $metadataIdRef;

            $logger->debug( "Found matching data\n" );
            $logger->debug( "Querying for keywords and endpoints in :" . $d1->toString . "\n" );
            
            #Get get source and dest 
            my %ma_test = ();
            my @keyword_list = ();
            my $endpointpair_elem = find( $d1, "./nmwg:metadata/*[local-name()='subject']/*[local-name()='endPointPair']", 0 );
            foreach my $ep ( $endpointpair_elem->get_nodelist ) {
                my $source = find( $ep, "./*[local-name()='src']/\@value", 0 );
                my $dest = find( $ep, "./*[local-name()='dst']/\@value", 0 );
                print "Source: $source   Dest: $dest\n";
                if($source && $dest){
                   $ma_test{'source'} = $source;
                   $ma_test{'destination'} = $dest;
                }
            }
            
            # get the keywords
            my $keyword_elems = find( $d1, "./nmwg:metadata/nmwg:parameters/nmwg:parameter", 0 );
            foreach my $k ( $keyword_elems->get_nodelist ) {
                $logger->debug( "Found attribute: " . $k->getAttribute( "name" ) );
                my $name = $k->getAttribute( "name" );
                next unless $name eq "keyword";
                my $value = extract( $k, 0 );
                if ( $value ) {
                    $keywords{$value} = 1;
                    push @keyword_list, $value;
                }
                $logger->debug( "Found keyword: " . $value );
            }
            $logger->debug( "Done querying for keywords\n" );

            # get the eventTypes
            my $eventTypes = find( $d1, "./nmwg:metadata/nmwg:eventType", 0 );
            foreach my $e ( $eventTypes->get_nodelist ) {
                my $value = extract( $e, 0 );
                if ( $value ) {

                    if ( $value eq "http://ggf.org/ns/nmwg/tools/snmp/2.0" ) {
                        $value = "http://ggf.org/ns/nmwg/characteristic/utilization/2.0";
                    }
                    if ( $value eq "http://ggf.org/ns/nmwg/tools/pinger/2.0/" ) {
                        $value = "http://ggf.org/ns/nmwg/tools/pinger/2.0";
                    }
                    if ( $value eq "http://ggf.org/ns/nmwg/characteristics/bandwidth/acheiveable/2.0" or $value eq "http://ggf.org/ns/nmwg/characteristics/bandwidth/achieveable/2.0" ) {
                        $value = "http://ggf.org/ns/nmwg/characteristics/bandwidth/achievable/2.0";
                    }
                    if ( $value eq "http://ggf.org/ns/nmwg/tools/iperf/2.0" ) {
                        $value = "http://ggf.org/ns/nmwg/characteristics/bandwidth/achievable/2.0";
                    }
                    
                    # more eventTypes as needed...

                    # we should be tracking things here, eliminate duplicates
                    foreach my $cp ( @contactPoints ){
                        if($ma_test{'source'} && $ma_test{'destination'}){
                            $ma_tests{$value}{$cp}{$ma_test{'source'}}{$ma_test{'destination'}} = 1;
                        }
                        
                        unless ( exists $dups{$value}{$cp} and $dups{$value}{$cp} ) {
                            $dups{$value}{$cp} = 1;
                            $matrix2{$h}{$cp}  = 1;
    
                            if ( exists $list{$value} ) {
                                push @{ $list{$value} }, { CONTACT => $cp, NAME => $serviceName, TYPE => $serviceType, DESC => $serviceDescription, KEYWORDS => \@keyword_list, TIMESTAMP => time };
                            }
                            else {
                                my @temp = ( { CONTACT => $cp, NAME => $serviceName, TYPE => $serviceType, DESC => $serviceDescription, KEYWORDS => \@keyword_list, TIMESTAMP => time  } );
                                $list{$value} = \@temp;
                            }
    
                        }
                    }
                }
            }
            last;
        }
    }

    # store the keywords
    $hls{$h}{"KEYWORDS"} = \%keywords;
}

my @hls_stats = ();

foreach my $h ( keys %hls_results ) {
    my $response_info = $hls_results{$h};

    my $request_duration = $response_info->{request_duration};
    my $total_duration   = $response_info->{total_duration};

    $request_duration = -1 unless ( defined $request_duration );
    $total_duration   = -1 unless ( defined $total_duration );

    my $error_msg;
    unless ( $response_info->{event_type} and $response_info->{event_type} !~ m/^error/ ) {
        if ( $response_info->{event_type} ) {
            $error_msg = $response_info->{event_type};
        }
        elsif ( $response_info->{error_msg} ) {
            $error_msg = $response_info->{error_msg};
        }
        else {
            $error_msg = "Unknown error";
        }
    }
    $error_msg = q{} unless ( defined $error_msg );

    my %stats = (
        url              => $h,
        request_duration => $request_duration,
        total_duration   => $total_duration,
        error_msg        => $error_msg,
    );

    push @hls_stats, \%stats;
}

$logger->debug( "Writing files\n" );
my %cacheData = ();
if(-e $base . "/" . "/list.glsmap"){
	open( FILER, "<" . $base . "/list.glsmap" ) or croak "can't open glsmap list";
	#my %cacheData = ();
	while ( <FILER> ){
		chomp;
		my @fields = split /\|/;
		if (@fields < 3){
        		print "Invalid line in $base/list.glsmap\n";
			next;
		}
	
		if($fields[2] && $fields[2] =~ /\d+/ && $fields[2] > $EXP_TIME){
			$cacheData{ $fields[0] } = {GLSURL => $fields[0], DATA => $fields[1], TIMESTAMP => $fields[2] };
		}
	}	
	close (FILER);
}
open(FILEW, ">". $base . "/list.glsmap") or croak "can't open glsmap list"; 
foreach my $g ( keys %matrix1 ) {
    print FILEW $g;
    my $counter = 0;
    foreach my $h ( keys %{ $matrix1{$g} } ) {
        if ( $counter ) {
            print FILEW ",", $h;
        }
        else {
            print FILEW "|", $h;
        }
        $counter++;
    }
    print FILEW "|", time;
    print FILEW "\n";
    if (defined $cacheData{$g} && $cacheData{$g}){
    	delete $cacheData{$g};
    }
}

#write missing entries from cache
foreach my $cachekey (keys %cacheData){
	print FILEW $cachekey, "|", $cacheData{$cachekey}{"DATA"}, "|",$cacheData{$cachekey}{"TIMESTAMP"},"\n";
}
close( FILEW );

my %cacheData2 = ();
if(-e $base . "/" . "/list.hlsmap"){
	open( FILER2, "<" . $base . "/list.hlsmap" ) or croak "can't open hls list";
	#my %cacheData2 = ();
	while ( <FILER2> ){
        	chomp;
        	my @fields = split /\|/;
        	if (@fields < 3){
                	print "Invalid line in $base/list.glsmap\n";
                	next;
        	}

        	if($fields[2] && $fields[2] =~ /\d+/ && $fields[2] > $EXP_TIME){
                	$cacheData2{ $fields[0] } = {GLSURL => $fields[0], DATA => $fields[1], TIMESTAMP => $fields[2] };
        	}
	}	
	close (FILER2);
}
#write hls data to file
open( FILEW2, ">" . $base . "/list.hlsmap" ) or croak "can't open hls list";
foreach my $h ( keys %matrix2 ) {
    print FILEW2 $h;
    my $counter = 0;
    foreach my $s ( keys %{ $matrix2{$h} } ) {
        if ( $counter ) {
            print FILEW2 ",", $s;
        }
        else {
            print FILEW2 "|", $s;
        }
        $counter++;
    }
    print FILEW2 "|", time;
    print FILEW2 "\n";
    if (defined $cacheData2{$h} && $cacheData2{$h}){
        delete $cacheData2{$h};
    }
}
#write missing entries from cache
foreach my $cachekey (keys %cacheData2){
    print FILEW2 $cachekey, "|", $cacheData2{$cachekey}{"DATA"}, "|",$cacheData2{$cachekey}{"TIMESTAMP"},"\n";
}
close( FILEW2 );

open( FILE3, ">" . $base . "/list.glsstats" ) or croak "can't open glsstats list";
foreach my $stat ( @gls_stats ) {
    print FILE3 $stat->{url} . "," . $stat->{request_duration} . "," . $stat->{total_duration} . "," . $stat->{error_msg} . "\n";
}
close( FILE3 );

open( FILE4, ">" . $base . "/list.hlsstats" ) or croak "can't open glsstats list";
foreach my $stat ( @hls_stats ) {
    print FILE4 $stat->{url} . "," . $stat->{request_duration} . "," . $stat->{total_duration} . "," . $stat->{error_msg} . "\n";
}
close( FILE4 );

#cache hls
if( -e $base . "/list.hls"){
    open( HLS, "<" . $base . "/list.hls" ) or croak "can't open hls list";
    while( <HLS> ){
        chomp;
        my @fields = split /\|/;
        if( @fields < 4 ){
            next;
        }
        if($#fields != 5 || $fields[5] < $EXP_TIME){
            next;
        }
        if(!defined $hls{$fields[0]}){
            print $fields[0] . "(cached)\n";
            my %tmpInfo = (
                "INFO" => ($fields[0] . "|" . $fields[1] . "|" . $fields[2] . "|" . $fields[3]),
            );
            
            $hls{ $fields[0] } = \%tmpInfo;
        }
    }
    close HLS;
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
        $hls{$fields[0]}{"KEYWORDS"}{$fields[1]} = 1;
        print "Cached Keyword: " . $fields[0] . " -> " . $fields[1] . "\n";
    }
    close KEYWORDS;
}

# should we do some verification/validation here?
open( KEYWORDS, ">" . $base . "/list.keywords" ) or croak "can't open keyword list";
open( HLS, ">" . $base . "/list.hls" ) or croak "can't open hls list";
foreach my $h ( keys %hls ) {
    print HLS $hls{$h}{"INFO"};
    
    print HLS "|";
    if ( exists $hls{$h}{"KEYWORDS"} and $hls{$h}{"KEYWORDS"} ) {
        my $counter = 0;
        foreach my $k ( keys %{ $hls{$h}{"KEYWORDS"} } ) {
            print KEYWORDS "$h|$k|" . time . "\n";
            if ( $counter ) {
                print HLS ",", $k;
            }
            else {
                print HLS $k;
            }
            $counter++;
        }
    }
    print HLS "|", time;
    print HLS "\n";
}
close( KEYWORDS );
close( HLS );

#read in cached MA tests
if( -e $base . "/list.ma_tests"){
    open (MATEST, "<" . $base . "/list.ma_tests");
    while( <MATEST> ){
        chomp;
        my @fields = split /\|/;
        if( @fields != 5 ){
            next;
        }
        if($ma_tests{$fields[0]}{$fields[1]}{$fields[2]}{$fields[3]}){
            next;
        }
        if($fields[4] < $EXP_TIME){
            next;
        }
        $ma_tests{$fields[0]}{$fields[1]}{$fields[2]}{$fields[3]} = $fields[4];
    }
    close MATEST;
}

#write ma tests
open (MATEST, ">" . $base . "/list.ma_tests");
foreach my $et(keys %ma_tests){
    foreach my $cp(keys %{$ma_tests{$et}}){
        foreach my $src(keys %{$ma_tests{$et}{$cp}}){
            foreach my $dst(keys %{$ma_tests{$et}{$cp}{$src}}){
                $ma_tests{$et}{$cp}{$src}{$dst} = time if($ma_tests{$et}{$cp}{$src}{$dst} == 1);
                print MATEST "$et|$cp|$src|$dst|" . $ma_tests{$et}{$cp}{$src}{$dst} . "\n";
            }
        }
    }
}
close MATEST;



my %file_service_tracker = ();
my %counter = ();
foreach my $et ( keys %list ) {
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
    foreach my $host ( @{ $list{$et} } ) {
        if(defined $cached_hosts{ $host->{"CONTACT"} } && $cached_hosts{ $host->{"CONTACT"} }){
            delete $cached_hosts{ $host->{"CONTACT"} };
        }
        if(exists $file_service_tracker{$host->{"CONTACT"} . $file}){
            next;
        }
        $file_service_tracker{$host->{"CONTACT"} . $file} = 1;
        print OUT $host->{"CONTACT"}, "|";
        print OUT $host->{"NAME"} if $host->{"NAME"};
        print OUT "|";
        print OUT $host->{"TYPE"} if $host->{"TYPE"};
        print OUT "|";
        print OUT $host->{"DESC"} if $host->{"DESC"};
        print OUT "|";
        my $first_kw = 1;
        foreach my $kw(@{ $host->{"KEYWORDS"} }){
            if($first_kw){
                $first_kw = 0;
            }else{
                print OUT ",";
            }
            print OUT $kw;
        }
        print OUT "|";
        print OUT $host->{"TIMESTAMP"} if $host->{"TIMESTAMP"};
        print OUT "\n";
        print $file , " - ", $host->{"CONTACT"}, "\n";
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

sub query_hlses {
    my $args = validateParams(
        @_,
        {
            hlses      => 1,
            event_type => 1,
            format     => 1,
        }
    );

    my %mappings = ();

    foreach my $h ( @{ $args->{hlses} } ) {
        my $cookie = $ls->add_query(
            {
                url    => $h,
                xquery => "declare namespace perfsonar=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/\";\n declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"; \ndeclare namespace psservice=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/\";\n/nmwg:store[\@type=\"LSStore\"]\n",
                event_type => $args->{event_type},
                format     => $args->{format},
                timeout    => 15,
            }
        );

        $mappings{$cookie} = $h;
    }

    my $results = $ls->wait_all( { timeout => 220, parallelism => 16 } );
    print "\nReturned HLS results:", scalar keys %{$results};
    my %ret_results = ();
    foreach my $key ( keys %{$results} ) {
        my $response_info = $results->{$key};
        
        # Skip any bad responses
        next unless ( $response_info->{cookie} and $mappings{ $response_info->{cookie} } );

        my $h = $mappings{ $response_info->{cookie} };

        $ret_results{$h} = $response_info;
    }

    return \%ret_results;
}

=head1 SEE ALSO

L<XML::LibXML>, L<Carp>, L<Getopt::Long>, L<Data::Validate::IP>,
L<Data::Validate::Domain>, L<Net::IP>, L<Net::CIDR>, L<LWP::Simple>,
L<FindBin>, L<perfSONAR_PS::Common>, L<perfSONAR_PS::Client::gLS>,
L<perfSONAR_PS::Utils::ParameterValidation>,
L<perfSONAR_PS::Client::Parallel::LS>

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

Jason Zurawski, zurawski@internet2.edu
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

Copyright (c) 2008-2010, Internet2

All rights reserved.

=cut

