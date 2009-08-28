use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../lib";
my $confdir = "$Bin/../etc";

use Cwd;
use File::Basename;
use Getopt::Long;
use Config::General;
use Log::Log4perl qw/:easy/;
use perfSONAR_PS::Utils::Daemon qw/daemonize setids lockPIDFile unlockPIDFile/;

use Cache::FastMmap;

my @child_pids = ();

$SIG{PIPE} = 'IGNORE';
$SIG{ALRM} = 'IGNORE';
$SIG{INT}  = \&signalHandler;
$SIG{TERM} = \&signalHandler;

my $CONFIG_FILE;
my $LOGOUTPUT;
my $LOGGER_CONF;
my $PIDFILE;
my $DEBUGFLAG;
my $HELP;
my $RUNAS_USER;
my $RUNAS_GROUP;

my ( $status, $res );

$status = GetOptions(
    'config=s'  => \$CONFIG_FILE,
    'output=s'  => \$LOGOUTPUT,
    'logger=s'  => \$LOGGER_CONF,
    'pidfile=s' => \$PIDFILE,
    'verbose'   => \$DEBUGFLAG,
    'user=s'    => \$RUNAS_USER,
    'group=s'   => \$RUNAS_GROUP,
    'help'      => \$HELP
);

$CONFIG_FILE = $confdir . "/dcn_status.conf" unless $CONFIG_FILE;
$CONFIG_FILE = getcwd . "/" . $CONFIG_FILE unless $CONFIG_FILE =~ /^\//;

# The configuration directory gets passed to the modules so that relative paths
# defined in their configurations can be resolved.
$confdir = dirname( $CONFIG_FILE );

# Read in configuration information
my %conf = new Config::General( $CONFIG_FILE )->getall();

if ( not $PIDFILE ) {
    $PIDFILE = $conf{"pid_file"};
}

if ( not $PIDFILE ) {
    $PIDFILE = "/var/run/dcn_status_caching_agent.pid";
}

( $status, $res ) = lockPIDFile( $PIDFILE );
if ( $status != 0 ) {
    print "Error: $res\n";
    exit( -1 );
}

my $fileHandle = $res;

# Check if the daemon should run as a specific user/group and then switch to
# that user/group.
if ( not $RUNAS_GROUP ) {
    if ( $conf{"group"} ) {
        $RUNAS_GROUP = $conf{"group"};
    }
}

if ( not $RUNAS_USER ) {
    if ( $conf{"user"} ) {
        $RUNAS_USER = $conf{"user"};
    }
}

if ( $RUNAS_USER and $RUNAS_GROUP ) {
    if ( setids( USER => $RUNAS_USER, GROUP => $RUNAS_GROUP ) != 0 ) {
        print "Error: Couldn't drop priviledges\n";
        exit( -1 );
    }
}
elsif ( $RUNAS_USER or $RUNAS_GROUP ) {

    # they need to specify both the user and group
    print "Error: You need to specify both the user and group if you specify either\n";
    exit( -1 );
}

# Now that we've dropped privileges, create the logger. If we do it in reverse
# order, the daemon won't be able to write to the logger.
my $logger;
if ( not defined $LOGGER_CONF or $LOGGER_CONF eq q{} ) {
    use Log::Log4perl qw(:easy);

    my $output_level = $INFO;
    if ( $DEBUGFLAG ) {
        $output_level = $DEBUG;
    }

    my %logger_opts = (
        level  => $output_level,
        layout => '%d (%P) %p> %F{1}:%L %M - %m%n',
    );

    if ( defined $LOGOUTPUT and $LOGOUTPUT ne q{} ) {
        $logger_opts{file} = $LOGOUTPUT;
    }

    Log::Log4perl->easy_init( \%logger_opts );
    $logger = get_logger( "perfSONAR_PS" );
}
else {
    use Log::Log4perl qw(get_logger :levels);

    my $output_level = $INFO;
    if ( $DEBUGFLAG ) {
        $output_level = $DEBUG;
    }

    my %logger_opts = (
        level  => $output_level,
        layout => '%d (%P) %p> %F{1}:%L %M - %m%n',
    );

    if ( $LOGOUTPUT ) {
        $logger_opts{file} = $LOGOUTPUT;
    }

    Log::Log4perl->init( $LOGGER_CONF );
    $logger = get_logger( "perfSONAR_PS" );
    $logger->level( $output_level ) if $output_level;
}

unless ($conf{"topology_service"}) {
    $logger->error("Must specify the topology service to query for. e.g. topology_service=http://ndb1.internet2.edu:8012/perfSONAR_PS/services/topology");
    exit( -1 );
}

unless ($conf{"domain"}) {
    $logger->error("Must specify which domain to use. e.g. domain=dcn.internet2.edu");
    exit( -1 );
}

unless ($conf{"oscars_client"}) {
    $logger->error("Must specify where the OSCARS client software is located. e.g. oscars_client=/opt/oscars_client");
    exit( -1 );
}

unless ($conf{"axis2_home"}) {
    $logger->error("Must specify where the Axis2 software is located. e.g. axis2_home=/opt/axis2_home");
    exit( -1 );
}

unless ($conf{"idc_url"}) {
    $logger->error("Must specify where the URL for the IDC for this domain. e.g. idc_url=https://test-idc.internet2.edu:8443/axis2/services/OSCARS");
    exit( -1 );
}

unless ($conf{"cache_file"}) {
    $logger->error("Must specify which file to use to cache the data. e.g. cache_file=/var/lib/dcn_web_interface/cache.dat");
    exit( -1 );
}

unless ($conf{"topology_interval"}) {
    $conf{"topology_interval"} = 86400;
}

unless ($conf{"reservations_interval"}) {
    $conf{"reservations_interval"} = 60;
}

unless ($conf{"reservations_update_amount"}) {
    $conf{"reservations_update_amount"} = 60;
}

my $cache = Cache::FastMmap->new({ share_file => $conf{"cache_file"}, unlink_on_exit => 0, compress => 1 });

my $topology_worker = perfSONAR_PS::DCNStatusPage::Workers::Topology->new();
($status, $res) = $topology_worker->init({ domain => $conf{"domain"}, topology_service_url => $conf{"topology_service"}, shared_cache => $cache, update_interval => $conf{"topology_interval"}, ciena_username => $conf{"ciena_username"}, ciena_password => $conf{"ciena_password"} });

my $reservations_worker = perfSONAR_PS::DCNStatusPage::Workers::Reservations->new();
($status, $res) = $reservations_worker->init({ domain => $conf{"domain"}, oscars_client_dir => $conf{"oscars_client"}, axis2_home => $conf{"axis2_home"}, idc_url => $conf{"idc_url"}, reservations_cache => $cache, update_interval => $conf{"reservations_interval"}, prefill_amount => $conf{"reservations_update_amount"}, java_directory => $conf{"java_directory"} });

my $pid;

$pid = fork();
if ( $pid == 0 ) {
    $topology_worker->run();
}
push @child_pids, $pid;

$pid = fork();
if ($pid == 0) {
    $reservations_worker->run();
}
push @child_pids, $pid;

foreach my $pid ( @child_pids ) {
    waitpid( $pid, 0 );
}

exit( 0 );

=head2 killChildren

Kills all the children for this process off. It uses global variables
because this function is used by the signal handler to kill off all
child processes.

=cut

sub killChildren {
    foreach my $pid ( @child_pids ) {
        kill( "SIGINT", $pid );
    }

    return;
}

=head2 signalHandler

Kills all the children for the process and then exits

=cut

sub signalHandler {
    killChildren;
    exit( 0 );
}



package perfSONAR_PS::DCNStatusPage::Workers::Base;

use strict;
use warnings;

use Log::Log4perl qw(get_logger);

use perfSONAR_PS::Utils::ParameterValidation;

our $VERSION = 3.1;

use fields 'LOGGER', 'UPDATE_INTERVAL';

sub new {
    my $class = shift;

    my $self = fields::new( $class );

    $self->{LOGGER} = get_logger( $class );

    return $self;
}

sub init {
    my ($self, @args) = @_;
    my $args = validateParams( @args, { update_interval => 1 });

    $self->{UPDATE_INTERVAL} = $args->{update_interval};

    return (0, "");
}

sub run {
    my ($self, @args) = @_;
    my $args = validateParams( @args, { });

    my $next_runtime;
    while(1) {
        if ($next_runtime) {
            my $sleep_time = ($next_runtime - time);
	    if ($sleep_time > 0) {
		    $self->{LOGGER}->debug("Sleeping: ".($sleep_time));
		    sleep($next_runtime - time);
	    }
        }

        $next_runtime = time + $self->{UPDATE_INTERVAL};

        $self->handle_task();
    }
}

sub handle_task {
    die("handle_task method must be overridden");
}

package perfSONAR_PS::DCNStatusPage::Workers::Topology;

use strict;
use warnings;

our $VERSION = 3.1;

use Data::Dumper;

use OSCARS::Topology::domain;
use perfSONAR_PS::Client::Topology;
use perfSONAR_PS::Utils::DNS qw(query_location);
use perfSONAR_PS::Utils::TL1::CoreDirector;

use perfSONAR_PS::Utils::ParameterValidation;

use base 'perfSONAR_PS::DCNStatusPage::Workers::Base';

use fields 'DOMAIN', 'TOPOLOGY_SERVICE_URL', 'SHARED_CACHE', 'MAPPINGS', 'CIENA_USERNAME', 'CIENA_PASSWORD';

sub init {
    my ($self, @args) = @_;
    my $args = validateParams( @args, { topology_service_url => 1, domain => 1, shared_cache => 1, update_interval => 1, ciena_username => 1, ciena_password => 1 });
   
    my ($status, $res) = $self->SUPER::init({ update_interval => $args->{update_interval} });
    unless ($status == 0) {
        return ($status, $res);
    }

    $self->{DOMAIN} = $args->{domain};
    $self->{TOPOLOGY_SERVICE_URL} = $args->{topology_service_url};
    $self->{SHARED_CACHE} = $args->{shared_cache};
    $self->{CIENA_USERNAME} = $args->{ciena_username};
    $self->{CIENA_PASSWORD} = $args->{ciena_password};

    my $mapping = $self->{SHARED_CACHE}->get("dcn_status_page.worker.topology.interface_name_mappings");
    unless ($mapping) {
        my %tmp = ();
        $mapping = \%tmp;
        $self->{LOGGER}->debug("No cached mappings");
    }

    my %static_mapping = (
        'urn:ogf:network:domain=dcn.internet2.edu:node=CHIC:port=S26111' => '1-A-6-1-1',
        'urn:ogf:network:domain=dcn.internet2.edu:node=CHIC:port=S27647' => '1-A-7-1-1',
        'urn:ogf:network:domain=dcn.internet2.edu:node=KANS:port=S27391' => '1-A-6-1-1',
        'urn:ogf:network:domain=dcn.internet2.edu:node=CHIC:port=S27903' => '1-A-8-1-1',
        'urn:ogf:network:domain=dcn.internet2.edu:node=CHIC:port=S28159' => '1-A-4-1-9',
        'urn:ogf:network:domain=dcn.internet2.edu:node=CHIC:port=S28415' => '1-A-5-1-1',
        'urn:ogf:network:domain=dcn.internet2.edu:node=NEWY:port=S26367' => '1-A-5-1-1',
        'urn:ogf:network:domain=dcn.internet2.edu:node=NEWY:port=S26623' => '1-A-6-1-1',
        'urn:ogf:network:domain=dcn.internet2.edu:node=BOST:port=S26879' => '1-A-6-1-1',
        'urn:ogf:network:domain=dcn.internet2.edu:node=NEWY:port=S27135' => '1-A-3-1-3',
        'urn:ogf:network:domain=dcn.internet2.edu:node=NEWY:port=S28671' => '1-A-7-1-1',
        'urn:ogf:network:domain=dcn.internet2.edu:node=NEWY:port=S27647' => '1-A-3-1-5',
        'urn:ogf:network:domain=dcn.internet2.edu:node=NEWY:port=S28927' => '1-A-7-1-2',
        'urn:ogf:network:domain=dcn.internet2.edu:node=NEWY:port=S28159' => '1-A-4-1-1',
        'urn:ogf:network:domain=dcn.internet2.edu:node=NEWY:port=S29183' => '1-A-7-1-3',
        'urn:ogf:network:domain=dcn.internet2.edu:node=NEWY:port=S29439' => '1-A-7-1-4',
        'urn:ogf:network:domain=dcn.internet2.edu:node=WASH:port=S26111' => '1-A-5-1-3',
        'urn:ogf:network:domain=dcn.internet2.edu:node=WASH:port=S26367' => '1-A-6-1-1',
        'urn:ogf:network:domain=dcn.internet2.edu:node=JACK:port=S26111' => '1-A-5-1-3',
        'urn:ogf:network:domain=dcn.internet2.edu:node=ELPA:port=S26367' => '1-A-5-1-3',
        'urn:ogf:network:domain=dcn.internet2.edu:node=HOUS:port=S26623' => '1-A-5-1-9',
        'urn:ogf:network:domain=dcn.internet2.edu:node=HOUS:port=S26879' => '1-A-6-1-1',
        'urn:ogf:network:domain=dcn.internet2.edu:node=BATO:port=S27135' => '1-A-6-1-1',
        'urn:ogf:network:domain=dcn.internet2.edu:node=SUNN:port=S26623' => '1-A-5-1-4',
        'urn:ogf:network:domain=dcn.internet2.edu:node=SALT:port=S26879' => '1-A-5-1-4',
        'urn:ogf:network:domain=dcn.internet2.edu:node=LOSA:port=S27135' => '1-A-5-1-9',
        'urn:ogf:network:domain=dcn.internet2.edu:node=LOSA:port=S27391' => '1-A-6-1-1',
        'urn:ogf:network:domain=dcn.internet2.edu:node=SALT:port=S27647' => '1-A-7-1-1',
        'urn:ogf:network:domain=dcn.internet2.edu:node=DENV:port=S27903' => '1-A-6-1-1',
        'urn:ogf:network:domain=dcn.internet2.edu:node=SEAT:port=S28159' => '1-A-6-1-1',
        );
    foreach my $id (keys %static_mapping) {
        $self->{LOGGER}->debug("Adding $id to mappings: ".$static_mapping{$id});
        $mapping->{$id} = $static_mapping{$id};
    }

    $self->{SHARED_CACHE}->set("dcn_status_page.worker.topology.interface_name_mappings", $mapping);

    $mapping = $self->{SHARED_CACHE}->get("dcn_status_page.worker.topology.interface_name_mappings");
    $self->{LOGGER}->debug("Cached Mappings: ".Dumper($mapping));

    return (0, "");
}

sub handle_task {
    my ($self, @args) = @_;
    my $args = validateParams( @args, { });

    my $ts_client = perfSONAR_PS::Client::Topology->new($self->{TOPOLOGY_SERVICE_URL});
    $ts_client->open();
    my ($status, $res) = $ts_client->xQuery('//*[@id="urn:ogf:network:domain='.$self->{DOMAIN}.'"]', 1);
    unless ($status == 0) {
        $self->{LOGGER}->error("Error retrieving topology: $res");
        return;
    }

    my $domain_dom = $res->find('//*[@id="urn:ogf:network:domain='.$self->{DOMAIN}.'"]')->get_node(0);
    unless ($domain_dom) {
        $self->{LOGGER}->error("Error retrieving topology: response does not contain domain information");
        return;
    }

    my $domain = OSCARS::Topology::domain->from_xml_dom($domain_dom);

    unless ($domain) {
        $self->{LOGGER}->error("Error retrieving topology: Couldn't parse returned domain");
        return;
    }

    ($status, $res) = $self->process_domain($domain);
    unless ($status == 0) {
        $self->{LOGGER}->error("Error processing topology: $res");
    }

    ($status, $res) = $self->filter_domain($res);
    unless ($status == 0) {
        $self->{LOGGER}->error("Error processing topology: $res");
    }

    $self->{SHARED_CACHE}->set("dcn_status_page.topology", $res);

    return;
}

sub process_domain {
    my ($self, $domain) = @_;

    my %elements = ();

    my %domain = ();
    $domain{id} = $domain->_id->__value;
    $domain{type} = "domain";
    $domain{children} = {};

    $elements{$domain{id}} = \%domain;

    foreach my $node (@{ $domain->node }) {
        my %node = ();
        $node{id} = $node->_id->__value;
        $node{parent} = $domain->_id->__value;
        $node{children} = {};
        $node{type} = "node";

        $domain{children}->{$node{id}} = 1;

        $elements{$node{id}} = \%node;

        if ($node->port) {
            foreach my $port(@{ $node->port }) {
                my %port = ();
                $port{id} = $port->_id->__value;
                $port{type} = "port";
                $port{parent} = $node->_id->__value;
                $port{children} = {};
                $port{capacity} = $port->capacity->__value if ($port->capacity);
                $port{reservable_capacity} = $port->maximumReservableCapacity->__value if ($port->maximumReservableCapacity);

                $node{children}->{$port{id}} = 1;

                $elements{$port{id}} = \%port;

                foreach my $link (@{ $port->link }) {
                    my %link = ();
                    $link{id} = $link->_id->__value;
                    $link{type} = "link";
                    $link{parent} = $port->_id->__value;
                    $link{remote_link_id} = $link->remoteLinkId->__value if ($link->remoteLinkId);
                    $link{capacity} = $link->capacity->__value if ($link->capacity);
                    $link{reservable_capacity} = $link->maximumReservableCapacity->__value if ($link->maximumReservableCapacity);

                    $port{children}->{$link{id}} = 1;

                    $elements{$link{id}} = \%link;
                }
            }
        }
    }

    return (0, \%elements);
}

sub filter_domain {
    my ($self, $domain) = @_;

    foreach my $element_id (keys %{ $domain }) {
        next unless ($domain->{$element_id}->{type} eq "node");

        my $node = $domain->{$element_id};

        my ($router_address);

        # get the router address, and add the node mapping
        if ($element_id =~ /^urn:ogf:network:domain=dcn.internet2.edu:node=([^:]*)$/) {
            $router_address = "mss.".lc($1).".net.internet2.edu";
        }

        unless ($router_address) {
            print STDERR "Unknown router address for $element_id\n";
            next;
        }

        $router_address = "mss.newy32aoa.net.internet2.edu" if ($router_address eq "mss.newy.net.internet2.edu");

        $node->{name} = $router_address;

        my ($latitude, $longitude);

        ($status, $res) = query_location($router_address);

        if ($status == 0) {
            $node->{latitude} = $res->{latitude};
            $node->{longitude} = $res->{longitude};
        }

        my $mapping = $self->{SHARED_CACHE}->get("dcn_status_page.worker.topology.interface_name_mappings");
        unless ($mapping) {
            my %tmp = ();
            $mapping = \%tmp;
            $self->{LOGGER}->debug("No cached mappings");
        } else {
            $self->{LOGGER}->debug("Cached Mappings: ".Dumper($mapping));
        }

        my $need_lookup_mappings;

        foreach my $port_id (keys %{ $node->{children} }) {
            unless ($mapping->{$port_id}) {
                $self->{LOGGER}->debug("Missing: ".$port_id);
                $need_lookup_mappings = 1;
                last;
            }
        }

        if ($need_lookup_mappings) {
            my $client = perfSONAR_PS::Utils::TL1::CoreDirector->new();
            $client->initialize({ address => $router_address, username => $self->{CIENA_USERNAME}, password => $self->{CIENA_PASSWORD}, cache_time => 30 });
            $status = $client->connect({ inhibit_messages => 1 });

            if ($status != 0) {
                print STDERR "Couldn't connect to $router_address\n";
            } else {
                ($status, $res) = $client->rtrv_osrp_ltp();
                if ($status != 0) {
                    print STDERR "Problem looking up OSRP LTP settings\n";
                } else {
                    foreach my $port_info (@$res) {
                        my $node_name = $port_info->{node};
                        my $port_name = "DTL".$port_info->{port};
                        my $real_port = $port_info->{osrpctps};

                        $mapping->{"urn:ogf:network:domain=dcn.internet2.edu:node=".$node_name.":port=".$port_name} = $real_port;
                    }
                }
                $client->disconnect();

                # Update the name mappings
                $self->{SHARED_CACHE}->set("dcn_status_page.worker.topology.interface_name_mappings", $mapping);
            }
        }

        foreach my $element_id (keys %{ $domain }) {
            next unless ($domain->{$element_id}->{type} eq "port");

            my $port = $domain->{$element_id};

            my $port_name = $mapping->{$element_id};

            $port->{name} = $port_name if ($port_name);
        }

        foreach my $element_id (keys %{ $domain }) {
            next unless ($domain->{$element_id}->{type} eq "link");

            my $link = $domain->{$element_id};

            my $remote_link_id = $link->{remote_link_id};

            next unless ($remote_link_id =~ /urn:ogf:network:domain=[^:]*:node=[^:]*:port=[^:]*/);

            my ($port_id, $node_id, $domain_id) = ($remote_link_id =~ /(((urn:ogf:network:domain=[^:]*):node=[^:]*):port=[^:]*)/);

            $link->{remote_port_id} = $port_id;
            $link->{remote_node_id} = $node_id;
            $link->{remote_domain_id} = $domain_id;
        }
    }

    return (0, $domain);
}


package perfSONAR_PS::DCNStatusPage::Workers::Reservations;

use strict;
use warnings;

our $VERSION = 3.1;

use perfSONAR_PS::Client::OSCARS;

use perfSONAR_PS::Utils::ParameterValidation;

use base 'perfSONAR_PS::DCNStatusPage::Workers::Base';

use fields 'OSCARS_CLIENT', 'AXIS2_HOME', 'IDC_URL', 'RESERVATIONS_CACHE', 'PREFILL_AMOUNT', 'DOMAIN', 'JAVA_DIRECTORY';

sub init {
    my ($self, @args) = @_;
    my $args = validateParams( @args, { oscars_client_dir => 1, axis2_home => 1, idc_url => 1, reservations_cache => 1, update_interval => 1, domain => 1, prefill_amount => 1, java_directory => 0 });
   
    my ($status, $res) = $self->SUPER::init({ update_interval => $args->{update_interval} });
    unless ($status == 0) {
        return ($status, $res);
    }

    $self->{OSCARS_CLIENT} = $args->{oscars_client_dir};
    $self->{AXIS2_HOME} = $args->{axis2_home};
    $self->{IDC_URL} = $args->{idc_url};
    $self->{DOMAIN} = $args->{domain};
    $self->{RESERVATIONS_CACHE} = $args->{reservations_cache};
    $self->{PREFILL_AMOUNT} = $args->{prefill_amount};
    $self->{JAVA_DIRECTORY} = $args->{java_directory};

    return (0, "");
}

sub handle_task {
    my ($self) = @_;

    my $client = perfSONAR_PS::Client::OSCARS->new();

    my $n = $client->init({
            oscars_client => $self->{OSCARS_CLIENT},
            axis2_home => $self->{AXIS2_HOME},
            idc_url => $self->{IDC_URL},
            java_directory => $self->{JAVA_DIRECTORY},
            });

    if ($n != 0) {
        print "Couldn't initialize oscars client\n";
        exit(-1);
    }

    my $time = time;

#    unless ($self->{RESERVATIONS_CACHE}->get("last_runtime")) {
#    ($status, $res) = $client->listReservations({ max_reservations => $self->{PREFILL_AMOUNT} });
    eval {
	    ($status, $res) = $client->listReservations({ max_reservations => $self->{PREFILL_AMOUNT} });
    };

#    } else {
#        ($status, $res) = $client->listReservations({ start_time => $self->{RESERVATIONS_CACHE}->get("last_runtime"), end_time => $time });
#    }

    unless ($status == 0 and not $@) {
        $self->{LOGGER}->error("Problem querying for reservations: ".$res);
        return;
    }

    $self->{RESERVATIONS_CACHE}->set("last_runtime", $time);

    foreach my $resv (@{ $res->resDetails }) {
        my ($status, $res) = $self->process_reservation($resv);
        unless ($status == 0) {
            $self->{LOGGER}->error("Problem processing reservation: ".$res);
            next;
        }

        ($status, $res) = $self->filter_reservation($res);
        unless ($status == 0) {
            $self->{LOGGER}->error("Problem processing reservation: ".$res);
            next;
        }

        $self->{RESERVATIONS_CACHE}->set("dcn_status_page.reservations.".$res->{id}, $res);
    }

    return;
}

sub process_reservation {
    my ($self, $resv) = @_;

    my %reservation = ();
    $reservation{id} = $resv->globalReservationId->__value;
    $reservation{description} = $resv->description->__value;
    $reservation{login} = $resv->login->__value;
    $reservation{status} = $resv->status->__value;
    $reservation{bandwidth} = $resv->bandwidth->__value;
    $reservation{createTime} = $resv->createTime->__value;
    $reservation{startTime} = $resv->startTime->__value;
    $reservation{endTime} = $resv->endTime->__value;

    my @local_path = ();
    my @interdomain_path = ();

    my ($local_src, $local_dst, $prev_local_hop);

    if ($resv->pathInfo) {
        foreach my $hop (@{ $resv->pathInfo->path->hop }) {
            next unless $hop->link;

            my $id = $hop->_id;
            my $link_id = $hop->link->_id->__value;

            next unless ($link_id =~ /urn:ogf:network:domain=[^:]*:node=[^:]*:port=[^:]*/);

            my ($port_id, $node_id, $domain_id) = ($link_id =~ /(((urn:ogf:network:domain=[^:]*):node=[^:]*):port=[^:]*)/);

            unless ($domain_id eq "urn:ogf:network:domain=".$self->{DOMAIN}) {
                # Not local domain
                if ($prev_local_hop) {
                    $local_dst = $prev_local_hop;
                    push @interdomain_path, $link_id;
                }

                push @interdomain_path, $link_id;
            }
            else {
                unless ($local_src) {
                    push @interdomain_path, $link_id;
                    $local_src = $hop;
                }

                push @local_path, $link_id;

                $prev_local_hop = $hop;
            }
        }

        # We hit the end and need to add a hop to the inter-domain path.
        if ($prev_local_hop) {
            $local_dst = $prev_local_hop;
            push @interdomain_path, $local_dst->link->_id->__value;
        }
    }

    $reservation{local_path} = \@local_path;
    $reservation{interdomain_path} = \@interdomain_path;

    if ($local_src and $local_dst) {
        $reservation{local_source} = $local_src->link->_id->__value;
        $reservation{local_destination} = $local_dst->link->_id->__value;

        if ($local_src and $local_src->link->SwitchingCapabilityDescriptors->encodingType eq "ethernet") {
            $reservation{local_source_tag} = $local_src->link->SwitchingCapabilityDescriptors->switchingCapabilitySpecificInfo->vlanRangeAvailability->__value;
        }

        if ($local_dst and $local_dst->link->SwitchingCapabilityDescriptors->encodingType eq "ethernet") {
            $reservation{local_destination_tag} = $local_dst->link->SwitchingCapabilityDescriptors->switchingCapabilitySpecificInfo->vlanRangeAvailability->__value;
        }
    }

    return (0, \%reservation);
}

sub filter_reservation {
    my ($self, $resv) = @_;

    return (0, $resv);
}

#package perfSONAR_PS::DCNStatusPage::Workers::Status;
#
#use strict;
#use warnings;
#
#our $VERSION = 3.1;
#
#use perfSONAR_PS::Client::MA;
#
#use perfSONAR_PS::Utils::ParameterValidation;
#
#use base 'perfSONAR_PS::DCNStatusPage::Workers::Base';
#
#use fields 'MA_URL', 'SHARED_CACHE';
#
#sub init {
#    my ($self, @args) = @_;
#    my $args = validateParams( @args, { ma_url => 1, axis2_home => 1, idc_url => 1, reservations_cache => 1, update_interval => 1, domain => 1, prefill_amount => 1 });
#   
#    my ($status, $res) = $self->SUPER::init({ update_interval => $args->{update_interval} });
#    unless ($status == 0) {
#        return ($status, $res);
#    }
#
#    my $ma = perfSONAR_PS::Client::MA->new( { instance => "http://packrat.internet2.edu:8083/perfSONAR_PS/services/SNMPMA" } );
#
#    $self->{OSCARS_CLIENT} = $args->{oscars_client_dir};
#    $self->{AXIS2_HOME} = $args->{axis2_home};
#    $self->{IDC_URL} = $args->{idc_url};
#    $self->{DOMAIN} = $args->{domain};
#    $self->{RESERVATIONS_CACHE} = $args->{reservations_cache};
#    $self->{PREFILL_AMOUNT} = $args->{prefill_amount};
#
#    return (0, "");
#}
#
#sub handle_task {
#    my ($self) = @_;


