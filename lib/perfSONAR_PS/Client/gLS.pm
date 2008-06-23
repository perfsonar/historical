package perfSONAR_PS::Client::gLS;

use fields 'ROOTS', 'HINTS', 'LOGGER';

use strict;
use warnings;

our $VERSION = 0.10;

=head1 NAME

perfSONAR_PS::Client::gLS - API for interacting with the gLS and hLS instances
to take some of the mystery out of queries.  

=head1 DESCRIPTION

The API identifies several common functions that will be of use to clients and
services in the perfSONAR framework for extracting information from the gLS.

=cut

use Log::Log4perl qw( get_logger );
use Params::Validate qw( :all );
use English qw( -no_match_vars );
use LWP::Simple;
use Net::Ping;
use XML::LibXML;

use perfSONAR_PS::ParameterValidation;
use perfSONAR_PS::Client::Echo;
use perfSONAR_PS::Client::LS;
use perfSONAR_PS::Common qw( genuid find extract );

=head2 new( $package, { url } )

Create new object, set the gls.hints URL and call init if applicable.

=cut

sub new {
    my ( $package, @args ) = @_;
    my $parameters = validateParams( @args, { url => 0 } );

    my $self = fields::new($package);
    $self->{LOGGER} = get_logger("perfSONAR_PS::Client::gLS");
    if ( exists $parameters->{"url"} ) {
        if ( $parameters->{"url"} =~ m/^http:\/\// ) {
            $self->{HINTS} = $parameters->{"url"};
            $self->init();
        }
        else {
            $self->{LOGGER}->error("URL must be of the form http://ADDRESS.");
        }
    }
    return $self;
}

=head2 setURL( $self, { url } )

Set the gls.hints url and call init if applicable.

=cut

sub setURL {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { url => { type => Params::Validate::SCALAR } } );
    if ( $parameters->{"url"} =~ m/^http:\/\// ) {
        $self->{HINTS} = $parameters->{"url"};
        $self->init();
    }
    else {
        $self->{LOGGER}->error("URL must be of the form http://ADDRESS.");
        return -1;
    }
    return 0;
}

=head2 init( $self, { } )

Used to extract gLS instances from some hints file, order the resulting gLS
instances by connectivity.

=cut

sub init {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, {} );

    my $content = get $self->{HINTS};
    if ($content) {
        my @roots = split( /\n/, $content );
        $self->orderRoots( { roots => \@roots } );
    }
    else {
        $self->{LOGGER}->error( "There was an error accessing " . $self->{HINTS} . "." );
        return -1;
    }
    return 0;
}

=head2 orderRoots( $self, { roots } )

For each gLS root in the gls.hints file, check to see if the service is
available, then order the resulting services by latency.

=cut

sub orderRoots {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { roots => 0 } );

    my @roots = ();
    if ( exists $parameters->{roots} ) {
        @roots = @{ $parameters->{roots} };
    }
    else {
        @roots = @{ $self->{ROOTS} };
    }
    undef $self->{ROOTS};

    my %list = ();
    my $ping = Net::Ping->new();
    $ping->hires();
    foreach my $root (@roots) {
        $root =~ s/\s+//g;
        unless (  $self->verifyURL( { url => $root } ) == -1 ) {
            my $host = $root;
            $host =~ s/^http:\/\///;
            $host =~ s/:.*//;
            my ( $ret, $duration, $ip ) = $ping->ping($host);
            $list{$duration} = $root if $ret;
        }
    }
    $ping->close();

    foreach my $time ( sort keys %list ) {
        push @{ $self->{ROOTS} }, $list{$time};
    }
    return;
}

=head2 verifyURL( $self, { url } )

Given a url, see if it is contactable via the echo interface.

=cut

sub verifyURL {
    my ( $self, @args ) = @_;
    my $parameters = validateParams(
        @args,
        {
            url =>  { type => Params::Validate::SCALAR }
        }
    );
    
    if ( $parameters->{url} =~ m/^http:\/\// ) {
        my $echo_service = perfSONAR_PS::Client::Echo->new( $parameters->{url} );
        my ( $status, $res ) = $echo_service->ping();
        if( $status > -1 ) {
            return 0;
        }
    }
    else {
        $self->{LOGGER}->error( "URL must be of the form http://ADDRESS." );
    }    
    return -1;
}

=head2 ( $self, { } )

Extract the first usable root element.  In the event you exhaust the list, try
again.

=cut

sub getRoot {
    my ( $self, @args ) = @_;
    my $parameters = validateParams(
        @args,
        { }
    );
    
    my $flag = 0;
    while ( $flag <= 1 ) {
        foreach my $root ( @{ $self->{ROOTS} } ) {
            my $echo_service = perfSONAR_PS::Client::Echo->new($root);
            my ( $status, $res ) = $echo_service->ping();
            return $root if $status != -1;
        } 
        $self->init();
        $flag++;
    }
    return;
}

=head2 createSummaryMetadata( $self, { addresses, domains, eventTypes } )

Given the data items of the summary metadata (addresses, domains, eventTypes), 
create and return this XML.

=cut

sub createSummaryMetadata {
    my ( $self, @args ) = @_;
    my $parameters = validateParams(
        @args,
        {
            addresses  => { type => Params::Validate::ARRAYREF },
            domains    => { type => Params::Validate::ARRAYREF },
            eventTypes => { type => Params::Validate::ARRAYREF }
        }
    );

    my $subject = "    <summary:subject id=\"subject." . genuid() . "\" xmlns:summary=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/summarization/2.0/\">\n";
    foreach my $addr ( @{ $parameters->{addresses} } ) {
        if ( ref($addr) eq "ARRAY" ) {
            if ( $addr->[0] and $addr->[1] ) {
                $subject .= "      <nmtb:address xmlns:nmtb=\"http://ogf.org/schema/network/topology/base/20070828/\" type=\"" . $addr->[1] . "\">" . $addr->[0] . "</nmtb:address>\n";
            }
            else {
                $subject .= "      <nmtb:address xmlns:nmtb=\"http://ogf.org/schema/network/topology/base/20070828/\" type=\"ipv4\">" . $addr->[0] . "</nmtb:address>\n";
            }
        }
        else {
            $subject .= "      <nmtb:address xmlns:nmtb=\"http://ogf.org/schema/network/topology/base/20070828/\" type=\"ipv4\">" . $addr . "</nmtb:address>\n";
        }
    }
    foreach my $domain ( @{ $parameters->{domains} } ) {
        $subject .= "      <nmtb:domain xmlns:nmtb=\"http://ogf.org/schema/network/topology/base/20070828/\">\n";
        $subject .= "        <nmtb:name type=\"dns\">" . $domain . "</nmtb:name>\n";
        $subject .= "      </nmtb:domain>\n";
    }
    foreach my $eT ( @{ $parameters->{eventTypes} } ) {
        $subject .= "      <nmwg:eventType>" . $eT . "</nmwg:eventType>\n";
    }
    $subject .= "    </summary:subject>\n";

    return $subject;
}

=head2 LEVEL 0 API

The following functions are classified according to the gLS design document
as existing in "Level 0".

=head3 getLSDiscoverRaw( $self, { ls, xquery } )

Perform the given XQuery on the root, or if supplied, some other LS instance.
This query is destined for the Summary data set by virtue of the eventType
that is used. Both gLS and hLS instances have this summary dataset, but gLS
instances are understood to know about much more.

=cut

sub getLSDiscoverRaw {
    my ( $self, @args ) = @_;
    my $parameters = validateParams(
        @args,
        {
            ls     => 0,
            xquery => { type => Params::Validate::SCALAR }
        }
    );
    my $ls = perfSONAR_PS::Client::LS->new();

    if ( exists $parameters->{ls} and $parameters->{ls} =~ m/^http:\/\// ) {
        unless ( $self->verifyURL( { url => $parameters->{ls} } ) == 0 ) {
            $self->{LOGGER}->error( "Supplied server \"".$parameters->{ls}."\" could not be contacted." );
            return; 
        }
        $ls->setInstance( { instance => $parameters->{ls} } );
    }
    else {
        my $ls_instance = $self->getRoot();
        unless ( $ls_instance ) {
            $self->{LOGGER}->error( "gLS Root servers could not be contacted." );
            return; 
        }        
        $ls->setInstance( { instance => $ls_instance } );
    }

    my $eventType = "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/discovery/xquery/2.0";
    my $result = $ls->queryRequestLS( { query => $parameters->{xquery}, format => 1, eventType => $eventType } );
    return $result;
}

=head3 getLSDiscoverRaw( $self, { ls, xquery } )

Perform the given XQuery on some LS instance.  This query is destined for the
regular data set by virtue of the eventType that is used. Both gLS and hLS
instances have this dataset, but gLS instances are understood to not accept
common service registration, while hLS instances will.

=cut

sub getLSQueryRaw {
    my ( $self, @args ) = @_;
    my $parameters = validateParams(
        @args,
        {
            ls     => { type => Params::Validate::SCALAR },
            xquery => { type => Params::Validate::SCALAR }
        }
    );

    my $result;
    my $ls = perfSONAR_PS::Client::LS->new();
    if ( $parameters->{ls} =~ m/^http:\/\// ) {
        unless ( $self->verifyURL( { url => $parameters->{ls} } ) == 0 ) {
            $self->{LOGGER}->error( "Supplied server \"".$parameters->{ls}."\" could not be contacted." );
            return; 
        }
        $ls->setInstance( { instance => $parameters->{ls} } );
    }
    else {
        $self->{LOGGER}->error("LS myst be of the form http://ADDRESS.");
        return $result;
    }

    my $eventType = "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/query/xquery/2.0";
    $result = $ls->queryRequestLS( { query => $parameters->{xquery}, format => 1, eventType => $eventType } );
    return $result;
}

=head3 getLSDiscoverControlRaw( $self, { ls, xquery } )

Not implemented.

=cut

=head3 getLSQueryControlRaw( $self, { ls, xquery } )

Not implemented.

=cut

=head2 LEVEL 1 API

The following functions are classified according to the gLS design document
as existing in "Level 0".

=head3 getLSDiscovey( $self, { ls, addresses, domains, eventTypes, service } )

Perform discovery on the gLS, or if applicable on the supplied (g|h)LS, and the
supplied arguments:

 - array of arrays of ip addresses: ( ( ADDRESS, "ipv4"), ( ADDRESS, "ipv6") )
 - array of domains: ( "edu", "udel.edu" )
 - array of eventTypes: ( http://ggf.org/ns/nmwg/tools/owamp/2.0" )
 - hash of service variables: ( 
   { 
     serviceType => "MA", 
     psservice:serviceType => "MA" 
   } 
 )

The result is a list of URLs that correspond to hLS instances to contact for
more information.

=cut

sub getLSDiscovey {
    my ( $self, @args ) = @_;
    my $parameters = validateParams(
        @args,
        {
            ls         => 0,
            addresses  => { type => Params::Validate::ARRAYREF },
            domains    => { type => Params::Validate::ARRAYREF },
            eventTypes => { type => Params::Validate::ARRAYREF },
            service    => { type => Params::Validate::HASHREF }
        }
    );

    my $ls = perfSONAR_PS::Client::LS->new();
    if ( exists $parameters->{ls} and $parameters->{ls} =~ m/^http:\/\// ) {
        unless ( $self->verifyURL( { url => $parameters->{ls} } ) == 0 ) {
            $self->{LOGGER}->error( "Supplied server \"".$parameters->{ls}."\" could not be contacted." );
            return; 
        }
        $ls->setInstance( { instance => $parameters->{ls} } );
    }
    else {
        my $ls_instance = $self->getRoot();
        unless ( $ls_instance ) {
            $self->{LOGGER}->error( "gLS Root servers could not be contacted." );
            return; 
        }        
        $ls->setInstance( { instance => $ls_instance } );
    }

    my $subject = $self->createSummaryMetadata(
        {
            addresses  => $parameters->{addresses},
            domains    => $parameters->{domains},
            eventTypes => $parameters->{eventTypes}
        }
    );

    my @urls      = ();
    my %list      = ();
    my $eventType = "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/discovery/summary/2.0";
    my $result    = $ls->queryRequestLS( { subject => $subject, eventType => $eventType } );
    if ( exists $result->{eventType} and $result->{eventType} eq "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/discovery/summary/2.0" ) {
        if ( exists $result->{response} and $result->{response} ) {
            my $parser  = XML::LibXML->new();
            my $doc     = $parser->parse_string( $result->{response} );
            my $service = find( $doc->getDocumentElement, ".//nmwg:data/nmwg:metadata/perfsonar:subject/psservice:service", 0 );
            foreach my $s ( $service->get_nodelist ) {
                my $flag = 1;
                foreach my $element ( keys %{ $parameters->{service} } ) {
                    my $value = q{};
                    if ( $element =~ m/:/ ) {
                        $value = extract( find( $s, "./" . $element . "[text()=\"" . $parameters->{service}->{$element} . "\" or value=\"" . $parameters->{service}->{$element} . "\"]", 1 ), 0 );
                        unless ($value) {
                            $flag = 0;
                            last;
                        }
                    }
                    else {
                        $value = extract( find( $s, "./*[local-name()='" . $element . "' and (text()=\"" . $parameters->{service}->{$element} . "\" or value=\"" . $parameters->{service}->{$element} . "\")]", 1 ), 0 );
                        unless ($value) {
                            $flag = 0;
                            last;
                        }
                    }
                }
                if ($flag) {
                    my $value = extract( find( $s, "./psservice:accessPoint", 1 ), 0 );
                    push @urls, $value if $value and ( not exists $list{$value} );
                    $list{$value}++;
                }
            }
        }
    }
    return \@urls;
}

=head3 getLSQueryLocation( $self, { ls, addresses, domains, eventTypes, service } )

Perform query on the supplied hLS and using the supplied arguments:

 - array of arrays of ip addresses: ( ( ADDRESS, "ipv4"), ( ADDRESS, "ipv6") )
 - array of domains: ( "edu", "udel.edu" )
 - array of eventTypes: ( http://ggf.org/ns/nmwg/tools/owamp/2.0" )
 - hash of service variables: ( 
   { 
     serviceType => "MA", 
     psservice:serviceType => "MA" 
   } 
 )

The result is a list of Service elements (service XML) of services to contact
for more information.

=cut

sub getLSQueryLocation {
    my ( $self, @args ) = @_;
    my $parameters = validateParams(
        @args,
        {
            ls         => { type => Params::Validate::SCALAR },
            addresses  => { type => Params::Validate::ARRAYREF },
            domains    => { type => Params::Validate::ARRAYREF },
            eventTypes => { type => Params::Validate::ARRAYREF },
            service    => { type => Params::Validate::HASHREF }
        }
    );

    my @service = ();
    my $ls      = perfSONAR_PS::Client::LS->new();
    if ( $parameters->{ls} =~ m/^http:\/\// ) {
        unless ( $self->verifyURL( { url => $parameters->{ls} } ) == 0 ) {
            $self->{LOGGER}->error( "Supplied server \"".$parameters->{ls}."\" could not be contacted." );
            return; 
        }
        $ls->setInstance( { instance => $parameters->{ls} } );
    }
    else {
        $self->{LOGGER}->error("LS myst be of the form http://ADDRESS.");
        return \@service;
    }

    my $subject = $self->createSummaryMetadata(
        {
            addresses  => $parameters->{addresses},
            domains    => $parameters->{domains},
            eventTypes => $parameters->{eventTypes}
        }
    );

    my %list      = ();
    my $eventType = "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/discovery/summary/2.0";
    my $result    = $ls->queryRequestLS( { subject => $subject, eventType => $eventType } );
    if ( exists $result->{eventType} and $result->{eventType} eq "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/discovery/summary/2.0" ) {
        if ( exists $result->{response} and $result->{response} ) {
            my $parser  = XML::LibXML->new();
            my $doc     = $parser->parse_string( $result->{response} );
            my $service = find( $doc->getDocumentElement, ".//nmwg:data/nmwg:metadata/perfsonar:subject/psservice:service", 0 );
            foreach my $s ( $service->get_nodelist ) {
                my $flag = 1;
                foreach my $element ( keys %{ $parameters->{service} } ) {
                    my $value = q{};
                    if ( $element =~ m/:/ ) {
                        $value = extract( find( $s, "./" . $element . "[text()=\"" . $parameters->{service}->{$element} . "\" or value=\"" . $parameters->{service}->{$element} . "\"]", 1 ), 0 );
                        unless ($value) {
                            $flag = 0;
                            last;
                        }
                    }
                    else {
                        $value = extract( find( $s, "./*[local-name()='" . $element . "' and (text()=\"" . $parameters->{service}->{$element} . "\" or value=\"" . $parameters->{service}->{$element} . "\")]", 1 ), 0 );
                        unless ($value) {
                            $flag = 0;
                            last;
                        }
                    }
                }
                if ($flag) {
                    my $value = $s->toString;
                    push @service, $value if $value and ( not exists $list{$value} );
                    $list{$value}++;
                }
            }
        }
    }

    return \@service;
}

=head3 getLSQueryContent( $self, { ls, addresses, domains, eventTypes, service } )

Perform query on the supplied hLS and using the supplied arguments:

 - array of arrays of ip addresses: ( ( ADDRESS, "ipv4"), ( ADDRESS, "ipv6") )
 - array of domains: ( "edu", "udel.edu" )
 - array of eventTypes: ( http://ggf.org/ns/nmwg/tools/owamp/2.0" )
 - hash of service variables: ( 
   { 
     serviceType => "MA", 
     psservice:serviceType => "MA" 
   } 
 )

The result is a list of metadata elements (metadata XML) that should match the
original query.

=cut

sub getLSQueryContent {
    my ( $self, @args ) = @_;
    my $parameters = validateParams(
        @args,
        {
            ls         => { type => Params::Validate::SCALAR },
            addresses  => { type => Params::Validate::ARRAYREF },
            domains    => { type => Params::Validate::ARRAYREF },
            eventTypes => { type => Params::Validate::ARRAYREF },
            service    => { type => Params::Validate::HASHREF }
        }
    );

    # TBD

    return;
}

=head3 getLSSummaryControlDirect( $self, { } )

Not implemented.

=cut

=head3 getLSRegistrationControlDirect( $self, { } )

Not implemented.

=cut

=head2 LEVEL 2 API

The following functions are classified according to the gLS design document
as existing in "Level 0".

=head3 getLSLocation( $self, { addresses, domains, eventTypes, service } )

Perform query at the root (or through the supplied hLS url) using the supplied
arguments:

 - array of arrays of ip addresses: ( ( ADDRESS, "ipv4"), ( ADDRESS, "ipv6") )
 - array of domains: ( "edu", "udel.edu" )
 - array of eventTypes: ( http://ggf.org/ns/nmwg/tools/owamp/2.0" )
 - hash of service variables: ( 
   { 
     serviceType => "MA", 
     psservice:serviceType => "MA" 
   } 
 )

The result is a list of Service elements (service XML) of services to contact
for more information.

=cut

sub getLSLocation {
    my ( $self, @args ) = @_;
    my $parameters = validateParams(
        @args,
        {
            ls         => 0,
            addresses  => { type => Params::Validate::ARRAYREF },
            domains    => { type => Params::Validate::ARRAYREF },
            eventTypes => { type => Params::Validate::ARRAYREF },
            service    => { type => Params::Validate::HASHREF }
        }
    );

    my @service = ();
    my $ls      = perfSONAR_PS::Client::LS->new();
    if ( exists $parameters->{ls} and $parameters->{ls} =~ m/^http:\/\// ) {
        unless ( $self->verifyURL( { url => $parameters->{ls} } ) == 0 ) {
            $self->{LOGGER}->error( "Supplied server \"".$parameters->{ls}."\" could not be contacted." );
            return; 
        }
        $ls->setInstance( { instance => $parameters->{ls} } );
    }
    else {
        my $ls_instance = $self->getRoot();
        unless ( $ls_instance ) {
            $self->{LOGGER}->error( "gLS Root servers could not be contacted." );
            return; 
        }        
        $ls->setInstance( { instance => $ls_instance } );
    }

    my $hls_array = $self->getLSDiscovey(
        {
            addresses  => $parameters->{addresses},
            domains    => $parameters->{domains},
            eventTypes => $parameters->{eventTypes},
            service    => $parameters->{service}
        }
    );

    foreach my $hls ( @{ $hls_array } ) {
        my $result = $self->getLSQueryLocation(
            {
                ls         => $hls,
                addresses  => $parameters->{addresses},
                domains    => $parameters->{domains},
                eventTypes => $parameters->{eventTypes},
                service    => $parameters->{service}
            }
        );
        push @service, @{ $result } if $result;
    }

    return \@service;
}

=head3 getLSContent( $self, { addresses, domains, eventTypes, service } )

Perform query on the root (or the supplied hLS) and using the supplied
arguments:

 - array of arrays of ip addresses: ( ( ADDRESS, "ipv4"), ( ADDRESS, "ipv6") )
 - array of domains: ( "edu", "udel.edu" )
 - array of eventTypes: ( http://ggf.org/ns/nmwg/tools/owamp/2.0" )
 - hash of service variables: ( 
   { 
     serviceType => "MA", 
     psservice:serviceType => "MA" 
   } 
 )

The result is a list of metadata elements (metadata XML) that should match the
original query.

=cut

sub getLSContent {
    my ( $self, @args ) = @_;
    my $parameters = validateParams(
        @args,
        {
            ls         => 0,
            addresses  => { type => Params::Validate::ARRAYREF },
            domains    => { type => Params::Validate::ARRAYREF },
            eventTypes => { type => Params::Validate::ARRAYREF },
            service    => { type => Params::Validate::HASHREF }
        }
    );

    # TBD

    return;
}

=head3 getLSSummaryControl( $self, { } )

Not implemented.

=cut

=head3 getLSRegistrationControl( $self, { } )

Not implemented.

=cut

1;

__END__

=head1 SYNOPSIS

    #!/usr/bin/perl -w

    use strict;
    use warnings;
    use Data::Dumper;
    
    use perfSONAR_PS::Client::gLS;
    my $url = "http://dc211.internet2.edu/gls.root.hints";

    my $gls = perfSONAR_PS::Client::gLS->new( { url => $url} );
    print Dumper( $gls->{ROOTS} ) , "\n";


=head1 SEE ALSO

L<Log::Log4perl>, L<Params::Validate>, L<English>, L<LWP::Simple>, L<Net::Ping>,
L<XML::LibXML>, L<perfSONAR_PS::ParameterValidation>,
L<perfSONAR_PS::Client::Echo>, L<perfSONAR_PS::Client::LS>,
L<perfSONAR_PS::Common>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  http://anonsvn.internet2.edu/svn/perfSONAR-PS

Questions and comments can be directed to the author, or the mailing list.
Bugs, feature requests, and improvements can be directed here:

  http://code.google.com/p/perfsonar-ps/issues/list

=head1 VERSION

$Id$

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework
along with this software.  If not, see
<http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2008, Internet2

All rights reserved.

=cut

