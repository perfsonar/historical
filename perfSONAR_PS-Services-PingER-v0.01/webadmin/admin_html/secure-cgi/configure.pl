#!/usr/local/bin/perl -w

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

=cut

use strict;
use FindBin qw($Bin);
use lib "$Bin/../../../lib";
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
 
use aliased 'perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::pingertopo::Topology';
use aliased 'perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::pingertopo::Topology::Domain';
use aliased 'perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::pingertopo::Topology::Domain::Node';
use aliased 'perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::nmtb::Topology::Domain::Node::Name';
use aliased 'perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::nmwg::Topology::Domain::Node::Parameters';
use aliased 'perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::nmwg::Topology::Domain::Node::Parameters::Parameter';
use aliased 'perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::nmtl3::Topology::Domain::Node::Port';
use constant URNBASE => 'urn:ogf:network';

use constant BASEDIR => "$Bin/../..";
#
 
Log::Log4perl->init( BASEDIR . "/etc/logger.conf" );
our $CONFIG_FILE = BASEDIR . '/etc/GeneralSystem.conf'; 
my $logger      = get_logger("configure");

$ENV{PATH} = '/usr/bin:/usr/local/bin:/bin';
croak("Please fix your deployment, basedir is not what pointing to the webadmin root: " . BASEDIR) unless -d BASEDIR . "/etc";

our %GENERAL_CONFIG = %{ loadConfig() };
   
#
#   although this is  the CGI script, but there is no HTML here
#   all html layout is defined by templates,   style defined by CSS
#   and interactive dynamic features exposed by javascript/Ajax
#
my $cgi     = CGI->new();
my $SESSION = new CGI::Session( "driver:File;serializer:Storable",
                                $cgi, 
			        { Directory => '/tmp' } 
			      );    ## to keep our session
my $COOKIE = $cgi->cookie( 'CGISESSID' => $SESSION->id);    ########   get cookie
$COOKIE->path('/secure-cgi/');
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
my ($TOPOLOGY_OBJ,$LANDMARKS_CONFIG);
###check if we saved previous session
unless ($SESSION && !$SESSION->is_expired &&  $SESSION->param("DOMAINS")) {
    fromFile();
    storeSESSION($SESSION);
}
else {
    $LANDMARKS_CONFIG = $SESSION->param("DOMAINS");
    $TOPOLOGY_OBJ =  Topology->new( { xml => $LANDMARKS_CONFIG } );

}
my $TEMPLATE_HEADER =
  HTML::Template->new( filename => BASEDIR .  $GENERAL_CONFIG{what_template}->{header} );
$TEMPLATE_HEADER->param(
    'Title' => "$GENERAL_CONFIG{MYDOMAIN} Pinger MP Configuration Manager" );
my $TEMPLATE_FOOTER =
  HTML::Template->new( filename => BASEDIR . $GENERAL_CONFIG{what_template}->{footer} );
######## global view
my $myhtml =
    $TEMPLATE_HEADER->output()
  . displayGlobal()
  . $TEMPLATE_FOOTER->output();    ##### get html
                                   #$ajax->DEBUG($DEBUG);
                                   #$ajax->JSDEBUG($DEBUG);
print $ajax->build_html( $cgi, $myhtml, { '-Expires' => '1d', '-cookie' => $COOKIE } );

=head2 isParam 

  returns true if argument string among supported pigner test parameters
  otherwise returns undef

=cut

sub isParam {
    my ($name) = @_;
    return 1  if $name =~ /^(packetSize|count|packetInterval|measurementPeriod|ttl|measurementOffset|ipAddress|type|hostName)/;
    return;
}

=head2 fromFile

   get landmarks from file into the object
   returns 0 if ok or dies

=cut

sub fromFile {
    my $file = BASEDIR . $GENERAL_CONFIG{LANDMARKS};
    eval {
        local ( $/, *FH );
        open( FH, $file ) or  die " Failed to open landmarks $file";
        my $text = <FH>;
        $TOPOLOGY_OBJ =   Topology->new( { xml => $text } );
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
    $sess->param( "DOMAINS", $TOPOLOGY_OBJ->asString );
}

=head2  saveConfigs

  update XML files ( Template for MP and    restart MP daemon)

=cut   

sub saveConfigs {
    my ($input) = shift;
    return displayGlobal(), "Wrong Request"
      unless $input && $input =~ /^Save\ MP landmarks XML$/;
    my $tmp_file = "/tmp/temp_LANDMARKS." . $SESSION->id;
    my $fd  = new IO::File(">$tmp_file")  or $logger->logdie( "Failed to open file $tmp_file" . $! );
    eval {
        print $fd $TOPOLOGY_OBJ->asString;
    };
    if($@) {
       $logger->logdie( "Failed to print $@"  );
    }
    
    $fd->close;
    move( $tmp_file, BASEDIR . $GENERAL_CONFIG{LANDMARKS} ) or  $logger->logdie( "Failed to replace:" .  BASEDIR . $GENERAL_CONFIG{LANDMARKS} . " due - $! "); ;
    return displayGlobal(), displayResponse("MP landmarks XML file was Saved"),  '&nbsp;';
}

=head2  resetit

   reset  web interface

=cut

sub resetit {
    my ($input) = shift;
    return displayGlobal(), "Wrong Request" unless $input && $input eq 'Reset';
    
    storeSESSION($SESSION) unless fromFile();
    return displayGlobal(), displayResponse(" MP landmarks XML configuration was reset "), '&nbsp;';

}

=head2 displayGlobal

   prints global view

   arguments:  
              $TOPOLOGY_OBJ - topology objects tree with domains to be monitored from XML template file
             
   return:  $html - HTML string

=cut

sub displayGlobal {
    my $TEMPLATEg = HTML::Template->new(filename => BASEDIR . $GENERAL_CONFIG{what_template}->{'Domains'});
    my @table2display = ();
    my %domain_names  = ();
    eval {
	foreach my $domain ( @{ $TOPOLOGY_OBJ->get_domain } ) {
            my $urn = $domain->get_id;
            if ($urn) {
        	my ($dname) = $urn =~ /\:domain\=([^\:]+)/;
        	my $nodes = $domain->get_node;
        	my @nodenames = ();
        	foreach my $node ( @{$nodes} ) {
                    push @nodenames,
                      { node_name => $node->get_name->get_text, urn => $node->get_id }
                      if $node->get_name;
        	}
        	$domain_names{$dname} = {
                     domain_name  => $dname,
                     urn          => $domain->get_id,
                     Nodes        => \@nodenames
        	};
            }
	}
    };
    if($@) {
        $logger->logdie("Display global failed $@ ");
    }
    foreach my $domain ( sort keys %domain_names ) {
        push @table2display, $domain_names{$domain};
    }
    ###$logger->debug(" ------------------- Domains: " . Dumper  \@table2display);
    $TEMPLATEg->param( "Domains" => \@table2display );
    @table2display = ();

    return $TEMPLATEg->output();
}

=head2  configureNode 

   configre node  callback id=configureLink<TMPL_VAR NAME=urn>, $urn 

=cut

sub configureNode {
    my ( $id, $urn, $input_button ) = @_;
    $logger->debug("id=$id  urn=$urn input_button=$input_button"); 
    my ($domain_obj, $node_obj) = findNode( { urn => $urn } );
    if (   $id =~ /^ConfigureNode/
        && $urn
	&& $domain_obj
        && $node_obj
        && $input_button eq 'Configure Node')
    {
        return displayNode($node_obj), displayResponse(' OK ');
    }
    else {
        return '&nbsp;',displayResponse(" !!!BAD Configure Node CALL=$id or urn=$urn  or button=$input_button !!! ");
    }
}

=head2 displayNode

   prints Node view

   arguments:  
              $node - topology objects tree with node
   return:  $html - HTML string

=cut

sub displayNode {
    my $node = shift;
    my $TEMPLATEn =  HTML::Template->new(filename => BASEDIR . $GENERAL_CONFIG{what_template}->{'Nodes'} );
    my @params = ();
    my $node_urn = $node->get_id;
    eval {
	push @params, { urn => $node_urn, what => 'hostName', valuen => $node->get_hostName->get_text} if $node->get_hostName;
	my $test_params = $node->get_parameters;
	foreach my $param ( @{ $test_params->get_parameter } ) {
            push @params, { urn => $node_urn, what => $param->get_name, valuen => $param->get_text}
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
    if($@) {
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
    my ( $node_urn, $port_name ) =  $urn =~ /^(.+\:node\=[\w\-\.]+)(?:\:port\=([\w\-\.]+))?$/;
    my ($domain_obj, $node) = findNode( { urn => $node_urn } );
   
    my ($item) = $action =~ /^update\_(\w+)/;
    $logger->debug(" Will update $item  => $param1  in the $urn node: " . $node->asString );  
    if ( $urn && $node && $param1 && isParam($item) )    {  
          if ( $param1 =~  $validation_regs{$item} ) {
        	eval{
		  if ( $item =~ /ipAddress|type/ ) {
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
                	  $response =
                            " !!!!!! Port $urn  not found:$action   $param1   !!! ";
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
	      if($@) {
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
    } else {
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
    my ( $act, $what ) =
      $action =~ /^(update|remove|add)\_(domain|node(?:name)?)?/;
    my ( $domain_urn, $node_name ) =
      $urn =~ /^(.+\:domain\=[\w\-\.]+)(?:\:node\=([\w\-\.]+))?$/;
    $logger->debug("action=$action   domain_urn=$domain_urn node_name=$node_name newname=$new_name");
    my $node_out = '&nbsp;';
    if ( $what =~ /domain/ ) {
	my $new_urn =
	  ( $new_name =~ /^[\w\-\.]+$/ )
	  ? URNBASE . ":domain=$new_name"
	  : undef;

	if ( $act eq 'add' && $new_urn ) {
	    my $domain_obj = $TOPOLOGY_OBJ->getDomainById($new_urn);
	    if ($domain_obj) {
		$response =
		  " !!!ADD DOMAIN FAILED:  DOMAIN $new_name EXISTS !!!";
	    }
	    else {
		$TOPOLOGY_OBJ->addDomain( Domain->new({ id => $new_urn }) );
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
	    my $node_obj = $urn =~ /\:node/?$domain_obj->getNodeById($urn):undef;
	    $TOPOLOGY_OBJ->removeDomainById($domain_urn);
	    my $new_urn =
	      ( $new_name =~ /^[\w\-\.]+$/ )
	      ? $domain_urn . ":node=$new_name"
	      : undef;
	    $logger->debug("action=$action - new_urn=$new_urn");
	    if ( $act eq 'add' && $new_urn ) {
        	eval {
		    $node_obj =  Node->new(
				{
				 id => $new_urn,
        			 name =>  Name->new(  { type => 'string', text => $new_name } ),
        			 hostName =>  HostName->new( { text => $new_name } ),	
				 port =>  Port->new(
					     { xml =>
						"<nmtl3:port xmlns:nmtl3=\"http://ogf.org/schema/network/topology/l3/20070707/\" id=\"$new_urn:port=255.255.255.255\">
						    <nmtl3:ipAddress type=\"IPv4\">255.255.255.255</nmtl3:ipAddress>
						 </nmtl3:port>"
					     }
				       ),
				parameters =>  Parameters->new(
					    {  xml => '<nmwg:parameters xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/" id="paramid1">
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
        	   $logger->debug(" new node will be added " . Dumper $node_obj->asString);
		   $domain_obj->addNode($node_obj);
        	
		   $node_out = displayNode($node_obj);
        	};
        	if($@) {
        	   $logger->logdie(" New node  failed: $@");
        	} else {
		   $logger->debug(" Added Domain :\n" . Dumper $domain_obj);
        	}
	    }
	    elsif ( $act eq 'remove' && $node_name ) {
		$domain_obj->removeNodeById($urn);
        	$logger->debug(" Removed Domain :\n" . Dumper $domain_obj);
	    }
	    elsif ( $act eq 'update' && $new_urn ) {
		eval {
		    $domain_obj->removeNodeById($urn);
		    $node_obj = updateNodeId( $node_obj, $new_urn );
		    $domain_obj->addNode($node_obj);
		    $node_out = displayNode($node_obj);
        	};
        	if($@) {
        	   $logger->logdie("Update global node failed $@  ");
        	}
	    }
	    $TOPOLOGY_OBJ->addDomain($domain_obj);

	}
	else {
	    $response = " !!!ADD NODE FAILED:  DOMAIN  $urn not found !!!";
	}

    }
    else {
	$response =
	  "!!! MISSED PARAM:$action  urn=$urn	callParam=$new_name  !!!";
    }
    if ( $response =~ /^OK/ ) {
	storeSESSION($SESSION);
    } else {
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
    $node_obj->set_name( Name->new({ type => 'string', text => $node_part }) );
    $node_obj->set_id($new_node_urn);
    my $port	= $node_obj->get_port;
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
    if ($params && ( ref $params ne 'HASH' || !( $params->{urn} || ( $params->{domain} && $params->{name} ) ))){
	$logger->logdie(" Failed, only hashref parmaeter is accepted and 'domain' and 'urn' or 'name' must be supplied");
    }
    my ( $domain_query, $node_query ) = ( $params->{domain}, $params->{name} );
    if ( $params->{urn} ) {
	( $domain_query, $node_query ) =  $params->{urn} =~ /^.+\:domain\=([^\:]+)\:node\=(.+)$/;
    }
    foreach my $domain ( @{ $TOPOLOGY_OBJ->get_domain } ) {
	my ($domain_part) = $domain->get_id =~ /domain\=([^\:]+)$/;       
	if ( $domain_part eq $domain_query ) {
	   foreach my $node ( @{ $domain->get_node } ) {
	       my ($node_part) = $node->get_id =~ /node\=([^\:]+)$/;
               $logger->debug(" quering for ::  $domain_query :: $node_query ---> $domain_part :: $node_part ");	
		if ( $node_part eq $node_query ) {
		    $logger->debug(" Found node");
		    return ($domain,$node);
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
   
    my $conf_obj =  new Config::General(-ConfigFile =>   $CONFIG_FILE, 
                                        -AutoTrue => '',
				        -InterPolateVars => '1',
                                        -StoreDelimiter => '=');
    my %GENERAL_CONFIG  = $conf_obj->getall; 
    $logger->logdie("Problem with parsing config file: $CONFIG_FILE ") unless %GENERAL_CONFIG;
    return \%GENERAL_CONFIG; 
}

 
1;

