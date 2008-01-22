package perfSONAR_PS::Collectors::LinkStatus::Agent::Constant;

our $VERSION = 0.06;

use strict;

sub new($$$$) {
	my ($package, $type, $constant) = @_;

	my %hash = ();

	$hash{"TYPE"} = $type;
	$hash{"CONSTANT"} = $constant;

	bless \%hash => $package;
}

sub getType($) {
	my ($self) = @_;

	return $self->{TYPE};
}

sub setType($$) {
	my ($self, $type) = @_;

	$self->{TYPE} = $type;
}

sub setConstant($$) {
	my ($self, $constant) = @_;

	$self->{CONSTANT} = $constant;
}

sub getConstant($) {
	my ($self) = @_;

	return $self->{CONSTANT};
}

sub run {
	my ($self) = @_;

	my $time = time;

	if (!defined $self->{CONSTANT} or $self->{CONSTANT} eq "") {
		my $msg = "no constant defined";
		return (-1, $msg);
	}

	return (0, $time, $self->{CONSTANT});
}

1;
