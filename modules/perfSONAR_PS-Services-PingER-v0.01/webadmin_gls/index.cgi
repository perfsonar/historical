#!/usr/bin/perl -w

=head1  NAME  

           configure.pl   - pinger MP webadmin
 

=head1 DESCRIPTION

    this is CGI::Ajax based script for pinger MP landmarks file webadmin configuration
  
=head1 SYNOPSIS
     
      pinger monitoring configuration  webinterface
     first virtual page is to see domains and add/remove/update them,
     second virtual page is to add/remove/update nodes  of the particular domain
     third virtual page is to configure ping test parameters for monitoring of the paricular node/domain
     every page is Ajaxed, means its interactively updates webpage while you are entering and its not a multi-page 
     use "Save" button to save new config in file ( it will effectively update landmarks XML   )
     
   
        
=head1 AUTHORS

     Maxim Grigoriev, maxim_at_fnal_gov   2007-2008        
     Aaron Brown, aaron_at_internet2_edu  2008
     
=head1 FUNCTIONS


=cut

use strict;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use CGI qw/:standard/;
use CGI::Carp qw(fatalsToBrowser);
use Data::Dumper;
use CGI::Session;
use CGI::Ajax;
use HTML::Template;
use IO::File;
use File::Copy;
use Storable qw(lock_retrieve lock_store);
use Log::Log4perl qw(get_logger :levels);
use Config::General;
use Storable qw(freeze thaw);
use perfSONAR_PS::Client::gLS;
use perfSONAR_PS::Common;
use perfSONAR_PS::Utils::DNS qw/reverse_dns resolve_address/;
use perfSONAR_PS::Datatypes::EventTypes;

use aliased  'perfSONAR_PS::SONAR_DATATYPES::v2_0::psservice::Message::Metadata::Subject::Service';

use aliased 'perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::pingertopo::Topology';
use aliased 'perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::pingertopo::Topology::Domain';
use aliased 'perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::pingertopo::Topology::Domain::Node';
use aliased 'perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::nmtb::Topology::Domain::Node::Name';
use aliased 'perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::nmtb::Topology::Domain::Node::HostName';
use aliased 'perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::nmwg::Topology::Domain::Node::Parameters';
use aliased 'perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::nmwg::Topology::Domain::Node::Parameters::Parameter';
use aliased 'perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::nmtl3::Topology::Domain::Node::Port';
use constant URNBASE => 'urn:ogf:network';

use constant BASEDIR => "$Bin/";

croak( "Please fix your deployment, basedir is not what pointing to the webadmin root: " . BASEDIR ) unless -d BASEDIR . "/etc";

our $CONFIG_FILE    = BASEDIR . '/etc/GeneralSystem.conf';
our %GENERAL_CONFIG = %{ loadConfig() };
 
Log::Log4perl->init( $GENERAL_CONFIG{LOGGER_CONF} );
my $logger = get_logger("configure");

$logger->debug( "Config: " . Dumper( \%GENERAL_CONFIG ) );

$ENV{PATH} = '/usr/bin:/usr/local/bin:/bin';

#
#   although this is  the CGI script, but there is no HTML here
#   all html layout is defined by templates,   style defined by CSS
#   and interactive dynamic features exposed by javascript/Ajax
#
my $cgi     = CGI->new();
my $SESSION = new CGI::Session( "driver:File;serializer:Storable", $cgi, { Directory => '/tmp' } );    ## to keep our session
my $COOKIE  = $cgi->cookie( 'CGISESSID' => $SESSION->id );                                             ########   get cookie
$COOKIE->path($cgi->url(-absolute=>1));
#### to make it interactive ( registering perl calls as javascript functions)
##
my $ajax = CGI::Ajax->new(
    'updateGlobal'  => \&updateGlobal,
    'updateNode'    => \&updateNode,
    'configureNode' => \&configureNode,
    'saveConfigs'   => \&saveConfigs,
    'resetit'       => \&resetit
);

#### These our global vars, there is no way to escape them since CGI::Ajax doesnt support structured data ( JSON ?)
#
my ( $TOPOLOGY_OBJ, $LANDMARKS_CONFIG, $GLS_PROJECTS );
###check if we saved previous session
unless ( $SESSION && !$SESSION->is_expired && $SESSION->param("DOMAINS") ) {
    fromFile();
    readgLSSites();

    storeSESSION($SESSION);
}
else {
    $LANDMARKS_CONFIG = $SESSION->param("DOMAINS");
    $TOPOLOGY_OBJ     = Topology->new( { xml => $LANDMARKS_CONFIG } );
    $GLS_PROJECTS     = thaw( $SESSION->param("GLS_PROJECTS") );

}
my $TEMPLATE_HEADER = HTML::Template->new( filename => $GENERAL_CONFIG{what_template}->{header} );
$TEMPLATE_HEADER->param( 'Title' => "$GENERAL_CONFIG{MYDOMAIN} Pinger MP Configuration Manager" );
my $TEMPLATE_FOOTER = HTML::Template->new( filename => $GENERAL_CONFIG{what_template}->{footer} );
######## global view
my $myhtml = $TEMPLATE_HEADER->output() . displayGlobal() . $TEMPLATE_FOOTER->output();    ##### get html
                                                                                           #$ajax->DEBUG($DEBUG);
                                                                                           #$ajax->JSDEBUG($DEBUG);
print $ajax->build_html( $cgi, $myhtml, { '-Expires' => '1d', '-cookie' => $COOKIE } );

=head2 readgLSSites

  Reads the set of pingable sites from the gLS and stores it in the global variable $GLS_PROJECTS

=cut

sub readgLSSites {
    my %HOSTS_BY_PROJECT = ();

    if ( not $GENERAL_CONFIG{DISABLE_GLS_LOOKUP} ) {
        my $gls;
        if ( $GENERAL_CONFIG{GLS_HINTS_FILE} ) {
            $logger->debug( "Using gLS hints file: " . $GENERAL_CONFIG{GLS_HINTS_FILE} );
            $gls = perfSONAR_PS::Client::gLS->new( { file => $GENERAL_CONFIG{GLS_HINTS_FILE} } );
        }
        elsif ( $GENERAL_CONFIG{GLS_HINTS_URL} ) {
            $logger->debug( "Using gLS hints URL: " . $GENERAL_CONFIG{GLS_HINTS_URL} );
            $gls = perfSONAR_PS::Client::gLS->new( { url => $GENERAL_CONFIG{GLS_HINTS_URL} } );
        }
        else {
            my $default_url = "http://www.perfsonar.net/gls.root.hints";
            $logger->debug( "Using default gLS hints URL: " . $default_url );
            $gls = perfSONAR_PS::Client::gLS->new( { url => $default_url } );
        }
 
        if ( not $gls->{ROOTS} ) {
            $logger->debug("No gLS Roots found!");
        }
        else {
            $logger->debug("Found gLS roots, looking up 'pinger' tools");

            my @eventTypes = ($GENERAL_CONFIG{EVENTTYPE}->tools->pinger);

            my @keywords = ();
            $logger->debug( "General Config: " . Dumper( \%GENERAL_CONFIG ) );
            if ( $GENERAL_CONFIG{PROJECT} ) {
                foreach my $project ( @{ $GENERAL_CONFIG{PROJECT} } ) {
                    push @keywords, "project:" . $project;
                }
            }
            else {
                push @keywords, "all";
            }

            my %reverse_dns_cache = ();

            foreach my $keyword (@keywords) {
                my @curr_hosts = ();

                my $result;
                if ( $keyword eq "all" ) {
                    $result = $gls->getLSLocation( { eventTypes => \@eventTypes } );
                }
                else {
                    my @send_keywords = ();
                    push @send_keywords, $keyword;

                    $result = $gls->getLSLocation( { eventTypes => \@eventTypes, keywords => \@send_keywords } );
                }

                foreach my $s ( @{$result} ) {
                    
                    my $service = Service->new({ xml => $s })
                    my $res;

                    my $description = findvalue( $doc->getDocumentElement, ".//*[local-name()='description']", 0 );

                    my @dns_names = ();

                    my @addrs = ();
                    my $res = find( $doc->getDocumentElement, ".//*[local-name()='address' and \@type=\"ipv4\"]", 0 );
                    foreach my $c ( $res->get_nodelist ) {
                        my $contact = extract( $c, 0 );

                        next if $contact =~ m/^10\./;
                        next if $contact =~ m/^192\.168\./;
                        next if $contact =~ m/^172\.16/;

                        my $dns_name;

                        if ( $reverse_dns_cache{$contact} ) {
                            $dns_name = reverse_dns($contact);
                        }
                        else {
                            $dns_name = reverse_dns($contact);
                            if ($dns_name) {
                                $reverse_dns_cache{$contact} = $dns_name;
                            }
                        }

                        if ($dns_name) {
                            push @dns_names, $dns_name;
                        }

                        push @addrs, $contact;
                    }

                    my $res = find( $doc->getDocumentElement, ".//*[local-name()='address' and \@type=\"ipv6\"]", 0 );
                    foreach my $c ( $res->get_nodelist ) {
                        my $contact = extract( $c, 0 );
                        my $dns_name = reverse_dns($contact);

                        push @dns_names, $dns_name;
                        push @addrs,     $contact;
                    }

                    # calculate the domain and the hostname
                    my $hostname;
                    my $domain;
                    foreach my $name (@dns_names) {
                        if ( $name =~ /^([^\.]+)\.(.*)/ ) {
                            $hostname = $1;
                            $domain   = $2;

                            last;
                        }
                    }

                    next unless ( $hostname and $domain );

                    my $domain_urn = "urn:ogf:network:domain=" . $domain;
                    my $node_urn   = $domain_urn . ":node=" . $hostname;

                    my %service_info = ();
                    $service_info{"description"} = $description;
                    $service_info{"hostname"}    = $hostname;
                    $service_info{"domain_name"} = $domain;
                    $service_info{"domain_urn"}  = $domain_urn;
                    $service_info{"node_urn"}    = $node_urn;
                    $service_info{"addresses"}   = \@addrs;

                    push @curr_hosts, \%service_info;
                }

                my $project_name;

                if ( $keyword =~ /^project:(.*)/ ) {
                    $project_name = "Project " . $1;
                }
                else {
                    $project_name = "All";
                }

                $HOSTS_BY_PROJECT{$project_name} = \@curr_hosts;
            }
        }
    }

    $GLS_PROJECTS = \%HOSTS_BY_PROJECT;

    return;
}

=head2 isParam 

  returns true if argument string among supported pigner test parameters
  otherwise returns undef

=cut

sub isParam {
    my ($name) = @_;
    return 1 if $name =~ /^(packetSize|count|packetInterval|measurementPeriod|ttl|measurementOffset|ipAddress|type|hostName)/;
    return;
}

=head2 fromFile

   get landmarks from file into the object
   returns 0 if ok or dies

=cut

sub fromFile {
    my $file = $GENERAL_CONFIG{LANDMARKS};
    eval {
        local ( $/, *FH );
        open( FH, $file ) or die " Failed to open landmarks $file";
        my $text = <FH>;
        $TOPOLOGY_OBJ = Topology->new( { xml => $text } );
        $LANDMARKS_CONFIG = $text;
        close FH;
    };
    if ($@) {
        $logger->logdie( " Failed to load landmarks $file " . $@ );
    }
    return 0;
}

=head2 displayResponse

=cut

sub displayResponse {
    my $message = shift;
    return "Last Action Status: " . $message;

}

=head2  storeSESSION

    store current session params

=cut

sub storeSESSION {
    my ($sess) = @_;
    $sess->param( "DOMAINS",      $TOPOLOGY_OBJ->asString );
    $sess->param( "GLS_PROJECTS", freeze($GLS_PROJECTS) );
}

=head2  saveConfigs

  update XML files ( Template for MP and    restart MP daemon)

=cut   

sub saveConfigs {
    my ($input) = shift;
    return displayGlobal(), "Wrong Request"
        unless $input && $input =~ /^Save\ MP landmarks XML$/;
    my $tmp_file = "/tmp/temp_LANDMARKS." . $SESSION->id;
    my $fd = new IO::File(">$tmp_file") or $logger->logdie( "Failed to open file $tmp_file" . $! );
    eval { print $fd $TOPOLOGY_OBJ->asString; };
    if ($@) {
        $logger->logdie("Failed to print $@");
    }

    $fd->close;
    move( $tmp_file, $GENERAL_CONFIG{LANDMARKS} ) or $logger->logdie( "Failed to replace:" . $GENERAL_CONFIG{LANDMARKS} . " due - $! " );
    return displayGlobal(), displayResponse("MP landmarks XML file was Saved"), '&nbsp;';
}

=head2  resetit

   reset  web interface

=cut

sub resetit {
    my ($input) = shift;
    return displayGlobal(), "Wrong Request" unless $input && $input eq 'Reset';

    readgLSSites();
    fromFile();
    storeSESSION($SESSION);

    return displayGlobal(), displayResponse(" MP landmarks XML configuration was reset "), '&nbsp;';

}

=head2 displayGlobal

   prints global view

   arguments:  
              $TOPOLOGY_OBJ - topology objects tree with domains to be monitored from XML template file
             
   return:  $html - HTML string

=cut

sub displayGlobal {
    my $TEMPLATEg            = HTML::Template->new( filename => $GENERAL_CONFIG{what_template}->{'Domains'} );
    my @table2display        = ();
    my %domain_names         = ();
    my %gls_display_projects = ();
    eval {
        foreach my $domain ( @{ $TOPOLOGY_OBJ->get_domain } )
        {
            my $urn = $domain->get_id;
            if ($urn) {
                my ($dname) = $urn =~ /\:domain\=([^\:]+)/;
                my $nodes = $domain->get_node;
                my @nodenames = ();
                foreach my $node ( @{$nodes} ) {
                    push @nodenames, { node_name => $node->get_name->get_text, urn => $node->get_id }
                        if $node->get_name;
                }
                $domain_names{$dname} = {
                    domain_name => $dname,
                    urn         => $domain->get_id,
                    Nodes       => \@nodenames
                };
            }
        }

        my %used_addresses = ();

        foreach my $domain ( @{ $TOPOLOGY_OBJ->get_domain } ) {
            if ( $domain->get_node ) {
                foreach my $node ( @{ $domain->get_node } ) {
                    my $port = $node->get_port;

                    $logger->debug( "Used Address: " . $port->get_ipAddress->get_text );
                    $used_addresses{ $port->get_ipAddress->get_text } = 1;
                }
            }
        }

        foreach my $project ( keys %{$GLS_PROJECTS} ) {
            my %project_domains = ();

            foreach my $service ( @{ $GLS_PROJECTS->{$project} } ) {
                my $exists;

                foreach my $addr ( @{ $service->{"addresses"} } ) {
                    $logger->debug( "Checking Address: " . $addr );
                    if ( $used_addresses{$addr} ) {
                        $exists = 1;
                    }
                }

                next if ($exists);

                my @dns_names = ();

                my $dns_name;
                foreach my $addr ( @{ $service->{"addresses"} } ) {
                    $dns_name = reverse_dns($addr);

                    if ($dns_name) {
                        push @dns_names, $dns_name;
                    }
                }

                # calculate the domain and the hostname
                my $hostname;
                my $domain_name;
                foreach my $name (@dns_names) {
                    if ( $name =~ /([^.]+).(.*)/ ) {
                        $hostname    = $1;
                        $domain_name = $2;

                        last;
                    }
                }

                # if we don't have a domain or hostname, skip 'em
                next unless ( $hostname and $domain_name );

                my $domain_urn = "urn:ogf:network:domain=" . $domain_name;
                my $node_urn   = $domain_urn . ":node=" . $hostname;

                if ( not $project_domains{$domain_name} ) {
                    $project_domains{$domain_name} = {
                        domain_name => $domain_name,
                        urn         => $domain_urn,
                        Nodes       => {}
                    };
                }

                if ( $project_domains{$domain_name}->{Nodes}->{$hostname} ) {

                    # if we get here, then we've seen the same node twice. skip it.
                    next;
                }

                $project_domains{$domain_name}->{Nodes}->{$hostname} = {
                    node_name => $hostname,
                    urn       => $node_urn,
                    Addresses => $service->{"addresses"},
                };
            }

            $gls_display_projects{$project} = \%project_domains;
        }
    };
    if ($@) {
        $logger->logdie("Display global failed $@ ");
    }

    @table2display = ();
    foreach my $domain ( sort keys %domain_names ) {
        push @table2display, $domain_names{$domain};
    }
    ###$logger->debug(" ------------------- Domains: " . Dumper  \@table2display);
    $TEMPLATEg->param( "Domains" => \@table2display );

    @table2display = ();

    # convert the table into the form HTML::Template likes
    if ( not $GENERAL_CONFIG{DISABLE_GLS_LOOKUP} ) {
        foreach my $project_name ( sort keys %gls_display_projects ) {
            my $domains     = $gls_display_projects{$project_name};
            my @new_domains = ();

            foreach my $domain_key ( sort keys %{$domains} ) {
                my $domain = $domains->{$domain_key};
                my @nodes  = ();

                $logger->debug("Handling $domain_key");

                foreach my $node_key ( sort keys %{ $domain->{Nodes} } ) {
                    my $node = $domain->{Nodes}->{$node_key};

                    $logger->debug("Handling node $node_key");

                    my @addrs = ();
                    foreach my $addr ( @{ $node->{Addresses} } ) {
                        my %new_addr = ();
                        $new_addr{"address"} = $addr;
                        $new_addr{"urn"}     = $node->{"urn"} . ":port=" . $addr;
                        push @addrs, \%new_addr;
                        $logger->debug("Handling addr $addr");
                    }

                    my %new_node = ();
                    $new_node{"Addresses"} = \@addrs;
                    $new_node{"node_name"} = $node->{"node_name"};
                    push @nodes, \%new_node;
                }

                my %new_domain = ();
                $new_domain{"domain_name"} = $domain->{"domain_name"};
                $new_domain{"Nodes"}       = \@nodes;

                push @new_domains, \%new_domain;
            }

            my %new_project = ();
            $new_project{name} = $project_name;
            $new_project{"Domains"} = \@new_domains;

            push @table2display, \%new_project;
        }

        $TEMPLATEg->param( "GLSDomains" => \@table2display );
    }

    @table2display = ();

    return $TEMPLATEg->output();
}

=head2  configureNode 

   configre node  callback id=configureLink<TMPL_VAR NAME=urn>, $urn 

=cut

sub configureNode {
    my ( $id, $urn, $input_button ) = @_;
    $logger->debug("id=$id  urn=$urn input_button=$input_button");
    my ( $domain_obj, $node_obj ) = findNode( { urn => $urn } );
    if (   $id =~ /^ConfigureNode/
        && $urn
        && $domain_obj
        && $node_obj
        && $input_button eq 'Configure Node' )
    {
        return displayNode($node_obj), displayResponse(' OK ');
    }
    else {
        return '&nbsp;', displayResponse(" !!!BAD Configure Node CALL=$id or urn=$urn  or button=$input_button !!! ");
    }
}

=head2 displayNode

   prints Node view

   arguments:  
              $node - topology objects tree with node
   return:  $html - HTML string

=cut

sub displayNode {
    my $node      = shift;
    my $TEMPLATEn = HTML::Template->new( filename => $GENERAL_CONFIG{what_template}->{'Nodes'} );
    my @params    = ();
    my $node_urn  = $node->get_id;
    eval {
        push @params, { urn => $node_urn, what => 'hostName', valuen => $node->get_hostName->get_text } if $node->get_hostName;
        my $test_params = $node->get_parameters;
        foreach my $param ( @{ $test_params->get_parameter } ) {
            push @params, { urn => $node_urn, what => $param->get_name, valuen => $param->get_text }
                if $param->get_name && isParam( $param->get_name );
        }
        my $port     = $node->get_port;
        my $port_urn = $port->get_id;
        if ( $port->get_ipAddress ) {
            push @params,
                {
                urn    => $port_urn,
                what   => 'ipAddress',
                valuen => $port->get_ipAddress->get_text
                };
            my $type = $port->get_ipAddress->get_type ? $port->get_ipAddress->get_type : 'IPv4';
            push @params, { urn => $port_urn, what => 'type', valuen => $type };
        }
        my ($domain_name) = $node_urn =~ /domain\=([^\:]+)/;
        $TEMPLATEn->param( "domain_name" => $domain_name );
        $TEMPLATEn->param( "node_name"   => $node->get_name->get_text );
        $TEMPLATEn->param( "urn"         => $node_urn );
        $TEMPLATEn->param( "nodeparams"  => \@params );
    };
    if ($@) {
        $logger->logdie(" Node display failed $@ ");
    }
    return $TEMPLATEn->output();
}

=head2 updateNode

  update Domain Node info

=cut

sub updateNode {
    my ( $action, $urn, $param1 ) = @_;
    my $response        = "OK";
    my %validation_regs = (
        packetSize        => qr'^\d{1,5}$',
        count             => qr'^\d{1,4}$',
        packetInterval    => qr'^\d{1,4}$',
        measurementPeriod => qr'^\d{1,4}$',
        ttl               => qr'^\d{1,4}$',
        measurementOffset => qr'^\d{1,4}$',
        ipAddress         => qr'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$',
        type              => qr'^IPv[4|6]$',
        hostName          => qr'^[\w\.\-]+$'
    );
    my ( $node_urn, $port_name ) = $urn =~ /^(.+\:node\=[\w\-\.]+)(?:\:port\=([\w\-\.]+))?$/;
    my ( $domain_obj, $node ) = findNode( { urn => $node_urn } );

    my ($item) = $action =~ /^update\_(\w+)/;
    $logger->debug( " Will update $item  => $param1  in the $urn node: " . $node->asString );
    if ( $urn && $node && $param1 && isParam($item) ) {
        if ( $param1 =~ $validation_regs{$item} ) {
            eval {
                if ( $item =~ /ipAddress|type/ )
                {
                    my $port_obj = $node->get_port;
                    if ( $port_obj && $port_obj->get_id eq $urn ) {
                        if ( $item eq 'ipAddress' ) {
                            $port_obj->set_ipAddress->set_text($param1);
                            $port_obj->set_id( $node_urn . ":port=$param1" );
                        }
                        else {
                            $port_obj->set_ipAddress->set_type($param1);
                        }
                    }
                    else {
                        $response = " !!!!!! Port $urn  not found:$action   $param1   !!! ";
                    }
                }
                elsif ( $item eq 'hostName' ) {

                    $node->set_hostName->set_text($param1);
                }
                else {
                    my $test_params = $node->get_parameters;
                    foreach my $parameter ( @{ $test_params->get_parameter } ) {
                        $parameter->set_text($param1)
                            if ( $parameter->get_name eq $item );
                    }

                }
            };
            if ($@) {
                $logger->logdie("node update failed $@ ");
            }
        }
        else {
            $response = " !!!BAD NODE PARAM:$action  $urn  $param1    !!! ";
        }

    }
    elsif ( !$node ) {
        $response = " !!! NODE not found:$action  $urn  $param1   !!! ";
    }
    else {
        $response = " !!!BAD NODE CONFIG CALL:$action  $urn  $param1   !!! ";
    }
    if ( $response eq "OK" ) {
        storeSESSION($SESSION);
    }
    else {
        $logger->logdie("action=$action  failed: $response");
    }
    return displayGlobal(), displayResponse($response), displayNode($node);
}

=head2
 
    callback for dynamic update on "add" "remove" "update" Ajax calls
             
=cut     

sub updateGlobal {
    my ( $action, $urn, $new_name ) = @_;
    my $response = "OK";
    my ( $act, $what ) = $action =~ /^(update|remove|add)\_(domain|addr|node(?:name)?)?/;
    my ( $domain_urn, $node_name, $addr ) = $urn =~ /^(.+\:domain\=[\w\-\.]+)(?:\:node\=([\w\-\.]+))?(?:\:port\=([\w\-\.]+))?$/;
    $logger->debug("action=$action   domain_urn=$domain_urn node_name=$node_name port_address=$addr newname=$new_name");
    my $node_out = '&nbsp;';
    if ( $what =~ /domain/ ) {
        my $new_urn
            = ( $new_name =~ /^[\w\-\.]+$/ )
            ? URNBASE . ":domain=$new_name"
            : undef;

        if ( $act eq 'add' && $new_urn ) {
            my $domain_obj = $TOPOLOGY_OBJ->getDomainById($new_urn);
            if ($domain_obj) {
                $response = " !!!ADD DOMAIN FAILED:  DOMAIN $new_name EXISTS !!!";
            }
            else {
                $TOPOLOGY_OBJ->addDomain( Domain->new( { id => $new_urn } ) );
            }
        }
        elsif ( $act eq 'remove' && $domain_urn ) {
            $TOPOLOGY_OBJ->removeDomainById($urn);
        }
        elsif ( $act eq 'update' && $domain_urn && $new_urn ) {
            my $domain_obj = $TOPOLOGY_OBJ->getDomainById($urn);
            $TOPOLOGY_OBJ->removeDomainById($urn);
            $domain_obj = updateDomainId( $domain_obj, $new_urn );
            $TOPOLOGY_OBJ->addDomain($domain_obj);
        }
        else {
            $response = "!!!BAD CALL PARAM:$action urn=$urn  callParam=$new_name    !!!";
        }
    }
    elsif ( $what =~ /node/ && $domain_urn ) {
        my $domain_obj = $TOPOLOGY_OBJ->getDomainById($domain_urn);

        if ($domain_obj) {
            my $node_obj = $urn =~ /\:node/ ? $domain_obj->getNodeById($urn) : undef;
            $TOPOLOGY_OBJ->removeDomainById($domain_urn);
            my $new_urn
                = ( $new_name =~ /^[\w\-\.]+$/ )
                ? $domain_urn . ":node=$new_name"
                : undef;
            $logger->debug("action=$action - new_urn=$new_urn");
            if ( $act eq 'add' && $new_urn ) {
	        my $ip_resolved; '255.255.255.255';
                eval {
		    ($ip_resolved) = resolve_address($new_name);
		    $ip_resolved = '255.255.255.255' unless $ip_resolved;
                    $node_obj = Node->new(
                        {
                            id   => $new_urn,
                            name => Name->new( { type => 'string', text => $new_name } ),
                            hostName => HostName->new( { text => $new_name } ),
                            port     => Port->new(
                                {
                                    xml => "<nmtl3:port xmlns:nmtl3=\"http://ogf.org/schema/network/topology/l3/20070707/\" id=\"$new_urn:port=255.255.255.255\">
                      <nmtl3:ipAddress type=\"IPv4\">$ip_resolved</nmtl3:ipAddress>
                   </nmtl3:port>"
                                }
                            ),
                            parameters => Parameters->new(
                                {
                                    xml => '<nmwg:parameters xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/" id="paramid1">
                              <nmwg:parameter name="packetSize">1000</nmwg:parameter>
                         <nmwg:parameter name="count">10</nmwg:parameter>
                              <nmwg:parameter name="packetInterval">1</nmwg:parameter>
                         <nmwg:parameter name="ttl">255</nmwg:parameter> 
                              <nmwg:parameter name="measurementPeriod">60</nmwg:parameter>  
                         <nmwg:parameter name="measurementOffset">0</nmwg:parameter> 
                              </nmwg:parameters>'
                                }
                            )
                        }
                    );
                    $logger->debug( " new node will be added " . Dumper $node_obj->asString );
                    $domain_obj->addNode($node_obj);

                    $node_out = displayNode($node_obj);
                };
                if ($@) {
                    $logger->logdie(" New node  failed: $@");
                }
                else {
                    $logger->debug( " Added Domain :\n" . Dumper $domain_obj);
                }
            }
            elsif ( $act eq 'remove' && $node_name ) {
                $domain_obj->removeNodeById($urn);
                $logger->debug( " Removed Domain :\n" . Dumper $domain_obj);
            }
            elsif ( $act eq 'update' && $new_urn ) {
                eval {
                    $domain_obj->removeNodeById($urn);
                    $node_obj = updateNodeId( $node_obj, $new_urn );
                    $domain_obj->addNode($node_obj);
                    $node_out = displayNode($node_obj);
                };
                if ($@) {
                    $logger->logdie("Update global node failed $@  ");
                }
            }
            $TOPOLOGY_OBJ->addDomain($domain_obj);

        }
        else {
            $response = " !!!ADD NODE FAILED:  DOMAIN  $urn not found !!!";
        }
    }
    elsif ( $what =~ /addr/ && $node_name && $domain_urn ) {
        my $domain_obj = $TOPOLOGY_OBJ->getDomainById($domain_urn);

        if ( not $domain_obj ) {
            $TOPOLOGY_OBJ->addDomain( Domain->new( { id => $domain_urn } ) );
            $domain_obj = $TOPOLOGY_OBJ->getDomainById($domain_urn);
        }

        my $node_urn = $domain_urn . ":node=" . $node_name;
        my $node_obj = $domain_obj->getNodeById($urn);
        if ( not $node_obj ) {
            eval {
                $node_obj = Node->new(
                    {
                        id   => $node_urn,
                        name => Name->new( { type => 'string', text => $node_name } ),
                        hostName => HostName->new( { text => $node_name } ),
                        port     => Port->new(
                            {
                                xml => "<nmtl3:port xmlns:nmtl3=\"http://ogf.org/schema/network/topology/l3/20070707/\" id=\"$urn\">
                  <nmtl3:ipAddress type=\"IPv4\">$addr</nmtl3:ipAddress>
               </nmtl3:port>"
                            }
                        ),
                        parameters => Parameters->new(
                            {
                                xml => '<nmwg:parameters xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/" id="paramid1">
                          <nmwg:parameter name="packetSize">1000</nmwg:parameter>
                     <nmwg:parameter name="count">10</nmwg:parameter>
                          <nmwg:parameter name="packetInterval">1</nmwg:parameter>
                     <nmwg:parameter name="ttl">255</nmwg:parameter> 
                          <nmwg:parameter name="measurementPeriod">60</nmwg:parameter>  
                     <nmwg:parameter name="measurementOffset">0</nmwg:parameter> 
                          </nmwg:parameters>'
                            }
                        )
                    }
                );
                $logger->debug( " new node will be added " . Dumper $node_obj->asString );
                $domain_obj->addNode($node_obj);

                $node_out = displayNode($node_obj);
            };
            if ($@) {
                $logger->logdie(" New node  failed: $@");
            }
            else {
                $logger->debug( " Added Domain :\n" . Dumper $domain_obj);
            }
        }
        else {
            $response = "!!! Already Pinging Host $node_name !!!";
        }
    }
    else {
        $response = "!!! MISSED PARAM:$action  urn=$urn   callParam=$new_name  !!!";
    }
    if ( $response =~ /^OK/ ) {
        storeSESSION($SESSION);
    }
    else {
        $logger->logdie("action=$action  failed: $response");
    }
    return displayGlobal(), displayResponse($response), $node_out;

}

=head2 updateNodeId 

  updates   node  id , port   id 

=cut

sub updateNodeId {
    my ( $node_obj, $new_node_urn ) = @_;

    my ($node_part) = $new_node_urn =~ /node\=([^\:]+)/;
    $node_obj->set_name( Name->new( { type => 'string', text => $node_part } ) );
    $node_obj->set_id($new_node_urn);
    my $port    = $node_obj->get_port;
    my $port_id = $port->get_id;
    $port_id =~ s/node\=([^\:]+)\:/node\=$node_part\:/;
    $port->set_id($port_id);
    ##$node_obj->port($port);
    return $node_obj;
}

=head2 updateDomainId 

  updates domain id and everything inside of domain element ( nodes id , ports  id )

=cut

sub updateDomainId {
    my ( $domain_obj, $new_domain_urn ) = @_;
    my ($domain_part) = $new_domain_urn =~ /domain\=([^\:]+)/;
    $domain_obj->set_id($new_domain_urn);
    foreach my $in_node ( @{ $domain_obj->get_node } ) {
        my $node_id = $in_node->get_id;
        $node_id =~ s/domain\=([^\:]+)\:/domain\=$domain_part\:/;
        $in_node->set_id($node_id);
        my $port    = $in_node->get_port;
        my $port_id = $port->get_id;
        $port_id =~ s/domain\=([^\:]+)\:/domain\=$domain_part\:/;
        $port->set_id($port_id);
    }
    return $domain_obj;
}

=head2 findNode

   find node by domain urn and nodename or urn, returns $domain, $node objects pari
   
=cut

sub findNode {
    my ($params) = @_;
    if ( $params && ( ref $params ne 'HASH' || !( $params->{urn} || ( $params->{domain} && $params->{name} ) ) ) ) {
        $logger->logdie(" Failed, only hashref parmaeter is accepted and 'domain' and 'urn' or 'name' must be supplied");
    }
    my ( $domain_query, $node_query ) = ( $params->{domain}, $params->{name} );
    if ( $params->{urn} ) {
        ( $domain_query, $node_query ) = $params->{urn} =~ /^.+\:domain\=([^\:]+)\:node\=(.+)$/;
    }
    foreach my $domain ( @{ $TOPOLOGY_OBJ->get_domain } ) {
        my ($domain_part) = $domain->get_id =~ /domain\=([^\:]+)$/;
        if ( $domain_part eq $domain_query ) {
            foreach my $node ( @{ $domain->get_node } ) {
                my ($node_part) = $node->get_id =~ /node\=([^\:]+)$/;
                $logger->debug(" quering for ::  $domain_query :: $node_query ---> $domain_part :: $node_part ");
                if ( $node_part eq $node_query ) {
                    $logger->debug(" Found node");
                    return ( $domain, $node );
                }
            }
            return;
        }
    }
    return;
}

=head2 loadConfig
 
       load config and return it as hash ref
 
=cut

sub loadConfig {

    my $conf_obj = new Config::General(
        -ConfigFile      => $CONFIG_FILE,
        -AutoTrue        => '',
        -InterPolateVars => '1',
        -StoreDelimiter  => '='
    );
    my %GENERAL_CONFIG = $conf_obj->getall;
    $logger->logdie("Problem with parsing config file: $CONFIG_FILE ") unless %GENERAL_CONFIG;
    if ( not $GENERAL_CONFIG{LOGGER_CONF} ) {
        $GENERAL_CONFIG{LOGGER_CONF} = "etc/logger.conf";
    }

    if ( $GENERAL_CONFIG{LOGGER_CONF} !~ /^\// ) {
	$GENERAL_CONFIG{LOGGER_CONF} = BASEDIR . "/" . $GENERAL_CONFIG{LOGGER_CONF};
    }

    foreach my $templ (qw/header footer Domains Nodes/) { 
	if ( $GENERAL_CONFIG{what_template}->{$templ} !~ /^\// ) {
            $GENERAL_CONFIG{what_template}->{$templ} = BASEDIR . "/" . $GENERAL_CONFIG{what_template}->{$templ};
	}
    }

    if ( $GENERAL_CONFIG{LANDMARKS} !~ /^\// ) {
	$GENERAL_CONFIG{LANDMARKS} = BASEDIR . "/" . $GENERAL_CONFIG{LANDMARKS};
    }

    if ( $GENERAL_CONFIG{PROJECT} ) {
	if ( ref( $GENERAL_CONFIG{PROJECT} ) ne "ARRAY" ) {
            my @arr = ();
            push @arr, $GENERAL_CONFIG{PROJECT};
            $GENERAL_CONFIG{PROJECT} = \@arr;
	}
    }

    # XXX: The following are meant for the NPToolkit where projects are defined as
    # 'site_project' instead of PROJECT and the name for the site is 'site_name',
    # not MYDOMAIN. Longer term, a common structure for projects and names should
    # be done.

    if ( $GENERAL_CONFIG{site_project} ) {
	if ( ref( $GENERAL_CONFIG{site_project} ) ne "ARRAY" ) {
            my @arr = ();
            push @arr, $GENERAL_CONFIG{site_project};
            $GENERAL_CONFIG{site_project} = \@arr;
	}
    }

    # move everything from 'site_project' into 'PROJECT'
    if ( $GENERAL_CONFIG{site_project} ) {
	my %tmp = ();

	if ( $GENERAL_CONFIG{PROJECT} ) {
            foreach my $project ( @{ $GENERAL_CONFIG{PROJECT} } ) {
        	$tmp{$project} = 1;
            }
	}

	foreach my $project ( @{ $GENERAL_CONFIG{site_project} } ) {
            $tmp{$project} = 1;
	}

	my @arr = keys %tmp;
	$GENERAL_CONFIG{PROJECT} = \@arr;
    }

    # set "MYDOMAIN" if it doesn't exist but "site_name" does.
    if ( not $GENERAL_CONFIG{MYDOMAIN} and $GENERAL_CONFIG{site_name} ) {
	$GENERAL_CONFIG{MYDOMAIN} = $GENERAL_CONFIG{site_name};
    }   
    $GENERAL_CONFIG{EVENTTYPE} = perfSONAR_PS::Datatypes::EventTypes->new();
    return \%GENERAL_CONFIG;
}

1;

