package perfSONAR_PS::DB::Elements;

use strict;
use warnings;
use Params::Validate qw(:all);
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Utils::ParameterValidation;
use Data::Dumper;
use perfSONAR_PS::DB::SQL;
use perfSONAR_PS::Common;
use English qw( -no_match_vars );

our $VERSION = 0.09;

use fields 'DB_CLIENT', 'LOGGER', 'USERNAME', 'PASSWORD', 'DBISTRING', 'ELEMENTS_TABLE';

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

	$self->{ELEMENTS_TABLE} = "ps_elements";
	if ($args->{table_prefix}) {
		$self->{ELEMENTS_TABLE} = $args->{table_prefix}."_elements";
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

sub get_new_element_key {
	my ($self, @args) = @_;
	my $args = validateParams( @args, { } );

	my $elements_table = $self->{ELEMENTS_TABLE};

	# XXX: hack, this should really use transactions, but for databases that don't support that...

	my $nonce = genuid();

	my %insertValues = (
			nonce => $nonce,
			);

	if ($self->{DB_CLIENT}->insert({ table => $elements_table, argvalues => \%insertValues }) == -1) {
		my $msg = "An error occurred while getting new element identifier";
		$self->{LOGGER}->error($msg);
		return (-1, $msg);
	}

	my $query = "select id from ".$elements_table." where nonce=".$nonce;
	my $ids = $self->{DB_CLIENT}->query({ query => $query });
	if ($ids == -1) {
		my $msg = "An error occurred while getting new element identifier";
		$self->{LOGGER}->error($msg);
		return (-1, $msg);
	}

	if (scalar(@{ $ids }) == 0) {
		my $msg = "An error occurred while getting new element identifier";
		$self->{LOGGER}->error($msg);
		return (-1, $msg);
	}

	my $ret_id;

	$ret_id = $ids->[0]->[0];

	my %updateValues = (
			nonce => 0,
			);

	my %where = (
			nonce => $nonce,
			);

	if ($self->{DB_CLIENT}->update({ table => $self->{ELEMENTS_TABLE}, wherevalues => \%where, updatevalues => \%updateValues }) == -1) {
		my $msg = "An error occurred while getting new element identifier";
		$self->{LOGGER}->error($msg);
		return (-1, $msg);
	}

	return (0, $ret_id);
}

1;
