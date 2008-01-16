package perfSONAR_PS::Collectors::LinkStatus::Status;

our $VERSION = 0.02;

use perfSONAR_PS::Status::Common;

use strict;

sub new($$$$) {
	my ($package, $time, $oper_state, $admin_state) = @_;

	my %hash = ();

	if (defined $time and $time ne "") {
		$hash{"TIME"} = $time;
	}

	if (defined $oper_state and $oper_state ne "") {
		if (isValidOperState($oper_state) == 0) {
			return undef;
		}

		$hash{"OPER_STATE"} = $oper_state;
	}

 	if (defined $admin_state and $admin_state ne "" and isValidAdminState($admin_state) == 0) {
		if (isValidAdminState($admin_state) == 0) {
			return undef;
		}

		$hash{"ADMIN_STATE"} = $admin_state;
	}

	bless \%hash => $package;
}

sub getTime($) {
	my ($self) = @_;

	return $self->{TIME};
}

sub getOperState($) {
	my ($self) = @_;

	return $self->{OPER_STATE};
}

sub getAdminState($) {
	my ($self) = @_;

	return $self->{ADMIN_STATE};
}

sub setTime($$) {
	my ($self, $time) = @_;

	$self->{TIME} = $time;
}

sub setOperState($$) {
	my ($self, $oper_state) = @_;

	if (isValidOperState($oper_state) == 0) {
		return -1;
	}

	$self->{OPER_STATE} = $oper_state;

	return 0;
}

sub setAdminState($$) {
	my ($self, $admin_state) = @_;

	if (isValidAdminState($admin_state) == 0) {
		return -1;
	}

	$self->{ADMIN_STATE} = $admin_state;

	return 0;
}

sub updateOperState($$) {
	my ($self, $oper_state) = @_;

	if (isValidOperState($oper_state) == 0) {
		return -1;
	}

	if (!defined $self->{OPER_STATE}) {
		$self->{OPER_STATE} = $oper_state;
	} elsif ($self->{OPER_STATE} eq "unknown" or $oper_state eq "unknown") {
		$self->{OPER_STATE} = "unknown";
	} elsif ($self->{OPER_STATE} eq "down" or $oper_state eq "down")  {
		$self->{OPER_STATE} = "down";
	} elsif ($self->{OPER_STATE} eq "degraded" or $oper_state eq "degraded")  {
		$self->{OPER_STATE} = "degraded";
	} elsif ($self->{OPER_STATE} eq "up" or $oper_state eq "up")  {
		$self->{OPER_STATE} = "up";
	}

	return 0;
}

sub updateAdminState($$) {
	my ($self, $admin_state) = @_;

	if (isValidAdminState($admin_state) == 0) {
		return -1;
	}

	if (!defined $self->{ADMIN_STATE}) {
		$self->{ADMIN_STATE} = $admin_state;
	} elsif ($self->{ADMIN_STATE} eq "unknown" or $admin_state eq "unknown") {
		$self->{ADMIN_STATE} = "unknown";
	} elsif ($self->{ADMIN_STATE} eq "maintenance" or $admin_state eq "maintenance") {
		$self->{ADMIN_STATE} = "maintenance";
	} elsif ($self->{ADMIN_STATE} eq "troubleshooting" or $admin_state eq "troubleshooting") {
		$self->{ADMIN_STATE} = "troubleshooting";
	} elsif ($self->{ADMIN_STATE} eq "underrepair" or $admin_state eq "underrepair") {
		$self->{ADMIN_STATE} = "underrepair";
	} elsif ($self->{ADMIN_STATE} eq "normaloperation" or $admin_state eq "normaloperation") {
		$self->{ADMIN_STATE} = "normaloperation";
	}

	return 0;
}

1;
