package perfSONAR_PS::Client::gLS;

use fields 'ROOTS', 'LOGGER';

use strict;
use warnings;

our $VERSION = 0.10;

=head1 NAME

perfSONAR_PS::Client::gLS - API for interacting with gLS and hLS instances.

=head1 DESCRIPTION

...

=cut

use Log::Log4perl qw( get_logger );
use Params::Validate qw( :all );
use English qw( -no_match_vars );

use perfSONAR_PS::ParameterValidation;

=head2 new($package { root_list })

Instantiates a new object.  The optional arguement here is an array of known
root servers.   

=cut

sub new {
    my ( $package, @args ) = @_;
    my $parameters = validateParams( @args, { root_list => 0 } );

    my $self = fields::new($package);
    $self->{LOGGER} = get_logger("perfSONAR_PS::Client::gLS");
    if ( exists $parameters->{"root_list"} and $#{ $parameters->{"root_list"} } > -1 ) {
        $self->{ROOTS} = $parameters->{"root_list"};
    }
    return $self;
}

=head2 addRoot($self { root })

Add a root server to the current list of root servers.

=cut

sub addRoot {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { root => 1 } );

    if($#{$self->{ROOTS}} > -1) {
      push @{ $self->{ROOTS} }, $parameters->{"root"};
    }
    else {
      my @temp = ( $parameters->{"root"} );
      $self->{ROOTS} = \@temp;
    }
    return 0;
}

=head2 deleteRoot($self { root })

Delete a root server from the current list of root servers.

=cut

sub deleteRoot {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { root => 1 } );

    my $counter = 0;
    foreach my $r ( @{ $self->{ROOTS} } ) {
        if( $r eq $parameters->{"root"} ) {
            splice(@{$self->{ROOTS}}, $counter, 1);
            return 0;
        }
        $counter++;
    }
    return -1;
}

=head2 clearRoots($self {  })

Remove all root servers.

=cut

sub clearRoots {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, {  } );

    undef $self->{ROOTS};
    return 0;    
}

=head2 LEVEL 0 API

The following functions are classified according to the gLS design document
as existing in "Level 0".

=head3 getLSDiscoverRaw($self { ls, xquery })

Given an XQuery, send it directly to the summary storage of the specified LS
instance.  Return the results as a XXX.

=cut

sub getLSDiscoverRaw {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { ls => 1, xquery => 1 } );

    return 0;    
}

=head3 getLSQueryRaw($self { ls, xquery })

Given an XQuery, send it directly to the registration storage of the specified
LS instance.  Return the results as a XXX.

=cut

sub getLSQueryRaw {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { ls => 1, xquery => 1 } );

    return 0;    
}

=head3 getLSDiscoverControlRaw($self { ls, xquery })

Given an XQuery, send it directly to the summary control storage of the
specified LS instance.  Return the results as a XXX.

=cut

sub getLSDiscoverControlRaw {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { ls => 1, xquery => 1 } );

    return 0;    
}

=head3 getLSQueryControlRaw($self { ls, xquery })

Given an XQuery, send it directly to the registration control storage of the
specified LS instance.  Return the results as a XXX.

=cut

sub getLSQueryControlRaw {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { ls => 1, xquery => 1 } );

    return 0;    
}

=head2 LEVEL 1 API

The following functions are classified according to the gLS design document
as existing in "Level 1".

=head3 getLSDiscoverEventType($self { eventType })

Given an eventType, return a list of hLS instances containing this eventType.
This function will search all loaded gLS Roots for an answer.

=cut

sub getLSDiscoverEventType {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { eventType => 1 } );

    return 0;    
}

=head3 getLSDiscoverAddress($self { address })

Given an address, return a list of hLS instances containing this address.
This function will search all loaded gLS Roots for an answer.

=cut

sub getLSDiscoverAddress {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { address => 1 } );

    return 0;    
}

=head3 getLSDiscoverDomain($self { domain })

Given a domain, return a list of hLS instances containing this domain.
This function will search all loaded gLS Roots for an answer.

=cut

sub getLSDiscoverDomain {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { domain => 1 } );

    return 0;    
}

=head3 getLSDiscoverService($self { type })

Given a service type, return a list of hLS instances containing a service of
this type.  This function will search all loaded gLS Roots for an answer.

=cut

sub getLSDiscoverService {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { type => 1 } );

    return 0;    
}

=head3 getLSQueryEventType($self { ls, eventType })

Given an LS instance and an eventType, return all matching metadata in an array
for this particular LS.

=cut

sub getLSQueryEventType {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { ls => 1, eventType => 1 } );

    return 0;    
}

=head3 getLSQueryAddress($self { ls, address })

Given an LS instance and an address, return all matching metadata in an array
for this particular LS.

=cut

sub getLSQueryAddress {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { ls => 1, address => 1 } );

    return 0;    
}

=head3 getLSQueryDomain($self { ls, domain })

Given an LS instance and a domain, return all matching metadata in an array
for this particular LS.

=cut

sub getLSQueryDomain {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { ls => 1, domain => 1 } );

    return 0;    
}

=head3 getLSQueryService($self { ls, type })

Given an LS instance and a service type, return all matching service metadata
in an array for this particular LS.

=cut

sub getLSQueryService {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { ls => 1, type => 1 } );

    return 0;    
}

=head3 getLSQueryControlService($self { ls, type, name, accessPoint })

Given an LS instance and some service info, return the times from the
LSStore-control file that the services will expire.

=cut

sub getLSQueryControlService {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { ls => 1, type => 0, name => 0, accessPoint => 0} );

    return 0;    
}

=head2 LEVEL 2 API

The following functions are classified according to the gLS design document
as existing in "Level 2".

=head3 getLSEventType($self { eventType })

Given an eventType, return all matching metadata.  This function will search
all loaded gLS Roots for answers.

=cut

sub getLSEventType {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { eventType => 1 } );

    return 0;    
}

=head3 getLSAddress($self { address })

Given an address, return all matching metadata.  This function will search all
loaded gLS Roots for answers.

=cut

sub getLSAddress {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { address => 1 } );

    return 0;    
}

=head3 getLSDomain($self { domain })

Given a domain, return all matching metadata.  This function will search
all loaded gLS Roots for answers.

=cut

sub getLSDomain {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { domain => 1 } );

    return 0;    
}

=head3 getLSService($self { type })

Given a service type, return all matching metadata.  This function will search
all loaded gLS Roots for answers.

=cut

sub getLSService {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { type => 1 } );

    return 0;    
}

=head3 getLSControlService($self { type, name, accessPoint })

Given a service information, return all times from the LSStore-control
structure that match.  This function will search all loaded gLS Roots for
answers.

=cut

sub getLSControlService {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { ls => 1, type => 0, name => 0, accessPoint => 0} );

    return 0;    
}

1;

__END__

=head1 SYNOPSIS

    #!/usr/bin/perl -w

    use strict;
    use warnings;
    use Data::Dumper;
    
    use perfSONAR_PS::Client::gLS;

    my @list = (
      "url1",
      "url2"
    );
    
    my $api = new perfSONAR_PS::Client::gLS(
      { root_list => \@list }
    );    
    print "1:\t" , Dumper($api) , "\n";
    
    $api->addRoot( { root => "url3" } );
    print "2:\t" , Dumper($api) , "\n";
    
    $api->deleteRoot( { root => "url3" } );
    print "3:\t" , Dumper($api) , "\n";
    
    $api->deleteRoot( { root => "url4" } );
    print "4:\t" , Dumper($api) , "\n";

    $api->clearRoots();
    print "5:\t" , Dumper($api) , "\n";

=head1 SEE ALSO

L<Log::Log4perl>, L<Params::Validate>, L<English>

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

Copyright (c) 2008, Internet2

All rights reserved.

=cut

