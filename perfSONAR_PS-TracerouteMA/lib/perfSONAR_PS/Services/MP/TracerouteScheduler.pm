package perfSONAR_PS::Services::MP::TracerouteScheduler;

use strict;
use warnings;

our $VERSION = 3.3;

use perfSONAR_PS::Utils::NetLogger;
use perfSONAR_PS::Utils::ParameterValidation;
use perfSONAR_PS::Config::OWP::Conf;
use OWP::MeasSet;
use perfSONAR_PS::Services::MP::TracerouteTest;

use Log::Log4perl qw(get_logger);

use constant PARAM_MAP => { 'FIRSTTTL' => 'first_hop' , 'MAXTTL' => 'max_ttl', 
                            'WAITTIME' => 'query_timeout', 'PAUSE' => 'pause', 
                            'PACKETSIZE' => 'packetlen', 'TIMEOUT' => 'timeout', 
                            'ICMP' => 'use_icmp', 'TRACE4PROG' => 'trace4_program',
                            'TRACE6PROG' => 'trace4_program', 'PREFIPV4' => 'prefer_ip_v4',
                            'IPV4ONLY' => 'ipv4_only', 'IPV6ONLY' => 'ipv6_only' };

use fields 'LOGGER','NETLOGGER','TRACEROUTE_TESTS';

sub new {
    my ( $class, $owmesh ) = @_;
    my $self = fields::new( $class );
    $self->{LOGGER} = get_logger( "perfSONAR_PS::Services::MP::TracerouteScheduler" );
    $self->{NETLOGGER} = get_logger( "NetLogger" );
    $self->{TRACEROUTE_TESTS} = ();
    eval{
        $self->init( $owmesh );
    };
    if($@){
        $self->{LOGGER}->error("Error loading test config: " . $@);
        die "Error loading test config: " . $@;
    }
    
    return $self;
}

sub init {
    my( $self, $owmesh ) = @_;
    my $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MP.TracerouteScheduler.init.start");
    $self->{NETLOGGER}->debug($nlmsg);
    my %defaults = ( CONFDIR => $owmesh );
    my $conf = new perfSONAR_PS::Config::OWP::Conf( %defaults );
    my $ttype = 'Trace';
    
    my @localnodes = $conf->get_val( ATTR => 'LOCALNODES' );
    if ( !defined( $localnodes[0] ) ) {
        my $me = $conf->must_get_val( ATTR => 'NODE' );
        @localnodes = ( $me );
    }
    
    my $datadir = $conf->must_get_val( ATTR => "DataDir", TYPE => $ttype );
    my $fullcentral_host = $conf->must_get_val(
        ATTR => 'CentralHost',
        TYPE => $ttype
    );
   # my $timeout = $conf->must_get_val(
   #     ATTR => 'SendTimeout',
   #     TYPE => $ttype
   # );
    
    #get test specs
    my @tracetests = $conf->get_list(
        LIST  => 'TESTSPEC',
        ATTR  => 'TOOL',
        VALUE => 'traceroute'
    );
    
    #get measurements
    my @meassets = ();
    foreach my $tracetest( @tracetests ){
        my @meassets =  $conf->get_list(
            LIST  => 'MEASUREMENTSET',
            ATTR  => 'TESTSPEC',
            VALUE => $tracetest
        );
        
        #reads measurment sets
        foreach my $measset(@meassets){
            $self->{LOGGER}->info("measset = $measset");
            my $meassetdesc = new OWP::MeasSet(
                CONF           => $conf,
                MEASUREMENTSET => $measset
            );
            
            foreach my $localnode( @localnodes){
                if ( defined( $conf->get_val( NODE => $localnode, ATTR => 'NOAGENT' ) ) ) {
                    die "configuration specifies NODE=$localnode should not run an agent";
                }
       
                #handle all tests where source is local node
                foreach my $send ( keys %{ $meassetdesc->{'SENDERS'} } ) {
                    next if ($localnode ne $send );
                    
                    my $local_addr = $conf->get_val(
                                NODE => $send,
                                TYPE => $meassetdesc->{'ADDRTYPE'},
                                ATTR => 'ADDR'
                            );
                    next unless (defined $local_addr && $local_addr);
                    $self->{LOGGER}->info("local send addr = $local_addr");
                    
                    foreach my $recv ( @{ $meassetdesc->{'SENDERS'}->{$send} } ) {
                        my %trace_test_params = ();
                        $trace_test_params{'source_address'} = $local_addr;
                        my $remote_addr = $conf->get_val(
                                NODE => $recv,
                                TYPE => $meassetdesc->{'ADDRTYPE'},
                                ATTR => 'ADDR'
                            );
                        die ("No " . $meassetdesc->{'ADDRTYPE'}. " defined for $recv") unless (defined $remote_addr && $remote_addr);
                        $trace_test_params{'host'} = $remote_addr;
                        $self->{LOGGER}->info("remote addr = $remote_addr");
                        $self->_addTest($conf, $datadir, $ttype, $tracetest, \%trace_test_params);
                    }
                }
                
                #handle all tests where desination local node
                foreach my $recv ( keys %{ $meassetdesc->{'RECEIVERS'} } ) {
                    next if ($localnode ne $recv );
                    my $local_addr = $conf->get_val(
                                NODE => $recv,
                                TYPE => $meassetdesc->{'ADDRTYPE'},
                                ATTR => 'ADDR'
                            );
                    next unless (defined $local_addr && $local_addr);
                    $self->{LOGGER}->info("local recv addr = $local_addr");
                    
                    foreach my $send ( @{ $meassetdesc->{'RECEIVERS'}->{$recv} } ) {
                      my %trace_test_params = (); 
                      $trace_test_params{'reverse'} = 1;
                      $trace_test_params{'host'} = $local_addr;
                      my $remote_addr = $conf->get_val(
                                NODE => $send,
                                TYPE => $meassetdesc->{'ADDRTYPE'},
                                ATTR => 'ADDR'
                            );           
                      die ("No " . $meassetdesc->{'ADDRTYPE'}. " defined for $send") unless (defined $remote_addr && $remote_addr);
                      $trace_test_params{'source_address'} = $remote_addr;
                      
                      my $mp_url = $conf->get_val(
                                NODE => $send,
                                TYPE => 'TRACEMP',
                                ATTR => 'ADDR'
                            );
                      #For now, if no MP URL provided just don't do the bidirectional test
                      unless (defined $mp_url && $mp_url) {
                        #just warn for now since not clear how widley deployed mp will be
                        #warn ("No TRACEMPADDR defined for $send. Will be unable do reverse traceroute tests.");
                        next;
                      }
                      $trace_test_params{'mp'} = $mp_url;
                      
                      #add test
                      $self->_addTest($conf, $datadir, $ttype, $tracetest, \%trace_test_params);
                    }
                }
            }
        }
    }
    
    $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MP.TracerouteScheduler.init.end");
    $self->{NETLOGGER}->debug($nlmsg);
}

sub run{
    my $self = shift;
    
    my $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MP.TracerouteScheduler.run.start");
    $self->{NETLOGGER}->debug($nlmsg);
    foreach my $test ( @{ $self->{TRACEROUTE_TESTS} } ){
        next if($test->getNextRuntime() > 0 && $test->getNextRuntime() > time);
        $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MP.TracerouteTest.run.start", $test->getParams());
        $self->{NETLOGGER}->debug($nlmsg);
        eval{
            $self->{LOGGER}->info("Running traceroute...");
            $test->run();
        };
        if($@){
            my $msg = "Error running traceroute: " . $@;
            $self->{LOGGER}->error( $msg );
            $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MP.TracerouteTest.run.end", {status => -1, msg => $msg});
            $self->{NETLOGGER}->debug( $nlmsg );
            next;
        }
        $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MP.TracerouteTest.run.end");
        $self->{NETLOGGER}->debug($nlmsg);
    }
    $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.Services.MP.TracerouteScheduler.run.end");
    $self->{NETLOGGER}->debug($nlmsg);
}

sub _addTest{
    my ($self, $conf, $datadir, $ttype, $tracetest, $trace_test_params) = @_;
    my $TRACE_PARAMS = PARAM_MAP;
    my $test_int = $conf->get_val(
            TESTSPEC => $tracetest,
            TYPE => $ttype,
            ATTR => 'TESTINTERVAL'
        );
    die ("No ${ttype}TESTINTERVAL defined for test") unless(defined $test_int && $test_int);
    
    #process optional parameters
    foreach my $param_name( keys %{ $TRACE_PARAMS }){
        my $param_val = $conf->get_val(
            TESTSPEC => $tracetest,
            TYPE => $ttype,
            ATTR => $param_name
        );
        $trace_test_params->{$TRACE_PARAMS->{$param_name}} = $param_val if(defined $param_val && $param_val);
    }
    my $test =  new perfSONAR_PS::Services::MP::TracerouteTest(
        $test_int, $datadir, $trace_test_params);
    push @{$self->{TRACEROUTE_TESTS}}, $test;
}
