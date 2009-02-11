package perfSONAR_PS::DB::Status;

use strict;
use warnings;
use Params::Validate qw(:all);
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Utils::ParameterValidation;
use Data::Dumper;
use perfSONAR_PS::DB::SQL;
use perfSONAR_PS::Status::Common;
use English qw( -no_match_vars );

our $VERSION = 0.09;

use fields 'DB_CLIENT', 'LOGGER', 'USERNAME', 'PASSWORD', 'DBISTRING', 'STATUS_TABLE';

sub new {
	my ( $class ) = @_;

	my $self = fields::new($class);
	$self->{LOGGER} = get_logger($class);
	return $self;
}

sub init {
	my ( $self, @args ) = @_;
	my $args = validateParams( @args, { dbistring => 1, username => 0, password => 0, table_prefix => 0 });

	$self->{DBISTRING} = $args->{dbistring};
	$self->{USERNAME} = $args->{username};
	$self->{PASSWORD} = $args->{password};

	$self->{STATUS_TABLE} = "ps_status";
	if ($args->{table_prefix}) {
		$self->{STATUS_TABLE} = $args->{table_prefix}."_status";
	}

	$self->{DB_CLIENT} = perfSONAR_PS::DB::SQL->new({ name => $self->{DBISTRING}, user => $self->{USERNAME}, pass => $self->{PASSWORD} });

	return 1;
}

sub openDB {
	my ( $self, @args ) = @_;
	my $args = validateParams( @args, {} );

	return $self->{DB_CLIENT}->openDB;
}

sub closeDB {
	my ( $self, @args ) = @_;
	my $args = validateParams( @args, {} );

	return $self->{DB_CLIENT}->closeDB;
}

sub get_element_status {
	my ( $self, @args ) = @_;
	my $args = validateParams( @args, { element_ids => 1, start_time => 0, end_time => 0 });

	my $element_ids = $args->{element_ids};
	my $start_time = $args->{start_time};
	my $end_time = $args->{end_time};

	my %elements;

	foreach my $element_id (@{ $element_ids }) {
		my $query;

		$query = "select start_time, end_time, oper_status, admin_status from ".$self->{STATUS_TABLE}." where id=\'".$element_id."\'";

        if ($end_time) {
            $query .= " and start_time <= \'".$end_time."\'";
        }

        if ($start_time) {
            $query .= "and end_time >= \'".$start_time."\'";
        }

        $query .= " order by start_time";

		my $states = $self->{DB_CLIENT}->query({ query => $query });
		if ($states == -1) {
			$self->{LOGGER}->error("Couldn't grab information for node ".$element_id);
			return (-1, "Couldn't grab information for node ".$element_id);
		}

		foreach my $state_ref (@{ $states }) {
			my @state = @{ $state_ref };
			my $new_element;

            $state[0] = $start_time if ($state[0] < $start_time);
            $state[1] = $end_time if ($state[1] > $end_time);

			$new_element = new perfSONAR_PS::Status::Link($element_id, $state[0], $state[1], $state[2], $state[3]);

            if (not defined $elements{$element_id}) {
                my @newa = ();
                $elements{$element_id} = \@newa;
            }

			push @{ $elements{$element_id} }, $new_element;
		}
	}

	return (0, \%elements);
}

sub update_status {
	my ( $self, @args ) = @_;
	my $args = validateParams( @args, { element_id => 1, time => 1, oper_status => 1, admin_status => 1, do_update => 0 });

	my $element_id = $args->{element_id};
	my $time = $args->{time};
	my $oper_status = $args->{oper_status};
	my $admin_status = $args->{admin_status};
	my $do_update = $args->{do_update};

	my $prev_end_time;

	$oper_status = lc($oper_status);
	$admin_status = lc($admin_status);

	if (!isValidOperState($oper_status)) {
		return (-1, "Invalid operational state: $oper_status");
	}

	if (!isValidAdminState($admin_status)) {
		return (-1, "Invalid administrative state: $admin_status");
	}

    my $query = "select end_time, oper_status, admin_status from ".$self->{STATUS_TABLE}." where id=\'".$element_id."\' order by end_time limit 1";

    my $states = $self->{DB_CLIENT}->query({ query => $query });
    if ($states == -1) {
        $self->{LOGGER}->error("Couldn't grab information for node ".$element_id);
        return (-1, "Couldn't grab information for node ".$element_id);
    }

    $self->{LOGGER}->debug("Size of: ".scalar(@$states)." -- ".Dumper($states));

    if (scalar(@$states) > 0) {
        $prev_end_time = $states->[0]->[0];

        if ($prev_end_time >= $time) {
            my $msg = "Update in the past for $element_id: most recent data was obtained for ".$prev_end_time;
            $self->{LOGGER}->error($msg);
            return (-1, $msg);
        }

        if ($do_update) {
            if ($states->[0]->[1] ne $oper_status) {
                my $msg = "Oper value differs for $element_id";
                $self->{LOGGER}->warn($msg);
                $do_update = 0;
            } elsif ($states->[0]->[2] ne $admin_status) {
                my $msg = "Admin value differs for $element_id";
                $self->{LOGGER}->warn($msg);
                $do_update = 0;
            }
        }
    }
    else {
        $do_update = 0;
    }

	if ($do_update) {
		$self->{LOGGER}->debug("Updating $element_id");

		my %updateValues = (
				end_time => $time,
				);

		my %where = (
				id => "'".$element_id."'",
				end_time => $prev_end_time,
			    );

		if ($self->{DB_CLIENT}->update({ table => $self->{STATUS_TABLE}, wherevalues => \%where, updatevalues => \%updateValues }) == -1) {
			my $msg = "Couldn't update element status for element $element_id";
			$self->{LOGGER}->error($msg);
			return (-1, $msg);
		}
	} else {
		my %insertValues = (
				id => $element_id,
				start_time => $time,
				end_time => $time,
				oper_status => $oper_status,
				admin_status => $admin_status,
				);

		if ($self->{DB_CLIENT}->insert({ table => $self->{STATUS_TABLE}, argvalues => \%insertValues }) == -1) {
			my $msg = "Couldn't update element status for element $element_id";

			$self->{LOGGER}->error($msg);
			return (-1, $msg);
		}
	}

	return (0, "");
}

sub get_unique_ids {
	my ($self) = @_;

	my $elements = $self->{DB_CLIENT}->query({ query => "select distinct id, id_type from ".$self->{STATUS_TABLE} });
	if ($elements == -1) {
		$self->{LOGGER}->error("Couldn't grab list of elements");
		return (-1, "Couldn't grab list of elements");
	}

	my @element_ids = ();
	foreach my $element_ref (@{ $elements }) {
		my @element = @{ $element_ref };

		my %id = ();
		$id{id} = $element[0];
		$id{type} = $element[1];

		push @element_ids, \%id;
	}

	return (0, \@element_ids);
}

1;
