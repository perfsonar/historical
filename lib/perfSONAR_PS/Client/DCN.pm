package perfSONAR_PS::Client::DCN;

use fields 'INSTANCE', 'LOGGER', 'CONF', 'LS_KEY';

use strict;
use warnings;

our $VERSION = 0.07;

=head1 NAME

perfSONAR_PS::Client::DCN - Simple library to implement some perfSONAR calls
that DCN tools will require.

=head1 DESCRIPTION

The goal of this module is to provide some simple library calls that DCN
software may implement to receive information from perfSONAR deployments.

=cut

use Log::Log4perl qw( get_logger );
use Params::Validate qw( :all );
use Digest::MD5 qw( md5_hex );
use English qw( -no_match_vars );

use perfSONAR_PS::Common qw( genuid makeEnvelope find extract );
use perfSONAR_PS::Transport;
use perfSONAR_PS::Client::Echo;

=head2 new($package { instance })

Constructor for object.  Optional argument of 'instance' is the LS instance
to be contacted for queries.  This can also be set via 'setInstance'.

=cut

sub new {
    my ( $package, @args ) = @_;
    my $parameters = validate( @args, { instance => 0 } );

    my $self = fields::new($package);

    $self->{CONF}                        = ();
    $self->{CONF}->{SERVICE_TYPE}        = "MA";
    $self->{CONF}->{SERVICE_NAME}        = "DCN LS";
    $self->{CONF}->{SERVICE_DESCRIPTION} = "Provides DCN Topology Information Mapping";

    $self->{LOGGER} = get_logger("perfSONAR_PS::Client::DCN");
    if ( exists $parameters->{"instance"} and $parameters->{"instance"} ) {
        $self->{INSTANCE}                    = $parameters->{"instance"};
        $self->{CONF}->{SERVICE_ACCESSPOINT} = $parameters->{"instance"};
        $self->{LS_KEY}                      = $self->getLSKey;
    }

    return $self;
}

=head2 setInstance($self { instance })

Required argument 'instance' is the LS instance to be contacted for queries.  

=cut

sub setInstance {
    my ( $self, @args ) = @_;
    my $parameters = validate( @args, { instance => 1 } );

    $self->{INSTANCE}                    = $parameters->{"instance"};
    $self->{CONF}->{SERVICE_ACCESSPOINT} = $parameters->{"instance"};
    $self->{LS_KEY}                      = $self->getLSKey;

    return;
}

=head2 callLS($self { message })

Calls the LS instance with the sent message and returns the response (if any). 

=cut

sub callLS {
    my ( $self, @args ) = @_;
    my $parameters = validate( @args, { message => 1 } );

    unless ( $self->{INSTANCE} ) {
        $self->{LOGGER}->error("Instance not defined.");
        return;
    }

    my $echo_service = perfSONAR_PS::Client::Echo->new( $self->{INSTANCE} );
    my ( $status, $res ) = $echo_service->ping();
    if ( $status == -1 ) {
        $self->{LOGGER}->error( "Ping to " . $self->{INSTANCE} . " failed: $res" );
        return;
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
    return $msg;
}

=head2 getLSKey($self { })

Send an LSKeyRequest to the service to retrive the actual key value for the
registration of the 'DCN' service.

=cut

sub getLSKey {
    my ( $self, @args ) = @_;
    my $parameters = validate( @args, {} );

    my $msg = $self->callLS( { message => $self->createKeyRequest( {} ) } );
    unless ($msg) {
        $self->{LOGGER}->error("Message element not found in return.");
        return;
    }

    my $key = find( $msg, "./nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"lsKey\"]", 0 );
    if ($key) {
        $self->{LS_KEY} = $key;
        return $key;
    }
    return;
}

=head2 getTopologyKey($self { accessPoint serviceName serviceType serviceDescription })

Send an LSKeyRequest to the LS with some service information reguarding a
topology service.  The goal is to get a key, nothing will be returned on
failure.

=cut

sub getTopologyKey {
    my ( $self, @args ) = @_;
    my $parameters = validate( @args, { accessPoint => 1, serviceName => 0, serviceType => 0, serviceDescription => 0 } );

    my $msg = $self->callLS( { message => $self->createKeyRequest( { accessPoint => $parameters->{accessPoint}, serviceName => $parameters->{serviceName}, serviceType => $parameters->{serviceType}, serviceDescription => $parameters->{serviceDescription} } ) } );
    unless ($msg) {
        $self->{LOGGER}->error("Message element not found in return.");
        return;
    }

    my $key = find( $msg, "./nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter[\@name=\"lsKey\"]", 0 );
    if ($key) {
        return $key;
    }
    return;
}

=head2 getDomainKey($self { key })

Get the domain for a topology service given a key.

=cut

sub getDomainKey {
    my ( $self, @args ) = @_;
    my $parameters = validate( @args, { key => 1 } );
    my @domains = ();

    my $query = "declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\";\n";
    $query .= "declare namespace perfsonar=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/\";\n";
    $query .= "declare namespace psservice=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/\";\n";
    $query .= "declare namespace nmtb=\"http://ogf.org/schema/network/topology/base/20070828/\";\n";

    $query .= "for \$metadata in /nmwg:store[\@type=\"LSStore\"]/nmwg:metadata\n";
    $query .= "  let \$metadata_id := \$metadata/\@id\n";
    $query .= "  let \$data := /nmwg:store[\@type=\"LSStore\"]/nmwg:data[\@metadataIdRef=\$metadata_id]\n";
    $query .= "  where \$metadata_id=\"" . $parameters->{key} . "\"\n";
    $query .= "  return \$data/nmwg:metadata/nmwg:subject/nmtb:domain\n\n";

    my $msg = $self->callLS( { message => $self->createQueryRequest( { query => $query } ) } );
    unless ($msg) {
        $self->{LOGGER}->error("Message element not found in return.");
        return;
    }

    my $ds = find( $msg, "./nmwg:data/psservice:datum/nmtb:domain", 0 );
    if ($ds) {
        foreach my $d ( $ds->get_nodelist ) {
            my $value = $d->getAttribute("id");
            $value =~ s/urn:ogf:network:domain=//xm;
            push @domains, $value if $value;
        }
    }
    else {
        $self->{LOGGER}->error("No domain elements found in return.");
        return;
    }

    return \@domains;
}

=head2 getDomainService($self { accessPoint, serviceName, serviceType })

Get the domain of a topology service given service information

=cut

sub getDomainService {
    my ( $self, @args ) = @_;
    my $parameters = validate( @args, { accessPoint => 1, serviceName => 0, serviceType => 0 } );
    my @domains = ();

    my $query = "declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\";\n";
    $query .= "declare namespace perfsonar=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/\";\n";
    $query .= "declare namespace psservice=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/\";\n";
    $query .= "declare namespace nmtb=\"http://ogf.org/schema/network/topology/base/20070828/\";\n\n";

    $query .= "for \$metadata in /nmwg:store[\@type=\"LSStore\"]/nmwg:metadata\n";
    $query .= "  let \$metadata_id := \$metadata/\@id\n";
    $query .= "  let \$data := /nmwg:store[\@type=\"LSStore\"]/nmwg:data[\@metadataIdRef=\$metadata_id]\n";
    $query .= "  where \$metadata/perfsonar:subject/psservice:service/psservice:accessPoint[text()=\"" . $parameters->{accessPoint} . "\"]\n";
    if ( $parameters->{serviceType} ) {
        $query .= "        and \$metadata/perfsonar:subject/psservice:service/psservice:serviceType[text()=\"" . $parameters->{serviceType} . "\"]\n";
    }
    if ( $parameters->{serviceName} ) {
        $query .= "        and \$metadata/perfsonar:subject/psservice:service/psservice:serviceName[text()=\"" . $parameters->{serviceName} . "\"]\n";
    }
    $query .= "  return \$data/nmwg:metadata/nmwg:subject/nmtb:domain\n\n";

    my $msg = $self->callLS( { message => $self->createQueryRequest( { query => $query } ) } );
    unless ($msg) {
        $self->{LOGGER}->error("Message element not found in return.");
        return;
    }

    my $ds = find( $msg, "./nmwg:data/psservice:datum/nmtb:domain", 0 );
    if ($ds) {
        foreach my $d ( $ds->get_nodelist ) {
            my $value = $d->getAttribute("id");
            $value =~ s/urn:ogf:network:domain=//xm;
            push @domains, $value if $value;
        }
    }
    else {
        $self->{LOGGER}->error("No domain elements found in return.");
        return;
    }

    return \@domains;
}

=head2 nameToId

Given a name (i.e. DNS 'hostname') return any matching link ids.

=cut

sub nameToId {
    my ( $self, @args ) = @_;
    my $parameters = validate( @args, { name => 1 } );
    my @ids = ();

    my $query = "declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\";\n";
    $query .= "declare namespace nmtb=\"http://ogf.org/schema/network/topology/base/20070828/\";\n";
    $query .= "/nmwg:store[\@type=\"LSStore\"]/nmwg:data/nmtb:node[nmtb:address/text()=\"" . $parameters->{name} . "\"]\n";

    my $msg = $self->callLS( { message => $self->createQueryRequest( { query => $query } ) } );
    unless ($msg) {
        $self->{LOGGER}->error("Message element not found in return.");
        return;
    }

    my $links = find( $msg, ".//psservice:datum/nmtb:node/nmtb:relation[\@type=\"connectionLink\"]/nmtb:linkIdRef", 0 );
    if ($links) {
        foreach my $l ( $links->get_nodelist ) {
            my $value = extract( $l, 0 );
            push @ids, $value if $value;
        }
    }
    else {
        $self->{LOGGER}->error("No link elements found in return.");
        return;
    }

    return \@ids;
}

=head2 idToName

Given a link id return any matching names (i.e. DNS 'hostname').

=cut

sub idToName {
    my ( $self, @args ) = @_;
    my $parameters = validate( @args, { id => 1 } );
    my @names = ();

    my $query = "declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\";\n";
    $query .= "declare namespace nmtb=\"http://ogf.org/schema/network/topology/base/20070828/\";\n";
    $query .= "/nmwg:store[\@type=\"LSStore\"]/nmwg:data/nmtb:node[nmtb:relation[\@type=\"connectionLink\"]/nmtb:linkIdRef[text()=\"" . $parameters->{id} . "\"]]\n";

    my $msg = $self->callLS( { message => $self->createQueryRequest( { query => $query } ) } );
    unless ($msg) {
        $self->{LOGGER}->error("Message element not found in return.");
        return;
    }

    my $hostnames = find( $msg, ".//psservice:datum/nmtb:node/nmtb:address[\@type=\"hostname\"]", 0 );
    if ($hostnames) {
        foreach my $hn ( $hostnames->get_nodelist ) {
            my $value = extract( $hn, 0 );
            push @names, $value if $value;
        }
    }
    else {
        $self->{LOGGER}->error("No name elements found in return.");
        return;
    }

    return \@names;
}

=head2 insert($self { id name })

Given an id AND a name, register this infomration to the LS instance.

=cut

sub insert {
    my ( $self, @args ) = @_;
    my $parameters = validate( @args, { id => 1, name => 1 } );

    unless ( $self->{LS_KEY} ) {
        $self->{LS_KEY} = $self->getLSKey;
    }

    my $msg = $self->callLS( { message => $self->createRegisterRequest( { id => $parameters->{id}, name => $parameters->{name} } ) } );
    unless ($msg) {
        $self->{LOGGER}->error("Message element not found in return.");
        return -1;
    }

    my $code  = extract( find( $msg, "./nmwg:metadata/nmwg:eventType",        1 ), 0 );
    my $datum = extract( find( $msg, "./nmwg:data/*[local-name()=\"datum\"]", 1 ), 0 );
    if ( defined $code and $code =~ m/success/xm ) {
        $self->{LOGGER}->info($datum) if $datum;
        if ( $datum =~ m/^\s*\[\d+\] Data elements/m ) {
            my $num = $datum;
            $num =~ s/^\[//xm;
            $num =~ s/\].*//xm;
            if ( $num > 0 ) {
                return 0;
            }
        }
        return -1;
    }
    $self->{LOGGER}->error($datum) if $datum;
    return -1;
}

=head2 remove($self { id name })

Given an id or a name, delete this specific info from the LS instance.

=cut

sub remove {
    my ( $self, @args ) = @_;
    my $parameters = validate( @args, { id => 0, name => 0 } );

    unless ( $parameters->{id} or $parameters->{name} ) {
        $self->{LOGGER}->error("Must supply either a name or id.");
        return -1;
    }

    unless ( $self->{LS_KEY} ) {
        $self->{LS_KEY} = $self->getLSKey;
    }

    if ( $self->{LS_KEY} ) {
        my $msg = $self->callLS( { message => $self->createDeregisterRequest( { id => $parameters->{id}, name => $parameters->{name} } ) } );
        unless ($msg) {
            $self->{LOGGER}->error("Message element not found in return.");
            return -1;
        }

        my $code  = extract( find( $msg, "./nmwg:metadata/nmwg:eventType",        1 ), 0 );
        my $datum = extract( find( $msg, "./nmwg:data/*[local-name()=\"datum\"]", 1 ), 0 );
        if ( defined $code and $code =~ m/success/xm ) {
            $self->{LOGGER}->info($datum) if $datum;
            if ( $datum =~ m/^Removed/xm ) {
                my $num = $datum;
                $num =~ s/^Removed\s{1}\[//xm;
                $num =~ s/\].*//xm;
                if ( $num > 0 ) {
                    return 0;
                }
            }
            return -1;
        }
        else {
            $self->{LOGGER}->error($datum) if $datum;
            return -1;
        }
    }

    return -1;
}

=head2 createService($self { })

Construct the service metadata given the default values for this module. 

=cut

sub createService {
    my ( $self, @args ) = @_;
    my $parameters = validate( @args, { accessPoint => 0, serviceName => 0, serviceType => 0, serviceDescription => 0 } );

    my $service = "    <perfsonar:subject xmlns:perfsonar=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/\">\n";
    $service = $service . "      <psservice:service xmlns:psservice=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/\">\n";
    if (   $parameters->{accessPoint}
        or $parameters->{serviceName}
        or $parameters->{serviceType}
        or $parameters->{serviceDescription} )
    {
        $service = $service . "        <psservice:serviceName>" . $parameters->{serviceName} . "</psservice:serviceName>\n"                      if ( defined $parameters->{serviceName} );
        $service = $service . "        <psservice:accessPoint>" . $parameters->{accessPoint} . "</psservice:accessPoint>\n"                      if ( defined $parameters->{accessPoint} );
        $service = $service . "        <psservice:serviceType>" . $parameters->{serviceType} . "</psservice:serviceType>\n"                      if ( defined $parameters->{serviceType} );
        $service = $service . "        <psservice:serviceDescription>" . $parameters->{serviceDescription} . "</psservice:serviceDescription>\n" if ( defined $parameters->{serviceDescription} );
    }
    else {
        $service = $service . "        <psservice:serviceName>" . $self->{CONF}->{SERVICE_NAME} . "</psservice:serviceName>\n"                      if ( defined $self->{CONF}->{"SERVICE_NAME"} );
        $service = $service . "        <psservice:accessPoint>" . $self->{CONF}->{SERVICE_ACCESSPOINT} . "</psservice:accessPoint>\n"               if ( defined $self->{CONF}->{"SERVICE_ACCESSPOINT"} );
        $service = $service . "        <psservice:serviceType>" . $self->{CONF}->{SERVICE_TYPE} . "</psservice:serviceType>\n"                      if ( defined $self->{CONF}->{"SERVICE_TYPE"} );
        $service = $service . "        <psservice:serviceDescription>" . $self->{CONF}->{SERVICE_DESCRIPTION} . "</psservice:serviceDescription>\n" if ( defined $self->{CONF}->{"SERVICE_DESCRIPTION"} );
    }
    $service = $service . "      </psservice:service>\n";
    $service = $service . "    </perfsonar:subject>\n";
    return $service;
}

=head2 createKey($self { })

Construct the key metadata given the default values for this module. 

=cut

sub createKey {
    my ( $self, @args ) = @_;
    my $parameters = validate( @args, {} );

    my $key = "    <nmwg:key xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\" id=\"key." . genuid() . "\">\n";
    $key .= "      <nmwg:parameters id=\"parameters." . genuid() . "\">\n";
    $key .= "        <nmwg:parameter name=\"lsKey\">" . $self->{LS_KEY} . "</nmwg:parameter>\n";
    $key .= "      </nmwg:parameters>\n";
    $key .= "    </nmwg:key>\n";

    return $key;
}

=head2 createNode($self { id name })

Construct a node given an id and a name.

=cut

sub createNode {
    my ( $self, @args ) = @_;
    my $parameters = validate( @args, { id => 0, name => 0 } );

    unless ( $parameters->{id} or $parameters->{name} ) {
        $self->{LOGGER}->error("Must supply either a name or id.");
        return -1;
    }

    my $id   = md5_hex( $parameters->{name} . $parameters->{id} );
    my $node = "<nmtb:node xmlns:nmtb=\"http://ogf.org/schema/network/topology/base/20070828/\" id=\"node." . $id . "\">\n";
    $node .= "  <nmtb:address type=\"hostname\">" . $parameters->{name} . "</nmtb:address>\n" if ( $parameters->{name} );
    if ( $parameters->{id} ) {
        $node .= "  <nmtb:relation type=\"connectionLink\">\n";
        $node .= "    <nmtb:linkIdRef>" . $parameters->{id} . "</nmtb:linkIdRef>\n";
        $node .= "  </nmtb:relation>\n";
    }
    $node .= "</nmtb:node>\n";

    return $node;
}

=head2 createQueryRequest($self { query })

Construct a query message for the LS, supplying the specifics of the query to
this function.  

=cut

sub createQueryRequest {
    my ( $self, @args ) = @_;
    my $parameters = validate( @args, { query => 1 } );

    my $request = q{};
    my $mdId    = "metadata." . genuid();
    $request .= "<nmwg:message type=\"LSQueryRequest\" id=\"message." . genuid() . "\"\n";
    $request .= "              xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"\n";
    $request .= "              xmlns:xquery=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xquery/1.0/\">\n";
    $request .= "  <nmwg:metadata id=\"" . $mdId . "\">\n";
    $request .= "    <xquery:subject id=\"subject." . genuid() . "\">\n";
    $request .= $parameters->{query};
    $request .= "    </xquery:subject>\n";
    $request .= "    <nmwg:eventType>http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xquery/1.0</nmwg:eventType>\n";
    $request .= "  <xquery:parameters id=\"parameters." . genuid() . "\">\n";
    $request .= "    <nmwg:parameter name=\"lsOutput\">native</nmwg:parameter>\n";
    $request .= "  </xquery:parameters>\n";
    $request .= "  </nmwg:metadata>\n";
    $request .= "  <nmwg:data metadataIdRef=\"" . $mdId . "\" id=\"data." . genuid() . "\"/>\n";
    $request .= "</nmwg:message>\n";

    return $request;
}

=head2 createDeregisterRequest($self {  })

Construct a de-registraton message for the LS, supplying the specifics of
the information to remove.

=cut

sub createDeregisterRequest {
    my ( $self, @args ) = @_;
    my $parameters = validate( @args, { id => 0, name => 0 } );

    unless ( $parameters->{id} or $parameters->{name} ) {
        $self->{LOGGER}->error("Must supply either a name or id.");
        return -1;
    }

    unless ( $self->{LS_KEY} ) {
        $self->{LS_KEY} = $self->getLSKey;
    }

    my $request = q{};
    if ( $self->{LS_KEY} ) {
        my $mdId = "metadata." . genuid();
        $request .= "<nmwg:message type=\"LSDeregisterRequest\" id=\"message." . genuid() . "\"\n";
        $request .= "              xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"\n";
        $request .= "              xmlns:xquery=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xquery/1.0/\">\n";
        $request .= "  <nmwg:metadata id=\"" . $mdId . "\">\n";
        $request .= $self->createKey;
        $request .= "  </nmwg:metadata>\n";
        $request .= "  <nmwg:data metadataIdRef=\"" . $mdId . "\" id=\"data." . genuid() . "\">\n";
        $request .= $self->createNode( { id => $parameters->{id}, name => $parameters->{name} } );
        $request .= "  </nmwg:data>\n";
        $request .= "</nmwg:message>\n";
    }

    return $request;
}

=head2 createRegisterRequest($self {  })

Construct a registration message for the LS, supplying the specifics of the
mapping to register.

=cut

sub createRegisterRequest {
    my ( $self, @args ) = @_;
    my $parameters = validate( @args, { id => 1, name => 1 } );

    unless ( $self->{LS_KEY} ) {
        $self->{LS_KEY} = $self->getLSKey;
    }

    my $request = q{};
    my $mdId    = "metadata." . genuid();
    $request .= "<nmwg:message type=\"LSRegisterRequest\" id=\"message." . genuid() . "\"\n";
    $request .= "              xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"\n";
    $request .= "              xmlns:xquery=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xquery/1.0/\">\n";
    $request .= "  <nmwg:metadata id=\"" . $mdId . "\">\n";
    if ( $self->{LS_KEY} ) {
        $request .= $self->createKey;
    }
    else {
        $request .= $self->createService;
    }
    $request .= "  </nmwg:metadata>\n";
    $request .= "  <nmwg:data metadataIdRef=\"" . $mdId . "\" id=\"data." . genuid() . "\">\n";
    $request .= $self->createNode( { id => $parameters->{id}, name => $parameters->{name} } );
    $request .= "  </nmwg:data>\n";
    $request .= "</nmwg:message>\n";

    return $request;
}

=head2 createRegisterRequest($self {  })

Construct a registration message for the LS, supplying the specifics of the
mapping to register.

=cut

sub createKeyRequest {
    my ( $self, @args ) = @_;
    my $parameters = validate( @args, { accessPoint => 0, serviceName => 0, serviceType => 0, serviceDescription => 0 } );

    my $request = q{};
    my $mdId    = "metadata." . genuid();
    $request .= "<nmwg:message type=\"LSKeyRequest\" id=\"message." . genuid() . "\"\n";
    $request .= "              xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"\n";
    $request .= "              xmlns:xquery=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xquery/1.0/\">\n";
    $request .= "  <nmwg:metadata id=\"" . $mdId . "\">\n";
    $request .= $self->createService( { accessPoint => $parameters->{accessPoint}, serviceName => $parameters->{serviceName}, serviceType => $parameters->{serviceType}, serviceDescription => $parameters->{serviceDescription} } );
    $request .= "  </nmwg:metadata>\n";
    $request .= "  <nmwg:data metadataIdRef=\"" . $mdId . "\" id=\"data." . genuid() . "\"/>\n";
    $request .= "</nmwg:message>\n";

    return $request;
}

1;

__END__

=head1 SYNOPSIS

    #!/usr/bin/perl -w

    use perfSONAR_PS::Client::DCN;
    my $name = "some.hostname.edu";
    my $id = "urn:ogf:network:domain=some.info.about.this.link"
 
    # Get link id values given a host name
    # 
    my $ids = $dcn->nameToId({ name => $name });
    foreach my $i (@$ids) {
      print $name , "\t=\t" , $i , "\n";
    }
    
    # Get host names given link id values
    #
    my $names = $dcn->idToName( { id => $id } );
    foreach my $n (@$names) {
      print $id , "\t=\t" , $n , "\n";
    }
  
    # The DCN module has associated 'registration' info to make it act like
    # a service.  This info will be registered with an LS, and will have a key
    # associated with it.  This call will get that key from the LS.
    # 
    my $key = $dcn->getLSKey;
    print "The DCN registration key is \"" , $key , "\".\n" if($key);

    # Like the previous call, get us the key for some other service.
    # 
    $key = $dcn->getTopologyKey({ accessPoint => "http://some.topology.service.edu:8080/perfSONAR_PS/services/topology" });
    print "Found key \"" , $key , "\" for topology service.\n" if($key);
    
    # Remove an entry from the LS given the host name and link id
    # 
    my $code = $dcn->remove({ name => $name, id => $id });
    print "Removal of \"".$name."\" and \"".$id."\" failed.\n" if($code == -1);
    
    # Insert a new entry into the LS given a host name and link id
    # 
    $code = $dcn->insert({ name => $name, id => $id });
    print "Insert of \"".$name."\" and \"".$id."\" failed.\n" if($code == -1);

    # Get the domain a particular topology service is responsible for given
    # the LS key that corresponds to the service
    # 
    my $domains = $dcn->getDomainKey({ key => "$key" });
    foreach my $d (@$domains) {
      print "Domain:\t" , $d , "\n";
    }

    # Get the domain a particular topology service is responsible for given
    # the service information of the service
    # 
    $domains = $dcn->getDomainService({ accessPoint => "http://some.topology.service.edu:8080/perfSONAR_PS/services/topology", serviceType => "MA" });
    foreach my $d (@$domains) {
      print "Domain:\t" , $d , "\n";
    }

    exit(1);
    
=head1 SEE ALSO

L<Log::Log4perl>, L<Params::Validate>, L<Digest::MD5>, L<XML::LibXML>,
L<English>, L<perfSONAR_PS::Common>, L<perfSONAR_PS::Transport>,
L<perfSONAR_PS::Client::Echo>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS

Questions and comments can be directed to the author, or the mailing list.  Bugs,
feature requests, and improvements can be directed here:

  https://bugs.internet2.edu/jira/browse/PSPS

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

