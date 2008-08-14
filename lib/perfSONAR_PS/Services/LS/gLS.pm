package perfSONAR_PS::Services::LS::gLS;

use base 'perfSONAR_PS::Services::Base';

use fields 'STATE', 'LOGGER', 'IPTRIE', 'CLAIMTREE';

use strict;
use warnings;

our $VERSION = 0.10;

=head1 NAME

perfSONAR_PS::Services::LS::gLS - A module that provides methods for the 
perfSONAR-PS Global Lookup Service (gLS).

=head1 DESCRIPTION

This module, in conjunction with other parts of the perfSONAR-PS framework,
handles specific messages from interested actors in search of data and services
that are registered with the gLS.  There are four major message types that this
service can act upon:

 - LSRegisterRequest   -      Given the name of a service and the metadata it
                              contains, register this information into the LS.
                              Special considerations should be given to already
                              registered services that wish to augment already
                              registered data.
 - LSDeregisterRequest -      Removes all or selective data about a specific
                              service already registered in the LS.
 - LSKeepaliveRequest  -      Given some info about already registered data
                              (i.e. a 'key') update the internal state to
                              reflect that this service and it's data are still
                              alive and valid.
 - LSQueryRequest
   LSQueryRequest      -      Given a descriptive query (written in the XPath or
                              XQuery langugages) return any relevant data or a 
                              descriptive error message.
 - LSKeyRequest        -      Given a service description, return the stored 
                              internal key for the dataset.
 - LSSynchronizationRequest - Message used between gLS instances to syncrhonize
                              registered hLS instances.  This keeps the cloud
                              current.
                         
The LS in general offers a web services (WS) interface to the Berkeley/Oracle
DB XML, a native XML database.   

=cut

use Log::Log4perl qw(get_logger);
use Time::HiRes qw(gettimeofday);
use Params::Validate qw(:all);
use Digest::MD5 qw(md5_hex);
use Net::CIDR ':all';
use Net::IPTrie;
use Net::Ping;
use LWP::Simple;
use File::stat;

use perfSONAR_PS::Services::MA::General;
use perfSONAR_PS::Services::LS::General;
use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;
use perfSONAR_PS::DB::XMLDB;
use perfSONAR_PS::Error_compat qw/:try/;
use perfSONAR_PS::ParameterValidation;
use perfSONAR_PS::Client::LS;
use perfSONAR_PS::Client::gLS;

my %ls_namespaces = (
    nmwg          => "http://ggf.org/ns/nmwg/base/2.0/",
    nmtm          => "http://ggf.org/ns/nmwg/time/2.0/",
    ifevt         => "http://ggf.org/ns/nmwg/event/status/base/2.0/",
    iperf         => "http://ggf.org/ns/nmwg/tools/iperf/2.0/",
    bwctl         => "http://ggf.org/ns/nmwg/tools/bwctl/2.0/",
    owamp         => "http://ggf.org/ns/nmwg/tools/owamp/2.0/",
    netutil       => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
    neterr        => "http://ggf.org/ns/nmwg/characteristic/errors/2.0/",
    netdisc       => "http://ggf.org/ns/nmwg/characteristic/discards/2.0/",
    snmp          => "http://ggf.org/ns/nmwg/tools/snmp/2.0/",
    select        => "http://ggf.org/ns/nmwg/ops/select/2.0/",
    average       => "http://ggf.org/ns/nmwg/ops/average/2.0/",
    dcn           => "http://ggf.org/ns/nmwg/tools/dcn/2.0/",
    perfsonar     => "http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/",
    psservice     => "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/",
    xquery        => "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xquery/1.0/",
    xpath         => "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xpath/1.0/",
    summary       => "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/summarization/2.0/",
    pinger        => "http://ggf.org/ns/nmwg/tools/pinger/2.0/",
    nmwgr         => "http://ggf.org/ns/nmwg/result/2.0/",
    traceroute    => "http://ggf.org/ns/nmwg/tools/traceroute/2.0/",
    tracepath     => "http://ggf.org/ns/nmwg/tools/traceroute/2.0/",
    ping          => "http://ggf.org/ns/nmwg/tools/ping/2.0/",
    nmwgt         => "http://ggf.org/ns/nmwg/topology/2.0/",
    nmwgtopo3     => "http://ggf.org/ns/nmwg/topology/base/3.0/",
    nmwgtopo3l4   => "http://ggf.org/ns/nmwg/topology/l4/3.0/",
    nmwgtopo3l3   => "http://ggf.org/ns/nmwg/topology/l3/3.0/",
    nmwgtopo3l2   => "http://ggf.org/ns/nmwg/topology/l2/3.0/",
    nmtb          => "http://ogf.org/schema/network/topology/base/20070828/",
    nmtopo        => "http://ogf.org/schema/network/topology/base/20070828/",
    nmtl2         => "http://ogf.org/schema/network/topology/l2/20070828/",
    nmtl3         => "http://ogf.org/schema/network/topology/l3/20070828/",
    nmtl4         => "http://ogf.org/schema/network/topology/l4/20070828/",
    nmwgt3        => "http://ggf.org/ns/nmwg/topology/base/3.0/",
    nmttcp        => "http://ogf.org/schema/network/topology/l4/20070828/tcp/20070828/",
    nmtudt        => "http://ogf.org/schema/network/topology/l4/20070828/udt/20070828/",
    ethernet      => "http://ogf.org/schema/network/topology/ethernet/20070828/",
    ipv4          => "http://ogf.org/schema/network/topology/ipv4/20070828/",
    ipv6          => "http://ogf.org/schema/network/topology/ipv6/20070828/",
    sonet         => "http://ogf.org/schema/network/topology/sonet/20070828/",
    transport     => "http://ogf.org/schema/network/topology/transport/20070828/",
    nmtb_jul      => "http://ogf.org/schema/network/topology/base/20070707/",
    nmtopo_jul    => "http://ogf.org/schema/network/topology/base/20070707/",
    nmtl2_jul     => "http://ogf.org/schema/network/topology/l2/20070707/",
    nmtl3_jul     => "http://ogf.org/schema/network/topology/l3/20070707/",
    nmtl4_jul     => "http://ogf.org/schema/network/topology/l4/20070707/",
    nmttcp_jul    => "http://ogf.org/schema/network/topology/l4/20070707/tcp/20070707/",
    nmtudt_jul    => "http://ogf.org/schema/network/topology/l4/20070707/udt/20070707/",
    ethernet_jul  => "http://ogf.org/schema/network/topology/ethernet/20070707/",
    ipv4_jul      => "http://ogf.org/schema/network/topology/ipv4/20070707/",
    ipv6_jul      => "http://ogf.org/schema/network/topology/ipv6/20070707/",
    sonet_jul     => "http://ogf.org/schema/network/topology/sonet/20070707/",
    transport_jul => "http://ogf.org/schema/network/topology/transport/20070707/",
    ctrlplane     => "http://ogf.org/schema/network/topology/ctrlPlane/20070707/",
    CtrlPlane     => "http://ogf.org/schema/network/topology/ctrlPlane/20070626/",
    ctrlplane_oct => "http://ogf.org/schema/network/topology/ctrlPlane/20071023/"
);

=head1 API

The offered API is not meant for external use as many of the functions are
relied upon by internal aspects of the perfSONAR-PS framework.

=head2 init($self, $handler)

Called at startup by the daemon when this particular module is loaded into
the perfSONAR-PS deployment.  Checks the configuration file for the necessary
items and fills in others when needed. Initializes the backed metadata storage
(DB XML).  Finally the message handler loads the appropriate message types and
eventTypes for this module.  Any other 'pre-startup' tasks should be placed in
this function.

=cut

sub init {
    my ( $self, $handler ) = @_;
    $self->{LOGGER}    = get_logger("perfSONAR_PS::Services::LS::gLS");
    $self->{STATE}     = ();
    $self->{IPTRIE}    = ();
    $self->{CLAIMTREE} = ();

    unless ( exists $self->{CONF}->{"root_hints_url"} ) {
        $self->{CONF}->{"root_hints_url"} = "http://www.perfsonar.net/gls.root.hints";
    }
    if ( exists $self->{CONF}->{"root_hints_file"} ) {
        if ( exists $self->{DIRECTORY} ) {
            unless ( $self->{CONF}->{"root_hints_file"} =~ "^/" ) {
                $self->{CONF}->{"root_hints_file"} = $self->{DIRECTORY} . "/" . $self->{CONF}->{"root_hints_file"};
            }
        }
    } 
    else {
        $self->{CONF}->{"root_hints_file"} = $self->{DIRECTORY} . "/gls.root.hints";
    }   

    unless ( exists $self->{CONF}->{"gls"}->{"root"} ) {
        $self->{LOGGER}->warn("Setting 'root' to '0'");
        $self->{CONF}->{"gls"}->{"root"} = "0";
    }

    unless ( exists $self->{CONF}->{"gls"}->{"metadata_db_name"}
        and $self->{CONF}->{"gls"}->{"metadata_db_name"} )
    {
        $self->{LOGGER}->error("Value for 'metadata_db_name' is not set.");
        return -1;
    }
    else {
        if ( exists $self->{DIRECTORY} ) {
            unless ( $self->{CONF}->{"gls"}->{"metadata_db_name"} =~ "^/" ) {
                $self->{CONF}->{"gls"}->{"metadata_db_name"} = $self->{DIRECTORY} . "/" . $self->{CONF}->{"gls"}->{"metadata_db_name"};
            }
        }
    }

    unless ( exists $self->{CONF}->{"gls"}->{"metadata_db_file"}
        and $self->{CONF}->{"gls"}->{"metadata_db_file"} )
    {
        $self->{LOGGER}->warn("Setting 'metadata_db_file' to 'glsstore.dbxml'");
        $self->{CONF}->{"gls"}->{"metadata_db_file"} = "glsstore.dbxml";
    }

    unless ( exists $self->{CONF}->{"gls"}->{"metadata_summary_db_file"}
        and $self->{CONF}->{"gls"}->{"metadata_summary_db_file"} )
    {
        $self->{LOGGER}->warn("Setting 'metadata_summary_db_file' to 'glsstore-summary.dbxml'");
        $self->{CONF}->{"gls"}->{"metadata_summary_db_file"} = "glsstore-summary.dbxml";
    }
    
    if ( exists $self->{CONF}->{"gls"}->{"ls_ttl"} and $self->{CONF}->{"gls"}->{"ls_ttl"} ) {
        $self->{CONF}->{"gls"}->{"ls_ttl"} *= 60;
    }
    else {
        $self->{LOGGER}->warn("Setting 'ls_ttl' to '24hrs'.");
        $self->{CONF}->{"gls"}->{"ls_ttl"} = 86400;
    }

    unless ( exists $self->{CONF}->{"gls"}->{"xmldb_reaper_interval"}
        and $self->{CONF}->{"gls"}->{"xmldb_reaper_interval"} )
    {
        if ( exists $self->{CONF}->{"gls"}->{"reaper_interval"}
            and $self->{CONF}->{"gls"}->{"reaper_interval"} ) {
            $self->{LOGGER}->info("Using legacy 'gls:reaper_interval' value: \"".$self->{CONF}->{"gls"}->{"reaper_interval"}."\".");
            $self->{CONF}->{"gls"}->{"xmldb_reaper_interval"} = $self->{CONF}->{"gls"}->{"reaper_interval"};
            delete $self->{CONF}->{"gls"}->{"reaper_interval"};
        }
        else {
            $self->{LOGGER}->warn("Setting 'reaper_interval' to '0'.");
            $self->{CONF}->{"gls"}->{"xmldb_reaper_interval"} = 0;
        }
    }

    $handler->registerFullMessageHandler( "LSRegisterRequest",        $self );
    $handler->registerFullMessageHandler( "LSDeregisterRequest",      $self );
    $handler->registerFullMessageHandler( "LSKeepaliveRequest",       $self );
    $handler->registerFullMessageHandler( "LSQueryRequest",           $self );
    $handler->registerFullMessageHandler( "LSLookupRequest",          $self );
    $handler->registerFullMessageHandler( "LSKeyRequest",             $self );
    $handler->registerFullMessageHandler( "LSSynchronizationRequest", $self );

    my $error = q{};
    my $metadatadb = $self->prepareDatabase( { container => $self->{CONF}->{"gls"}->{"metadata_db_file"} } );
    unless ($metadatadb) {
        $self->{LOGGER}->error( "There was an error opening \"" . $self->{CONF}->{"gls"}->{"metadata_db_name"} . "/" . $self->{CONF}->{"gls"}->{"metadata_db_file"} . "\": " . $error );
        return -1;
    }
    $metadatadb->closeDB( { error => \$error } );

    my $summarydb = $self->prepareDatabase( { container => $self->{CONF}->{"gls"}->{"metadata_summary_db_file"} } );
    unless ($summarydb) {
        $self->{LOGGER}->error( "There was an error opening \"" . $self->{CONF}->{"gls"}->{"metadata_db_name"} . "/" . $self->{CONF}->{"gls"}->{"metadata_summary_db_file"} . "\": " . $error );
        return -1;
    }
    $summarydb->closeDB( { error => \$error } );
    
    $self->getHints();
    
    return 0;
}

=head2 getHints($self, {})

Deletes an existing hints file, retrieves a new one from the hints url.

=cut

sub getHints {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { } );

    if ( exists $self->{CONF}->{"root_hints_url"} and exists $self->{CONF}->{"root_hints_file"} ) {
        my $content = get $self->{CONF}->{"root_hints_url"};
        unless ( $content ) {
            $self->{LOGGER}->error( "There was an error accessing " . $self->{CONF}->{"root_hints_url"} . "." );
            return -1;
        }
        open(HINTS, ">".$self->{CONF}->{"root_hints_file"});
        print HINTS $content;
        close(HINTS);
    }
    else {
        $self->{LOGGER}->error( "Missing gls.root.hints configuration information." );
        return -1;
    }
    return;
}

=head2 prepareDatabase($self, { doc })

Opens the XMLDB and returns the handle if there was not an error.

=cut

sub prepareDatabase {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { container => 1, doc => 0 } );

    my $error = q{};
    my $db    = new perfSONAR_PS::DB::XMLDB(
        {
            env  => $self->{CONF}->{"gls"}->{"metadata_db_name"},
            cont => $parameters->{container},
            ns   => \%ls_namespaces,
        }
    );
    unless ( $db->openDB( { txn => q{}, error => \$error } ) == 0 ) {
        $self->{LOGGER}->error( "There was an error opening \"" . $self->{CONF}->{"gls"}->{"metadata_db_name"} . "/" . $parameters->{container} . "\": " . $error );
        statusReport( $parameters->{doc}, "metadata." . genuid(), q{}, "data." . genuid(), "error.ls.xmldb", $error ) if $parameters->{doc};
        return;
    }

    return $db;
}

=head2 needLS($self)

Stub function that would allow the LS to  synchronization with another LS
isntance.

=cut

sub needLS {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, {} );
    
    return 1;
}

=head2 registerLS($self $sleep_time)

Given the service information (specified in configuration) and the contents of
our metadata database, we can contact the specified LS and register ourselves 
(or in the case or root servers we can synchronize).  We then sleep for some 
amount of time and do it again.

=cut

sub registerLS {
    my ( $self, $sleep_time ) = validateParamsPos( @_, 1, { type => SCALARREF }, );

    my $error = q{};
    my $eventType;
    my $database;    
    if ( -f $self->{CONF}->{"root_hints_file"} ) {
        my $hintsStats = stat( $self->{CONF}->{"root_hints_file"} );        # Is the cache file more than an hour old?
        if ( ( $hintsStats->mtime + 3600 ) < time ) {
            $self->getHints();        }         
    }
    else {
        $self->getHints();
    }

    my $gls = perfSONAR_PS::Client::gLS->new( { file => $self->{CONF}->{"root_hints_file"} } );

    if ( exists $self->{CONF}->{"ls_instance"} ) {
        my @temp = split(/\s+/, $self->{CONF}->{"ls_instance"});
        foreach my $t ( @temp ) {
            $t =~ s/\n$//;
            next if $t eq $self->{CONF}->{"gls"}->{"service_accesspoint"};
            $gls->addRoot ( { root =>  $t } ) if $t;
        } 
    } 
    if ( exists $self->{CONF}->{"gls"}->{"ls_instance"} ) {
        my @temp = split(/\s+/, $self->{CONF}->{"gls"}->{"ls_instance"});
        foreach my $t ( @temp ) {
            $t =~ s/\n$//;
            next if $t eq $self->{CONF}->{"gls"}->{"service_accesspoint"};
            $gls->addRoot ( { root =>  $t } ) if $t;
        }  
    }
    $gls->orderRoots();

    if( $self->{CONF}->{"gls"}->{root} ) {
        # if we are a root, we are 'synchronizing'
    
        $eventType = "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/registration/synchronization/2.0";
        $database = $self->prepareDatabase( { container => $self->{CONF}->{"gls"}->{"metadata_db_file"} } );
        unless ($database) {
            $self->{LOGGER}->error( "There was an error opening \"" . $self->{CONF}->{"gls"}->{"metadata_db_name"} . "/" . $self->{CONF}->{"gls"}->{"metadata_db_file"} . "\": " . $error );
            return -1;
        }    

        my @resultsString = $database->query( { query => "/nmwg:store[\@type=\"LSStore\"]/nmwg:metadata", txn => q{}, error => \$error } );
        if ( $#resultsString != -1 ) {
            my $len = $#resultsString;
            for my $x (0..$len) {
                my $parser = XML::LibXML->new();
                my $doc    = $parser->parse_string( $resultsString[$x] );
                my $service = find($doc->getDocumentElement, "./perfsonar:subject", 1);
                
                my @metadataArray = $database->query( { query => "/nmwg:store[\@type=\"LSStore\"]/nmwg:data[\@metadataIdRef=\"".$doc->getDocumentElement->getAttribute("id")."\"]/nmwg:metadata", txn => q{}, error => \$error } );

                foreach my $root ( @{ $gls->{ROOTS} } ) {
                    my $ls = perfSONAR_PS::Client::LS->new( { instance => $root } );
                    my $result = $ls->keyRequestLS( { servicexml => $service->toString } );
                    if ( exists $result->{key} and $result->{key} ) {
                        my $key = $result->{key};
                        $result = $ls->registerClobberRequestLS( { key => $key, eventType => $eventType, servicexml => $service->toString, data => \@metadataArray } );                        
                        if ( exists $result->{eventType} and $result->{eventType} eq "success.ls.register" ) {
                            my $msg = "Success from LS";
                            $msg .= ", eventType: " . $result->{eventType} if exists $result->{eventType} and $result->{eventType};
                            $msg .= ", response: " . $result->{response} if exists $result->{response} and $result->{response};
                            $self->{LOGGER}->debug( $msg );
                        }
                        else {
                            my $msg = "Error in LS Registration";
                            $msg .= ", eventType: " . $result->{eventType} if exists $result->{eventType} and $result->{eventType};
                            $msg .= ", response: " . $result->{response} if exists $result->{response} and $result->{response};
                            $self->{LOGGER}->error( $msg );
                        }
                    }
                    else {
                        $result = $ls->registerRequestLS( { eventType => $eventType, servicexml => $service->toString, data => \@metadataArray } );
                        if ( exists $result->{eventType} and $result->{eventType} eq "success.ls.register" ) {
                            my $msg = "Success from LS";
                            $msg .= ", eventType: " . $result->{eventType} if exists $result->{eventType} and $result->{eventType};
                            $msg .= ", response: " . $result->{response} if exists $result->{response} and $result->{response};
                            $self->{LOGGER}->debug( $msg );
                        }
                        else {
                            my $msg = "Error in LS Registration";
                            $msg .= ", eventType: " . $result->{eventType} if exists $result->{eventType} and $result->{eventType};
                            $msg .= ", response: " . $result->{response} if exists $result->{response} and $result->{response};
                            $self->{LOGGER}->error( $msg );
                        }
                    }
                }
            }
        }
    }
    else {
        # if we are not a root, send our summary to a root

        my %service = (
            serviceName        => $self->{CONF}->{"gls"}->{"service_name"},
            serviceType        => $self->{CONF}->{"gls"}->{"service_type"},
            serviceDescription => $self->{CONF}->{"gls"}->{"service_description"},
            accessPoint        => $self->{CONF}->{"gls"}->{"service_accesspoint"}
        );

        $eventType = "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/registration/summary/2.0";    
        $database = $self->prepareDatabase( { container => $self->{CONF}->{"gls"}->{"metadata_summary_db_file"} } );
        unless ($database) {
            $self->{LOGGER}->error( "There was an error opening \"" . $self->{CONF}->{"gls"}->{"metadata_db_name"} . "/" . $self->{CONF}->{"gls"}->{"metadata_summary_db_file"} . "\": " . $error );
            return -1;
        } 

        my @resultsString = $database->query( { query => "/nmwg:store[\@type=\"LSStore\"]/nmwg:metadata/\@id", txn => q{}, error => \$error } );
        if ( $#resultsString != -1 ) {
            my $md_len = $#resultsString;
            my @metadataArray = ();
            for my $x (0..$md_len) {
                $resultsString[$x] =~ s/^\{\}id=//;
                $resultsString[$x] =~ s/\"//g;

                my @temp = $database->query( { query => "/nmwg:store[\@type=\"LSStore\"]/nmwg:data[\@metadataIdRef=\"".$resultsString[$x]."\"]/nmwg:metadata", txn => q{}, error => \$error } );
                foreach my $t ( @temp ) {
                    push @metadataArray, $t if $t;
                }                    
            }

            if( $#metadataArray != -1 ) {

                # limit how many gLS instanaces we register with (pick the 3 closest)
                my $len = $#{ $gls->{ROOTS} };
                $len = 2 if $len > 2;
                for my $x ( 0..$len ) {
                    my $root = $gls->{ROOTS}->[$x];

                    my $ls = perfSONAR_PS::Client::LS->new( { instance => $root } );
                
                    my $result = $ls->keyRequestLS( { service => \%service } );
                    if ( exists $result->{key} and $result->{key} ) {
                        my $key = $result->{key};
                        $result = $ls->registerClobberRequestLS( { eventType => $eventType, service => \%service, key => $key, data => \@metadataArray } );
                        if ( exists $result->{eventType} and $result->{eventType} eq "success.ls.register" ) {
                            my $msg = "Success from LS";
                            $msg .= ", eventType: " . $result->{eventType} if exists $result->{eventType} and $result->{eventType};
                            $msg .= ", response: " . $result->{response} if exists $result->{response} and $result->{response};
                            $self->{LOGGER}->debug( $msg );
                        }
                        else {
                            my $msg = "Error in LS Registration";
                            $msg .= ", eventType: " . $result->{eventType} if exists $result->{eventType} and $result->{eventType};
                            $msg .= ", response: " . $result->{response} if exists $result->{response} and $result->{response};
                            $self->{LOGGER}->error( $msg );
                        }
                    }
                    else {
                        $result = $ls->registerRequestLS( { eventType => $eventType, service => \%service, data => \@metadataArray } );
                        if ( exists $result->{eventType} and $result->{eventType} eq "success.ls.register" ) {
                            my $msg = "Success from LS";
                            $msg .= ", eventType: " . $result->{eventType} if exists $result->{eventType} and $result->{eventType};
                            $msg .= ", response: " . $result->{response} if exists $result->{response} and $result->{response};
                            $self->{LOGGER}->debug( $msg );
                        }
                        else {
                            my $msg = "Error in LS Registration";
                            $msg .= ", eventType: " . $result->{eventType} if exists $result->{eventType} and $result->{eventType};
                            $msg .= ", response: " . $result->{response} if exists $result->{response} and $result->{response};
                            $self->{LOGGER}->error( $msg );
                        }
                    } 
                }
            }
        }
        else {
            $self->{LOGGER}->error("Nothing to register at this time.");
        }   
        
    }
    
    $database->closeDB( { error => \$error } );
    return 0;
}

=head2 summarizeLS($self)

Summarize the contents of the LSs registration dataset.

=cut

sub summarizeLS {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { error => 0 } );
    my ( $sec, $frac ) = Time::HiRes::gettimeofday;

    my $error     = q{};
    my $errorFlag = 0;
    my $metadatadb = $self->prepareDatabase( { container => $self->{CONF}->{"gls"}->{"metadata_db_file"} } );
    unless ($metadatadb) {
        $self->{LOGGER}->error( "There was an error opening \"" . $self->{CONF}->{"gls"}->{"metadata_db_name"} . "/" . $self->{CONF}->{"gls"}->{"metadata_db_file"} . "\": " . $error );
        return -1;
    }

    my $dbTr = $metadatadb->getTransaction( { error => \$error } );
    unless ($dbTr) {
        $metadatadb->abortTransaction( { txn => $dbTr, error => \$error } ) if $dbTr;
        undef $dbTr;
        $self->{LOGGER}->error( "Cound not start database transaction, database responded with \"" . $error . "\"." );
    }

    my @serviceString = $metadatadb->query( { query => "/nmwg:store[\@type=\"LSStore\"]/nmwg:metadata", txn => $dbTr, error => \$error } );
    $errorFlag++ if $error;
    if ( $#serviceString != -1 ) {
        my $numServices = $#serviceString;
        my $all_eventTypes;
        my $all_addresses;
        my $all_domains;
        my $all_keywords;

        my $sum_error     = q{};
        my $sum_errorFlag = 0;
        my $summarydb     = $self->prepareDatabase( { container => $self->{CONF}->{"gls"}->{"metadata_summary_db_file"} } );
        unless ($summarydb) {
            $self->{LOGGER}->error( "There was an error opening \"" . $self->{CONF}->{"gls"}->{"metadata_db_name"} . "/" . $self->{CONF}->{"gls"}->{"metadata_summary_db_file"} . "\": " . $sum_error );
            return -1;
        }

        my $sum_dbTr = $summarydb->getTransaction( { error => \$sum_error } );
        unless ($sum_dbTr) {
            $summarydb->abortTransaction( { txn => $sum_dbTr, error => \$sum_error } ) if $sum_dbTr;
            undef $sum_dbTr;
            $self->{LOGGER}->error( "Cound not start database transaction, database responded with \"" . $sum_error . "\"." );
        }

        for my $x ( 0 .. $numServices ) {
            my $parser = XML::LibXML->new();
            my $doc    = $parser->parse_string( $serviceString[$x] );

            my $service_mdId = $doc->getDocumentElement->getAttribute("id");                     
         
            my $contactPoint = extract( find( $doc->getDocumentElement, "./*[local-name()='subject']/*[local-name()='service']/*[local-name()='accessPoint']", 1 ), 0 );
            my $contactName;
            my $contactType;
            unless ( $contactPoint ) {
                $contactPoint = extract( find( $doc->getDocumentElement, "./*[local-name()='subject']/*[local-name()='service']/*[local-name()='address']", 1 ), 0 );
                $contactName = extract( find( $doc->getDocumentElement, "./*[local-name()='subject']/*[local-name()='service']/*[local-name()='name']", 1 ), 0 );
                $contactType = extract( find( $doc->getDocumentElement, "./*[local-name()='subject']/*[local-name()='service']/*[local-name()='type']", 1 ), 0 );
                unless ( $contactPoint ) {
                    return;
                }
            }            
# warning is thrown off
            my $serviceKey = md5_hex( $contactPoint.$contactName.$contactType );    
                        
            my @resultsString = $metadatadb->query( { query => "/nmwg:store[\@type=\"LSStore\"]/nmwg:data[\@metadataIdRef=\"".$service_mdId."\"]/nmwg:metadata", txn => $dbTr, error => \$error } );
            $errorFlag++ if $error;
            if ( $#resultsString != -1 ) {
                my $len = $#resultsString;
                my $service_eventTypes;
                my $service_addresses;
                my $service_domains;
                my $service_keywords;

                for my $x ( 0 .. $len ) {
                    my $doc2 = $parser->parse_string( $resultsString[$x] );
                    
                    # eventTypes common to both...
                    my $temp_eventTypes = find( $doc2->getDocumentElement, "./nmwg:eventType", 0 );
                    my $temp_supportedEventTypes = find( $doc2->getDocumentElement, ".//nmwg:parameter[\@name=\"supportedEventType\" or \@name=\"eventType\"]", 0 );
                    foreach my $e ( $temp_eventTypes->get_nodelist ) {
                        my $value = extract( $e, 0 );
                        if ($value) {
                            $service_eventTypes->{$value} = 1;
                            $all_eventTypes->{$value} = 1;
                        }
                    }
                    foreach my $se ( $temp_supportedEventTypes->get_nodelist ) {
                        my $value = extract( $se, 0 );
                        if ($value) {
                            $service_eventTypes->{$value} = 1;
                            $all_eventTypes->{$value} = 1;
                        }
                    }  

                    my $temp_keywords = find( $doc2->getDocumentElement, ".//nmwg:parameter[\@name=\"keyword\"]", 0 );
                    foreach my $k ( $temp_keywords->get_nodelist ) {
                        my $value = extract( $k, 0 );
                        if ($value) {
                            $service_keywords->{$value} = 1;
                            $all_keywords->{$value} = 1;
                        }
                    }  

                    if ( $self->{CONF}->{"gls"}->{"root"} ) {
                
                        my $temp_networks = find( $doc2->getDocumentElement, "./summary:subject/nmtl3:network", 0 );
                        foreach my $n ( $temp_networks->get_nodelist ) {
                            my $address = extract( find( $n, "./nmtl3:subnet/nmtl3:address", 1 ), 0 );
                            my $mask = extract( find( $n, "./nmtl3:subnet/nmtl3:netmask", 1 ), 0 );
                            if ( $address ) {
                                $address .= "/" . $mask if $mask;
                                $service_addresses->{$address} = 1;
                                $all_addresses->{$address} = 1;                                
                            }
                        }       
                
                        my $temp_domains = find( $doc2->getDocumentElement, "./summary:subject/nmtb:domain", 0 );
                        foreach my $d ( $temp_domains->get_nodelist ) {
                            my $name = extract( find( $d, "./nmtb:name", 1 ), 0 );
                            if ( $name ) {
                                $service_domains->{$name} = 1;
                                $all_domains->{$name} = 1;
                            }
                        }  
                         
                    }
                    else {
                        # topology junk (interface)
                        my $temp_interfaces = find( $doc2->getDocumentElement, "./*[local-name()='subject']/*[local-name()='interface']", 0 );
                        foreach my $interface ( $temp_interfaces->get_nodelist ) {
                            my @elements = ( "address", "ipAddress", "ifAddress", "name" );
                            my @types = ( "ipv4", "IPv4" );
                            $service_addresses = $self->summarizeAddress( { search => $interface, elements => \@elements, types => \@types, addresses => $service_addresses } );
                            $all_addresses = $self->summarizeAddress( { search => $interface, elements => \@elements, types => \@types, addresses => $all_addresses } );
                                
                            my @hosts = ();
                            @types = ( "hostname", "hostName", "host", "dns", "DNS" );
                            push @hosts, extract( find( $interface, "./*[local-name()='hostName']", 1 ), 0 );
                            $service_domains = $self->summarizeHosts( { search => $interface, elements => \@elements, types => \@types, hostarray => \@hosts, hosts => $service_domains } );    
                            $all_domains = $self->summarizeHosts( { search => $interface, elements => \@elements, types => \@types, hostarray => \@hosts, hosts => $all_domains } );                                
                        
                            my @urns = ();
                            @types = ( "urn", "URN" );
                            my $id = $interface->getAttribute("id");
                            push @urns, $id if $id and $id =~ m/^urn:ogf:network:/; 
                            $service_domains = $self->summarizeURN( { search => $interface, elements => \@elements, types => \@types, urnarray => \@urns, urns => $service_domains } );    
                            $all_domains = $self->summarizeURN( { search => $interface, elements => \@elements, types => \@types, urnarray => \@urns, urns => $all_domains } );
                        }

                        # topology junk (port)
                        my $temp_ports = find( $doc2->getDocumentElement, "./*[local-name()='subject']/*[local-name()='port']", 0 );
                        foreach my $port ( $temp_ports->get_nodelist ) {
# what do we do here...
                            my $netmask = extract( find( $port, "./*[local-name()='netmask']", 1 ), 0 );

                            my @elements = ( "address", "ipAddress", "name" );
                            my @types = ( "ipv4", "IPv4" );
                            $service_addresses = $self->summarizeAddress( { search => $port, elements => \@elements, types => \@types, addresses => $service_addresses } );    
                            $all_addresses = $self->summarizeAddress( { search => $port, elements => \@elements, types => \@types, addresses => $all_addresses } );                                
                                
                            my @hosts = ();
                            @types = ( "hostname", "hostName", "host", "dns", "DNS" );
                            $service_domains = $self->summarizeHosts( { search => $port, elements => \@elements, types => \@types, hostarray => \@hosts, hosts => $service_domains } );
                            $all_domains = $self->summarizeHosts( { search => $port, elements => \@elements, types => \@types, hostarray => \@hosts, hosts => $all_domains } );    

                            my @urns = ();
                            @types = ( "urn", "URN" );
                            my $id = $port->getAttribute("id");
                            push @urns, $id if $id and $id =~ m/^urn:ogf:network:/; 
                            $service_domains = $self->summarizeURN( { search => $port, elements => \@elements, types => \@types, urnarray => \@urns, urns => $service_domains } );    
                            $all_domains = $self->summarizeURN( { search => $port, elements => \@elements, types => \@types, urnarray => \@urns, urns => $all_domains } );
                        }

                        # topology junk (node)
                        my $temp_nodes = find( $doc2->getDocumentElement, "./*[local-name()='subject']/*[local-name()='node']", 0 );
                        foreach my $node ( $temp_nodes->get_nodelist ) {
                            my @elements = ( "address", "ipAddress", "name" );
                            my @types = ( "ipv4", "IPv4" );
                            $service_addresses = $self->summarizeAddress( { search => $node, elements => \@elements, types => \@types, addresses => $service_addresses } );
                            $all_addresses = $self->summarizeAddress( { search => $node, elements => \@elements, types => \@types, addresses => $all_addresses } );

                            my @hosts = ();
                            @types = ( "hostname", "hostName", "host", "dns", "DNS" );
                            $service_domains = $self->summarizeHosts( { search => $node, elements => \@elements, types => \@types, hostarray => \@hosts, hosts => $service_domains } );
                            $all_domains = $self->summarizeHosts( { search => $node, elements => \@elements, types => \@types, hostarray => \@hosts, hosts => $all_domains } );   

                            my @urns = ();
                            @types = ( "urn", "URN" );
                            my $id = $node->getAttribute("id");
                            push @urns, $id if $id and $id =~ m/^urn:ogf:network:/; 
                            push @urns, extract( find( $node, "./*[local-name()='relation' and \@type=\"connectionLink\"]/nmtb:linkIdRef", 1 ), 0 );                            
                            $service_domains = $self->summarizeURN( { search => $node, elements => \@elements, types => \@types, urnarray => \@urns, urns => $service_domains } );    
                            $all_domains = $self->summarizeURN( { search => $node, elements => \@elements, types => \@types, urnarray => \@urns, urns => $all_domains } );
                        }

                        # topology junk (network)
                        my $temp_networks = find( $doc2->getDocumentElement, "./*[local-name()='subject']/*[local-name()='network']", 0 );
                        foreach my $network ( $temp_networks->get_nodelist ) {
# what do we do here...
                            my $subaddress = extract( find( $network, "./*[local-name()='subnet']/*[local-name()='address']", 1 ), 0 );
                            my $subnetmask = extract( find( $network, "./*[local-name()='subnet']/*[local-name()='netmask']", 1 ), 0 );

                            my @elements = ("name");
                            my @types = ( "ipv4", "IPv4" );
                            $service_addresses = $self->summarizeAddress( { search => $network, elements => \@elements, types => \@types, addresses => $service_addresses } );   
                            $all_addresses = $self->summarizeAddress( { search => $network, elements => \@elements, types => \@types, addresses => $all_addresses } );
                                                                
                            my @hosts = ();
                            @types = ( "hostname", "hostName", "host", "dns", "DNS" );
                            $service_domains = $self->summarizeHosts( { search => $network, elements => \@elements, types => \@types, hostarray => \@hosts, hosts => $service_domains } );
                            $all_domains = $self->summarizeHosts( { search => $network, elements => \@elements, types => \@types, hostarray => \@hosts, hosts => $all_domains } );  

                            my @urns = ();
                            @types = ( "urn", "URN" );
                            my $id = $network->getAttribute("id");
                            push @urns, $id if $id and $id =~ m/^urn:ogf:network:/; 
                            $service_domains = $self->summarizeURN( { search => $network, elements => \@elements, types => \@types, urnarray => \@urns, urns => $service_domains } );    
                            $all_domains = $self->summarizeURN( { search => $network, elements => \@elements, types => \@types, urnarray => \@urns, urns => $all_domains } );
                        }

                        # topology junk (domain)
                        my $temp_domains = find( $doc2->getDocumentElement, "./*[local-name()='subject']/*[local-name()='domain']", 0 );
                        foreach my $domain ( $temp_domains->get_nodelist ) {   
                            my @hosts    = ();
                            my @elements = ("name");
                            my @types    = ( "hostname", "hostName", "host", "dns", "DNS" );
                            $service_domains = $self->summarizeHosts( { search => $domain, elements => \@elements, types => \@types, hostarray => \@hosts, hosts => $service_domains } );
                            $all_domains = $self->summarizeHosts( { search => $domain, elements => \@elements, types => \@types, hostarray => \@hosts, hosts => $all_domains } );    

                            my @urns = ();
                            @types = ( "urn", "URN" );
                            my $id = $domain->getAttribute("id");
                            push @urns, $id if $id and $id =~ m/^urn:ogf:network:/; 
                            $service_domains = $self->summarizeURN( { search => $domain, elements => \@elements, types => \@types, urnarray => \@urns, urns => $service_domains } );    
                            $all_domains = $self->summarizeURN( { search => $domain, elements => \@elements, types => \@types, urnarray => \@urns, urns => $all_domains } );
                        }

                        # topology junk (service)
                        my $temp_services = find( $doc2->getDocumentElement, "./*[local-name()='subject']/*[local-name()='service']", 0 );
                        my $temp_test = find( $doc2->getDocumentElement, "./*[local-name()='subject']", 0 );
                        foreach my $service ( $temp_services->get_nodelist ) {     
                            my @elements = ( "address", "ipAddress", "name" );
                            my @types = ( "ipv4", "IPv4" );
                            $service_addresses = $self->summarizeAddress( { search => $service, elements => \@elements, types => \@types, addresses => $service_addresses } );    
                            $all_addresses = $self->summarizeAddress( { search => $service, elements => \@elements, types => \@types, addresses => $all_addresses } );
                                                            
                            my @hosts = ();
                            @types = ( "hostname", "hostName", "host", "dns", "DNS" );
                            $service_domains = $self->summarizeHosts( { search => $service, elements => \@elements, types => \@types, hostarray => \@hosts, hosts => $service_domains } );
                            $all_domains = $self->summarizeHosts( { search => $service, elements => \@elements, types => \@types, hostarray => \@hosts, hosts => $all_domains } );    

                            my @urns = ();
                            @types = ( "urn", "URN" );
                            my $id = $service->getAttribute("id");
                            push @urns, $id if $id and $id =~ m/^urn:ogf:network:/; 
                            $service_domains = $self->summarizeURN( { search => $service, elements => \@elements, types => \@types, urnarray => \@urns, urns => $service_domains } );    
                            $all_domains = $self->summarizeURN( { search => $service, elements => \@elements, types => \@types, urnarray => \@urns, urns => $all_domains } );
                        }

                        # topology junk (endPointPair)
                        my $temp_endpointpairs = find( $doc2->getDocumentElement, "./*[local-name()='subject']/*[local-name()='endPointPair']", 0 );
                        foreach my $endpointpair ( $temp_endpointpairs->get_nodelist ) {
                            my @elements = ( ".", "address", "ipAddress", "name", "src", "dst" );
                            my @types = ( "ipv4", "IPv4" );
                            $service_addresses = $self->summarizeAddress( { search => $endpointpair, elements => \@elements, types => \@types, addresses => $service_addresses } );
                            $all_addresses = $self->summarizeAddress( { search => $endpointpair, elements => \@elements, types => \@types, addresses => $all_addresses } );
                                
                            my @hosts = ();
                            @types = ( "hostname", "hostName", "host", "dns", "DNS" );
                            $service_domains = $self->summarizeHosts( { search => $endpointpair, elements => \@elements, types => \@types, hostarray => \@hosts, hosts => $service_domains } );                               
                            $all_domains = $self->summarizeHosts( { search => $endpointpair, elements => \@elements, types => \@types, hostarray => \@hosts, hosts => $all_domains } );     

                            my @urns = ();
                            @types = ( "urn", "URN" );
                            my $id = $endpointpair->getAttribute("id");
                            push @urns, $id if $id and $id =~ m/^urn:ogf:network:/; 
                            $service_domains = $self->summarizeURN( { search => $endpointpair, elements => \@elements, types => \@types, urnarray => \@urns, urns => $service_domains } );    
                            $all_domains = $self->summarizeURN( { search => $endpointpair, elements => \@elements, types => \@types, urnarray => \@urns, urns => $all_domains } );
                        }

                        # topology junk (endPointPair)
                        $temp_endpointpairs = find( $doc2->getDocumentElement, "./*[local-name()='subject']/*[local-name()='endPointPair']/*[local-name()='endPoint']", 0 );
                        foreach my $endpointpair ( $temp_endpointpairs->get_nodelist ) {
                            my @elements = ( ".", "address", "ipAddress", "name", "src", "dst" );
                            my @types = ( "ipv4", "IPv4" );
                            $service_addresses = $self->summarizeAddress( { search => $endpointpair, elements => \@elements, types => \@types, addresses => $service_addresses } );    
                            $all_addresses = $self->summarizeAddress( { search => $endpointpair, elements => \@elements, types => \@types, addresses => $all_addresses } );
                                                                
                            my @hosts = ();
                            @types = ( "hostname", "hostName", "host", "dns", "DNS" );
                            $service_domains = $self->summarizeHosts( { search => $endpointpair, elements => \@elements, types => \@types, hostarray => \@hosts, hosts => $service_domains } );
                            $all_domains = $self->summarizeHosts( { search => $endpointpair, elements => \@elements, types => \@types, hostarray => \@hosts, hosts => $all_domains } );    

                            my @urns = ();
                            @types = ( "urn", "URN" );
                            my $id = $endpointpair->getAttribute("id");
                            push @urns, $id if $id and $id =~ m/^urn:ogf:network:/; 
                            $service_domains = $self->summarizeURN( { search => $endpointpair, elements => \@elements, types => \@types, urnarray => \@urns, urns => $service_domains } );    
                            $all_domains = $self->summarizeURN( { search => $endpointpair, elements => \@elements, types => \@types, urnarray => \@urns, urns => $all_domains } );
                        }

                        # topology junk (endPoint)
                        my $temp_endpoints = find( $doc2->getDocumentElement, "./*[local-name()='subject']/*[local-name()='endPoint']", 0 );
                        foreach my $endpoint ( $temp_endpoints->get_nodelist ) {     
                            my @elements = ( ".", "address", "ipAddress", "name", "src", "dst" );
                            my @types = ( "ipv4", "IPv4" );
                            $service_addresses = $self->summarizeAddress( { search => $endpoint, elements => \@elements, types => \@types, addresses => $service_addresses } );
                            $all_addresses = $self->summarizeAddress( { search => $endpoint, elements => \@elements, types => \@types, addresses => $all_addresses } );
                                
                            my @hosts = ();
                            @types = ( "hostname", "hostName", "host", "dns", "DNS" );
                            $service_domains = $self->summarizeHosts( { search => $endpoint, elements => \@elements, types => \@types, hostarray => \@hosts, hosts => $service_domains } );                            
                            $all_domains = $self->summarizeHosts( { search => $endpoint, elements => \@elements, types => \@types, hostarray => \@hosts, hosts => $all_domains } );                                                   

                            my @urns = ();
                            @types = ( "urn", "URN" );
                            my $id = $endpoint->getAttribute("id");
                            push @urns, $id if $id and $id =~ m/^urn:ogf:network:/; 
                            $service_domains = $self->summarizeURN( { search => $endpoint, elements => \@elements, types => \@types, urnarray => \@urns, urns => $service_domains } );    
                            $all_domains = $self->summarizeURN( { search => $endpoint, elements => \@elements, types => \@types, urnarray => \@urns, urns => $all_domains } );
                        }          
                    }        
                }
                # specific service done

                my $list1;
                if ( $self->{CONF}->{"gls"}->{"root"} ) {
                    foreach my $host ( keys %{ $service_addresses } ) {
                        push @{$list1}, $host; 
                    }
                }
                else {
                    $list1 = $self->ipSummarization( { addresses => $service_addresses } ) if defined $service_addresses;
                }
                my $serviceSummary = $self->makeSummary( { key => $serviceKey, addresses => $list1, domains => $service_domains, eventTypes => $service_eventTypes, keywords => $service_keywords } );

                unless ( exists $self->{STATE}->{"messageKeys"}->{$serviceKey} ) {
                    $self->{STATE}->{"messageKeys"}->{$serviceKey} = $self->isValidKey( { database => $summarydb, key => $serviceKey, txn => $sum_dbTr } );
                }

                # should delete the data here...
                $self->{LOGGER}->debug( "Removing data for \"" . $serviceKey . "\" so we can start clean." );
                my @resultsString2 = $summarydb->queryForName( { query => "/nmwg:store[\@type=\"LSStore\"]/nmwg:data[\@metadataIdRef=\"" . $serviceKey . "\"]", txn => $sum_dbTr, error => \$sum_error } );
                $sum_errorFlag++ if $sum_error;
                my $len2 = $#resultsString2;
                for my $y ( 0 .. $len2 ) {
                    $summarydb->remove( { name => $resultsString2[$y], txn => $sum_dbTr, error => \$sum_error } );
                    $sum_errorFlag++ if $sum_error;
                }

                my $auth = 1;
                unless ( $self->{STATE}->{"messageKeys"}->{$serviceKey} == 2 ) {
                    if ( $self->{STATE}->{"messageKeys"}->{$serviceKey} ) {
                        $self->{LOGGER}->debug("Key already exists, but updating control time information anyway.");
                        $summarydb->updateByName( { content => createControlKey( { key => $serviceKey, time => ( $sec + $self->{CONF}->{"gls"}->{"ls_ttl"} ), auth => $auth } ), name => $serviceKey . "-control", txn => $sum_dbTr, error => \$sum_error } );
                        $sum_errorFlag++ if $sum_error;            
                    }
                    else {
                        $self->{LOGGER}->debug("New registration info, inserting service metadata and time information.");

                        $doc->getDocumentElement->setAttribute("id", $serviceKey); 
                        $summarydb->insertIntoContainer( { content => $summarydb->wrapStore( { content => $doc->getDocumentElement->toString, type => "LSStore" } ), name => $serviceKey, txn => $sum_dbTr, error => \$sum_error } );
                        $sum_errorFlag++ if $sum_error;
                        $summarydb->insertIntoContainer( { content => createControlKey( { key => $serviceKey, time => ( $sec + $self->{CONF}->{"gls"}->{"ls_ttl"} ), auth => $auth } ), name => $serviceKey . "-control", txn => $sum_dbTr, error => \$sum_error } );
                        $sum_errorFlag++ if $sum_error;
                    }
                    $self->{STATE}->{"messageKeys"}->{$serviceKey} = 2;
                }

                my $cleanHash = md5_hex($serviceSummary);
                my $success = $summarydb->queryByName( { name => $serviceKey . "/" . $cleanHash, txn => $sum_dbTr, error => \$sum_error } );

                $sum_errorFlag++ if $sum_error;
                unless ($success) {
                    my $insRes = $summarydb->insertIntoContainer( { content => createLSData( { type => "LSStore", dataId => $serviceKey . "/" . $cleanHash, metadataId => $serviceKey, data => $serviceSummary } ), name => $serviceKey . "/" . $cleanHash, txn => $sum_dbTr, error => \$sum_error } );
                    $sum_errorFlag++ if $sum_error;
                }
            }
            else {
                $self->{LOGGER}->error("Data not registered for service with metadataId \"".$service_mdId."\", cannot summarize at this time.");
            }  
        }

        my %service_conf = (
            serviceName        => $self->{CONF}->{"gls"}->{"service_name"},
            serviceType        => $self->{CONF}->{"gls"}->{"service_type"},
            serviceDescription => $self->{CONF}->{"gls"}->{"service_description"},
            accessPoint        => $self->{CONF}->{"gls"}->{"service_accesspoint"}
        );

        my $mdKey = md5_hex( $self->{CONF}->{"gls"}->{"service_accesspoint"} );

        my $ls_client = perfSONAR_PS::Client::LS->new( { instance => $self->{CONF}->{"gls"}->{"service_accesspoint"} } );
        my $service2 = "  <nmwg:metadata xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\" id=\"" . $mdKey . "\">\n" . $ls_client->createService( { service => \%service_conf } ) . "  </nmwg:metadata>\n";

        my $list2;
        if ( $self->{CONF}->{"gls"}->{"root"} ) {
            foreach my $host ( keys %{ $all_addresses } ) {
                push @{$list2}, $host; 
            }
        }
        else {
            $list2 = $self->ipSummarization( { addresses => $all_addresses } ) if defined $all_addresses;
        }

        my $totalSummary = $self->makeSummary( { key => $mdKey, addresses => $list2, domains => $all_domains, eventTypes => $all_eventTypes, keywords => $all_keywords } );

        unless ( exists $self->{STATE}->{"messageKeys"}->{$mdKey} ) {
            $self->{STATE}->{"messageKeys"}->{$mdKey} = $self->isValidKey( { database => $summarydb, key => $mdKey, txn => $sum_dbTr } );
        }

        # should delete the data here...
        $self->{LOGGER}->debug( "Removing data for \"" . $mdKey . "\" so we can start clean." );
        my @resultsString2 = $summarydb->queryForName( { query => "/nmwg:store[\@type=\"LSStore-summary\"]/nmwg:data[\@metadataIdRef=\"" . $mdKey . "\"]", txn => $sum_dbTr, error => \$sum_error } );
        $sum_errorFlag++ if $sum_error;
        my $len2 = $#resultsString2;
        for my $y ( 0 .. $len2 ) {
            $summarydb->remove( { name => $resultsString2[$y], txn => $sum_dbTr, error => \$sum_error } );
            $sum_errorFlag++ if $sum_error;
        }

        my $auth = 1;
        unless ( $self->{STATE}->{"messageKeys"}->{$mdKey} == 2 ) {
            if ( $self->{STATE}->{"messageKeys"}->{$mdKey} ) {
                $self->{LOGGER}->debug("Key already exists, but updating control time information anyway.");
                $summarydb->updateByName( { content => createControlKey( { key => $mdKey, time => ( $sec + $self->{CONF}->{"gls"}->{"ls_ttl"} ), auth => $auth } ), name => $mdKey . "-control", txn => $sum_dbTr, error => \$sum_error } );
                $sum_errorFlag++ if $sum_error;            
            }
            else {
                $self->{LOGGER}->debug("New registration info, inserting service metadata and time information.");

                $summarydb->insertIntoContainer( { content => $summarydb->wrapStore( { content => $service2, type => "LSStore-summary" } ), name => $mdKey, txn => $sum_dbTr, error => \$sum_error } );
                $sum_errorFlag++ if $sum_error;
                $summarydb->insertIntoContainer( { content => createControlKey( { key => $mdKey, time => ( $sec + $self->{CONF}->{"gls"}->{"ls_ttl"} ), auth => $auth } ), name => $mdKey . "-control", txn => $sum_dbTr, error => \$sum_error } );
                $sum_errorFlag++ if $sum_error;
            }
            $self->{STATE}->{"messageKeys"}->{$mdKey} = 2;
        }

        my $cleanHash = md5_hex($totalSummary);
        my $success = $summarydb->queryByName( { name => $mdKey . "/" . $cleanHash, txn => $sum_dbTr, error => \$sum_error } );

        $sum_errorFlag++ if $sum_error;
        unless ($success) {
            my $insRes = $summarydb->insertIntoContainer( { content => createLSData( { type => "LSStore-summary", dataId => $mdKey . "/" . $cleanHash, metadataId => $mdKey, data => $totalSummary } ), name => $mdKey . "/" . $cleanHash, txn => $sum_dbTr, error => \$sum_error } );
            $sum_errorFlag++ if $sum_error;
        }

        if ($sum_errorFlag) {
            $summarydb->abortTransaction( { txn => $sum_dbTr, error => \$sum_error } ) if $sum_dbTr;
            undef $sum_dbTr;
            $summarydb->closeDB( { error => \$sum_error } );
            $self->{LOGGER}->error("Database errors prevented the transaction from completing.");
            return -1;
        }
        else {
            my $status = $summarydb->commitTransaction( { txn => $sum_dbTr, error => \$sum_error } );
            if ( $status == 0 ) {
                undef $sum_dbTr;
                $summarydb->closeDB( { error => \$sum_error } );
            }
            else {
                $summarydb->abortTransaction( { txn => $sum_dbTr, error => \$sum_error } ) if $sum_dbTr;
                undef $sum_dbTr;
                $summarydb->closeDB( { error => \$sum_error } );
                $self->{LOGGER}->error( "Database Error: \"" . $sum_error . "\"." );
                return -1;
            }
        } 
    }
    else {
        $self->{LOGGER}->error("Services not registered, cannot summarize at this time.");
    }  

    if ($errorFlag) {
        $metadatadb->abortTransaction( { txn => $dbTr, error => \$error } ) if $dbTr;
        undef $dbTr;
        $metadatadb->closeDB( { error => \$error } );
        $self->{LOGGER}->error("Database errors prevented the transaction from completing.");
        return -1;
    }
    else {
        my $status = $metadatadb->commitTransaction( { txn => $dbTr, error => \$error } );
        if ( $status == 0 ) {
            undef $dbTr;
            $metadatadb->closeDB( { error => \$error } );
        }
        else {
            $metadatadb->abortTransaction( { txn => $dbTr, error => \$error } ) if $dbTr;
            undef $dbTr;
            $metadatadb->closeDB( { error => \$error } );
            $self->{LOGGER}->error( "Database Error: \"" . $error . "\"." );
            return -1;
        }
    }
    return 0;
}

=head2 makeSummary( $self, { key, addresses, domains, eventTypes } )

Given the summary information, create a summary metadata that we can register
internally as well as with other LS instances.

=cut

sub makeSummary {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { key => 1, addresses => 0, domains => 0, eventTypes => 0, keywords => 0 } );

    my $summary = q{};
    $summary .= "    <nmwg:metadata xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\" id=\"metadata." . $parameters->{key} . "\">\n";
    $summary .= "      <summary:subject xmlns:summary=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/summarization/2.0/\" id=\"subject." . $parameters->{key} . "\">\n";
    if ( exists $parameters->{addresses} and $parameters->{addresses} ) {
        foreach my $l ( @{ $parameters->{addresses} } ) {
            my @array = split( /\//, $l );
            $summary .= "        <nmtl3:network xmlns:nmtl3=\"http://ogf.org/schema/network/topology/l3/20070828/\">\n";
            $summary .= "          <nmtl3:subnet>\n";
            if ( $array[0] and $array[1] ) {
                $summary .= "            <nmtl3:address type=\"ipv4\">" . $array[0] . "</nmtl3:address>\n";
                $summary .= "            <nmtl3:netmask>" . $array[1] . "</nmtl3:netmask>\n";
            }
            else {
                $summary .= "            <nmtl3:address type=\"ipv4\">" . $l . "</nmtl3:address>\n";
            }
            $summary .= "          </nmtl3:subnet>\n";
            $summary .= "        </nmtl3:network>\n";
        }
    }
    if ( exists $parameters->{domains} and $parameters->{domains} ) {
        foreach my $d ( keys %{ $parameters->{domains} } ) {
            $summary .= "        <nmtb:domain xmlns:nmtb=\"http://ogf.org/schema/network/topology/base/20070828/\">\n";
            $summary .= "          <nmtb:name type=\"dns\">" . $d . "</nmtb:name>\n";
            $summary .= "        </nmtb:domain>\n";
        }
    }
    $summary .= "      </summary:subject>\n";
    if ( exists $parameters->{eventTypes} and $parameters->{eventTypes} ) {
        foreach my $et ( keys %{ $parameters->{eventTypes} } ) {
            $summary .= "      <nmwg:eventType>" . $et . "</nmwg:eventType>\n";
        }
        $summary .= "      <summary:parameters xmlns:summary=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/summarization/2.0/\" id=\"parameters." . $parameters->{key} . "\">\n";
        foreach my $et ( keys %{ $parameters->{eventTypes} } ) {
            $summary .= "        <nmwg:parameter name=\"eventType\" value=\"" . $et . "\" />\n";
        }
        foreach my $k ( keys %{ $parameters->{keywords} } ) {
            $summary .= "        <nmwg:parameter name=\"keyword\" value=\"" . $k . "\" />\n";
        }
        $summary .= "      </summary:parameters>\n";
    } 
    $summary .= "    </nmwg:metadata>\n";
    return $summary;
}

=head2 summarizeURN($self, { search, elements, types, urnarray, urns } );

...

=cut

sub summarizeURN {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { search => 1, elements => 1, types => 1, urnarray => 1, urns => 1 } );

    foreach my $element ( @{ $parameters->{elements} } ) {
        foreach my $type ( @{ $parameters->{types} } ) {
            my $temp_urns = find( $parameters->{search}, ".//*[local-name()='" . $element . "' and \@type=\"" . $type . "\"]", 0 );
            foreach my $urn ( $temp_urns->get_nodelist ) {        
                push @{ $parameters->{urnarray} }, extract( $urn, 0 );
            }
        }
    }

    foreach my $urn ( @{ $parameters->{urnarray} } ) {
        $urn =~ s/^urn:ogf:network://;
        my @fields = split(/:/, $urn);
        foreach my $field ( @fields ) {
            if ( $field =~ m/^domain=/ ) {
                $field =~ s/^domain=//;                
                my @urnArray = split( /\./, $field );
                my $urn_len = $#urnArray;
                for my $len ( 1 .. $urn_len ) {
                    my $cat = q{};
                    for my $len2 ( $len .. $urn_len ) {
                        $cat .= "." . $urnArray[$len2];
                    }
                    $cat =~ s/^\.//;
                    $parameters->{urns}->{$cat} = 1 if $cat;
                }
                
                # we are stopping after domain for now...
                last;
            }
        }
    }

    return $parameters->{urns};
}

=head2 summarizeAddress( $self, { search, elements, types, addresses } );

Given a topology element, a list of possible sub-elements, and types, extract
IP addresses and return them in a hash reference.  We will later summarize
these into CIDR ranges.

=cut

sub summarizeAddress {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { search => 1, elements => 1, types => 1, addresses => 1 } );

    foreach my $element ( @{ $parameters->{elements} } ) {
        foreach my $type ( @{ $parameters->{types} } ) {
            if ( $element eq "." ) {
                my $temp_addresses = find( $parameters->{search}, ".//*[\@type=\"" . $type . "\"]", 0 );
                foreach my $a ( $temp_addresses->get_nodelist ) {
                    my $address = extract( $a, 0 );
                    $parameters->{addresses}->{$address} = 1 if $address;
                }
            }
            else {
                my $temp_addresses = find( $parameters->{search}, ".//*[local-name()='" . $element . "' and \@type=\"" . $type . "\"]", 0 );
                foreach my $a ( $temp_addresses->get_nodelist ) {
                    my $address = extract( $a, 0 );
                    $parameters->{addresses}->{$address} = 1 if $address;
                }
            }
        }
    }
    return $parameters->{addresses};
}

=head2 summarizeHosts($self, { search, elements, types, hostarray, hosts } );

Given a topology element, a list of possible sub-elements, and types, extract
host names.  Seperate these into classeses (e.g. edu/org/net, domain name, sub
domain name) and return them in a hash reference.

=cut

sub summarizeHosts {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { search => 1, elements => 1, types => 1, hostarray => 1, hosts => 1 } );

    foreach my $element ( @{ $parameters->{elements} } ) {
        foreach my $type ( @{ $parameters->{types} } ) {
            my $temp_hosts = find( $parameters->{search}, ".//*[local-name()='" . $element . "' and \@type=\"" . $type . "\"]", 0 );
            foreach my $h ( $temp_hosts->get_nodelist ) {        
                push @{ $parameters->{hostarray} }, extract( $h, 0 );
            }
        }
    }

    foreach my $host ( @{ $parameters->{hostarray} } ) {
        my @hostArray = split( /\./, $host );
        my $host_len = $#hostArray;
        for my $len ( 1 .. $host_len ) {
            my $cat = q{};
            for my $len2 ( $len .. $host_len ) {
                $cat .= "." . $hostArray[$len2];
            }
            $cat =~ s/^\.//;
            $parameters->{hosts}->{$cat} = 1 if $cat;
        }
    }

    return $parameters->{hosts};
}

=head2 ipSummarization( $self, { addresses } )

Summarize IP addresses into CDIR ranges.

=cut

sub ipSummarization {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { addresses => 1 } );

    if ( keys ( %{ $parameters->{addresses} } ) == 1) {
        my @temp = ();
        foreach my $host ( keys %{ $parameters->{addresses} } ) {
            push @temp, $host."/32";
        }
        return \@temp;
    }

    $self->{IPTRIE}    = ();
    $self->{CLAIMTREE} = ();

    # IP Trie Data Structure (similar to Net::Patricia).  First we add in all
    # of the 'base' addresses
    my $tr = Net::IPTrie->new( version => 4 );
    foreach my $host ( keys %{ $parameters->{addresses} } ) {
        $tr->add( address => $host, prefix => "32" );
    }

    my %tally = ();
    foreach my $host ( keys %{ $parameters->{addresses} } ) {
        my @list = Net::CIDR::addr2cidr($host);
        foreach my $range (@list) {

            # we want to ingore the wildcard addresses...
            next if $range =~ m/^0\./;

            $tally{$range}++ if defined $tally{$range};
            $tally{$range} = 1 if not defined $tally{$range};
        }
    }

    # Add in the CIDR stuff to the tree
    foreach my $t ( sort keys %tally ) {
        my @parts = split( /\//, $t );
        $tr->add( address => $parts[0], prefix => $parts[1] );
    }

    my $list  = ();
    my $code  = sub { push @$list, shift @_; };
    my $count = $tr->traverse( code => $code );

    # hacky root pointer (gives us unification if the whild card [0.*]
    # was really needed as the root)
    my @temp = ();
    $self->{IPTRIE}{"Root"}{"C"} = \@temp;
    $self->{IPTRIE}{"Root"}{"U"} = "NULL";

    # we need to go backwards when looking at the IPTrie print out, this is
    # is really to be sure children aren't all claimed by the root (the internal
    # structure of the IPTrie is a little strange and actually allows this to
    # happen) so this ensures we hit the root last.
    foreach my $node ( reverse @{$list} ) {
        my $me = "";
        $me = $node->[3] . "/" . $node->[5] if defined $node->[3] and defined $node->[5];
        next unless $me;

        # each one of our node-keys has some location information, namely a
        # child list, and we will know who the parent is.
        my @temp = ();
        $self->{IPTRIE}{$me}{"C"} = \@temp;
        $self->{IPTRIE}{$me}{"U"} = "";

        # recursively search the tree, stop after you find a left and right
        # child though (N.B. this creates problems unfortunately, so we need
        # to manually manipulate later on...)
        my %status = (
            "L" => 0,
            "R" => 0
        );
        $self->extractIPNode( { parent => $me, node => $node, status => \%status, side => "" } );
    }

    # link all the parent information for each node and child
    foreach my $item ( keys %{ $self->{IPTRIE} } ) {
        foreach my $c ( @{ $self->{IPTRIE}{$item}{"C"} } ) {
            $self->{IPTRIE}{$c}{"U"} = $item if $c and $item;
        }
    }

    # First step: Start at the leaves and walk toward the root.
    # - Every time we see a node with a sinle child, collapse it into the parent
    #   (we are pruning the tree)
    foreach my $host ( keys %{ $parameters->{addresses} } ) {
        my $current = $host . "/32";
        while ($current) {
            my $delete = "";
            if ( $#{ $self->{IPTRIE}{ $self->{IPTRIE}{$current}{"U"} }{"C"} } == 0 and not( $current =~ m/\/32$/ ) and $#{ $self->{IPTRIE}{$current}{"C"} } == 0 ) {
                $delete = $current;
                foreach my $child ( @{ $self->{IPTRIE}{$current}{"C"} } ) {
                    $self->{IPTRIE}{$child}{"U"} = $self->{IPTRIE}{$current}{"U"};
                }
                $self->{IPTRIE}{ $self->{IPTRIE}{$current}{"U"} }{"C"} = $self->{IPTRIE}{$current}{"C"};
                delete $self->{IPTRIE}{$delete}{"C"};
            }
            $current = $self->{IPTRIE}{$current}{"U"};
            delete $self->{IPTRIE}{$delete} if $delete;
        }
    }

    # Second step: Start at the leaves and walk toward the root.
    # - Every time we see a single child node, collapse it into the child (this
    #   is the opposite of what we just did, but this handles branching much
    #   better, this is also a form of pruning).
    foreach my $host ( keys %{ $parameters->{addresses} } ) {
        my $current = $host . "/32";
        while ($current) {
            my $delete = "";
            if ( $#{ $self->{IPTRIE}{$current}{"C"} } == 0 ) {
                $delete = $current;
                foreach my $child ( @{ $self->{IPTRIE}{$delete}{"C"} } ) {
                    $self->{IPTRIE}{$child}{"U"} = $self->{IPTRIE}{$delete}{"U"};
                    push @{ $self->{IPTRIE}{ $self->{IPTRIE}{$delete}{"U"} }{"C"} }, $child;
                }

                my $counter = 0;
                foreach my $child ( @{ $self->{IPTRIE}{ $self->{IPTRIE}{$delete}{"U"} }{"C"} } ) {
                    if ( $child eq $current ) {
                        my $remove = splice( @{ $self->{IPTRIE}{ $self->{IPTRIE}{$delete}{"U"} }{"C"} }, $counter, 1 );
                    }
                    $counter++;
                }
            }
            $current = $self->{IPTRIE}{$current}{"U"};
            delete $self->{IPTRIE}{$delete} if $delete;
        }
    }

    # finally link the tree(s) to the root pointer.  Note that we may have
    # several subtrees (e.g. not 2 to make it binary) in the final forest.  This
    # is OK because we didn't allow the 0.* wildcard initially.  This will not
    # effect the search for dominators.
    foreach my $node ( keys %{ $self->{IPTRIE} } ) {
        unless ( $self->{IPTRIE}{$node}{"U"} ) {
            $self->{IPTRIE}{$node}{"U"} = "Root";
            push @{ $self->{IPTRIE}{"Root"}{"C"} }, $node;
        }
    }

    # find the min dominators...

    my @expand = ();
    foreach my $node ( sort keys %{ $self->{IPTRIE} } ) {
        if ( $node and $self->{IPTRIE}{$node}{"U"} eq "Root" ) {

            # add the root the 'expand' list so we can
            # examine it (and it's children, etc.) then
            # exit
            push @expand, $node;
        }
    }

    my $counter = 0;
    my @minDoms = ();

    # now we are going to walk the tree.  If a non-leaf
    # node has two non-leaf children is is useless to us,
    # so we skip it.  If a non-leaf node has at least one
    # leaf child, this is a part of our 'boundary' so
    # we list it as a minDominator.

    while ( $expand[$counter] ) {
        my $minDomFlag = 0;
        my $expandFlag = 0;

        foreach my $child ( sort @{ $self->{IPTRIE}{ $expand[$counter] }{"C"} } ) {
            my @array = split( /\//, $child );

            # /32's are leaf nodes, if one of our children is a leaf
            # we are a on the min dominator boundary
            if ( $array[1] eq "32" ) {

                # Make sure we only add the node once...
                if ( ( $#minDoms == -1 ) or ( $minDoms[$#minDoms] ne $expand[$counter] ) ) {
                    push @minDoms, $expand[$counter];
                }
                $minDomFlag++;
            }
            else {

                # If we have a non leaf node as a child, we will probably
                # need to expland that child later...

                push @expand, $child;
                $expandFlag++;
            }
        }

        # corner case: if we have a non leaf child and a leaf
        # child we need to remove the non leaf child from the
        # expand list

        pop @expand if $expandFlag and $minDomFlag;
        $counter++;
    }

    return \@minDoms;
}

=head2 extractIPNode($self, $parent, $node, $status, $side)

This aux function recursively walks the nodes of the IPTrie structure
and creates a more usefriendly tree that we will use for manipulation
and final display.

=cut

sub extractIPNode {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { parent => 1, node => 1, status => 1, side => 0 } );

    my $me = "";
    $me = $parameters->{node}->[3] . "/" . $parameters->{node}->[5] if defined $parameters->{node}->[3] and defined $parameters->{node}->[5];
    if ( $me and $parameters->{side} and ( not $self->{CLAIMTREE}{$me} ) ) {
        push @{ $self->{IPTRIE}{ $parameters->{parent} }{"C"} }, $me;
        $self->{CLAIMTREE}{$me} = 1;
    }
    $parameters->{status} = $self->extractIPNode( { parent => $parameters->{parent}, node => $parameters->{node}->[1], status => $parameters->{status}, side => "L" } ) if $parameters->{node}->[1] and ( not $parameters->{status}->{"L"} );
    $parameters->{status} = $self->extractIPNode( { parent => $parameters->{parent}, node => $parameters->{node}->[2], status => $parameters->{status}, side => "R" } ) if $parameters->{node}->[2] and ( not $parameters->{status}->{"R"} );
    return $parameters->{status};
}

=head2 cleanLS($self)

On some schedule the daemon will kick off a process to clean the internal
databases.  This process will connect to the database, and check the timestamps
of all registered data.  Anything that is 'expired', i.e. hasn't been updated
in the TTL for the data will be removed.

=cut

sub cleanLS {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { error => 0 } );

    return 0 if $self->{CONF}->{"gls"}->{"xmldb_reaper_interval"} == 0;

    my $error     = q{};
    my $errorFlag = 0;
    my ( $sec, $frac ) = Time::HiRes::gettimeofday;

    my $metadatadb = $self->prepareDatabase( { container => $self->{CONF}->{"gls"}->{"metadata_db_file"} } );
    unless ($metadatadb) {
        $self->{LOGGER}->error( "There was an error opening \"" . $self->{CONF}->{"gls"}->{"metadata_db_name"} . "/" . $self->{CONF}->{"gls"}->{"metadata_db_file"} . "\": " . $error );
        return -1;
    }
    my $status = $self->cleanLSAux( { database => $metadatadb, time => $sec } );
    unless ( $status == 0 ) {
        $self->{LOGGER}->error( "Database \"" . $self->{CONF}->{"gls"}->{"metadata_db_name"} . "/" . $self->{CONF}->{"gls"}->{"metadata_db_file"} . "\" could not be cleaned." );
        return -1;
    }

    my $summarydb = $self->prepareDatabase( { container => $self->{CONF}->{"gls"}->{"metadata_summary_db_file"} } );
    unless ($summarydb) {
        $self->{LOGGER}->error( "There was an error opening \"" . $self->{CONF}->{"gls"}->{"metadata_db_name"} . "/" . $self->{CONF}->{"gls"}->{"metadata_summary_db_file"} . "\": " . $error );
        return -1;
    }
    $status = $self->cleanLSAux( { database => $summarydb, time => $sec } );
    unless ( $status == 0 ) {
        $self->{LOGGER}->error( "Database \"" . $self->{CONF}->{"gls"}->{"metadata_db_name"} . "/" . $self->{CONF}->{"gls"}->{"metadata_summary_db_file"} . "\" could not be cleaned." );
        return -1;
    }

    return 0;
}

=head2 cleanLSAux($self, { database, time })

Auxilary function to clean a specific container in the database.

=cut

sub cleanLSAux {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { database => 1, time => 1 } );

    my $error     = q{};
    my $errorFlag = 0;

    my $dbTr = $parameters->{database}->getTransaction( { error => \$error } );
    unless ($dbTr) {
        $parameters->{database}->abortTransaction( { txn => $dbTr, error => \$error } ) if $dbTr;
        undef $dbTr;
        $self->{LOGGER}->error( "Cound not start database transaction, database responded with \"" . $error . "\"." );
    }

    my @resultsString = $parameters->{database}->query( { query => "/nmwg:store[\@type=\"LSStore-control\"]/nmwg:metadata", txn => $dbTr, error => \$error } );
    $errorFlag++ if $error;
    if ( $#resultsString != -1 ) {
        my $len = $#resultsString;
        for my $x ( 0 .. $len ) {
            my $parser = XML::LibXML->new();
            my $doc    = $parser->parse_string( $resultsString[$x] );

            my $time = extract( find( $doc->getDocumentElement, "./nmwg:parameters/nmwg:parameter[\@name=\"timestamp\"]/nmtm:time[text()]", 1 ), 1 );
            if ( $time =~ m/^\d+$/mx ) {
                my $key = $doc->getDocumentElement->getAttribute("id");
                $key =~ s/-control$//mx;
                if ( $time and $key and $parameters->{time} >= $time ) {
                    $self->{LOGGER}->debug( "Removing all info for \"" . $key . "\"." );
                    my @resultsString2 = $parameters->{database}->queryForName( { query => "/nmwg:store[\@type=\"LSStore\"]/nmwg:data[\@metadataIdRef=\"" . $key . "\"]", txn => $dbTr, error => \$error } );
                    $errorFlag++ if $error;
                    my $len2 = $#resultsString2;
                    for my $y ( 0 .. $len2 ) {
                        $parameters->{database}->remove( { name => $resultsString2[$y], txn => $dbTr, error => \$error } );
                        $errorFlag++ if $error;
                    }
                    my @resultsString3 = $parameters->{database}->queryForName( { query => "/nmwg:store[\@type=\"LSStore-summary\"]/nmwg:data[\@metadataIdRef=\"" . $key . "\"]", txn => $dbTr, error => \$error } );
                    $errorFlag++ if $error;
                    my $len3 = $#resultsString3;
                    for my $y ( 0 .. $len3 ) {
                        $parameters->{database}->remove( { name => $resultsString3[$y], txn => $dbTr, error => \$error } );
                        $errorFlag++ if $error;
                    }
                    $parameters->{database}->remove( { name => $key . "-control", txn => $dbTr, error => \$error } );
                    $errorFlag++ if $error;
                    $parameters->{database}->remove( { name => $key, txn => $dbTr, error => \$error } );
                    $errorFlag++ if $error;
                    $self->{LOGGER}->debug( "Removed [" . ( $#resultsString3 + $#resultsString2 + 1 ) . "] data elements and service info for key \"" . $key . "\"." );
                }
            }
        }
    }
    else {
        $self->{LOGGER}->error("Nothing Registered, cannot clean at this time.");
    }

    if ($errorFlag) {
        $parameters->{database}->abortTransaction( { txn => $dbTr, error => \$error } ) if $dbTr;
        undef $dbTr;
        $self->{LOGGER}->error("Database errors prevented the transaction from completing.");
        return -1;
    }
    else {
        my $status = $parameters->{database}->commitTransaction( { txn => $dbTr, error => \$error } );
        if ( $status == 0 ) {
            undef $dbTr;
        }
        else {
            $parameters->{database}->abortTransaction( { txn => $dbTr, error => \$error } ) if $dbTr;
            undef $dbTr;
            $self->{LOGGER}->error( "Database Error: \"" . $error . "\"." );
            return -1;
        }
    }
    return 0;
}

=head2 handleMessageParameters($self, $msgParams)

Looks in the mesage for any parameters and sets appropriate variables if
applicable.

=cut

sub handleMessageParameters {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { msgParams => 1 } );

    foreach my $p ( $parameters->{msgParams}->getChildrenByTagNameNS( $ls_namespaces{"nmwg"}, "parameter" ) ) {
        if ( $p->getAttribute("name") eq "lsTTL" ) {
            $self->{LOGGER}->debug("Found TTL parameter.");

            my $units = $p->getAttribute("units");
            $units = "seconds" unless $units;
            my $time = extract( $p, 0 );
            $time *= 60   if $units eq "minutes";
            $time *= 3600 if $units eq "hours";

            if ( $time < ( int $self->{"CONF"}->{"gls"}->{"ls_ttl"} / 2 ) or $time > $self->{"CONF"}->{"gls"}->{"ls_ttl"} ) {
                $p->setAttribute( "units", "seconds" );
                if ( $p->getAttribute("value") ) {
                    $p->setAttribute( "value", $self->{"CONF"}->{"gls"}->{"ls_ttl"} );
                }
                elsif ( $p->childNodes ) {
                    if ( $p->firstChild->nodeType == 3 ) {
                        my $oldChild = $p->removeChild( $p->firstChild );
                        $p->appendTextNode( $self->{"CONF"}->{"gls"}->{"ls_ttl"} );
                    }
                }
            }
        }
    }
    return $parameters->{msgParams};
}

=head2 isValidKey($self, $database, $key)

This function will check to see if a key found in a request message is
a valid key in the datbase.  

=cut

sub isValidKey {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { database => 1, key => 1, txn => 0 } );

    my $error = q{};
    my $result;
    if ( exists $parameters->{txn} and $parameters->{txn} ) {
        $result = $parameters->{database}->queryByName( { name => $parameters->{key}, txn => $parameters->{txn}, error => \$error } );
    }
    else {
        $result = $parameters->{database}->queryByName( { name => $parameters->{key}, txn => q{}, error => \$error } );
    }
    
    if ($result) {
        $self->{LOGGER}->debug( "Key \"" . $parameters->{key} . "\" found in database." );
        return 1;
    }
    $self->{LOGGER}->debug( "Key \"" . $parameters->{key} . "\" not found in database." );
    return 0;
}

=head2 handleMessage($self, $doc, $messageType, $message, $request)

Given a message from the Transport module, this function will route
the message to the appropriate location based on message type.

=cut

sub handleMessage {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { output => { type => ARRAYREF, isa => "perfSONAR_PS::XML::Document" }, messageId => { type => SCALAR | UNDEF }, messageType => { type => SCALAR }, message => { type => SCALARREF }, rawRequest => { type => ARRAYREF } } );

    my $error   = q{};
    my $counter = 0;
    $self->{STATE}->{"messageKeys"} = ();
    my $messageIdReturn = "message." . genuid();
    ( my $messageTypeReturn = $parameters->{messageType} ) =~ s/Request/Response/xm;

    my $msgParams = find( $parameters->{rawRequest}->getRequestDOM()->getDocumentElement, "./nmwg:parameters", 1 );
    if ($msgParams) {
        $msgParams = $self->handleMessageParameters( { msgParams => $msgParams } );
        $parameters->{output}->addExistingXMLElement($msgParams);
    }

    startMessage( $parameters->{output}, $messageIdReturn, $parameters->{messageId}, $messageTypeReturn, q{}, undef );

    my $metadatadb = $self->prepareDatabase( { doc => $parameters->{output}, container => $self->{CONF}->{"gls"}->{"metadata_db_file"} } );
    unless ($metadatadb) {
        throw perfSONAR_PS::Error_compat( "error.ls.xmldb", "Metadata Database could not be opened." );
        return;
    }
    my $summarydb = $self->prepareDatabase( { doc => $parameters->{output}, container => $self->{CONF}->{"gls"}->{"metadata_summary_db_file"} } );
    unless ($summarydb) {
        throw perfSONAR_PS::Error_compat( "error.ls.xmldb", "Summary Database could not be opened." );
        return;
    }

    foreach my $d ( $parameters->{rawRequest}->getRequestDOM()->getDocumentElement->getChildrenByTagNameNS( $ls_namespaces{"nmwg"}, "data" ) ) {
        $counter++;

        my $errorEventType = q{};
        my $errorMessage   = q{};
        my $m              = find( $parameters->{rawRequest}->getRequestDOM()->getDocumentElement, "./nmwg:metadata[\@id=\"" . $d->getAttribute("metadataIdRef") . "\"]", 1 );
        try {
            unless ($m) {
                throw perfSONAR_PS::Error_compat( "error.ls.data_trigger", "Matching metadata not found for data trigger \"" . $d->getAttribute("id") . "\"" );
            }

            if ( $parameters->{messageType} eq "LSRegisterRequest" ) {
                $self->{LOGGER}->debug("Parsing LSRegister request.");
                $self->lsRegisterRequest( { doc => $parameters->{output}, request => $parameters->{rawRequest}, m => $m, d => $d, database => $metadatadb } );
            }
            elsif ( $parameters->{messageType} eq "LSDeregisterRequest" ) {
                $self->{LOGGER}->debug("Parsing LSDeregister request.");
                $self->lsDeregisterRequest( { doc => $parameters->{output}, request => $parameters->{rawRequest}, m => $m, d => $d, metadatadb => $metadatadb, summarydb => $summarydb } );
            }
            elsif ( $parameters->{messageType} eq "LSKeepaliveRequest" ) {
                $self->{LOGGER}->debug("Parsing LSKeepalive request.");
                $self->lsKeepaliveRequest( { doc => $parameters->{output}, request => $parameters->{rawRequest}, m => $m, metadatadb => $metadatadb, summarydb => $summarydb } );
            }
            elsif ($parameters->{messageType} eq "LSQueryRequest"
                or $parameters->{messageType} eq "LSLookupRequest" )
            {
                $self->lsQueryRequest( { doc => $parameters->{output}, request => $parameters->{rawRequest}, m => $m, metadatadb => $metadatadb, summarydb => $summarydb } );
            }
            elsif ( $parameters->{messageType} eq "LSKeyRequest" ) {
                $self->lsKeyRequest( { doc => $parameters->{output}, request => $parameters->{rawRequest}, m => $m, metadatadb => $metadatadb, summarydb => $summarydb } );
            }
            else {
                throw perfSONAR_PS::Error_compat( "error.ls.messages", "Unrecognized message type" );
            }
        }
        catch perfSONAR_PS::Error_compat with {
            my $ex = shift;
            $errorEventType = $ex->eventType;
            $errorMessage   = $ex->errorMessage;
        }
        catch perfSONAR_PS::Error with {
            my $ex = shift;
            $errorEventType = $ex->eventType;
            $errorMessage   = $ex->errorMessage;
        }
        catch Error::Simple with {
            my $ex = shift;
            $errorEventType = "error.ls.system";
            $errorMessage   = $ex->{"-text"};
        }
        otherwise {
            my $ex = shift;
            $errorEventType = "error.ls.internal_error";
            $errorMessage   = "An internal error occurred.";
        };
        if ($errorEventType) {
            my $mdIdRef = q{};
            if ( $m and $m->getAttribute("id") ) {
                $mdIdRef = $m->getAttribute("id");
            }
            $self->{LOGGER}->error($errorMessage);
            my $mdId = "metadata." . genuid();
            getResultCodeMetadata( $parameters->{output}, $mdId, $mdIdRef, $errorEventType );
            getResultCodeData( $parameters->{output}, "data." . genuid(), $mdId, $errorMessage, 1 );
        }
    }

    $metadatadb->closeDB( { error => \$error } );
    $summarydb->closeDB(  { error => \$error } );
    unless ($counter) {
        throw perfSONAR_PS::Error_compat( "error.ls.register.data_trigger_missing", "No data triggers found in request." );
    }

    endMessage( $parameters->{output} );
    return;
}

=head2 lsRegisterRequest($self, $doc, $request)

The LSRegisterRequest procedure allows services (both previously registered
and new) the ability to register data with the LS.  In the case of previously
registered services it is possible to augment a data set with new information
by supplying your previously issued key, or change an existing registration
(i.e. if the service info has changed) and subsequently un and re-register
all data.  Responses should indicate success and failure for the datasets that
were registered.  This function is split into sub functions described below.

The following is a brief outline of the procedures:

    Does MD have a key
    Y: Update of registration, Is there a service element?
      Y: Old style 'clobber' update, pass to lsRegisterRequestUpdateNew
      N: New style 'append' update, pass to lsRegisterRequestUpdate
    N: This is a 'new' registration, pass to lsRegisterRequestNew
    
=cut

sub lsRegisterRequest {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { doc => 1, request => 1, m => 1, d => 1, database => 1 } );

    my $error = q{};
    my $auth;
    my ( $sec, $frac ) = Time::HiRes::gettimeofday;

    my $eventType = extract( find( $parameters->{m}, "./nmwg:eventType", 1 ), 0 );   
    if ( $self->{"CONF"}->{"gls"}->{"root"} ) {
        if ( $eventType eq "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/registration/summary/2.0" ) {
            # comes from an hLS to a gLS, this is authoratative
            $auth = 1;
        }
        elsif( $eventType eq "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/registration/synchronization/2.0" ) {
            # comes from an gLS to a gLS, this is NOT authoratative
            $auth = 0;
        }
        else {
            # Anything else is rejected
            throw perfSONAR_PS::Error_compat( "error.gls.register", "Root gLS servers can only accept registration and synchronization of hLS summaries." );
        }

        my $totalCount = 0;
        my $summaryCount = 0;
        foreach my $d_content ( $parameters->{d}->childNodes ) {
            if ( $d_content->getType != 3 and $d_content->getType != 8 ) {
                if ( find( $d_content, ".//summary:subject", 1 ) ) {
                    $summaryCount++;
                }
                $totalCount++;
            }
        }
        
        unless ( $summaryCount == $totalCount ) {
            throw perfSONAR_PS::Error_compat( "error.gls.register", "Root gLS servers can only accept registration and synchronization of hLS summaries." );
        }
    }
    else {
        # hLS should have no eventType, or the service registration eventType.
        # Everything else is rejected, and these previous two interactions are
        # authoratative.
        unless ( $eventType eq "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/registration/service/2.0" ) {
            if( $eventType ) {
                throw perfSONAR_PS::Error_compat( "error.hls.register", "hLS servers can only accept service registration." );
            }
        }

        foreach my $d_content ( $parameters->{d}->childNodes ) {
            if ( $d_content->getType != 3 and $d_content->getType != 8 ) {
                if ( find( $d_content, ".//summary:subject", 1 ) ) {  
                    throw perfSONAR_PS::Error_compat( "error.hls.register", "hLS servers can not accept summary registration." );
                }
            }
        }

        $auth = 1;
    }

    my $dbTr = $parameters->{database}->getTransaction( { error => \$error } );
    unless ($dbTr) {
        $parameters->{database}->abortTransaction( { txn => $dbTr, error => \$error } ) if $dbTr;
        undef $dbTr;
        throw perfSONAR_PS::Error_compat( "error.ls.xmldb", "Cound not start summary database transaction, database responded with \"" . $error . "\"." );
    }

    my $mdKey = extract( find( $parameters->{m}, "./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"lsKey\"]", 1 ), 0 );
    if ($mdKey) {
        unless ( exists $self->{STATE}->{"messageKeys"}->{$mdKey} ) {
            $self->{STATE}->{"messageKeys"}->{$mdKey} = $self->isValidKey( { txn => $dbTr, database => $parameters->{database}, key => $mdKey } );
        }

        unless ( $self->{STATE}->{"messageKeys"}->{$mdKey} ) {
            throw perfSONAR_PS::Error_compat( "error.ls.register.key_not_found", "Sent key \"" . $mdKey . "\" was not registered." );
        }

        my $service = find( $parameters->{m}, "./*[local-name()='subject']/*[local-name()='service']", 1 );
        if ($service) {
            # 'clobber' registration case
            $self->lsRegisterRequestUpdateNew( { doc => $parameters->{doc}, database => $parameters->{database}, dbTr => $dbTr, metadataId => $parameters->{m}->getAttribute("id"), d => $parameters->{d}, mdKey => $mdKey, service => $service, sec => $sec, eventType => $eventType, auth => $auth } );
        }
        else {
             # 'update' registration case
            $self->lsRegisterRequestUpdate( { doc => $parameters->{doc}, database => $parameters->{database}, dbTr => $dbTr, metadataId => $parameters->{m}->getAttribute("id"), d => $parameters->{d}, mdKey => $mdKey, sec => $sec, eventType => $eventType, auth => $auth } );
        }
    }
    else {
        # 'new' registration case
        $self->lsRegisterRequestNew( { doc => $parameters->{doc}, database => $parameters->{database}, dbTr => $dbTr, m => $parameters->{m}, d => $parameters->{d}, sec => $sec, eventType => $eventType, auth => $auth } );
    }
    return;
}

=head2 lsRegisterRequestUpdateNew($self, $doc, $request, $database, $m, $d, $mdKey, $service, $sec, $eventType, $auth)

As a subprocedure of the main LSRegisterRequest procedure, this is the special
case of the 'clobber' update.  Namely there is data for a given key in the
database already (will be verified) and the user wishes to update the service
info and delete all existing data, and replace it with new sent data.  This
essentually amounts to a deregistration, and reregistration.  

The following is a brief outline of the procedures:

    Does service info have an accessPoint
    Y: Remove old info, add new info
    N: Error Out

=cut

sub lsRegisterRequestUpdateNew {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { doc => 1, database => 1, dbTr => 1, metadataId => 1, d => 1, mdKey => 1, service => 1, sec => 1, eventType => 1, auth => 1 } );

    my $error     = q{};
    my $errorFlag = 0;
    my $mdId      = "metadata." . genuid();
    my $dId       = "data." . genuid();

    my $accessPoint = extract( find( $parameters->{service}, "./*[local-name()='accessPoint']", 1 ), 0 );
    my $accessType;
    my $accessName;
    unless ($accessPoint) {
        $accessPoint = extract( find( $parameters->{service}, "./*[local-name()='address']", 1 ), 0 );
        $accessType = extract( find( $parameters->{service}, "./*[local-name()='type']", 1 ), 0 );
        $accessName = extract( find( $parameters->{service}, "./*[local-name()='name']", 1 ), 0 );        
        unless ($accessPoint) {
            throw perfSONAR_PS::Error_compat( "error.ls.register.missing_value", "Cannont register data, accessPoint or address was not supplied." );
            return;
        }
    }

    my $mdKeyStorage = md5_hex($accessPoint . $accessType . $accessName );

    my $update = 1;
    if( $parameters->{eventType} eq "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/registration/synchronization/2.0" ) {
        my @resultsString = $parameters->{database}->query( { query => "/nmwg:store[\@type=\"LSStore-control\"]/nmwg:metadata[\@metadataIdRef=\"".$parameters->{mdKey}."\"]/nmwg:parameters/nmwg:parameter[\@name=\"authoritative\"]/text()", txn => q{}, error => \$error } );
        $errorFlag++ if $error;
        if ( lc($resultsString[0]) eq "yes" ) {
            # if this is a synch message, AND we already have some authoratative
            # registration of the data (e.g. it was directly registered) we
            # don't want to touch it.
            $update = 0;
        }    
    }

    if ( $update ) {
        # remove all the old stuff (its a 'clobber' after all)
    
        my @resultsString2 = $parameters->{database}->queryForName( { query => "/nmwg:store[\@type=\"LSStore\"]/nmwg:data[\@metadataIdRef=\"" . $parameters->{mdKey} . "\"]", txn => $parameters->{dbTr}, error => \$error } );
        my $len2 = $#resultsString2;
        $self->{LOGGER}->debug( "Removing all info for \"" . $parameters->{mdKey} . "\"." );
        for my $y ( 0 .. $len2 ) {
            $parameters->{database}->remove( { name => $resultsString2[$y], txn => $parameters->{dbTr}, error => \$error } );
        }
        $parameters->{database}->remove( { name => $parameters->{mdKey} . "-control", txn => $parameters->{dbTr}, error => \$error } );
        $parameters->{database}->remove( { name => $parameters->{mdKey}, txn => $parameters->{dbTr}, error => \$error } );
        $self->{STATE}->{"messageKeys"}->{ $parameters->{mdKey} } = 0;
    }

    unless ( $self->{STATE}->{"messageKeys"}->{$mdKeyStorage} == 2 ) {
        if ( $self->{STATE}->{"messageKeys"}->{$mdKeyStorage} ) {
            if ( $update ) {
                # update the key (if we are allowed to)
            
                $self->{LOGGER}->debug("Key already exists, but updating control time information anyway.");
                $parameters->{database}->updateByName( { content => createControlKey( { key => $mdKeyStorage, time => ( $parameters->{sec} + $self->{CONF}->{"gls"}->{"ls_ttl"} ), auth => $parameters->{auth} } ), name => $mdKeyStorage . "-control", txn => $parameters->{dbTr}, error => \$error } );
                $errorFlag++ if $error;
            }
        }
        else {
            # its new to us, so add it
        
            $self->{LOGGER}->debug("New registration info, inserting service metadata and time information.");
            my $mdCopy = "<nmwg:metadata xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\" id=\"" . $mdKeyStorage . "\">\n<perfsonar:subject xmlns:perfsonar=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/\">" . $parameters->{service}->toString . "</perfsonar:subject>\n</nmwg:metadata>\n";
            $parameters->{database}->insertIntoContainer( { content => $parameters->{database}->wrapStore( { content => $mdCopy, type => "LSStore" } ), name => $mdKeyStorage, txn => $parameters->{dbTr}, error => \$error } );
            $parameters->{database}->insertIntoContainer( { content => createControlKey( { key => $mdKeyStorage, time => ( $parameters->{sec} + $self->{CONF}->{"gls"}->{"ls_ttl"} ), auth => $parameters->{auth} } ), name => $mdKeyStorage . "-control", txn => $parameters->{dbTr}, error => \$error } );
        }
        $self->{STATE}->{"messageKeys"}->{$mdKeyStorage} = 2;
    }

    my $dCount = 0;
    if ( $update ) {
        # add the data (if we are allowed to)
        foreach my $d_content ( $parameters->{d}->childNodes ) {
            if ( $d_content->getType != 3 and $d_content->getType != 8 ) {
                my $cleanNode = $d_content->cloneNode(1);
                $cleanNode->removeAttribute("id");
                my $cleanHash = md5_hex( $cleanNode->toString );

                my $success = $parameters->{database}->queryByName( { name => $mdKeyStorage . "/" . $cleanHash, txn => $parameters->{dbTr}, error => \$error } );
                $errorFlag++ if $error;
                unless ($success) {
                    my $insRes = $parameters->{database}->insertIntoContainer( { content => createLSData( { type => "LSStore", dataId => $mdKeyStorage . "/" . $cleanHash, metadataId => $mdKeyStorage, data => $d_content->toString } ), name => $mdKeyStorage . "/" . $cleanHash, txn => $parameters->{dbTr}, error => \$error } );
                    $errorFlag++ if $error;
                    $dCount++    if $insRes == 0;
                }
            }
        }
    }

    if ($errorFlag) {
        $parameters->{database}->abortTransaction( { txn => $parameters->{dbTr}, error => \$error } ) if $parameters->{dbTr};
        undef $parameters->{dbTr};
        throw perfSONAR_PS::Error_compat( "error.ls.xmldb", "Database errors prevented the transaction from completing." );
    }
    else {
        my $status = $parameters->{database}->commitTransaction( { txn => $parameters->{dbTr}, error => \$error } );
        if ( $status == 0 ) {
            createMetadata( $parameters->{doc}, $mdId, $parameters->{metadataId}, createLSKey( { key => $mdKeyStorage, eventType => "success.ls.register" } ), undef );
            createData( $parameters->{doc}, $dId, $mdId, "<nmwg:datum value=\"[" . $dCount . "] Data elements have been registered with key [" . $mdKeyStorage . "]\" />\n", undef );
            undef $parameters->{dbTr};
        }
        else {
            $parameters->{database}->abortTransaction( { txn => $parameters->{dbTr}, error => \$error } ) if $parameters->{dbTr};
            undef $parameters->{dbTr};
            throw perfSONAR_PS::Error_compat( "error.ls.xmldb", "Database Error: \"" . $error . "\"." );
        }
    }
    return;
}

=head2 lsRegisterRequestUpdate($self, $doc, $request, $database, $m, $d, $mdKey, $sec, $eventType)

As a subprocedure of the main LSRegisterRequest procedure, this is the special
case of the 'append' update.  Namely there is data for a given key in the
database already (will be verified) and the user wishes to add more data to this
set.  The key will already have been verified in the previous step, so the
control info is simply updated, and the new data is appended.

=cut

sub lsRegisterRequestUpdate {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { doc => 1, database => 1, dbTr => 1, metadataId => 1, d => 1, mdKey => 1, sec => 1, eventType => 1, auth => 1 } );

    my $error     = q{};
    my $errorFlag = 0;
    my $mdId      = "metadata." . genuid();
    my $dId       = "data." . genuid();

    my $update = 1;
    if( $parameters->{eventType} eq "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/registration/synchronization/2.0" ) {
        my @resultsString = $parameters->{database}->query( { query => "/nmwg:store[\@type=\"LSStore-control\"]/nmwg:metadata[\@metadataIdRef=\"".$parameters->{mdKey}."\"]/nmwg:parameters/nmwg:parameter[\@name=\"authoritative\"]/text()", txn => $parameters->{dbTr}, error => \$error } );
        $errorFlag++ if $error;
        if ( lc($resultsString[0]) eq "yes" ) {
            # if this is a synch message, AND we already have some authoratative
            # registration of the data (e.g. it was directly registered) we
            # don't want to touch it.
            $update = 0;
        }    
    }

    my $dCount = 0;
    if ( $update ) {
        # only update if we are allowed to do so

        if ( $self->{STATE}->{"messageKeys"}->{ $parameters->{mdKey} } == 1 ) {
            $self->{LOGGER}->debug("Key already exists, but updating control time information anyway.");
            $parameters->{database}->updateByName( { content => createControlKey( { key => $parameters->{mdKey}, time => ( $parameters->{sec} + $self->{CONF}->{"gls"}->{"ls_ttl"} ), auth => $parameters->{auth} } ), name => $parameters->{mdKey} . "-control", txn => $parameters->{dbTr}, error => \$error } );
            $errorFlag++ if $error;
            $self->{STATE}->{"messageKeys"}->{ $parameters->{mdKey} }++;
        }
        $self->{LOGGER}->debug("Key already exists and was already updated in this message, skipping.");

        if( $parameters->{eventType} eq "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/registration/synchronization/2.0" ) {
                # special case: we always want to clobber the summary data
                # (e.g. it may be different from time to time, therefore
                # it is safest to just nuke it)
                
                $self->{LOGGER}->debug( "Removing data for \"" . $parameters->{mdKey} . "\" so we can start clean." );
                my @resultsString2 = $parameters->{database}->queryForName( { query => "/nmwg:store[\@type=\"LSStore\"]/nmwg:data[\@metadataIdRef=\"" . $parameters->{mdKey} . "\"]", txn => $parameters->{dbTr}, error => \$error } );
                my $len2 = $#resultsString2;
                for my $y ( 0 .. $len2 ) {
                    $parameters->{database}->remove( { name => $resultsString2[$y], txn => $parameters->{dbTr}, error => \$error } );
                    $errorFlag++ if $error;
                }
        }

        foreach my $d_content ( $parameters->{d}->childNodes ) {
            if ( $d_content->getType != 3 and $d_content->getType != 8 ) {
                my $cleanNode = $d_content->cloneNode(1);
                $cleanNode->removeAttribute("id");
                my $cleanHash = md5_hex( $cleanNode->toString );

                my $success = $parameters->{database}->queryByName( { name => $parameters->{mdKey} . "/" . $cleanHash, txn => $parameters->{dbTr}, error => \$error } );
                $errorFlag++ if $error;
                unless ($success) {
                my $insRes = $parameters->{database}->insertIntoContainer( { content => createLSData( { type => "LSStore", dataId => $parameters->{mdKey} . "/" . $cleanHash, metadataId => $parameters->{mdKey}, data => $d_content->toString } ), name => $parameters->{mdKey} . "/" . $cleanHash, txn => $parameters->{dbTr}, error => \$error } );
                    $errorFlag++ if $error;
                    $dCount++    if $insRes == 0;
                }
            }
        }
    }

    if ($errorFlag) {
        $parameters->{database}->abortTransaction( { txn => $parameters->{dbTr}, error => \$error } ) if $parameters->{dbTr};
        undef $parameters->{dbTr};
        throw perfSONAR_PS::Error_compat( "error.ls.xmldb", "Database errors prevented the transaction from completing." );
    }
    else {
        my $status = $parameters->{database}->commitTransaction( { txn => $parameters->{dbTr}, error => \$error } );
        if ( $status == 0 ) {
            createMetadata( $parameters->{doc}, $mdId, $parameters->{metadataId}, createLSKey( { key => $parameters->{mdKey}, eventType => "success.ls.register" } ), undef );
            createData( $parameters->{doc}, $dId, $mdId, "<nmwg:datum value=\"[" . $dCount . "] Data elements have been updated with key [" . $parameters->{mdKey} . "]\" />\n", undef );
            undef $parameters->{dbTr};
        }
        else {
            $parameters->{database}->abortTransaction( { txn => $parameters->{dbTr}, error => \$error } ) if $parameters->{dbTr};
            undef $parameters->{dbTr};
            throw perfSONAR_PS::Error_compat( "error.ls.xmldb", "Database Error: \"" . $error . "\"." );
        }
    }
    return;
}

=head2 lsRegisterRequestNew()

As a subprocedure of the main LSRegisterRequest procedure, this is the special
case of the brand new addition.  We will check to be sure that the data does
not already exist, if it does we treat this as an 'append' update.  

The following is a brief outline of the procedures:

    Does service info have an accessPoint
    Y: Is the key already in the database
      Y: Is the service info exactly the same
        Y: Treat this as an append, add things and update key
        N: Error out (to be safe, ask them to provide a key)
      N: Create a key, add data
    N: Error Out

=cut

sub lsRegisterRequestNew {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { doc => 1, database => 1, dbTr => 1, m => 1, d => 1, sec => 1, eventType => 1, auth => 1 } );

    my $error     = q{};
    my $errorFlag = 0;
    my $mdId      = "metadata." . genuid();
    my $dId       = "data." . genuid();

    my $accessPoint = extract( find( $parameters->{m}, "./*[local-name()='subject']/*[local-name()='service']/*[local-name()='accessPoint']", 1 ), 0 );
    my $accessType;
    my $accessName;
    unless ($accessPoint) {
        $accessPoint = extract( find( $parameters->{m}, "./*[local-name()='subject']/*[local-name()='service']/*[local-name()='address']", 1 ), 0 );
        $accessType = extract( find( $parameters->{m}, "./*[local-name()='subject']/*[local-name()='service']/*[local-name()='type']", 1 ), 0 );
        $accessName = extract( find( $parameters->{m}, "./*[local-name()='subject']/*[local-name()='service']/*[local-name()='name']", 1 ), 0 );
        unless ($accessPoint) {
            throw perfSONAR_PS::Error_compat( "error.ls.register.missing_value", "Cannont register data, accessPoint or address was not supplied." );
            return;
        }
    }

    my $mdKey = md5_hex( $accessPoint . $accessType . $accessName );
    unless ( exists $self->{STATE}->{"messageKeys"}->{$mdKey} ) {
        $self->{STATE}->{"messageKeys"}->{$mdKey} = $self->isValidKey( { txn => $parameters->{dbTr}, database => $parameters->{database}, key => $mdKey } );
    }

    my $update = 1;
    if( $parameters->{eventType} eq "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/registration/synchronization/2.0" ) {
        my @resultsString = $parameters->{database}->query( { query => "/nmwg:store[\@type=\"LSStore-control\"]/nmwg:metadata[\@metadataIdRef=\"".$mdKey."\"]/nmwg:parameters/nmwg:parameter[\@name=\"authoritative\"]/text()", txn => $parameters->{dbTr}, error => \$error } );
        $errorFlag++ if $error;
        if ( lc($resultsString[0]) eq "yes" ) {
            # if this is a synch message, AND we already have some authoratative
            # registration of the data (e.g. it was directly registered) we
            # don't want to touch it.
            $update = 0;
        }    
    }

    unless ( $self->{STATE}->{"messageKeys"}->{$mdKey} == 2 ) {
        if ( $self->{STATE}->{"messageKeys"}->{$mdKey} ) {
            if( $parameters->{eventType} eq "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/registration/synchronization/2.0" ) {
                if ( $update ) {
                    $parameters->{database}->updateByName( { content => createControlKey( { key => $mdKey, time => ( $parameters->{sec} + $self->{CONF}->{"gls"}->{"ls_ttl"} ), auth => $parameters->{auth} } ), name => $mdKey . "-control", txn => $parameters->{dbTr}, error => \$error } );
                    $errorFlag++ if $error;  

                    # special case: we always want to clobber the summary data
                    # (e.g. it may be different from time to time, therefore
                    # it is safest to just nuke it)
                    $self->{LOGGER}->debug( "Removing data for \"" . $mdKey . "\" so we can start clean." );
                    my @resultsString2 = $parameters->{database}->queryForName( { query => "/nmwg:store[\@type=\"LSStore\"]/nmwg:data[\@metadataIdRef=\"" . $mdKey . "\"]", txn => $parameters->{dbTr}, error => \$error } );
                    my $len2 = $#resultsString2;
                    for my $y ( 0 .. $len2 ) {
                        $parameters->{database}->remove( { name => $resultsString2[$y], txn => $parameters->{dbTr}, error => \$error } );
                        $errorFlag++ if $error;
                    }
                }
            }
            else {
                # simple update
            
                $self->{LOGGER}->debug("Key already exists, but updating control time information anyway.");
                $parameters->{database}->updateByName( { content => createControlKey( { key => $mdKey, time => ( $parameters->{sec} + $self->{CONF}->{"gls"}->{"ls_ttl"} ), auth => $parameters->{auth} } ), name => $mdKey . "-control", txn => $parameters->{dbTr}, error => \$error } );
                $errorFlag++ if $error;
            }
        }
        else {
            # newly added

            $self->{LOGGER}->debug("New registration info, inserting service metadata and time information.");
            my $service = $parameters->{m}->cloneNode(1);

            my $et = find( $service, "./nmwg:eventType", 1 );
            my $junk = $service->removeChild( $et ) if $et;
            
            $service->setAttribute( "id", $mdKey );
            $parameters->{database}->insertIntoContainer( { content => $parameters->{database}->wrapStore( { content => $service->toString, type => "LSStore" } ), name => $mdKey, txn => $parameters->{dbTr}, error => \$error } );
            $errorFlag++ if $error;
            $parameters->{database}->insertIntoContainer( { content => createControlKey( { key => $mdKey, time => ( $parameters->{sec} + $self->{CONF}->{"gls"}->{"ls_ttl"} ), auth => $parameters->{auth} } ), name => $mdKey . "-control", txn => $parameters->{dbTr}, error => \$error } );
            $errorFlag++ if $error;
        }
        $self->{STATE}->{"messageKeys"}->{$mdKey} = 2;        
    }

    my $dCount = 0;
    if( $update ) {
        # add only if we are allowed to
    
        foreach my $d_content ( $parameters->{d}->childNodes ) {
            if ( $d_content->getType != 3 and $d_content->getType != 8 ) {
                my $cleanNode = $d_content->cloneNode(1);
                $cleanNode->removeAttribute("id");
                my $cleanHash = md5_hex( $cleanNode->toString );
                my $success = $parameters->{database}->queryByName( { name => $mdKey . "/" . $cleanHash, txn => $parameters->{dbTr}, error => \$error } );
                $errorFlag++ if $error;
                unless ($success) {
                    my $insRes = $parameters->{database}->insertIntoContainer( { content => createLSData( { type => "LSStore", dataId => $mdKey . "/" . $cleanHash, metadataId => $mdKey, data => $d_content->toString } ), name => $mdKey . "/" . $cleanHash, txn => $parameters->{dbTr}, error => \$error } );
                    $errorFlag++ if $error;
                    $dCount++    if $insRes == 0;
                }
            }
        }
    }    

    if ($errorFlag) {
        $parameters->{database}->abortTransaction( { txn => $parameters->{dbTr}, error => \$error } ) if $parameters->{dbTr};
        throw perfSONAR_PS::Error_compat( "error.ls.xmldb", "Database errors prevented the transaction from completing." );
        undef $parameters->{dbTr};
    }
    else {
        my $status = $parameters->{database}->commitTransaction( { txn => $parameters->{dbTr}, error => \$error } );
        if ( $status == 0 ) {
            createMetadata( $parameters->{doc}, $mdId, $parameters->{m}->getAttribute("id"), createLSKey( { key => $mdKey, eventType => "success.ls.register" } ), undef );
            createData( $parameters->{doc}, $dId, $mdId, "<nmwg:datum value=\"[" . $dCount . "] Data elements have been registered with key [" . $mdKey . "]\" />\n", undef );
            undef $parameters->{dbTr};
        }
        else {
            $parameters->{database}->abortTransaction( { txn => $parameters->{dbTr}, error => \$error } ) if $parameters->{dbTr};
            undef $parameters->{dbTr};
            throw perfSONAR_PS::Error_compat( "error.ls.xmldb", "Database Error: \"" . $error . "\"." );
        }
    }
    return;
}

=head2 lsDeregisterRequest($self, $doc, $request)

The LSDeregisterRequest message should contain a key of an already registered
service, and then optionally any specific data to be removed (absense of data
indicates we want removal of ALL data).  After checking the validity of the key
and if possible any sent data, the items will be removed from the database.  The
response message will indicate success or failure.

The following is a brief outline of the procedures:

    Does MD have a key
    Y: Is Key in the DB?
      Y: Are there metadata blocks in the data section?
        Y: Remove ONLY the data for that service/control
        N: Deregister the service, all data, and remove the control
      N: Send 'error.deregister.ls.key_not_found' error
    N: Send 'error.ls.deregister.key_not_found' error

=cut

sub lsDeregisterRequest {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { doc => 1, request => 1, m => 1, d => 1, metadatadb => 1, summarydb => 1 } );

    my $msg   = q{};
    my $error = q{};
    my $mdId  = "metadata." . genuid();
    my $dId   = "data." . genuid();
    my ( $sec, $frac ) = Time::HiRes::gettimeofday;
    my $mdKey = extract( find( $parameters->{m}, "./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"lsKey\"]", 1 ), 0 );
    unless ($mdKey) {
        throw perfSONAR_PS::Error_compat( "error.ls.deregister.key_not_found", "Key not found in message." );
    }

    my $summary = 0;
    my $eventType = extract( find( $parameters->{m}, "./nmwg:eventType", 1 ), 0 );
    unless ( $eventType eq "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/deregistration/service/2.0" or 
             $eventType eq "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/deregistration/summary/2.0") {
        if( $eventType ) {
            throw perfSONAR_PS::Error_compat( "error.ls.deregister.eventType", "Incorrect eventType for LSDeregisterRequest." );
        }
    }

    if ( $eventType eq "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/deregistration/summary/2.0" ) {
        $summary++;
    }
    my $database = "";
    if ($summary) {
        $database = $parameters->{summarydb};
    }
    else {
        $database = $parameters->{metadatadb};
    }

    unless ( exists $self->{STATE}->{"messageKeys"}->{$mdKey} ) {
        $self->{STATE}->{"messageKeys"}->{$mdKey} = $self->isValidKey( { txn => q{}, database => $database, key => $mdKey } );
    }

    unless ( $self->{STATE}->{"messageKeys"}->{$mdKey} ) {
        throw perfSONAR_PS::Error_compat( "error.ls.deregister.key_not_found", "Sent key \"" . $mdKey . "\" was not registered." );
    }

    my $dbTr = $database->getTransaction( { error => \$error } );
    unless ($dbTr) {
        $database->abortTransaction( { txn => $dbTr, error => \$error } ) if $dbTr;
        undef $dbTr;
        throw perfSONAR_PS::Error_compat( "error.ls.xmldb", "Cound not start database transaction, database responded with \"" . $error . "\"." );
    }

    my @resultsString = ();
    my $errorFlag     = 0;
    my @deregs        = $parameters->{d}->getElementsByTagNameNS( $ls_namespaces{"nmwg"}, "metadata" );
    my $mdFlag        = 1;
    if ( $#deregs == -1 ) {
        $mdFlag = 0;
        @deregs = $parameters->{d}->getElementsByTagNameNS( $ls_namespaces{"nmtopo"}, "node" );
    }

    if ( $#deregs == -1 ) {
        $self->{LOGGER}->debug( "Removing all info for \"" . $mdKey . "\"." );
        @resultsString = $database->queryForName( { query => "/nmwg:store[\@type=\"LSStore\"]/nmwg:data[\@metadataIdRef=\"" . $mdKey . "\"]", txn => $dbTr, error => \$error } );
        my $len = $#resultsString;
        for my $x ( 0 .. $len ) {
            $database->remove( { name => $resultsString[$x], txn => $dbTr, error => \$error } );
            $errorFlag++ if $error;
        }
        $database->remove( { name => $mdKey . "-control", txn => $dbTr, error => \$error } );
        $errorFlag++ if $error;
        $database->remove( { name => $mdKey, txn => $dbTr, error => \$error } );
        $errorFlag++ if $error;
        $msg = "Removed [" . ( $#resultsString + 1 ) . "] data elements and service info for key \"" . $mdKey . "\".";
    }
    else {
        $self->{LOGGER}->debug( "Removing selected info for \"" . $mdKey . "\", keeping record." );
        foreach my $d_md (@deregs) {

            my $removeQuery = q{};
            if ($mdFlag) {
                @resultsString = $database->queryForName( { query => "/nmwg:store[\@type=\"LSStore\"]/nmwg:data[\@metadataIdRef=\"" . $mdKey . "\"]/nmwg:metadata[" . getMetadataXQuery( { node => $d_md } ) . "]", txn => $dbTr, error => \$error } );
            }
            else {
                @resultsString = $database->queryForName( { query => "/nmwg:store[\@type=\"LSStore\"]/nmwg:data[\@metadataIdRef=\"" . $mdKey . "\"]/nmtopo:node[" . getMetadataXQuery( { node => $d_md } ) . "]", txn => $dbTr, error => \$error } );
            }
            my $len = $#resultsString;
            for my $x ( 0 .. $len ) {
                $database->remove( { name => $resultsString[$x], txn => $dbTr, error => \$error } );
                $errorFlag++ if $error;
            }
        }
        $msg = "Removed [" . ( $#resultsString + 1 ) . "] data elements for key \"" . $mdKey . "\".";
    }

    if ($errorFlag) {
        $database->abortTransaction( { txn => $dbTr, error => \$error } ) if $dbTr;
        undef $dbTr;
        throw perfSONAR_PS::Error_compat( "error.ls.xmldb", "Database errors prevented the transaction from completing:" . $error );
    }
    else {
        my $status = $database->commitTransaction( { txn => $dbTr, error => \$error } );
        if ( $status == 0 ) {
            statusReport( $parameters->{doc}, $mdId, $parameters->{m}->getAttribute("id"), $dId, "success.ls.deregister", $msg );
            undef $dbTr;
        }
        else {
            $database->abortTransaction( { txn => $dbTr, error => \$error } ) if $dbTr;
            undef $dbTr;
            throw perfSONAR_PS::Error_compat( "error.ls.xmldb", "Database Error: \"" . $error . "\"." );
        }
    }
    return;
}

=head2 lsKeepaliveRequest($self, $doc, $request)

The LSKeepaliveRequest message must contain 'key' values identifying an 
already registered LS instance.  If the key for the sent LS is valid the
internal state (i.e. time values) will be advanced so the data set is not
cleaned by the LS Reaper.  Response messages should indicate success or
failure. 

The following is a brief outline of the procedures:

    Does MD have a key
      Y: Is Key in the DB?
        Y: update control info
        N: Send 'error.ls.keepalive.key_not_found' error
      N: Send 'error.ls.keepalive.key_not_found' error

=cut

sub lsKeepaliveRequest {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { doc => 1, request => 1, m => 1, metadatadb => 1, summarydb => 1 } );

    my $error = q{};
    my $mdId  = "metadata." . genuid();
    my $dId   = "data." . genuid();

    my $auth = 1;

    my ( $sec, $frac ) = Time::HiRes::gettimeofday;
    my $mdKey = extract( find( $parameters->{m}, "./nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"lsKey\"]", 1 ), 0 );
    unless ($mdKey) {
        throw perfSONAR_PS::Error_compat( "error.ls.keepalive.key_not_found", "Key not found in message." );
    }

    my $summary = 0;
    my $eventType = extract( find( $parameters->{m}, "./nmwg:eventType", 1 ), 0 );
    unless ( $eventType eq "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/keepalive/service/2.0" or 
             $eventType eq "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/keepalive/summary/2.0") {
        if( $eventType ) {
            throw perfSONAR_PS::Error_compat( "error.ls.keepalive.eventType", "Incorrect eventType for LSKeepaliveRequest." );
        }
    }
    
    if ( $eventType eq "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/keepalive/summary/2.0" ) {
        $summary++;
    }
    my $database = "";
    if ($summary) {
        $database = $parameters->{summarydb};
    }
    else {
        $database = $parameters->{metadatadb};
    }

    unless ( exists $self->{STATE}->{"messageKeys"}->{$mdKey} ) {
        $self->{STATE}->{"messageKeys"}->{$mdKey} = $self->isValidKey( { txn => q{}, database => $database, key => $mdKey } );
    }

    unless ( $self->{STATE}->{"messageKeys"}->{$mdKey} ) {
        throw perfSONAR_PS::Error_compat( "error.ls.keepalive.key_not_found", "Sent key \"" . $mdKey . "\" was not registered." );
    }

    if ( $self->{STATE}->{"messageKeys"}->{$mdKey} == 1 ) {

        my $database;
        if ($summary) {
            $database = $parameters->{summarydb};
        }
        else {
            $database = $parameters->{metadatadb};
        }

        my $dbTr = $database->getTransaction( { error => \$error } );
        unless ($dbTr) {
            $database->abortTransaction( { txn => $dbTr, error => \$error } ) if $dbTr;
            undef $dbTr;
            throw perfSONAR_PS::Error_compat( "error.ls.xmldb", "Cound not start database transaction, database responded with \"" . $error . "\"." );
        }

        $self->{LOGGER}->debug("Updating control time information.");
        my $status = $database->updateByName( { content => createControlKey( { key => $mdKey, time => ( $sec + $self->{CONF}->{"gls"}->{"ls_ttl"} ), auth => $auth } ), name => $mdKey . "-control", txn => $dbTr, error => \$error } );

        unless ( $status == 0 ) {
            $database->abortTransaction( { txn => $dbTr, error => \$error } ) if $dbTr;
            undef $dbTr;
            throw perfSONAR_PS::Error_compat( "error.ls.xmldb", "Database Error: \"" . $error . "\"." );
        }

        $status = $database->commitTransaction( { txn => $dbTr, error => \$error } );
        if ( $status == 0 ) {
            statusReport( $parameters->{doc}, $mdId, $parameters->{m}->getAttribute("id"), $dId, "success.ls.keepalive", "Key \"" . $mdKey . "\" was updated." );
            $self->{STATE}->{"messageKeys"}->{$mdKey}++;
            undef $dbTr;
        }
        else {
            $database->abortTransaction( { txn => $dbTr, error => \$error } ) if $dbTr;
            undef $dbTr;
            throw perfSONAR_PS::Error_compat( "error.ls.xmldb", "Database Error: \"" . $error . "\"." );
        }
    }
    else {
        statusReport( $parameters->{doc}, $mdId, $parameters->{m}->getAttribute("id"), $dId, "success.ls.keepalive", "Key \"" . $mdKey . "\" was already updated in this exchange, skipping." );
    }
    return;
}

=head2 lsQueryRequest($self, $doc, $request)

The LSQueryRequest message contains a query string written in either the XQuery
or XPath languages.  This query string will be extracted and directed to the 
XML Database.  The result (succes being defined as actual XML data, failure
being an error message) will then be packaged and sent in the response message.

The following is a brief outline of the procedures:

    Does MD have a supported subject (xquery: only currently)
    Y: does it have an eventType and is it currently supported?
      Y: Send query to DB, prepare results
      N: Send 'error.ls.query.eventType' error
    N: Send 'error.ls.query.query_not_found' error

Any database errors will cause the given metadata/data pair to fail.

=cut

sub lsQueryRequest {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { doc => 1, request => 1, m => 1, metadatadb => 1, summarydb => 1 } );

    my $error = q{};
    my $mdId  = "metadata." . genuid();
    my $dId   = "data." . genuid();
    my ( $sec, $frac ) = Time::HiRes::gettimeofday;

    my %query_map = (
        "service.lookup.xquery"                                                              => 1,
        "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xquery/1.0"               => 1,
        "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/query/xquery/2.0"         => 1,
        "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/query/control/xquery/2.0" => 1
    );
    my %summary_map = (
        "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/discovery/xquery/2.0"         => 1,
        "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/discovery/control/xquery/2.0" => 1,
        "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/discovery/summary/2.0" => 1
    );

    my $database;
    my $eventType = extract( find( $parameters->{m}, "./nmwg:eventType", 1 ), 0 );
    if ( $eventType and $summary_map{$eventType} ) {
        $database = $parameters->{summarydb};
    }
    else {
        if ( $eventType and $query_map{$eventType} ) {
            $database = $parameters->{metadatadb};
        }
        else {
            throw perfSONAR_PS::Error_compat( "error.ls.query.eventType", "Given query type is missing or not supported." );
        }
    }

    # special case discovery message
    if( $eventType eq "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/discovery/summary/2.0" ) {
        my $sum_parameters = find( $parameters->{m}, "./summary:parameters", 1 );  

        my $subject = find( $parameters->{m}, "./summary:subject", 1 );        
        unless ( $subject ) {
            throw perfSONAR_PS::Error_compat( "error.ls.query.subject_not_found", "Summary subject not found in metadata." );
        } 

        if ( $self->{CONF}->{"gls"}->{"root"} ) {
            # special case for 'self' summary in the hLS instances
            $database = $parameters->{metadatadb};
        }

        # pull out items from the summary subject               
        my @resultServices = ();
        my $sent;
        my $l_eventTypes = find( $subject, "./nmwg:eventType", 0 );
        foreach my $e ( $l_eventTypes->get_nodelist ) {
            my $value = extract( $e, 0 );
            next unless $value;
            $sent->{"eventType"}->{$value} = 1
        }      

        if ( $sum_parameters ) {
            my $l2_eventTypes = find( $sum_parameters, ".//nmwg:parameter[\@name=\"eventType\" or \@name=\"supportedEventType\"]", 0 );
            foreach my $e ( $l2_eventTypes->get_nodelist ) {
                my $value = extract( $e, 0 );
                next unless $value;
                $sent->{"eventType"}->{$value} = 1
            } 
        }

        my $l_domains = find( $subject, "./nmtb:domain", 0 );
        foreach my $d ( $l_domains->get_nodelist ) {
            my $name = extract( find( $d, "./nmtb:name", 1 ), 0 );
            next unless $name;
            $sent->{"domain"}->{$name} = 1
        }    

        my $l_addresses = find( $subject, "./nmtb:address", 0 );
        foreach my $address ( $l_addresses->get_nodelist ) {
            my $ad = extract( $address, 0 );
            next unless $ad;
            $sent->{"address"}->{$ad} = 1
        } 

        # pull out items from the summary parameters        

        if ( $sum_parameters ) {
            my $l_keywords = find( $sum_parameters, ".//nmwg:parameter[\@name=\"keyword\"]", 0 );
            foreach my $k ( $l_keywords->get_nodelist ) {
                my $value = extract( $k, 0 );
                next unless $value;
                $sent->{"keyword"}->{$value} = 1
            }
        } 
        
        # extract our summaries
        my @resultsString = $database->query( { query => "/nmwg:store[\@type=\"LSStore\"]/nmwg:data", txn => q{}, error => \$error } );
        my $len = $#resultsString;
        throw perfSONAR_PS::Error_compat( "error.ls.query.summary_error", "Service empty, query not found." ) if $len == -1;
       
        for my $x ( 0 .. $len ) {
            my $parser = XML::LibXML->new();
            my $doc    = $parser->parse_string( $resultsString[$x] );

            my %store = ();
            $store{ "eventType" } = 0 if exists $sent->{ "eventType" };
            $store{ "address" } = 0 if exists $sent->{ "address" };
            $store{ "domain" } = 0 if exists $sent->{ "domain" };
            $store{ "keyword" } = 0 if exists $sent->{ "keyword" };

            # gather eventTypes
            if ( exists $store{ "eventType" } ) {
                my $l_eventTypes = find( $doc->getDocumentElement, "./nmwg:metadata/nmwg:eventType", 0 );
                my $l_supportedEventTypes = find( $doc->getDocumentElement, "./nmwg:metadata/nmwg:parameter[\@name=\"supportedEventType\" or \@name=\"eventType\"]", 0 );
                foreach my $e ( $l_eventTypes->get_nodelist ) {
                    my $value = extract( $e, 0 );
                    next unless $value;
                    $store{"eventType"}++ if $sent->{ "eventType" }->{ $value };
                }
                foreach my $se ( $l_supportedEventTypes->get_nodelist ) {
                    my $value = extract( $se, 0 );
                    next unless $value;
                    $store{"eventType"}++ if $sent->{ "eventType" }->{ $value };
                }      
            }          
   
            # gather the domains
            if ( exists $store{ "domain" } ) {
                my $l_domains = find( $doc->getDocumentElement, "./nmwg:metadata/summary:subject/nmtb:domain", 0 );
                foreach my $d ( $l_domains->get_nodelist ) {
                    my $name = extract( find( $d, "./nmtb:name", 1 ), 0 );
                    next unless $name;
                    $store{"domain"}++ if $sent->{ "domain" }->{ $name };
                }     
            }
            
            #gather the networks
            if ( exists $store{ "address" } ) {

                my $l_networks = find( $doc->getDocumentElement, "./nmwg:metadata/summary:subject/nmtl3:network", 0 );
                my @cidr_list = ();
                foreach my $n ( $l_networks->get_nodelist ) {
                    my $address = extract( find( $n, "./nmtl3:subnet/nmtl3:address", 1 ), 0 );
                    my $mask = extract( find( $n, "./nmtl3:subnet/nmtl3:netmask", 1 ), 0 );
                    if ( $address ) {
                        $address .= "/" . $mask if $mask;
                        @cidr_list = Net::CIDR::cidradd($address, @cidr_list);
                    }
                }  

                # we need to do some CIDR finding
                foreach my $add (keys %{$sent->{ "address" }} ) {
                    $store{"address"}++ if Net::CIDR::cidrlookup($add, @cidr_list);
                }
            }

            # gather keywords
            if ( exists $store{ "keyword" } ) {
                my $l_keywords = find( $doc->getDocumentElement, "./nmwg:metadata//nmwg:parameter[\@name=\"keyword\"]", 0 );
                foreach my $k ( $l_keywords->get_nodelist ) {
                    my $value = extract( $k, 0 );
                    next unless $value;
                    $store{"keyword"}++ if $sent->{ "keyword" }->{ $value };
                }      
            }    

            # we have a mactch, get the contact service.
            my $flag = 1;
            foreach my $key ( keys %store ) {
                $flag = $store{$key};
                last if $flag <= 0;
            }

            if ( $flag ) {         
                my $query2 = "/nmwg:store[\@type=\"LSStore\"]/nmwg:metadata[\@id=\"".$doc->getDocumentElement->getAttribute("metadataIdRef")."\"]";
                my @resultsString2 = $database->query( { query => $query2, txn => q{}, error => \$error } );
                my $len2 = $#resultsString2;
                for my $y ( 0 .. $len2 ) {
                    push @resultServices, $resultsString2[$y];
                }
            }
        }
               
        if($#resultServices == -1) {
            createMetadata( $parameters->{doc}, $mdId, $parameters->{m}->getAttribute("id"), $subject->toString . "\n<nmwg:eventType>error.ls.query.empty_results</nmwg:eventType>\n" , undef );  
            createData( $parameters->{doc}, $dId, $mdId, "<nmwgr:datum xmlns:nmwgr=\"http://ggf.org/ns/nmwg/result/2.0/\">Nothing returned for search.</nmwgr:datum>\n", undef );                
        }
        else {
            createMetadata( $parameters->{doc}, $mdId, $parameters->{m}->getAttribute("id"), $subject->toString . "\n<nmwg:eventType>" . $eventType . "</nmwg:eventType>\n" , undef );  
            foreach my $metadata (@resultServices) {
                createData( $parameters->{doc}, $dId, $mdId, $metadata, undef );                
            }
        }                           
    }
    else {
        # deny the 'control' eventTypes for now    
        if ( $eventType eq "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/query/control/xquery/2.0" or 
             $eventType eq "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/discovery/control/xquery/2.0" ) {
            throw perfSONAR_PS::Error_compat( "error.ls.query.eventType", "Sent evnentType not supported." );
        }
    
        my $query = extractQuery( { node => find( $parameters->{m}, "./xquery:subject", 1 ) } );
        unless ($query) {
            throw perfSONAR_PS::Error_compat( "error.ls.query.query_not_found", "Query not found in sent metadata." );
        }
        $query =~ s/\s+\// collection('CHANGEME')\//gmx;
    
        my @resultsString = $database->query( { query => $query, txn => q{}, error => \$error } );
        if ($error) {
            throw perfSONAR_PS::Error_compat( "error.ls.xmldb", $error );
        }

        my $dataString = q{};
        my $len        = $#resultsString;
        for my $x ( 0 .. $len ) {
            $dataString = $dataString . $resultsString[$x];
        }
        unless ($dataString) {
            throw perfSONAR_PS::Error_compat( "error.ls.query.empty_results", "Nothing returned for search." );
        }

        createMetadata( $parameters->{doc}, $mdId, $parameters->{m}->getAttribute("id"), "<nmwg:eventType>success.ls.query</nmwg:eventType>", undef );
        my $mdPparameters = q{};
        $mdPparameters = extractQuery( { node => find( $parameters->{m}, "./xquery:parameters/nmwg:parameter[\@name=\"lsOutput\"]", 1 ) } );
        if ( not $mdPparameters ) {
            $mdPparameters = extractQuery( { node => find( $parameters->{m}, "./nmwg:parameters/nmwg:parameter[\@name=\"lsOutput\"]", 1 ) } );
        }

        if ( $mdPparameters eq "native" ) {
            createData( $parameters->{doc}, $dId, $mdId, "<psservice:datum xmlns:psservice=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/\">" . $dataString . "</psservice:datum>\n", undef );
        }
        else {
            createData( $parameters->{doc}, $dId, $mdId, "<psservice:datum xmlns:psservice=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/\">" . escapeString($dataString) . "</psservice:datum>\n", undef );
        }
    }    
    return;
}

=head2 lsKeyRequest($self, { doc request metadatadb })

The LSKeyRequest message contains service information of a potentially
registered service.  If this service is registered, the lsKey will be returned
otherwise an error will be returned.

Any database errors will cause the given metadata/data pair to fail.

=cut

sub lsKeyRequest {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { doc => 1, request => 1, m => 1, metadatadb => 1, summarydb => 1 } );

    my $error     = q{};
    my $summary   = 0;
    my $et = find( $parameters->{m}, "./nmwg:eventType", 1 );
    my $eventType = extract( $et, 0 );
    unless ( $eventType eq "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/key/service/2.0" or 
             $eventType eq "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/key/summary/2.0") {
        if( $eventType ) {
            throw perfSONAR_PS::Error_compat( "error.ls.key.eventType", "Incorrect eventType for LSKeyRequest." );
        }
    }
    
    if ( $eventType eq "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/key/summary/2.0" ) {
        $summary++;
    }

    my $service = find( $parameters->{m}, "./*[local-name()='subject']/*[local-name()='service']", 1 );
    if ($service) {
        my $junk = $parameters->{m}->removeChild( $et ) if $et;
        my $queryString = "collection('CHANGEME')/nmwg:store[\@type=\"LSStore\"]/nmwg:metadata[" . getMetadataXQuery( { node => $parameters->{m} } ) . "]";

        my @resultsString = ();

        if ($summary) {
            @resultsString = $parameters->{summarydb}->query( { query => $queryString, txn => q{}, error => \$error } );
        }
        else {
            @resultsString = $parameters->{metadatadb}->query( { query => $queryString, txn => q{}, error => \$error } );
        }

        if ($error) {
            throw perfSONAR_PS::Error_compat( "error.ls.xmldb", $error );
        }

        unless ( $#resultsString == 0 ) {
            throw perfSONAR_PS::Error_compat( "error.ls.key.not_registered", "Service was not registered in this LS." );
        }

        my $parser   = XML::LibXML->new();
        my $metadata = $parser->parse_string( $resultsString[0] );
        if ( $metadata and $metadata->getDocumentElement->getAttribute("id") ) {
            my $mdId = "metadata." . genuid();
            my $dId  = "data." . genuid();
            createMetadata( $parameters->{doc}, $mdId, $parameters->{m}->getAttribute("id"), $service->toString, undef );
            createData( $parameters->{doc}, $dId, $mdId, createLSKey( { key => $metadata->getDocumentElement->getAttribute("id") } ), undef );
        }
        else {
            throw perfSONAR_PS::Error_compat( "error.ls.key.not_registered", "Service was not registered in this LS." );
        }
    }
    else {
        throw perfSONAR_PS::Error_compat( "error.ls.key.service_missing", "Cannont find data, service element was not found." );
    }
    return;
}

1;

__END__

=head1 SEE ALSO

L<Log::Log4per>, L<Time::HiRes>, L<Params::Validate>, L<Digest::MD5>,
L<Net::CIDR>, L<Net::IPTrie>, L<Net::Ping>, L<LWP::Simple>, L<File::stat>,
L<perfSONAR_PS::Services::MA::General>, L<perfSONAR_PS::Services::LS::General>,
L<perfSONAR_PS::Common>, L<perfSONAR_PS::Messages>, L<perfSONAR_PS::DB::XMLDB>,
L<perfSONAR_PS::Error_compat>, L<perfSONAR_PS::ParameterValidation>,
L<perfSONAR_PS::Client::LS>, L<perfSONAR_PS::Client::gLS>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS

Questions and comments can be directed to the author, or the mailing list.  Bugs,
feature requests, and improvements can be directed here:

  http://code.google.com/p/perfsonar-ps/issues/list

=head1 VERSION

$Id$

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework along
with this software.  If not, see <http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2004-2008, Internet2 and the University of Delaware

All rights reserved.

=cut
# vim: expandtab shiftwidth=4 tabstop=4
