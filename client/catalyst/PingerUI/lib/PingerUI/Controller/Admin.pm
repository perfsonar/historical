package PingerUI::Controller::Admin;

use strict;
use warnings;
use parent 'Catalyst::Controller';
use English qw( -no_match_vars );
use File::Slurp qw( slurp );
use File::Copy;
use Data::Dumper;
use Scalar::Util qw(blessed);
use Captcha::reCAPTCHA;

=head1 NAME

PingerUI::Controller::Admin - pinger admin controller

=head1 DESCRIPTION

PingER administrative GUI, implemented as Catalyst Controller.

=head1 METHODS

=cut
use PingerUI::Utils qw(isParam   updateNodeId updateDomainId get_params_obj %pinger_keys csv2xml_landmarks findNode );
 
=head2 index 

=cut

use aliased 'perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::pingertopo::Topology';
use aliased 'perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::pingertopo::Topology::Domain';
use aliased 'perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::pingertopo::Topology::Domain::Node';
use aliased 'perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::nmtb::Topology::Domain::Node::Name';
use aliased 'perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::nmtb::Topology::Domain::Node::HostName';
use aliased 'perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::nmwg::Topology::Domain::Node::Parameters';
use aliased 'perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::nmwg::Topology::Domain::Node::Parameters::Parameter';
use aliased 'perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::nmtl3::Topology::Domain::Node::Port';

use perfSONAR_PS::Utils::DNS qw/reverse_dns resolve_address/;

sub index :Path :Args(0) {
    my ( $self, $c ) = @_;
    $c->response->body('Matched PingerUI::Controller::Admin in Admin.');
}

sub auto : Private {
    my ($self, $c) = @_;
    my $login_path = 'admin/login';
    $c->require_ssl;
    # allow people to actually reach the login page!
     # if a user doesn't exist, force login
     $c->stash->{local_user} = $ENV{USER};
    if(($c->request->path eq $login_path) || 
        !($c->user_exists &&  
            $c->sessionid && 
	    $c->check_user_roles("config"))) {
        my $recap = Captcha::reCAPTCHA->new;
	my $captcha_response =$c->req->params->{recaptcha_response_field};
        my $captcha_challenge =  $c->req->params->{recaptcha_challenge_field};	       
        my $result = $recap->check_answer($c->config->{RECAPTCHA_PRIVATE},
                                       $ENV{'REMOTE_ADDR'},
				       $captcha_challenge,  
				       $captcha_response );
	 if ( my $user     = $c->req->params->{username} and
              my $password = $c->req->params->{password} and 
	      $result->{is_valid})  {
            if ( $c->login( $user,  $password ) ) {	
	        return 1;
	    }		
	    else {
	        $c->stash->{'message'} =   'Unable to authenticate';
	        $c->error; 
	    }
	} 
        else {
            $c->stash->{'message'} =   'Please provide username and password';
            $c->stash->{captcha} =  $recap->get_html($c->config->{RECAPTCHA_PUBLIC});
            $c->stash->{'template'} = "admin/login.tt";
        }       
    }
    $c->log->debug(" We have a user");
    # otherwise, we have a user - continue with the processing chain
    return 1;
}
 

sub login : Local {
  my ($self, $c) = @_;
  $c->response->redirect('configure');
}

sub logout : Local {
    my ($self, $c) = @_;
    # log the user out
    $c->logout;
    # do the 'default' action
    $c->response->redirect($c->request->base);
} 

 
=head2  config 
    
         admin gui

=cut

sub configure : Local {
    my ( $self, $c ) = @_;
    $c->forward('_process_params');
    $c->stash->{title} = "PingER MA and MP Configuration Manager"; 
    $c->forward('_displayGlobal');
    $c->stash->{template} = 'admin/admin_header.tmpl';
}


sub upload_file : Local {
    my ( $self, $c ) = @_;
    $c->log->debug("Uploads:" . Dumper    $c->request->uploads);
    my $upload = $c->request->upload('file_id');
 
    unless($upload && $upload->filename) {
        $c->res->output("No file in upload");
	return $c->forward('configure')  
    }
    my $tmp = $c->config->{uploadtmp} . $upload->filename;
    $upload->copy_to( $tmp  );
    if(-f  $tmp ) {
        if($tmp =~ /\.csv$/) {
	    $tmp = csv2xml_landmarks($c->log, $tmp);
	}  
        move( $tmp , $c->config->{LANDMARKS} ) or die $c->error( "Failed to replace:  $c->config->{LANDMARKS}  " );    
	$c->forward('_set_defaults');
	$c->forward('configure');
    }
}

sub _process_params : Private {
    my ( $self,   $c ) = @_;        
    foreach  my $param ( keys %{$c->req->params}){
        $c->stash->{$param} = $c->req->params->{$param};
    } 
    if($c->session && $c->session->{topology}) {
        $c->stash->{topology} =  Topology->new( { xml => $c->session->{topology} }) ;
	$c->log->debug("Setting topology from session storage");
    } 
    else {
        $c->forward('_set_defaults'); 
	$c->log->debug("Setting topology from file");
    }                           
}


sub _set_defaults : Private {
    my ( $self,   $c ) = @_;
    my $string =  slurp($c->config->{LANDMARKS}, err_mode => 'croak');
    $c->stash->{topology} = Topology->new( { xml => $string  } );
    $c->session->{topology} =   $c->stash->{topology}->asString;
}

=head2  restart_mp

   restart mp/ma

=cut

sub restart_mp  : Local {
    my ( $self, $c ) = @_;
    $c->forward('_process_params');
    if($c->stash->{action} eq 'Restart' && $c->config->{RESTART_SERVICE}) {
        system("sudo /etc/init.d/PingER.sh restart &> /dev/null");
        $c->res->output( ' PingER MP/MA was restarted');
    }
    else {
       $c->res->output( ' Wrong or unsupported request, check config');
    }
}

=head2  resetit

   reset  session

=cut

sub resetit : Local {
    my ( $self, $c ) = @_;
    $c->forward('_process_params');
    $c->forward('_set_defaults');
    $c->forward('_displayGlobal');
    $c->stash->{status} = ' Session contents has been reset ';
    $c->stash->{template} = 'admin/domains.tmpl';

}
=head2  saveConfigs

  update XML files ( Template for MP and restart MP daemon)

=cut   

sub saveConfigs : Local {
    my ( $self,   $c ) = @_;
    $c->forward('_process_params');
    my $tmp_file = $c->config->{uploadtmp} . 'temp_LANDMARKS.' . $c->sessionid;
    my $fd = new IO::File($tmp_file, "w") or die $c->error( "Failed to open file $tmp_file" . $ERRNO );
    eval { print $fd $c->stash->{topology}->asString; };
    if ($EVAL_ERROR) {
          die $c->error("Failed $ERRNO to store config file $tmp_file - $EVAL_ERROR");
    }
    $fd->close;
    move( $tmp_file, $c->config->{LANDMARKS} ) or die $c->error( "Failed to replace:  $c->config->{LANDMARKS}  " );
    my $res = "PingER landmarks XML file was saved";
    if ($c->config->{RESTART_SERVICE}) {
        system("sudo /etc/init.d/PingER.sh restart &> /dev/null");
        $res = "PingER landmarks XML file was saved, and the PingER service has been restarted.";
    }
    $c->stash->{status} = $res;
    $c->res->output($res); 
}
=head2  configureNode 

   configre node  callback id=configureLink<TMPL_VAR NAME=urn>, $urn 

=cut

sub configureNode : Local { 
    my ( $self,   $c ) = @_;
    $c->forward('_process_params');
    $c->log->debug("id=" . $c->stash->{input} . " urn=" . $c->stash->{urn});
    if (  $c->stash->{input} =~ /^Configure Node/sm   &&  $c->stash->{urn}  )  {
        $c->forward('_displayNode');
    }
    else {
        $c->res->output('Failed parameters input='. $c->stash->{input} . ' urn=' .  $c->stash->{urn}); 
        $c->error('Failed parameters input='. $c->stash->{input} . ' urn=' .  $c->stash->{urn});
    }
}

=head2 displayNode

   prints Node view

   arguments:  
              $node - topology objects tree with node
   return:  $html - HTML string

=cut

sub _displayNode : Private{
    my ( $self,   $c ) = @_; 
    my ( $domain_obj, $node ) = findNode($c->stash->{topology}, { urn =>  $c->stash->{urn} }, $c->log );
    my @params    = ();
    unless($node) {
        die $c->error('No nodes found urn=' . $c->stash->{urn});
    }
    my $node_urn  = $node->get_id;  
    eval {
        push @params, { urn => $node_urn, what => 'hostName', valuen => $node->get_hostName->get_text } if $node->get_hostName;
        my $test_params = $node->get_parameters;
        foreach my $param ( @{ $test_params->get_parameter } ) {
	    
            push @params, { urn => $node_urn, what => $param->get_name, valuen => ($param->get_value?$param->get_value:$param->get_text) }
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
        $c->stash->{"domain_name"} =  $domain_name;
        $c->stash->{"node_name"}   =  $node->get_name->get_text;
        $c->stash->{"urn"}         =  $node_urn;
        $c->stash->{"nodeparams"}  =  \@params;
    };
    if ($EVAL_ERROR) {
        die $c->error(" Node display failed $EVAL_ERROR");
    }
    $c->stash->{status} = 'OK';
    $c->session->{topology}  = $c->stash->{topology}->asString; 
    $c->stash->{template} =   'admin/node_config.tmpl';
}
 
sub _displayGlobal : Private {
    my ( $self,   $c ) = @_;   
    my %domain_names         = ();
    my %gls_display_projects = ();
    $c->stash->{domains} = [];  
   
    return unless $c->stash->{topology} && blessed $c->stash->{topology} && $c->stash->{topology}->get_domain;
    foreach my $domain ( @{$c->stash->{topology}->get_domain} )  {
        my $urn = $domain->get_id;
	$c->log->debug( "  _displayGlobal urn=$urn ");
        if ($urn) {
            my ($dname) = $urn =~ /\:domain\=([^\:]+)/;
            my $nodes = $domain->get_node;
            my @nodenames = ();
            foreach my $node ( @{$nodes} ) {
	        $c->log->debug( "  _displayGlobal Node urn= " . $node->get_id);
        	push @nodenames, { node_name => $node->get_name->get_text, urn => $node->get_id }
        	    if $node->get_name;
            }
            $domain_names{$dname} = {
        	domain_name => $dname,
        	urn	    => $domain->get_id,
        	Nodes	    => \@nodenames
            };
        }
    }

    my %used_addresses = ();

    foreach my $domain ( @{ $c->stash->{topology}->get_domain } ) {
        if ( $domain->get_node ) {
   	    foreach my $node ( @{ $domain->get_node } ) {
   	        my $port = $node->get_port;

   	        $c->log->debug( "Used Address: " . $port->get_ipAddress->get_text );
   	        $used_addresses{ $port->get_ipAddress->get_text } = 1;
   	    }
        }
    }
    my @table2display = ();
    foreach my $domain ( sort keys %domain_names ) {
        push @table2display, $domain_names{$domain};
    }  
    $c->session->{topology}  = $c->stash->{topology}->asString; 
    $c->stash->{domains} = \@table2display;
    $c->stash->{template} = 'admin/domains.tmpl';
}

=head2
 
    callback for dynamic update on "add" "remove" "update" Ajax calls
             
=cut     

sub updateGlobal : Local {
    my ( $self,   $c ) = @_; 
    $c->forward('_process_params');  
    my $response = "OK";
    
    die $c->error(" updateGlobal missing action or urn parameter") unless $c->stash->{action} &&  $c->stash->{urn};
    my $action = $c->stash->{action};
    my $urn =  $c->stash->{urn};
    my $new_name = $c->stash->{input};
    my ( $act, $what ) = $action =~ /^(update|remove|add)\_(domain|addr|node(?:name)?)?/;
    my ( $domain_urn, $node_name, $addr ) = $urn =~ /^(.+\:domain\=[\w\-\.]+)(?:\:node\=([\w\-\.]+))?(?:\:port\=([\w\-\.]+))?$/;
    $c->log->debug("action=$action   domain_urn=$domain_urn node_name=$node_name port_address=$addr newname=$new_name");
  
    if ( $what =~ /domain/ ) {
        my $new_urn
            = ( $new_name =~ /^[\w\-\.]+$/ )
            ? $c->config->{URNBASE} . ":domain=$new_name"
            : undef;

        if ( $act eq 'add' && $new_urn ) {
            my $domain_obj = $c->stash->{topology}->getDomainById($new_urn);
            if ($domain_obj) {
                $response = " !!!ADD DOMAIN FAILED:  DOMAIN $new_name EXISTS !!!";
            }
            else {
                $c->stash->{topology}->addDomain( Domain->new( { id => $new_urn } ) );
            }
        }
        elsif ( $act eq 'remove' && $domain_urn ) {
            $c->stash->{topology}->removeDomainById($urn);
        }
        elsif ( $act eq 'update' && $domain_urn && $new_urn ) {
            my $domain_obj = $c->stash->{topology}->getDomainById($urn);
            $c->stash->{topology}->removeDomainById($urn);
            $domain_obj = updateDomainId( $domain_obj, $new_urn );
            $c->stash->{topology}->addDomain($domain_obj);
        }
        else {
            $response = "!!!BAD CALL PARAM:$action urn=$urn  callParam=$new_name    !!!";
        }
    }
    elsif ( $what =~ /node/ && $domain_urn ) {
        my $domain_obj = $c->stash->{topology}->getDomainById($domain_urn);

        if ($domain_obj) {
            my $node_obj = $urn =~ /\:node/ ? $domain_obj->getNodeById($urn) : undef;
            $c->stash->{topology}->removeDomainById($domain_urn);
            my $new_urn
                = ( $new_name =~ /^[\w\-\.]+$/ )
                ? $domain_urn . ":node=$new_name"
                : undef;
            $c->log->debug("action=$action - new_urn=$new_urn");
            if ( $act eq 'add' && $new_urn ) {
                eval {
                    my ($dname) = $urn =~ /\:domain\=([^\:]+)/;

                    my ($ip_resolved) = resolve_address($new_name.".".$dname);
                    $ip_resolved = "255.255.255.255" if (not $ip_resolved or $ip_resolved eq $new_name.".".$dname);

                    my $ip_type;
                    if ($ip_resolved =~ /:/) {
                        $ip_type = "IPv6";
                    } else {
                        $ip_type = "IPv4";
                    }

                    $node_obj = Node->new(
                        {
                            id   => $new_urn,
                            name => Name->new( { type => 'string', text => $new_name } ),
                            hostName => HostName->new( { text => $new_name.".".$dname } ),
                            port     => Port->new(
                                {
                                    xml => "<nmtl3:port xmlns:nmtl3=\"http://ogf.org/schema/network/topology/l3/20070707/\" id=\"$new_urn:port=255.255.255.255\">
                      <nmtl3:ipAddress type=\"$ip_type\">$ip_resolved</nmtl3:ipAddress>
                   </nmtl3:port>"
                                }
                            ),
                            parameters => get_params_obj({}, 'paramid1')
                        }
                    );
                    $c->log->debug( " new node will be added " . $node_obj->asString );
                    $domain_obj->addNode($node_obj);
		    $c->log->debug( " Added Domain :\n" .  $domain_obj->asString );		    
                   
                };
                if ($EVAL_ERROR) {
                    die $c->error(" New node  failed: $EVAL_ERROR ");
                } 		  
            }
            elsif ( $act eq 'remove' && $node_name ) {
                $domain_obj->removeNodeById($urn);
            }
            elsif ( $act eq 'update' && $new_urn ) {
                eval {
                    $domain_obj->removeNodeById($urn);
                    $node_obj = updateNodeId( $node_obj, $new_urn );
                    $domain_obj->addNode($node_obj);                  
                };
                if ($EVAL_ERROR) {
                    die $c->error("Update global node failed $EVAL_ERROR  ");
                }
            }
	    $c->stash->{urn} = $new_urn;       
            $c->stash->{topology}->addDomain($domain_obj);	    
	    return ($action =~ /(update|add)_node/?$c->forward('_displayNode'):$c->forward('_displayGlobal')); 
        }
        else {
            $c->error(" !!!ADD NODE FAILED:  DOMAIN  $urn not found !!!");
        }
    }
    elsif ( $what =~ /addr/ && $node_name && $domain_urn ) {
        my $domain_obj = $c->stash->{topology}->getDomainById($domain_urn);

        if ( not $domain_obj ) {
            $c->stash->{topology}->addDomain( Domain->new( { id => $domain_urn } ) );
            $domain_obj = $c->stash->{topology}->getDomainById($domain_urn);
        }

        my $node_urn = $domain_urn . ":node=" . $node_name;
        my $node_obj = $domain_obj->getNodeById($urn);
        if ( not $node_obj ) {
            eval {
                my ($dname) = $urn =~ /\:domain\=([^\:]+)/;
                my $ip_type;
                if ($ip_type =~ /:/) {
                    $ip_type = "IPv6";
                } else {
                    $ip_type = "IPv4";
                }
                $node_obj = Node->new(
                    {
                        id   => $node_urn,
                        name => Name->new( { type => 'string', text => $node_name } ),
                        hostName => HostName->new( { text => $node_name.".".$dname } ),
                        port     => Port->new(
                            {
                                xml => "<nmtl3:port xmlns:nmtl3=\"http://ogf.org/schema/network/topology/l3/20070707/\" id=\"$urn\">
                  <nmtl3:ipAddress type=\"$ip_type\">$addr</nmtl3:ipAddress>
               </nmtl3:port>"
                            }
                        ),
                        parameters => get_params_obj({}, 'paramid1')
                    }
                );
                $c->log->debug( " new node will be added " . Dumper $node_obj->asString );
                $domain_obj->addNode($node_obj); 
            };
            if ($EVAL_ERROR) {
                  $c->error(" New node  failed: $EVAL_ERROR ");
            }
            else {
                  $c->log->debug( " Added Domain :\n" . Dumper $domain_obj);
            }
        }
        else {
            $response = "!!! Already Pinging Host $node_name !!!";
        }
    }
    else {
        $response = "!!! MISSED PARAM:$action  urn=$urn   callParam=$new_name  !!!";
    }
    
    unless($response eq "OK") {
        $c->res->output("action=$action  failed: $response");
        $c->log->fatal("action=$action  failed: $response"); 
    }
    else {
        $c->forward('_displayGlobal'); 
    }
}

=head2 updateNode

  update Domain Node info

=cut

sub updateNode : Local {
    my ( $self,   $c ) = @_; 
    $c->forward('_process_params');  
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
    my $action = $c->stash->{action};
    my $urn =  $c->stash->{urn};
    my $item =  $c->stash->{extra};
    my $param1 =  $c->stash->{input};
    my ( $node_urn, $port_name ) = $urn =~ /^(.+\:node\=[\w\-\.]+)(?:\:port\=([\w\-\.]+))?$/;
    my ( $domain_obj, $node ) = findNode($c->stash->{topology}, { urn => $node_urn }, $c->log );
    
    $c->log->debug( " Will update $item  => $param1  in the $urn node: " . $node->asString );
    if ( $urn && $node && $param1 && isParam($item) ) {
        if ( $param1 =~ $validation_regs{$item} ) {
            eval {
                if ( $item =~ /ipAddress|type/ )  {
                    my $port_obj = $node->get_port;
                    if ( $port_obj && $port_obj->get_id eq $urn ) {
                        if ( $item eq 'ipAddress' ) {
                            $port_obj->set_ipAddress->set_text($param1);
                            $port_obj->set_id( $node_urn . ":port=$param1" );
			    $c->stash->{urn} = $node_urn;
			    $c->log->debug(" Updating node:port with: $node_urn\:port=$param1");
                        }
                        else {
                            $port_obj->set_ipAddress->set_type($param1);
                        }
                    }
                    else {
                        $response = " !!!!!! Port $urn  not found: $item  => $param1   !!! ";
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
            if ($EVAL_ERROR) {
                $c->error("node update failed $EVAL_ERROR ");
            }
        }
        else {
            $response = " !!!BAD NODE PARAM:$item  $urn  $param1    !!! ";
        }

    }
    elsif ( !$node ) {
        $response = " !!! NODE not found:$item   $urn  $param1   !!! ";
    }
    else {
        $response = " !!!BAD NODE CONFIG CALL:$item  $urn  $param1   !!! ";
    }
    unless($response eq "OK") {
        $c->res->output("update param=$item  failed: $response");
        $c->log->fatal("update param=$item failed: $response");	 
    } else {
        $c->forward('_displayNode');
    }
}

=head1   AUTHOR

    Maxim Grigoriev, 2009, maxim@fnal.gov
         

=head1 COPYRIGHT

Copyright (c) 2009, Fermi Research Alliance (FRA)

=head1 LICENSE

You should have received a copy of the Fermitool license along with this software.


=cut

1;
