package perfSONAR_PS::Collectors::LinkStatus::Agent::Constant;

use strict;
use warnings;

our $VERSION = 0.08;

use fields 'TYPE', 'CONSTANT';

sub new {
	my ($class, $type, $constant) = @_;

	my $self = fields::new($class);

	$self->{"TYPE"} = $type;
	$self->{"CONSTANT"} = $constant;

	return $self;
}

sub getType {
	my ($self) = @_;

	return $self->{TYPE};
}

sub setType {
	my ($self, $type) = @_;

	$self->{TYPE} = $type;

	return;
}

sub setConstant {
	my ($self, $constant) = @_;

	$self->{CONSTANT} = $constant;

	return;
}

sub getConstant {
	my ($self) = @_;

	return $self->{CONSTANT};
}

sub run {
	my ($self) = @_;

	my $time = time;

	if (not defined $self->{CONSTANT} or $self->{CONSTANT} eq "") {
		my $msg = "no constant defined";
		return (-1, $msg);
	}

	return (0, $time, $self->{CONSTANT});
}

1;
