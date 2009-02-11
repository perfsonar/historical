package perfSONAR_PS::DB::Facilities;

use strict;
use warnings;
use Params::Validate qw(:all);
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Utils::ParameterValidation;
use Data::Dumper;
use perfSONAR_PS::DB::SQL;
use perfSONAR_PS::DB::Elements;
use English qw( -no_match_vars );

our $VERSION = 0.09;

use fields 'DB_CLIENT', 'LOGGER', 'USERNAME', 'PASSWORD', 'DBISTRING', 'FACILITIES_TABLE', 'ELEMENTS_CLIENT';

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

	$self->{FACILITIES_TABLE} = "ps_facilities";
	if ($args->{table_prefix}) {
		$self->{FACILITIES_TABLE} = $args->{table_prefix}."_facilities";
	}

	$self->{ELEMENTS_CLIENT} = perfSONAR_PS::DB::Elements->new();

	unless ($self->{ELEMENTS_CLIENT}->init(@args)) {
		my $msg = "Couldn't initialize elements database client";
		$self->{LOGGER}->error($msg);
		return 0;
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

sub add_facility {
	my ($self, @args) = @_;
	my $args = validateParams( @args, { host => 1, host_type => 1, facility => 1, facility_type => 1 } );

	my $facilities_table = $self->{FACILITIES_TABLE};

	my ($status, $res);

	my $query = "select id, host, host_type, facility, facility_type from ".$facilities_table;
	my $next_connector = "where";
	if ($args->{host}) {
		$query .= " ".$next_connector . " host='" . $args->{host} . "'";
		$next_connector = "and";
	}
	if ($args->{host_type}) {
		$query .= " ".$next_connector . " host_type='" . $args->{host_type} . "'";
		$next_connector = "and";
	}
	if ($args->{facility}) {
		$query .= " ".$next_connector . " facility='" . $args->{facility} . "'";
		$next_connector = "and";
	}
	if ($args->{facility_type}) {
		$query .= " ".$next_connector . " facility_type='" . $args->{facility_type} . "'";
		$next_connector = "and";
	}

	($status, $res) = $self->query_facilities({ host => $args->{host}, host_type => $args->{host_type}, facility => $args->{facility}, facility_type => $args->{facility_type} });
	if ($status != 0) {
		my $msg = "An error occurred while querying for facilities: $res";
		$self->{LOGGER}->error($msg);
		return (-1, $msg);
	}

	if (scalar(@{ $res }) > 0) {
		return (0, $res);
	}

	if ($self->{ELEMENTS_CLIENT}->openDB) {
		my $msg = "Couldn't open element identifier database";
		$self->{LOGGER}->error($msg);
		return (-1, $msg);
	}

	($status, $res) = $self->{ELEMENTS_CLIENT}->get_new_element_key();
	if ($status != 0) {
		$self->{ELEMENTS_CLIENT}->closeDB;

		my $msg = "Couldn't get new element identifier: $res";
		$self->{LOGGER}->error($msg);
		return (-1, $msg);
	}

	$self->{ELEMENTS_CLIENT}->closeDB;

	my $element_id = $res;

	my %insertValues = (
			id => $element_id,
			host => $args->{host},
			host_type => $args->{host_type},
			facility => $args->{facility},
			facility_type => $args->{facility_type},
			);

	if ($self->{DB_CLIENT}->insert({ table => $facilities_table, argvalues => \%insertValues }) == -1) {
		my $msg = "Couldn't add new facility: ".$args->{host}."/".$args->{facility};
		$self->{LOGGER}->error($msg);
		return (-1, $msg);
	}

	return $self->query_facilities({ host => $args->{host}, host_type => $args->{host_type}, facility => $args->{facility}, facility_type => $args->{facility_type} });
}

sub query_facilities {
	my ($self, @args) = @_;
	my $args = validateParams( @args, { host => 0, host_type => 0, facility => 0, facility_type => 0 } );

	my $facilities_table = $self->{FACILITIES_TABLE};

	my $id;
	my $query = "select id, host, host_type, facility, facility_type from ".$facilities_table;
	my $next_connector = "where";
	if ($args->{host}) {
		$query .= " ".$next_connector . " host='" . $args->{host} . "'";
		$next_connector = "and";
	}
	if ($args->{host_type}) {
		$query .= " ".$next_connector . " host_type='" . $args->{host_type} . "'";
		$next_connector = "and";
	}
	if ($args->{facility}) {
		$query .= " ".$next_connector . " facility='" . $args->{facility} . "'";
		$next_connector = "and";
	}
	if ($args->{facility_type}) {
		$query .= " ".$next_connector . " facility_type='" . $args->{facility_type} . "'";
		$next_connector = "and";
	}

	$self->{LOGGER}->debug("Query: ".$query);

	my $ids = $self->{DB_CLIENT}->query({ query => $query });
	if ($ids == -1) {
		my $msg = "An error occurred while querying for facilities";
		$self->{LOGGER}->error($msg);
		return (-1, $msg);
	}

	my @facilities = ();

	foreach my $id_ref (@{ $ids }) {
		my @fields = @{ $id_ref };

		my %facility = ();
		$facility{key} = $fields[0];
		$facility{host} = $fields[1];
		$facility{host_type} = $fields[2];
		$facility{facility} = $fields[3];
		$facility{facility_type} = $fields[4];

		push @facilities, \%facility;
	}

	return (0, \@facilities);
}

1;
