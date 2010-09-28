package perfSONAR_PS::Collectors::Status::DeviceAgents::Base;

use strict;
use warnings;

our $VERSION = 3.1;

=head1 NAME

perfSONAR_PS::Collectors::Status::DeviceAgents::Base

=head1 DESCRIPTION

TBD

=cut

use Params::Validate qw(:all);
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Utils::ParameterValidation;
use Data::Dumper;

use fields 'POLLING_INTERVAL', 'NEXT_RUNTIME', 'LOGGER', 'IDENTIFIER_PATTERN', 'DATA_CLIENT';

=head2 new($class)

TBD

=cut

sub new {
    my ( $class ) = @_;

    my $self = fields::new( $class );

    $self->{LOGGER} = get_logger( $class );

    return $self;
}

=head2 init( $self, { data_client, polling_interval, identifier_pattern } )

TBD

=cut

sub init {
    my ( $self, @params ) = @_;

    my $args = validateParams(
        @params,
        {
            data_client        => 1,
            polling_interval   => 0,
            identifier_pattern => 0,
        }
    );

    $self->{POLLING_INTERVAL} = $args->{polling_interval};

    unless ( $self->{POLLING_INTERVAL} ) {
        $self->{LOGGER}->warn( "No polling interval set for worker. Defaulting to 60 seconds" );
        $self->{POLLING_INTERVAL} = 60;
    }

    $self->{IDENTIFIER_PATTERN} = $args->{identifier_pattern};
    $self->{DATA_CLIENT}        = $args->{data_client};

    return 0;
}

=head2 run($self)

TBD

=cut

sub run {
    my ( $self ) = @_;

    my $prev_update_successful;
    my %metadata_added    = ();
    my %topology_id_added = ();

    while ( 1 ) {
        if ( $self->{NEXT_RUNTIME} ) {
            $self->{DATA_CLIENT}->closeDB;

            my $sleep_time = $self->{NEXT_RUNTIME} - time;
            sleep( $sleep_time ) if ($sleep_time > 0);
        }

        $self->{NEXT_RUNTIME} = time + $self->{POLLING_INTERVAL};

        my ( $status, $res );

        ( $status, $res ) = $self->{DATA_CLIENT}->openDB;
        if ( $status != 0 ) {
            my $msg = "Couldn't open database client: $res";
            $self->{LOGGER}->error( $msg );
            next;
        }

        unless ( $self->connect() ) {
            $self->{LOGGER}->error( "Could not connect to host" );
            next;
        }

        my $curr_time = time;

        ( $status, $res ) = $self->check_facilities();
        if ( $status != 0 ) {
            my $msg = "Facilities check failed: $res";
            $self->{LOGGER}->error( $msg );
            next;
        }

        $self->{LOGGER}->debug( "Facilities: " . Dumper( $res ) );

        my $facilities = $res;

        my %new_update_successful = ();
        foreach my $facility ( @$facilities ) {
            my $id = $facility->{id};
            unless ( $id ) {
                my $name = $facility->{name};
                $id = $self->{IDENTIFIER_PATTERN};
                $id =~ s/\%facility%/$name/g;
            }

            my $do_update;
            if ( $prev_update_successful && $prev_update_successful->{$id} ) {
                $self->{LOGGER}->debug( "Doing update" );
                $do_update = 1;
            }

            ( $status, $res ) = $self->{DATA_CLIENT}->update_status( { element_id => $id, time => $curr_time, oper_status => $facility->{oper_status}, admin_status => $facility->{admin_status}, do_update => $do_update } );
            if ( $status != 0 ) {
                $self->{LOGGER}->error( "Couldn't store status for element: $res" );
                $new_update_successful{$id} = 0;
            }
            else {
                $new_update_successful{$id} = 1;
            }
        }

        $prev_update_successful = \%new_update_successful;

        $self->disconnect();
    }

    return;
}

1;

__END__

=head1 SEE ALSO

L<Params::Validate>, L<Log::Log4perl>,
L<perfSONAR_PS::Utils::ParameterValidation>, L<Data::Dumper>

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
