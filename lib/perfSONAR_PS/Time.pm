package perfSONAR_PS::Time;

use strict;
use warnings;
use Log::Log4perl qw(get_logger);
use Data::Dumper;

use fields 'TYPE', 'STARTTIME', 'ENDTIME', 'DURATION', 'TIME';

our $VERSION = 0.08;

sub new {
	my ($package, $type, $arg1, $arg2) = @_;
	my $logger = get_logger("perfSONAR_PS::Time");

    my $self = fields::new($package);

	if ($type eq "range") {
		$self->{TYPE} = "range";
		$self->{STARTTIME} = $arg1;
		$self->{ENDTIME} = $arg2;
		$self->{DURATION} = $arg2 - $arg1;
	} elsif ($type eq "duration") {
		$self->{TYPE} = "duration";
		$self->{STARTTIME} = $arg1;
		$self->{DURATION} = $arg2;
	} elsif ($type eq "point") {
		$self->{TYPE} = "point";
		$self->{TIME} = $arg1;
	} else {
		$logger->error("Invalid type: $type");
		return;
	}

    return $self;
}

sub getType {
	my ($self) = @_;

	return $self->{TYPE};
}

sub getTime {
	my ($self) = @_;

	return $self->{TIME};
}

sub getStartTime {
	my ($self) = @_;
	if ($self->{TYPE} eq "point") {
		return $self->{TIME};
	} else {
		return $self->{STARTTIME};
	}
}

sub getEndTime {
	my ($self) = @_;

	if ($self->{TYPE} eq "duration") {
		return $self->{STARTTIME} + $self->{DURATION};
	} elsif ($self->{TYPE} eq "range") {
		return $self->{ENDTIME};
	} else {
		return $self->{TIME};
	}
}

sub getDuration {
	my ($self) = @_;

	return $self->{DURATION};
}

1;

# vim: expandtab shiftwidth=4 tabstop=4
