package perfSONAR_PS::Collectors::TL1Collector::Base;

use strict;
use warnings;

our $VERSION = 3.1;

=head1 NAME

perfSONAR_PS::Collectors::TL1Collector::WorkerBase

=head1 DESCRIPTION

This module provides an agent for the Link TL1Collector Collector that gets status
information by executing a script.  This agent will run a script that should
print out the link status information in the format: 

"timestamp,measurement_value".

=head1 API

=cut

use Log::Log4perl qw( get_logger );
use perfSONAR_PS::Utils::ParameterValidation;

use fields 'LOGGER', 'DATA_CLIENT';

=head2 new 

Minimal setup routine. Instantiates the class and sets up the logging. The
actual setting of attributes is done using the "init" function.

=cut

sub new {
    my ( $class ) = @_;

    my $self = fields::new( $class );

    $self->{LOGGER} = get_logger( $class );

    return $self;
}

=head2 init( $self, { data_client } )

TBD

=cut

sub init {
    my ( $self, @args ) = @_;
    my $args = validateParams( @args, { data_client => 1 } );

    $self->{DATA_CLIENT} = $args->{data_client};

    return 0;

}

=head2 type ($self, $type)

Gets/sets the status type of this agent: admin or oper.

=cut

sub run {
    my ( $self ) = @_;

    croak( "Class must be overridden" );
}

1;

__END__

=head1 SEE ALSO

To join the 'perfSONAR Users' mailing list, please visit:

  https://mail.internet2.edu/wws/info/perfsonar-user

The perfSONAR-PS subversion repository is located at:

  http://anonsvn.internet2.edu/svn/perfSONAR-PS/trunk

Questions and comments can be directed to the author, or the mailing list.
Bugs, feature requests, and improvements can be directed here:

  http://code.google.com/p/perfsonar-ps/issues/list

=head1 VERSION

$Id$

=head1 AUTHOR

Aaron Brown, aaron@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework
along with this software.  If not, see
<http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2004-2009, Internet2 and the University of Delaware

All rights reserved.

=cut

# vim: expandtab shiftwidth=4 tabstop=4
