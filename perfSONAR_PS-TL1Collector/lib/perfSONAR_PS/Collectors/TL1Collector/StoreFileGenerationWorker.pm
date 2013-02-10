package perfSONAR_PS::Collectors::TL1Collector::StoreFileGenerationWorker;

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
use Digest::MD5 qw(md5_hex);
use Fcntl qw(:DEFAULT :flock);

use perfSONAR_PS::Utils::ParameterValidation;

use base 'perfSONAR_PS::Collectors::TL1Collector::Base';

use fields 'STORE_FILE', 'PREV_STORE_HASH', 'REGENERATION_PERIOD';

=head2 init( $self, { data_client => 1, store_file => 1, regeneration_period => 1 } )

Initializes the worker. 

=cut

sub init {
    my ( $self, @args ) = @_;
    my $args = validateParams( @args, { regeneration_period => 1, store_file => 1, data_client => 1 } );

    my $status = $self->SUPER::init( { data_client => $args->{data_client} } );

    if ( $status != 0 ) {
        return $status;
    }

    $self->{REGENERATION_PERIOD} = $args->{regeneration_period};
    $self->{STORE_FILE}          = $args->{store_file};
    $self->{LOGGER}->debug( "Set regeneration period to: " . $self->{REGENERATION_PERIOD} );
    $self->{LOGGER}->debug( "Set store file to: " . $self->{STORE_FILE} );
    return 0;

}

=head2 type ($self, $type)

Gets/sets the status type of this agent: admin or oper.

=cut

sub run {
    my ( $self ) = @_;

    my $next_runtime;

    while ( 1 ) {
        if ( $next_runtime ) {
            sleep( $next_runtime - time );
        }

        # Set the next runtime before we do the work so that we update at that
        # time period no matter how long this takes.
        $next_runtime = time + $self->{REGENERATION_PERIOD};

        my $file_contents = $self->{DATA_CLIENT}->generate_store_file( {} );
        my $md5sum = md5_hex( $file_contents );
        unless ( $self->{PREV_STORE_HASH} and $self->{PREV_STORE_HASH} eq $md5sum ) {
            my $status;
            if ( -f $self->{STORE_FILE} ) {

                # Don't blow away the file if it already exists. We don't want
                # to blow it away until we have a lock on it.
                $status = open( STORE, "+<", $self->{STORE_FILE} );
            }
            else {
                $status = open( STORE, ">", $self->{STORE_FILE} );
            }
            unless ( $status ) {
                $self->{LOGGER}->error( "Couldn't open " . $self->{STORE_FILE} . " for writing" );
            }
            else {
                flock STORE, LOCK_EX;
                truncate STORE, 0;
                seek STORE, 0, 0;
                print STORE $file_contents;
                close( STORE );    # Closing will auto-unlock, and make sure that the
                                   # data is on disk before finishing.
                $self->{LOGGER}->debug( "Wrote " . $self->{STORE_FILE} );

                $self->{PREV_STORE_HASH} = $md5sum;
            }
        }
    }
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

$Id: Base.pm 2640 2009-03-20 01:21:21Z zurawski $

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
