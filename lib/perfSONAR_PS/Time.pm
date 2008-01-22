package perfSONAR_PS::Time;

our $VERSION = 0.06;

use strict;
use Log::Log4perl qw(get_logger);
use Data::Dumper;

sub new {
	my ($package, $type, $arg1, $arg2) = @_;
	my $logger = get_logger("perfSONAR_PS::Time");

	my %hash = ();

	if ($type eq "range") {
		$hash{TYPE} = "range";
		$hash{STARTTIME} = $arg1;
		$hash{ENDTIME} = $arg2;
		$hash{DURATION} = $arg2 - $arg1;
	} elsif ($type eq "duration") {
		$hash{TYPE} = "duration";
		$hash{STARTTIME} = $arg1;
		$hash{DURATION} = $arg2;
	} elsif ($type eq "point") {
		$hash{TYPE} = "point";
		$hash{TIME} = $arg1;
	} else {
		$logger->error("Invalid type: $type");
		return undef;
	}

	bless \%hash => $package;
}

sub getType($) {
	my ($self) = @_;

	return $self->{TYPE};
}

sub getTime($) {
	my ($self) = @_;

	return $self->{TIME};
}

sub getStartTime($) {
	my ($self) = @_;
	if ($self->{TYPE} eq "point") {
		return $self->{TIME};
	} else {
		return $self->{STARTTIME};
	}
}

sub getEndTime($) {
	my ($self) = @_;

	if ($self->{TYPE} eq "duration") {
		return $self->{STARTTIME} + $self->{DURATION};
	} elsif ($self->{TYPE} eq "range") {
		return $self->{ENDTIME};
	} else {
		return $self->{TIME};
	}
}

sub getDuration($) {
	my ($self) = @_;

	return $self->{DURATION};
}

1;

# vim: expandtab shiftwidth=4 tabstop=4
