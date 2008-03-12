package perfSONAR_PS::Client::LS;

use fields 'INSTANCE', 'LOGGER', 'ALIVE';

use strict;
use warnings;

our $VERSION = 0.08;

=head1 NAME

perfSONAR_PS::Client::LS - API for calling the LS from a client or another
service.

=head1 DESCRIPTION

The Lookup Service is an integral part of the perfSONAR-PS framework when it
comes to discovering services and data.  This API offers the basic functionality
that is needed to interact with the LS.

=cut

use Log::Log4perl qw( get_logger );
use Params::Validate qw( :all );
use English qw( -no_match_vars );

use perfSONAR_PS::Common qw( genuid makeEnvelope find extract unescapeString );
use perfSONAR_PS::Transport;
use perfSONAR_PS::Client::Echo;
use perfSONAR_PS::ParameterValidation;

=head2 new($package { instance })

Constructor for object.  Optional argument of 'instance' is the LS instance
to be contacted for interaction.  This can also be set via 'setInstance'.

=cut

sub new {
    my ( $package, @args ) = @_;
    my $parameters = validateParams( @args, { instance => 0 } );

    my $self = fields::new($package);
    $self->{ALIVE}  = 0;
    $self->{LOGGER} = get_logger("perfSONAR_PS::Client::LS");
    if ( exists $parameters->{"instance"} and $parameters->{"instance"} ) {
        $self->{INSTANCE} = $parameters->{"instance"};
    }
    return $self;
}

=head2 setInstance($self { instance })

Required argument 'instance' is the LS instance to be contacted for queries.  

=cut

sub setInstance {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { instance => 1 } );

    $self->{ALIVE}    = 0;
    $self->{INSTANCE} = $parameters->{"instance"};
    return;
}

=head2 callLS($self { message })

Calls the LS instance with the sent message and returns the response (if any). 

=cut

sub callLS {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { message => 1 } );

    unless ( $self->{INSTANCE} ) {
        $self->{LOGGER}->error("Instance not defined.");
        return;
    }

    unless ( $self->{ALIVE} ) {
        my $echo_service = perfSONAR_PS::Client::Echo->new( $self->{INSTANCE} );
        my ( $status, $res ) = $echo_service->ping();
        if ( $status == -1 ) {
            $self->{LOGGER}->error( "Ping to " . $self->{INSTANCE} . " failed: $res" );
            return;
        }
        $self->{ALIVE} = 1;
    }

    my ( $host, $port, $endpoint ) = perfSONAR_PS::Transport::splitURI( $self->{INSTANCE} );
    unless ( defined $host and defined $port and defined $endpoint ) {
        return;
    }

    my $sender = new perfSONAR_PS::Transport( $host, $port, $endpoint );
    unless ($sender) {
        $self->{LOGGER}->error("LS could not be contaced.");
        return;
    }

    my $error = q{};
    my $responseContent = $sender->sendReceive( makeEnvelope( $parameters->{message} ), q{}, \$error );
    if ($error) {
        $self->{ALIVE} = 0;
        $self->{LOGGER}->error("sendReceive failed: $error");
        return;
    }

    my $msg    = q{};
    my $parser = XML::LibXML->new();
    if ( defined $responseContent and $responseContent and ( not $responseContent =~ m/^\d+/xm ) ) {
        my $doc = q{};
        eval { $doc = $parser->parse_string($responseContent); };
        if ($EVAL_ERROR) {
            $self->{LOGGER}->error( "Parser failed: " . $EVAL_ERROR );
        }
        else {
            $msg = $doc->getDocumentElement->getElementsByTagNameNS( "http://ggf.org/ns/nmwg/base/2.0/", "message" )->get_node(1);
        }
    }
    else {
        $self->{ALIVE} = 0;
    }
    return $msg;
}

=head2 registerRequestLS($self, { service, data })

Given service information (in the form of a hash reference) create a service
metadata block and include the data (in the form of an array reference) into
an LS registration message.  The results of this operation will be a 
hash of results for each metadata/data pair.  Note this should be used for all
'new' service registrations.

=cut

sub registerRequestLS {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { service => 1, data => 1 } );

    my $metadata = q{};
    my %ns       = (
        perfsonar => "http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/",
        psservice => "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/"
    );
    $metadata .= $self->createService( { service => $parameters->{service} } );

    my $msg = $self->callLS( { message => $self->createLSMessage( { type => "LSRegisterRequest", ns => \%ns, metadata => $metadata, data => $parameters->{data} } ) } );
    unless ($msg) {
        $self->{LOGGER}->error("Message element not found in return.");
        return;
    }

    my %result = ();
    my $eventType = extract( find( $msg, "./nmwg:metadata/nmwg:eventType", 1 ), 0 );
    if ($eventType) {
        $result{"eventType"} = $eventType;
        $result{"response"} = extract( find( $msg, "./nmwg:data/nmwg:datum", 1 ), 0 );
        unless ( $result{"response"} ) {
            $result{"response"} = extract( find( $msg, "./nmwg:data/nmwgr:datum", 1 ), 0 );
        }
        if ( $eventType =~ m/^success/mx ) {
            $result{"key"} = extract( find( $msg, "./nmwg:metadata/nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"lsKey\"]", 1 ), 0 );
        }
    }
    return \%result;
}

=head2 registerUpdateRequestLS($self, { key, data })

Given a key of an alredy registered service, create a key metadata block and
include the data (in the form of an array reference) into an LS registration
message.  The results of this operation will be a hash of results for each
metadata/data pair.  Note this should be used for all 'existing' service 
where the goal is to add data to the registration set.

=cut

sub registerUpdateRequestLS {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { key => 1, data => 1 } );

    my $metadata = q{};
    my %ns       = (
        perfsonar => "http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/",
        psservice => "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/"
    );
    $metadata .= $self->createKey( { key => $parameters->{key} } );

    my $msg = $self->callLS( { message => $self->createLSMessage( { type => "LSRegisterRequest", ns => \%ns, metadata => $metadata, data => $parameters->{data} } ) } );
    unless ($msg) {
        $self->{LOGGER}->error("Message element not found in return.");
        return;
    }

    my %result = ();
    my $eventType = extract( find( $msg, "./nmwg:metadata/nmwg:eventType", 1 ), 0 );
    if ($eventType) {
        $result{"eventType"} = $eventType;
        $result{"response"} = extract( find( $msg, "./nmwg:data/nmwg:datum", 1 ), 0 );
        unless ( $result{"response"} ) {
            $result{"response"} = extract( find( $msg, "./nmwg:data/nmwgr:datum", 1 ), 0 );
        }
        if ( $eventType =~ m/^success/mx ) {
            $result{"key"} = extract( find( $msg, "./nmwg:metadata/nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"lsKey\"]", 1 ), 0 );
        }
    }
    return \%result;
}

=head2 registerClobberRequestLS($self, { service, key, data })

Given service information (in the form of a hash reference) and an already 
existing key, create a service/key metadata block and include the data
(in the form of an array reference) into an LS registration message.  The
results of this operation will be a hash of results for each metadata/data
pair.  Note this should be used for 'clobber' existing registration info for 
a service.  Essentually, if we wish to 'start over', use this message type.  It
replaces the need to deregister/register the data set.

=cut

sub registerClobberRequestLS {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { service => 1, key => 1, data => 1 } );

    my $metadata = q{};
    my %ns       = (
        perfsonar => "http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/",
        psservice => "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/"
    );
    $metadata .= $self->createKey( { key => $parameters->{key} } ) . $self->createService( { service => $parameters->{service} } );

    my $msg = $self->callLS( { message => $self->createLSMessage( { type => "LSRegisterRequest", ns => \%ns, metadata => $metadata, data => $parameters->{data} } ) } );
    unless ($msg) {
        $self->{LOGGER}->error("Message element not found in return.");
        return;
    }

    my %result = ();
    my $eventType = extract( find( $msg, "./nmwg:metadata/nmwg:eventType", 1 ), 0 );
    if ($eventType) {
        $result{"eventType"} = $eventType;
        $result{"response"} = extract( find( $msg, "./nmwg:data/nmwg:datum", 1 ), 0 );
        unless ( $result{"response"} ) {
            $result{"response"} = extract( find( $msg, "./nmwg:data/nmwgr:datum", 1 ), 0 );
        }
        if ( $eventType =~ m/^success/mx ) {
            $result{"key"} = extract( find( $msg, "./nmwg:metadata/nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"lsKey\"]", 1 ), 0 );
        }
    }
    return \%result;
}

=head2 deregisterRequestLS($self, { key, data })

Given the key of a registered service, and optional data, deregister either
the data or the entire service.  The results of the operation are returned 
in a hash.

=cut

sub deregisterRequestLS {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { key => 1, data => 0 } );

    my $metadata = q{};
    $metadata .= $self->createKey( { key => $parameters->{key} } );

    my $msg = $self->callLS( { message => $self->createLSMessage( { type => "LSDeregisterRequest", metadata => $metadata, data => $parameters->{data} } ) } );
    unless ($msg) {
        $self->{LOGGER}->error("Message element not found in return.");
        return;
    }

    my %result = ();
    my $eventType = extract( find( $msg, "./nmwg:metadata/nmwg:eventType", 1 ), 0 );
    if ($eventType) {
        $result{"eventType"} = $eventType;
        $result{"response"} = extract( find( $msg, "./nmwg:data/nmwg:datum", 1 ), 0 );
        unless ( $result{"response"} ) {
            $result{"response"} = extract( find( $msg, "./nmwg:data/nmwgr:datum", 1 ), 0 );
        }
    }
    return \%result;
}

=head2 keepaliveRequestLS($self, { key })

Given the key of a registered service, send a 'keepalive' to ensure that the
data TTL does not expire.  The results of the operation are returned in a hash.

=cut

sub keepaliveRequestLS {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { key => 1 } );

    my $metadata = q{};
    $metadata .= $self->createKey( { key => $parameters->{key} } );

    my $msg = $self->callLS( { message => $self->createLSMessage( { type => "LSKeepaliveRequest", metadata => $metadata } ) } );
    unless ($msg) {
        $self->{LOGGER}->error("Message element not found in return.");
        return;
    }

    my %result = ();
    my $eventType = extract( find( $msg, "./nmwg:metadata/nmwg:eventType", 1 ), 0 );
    if ($eventType) {
        $result{"eventType"} = $eventType;
        $result{"response"} = extract( find( $msg, "./nmwg:data/nmwg:datum", 1 ), 0 );
        unless ( $result{"response"} ) {
            $result{"response"} = extract( find( $msg, "./nmwg:data/nmwgr:datum", 1 ), 0 );
        }
    }
    return \%result;
}

=head2 keyRequestLS($self, { service, data })

Given service information (in the form of a hash reference) create a service
metadata block and include the data (in the form of an array reference) into
an LS registration message.  The results of this operation will be a 
hash of results for each metadata/data pair.  Note this should be used for all
'new' service registrations.

=cut

sub keyRequestLS {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { service => 1 } );

    my $metadata = q{};
    my %ns       = (
        perfsonar => "http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/",
        psservice => "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/"
    );
    $metadata .= $self->createService( { service => $parameters->{service} } );

    my $msg = $self->callLS( { message => $self->createLSMessage( { type => "LSKeyRequest", ns => \%ns, metadata => $metadata } ) } );
    unless ($msg) {
        $self->{LOGGER}->error("Message element not found in return.");
        return;
    }

    my %result = ();
    my $eventType = extract( find( $msg, "./nmwg:metadata/nmwg:eventType", 1 ), 0 );
    if ($eventType) {
        $result{"eventType"} = $eventType;
        if ( $eventType =~ m/^success/mx ) {
            $result{"key"} = extract( find( $msg, "./nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"lsKey\"]", 1 ), 0 );
        }
        else {
            $result{"response"} = extract( find( $msg, "./nmwg:data/nmwg:datum", 1 ), 0 );
            unless ( $result{"response"} ) {
                $result{"response"} = extract( find( $msg, "./nmwg:data/nmwgr:datum", 1 ), 0 );
            }
        }
    }
    else {
        $result{"key"} = extract( find( $msg, "./nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"lsKey\"]", 1 ), 0 );
    }
    return \%result;
}

=head2 queryRequestLS($self, { query, format })

Given an xquery/xpath expression, return the results of this query to the
user.  The result could be a status message (i.e. 'no results') or the actual
data from the LS (i.e. xml elements, etc.).  The caller should know how to
handle either result.

=cut

sub queryRequestLS {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { query => 1, format => 0 } );

    my $metadata = q{};
    my %ns = ( xquery => "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xquery/1.0/" );
    $metadata .= "    <xquery:subject id=\"subject." . genuid() . "\" xmlns:xquery=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xquery/1.0/\">\n";
    $metadata .= $parameters->{query};
    $metadata .= "    </xquery:subject>\n";
    $metadata .= "    <nmwg:eventType>http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xquery/1.0</nmwg:eventType>\n";
    if ( exists $parameters->{format} and $parameters->{format} ) {
        $metadata .= "  <xquery:parameters id=\"parameters." . genuid() . "\" xmlns:xquery=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xquery/1.0/\">\n";
        $metadata .= "    <nmwg:parameter name=\"lsOutput\">native</nmwg:parameter>\n";
        $metadata .= "  </xquery:parameters>\n";
    }

    my $msg = $self->callLS( { message => $self->createLSMessage( { type => "LSQueryRequest", ns => \%ns, metadata => $metadata } ) } );
    unless ($msg) {
        $self->{LOGGER}->error("Message element not found in return.");
        return;
    }

    my %result = ();
    my $eventType = extract( find( $msg, "./nmwg:metadata/nmwg:eventType", 1 ), 0 );
    if ($eventType) {
        $result{"eventType"} = $eventType;
        if ( $eventType =~ m/^success/mx ) {
            $result{"response"} = $msg->getChildrenByLocalName("data")->get_node(1)->getChildrenByLocalName("datum")->get_node(1)->toString;
        }
        else {
            $result{"response"} = extract( find( $msg, "./nmwg:data/nmwgr:datum", 1 ), 0 );
            unless ( $result{"response"} ) {
                $result{"response"} = extract( find( $msg, "./nmwg:data/nmwg:datum", 1 ), 0 );
            }
        }
    }
    else {
        $result{"response"} = unescapeString( $msg->getChildrenByLocalName("data")->get_node(1)->getChildrenByLocalName("datum")->get_node(1)->toString );
    }
    return \%result;
}

=head2 createService($self { accessPoint, serviceName, serviceType, serviceDescription })

Construct the service metadata given the values commonly used to make this
xml block (access point, service name, type, and description.  Access point is
the only required element.  The fully constructed service block will be returned
from this function.

=cut

sub createService {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { service => 1 } );

    my $service = "    <perfsonar:subject xmlns:perfsonar=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/\">\n";
    $service = $service . "      <psservice:service xmlns:psservice=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/\">\n";
    $service = $service . "        <psservice:serviceName>" . $parameters->{service}->{serviceName} . "</psservice:serviceName>\n" if ( defined $parameters->{service}->{serviceName} );
    $service = $service . "        <psservice:accessPoint>" . $parameters->{service}->{accessPoint} . "</psservice:accessPoint>\n" if ( defined $parameters->{service}->{accessPoint} );
    $service = $service . "        <psservice:serviceType>" . $parameters->{service}->{serviceType} . "</psservice:serviceType>\n" if ( defined $parameters->{service}->{serviceType} );
    $service = $service . "        <psservice:serviceDescription>" . $parameters->{service}->{serviceDescription} . "</psservice:serviceDescription>\n" if ( defined $parameters->{service}->{serviceDescription} );
    $service = $service . "      </psservice:service>\n";
    $service = $service . "    </perfsonar:subject>\n";
    return $service;
}

=head2 createKey($self { key })

Construct the key metadata given a value for lsKey.  The fully constructed key
will be returned from this function.

=cut

sub createKey {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { key => 1 } );

    my $key = "    <nmwg:key xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\" id=\"key." . genuid() . "\">\n";
    $key .= "      <nmwg:parameters id=\"parameters." . genuid() . "\">\n";
    $key .= "        <nmwg:parameter name=\"lsKey\">" . $parameters->{key} . "</nmwg:parameter>\n";
    $key .= "      </nmwg:parameters>\n";
    $key .= "    </nmwg:key>\n";

    return $key;
}

=head2 createLSMessage($self, { type, metadata, ns, data })

Creates the basic message structure for communication with the LS.  The type
argument is used to insert a message type (LSRegisterRequest,
LSDeregisterRequest, LSKeepaliveRequest, LSKeyRequest, LSQueryRequest).  The
metadata argument must contain metadata (a service block, a key, or an xquery).
The optional ns hash reference can contain namespace to prefix mappings and
the data block can optionally contain data (in the case of register and
deregister messages).  The fully formed message is returned from this function.

=cut

sub createLSMessage {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { type => 1, metadata => 1, ns => 0, data => 0 } );

    my $request = q{};
    my $mdId    = "metadata." . genuid();
    my $dId     = "data." . genuid();
    $request .= "<nmwg:message type=\"" . $parameters->{type} . "\" id=\"message." . genuid() . "\"";
    $request .= " xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"";
    if ( exists $parameters->{ns} and $parameters->{ns} ) {
        foreach my $n ( keys %{ $parameters->{ns} } ) {
            $request .= " xmlns:" . $n . "=\"" . $parameters->{ns}->{$n} . "\"";
        }
    }
    $request .= ">\n";
    $request .= "  <nmwg:metadata id=\"" . $mdId . "\">\n";
    $request .= $parameters->{metadata};
    $request .= "  </nmwg:metadata>\n";
    if ( exists $parameters->{data} and $parameters->{data} ) {
        $request .= "  <nmwg:data metadataIdRef=\"" . $mdId . "\" id=\"" . $dId . "\">\n";
        foreach my $data ( @{ $parameters->{data} } ) {
            $request .= $data;
        }
        $request .= "  </nmwg:data>\n";
    }
    else {
        $request .= "  <nmwg:data metadataIdRef=\"" . $mdId . "\" id=\"" . $dId . "\"/>\n";
    }
    $request .= "</nmwg:message>\n";

    return $request;
}

1;

__END__

=head1 SYNOPSIS

    #!/usr/bin/perl -w

    use strict;
    use warnings;
    use perfSONAR_PS::Client::LS;

    my $ls = new perfSONAR_PS::Client::LS(
      { instance => "http://localhost:8080/perfSONAR_PS/services/LS"}
    );

    my %service = (
      serviceName => "Internet2 SNMP MA",
      serviceType => "MA",
      serviceDescription => "Testing SNMP MA",
      accessPoint => "http://localhost:8080/perfSONAR_PS/services/snmpMA"
    );

    my @rdata = ();
    $rdata[0] .= "    <nmwg:metadata id=\"meta\">\n";
    $rdata[0] .= "      <netutil:subject id=\"subj\" xmlns:netutil=\"http://ggf.org/ns/nmwg/characteristic/utilization/2.0/\">\n";
    $rdata[0] .= "        <nmwgt:interface xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\">\n";
    $rdata[0] .= "          <nmwgt:hostName>localhost</nmwgt:hostName>\n";
    $rdata[0] .= "          <nmwgt:ifName>eth0</nmwgt:ifName>\n";
    $rdata[0] .= "          <nmwgt:ifAddress type=\"ipv4\">127.0.0.1</nmwgt:ifAddress>\n";
    $rdata[0] .= "          <nmwgt:direction>in</nmwgt:direction>\n";
    $rdata[0] .= "        </nmwgt:interface>\n";
    $rdata[0] .= "      </netutil:subject>\n";
    $rdata[0] .= "      <nmwg:eventType>http://ggf.org/ns/nmwg/characteristic/utilization/2.0</nmwg:eventType>\n";
    $rdata[0] .= "    </nmwg:metadata>\n";

    my @rdata2 = ();
    $rdata2[0] .= "    <nmwg:metadata id=\"meta1\">\n";
    $rdata2[0] .= "      <netutil:subject id=\"subj1\" xmlns:netutil=\"http://ggf.org/ns/nmwg/characteristic/utilization/2.0/\">\n";
    $rdata2[0] .= "        <nmwgt:interface xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\">\n";
    $rdata2[0] .= "          <nmwgt:hostName>localhost1</nmwgt:hostName>\n";
    $rdata2[0] .= "          <nmwgt:ifName>eth1</nmwgt:ifName>\n";
    $rdata2[0] .= "          <nmwgt:ifAddress type=\"ipv4\">127.0.1.1</nmwgt:ifAddress>\n";
    $rdata2[0] .= "          <nmwgt:direction>in</nmwgt:direction>\n";
    $rdata2[0] .= "        </nmwgt:interface>\n";
    $rdata2[0] .= "      </netutil:subject>\n";
    $rdata2[0] .= "      <nmwg:eventType>http://ggf.org/ns/nmwg/characteristic/utilization/2.0</nmwg:eventType>\n";
    $rdata2[0] .= "    </nmwg:metadata>\n";

    my $result = q{};
    my $query = q{};
    my $key = q{};

    print "\nFirst we register some data...\n\n";

    $result = $ls->registerRequestLS( { service => \%service, data => \@rdata } );
    if ( $result->{eventType} eq "success.ls.register" ) {
        $key = $result->{key};
        print "Success!  The key is \"" . $key . "\"\n";
        print "Message:\t" . $result->{response} . "\n";
    
        print "\nWhat about a keepalive?\n\n";
    
        $result = $ls->keepaliveRequestLS( { key => $key } );
        if ( $result->{eventType} eq "success.ls.keepalive" ) {
            print "Success!\n";
            print "Message:\t" . $result->{response} . "\n";
       }
        else {
            print "Failed to keepalive.\n";
            print "eventType:\t" . $result->{eventType} . "\nResponse:\t" . $result->{response} , "\n";
        }
    
        print "\nOh no, whats the key again?\n\n";
        $result = $ls->keyRequestLS( { service => \%service } );
        if ( $result->{key} ) {
            print "Thats right, the key was \"" . $result->{key} . "\", try to remember it!\n";
        }
        else {
            print "Service \"" . $service{accessPoint} . "\" is not registered?  That can't be right.\n";
        }

        print "\nWhat is the current data that we have registered?\n\n";    
        $query = "declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\";\n";
        $query .= "/nmwg:store[\@type=\"LSStore\"]/nmwg:data[\@metadataIdRef=\"".$key."\"]\n";
        $result = $ls->queryRequestLS( { query => $query, format => 1 } );
        if( $result->{eventType} =~ m/^error/mx ) {
            print "Something went wrong...\n";
            print "eventType:\t" . $result->{eventType} . "\nResponse:\t" . $result->{response} , "\n";
        } 
        else {
            print "Here it is:\n" . $result->{response} . "\n";
        }

        print "\nI want to add some more data\n\n";
    
        $result = $ls->registerUpdateRequestLS( { key => $key, data => \@rdata2 } );
        if ( $result->{eventType} eq "success.ls.register" ) {
            print "Success!  The key is \"" . $result->{key} . "\"\n";
            print "Message:\t" . $result->{response} . "\n";
        }
        else {
            print "Failed to register.\n";
            print "eventType:\t" . $result->{eventType} . "\nResponse:\t" . $result->{response} , "\n";
        }

        print "\nWhat is the current data that we have registered?\n\n";    
        $query = "declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\";\n";
        $query .= "/nmwg:store[\@type=\"LSStore\"]/nmwg:data[\@metadataIdRef=\"".$key."\"]\n";
        $result = $ls->queryRequestLS( { query => $query, format => 1 } );
        if( $result->{eventType} =~ m/^error/mx ) {
            print "Something went wrong...\n";
            print "eventType:\t" . $result->{eventType} . "\nResponse:\t" . $result->{response} , "\n";
        } 
        else {
            print "Here it is:\n" . $result->{response} . "\n";
        }

        print "\nCan I remove the original data item?\n\n";
        $result = $ls->deregisterRequestLS( { key => $key, data => \@rdata } );
        if ( $result->{eventType} eq "success.ls.deregister" ) {    
            print "Sure you can!\n";
            print "eventType:\t" . $result->{eventType} . "\nResponse:\t" . $result->{response} , "\n";
        }  
        else {
            print "I guess not, someone beat you to it!\n";
            print "eventType:\t" . $result->{eventType} . "\nResponse:\t" . $result->{response} , "\n";
        }  
    
        print "\nWhat if the service name changes, what should I do?\n";
        print "You will need to send the change, the key, and the new dataset...\n\n";
        $service{serviceName} = "changed...";

        $result = $ls->registerClobberRequestLS( { service => \%service, key => $key, data => \@rdata2 } );
        if ( $result->{eventType} eq "success.ls.register" ) {
            my $key = $result->{key};
            print "Success, and here is the new key: \"" . $key . "\"\n";
            print "eventType:\t" . $result->{eventType} . "\nResponse:\t" . $result->{response} , "\n";
        }
        else {
            print "That may have not worked as planned...\n";
            print "eventType:\t" . $result->{eventType} . "\nResponse:\t" . $result->{response} , "\n";
        }

        print "\nLets deregister the whole thing...\n\n";

        $result = $ls->deregisterRequestLS( { key => $key } );
        if ( $result->{eventType} eq "success.ls.deregister" ) {    
            print "Done!\n";
            print "eventType:\t" . $result->{eventType} . "\nResponse:\t" . $result->{response} , "\n";
        }  
        else {
            print "I guess not, someone beat you to it!\n";
            print "eventType:\t" . $result->{eventType} . "\nResponse:\t" . $result->{response} , "\n";
        }  
    }
    else {
        print "Failed to register.\n";
        print "eventType:\t" . $result->{eventType} . "\nResponse:\t" . $result->{response} , "\n";
    }

=head1 SEE ALSO

L<Log::Log4perl>, L<Params::Validate>, L<English>, L<perfSONAR_PS::Common>,
L<perfSONAR_PS::Transport>, L<perfSONAR_PS::Client::Echo>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS

Questions and comments can be directed to the author, or the mailing list.
Bugs, feature requests, and improvements can be directed here:

  https://bugs.internet2.edu/jira/browse/PSPS

=head1 VERSION

$Id$

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework
along with this software.  If not, see
<http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2004-2008, Internet2 and the University of Delaware

All rights reserved.

=cut
