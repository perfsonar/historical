package perfSONAR_PS::Services::MP::NetTraceroute;
    
use strict;
use warnings;
use base 'Net::Traceroute';

our $VERSION = 3.3;

use XML::LibXML;
use Log::Log4perl qw(get_logger);
use Symbol qw(qualify_to_ref);
use perfSONAR_PS::Utils::NetLogger;
use perfSONAR_PS::Utils::ParameterValidation;

use constant DEFAULT_TIMEOUT => 30;
use constant TRACEROUTE_NS => 'http://ggf.org/ns/nmwg/tools/traceroute/2.0';
use constant NMWG_NS => 'http://ggf.org/ns/nmwg/base/2.0/';
use constant TRACEROUTE_PREFIX => 'traceroute';
use constant NMWG_PREFIX => 'nmwg';

$SIG{CHLD} = 'IGNORE';

my %CMDLINE_VALUEMAP = ( "base_port" => "-p",
      "max_ttl" => "-m",
      "queries" => "-q",
      "query_timeout" => "-w",
      "source_address" => "-s",
      "first_hop" => "-f",
      "pause" => "-z"
      );
my %CMDLINE_FLAGMAP =
        ( "no_fragment" => "-F",
          "use_icmp" => "-I",
        );

my @ADDITIONAL_TRACE_PARAMS = ( 'first_hop', 'pause' );                          

sub new {
    my ( $class, %test_params ) = @_;
    
    #Remove host so traceroute does not get executed immediately
    my $host = delete $test_params{'host'};
    
    #set default timeout so we always have one
    unless( exists  $test_params{'timeout'} && $test_params{'timeout'} > 0 ){
        $test_params{'timeout'} = DEFAULT_TIMEOUT;
    }
    
    #Pass test parameters to super class
    my $self = Net::Traceroute->new(%test_params);
    bless $self, $class;
    #Now that object is created, add host back0
    $self->host($host);
    
    #Set parameters that Net::Traceroute does not support
    foreach my $param(@ADDITIONAL_TRACE_PARAMS){
        my $sym = qualify_to_ref($param, $class);
        my $get_set_sub = sub {
	        my ($self, $val) = @_;
	        $self->{$param} = $val if(defined $val && $val);
	        return $self->{$param};
        };
        *{$sym} = $get_set_sub;
        $self->$param($test_params{$param}) if(defined $test_params{$param});
    }

    return $self;
}

sub _tr_cmd_args ($) {
    my $self = shift;

    my @result = ();
    push(@result, "-n");
    my($key, $flag);
    while(($key, $flag) = each %CMDLINE_FLAGMAP) {
        push(@result, $flag) if($self->$key());;
    }

    while(($key, $flag) = each %CMDLINE_VALUEMAP) {
        my $val = $self->$key();
        if(defined $val) {
            push(@result, $flag, $val);
        }
    }

    return @result;
}

sub psTraceroute(){
    my $self = shift @_;
    
    my $trace_time = time;
    #create eval block to handle timeouts since Net::Traceroute timeout behavior doesn't always work
    $SIG{ALRM} = \&_handle_timeout;
    eval{
        alarm( $self->timeout() );
        $self->traceroute();
        alarm(0);
    };
    if($@){
        #make sure timeout is cleared if another exception got us to this block
        alarm(0);
        #passing error up the stack
        #looks strange but important for alarm to be in eval block
        die "$@";
    }
    
    if($self->hops == 0){
        die "Traceroute did not return any hops";
    }
    
    #Determine first hop because Net::Traceroute sets first few hops to undefined when first_hop given
    my $first_hop = 1;
    if(defined $self->first_hop() &&  $self->first_hop() > 0){
        $first_hop = $self->first_hop();
    }
    
    my $dom = XML::LibXML::Document->createDocument();
    my $data_elem = $dom->createElementNS(NMWG_NS, NMWG_PREFIX . ":data");
    for(my $hop_i = $first_hop; $hop_i <= $self->hops; $hop_i++){
        for(my $query_i = 1; $query_i <= $self->hop_queries($hop_i); $query_i++){
            my $datum_elem = $dom->createElementNS(TRACEROUTE_NS, TRACEROUTE_PREFIX . ":datum");
            my $query_status = $self->hop_query_stat($hop_i, $query_i);
            $datum_elem->setAttribute( 'ttl', $hop_i);
            $datum_elem->setAttribute( 'queryNum', $query_i);
            $datum_elem->setAttribute( 'timeValue', $trace_time);
            $datum_elem->setAttribute( 'timeType', 'unix');
            if($query_status == $self->TRACEROUTE_OK()){
                $datum_elem->setAttribute( 'hop', $self->hop_query_host($hop_i, $query_i));
                $datum_elem->setAttribute( 'value', $self->hop_query_time($hop_i, $query_i));
                $datum_elem->setAttribute( 'valueUnits', 'ms');
            }else{
                $datum_elem->setAttribute( 'hop', $self->getErrorCode($query_status));
            }
            $data_elem->appendChild($datum_elem);
        }
    }
    
    return $data_elem;
}

#translate Net::Traceroute values to RFC5388 values
sub getErrorCode(){
    my ($self, $code)  = @_;
    
    #append with "error:" to distinguish from address
    my $error_code = "error:";
    
    if($code == $self->TRACEROUTE_TIMEOUT()){
        $error_code .= "requestTimedOut"; 
    }elsif($code == $self->TRACEROUTE_UNREACH_NET()){
        $error_code .= "noRouteToTarget"; 
    }elsif($code == $self->TRACEROUTE_UNREACH_HOST()){
        $error_code .= "unknownDestinationAddress"; 
    }elsif($code == $self->TRACEROUTE_UNREACH_SRCFAIL()){
        $error_code .= "interfaceInactiveToTarget"; 
    }elsif($code == $self->TRACEROUTE_UNKNOWN()){
        $error_code .= "unknown"; 
    }else{
        #TRACEROUTE_UNREACH_PROTO,TRACEROUTE_UNREACH_NEEDFRAG
        #TRACEROUTE_UNREACH_FILTER_PROHIB, TRACEROUTE_BSDBUG
        $error_code .= "internalError";
    }
    
    return $error_code;    
}
sub _handle_timeout{
    die "Traceroute execution timed out";
}

#override parsing so can prep output for some cases Net::Traceroute doesn't support
sub _parse ($$) {
    my $self = shift;
    my $tr_output = shift;
    
    ##
    # Some versions of traceroute put consecutive queries with different addresses on new line.
    # This breaks Net::Traceroute so the code below puts them on same line. For example:
    # traceroute to fnal-owamp.es.net (198.124.252.101), 64 hops max, 40 byte packets
    # 1  anlmr1-anlowamp (198.124.252.98)  0.470 ms  0.277 ms  0.180 ms
    # 2  starcr1-anlmr2 (134.55.219.54)  2.215 ms  2.228 ms
    # chiccr1-ip-anlmr2 (134.55.220.37)  1.096 ms
    # ....
    #Now becomes:
    # traceroute to fnal-owamp.es.net (198.124.252.101), 64 hops max, 40 byte packets
    # 1  anlmr1-anlowamp (198.124.252.98)  0.470 ms  0.277 ms  0.180 ms
    # 2  starcr1-anlmr2 (134.55.219.54)  2.215 ms  2.228 ms chiccr1-ip-anlmr2 (134.55.220.37)  1.096 ms
    ##
    my $new_tr_output = "";
    my $ttl = -1;
    my $line_num = 0;
    foreach my $tr_line (split(/\n/, $tr_output)) {
        $line_num++;
        if($tr_line =~ /^traceroute to / ||
            $tr_line =~ /^trying to get / ||
            $tr_line =~ /^source should be / ||
            $tr_line =~ /^message too big, trying new MTU = (\d+)/ ||
            $tr_line =~ /^\s+MPLS Label=(\d+) CoS=(\d) TTL=(\d+) S=(\d+)/
           ){
             $new_tr_output .= "\n" if($line_num > 1);
             $new_tr_output .= "$tr_line";
             next;
        }
        
        if($tr_line =~ /^([0-9 ][0-9]) /){
            $ttl = $1 + 0;
            $new_tr_output .= "\n" if($line_num > 1);
            $new_tr_output .= "$tr_line";
        }elsif ($ttl == -1){
            #this is an error so reset and let Net::Traceroute deal with it
            $new_tr_output = $tr_output; 
            last;
        }else{
            $tr_line =~ s/^\s+/ /;
            $new_tr_output .= "$tr_line";
        }
    }
    
    
    $self->SUPER::_parse( $new_tr_output );
}
