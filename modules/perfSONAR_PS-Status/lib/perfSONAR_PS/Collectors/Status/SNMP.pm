package perfSONAR_PS::Collectors::Status::SNMP;

=head1 NAME

perfSONAR_PS::Collectors::Status::SNMP - This module polls a router using SNMP
for the operational and administrative status of its interface names. 

=head1 DESCRIPTION

This worker will periodically poll the router using SNMP. It will grab the
interface names, operation status and administrative status. It will then store
this information into a status database.

=head1 API
=cut

use strict;
use warnings;
use Log::Log4perl qw(get_logger);
use Data::Dumper;
use perfSONAR_PS::Utils::ParameterValidation;
use perfSONAR_PS::Utils::SNMPWalk;

our $VERSION = 0.09;

use base 'perfSONAR_PS::Collectors::Status::BaseWorker';

use fields 'POLLING_INTERVAL', 'NEXT_RUNTIME', 'ADDRESS', 'PORT', 'COMMUNITY', 'VERSION', 'CHECK_ALL_INTERFACES', 'IDENTIFIER_PATTERN', 'INTERFACES';

sub init {
	my ($self, @args) = @_;
	my $args = validateParams(@args, {
						database_client => 1,
						polling_interval => 0,
						address => 1,
						port => 0,
						community => 0,
						version => 0,
						check_all_interfaces => 0,
						interfaces => 0,
						identifier_pattern => 0,
					});

	my $n = $self->SUPER::init({ database_client => $args->{database_client} });
	if ($n == -1) {
		return -1;
	}

	$self->{POLLING_INTERVAL} = $args->{polling_interval};
	unless ($self->{POLLING_INTERVAL}) {
		$self->{LOGGER}->warn("No polling interval set for SNMP worker. Setting to 60 seconds");
		$self->{POLLING_INTERVAL} = 60;
	}

	$self->{ADDRESS} = $args->{address};
	$self->{PORT} = $args->{port};
	$self->{COMMUNITY} = $args->{community};
	$self->{VERSION} = $args->{version};

	$self->{CHECK_ALL_INTERFACES} = $args->{check_all_interfaces};
	$self->{IDENTIFIER_PATTERN} = $args->{identifier_pattern};

	if ($self->{CHECK_ALL_INTERFACES} and (not $self->{IDENTIFIER_PATTERN} or $self->{IDENTIFIER_PATTERN} !~ /%facility%/)) {
		my $msg = "Checking all interfaces, but invalid identifier pattern specified";
		$self->{LOGGER}->error($msg);
		return (-1, $msg);
		# ERROR
	}

	$self->{INTERFACES} = ();

	# XXX: need better error checking
	if ($args->{interfaces}) {
		my %interfaces = ();
		foreach my $interface (@{ $args->{interfaces} }) {
            unless ($interface->{name}) {
                my $msg = "Interfaces must have 'name' specified";
                $self->{LOGGER}->error($msg);
                return (-1, $msg);
            }

            unless ($interface->{id} or $args->{identifier_pattern}) {
                my $msg = "Interfaces must have an 'id' if identifier pattern isn't specified";
                $self->{LOGGER}->error($msg);
                return (-1, $msg);
            }

			$interfaces{$interface->{name}} = $interface;
		}
		$self->{INTERFACES} = \%interfaces;
	}

	return 0;
}

sub run {
	my ($self) = @_;

	my $prev_update_successful;
	while(1) {
		if ($self->{NEXT_RUNTIME}) {
			sleep($self->{NEXT_RUNTIME} - time);
		}

        my ( $status, $res ) = $self->{DB_CLIENT}->open;
        if ( $status != 0 ) {
            my $msg = "Couldn't open database client: $res";
            $self->{LOGGER}->error( $msg );
            next;
        }

		# set the next runtime before we poll so that we don't add slop
		# to the end.
		my $curr_time = time;

		$self->{NEXT_RUNTIME} = $curr_time + $self->{POLLING_INTERVAL};

		my ($ifNameLines, $ifOperStatusLines, $ifAdminStatusLines);

		($status, $res) = snmpwalk($self->{ADDRESS}, $self->{PORT}, "1.3.6.1.2.1.31.1.1.1.1", $self->{COMMUNITY}, $self->{VERSION});
		if ($status != 0) {
			my $msg = "Couldn't look up list of ifNames: $res";
			$self->{LOGGER}->error($msg);
			next;
		}
		$ifNameLines = $res;

		($status, $res) = snmpwalk($self->{ADDRESS}, $self->{PORT}, "1.3.6.1.2.1.2.2.1.8", $self->{COMMUNITY}, $self->{VERSION});
		if ($status != 0) {
			my $msg = "Couldn't look up list of ifOperStatus: $res";
			$self->{LOGGER}->error($msg);
			next;
		}
		$ifOperStatusLines = $res;

		($status, $res) = snmpwalk($self->{ADDRESS}, $self->{PORT}, "1.3.6.1.2.1.2.2.1.7", $self->{COMMUNITY}, $self->{VERSION});
		if ($status != 0) {
			my $msg = "Couldn't look up list of ifAdminStatus: $res";
			$self->{LOGGER}->error($msg);
			next;
		}
		$ifAdminStatusLines = $res;

		my %ifNames = ();
		my %ifOperStatuses = ();
		my %ifAdminStatuses = ();

		# create the ifIndex mapping
		foreach my $oid_ref ( @{ $ifNameLines } ) {
			my $oid = $oid_ref->[0];
			my $type = $oid_ref->[1];
			my $value = $oid_ref->[2];

			$self->{LOGGER}->debug("$oid = $type: $value");
			if ($oid =~ /1\.3\.6\.1\.2\.1\.31\.1\.1\.1\.1\.(\d+)/x) {
				$ifNames{$1} = $value;
			}
		}

		foreach my $oid_ref ( @{ $ifOperStatusLines } ) {
			my $oid = $oid_ref->[0];
			my $type = $oid_ref->[1];
			my $value = $oid_ref->[2];

			$self->{LOGGER}->debug("$oid = $type: $value");
			if ($oid =~ /1.3.6.1.2.1.2.2.1.8.(\d+)/x) {
				if ($value eq "3") {
					$value = "degraded";
				} elsif ($value eq "2") {
					$value = "down";
				} elsif ($value eq "1") {
					$value = "up";
				} else {
					$value = "unknown";
				}

				$ifOperStatuses{$ifNames{$1}} = $value;
			}
		}

		foreach my $oid_ref ( @{ $ifAdminStatusLines } ) {
			my $oid = $oid_ref->[0];
			my $type = $oid_ref->[1];
			my $value = $oid_ref->[2];

			$self->{LOGGER}->debug("$oid = $type: $value");
			if ($oid =~ /1.3.6.1.2.1.2.2.1.7.(\d+)/x) {
				if ($value eq "1") {
					$value = "normaloperation";
				} elsif ($value eq "2") {
					$value = "maintenance";
				} elsif ($value eq "3") {
					$value = "troubleshooting";
				} else {
					$value = "unknown";
				}

				$ifAdminStatuses{$ifNames{$1}} = $value;
			}
		}

		my @interfaces;
		if ($self->{CHECK_ALL_INTERFACES}) {
            @interfaces = ();
            foreach my $index (keys %ifNames) {
                push @interfaces, $ifNames{$index};
            }
		}
		else {
			@interfaces = keys %{ $self->{INTERFACES} };
		}

        $self->{LOGGER}->debug("Interfaces to check: ".Dumper(\@interfaces));
		my %new_update_successful = ();
		foreach my $ifName (@interfaces) {
			my $id;
			if ($self->{INTERFACES}->{$ifName} and $self->{INTERFACES}->{$ifName}->{"id"}) {
				$id = $self->{INTERFACES}->{$ifName}->{"id"};
			} else {
				$id = $self->{IDENTIFIER_PATTERN};
				$id =~ s/\%facility\%/$ifName/g;
			}

			my $do_update;

			if ($prev_update_successful && $prev_update_successful->{$ifName}) {
                $self->{LOGGER}->debug("Doing update");
				$do_update = 1;
			}

			my ($status, $res) = $self->{DB_CLIENT}->updateStatus($curr_time,
					$id,
					$ifOperStatuses{$ifName},
					$ifAdminStatuses{$ifName},
					$do_update);
			if ($status != 0) {
				$self->{LOGGER}->error("Couldn't store status for element $id: $res");
				$new_update_successful{$ifName} = 0;
			} else {
				$new_update_successful{$ifName} = 1;
			}
		}

        $self->{DB_CLIENT}->close;

		$prev_update_successful = \%new_update_successful;
	}
}

1;

__END__

To join the 'perfSONAR-PS' mailing list, please visit:

https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

https://svn.internet2.edu/svn/perfSONAR-PS

Questions and comments can be directed to the author, or the mailing list.  Bugs,
feature requests, and improvements can be directed here:

https://bugs.internet2.edu/jira/browse/PSPS

=head1 VERSION

$Id:$

=head1 AUTHOR

Aaron Brown, aaron@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework along
with this software.  If not, see <http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2004-2008, Internet2 and the University of Delaware

All rights reserved.

=cut
# vim: expandtab shiftwidth=4 tabstop=4
