package perfSONAR_PS::Collectors::TL1Collector::Base;

use strict;
use warnings;

our $VERSION = 3.3;

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

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=head1 COPYRIGHT

Copyright (c) 2004-2009, Internet2 and the University of Delaware

All rights reserved.

=cut

# vim: expandtab shiftwidth=4 tabstop=4
