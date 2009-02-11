package perfSONAR_PS::DB::TopologyID;

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

use fields 'DB_CLIENT', 'LOGGER', 'USERNAME', 'PASSWORD', 'DBISTRING', 'TOPOLOGY_IDS_TABLE', 'ELEMENTS_CLIENT';

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

	$self->{TOPOLOGY_IDS_TABLE} = "ps_topology_ids";
	if ($args->{table_prefix}) {
		$self->{TOPOLOGY_IDS_TABLE} = $args->{table_prefix}."_topology_ids";
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

sub add_topology_id {
	my ($self, @args) = @_;
	my $args = validateParams( @args, { topology_id => { type => SCALAR }, element_id => 0 } );

	my $topology_ids_table = $self->{TOPOLOGY_IDS_TABLE};

	unless ($args->{topology_id} =~ /^urn:/) {
		my $msg = "Invalid topology identifier. They must all be URNs";
		$self->{LOGGER}->error($msg);
		return (-1, $msg);
	}

	my ($status, $res);

	($status, $res) = $self->query_topology_ids({ topology_id => $args->{topology_id} });
	if ($status != 0) {
		my $msg = "An error occurred while querying for topology_ids: $res";
		$self->{LOGGER}->error($msg);
		return (-1, $msg);
	}

	if (scalar(@{ $res }) > 0) {
		if (not $args->{element_id}) {
			return (0, $res);
		} elsif ($args->{element_id} ne $res->[0]->{key}) {
			return (-1, "Existing topology id for different element: ".$args->{element_id}." vs. ".$res->[0]->{key});
		} else {
			return (0, $res);
		}
	}

	my $key = $args->{element_id};
	unless ($key) {
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
	}

	my %insertValues = (
			id => $key,
			topology_id => $args->{topology_id},
			);

	if ($self->{DB_CLIENT}->insert({ table => $topology_ids_table, argvalues => \%insertValues }) == -1) {
		my $msg = "Couldn't add new topology_id: ".$args->{topology_id};
		$self->{LOGGER}->error($msg);
		return (-1, $msg);
	}

	return $self->query_topology_ids({ topology_id => $args->{topology_id} });
}

sub query_topology_ids {
	my ($self, @args) = @_;
	my $args = validateParams( @args, { topology_id => 0, element_id => 0 } );

	my $topology_ids_table = $self->{TOPOLOGY_IDS_TABLE};

	my $query = "select id, topology_id from ".$topology_ids_table;
	my $next_connector = "where";
	if ($args->{topology_id}) {
		$query .= " ".$next_connector . " topology_id='" . $args->{topology_id} . "'";
		$next_connector = "and";
	}
	if ($args->{element_id}) {
		$query .= " ".$next_connector . " id=" . $args->{element_id} ;
		$next_connector = "and";
	}

	my $ids = $self->{DB_CLIENT}->query({ query => $query });
	if ($ids == -1) {
		my $msg = "An error occurred while querying for topology ids";
		$self->{LOGGER}->error($msg);
		return (-1, $msg);
	}

	my @topology_ids = ();

	foreach my $id_ref (@{ $ids }) {
		my @fields = @{ $id_ref };

		my %topology_id = ();
		$topology_id{key} = $fields[0];
		$topology_id{topology_id} = $fields[1];

		push @topology_ids, \%topology_id;
	}

	return (0, \@topology_ids);
}

1;
