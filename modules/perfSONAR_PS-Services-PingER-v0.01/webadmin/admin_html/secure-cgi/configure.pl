#!/usr/local/bin/perl -w

=head1  NAME  configure.pl
     
 

=head1 DESCRIPTION

    this is CGI::Ajax based script for pinger landmarks webadmin configuration
  
=head1 SYNOPSIS
     
      pinger monitoring configuration  webinterface
     first virtual page is to see domains and add/remove/update them,
     second virtual page is to add/remove/update nodes  of the particular domain
     third virtual page is to configure ping test parameters for monitoring of the paricular node/domain
     every page is Ajaxed, means its interactively updates webpage while you are entering and its not a multi-page 
     use "Save" button to save new config in file ( it will effectively update landmarks XML   )
     
   
	     
=head1 AUTHORS

     Maxim Grigoriev, maxim@fnal.gov   2007	     

=cut
 
use strict;
use lib  ('/home/netadmin/LHCOPN/perfSONAR-PS/branches/pinger/perfSONAR-PS-PingER-1.0/lib');
use CGI qw/:standard/;
use CGI::Carp qw(fatalsToBrowser); 
use Data::Dumper;
use CGI::Session;
use CGI::Ajax;
use HTML::Template; 
use IO::File;
use File::Copy;
use Storable qw(lock_retrieve lock_store);
#
#    configuration parameters are in the next packages
#
BEGIN { 
        use constant BASEDIR => '/home/netadmin/LHCOPN/perfSONAR-PS/branches/pinger/perfSONAR-PS-PingER-1.0/webadmin';
        use Log::Log4perl qw(get_logger :levels);   
        Log::Log4perl->init(BASEDIR . "/etc/logger.conf"); 
        our $CONFIG_FILE  = BASEDIR . '/etc/GeneralSystem.conf';
        use perfSONAR_PS::WebAdmin::Config qw(&loadConfig $CONFIG_FILE $debug);
      };

use perfSONAR_PS::Datatypes::v2_0::pingertopo::Topology;
use perfSONAR_PS::Datatypes::v2_0::nmtb::Topology::Domain;
use perfSONAR_PS::Datatypes::v2_0::nmtb::Topology::Domain::Node; 
use perfSONAR_PS::Datatypes::v2_0::nmtb::Topology::Domain::Node::Name;
use perfSONAR_PS::Datatypes::v2_0::pingertopo::Topology::Domain::Node::Test;
use perfSONAR_PS::Datatypes::v2_0::nmtl3::Topology::Domain::Node::Port;
use constant  URNBASE => 'urn:ogf:network';
 
#
#
$debug = 1; 


$ENV{PATH} = '/usr/bin:/usr/local/bin:/bin';
our %GENERAL_CONFIG = %{loadConfig()};
my $this_script = "$GENERAL_CONFIG{admin_server}/secure-cgi/configure.pl";
my $logger = get_logger("configure");
$logger->level($DEBUG) if $debug;
#
#   although this is  the CGI script, but there is no HTML here
#   all html layout is defined by templates,   style defined by CSS
#   and interactive dynamic features exposed by javascript/Ajax
#   
my $cgi =   CGI->new(); 
my $SESSION = new CGI::Session("driver:File;serializer:Storable",  $cgi, {Directory => '/tmp'}); ## to keep our session
my $COOKIE =   $cgi->cookie( 'CGISESSID' )?$cgi->cookie( 'CGISESSID' ):$cgi->cookie( 'CGISESSID' => $SESSION->id);    ########   get cookie
#### to make it interactive ( registering perl calls as javascript functions)
##                           
my $ajax = CGI::Ajax->new(   'updateGlobal' => \&updateGlobal, 'updateNode' => \&updateNode, 'configureNode' => \&configureNode,
			     'saveConfigs' => \&saveConfigs , "resetit" => \&resetit ); 
			     
#### These our global vars, there is no way to escape them since CGI::Ajax doesnt support structured data ( JSON ?)
#
my $TOPOLOGY_OBJ = undef;
my $LANDMARKS_CONFIG = $SESSION->param( "DOMAINS" );
###check if we saved previous session
unless( $LANDMARKS_CONFIG ) {
      $logger->debug(" .........Session expired...............  $COOKIE"  );
      $SESSION->delete();
      $SESSION = new CGI::Session("driver:File;serializer:Storable", undef , {Directory => '/tmp'});
      $COOKIE = $cgi->cookie(  'CGISESSID' => $SESSION->id);  
      storeSESSION($SESSION) unless fromFile(); 
}   else {
    $TOPOLOGY_OBJ =  perfSONAR_PS::Datatypes::v2_0::pingertopo::Topology->new({xml =>  $LANDMARKS_CONFIG });
    
}
my $TEMPLATE_HEADER  = HTML::Template->new(filename => $GENERAL_CONFIG{what_template}->{header});
$TEMPLATE_HEADER->param( 'Title' => "$GENERAL_CONFIG{MYDOMAIN} Pinger MP Configuration Manager"); 
my $TEMPLATE_FOOTER  = HTML::Template->new(filename => $GENERAL_CONFIG{what_template}->{footer});
######## global view
my $myhtml = $TEMPLATE_HEADER->output() .   displayGlobal() . $TEMPLATE_FOOTER->output() ;  ##### get html
 # $ajax->DEBUG($debug);
 # $ajax->JSDEBUG($debug);
print $ajax->build_html( $cgi,  $myhtml, {'-Expires'=>'1d',   '-cookie' =>  $COOKIE   });

=head2 fromFile

   get landmarks from file into the object
   returns 0 if ok or dies

=cut

sub fromFile{
      
    my $file = $GENERAL_CONFIG{LANDMARKS};
    eval {
        local( $/, *FH ) ;
        open( FH, $file ) or  $logger->logdie(" Failed to load landmarks $file");
        my $text = <FH>;
        $TOPOLOGY_OBJ = perfSONAR_PS::Datatypes::v2_0::pingertopo::Topology->new({xml => $text});
	$LANDMARKS_CONFIG = $text;	 
	close FH;
    };
    if($@) {
        $logger->error(" Failed to load landmarks $file into object" . $@);
	return 1;
    } 
    return 0;
}

=head2 displayResponse

=cut

sub displayResponse {
    my  $message  = shift;
    return "Last Action Status: " . $message;

} 

=head2  storeSESSION

    store current session params

=cut

sub storeSESSION {
    my ($sess ) = @_;   
    $sess->param("DOMAINS", $TOPOLOGY_OBJ->asString);   
} 
 
=head2  saveConfigs

  update XML files ( Template for MP and    restart MP daemon)

=cut   

sub saveConfigs {
    my($input) = shift;
    return  displayGlobal(),"Wrong Request" unless $input && $input =~ /^Save\ MP landmarks XML$/;      
    my $tmp_file = "/tmp/temp_LANDMARKS."  . $SESSION ;
    my $fd = new IO::File(">$tmp_file")  or croak("Failed to open file $tmp_file" . $!);
    print $fd $TOPOLOGY_OBJ->asString;
    $fd->close;
    move($tmp_file,  $GENERAL_CONFIG{LANDMARKS});       
     ### manage_proc('ServerDaemon', 1);
     ###  sleep  3;
     ###   eval {
    ###       system($server_MP) 
     ###   };  
      ###  if($@) { 
     ###       return  ("!!! Failed to start MP Daemon  " . $@);
     ###   } elsif( !manage_proc('ServerDaemon', undef)) {
     ###       return  ("!!! Daemon seems to be started but there is no PID "); 
     ###   } else {
    return  displayGlobal(),displayResponse("MP landmarks XML file was Saved"),'&nbsp;';        
}

=head2  resetit

   reset  web interface

=cut

sub resetit {
    my($input) = shift;
    return  displayGlobal(),"Wrong Request" unless $input && $input  eq 'Reset';
    storeSESSION($SESSION) unless fromFile(); 
    return  displayGlobal(),displayResponse(" MP landmarks XML configuration was reset "),'&nbsp;';
        
}

=head2 displayGlobal

   prints global view

   arguments:  
              $TOPOLOGY_OBJ - topology objects tree with domains to be monitored from XML template file
             
   return:  $html - HTML string

=cut

sub displayGlobal {
    my $TEMPLATEg  = HTML::Template->new(filename =>  $GENERAL_CONFIG{what_template}->{'Domains'}) ;
    my @table2display = (); 
    my %domain_names =();
  #####  map {$_->[0]} sort {$a->[1] cmp $b->[1] }  map {[$_, $TOPOLOGY_OBJ->{$_ }{globalname}]} keys %{$TOPOLOGY_OBJ}) 
   foreach my $domain (@{$TOPOLOGY_OBJ->domain}) { 
     my $urn =   $domain->id ;
     if($urn) { 
        my ($dname) = $urn =~ /\:domain\=([^\:]+)/;
	my $nodes = $domain->node;
	my @nodenames = ();
	foreach my $node (@{$nodes}) {
	    push @nodenames, { node_name => $node->name->text, urn => $node->id} if  $node->name;
	}
         $domain_names{$dname} =  {"domain_name" =>   $dname, "urn" => $domain->id, Nodes =>   \@nodenames};
      }
   }     
   
   foreach my $domain  (sort keys %domain_names ) {
       push  @table2display, $domain_names{$domain}; 
   } 
   ###$logger->debug(" ------------------- Domains: " . Dumper  \@table2display);      
   $TEMPLATEg->param("Domains" => \@table2display);
   @table2display = (); 
   
  return $TEMPLATEg->output();
}

=head2  configureNode 

   configre node  callback id=configureLink<TMPL_VAR NAME=urn>, $urn 

=cut

sub configureNode {
  my ($id, $urn, $input_button  ) = @_;
  my $node_obj =  findNode({urn => $urn}); 
  if($id =~ /^ConfigureNode/ && $urn &&  $node_obj &&  $input_button eq 'Configure Node') { 
     return displayNode( $node_obj ), displayResponse(' OK ');
  } else {
     return  '&nbsp;', displayResponse(" !!!BAD Configure Node CALL=$id or urn=$urn  or button=$input_button !!! ");
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
    my $TEMPLATEn  = HTML::Template->new(filename =>  $GENERAL_CONFIG{what_template}->{'Nodes'}) ;
    my @params = ();
	    my $node_urn = $node->id;
	     
	    push @params,  {urn =>  $node_urn , what => 'hostName',  valuen => $node->hostName} if $node->hostName;
	    my $test_params = $node->test; 
	    push @params,  {urn =>  $node_urn , what =>  'count',  
	                      valuen =>  $test_params->count } if $test_params->count; 
	    push @params,  {urn =>  $node_urn , what =>  'interval',  
	                      valuen =>  $test_params->interval } if $test_params->interval; 
	    push @params,  {urn =>  $node_urn , what =>  'period',  
	                      valuen =>  $test_params->period } if $test_params->period; 
            push @params,  {urn =>  $node_urn , what =>  'ttl',  
	                      valuen =>  $test_params->ttl } if $test_params->ttl; 
	    push @params,  {urn =>  $node_urn , what =>  'offset',  
	                      valuen =>  $test_params->offset } if $test_params->offset; 	      
	    push @params,  {urn =>  $node_urn , what =>  'packetSize',  
	                      valuen =>  $test_params->packetSize} if $test_params->packetSize; 
	    my $port=$node->port;
	    my $port_urn = $port->id;
	    if($port->ipAddress) {
	          push @params,  {urn =>  $port_urn , what => 'ipAddress',  valuen => $port->ipAddress->text};
		  my $type =  $port->ipAddress->type?$port->ipAddress->type:'IPv4';
		  push @params,  {urn =>   $port_urn , what => 'type',  valuen => $type};
	    }
   ###$logger->debug(" ------------------- Domains: " . Dumper  \@table2display); 
   my ($domain_name) = $node_urn =~ /domain\=([^\:]+)/;
   $TEMPLATEn->param("domain_name" =>  $domain_name ); 	   
   $TEMPLATEn->param("node_name" =>  $node->name->text); 
   $TEMPLATEn->param("urn" => $node_urn);  
   $TEMPLATEn->param("nodeparams" => \@params);
   return $TEMPLATEn->output();
} 
=head2 updateNode

  update Domain Node info

=cut

sub updateNode {
my ($action, $urn, $param1 ) = @_; 
   my $response = "OK";
   my %validation_regs =(packetSize => '^\d{1,5}$', count  => '^\d{1,4}$',  interval => '^\d{1,4}$',
                         period => '^\d{1,4}$', ttl => '^\d{1,4}$', offset => '^\d{1,4}$', 
			 ipAddress => '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$',  type   => '^IPv[4|6]$', hostName => '^[\w\.\-]+$');
   my ($node_urn, $port_name) = $urn =~ /^(.+\:node\=[\w\-\.]+)(?:\:port\=([\w\-\.]+))?$/; 
    my $node = findNode({urn => $node_urn}); 
    			 
    if($urn && $node && $param1 &&   ( $action =~ /^update\_(packetSize|count|interval|period|ttl|offset|ipAddress|type|hostName)/)) {
	  my $item = $1;
	 if($param1 =~ /$validation_regs{$item}/o) {
	    if($item =~ /ipAddress|type/)  {
	      my $port_obj = $node->port;
	      if($port_obj && $port_obj->id eq $urn) { 
	        if($item eq 'ipAddress') {
	           $port_obj->ipAddress->text($param1);
		   $port_obj->id($node_urn . ":port=$param1");
	        } else {
	           $port_obj->ipAddress->type($param1);
	        }
	      } else {
	        $response =     " !!!!!! Port $urn  not found:$action   $param1   !!! ";
	      }	
	    } elsif($item eq 'hostName'){
	       $node->hostName($param1);
	    } else {
	      my $test = $node->test;
	      no  strict 'refs';
	      ("perfSONAR_PS::Datatypes::v2_0::pingertopo::Topology::Domain::Node::Test::$item")->($test,$param1); 
	      use strict;
	    }
	 } else {
	   $response =     " !!!BAD NODE PARAM:$action  $urn  $param1    !!! ";
	 } 
      
   } elsif(!$node) {
     $response =   " !!! NODE not found:$action  $urn  $param1   !!! ";      
   }else {
     $response =   " !!!BAD NODE CONFIG CALL:$action  $urn  $param1   !!! ";
  }
  if($response eq "OK") {
      storeSESSION($SESSION);   
  }
  ####$logger->debug(" topology::\n" . Dumper $TOPOLOGY_OBJ);
  ####$logger->debug("  node \n " . Dumper $node);
  return  displayGlobal(), displayResponse($response), displayNode($node);
}



=head2
 
    callback for dynamic update on "add" "remove" "update" Ajax calls
   	       
=cut     

sub updateGlobal {
my ($action,  $urn, $new_name ) = @_; 
   my $response = "OK";
   my ($act, $what)  =  $action =~ /^(update|remove|add)\_(domain|node(?:name)?)?/;
   my ($domain_urn, $node_name) = $urn =~ /^(.+\:domain\=[\w\-\.]+)(?:\:node\=([\w\-\.]+))?$/; 
   $logger->debug("action=$action   domain_urn=$domain_urn node_name=$node_name newname=$new_name");
   my $node_out = '&nbsp;';
   if( $what  =~ /domain/) {
       my $new_urn = ($new_name =~ /^[\w\-\.]+$/)?URNBASE . ":domain=$new_name":undef;
         
       if($act eq 'add' && $new_urn) {  
           my $domain_obj =   $TOPOLOGY_OBJ->getDomainById($new_urn);  	 
           if($domain_obj) { 
	      $response =   " !!!ADD DOMAIN FAILED:  DOMAIN $new_name EXISTS !!!";
	   } else {
	      $TOPOLOGY_OBJ->addDomain(perfSONAR_PS::Datatypes::v2_0::nmtb::Topology::Domain->new({id => $new_urn}));
           }
        } elsif($act eq 'remove' && $domain_urn) {
	    $TOPOLOGY_OBJ->removeDomainById($urn);
	}  elsif($act eq 'update' && $domain_urn && $new_urn) {
	     my $domain_obj =   $TOPOLOGY_OBJ->getDomainById($urn);
	     $TOPOLOGY_OBJ->removeDomainById($urn);
	     $domain_obj = updateDomainId($domain_obj, $new_urn);
	     $TOPOLOGY_OBJ->addDomain($domain_obj); 
	} else {
	   $response =   "!!!BAD CALL PARAM:$action urn=$urn  callParam=$new_name    !!!";
	}
   } elsif( $what =~ /node/ && $domain_urn) {
       my $domain_obj =   $TOPOLOGY_OBJ->getDomainById($domain_urn);
      
       if($domain_obj) { 
       
           my $node_obj =  $domain_obj->getNodeById($urn);   
           $TOPOLOGY_OBJ->removeDomainById($domain_urn);
	   my $new_urn =  ($new_name =~ /^[\w\-\.]+$/)?$domain_urn . ":node=$new_name":undef;
	   
           if($act eq 'add' &&  $new_urn) {        
             $node_obj = perfSONAR_PS::Datatypes::v2_0::nmtb::Topology::Domain::Node->new(
	                             {id=> $new_urn, 
				      name =>   perfSONAR_PS::Datatypes::v2_0::nmtb::Topology::Domain::Node::Name->new({type => 'string', text => $new_name}),
				      port =>   perfSONAR_PS::Datatypes::v2_0::nmtl3::Topology::Domain::Node::Port->new(
				                   {xml  => "<nmtl3:port xmlns:nmtl3=\"http://ogf.org/schema/network/topology/l3/20070707/\" id=\"$new_urn:port=255.255.255.255\">
                                                          <nmtl3:ipAddress type=\"IPv4\">255.255.255.255</nmtl3:ipAddress>
                                                           </nmtl3:port>"}),
				      test =>   perfSONAR_PS::Datatypes::v2_0::pingertopo::Topology::Domain::Node::Test->new(
				                   {xml => '<pingertopo:test xmlns:pingertopo="http://ogf.org/ns/nmwg/tools/pinger/landmarks/1.0/">
				                            <pingertopo:packetSize>100</pingertopo:packetSize>
                                                            <pingertopo:count>10</pingertopo:count><pingertopo:interval>300</pingertopo:interval>
                                                            <pingertopo:ttl>255</pingertopo:ttl><pingertopo:period>10</pingertopo:period>
                                                            <pingertopo:offset>30</pingertopo:offset></pingertopo:test>'}) 
				    });
	     $domain_obj->addNode( $node_obj );
             $node_out = displayNode($node_obj);
             ####$logger->debug(" Added Domain :\n" . Dumper $domain_obj);
	   } elsif($act eq 'remove' && $node_name) {
             $domain_obj->removeNodeById($urn);
	
          } elsif( $act eq 'update' &&  $new_urn) {  
             
	      $domain_obj->removeNodeById($urn);
	      $node_obj = updateNodeId($node_obj, $new_urn);
	      $domain_obj->addNode($node_obj); 
	      $node_out = displayNode($node_obj);
	  }
          $TOPOLOGY_OBJ->addDomain($domain_obj);

        } else {
	  $response =   " !!!ADD NODE FAILED:  DOMAIN  $urn not found !!!";
        }
     
   } else {
      $response = "!!! MISSED PARAM:$action  urn=$urn   callParam=$new_name  !!!";
   }
   if($response =~ /^OK/) { 
     storeSESSION($SESSION); 
   }
   return  displayGlobal(),displayResponse($response), $node_out;
  
}
=head2 updateNodeId 

  updates   node  id , port   id 

=cut

sub updateNodeId {
  my ($node_obj, $new_node_urn) = @_;
  
  my ($node_part) =  $new_node_urn =~ /node\=([^\:]+)/;
  $node_obj->name(perfSONAR_PS::Datatypes::v2_0::nmtb::Topology::Domain::Node::Name->new({type => 'string', text => $node_part}));
	      
  $node_obj->id($new_node_urn);
  my $port = $node_obj->port;
  my $port_id = $port->id;  
  $port_id =~ s/node\=([^\:]+)\:/node\=$node_part\:/;
  $port->id($port_id);  
  ##$node_obj->port($port);
  return $node_obj;
}
=head2 updateDomainId 

  updates domain id and everything inside of domain element ( nodes id , ports  id )

=cut

sub updateDomainId {
  my ($domain_obj, $new_domain_urn) = @_;
  
  my ($domain_part) =   $new_domain_urn =~ /domain\=([^\:]+)/;
  $domain_obj->id($new_domain_urn);
  foreach my $in_node (@{$domain_obj->node}) {
	  my $node_id = $in_node->id;   
	  $node_id =~ s/domain\=([^\:]+)\:/domain\=$domain_part\:/;
          $in_node->id($node_id);
	  my $port = $in_node->port;
	  my $port_id = $port->id;  
	  $port_id =~ s/domain\=([^\:]+)\:/domain\=$domain_part\:/;
          $port->id($port_id);
           
   }
   return $domain_obj;
}
 
=head2 findNode

   find node by domain urn and nodename or urn
   
=cut

sub findNode {
   my($params ) = @_; 
   if($params && (ref($params) ne 'HASH' || !($params->{urn} || ($params->{domain} &&  $params->{name}) ))) {
       $logger->logdie(" Failed, only hashref parmaeter is accepted and 'domain' and 'urn' or 'name' must be supplied");
   }
   my ($domain_query, $node_query) = ($params->{domain}, $params->{name}); 
   if($params->{urn}) {
        ($domain_query ,$node_query)  = $params->{urn}  =~ /^.+\:domain\=([^\:]+)\:node\=(.+)$/;
   }
   
    $logger->debug(" quering for ::  $domain_query ,$node_query"); 
    foreach my $domain (@{$TOPOLOGY_OBJ->domain}) { 
        my ( $domain_part) = $domain->id =~ /domain\=([^\:]+)$/;
	   if($domain_part eq $domain_query) {
            foreach my $node (@{$domain->node}) {
	       my ( $node_part)   =  $node->id  =~ /node\=([^\:]+)$/; 
                 if($node_part  eq $node_query) {
	            $logger->debug(" Found node");
		    return  $node;
	       }
	    }
	    return undef;
        }
    } 
    return undef;
}


1;
 
