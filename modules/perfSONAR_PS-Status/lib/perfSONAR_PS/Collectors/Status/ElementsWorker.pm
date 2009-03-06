package perfSONAR_PS::Collectors::Status::ElementsWorker;

use strict;
use warnings;
use Params::Validate qw(:all);
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Utils::ParameterValidation;
use perfSONAR_PS::Status::Common;
use Data::Dumper;

our $VERSION = 0.09;

use base 'perfSONAR_PS::Collectors::Status::Base';

use fields 'POLLING_INTERVAL', 'NEXT_RUNTIME', 'ELEMENTS';

sub init {
    my ( $self, @params ) = @_;

    my $args = validateParams(
        @params,
        {
            data_client              => 1,
            polling_interval         => 0,
            elements                 => 1,
        }
    );

    my $n = $self->SUPER::init( { data_client => $args->{data_client} } );
    if ( $n == -1 ) {
        return -1;
    }

    $self->{POLLING_INTERVAL} = $args->{polling_interval};
    unless ( $self->{POLLING_INTERVAL} ) {
        $self->{LOGGER}->warn( "No polling interval set for SNMP worker. Setting to 60 seconds" );
        $self->{POLLING_INTERVAL} = 60;
    }

	$self->{ELEMENTS} = $args->{elements};

    return 0;
}

sub run {
    my ( $self ) = @_;

    my $prev_update_successful;

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

		my %new_update_successful = ();

        my $curr_time = time;

		foreach my $element (@{$self->{ELEMENTS}}) {
			my ($status, $res);

			my ($admin_status, $oper_status);

			$self->{LOGGER}->info("ELEMENT: ".Dumper($element));

			foreach my $agent (@{ $element->{agents} }) {
				my ($status, $res1, $res2, $res3) = $agent->run();

				my $new_oper_status;
				my $new_admin_status;

				if ($status != 0) {
					$self->{LOGGER}->error("Agent failed: $res1");
					if ($agent->type() eq "oper") {
						$new_oper_status = "unknown";
					} elsif ($agent->type() eq "admin") {
						$new_admin_status = "unknown";
					} elsif ($agent->type() eq "oper/admin") {
						$new_oper_status = "unknown";
						$new_admin_status = "unknown";
					}
				}

				my $time = $res1; # we no longer use their specified time since who knows what it might be.
				if ($agent->type() eq "oper") {
					$new_oper_status = $res2;
					$self->{LOGGER}->debug($agent->type()." agent returned ".$time.", oper=".$new_oper_status);
				} elsif ($agent->type() eq "admin") {
					$new_admin_status = $res2;
					$self->{LOGGER}->debug($agent->type()." agent returned ".$time.", admin=".$new_admin_status);
				} elsif ($agent->type() eq "oper/admin") {
					$new_oper_status = $res2;
					$new_admin_status = $res3;
					$self->{LOGGER}->debug($agent->type()." agent returned ".$time.", oper= ".$new_oper_status." admin=".$new_admin_status);
				}

				if ($new_admin_status) {
					$admin_status = get_new_admin_status($admin_status, $new_admin_status);
				}

				if ($new_oper_status) {
					$oper_status = get_new_oper_status($oper_status, $new_oper_status);
				}
			}

			unless ($admin_status and $oper_status) {
				$self->{LOGGER}->error("Couldn't get both administrative and operational statuses for element ".@{ $element->{ids} }[0]);
				next;
			}

			my $do_update;

			foreach my $id (@{ $element->{ids} }) {
				if ( $prev_update_successful && $prev_update_successful->{$id} ) {
					$self->{LOGGER}->debug( "Doing update" );
					$do_update = 1;
				}

				( $status, $res ) = $self->{DATA_CLIENT}->update_status( { element_id => $id, time => $curr_time, oper_status => $oper_status, admin_status => $admin_status, do_update => $do_update } );
				if ($status != 0) {
					$self->{LOGGER}->error("Couldn't store status for element ".$id.": $res");
					$new_update_successful{$id} = 0;
				}
				else {
					$new_update_successful{$id} = 1;
				}
			}
		}

        $prev_update_successful = \%new_update_successful;
	}
}

1;
