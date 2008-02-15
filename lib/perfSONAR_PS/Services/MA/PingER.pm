use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;
 
use perfSONAR_PS::Client::LS::Remote;
use perfSONAR_PS::Services::MA::General; 

use perfSONAR_PS::Datatypes::Namespace;
use perfSONAR_PS::Datatypes::v2_0::nmwg::Message; 
use perfSONAR_PS::Datatypes::Message;
use perfSONAR_PS::Datatypes::PingER;
use perfSONAR_PS::DB::PingER;

package perfSONAR_PS::Services::MA::PingER;

use version; our $VERSION = qv('2.0_0'); 

=head1 NAME

perfSONAR_PS::Services::MA::PingER - A module that implements   MA service.  

=head1 DESCRIPTION

This module aims to offer simple methods for dealing with requests for information, and the 
related tasks of intializing the backend storage.  

=head1 SYNOPSIS

    use perfSONAR_PS::Services::MA::PingER;
    
    use perfSONAR_PS::SimpleConfig;
    
   
    my %conf = ();
    $conf{"METADATA_DB_TYPE"} = "xmldb";
    $conf{"METADATA_DB_NAME"} = "/home/netadmin/LHCOPN/perfSONAR-PS/MP/Ping/xmldb";
    $conf{"METADATA_DB_FILE"} = "pingerstore.dbxml";
    $conf{"SQL_DB_USER"} = "pinger";
    $conf{"SQL_DB_PASS"} = "pinger";
    $conf{"SQL_DB_DB"} = "pinger_pairs";
    
    my $pingerMA_conf = perfSONAR_PS::SimpleConfig->new( -FILE => 'pingerMA.conf', -PROMPTS => \%CONF_PROMPTS, -DIALOG => '1');
    my $config_data = $pingerMA_conf->parse(); 
    $pingerMA_conf->store;
    %conf = %{$pingerMA_conf->getNormalizedData()}; 
    my $ma = perfSONAR_PS::MA::PingER->new( \%con );

    # or
    # $self = perfSONAR_PS::MA::PingER->new;
    # $self->setConf(\%conf);
       
        
    $self->init;  
    while(1) {
      $self->receive;
      $self->respond;
    }  
  

=head1 DETAILS

This API is a work in progress, and still does not reflect the general access needed in an MA.
Additional logic is needed to address issues such as different backend storage facilities.  

=head1 API

The offered API is simple, but offers the key functions we need in a measurement archive. 

=cut

use perfSONAR_PS::Services::Base;
use base 'perfSONAR_PS::Services::Base';

use fields qw( DATABASE LS_CLIENT );
use warnings;
use Exporter;

use POSIX qw(strftime);

# temp change the rose::db::object basename path to suit code
${perfSONAR_PS::DB::PingER::basename} = 'perfSONAR_PS::DB::PingER_DB';

use constant CLASSPATH => 'perfSONAR_PS::Services::MA::PingER';

use Log::Log4perl qw(get_logger);
our $logger = get_logger( CLASSPATH );

# name of configuraiotn elements to pick up
our $basename = 'PingERMA';

our $processName = 'perfSONAR-PS PingER MA';

=head2 new

create a new instance of the PingER MA

=cut
sub new {
	my $package = shift;
	
	my $self = $package->SUPER::new( @_ );
	$self->{'DATABASE'} = undef;
	$self->{'LS_CLIENT'} = undef;

	return $self;
}

=head2 init( $handler )

Initiate the MA; configure the configuration defaults, and message handlers.

=cut
sub init {
	my ($self, $handler) = @_;
    
    eval {
    	
    	# info about service
    	$self->configureConf( 'service_name', $processName, $self->getConf('service_name') );
    	$self->configureConf( 'service_type', 'MA', $self->getConf('service_type') );
    	$self->configureConf( 'service_description', $processName . ' Service', $self->getConf('service_description') );
    	$self->configureConf( 'service_accesspoint', 'http://localhost:'.$self->{PORT}."/".$self->{ENDPOINT} , $self->getConf('service_accesspoint') );
    	
    	$self->configureConf( 'metadata_db_host', undef, $self->getConf('metadata_db_host') );
		$self->configureConf( 'metadata_db_port', undef, $self->getConf('metadata_db_port') );
	    $self->configureConf( 'metadata_db_type', 'SQLite', $self->getConf('metadata_db_type') );
    	$self->configureConf( 'metadata_db_name', 'pingerMA.sqlite3', $self->getConf('metadata_db_name') );

    	$self->configureConf( 'metadata_db_user', undef, $self->getConf( 'metadata_db_user') );
    	$self->configureConf( 'metadata_db_pass', undef, $self->getConf( 'metadata_db_pass') );

    	# other
    	
    	# ls stuff
    	$self->configureConf( 'enable_registration', undef, $self->getConf( 'enable_registration') );


    };
    if ( $@ ) {
    	$logger->error( "Configuration incorrect: $@" ); 
		return -1;
    }
    
	$logger->info( "Initialising PingER MA");

    if ( $handler ) {
	    $logger->debug("Setting up message handlers");
  		$handler->addMessageHandler("SetupDataRequest", $self);
  		$handler->addMessageHandler("MetadataKeyRequest", $self);
  		$handler->addEventHandler("SetupDataRequest", "http://ggf.org/ns/nmwg/tools/pinger/2.0/", $self);
#  		$handler->addEventHandler("SetupDataRequest", "http://ggf.org/ns/nmwg/ops/select/2.0", $self);

    }
    
	# setup database  
  	$logger->debug( "initializing database " . $self->getConf("metadata_db_type") );
  
	if( $self->getConf("metadata_db_type") eq "SQLite" || "mysql") {
		
		# setup rose object
		eval {
			perfSONAR_PS::DB::PingER->register_db(
				domain	=> 'default',
				type	=> 'default',
				driver	=> $self->getConf( "metadata_db_type" ),
				database => $self->getConf( "metadata_db_name" ),
				host	=> $self->getConf( "metadata_db_host"),
				port	=> $self->getConf( "metadata_db_port"),
				username	=> $self->getConf( "metadata_db_user" ),
				password	=> $self->getConf( "metadata_db_pass" ),
			);
			# try to opent eh db
			my $db = perfSONAR_PS::DB::PingER->new_or_cached();
			$self->database( $db );
			$db->openDB();
		};
		if ( $@ ) {
			$logger->logdie( "Could not open database '" . $self->getConf( 'metadata_db_type') . "' for '"
				. $self->getConf( 'metadata_db_name') 
				. "' using '" . $self->getConf( 'metadata_db_user') ."'" );
		}
			
	} else {
		$logger->logdie( "Database type '" .  $self->getConf("metadata_db_type") . "' is not supported.");
		return -1;
	}
	
	# set name
	$0 = $processName;
	
    return 0;
}

=head2 database

accessor/mutator for database instance

=cut
sub database
{
	my $self = shift;
	if ( @_ ) {
		$self->{DATABASE} = shift;
	}
	return $self->{DATABASE};
}


sub configureConf
{
	my $self = shift;
	my $key = shift;
	my $default = shift;
	my $value = shift;
	
	my $fatal = shift; # if set, then if there is no value, will return -1

		if ( defined $value ) {
			if ( $value =~ /^ARRAY/ ) {
				my $index = scalar @$value - 1;
				#$logger->info( "VALUE: $value,  SIZE: $index");

				$value = $value->[$index];
				$logger->fatal( "Value for '$key' set to '$value'");
			}
			$self->{CONF}->{$basename}->{$key} = $value;
		} else {
			if ( ! $fatal ) {
				if ( defined $default ) {
						$self->{CONF}->{$basename}->{$key} = $default;
						$logger->warn( "Setting '$key' to '$default'");
				} else {
					$self->{CONF}->{$basename}->{$key} = undef;
					$logger->warn( "Setting '$key' to null");
				}
			} else {
				$logger->logdie( "Value for '$key' is not set" );
			}
		}
			
	return 0;
}


sub getConf
{
	my $self = shift;
	my $key = shift;
	return $self->{'CONF'}->{$basename}->{$key};
}

=head2 ls

accessor/mutator for the lookup service

=cut
sub ls
{
	my $self = shift;
	if ( @_ ) {
		$self->{'LS_CLIENT'} = shift;
	}	
	return $self->{'LS_CLIENT'};
}

=head2 needLS

Should the instance of the PingER register with a LS?

=cut
sub needLS($) {
	my ($self) = @_;
	return $self->getConf( 'enable_registration' );;
}

=head2 registerLS

register all the metadata that our ma contains to the LS

=cut
sub registerLS($)
{
	my $self = shift;
	
	$0 = $processName . ' LS Registration';
	
	$logger->info( "Registering PingER MA with LS");
	# create new client if required
	if ( ! defined $self->ls() ) {
		my $ls_conf = {
			'SERVICE_TYPE' => $self->getConf( 'service_type' ),
			'SERVICE_NAME' => $self->getConf( 'service_name'),
			'SERVICE_DESCRIPTION' => $self->getConf( 'service_description'),
			'SERVICE_ACCESSPOINT' => $self->getConf( 'service_accesspoint' ),
		};
		my $ls = new perfSONAR_PS::Client::LS::Remote(
				$self->getConf('ls_instance'),
				$ls_conf,
			);
		$self->ls( $ls );
	}
	
	my @sendToLS = ();
	
	# open db
	my $iterator = perfSONAR_PS::DB::PingER_DB::MetaData::Manager->get_metaData_iterator();
	while( $md = $iterator->next )
	{
		# get hosts
		my $endpoint = perfSONAR_PS::Datatypes::v2_0::nmwgt::Message::Metadata::Subject::EndPointPair->new();
		
		my $src = perfSONAR_PS::Datatypes::v2_0::nmwgt::Message::Metadata::Subject::EndPointPair::Src->new({
								'value' =>  $md->ip_name_src(),
								'type'  =>  'hostname', 
							});
		my $dst = perfSONAR_PS::Datatypes::v2_0::nmwgt::Message::Metadata::Subject::EndPointPair::Src->new({
								'value' =>  $md->ip_name_dst(),
								'type'  =>  'hostname', 
							});
	
		$endpoint->src( $src );
		$endpoint->dst( $dst );


		my $subject = perfSONAR_PS::Datatypes::v2_0::pinger::Message::Metadata::Subject->new();
		$subject->endPointPair( $endpoint );
		
		# setup parameters
		my @params = ();
		no strict 'refs';
		foreach my $p ( qw/ count packetSize interval ttl / ) {
			my $param = perfSONAR_PS::Datatypes::v2_0::nmwg::Message::Metadata::Parameters::Parameter->new({
							'name' => $p, });
			my $q = $p;
			$q = 'packetInterval'
				if $p eq 'interval';
			$param->text( $md->$q() );
			push @params, $param;
		}
		use strict 'refs';
		my $parameters = perfSONAR_PS::Datatypes::v2_0::pinger::Message::Metadata::Parameters->new();
		$parameters->parameter( @params );
		
		# event type
		my $eventType = perfSONAR_PS::Datatypes::EventTypes->new();

		# create the metadata
		my $mdid = ref($md->metaID) eq 'Math::BigInt' ? $md->metaID->bstr : $md->metaID;
		my $metadata = perfSONAR_PS::Datatypes::v2_0::nmwg::Message::Metadata->new({
			 				'id' => $mdid });

		$metadata->subject( $subject );
		$metadata->eventType( $eventType->tools->pinger );
		$metadata->parameters( $parameters );
		
		push @sendToLS, $metadata->getDOM()->toString() ;

	}
	
	# foreach my $meta ( @sendToLS ) {
	# 	$logger->debug( "Found metadata for LS registration: '" . $meta . "'" );
	# }

	return $self->ls()->registerStatic(\@sendToLS);
}


sub handleMessageBegin($$$$$$$$) {
	my ($self, $ret_message, $messageId, $messageType, $msgParams, $request, $retMessageType, $retMessageNamespaces);
	
	$0 = $processName . ' Query';

	return 1;
}

sub handleMessageEnd($$$$$$$$) {
	my ($self, $ret_message, $messageId);
	return 1;
}

=head2 handleEvent()

main access into MA from Daemon Architecture

=cut
sub handleEvent()
{
	my ($self, $output, $messageId, $messageType, $message_parameters, $eventType, $md, $d, $raw_request) = @_;
	
	# shoudl do some validation on the eventType
	
	my $response = $self->__handleEvent( $raw_request );
	$output->addExistingXMLElement( $response->getDOM() );

	return ( "", "" );
}

=head2 __handleEvent( $request )

actually do something the incoming $request message.

=cut
sub __handleEvent {
 	
	my( $self, $request ) = @_;
  	
#  	use Data::Dumper;
#	$logger->info( "\n\n\nRequest:\n" . Dumper $request );

#	$self->{REQUESTNAMESPACES} =  $request->getNamespaces();
	my $doc = $request->getRequestDOM();

 	$logger->info( "\n\nDOM:\n" . $doc->toString );

	$logger->debug("Unmarshalling into PingER object");
	my $pingerRequest = perfSONAR_PS::Datatypes::PingER->new( $doc->documentElement() );
	my $error_msg = '';
	my $type = $pingerRequest->type;

#	foreach my $field ($pingerRequest->show_fields('Public')) {
#		$logger->debug("Pinger Request:: $field= " . $pingerRequest->{$field});
#	}
  
	my $messageIdReturn = "message." . perfSONAR_PS::Common::genuid(); 
	(my $responseType = $type ) =~ s/Request/Response/;
     
 	$logger->debug("Parsing request...Registering namespaces...");
	$pingerRequest->registerNamespaces();
	$logger->debug("Done...");
   
	### pass db handler down request object
	$logger->debug("Creating PingER response");
	my $pingerResponse =   perfSONAR_PS::Datatypes::Message->new(
   		{type => $responseType , id =>   $messageIdReturn  }); # response message
	$logger->debug("Done...");
   
#	foreach my $field ($pingerResponse->show_fields('Public')) {
#		$logger->debug("Pinger Response:  $field= " . $pingerResponse->{$field});
#	}
   
	#### map namespaces on response
	$logger->debug(" Mapping namespaces on response");
	$pingerResponse->nsmap($pingerRequest->nsmap);
	## merge chains and work with them in request
    $logger->debug("Done...");
	### 
   	 
	my $evt = $pingerRequest->eventTypes;
  	my $errorMessage = $pingerRequest->handle($type, $pingerResponse, $self->{'CONF'}->{'PingERMA'});

	$logger->debug( "PINGER RESPONSE: $errorMessage\n" . $pingerResponse->asString() );
   
	return $pingerResponse;
}
 
  


1;


=head1 SEE ALSO

L<perfSONAR_PS::MA::Base>, L<perfSONAR_PS::MA::General>, L<perfSONAR_PS::Common>, 
L<perfSONAR_PS::Messages>, L<perfSONAR_PS::DB::File>, L<perfSONAR_PS::DB::XMLDB>, 
L<perfSONAR_PS::DB::RRD>, L<perfSONAR_PS::Datatypes::Namespace>, L<perfSONAR_PS::SimpleConfig>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 VERSION

$Id: PingER.pm 227 2007-06-13 12:25:52Z zurawski $

=head1 AUTHOR

Yee-Ting Li, E<lt>ytl@slac.stanford.eduE<gt>
Maxim Grigoriev, E<lt>maxim@fnal.govE<gt>
Jason Zurawski, E<lt>zurawski@internet2.eduE<gt>


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Internet2

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
