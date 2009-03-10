package perfSONAR_PS::Collectors::Status::DeviceAgents::Base;

use strict;
use warnings;
use Params::Validate qw(:all);
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Utils::ParameterValidation;
use Data::Dumper;

our $VERSION = 0.09;

use fields 'POLLING_INTERVAL', 'NEXT_RUNTIME', 'LOGGER', 'IDENTIFIER_PATTERN', 'DATA_CLIENT';

sub new {
    my ( $class ) = @_;

    my $self = fields::new( $class );

    $self->{LOGGER} = get_logger( $class );

    return $self;
}

sub init {
    my ( $self, @params ) = @_;

    my $args = validateParams(
        @params,
        {
            data_client              => 1,
            polling_interval         => 0,
            identifier_pattern       => 0,
        }
    );

    $self->{POLLING_INTERVAL} = $args->{polling_interval};

    unless ( $self->{POLLING_INTERVAL} ) {
        $self->{LOGGER}->warn( "No polling interval set for worker. Defaulting to 60 seconds" );
        $self->{POLLING_INTERVAL} = 60;
    }

	$self->{IDENTIFIER_PATTERN} = $args->{identifier_pattern};
	$self->{DATA_CLIENT} = $args->{data_client};

    return 0;
}

sub run {
    my ( $self ) = @_;

    my $prev_update_successful;
	my %metadata_added = ();
	my %topology_id_added = ();

    while ( 1 ) {
        if ( $self->{NEXT_RUNTIME} ) {
            $self->{DATA_CLIENT}->closeDB;

            sleep( $self->{NEXT_RUNTIME} - time );
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

		($status, $res) = $self->check_facilities();
		if ($status != 0) {
			my $msg = "Facilities check failed: $res";
			$self->{LOGGER}->error($msg);
			next;
		}

		$self->{LOGGER}->debug("Facilities: ".Dumper($res));

		my $facilities = $res;

        my %new_update_successful = ();
        foreach my $facility ( @$facilities ) {
			my $id = $facility->{id};
			unless ($id) {
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
