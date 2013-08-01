package perfSONAR_PS::Services::MP::TracerouteTest;

use strict;
use warnings;

our $VERSION = 3.3;
use Data::Validate::IP qw(is_ipv4 is_ipv6);
use File::Copy qw(move);
use File::Temp qw(tempfile);
use Net::DNS;
use XML::LibXML;
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Common;
use perfSONAR_PS::Client::MA;
use perfSONAR_PS::Services::MP::NetTraceroute;
use perfSONAR_PS::Utils::NetLogger;
use perfSONAR_PS::Utils::ParameterValidation;

use fields 'LOGGER','NETLOGGER', 'TRACE_PARAMS', 'TEST_INTERVAL', 'LAST_RUNTIME', 'DATADIR', 'METADATA', 'METADATA_ID';

use constant NMWG_NS => 'http://ggf.org/ns/nmwg/base/2.0/';
use constant TRACEROUTE_NS => 'http://ggf.org/ns/nmwg/tools/traceroute/2.0/';
use constant NMWGT_NS => 'http://ggf.org/ns/nmwg/topology/2.0/';
use constant TRACEROUTE_PREFIX => 'traceroute';
use constant NMWG_PREFIX => 'nmwg';
use constant NMWGT_PREFIX => 'nmwgt';
use constant PARAM_MAP => { 'firstTtl' => 'first_hop' , 'maxTtl' => 'max_ttl', 'waitTime' => 'query_timeout', 'pause' => 'pause', 'packetSize' => 'packetlen' };
                
sub new {
    my ( $class, $test_int, $datadir, $trace_params ) = @_;
    my $self = fields::new( $class );
    $self->{LOGGER} = get_logger( "perfSONAR_PS::Services::MP::TracerouteTest" );
    $self->{NETLOGGER} = get_logger( "NetLogger" );
    
    if(defined $test_int && $test_int){
        $self->{'TEST_INTERVAL'} = $test_int;
    }
    
    if(defined $trace_params && $trace_params){
        $self->{'TRACE_PARAMS'} = $trace_params;
        ($self->{'METADATA_ID'}, $self->{'METADATA'}) = $self->_createMetadata();
        $self->determine_v4_or_v6();
    }
    
    if(defined $datadir && $datadir){
        $self->{'DATADIR'} = $datadir;
    }
    
    return $self;
}

sub determine_v4_or_v6 {
    my $self = shift @_;   
    if(!$self->{'TRACE_PARAMS'}->{'host'}){
        $self->{LOGGER}->warn("No destination host provided for traceroute test");
        return;
    }
    
    #Set the v4 and v6 versions of traceroute
    my $trace6prog = $self->{'TRACE_PARAMS'}->{'TRACE6PROG'} ? $self->{'TRACE_PARAMS'}->{'TRACE6PROG'} : "traceroute6" ;
    my $trace4prog = $self->{'TRACE_PARAMS'}->{'TRACE4PROG'} ? $self->{'TRACE_PARAMS'}->{'TRACE4PROG'} : "" ; #just use default if not specified
    
    #Determine the endpoint type
    my $endpoint_type = $self->getEndpointType($self->{'TRACE_PARAMS'}->{'host'});
    #If its a hostname then we have more work to do
    if($endpoint_type eq 'hostname'){
        my ($ipv4addr, $ipv6addr) = $self->getv4v6( $self->{'TRACE_PARAMS'}->{'host'} );
        #Prefer Ipv6 by default otherwise use v4
        if(!$self->{'TRACE_PARAMS'}->{'prefer_ip_v4'} && $ipv6addr){
            $endpoint_type = 'ipv6';
        }elsif($ipv4addr){
            $endpoint_type = 'ipv4';
        }elsif($ipv6addr){
            # preference but no ipv4
            $endpoint_type = 'ipv6'
        }else{
            $self->{LOGGER}->warn("Unable to find A or AAA record for " . $self->{'TRACE_PARAMS'}->{'host'});
        }
    }
      
    if ($self->{'TRACE_PARAMS'}->{'ipv4_only'}) {
        $endpoint_type = "ipv4";
    }
    elsif ($self->{'TRACE_PARAMS'}->{'ipv6_only'}) {
        $endpoint_type = "ipv6";
    }

    #set the traceroute program
    if($endpoint_type eq "ipv6" ){
        $self->{'TRACE_PARAMS'}->{'trace_program'} = $trace6prog;
    }elsif($trace4prog){
        $self->{'TRACE_PARAMS'}->{'trace_program'} = $trace4prog;
    }
    $self->verifySourceAddr( $endpoint_type ) if($endpoint_type ne 'hostname');
    
    $self->{LOGGER}->info("Test type is " . $endpoint_type . " for " . $self->{'TRACE_PARAMS'}->{'host'} );
    $self->{LOGGER}->info("Source address is " . $self->{'TRACE_PARAMS'}->{'source_address'} );
    $self->{LOGGER}->info("Traceroute program is " . ($self->{'TRACE_PARAMS'}->{'trace_program'} ? $self->{'TRACE_PARAMS'}->{'trace_program'} : 'traceroute'));
    
    #otherwise just let it do default ipv4 traceroute
    return 0;
}

sub verifySourceAddr {
    my($self, $destAddrType) = @_;
    
    if(!$self->{'TRACE_PARAMS'}->{'source_address'}){
        return;
    }
    
    #get source endpoint type
    my $endpoint_type = $self->getEndpointType($self->{'TRACE_PARAMS'}->{'source_address'});
    if($endpoint_type eq $destAddrType){
        return;
    }elsif($endpoint_type ne 'hostname'){
        $self->{LOGGER}->warn("Specified an $endpoint_type address " . $self->{'TRACE_PARAMS'}->{'source_address'} . " to a $destAddrType destination " . $self->{'TRACE_PARAMS'}->{'host'});
        return;
    }elsif($destAddrType eq 'ipv4'){
        #can use hostnames for ipv4 traceroute
        return;
    }
    #traceroute6 does not like it when you give the source as a hostname
    #we need a v6 address if we get here...
    my ($srcipv4addr, $srcipv6addr) = $self->getv4v6( $self->{'TRACE_PARAMS'}->{'source_address'} );
    if($srcipv6addr && is_ipv6($srcipv6addr) && $srcipv6addr =~ /(.+)/){
        $self->{'TRACE_PARAMS'}->{'source_address'} = $1; #gets around tainting error
    }else{
        $self->{LOGGER}->warn("Unable to find $destAddrType record for source address");
    }
}
sub getv4v6 {
    my ($self, $hostname) = @_;
    my $ipv6addr = "";
    my $ipv4addr = "";
    my $res = Net::DNS::Resolver->new;
    
    #lookup IPv4 address
    my $query = $res->search($hostname, "A");
    if($query){
        foreach my $rr ($query->answer) {
            if($rr->type eq "A"){
                $ipv4addr = $rr->address;
                last;
            }
        }
    }
    #lookup IPv6 address
    $query = $res->search($hostname, "AAAA");
    if($query){
        foreach my $rr ($query->answer) {
            if($rr->type eq "AAAA"){
                $ipv6addr = $rr->address;
                last;
            }
        }
    }
    
    return ($ipv4addr, $ipv6addr );
}

sub run {
    my ($self) = @_;
    
    #create traceroute
    my $tr_dom;
    
    eval{
        if($self->{'TRACE_PARAMS'}->{'reverse'}){
            $tr_dom = $self->sendMPRequest();
        }else{
            my $traceroute = perfSONAR_PS::Services::MP::NetTraceroute->new(%{$self->{'TRACE_PARAMS'}});
            $tr_dom = $traceroute->psTraceroute();
        }
    };
    if($@){
        #make sure failed test doesn't keep running
        $self->{'LAST_RUNTIME'} = time;
        $self->{LOGGER}->debug("NEXT RUNTIME =" .  $self->getNextRuntime());
        die $@;
    }
    
    unless(defined $self->{'TRACE_PARAMS'}->{'no_data_register'} && $self->{'TRACE_PARAMS'}->{'no_data_register'}){
        my $data_id = genuid();
        $tr_dom->setAttribute('id', "data.$data_id");
        $tr_dom->setAttribute('metadataIdRef', $self->{'METADATA_ID'});
        # write to file
        my $datafile = $self->{'DATADIR'} . "/${data_id}.xml";
        my($tmp_fh, $tmp_filename) = tempfile();
        print $tmp_fh $self->{'METADATA'}->toString();
        print $tmp_fh $tr_dom->toString();
        close $tmp_fh;
        move("$tmp_filename", $datafile) or die("Unable to move $tmp_filename to $datafile: $!");
    }
    
    #return dom
    $self->{'LAST_RUNTIME'} = time;
    $self->{LOGGER}->debug("NEXT RUNTIME =" .  $self->getNextRuntime());
    
    return $tr_dom;
}

sub _createMetadata {
    my $self = shift;
    my $dom = XML::LibXML::Document->createDocument();
    my $metadata_elem = $dom->createElementNS(NMWG_NS, NMWG_PREFIX . ":metadata");
    my $mid = 'meta.' . genuid();
    $metadata_elem->setAttribute('id', $mid);

    my $subject_elem = $self->_createSubject();
    $metadata_elem->appendChild($subject_elem);
    
    my $eventtype_elem = $dom->createElementNS(NMWG_NS, NMWG_PREFIX . ":eventType");
    $eventtype_elem->appendChild($dom->createTextNode(TRACEROUTE_NS));
    $metadata_elem->appendChild($eventtype_elem);
    
    my $parameters_elem = $dom->createElementNS(NMWG_NS, NMWG_PREFIX . ":parameters");
    my $param_map = PARAM_MAP;
    foreach my $param_key(keys %{$param_map}){
        if(defined $self->{'TRACE_PARAMS'}->{$param_map->{$param_key}}){
            my $parameter_elem = $dom->createElementNS(NMWG_NS, NMWG_PREFIX . ":parameter");
            $parameter_elem->setAttribute('name', $param_key);
            $parameter_elem->setAttribute('value', $self->{'TRACE_PARAMS'}->{$param_map->{$param_key}});
            $parameters_elem->appendChild($parameter_elem);
        }
    }
    $metadata_elem->appendChild($parameters_elem);
    
    return ($mid, $metadata_elem);
}

sub _createSubject {
    my ($self) = @_;
    my $dom = XML::LibXML::Document->createDocument();
    my $subject_elem = $dom->createElementNS(TRACEROUTE_NS, TRACEROUTE_PREFIX . ":subject");
    my $endpoint_elem = $dom->createElementNS(NMWGT_NS, NMWGT_PREFIX . ":endPointPair");
    my $src_elem = $dom->createElementNS(NMWGT_NS, NMWGT_PREFIX . ":src");
    $src_elem->setAttribute('type', $self->getEndpointType($self->{'TRACE_PARAMS'}->{'source_address'}));
    $src_elem->setAttribute('value', $self->{'TRACE_PARAMS'}->{'source_address'});
    my $dst_elem = $dom->createElementNS(NMWGT_NS, NMWGT_PREFIX . ":dst");
    $dst_elem->setAttribute('type', $self->getEndpointType($self->{'TRACE_PARAMS'}->{'host'}));
    $dst_elem->setAttribute('value', $self->{'TRACE_PARAMS'}->{'host'});
    $endpoint_elem->appendChild($src_elem);
    $endpoint_elem->appendChild($dst_elem);
    $subject_elem->appendChild($endpoint_elem);
    
    return $subject_elem;
}

sub getMetaData(){
    my $self = shift @_;
    return $self->{METADATA};
}

sub getEndpointType() {
    my ($self, $endpoint) = @_;
    my $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MP.TracerouteTest.getEndpointType.start");
    $self->{NETLOGGER}->debug( $nlmsg );
    my $type = "hostname";
   
    if( is_ipv4($endpoint) ){
        $type = "ipv4";
    }elsif( is_ipv6($endpoint) ){
        $type = "ipv6";
    }
    
    $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MP.TracerouteTest.getEndpointType.end", {type => $type, addr => $endpoint});
    $self->{NETLOGGER}->debug( $nlmsg );
    return $type;
}

sub getNextRuntime() {
    my $self = shift;
    if($self->{'LAST_RUNTIME'}){
        return ($self->{'LAST_RUNTIME'} + $self->{'TEST_INTERVAL'});
    }else{
        return 0;
    }
}

sub getParams(){
    my $self = shift;
    return $self->{TRACE_PARAMS};
}

sub getMPRequestItems(){
    my $self = shift;
    
    my $mp_url = $self->{'TRACE_PARAMS'}->{'mp'};
    unless(defined $mp_url && $mp_url){
        die("No MP URL provided");
    }
    
    my $subject = $self->_createSubject()->toString();
    
    my $param_map = PARAM_MAP;
    my %mp_params = ();
    #don't want the remote mp to register data
    $mp_params{'noDataRegister'} = 1;
    foreach my $param_key(keys %{$param_map}){
        if(defined $self->{'TRACE_PARAMS'}->{$param_map->{$param_key}}){
            $mp_params{$param_key} = $self->{'TRACE_PARAMS'}->{$param_map->{$param_key}};
        }
    }
    
    return ($mp_url, $subject, \%mp_params);
}

sub sendMPRequest {
    my $self = shift;
    
    my ($mp_url, $subject, $mp_params) = $self->getMPRequestItems();
    my $mp_client = new perfSONAR_PS::Client::MA( { instance => $mp_url } );
    my @eventTypes = ( TRACEROUTE_NS );
    my $parser = XML::LibXML->new();
    my $result = $mp_client->setupDataRequest(
            {
                start      => time,
                eventTypes => \@eventTypes,
                subject    => $subject,
                parameters => $mp_params
            }
        ) or die("Unable to contact $mp_url: $!");
    unless ($result->{data} && @{$result->{data}} > 0){
        die "No data returned by traceroute MP";
    }
    my $doc = $parser->parse_string( $result->{data}->[0] );
    my $datum = find($doc->getDocumentElement, "./*[local-name()='datum']", 0);
    if( !defined $datum){
        die( "No datum in response" );
    }
    unless( @{$datum} > 0 && $datum->[0] && defined $datum->[0]->getAttribute("ttl")) {
        ie( "Datum in invalid format" );
    }
    
    return $doc->getDocumentElement;
}
