package perfSONAR_PS::Collectors::Status::ElementAgents::Script;

use strict;
use warnings;

our $VERSION = 3.3;

=head1 NAME

perfSONAR_PS::Collectors::LinkStatus::Agent::Script

=head1 DESCRIPTION

This module provides an agent for the Link Status Collector that gets status
information by executing a script.  This agent will run a script that should
print out the link status information in the format: 

"timestamp,measurement_value".

=head1 API

=cut

use Log::Log4perl qw(get_logger);

use fields 'TYPE', 'SCRIPT', 'PARAMETERS';

=head2 new ($self, $status_type, $script, $parameters)

Creates a new Script Agent of the specified type and with the specified script
and script parameters.

=cut

sub new {
    my ( $class, $type, $script, $parameters ) = @_;

    my $self = fields::new( $class );

    $self->{"TYPE"}       = $type;
    $self->{"SCRIPT"}     = $script;
    $self->{"PARAMETERS"} = $parameters;

    return $self;
}

=head2 type ($self, $type)

Gets/sets the status type of this agent: admin or oper.

=cut

sub type {
    my ( $self, $type ) = @_;

    if ( $type ) {
        $self->{TYPE} = $type;
    }

    return $self->{TYPE};
}

=head2 script ($self, $script)

Gets/sets the script to be run

=cut

sub script {
    my ( $self, $script ) = @_;

    if ( $script ) {
        $self->{SCRIPT} = $script;
    }

    return $self->{SCRIPT};
}

=head2 parameters ($self, $parameters)

Sets the parameters that are passed to the script

=cut

sub parameters {
    my ( $self, $parameters ) = @_;

    if ( $parameters ) {
        $self->{PARAMETERS} = $parameters;
    }

    return $self->{PARAMETERS};
}

=head2 run ($self)

This function is called by the collector daemon. It executes the script adding
the status type ('admin' or 'oper') and any parameters specified as parameters
to the script.

=cut

sub run {
    my ( $self ) = @_;
    my $logger = get_logger( "perfSONAR_PS::Collectors::LinkStatus::Agent::Script" );

    my $cmd = $self->{SCRIPT} . " " . $self->{TYPE};

    if ( defined $self->{PARAMETERS} ) {
        $cmd .= " " . $self->{PARAMETERS};
    }

    $logger->debug( "Command to run: $cmd" );

    open my $SCRIPT, "-|", $cmd or return ( -1, "Couldn't execute cmd: $cmd" );
    my @lines = <$SCRIPT>;
    close( $SCRIPT );

    if ( $#lines < 0 ) {
        my $msg = "script returned no output";
        return ( -1, $msg );
    }

    if ( $#lines > 0 ) {
        my $msg = "script returned invalid output: more than one line";
        return ( -1, $msg );
    }

    $logger->debug( "Command returned \"$lines[0]\"" );

    chomp( $lines[0] );
    my @fields = split( ',', $lines[0] );

    if ( scalar( @fields ) == 0 ) {
        my $msg = "script returned invalid output: does not contain measurement time";
        return ( -1, $msg );
    }

    if ( scalar( @fields ) == 1 ) {
        my $msg = "script returned invalid output: does not contain link status";
        return ( -1, $msg );
    }

    if ( $self->{TYPE} eq "oper/admin" and scalar( @fields ) == 2 ) {
        my $msg = "script returned invalid output: does not contain link admin status";
        return ( -1, $msg );
    }

    if ( $self->{TYPE} eq "oper/admin" ) {
        return ( 0, $fields[0], lc( $fields[1] ), lc( $fields[2] ) );
    }
    else {
        return ( 0, $fields[0], lc( $fields[1] ) );
    }
}

1;

__END__

=head1 SEE ALSO

To join the 'perfSONAR-PS Users' mailing list, please visit:

  https://lists.internet2.edu/sympa/info/perfsonar-ps-users

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

Copyright (c) 2004-2010, Internet2 and the University of Delaware

All rights reserved.

=cut

# vim: expandtab shiftwidth=4 tabstop=4
