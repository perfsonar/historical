package perfSONAR_PS::Collectors::LinkStatus::Agent::Script;

use strict;
use warnings;
use Log::Log4perl qw(get_logger);

our $VERSION = 0.08;

use fields 'TYPE', 'SCRIPT','PARAMETERS';

sub new {
	my ($class, $type, $script, $parameters) = @_;

	my $self = fields::new($class);

	$self->{"TYPE"} = $type;
	$self->{"SCRIPT"} = $script;
	$self->{"PARAMETERS"} = $parameters;

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

sub setScript {
	my ($self, $script) = @_;

	$self->{SCRIPT} = $script;

	return;
}

sub getScript {
	my ($self) = @_;

	return $self->{SCRIPT};
}

sub setParameters {
	my ($self, $parameters) = @_;
	
	$self->{PARAMETERS} = $parameters;

	return;
}

sub getParameters {
	my ($self) = @_;
	
	return $self->{PARAMETERS};
}

sub run {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::Collectors::LinkStatus::Agent::Script");

	my $cmd = $self->{SCRIPT} . " " . $self->{TYPE};

	if (defined $self->{PARAMETERS}) {
		$cmd .= " " . $self->{PARAMETERS};
	}

	$logger->debug("Command to run: $cmd");

	open my $SCRIPT, "-|", $cmd or return (-1, "Couldn't execute cmd: $cmd");
	my @lines = <$SCRIPT>;
	close($SCRIPT);

	if ($#lines < 0) {
		my $msg = "script returned no output";
		return (-1, $msg);
	}

	if ($#lines > 0) {
		my $msg = "script returned invalid output: more than one line";
		return (-1, $msg);
	}

	$logger->debug("Command returned \"$lines[0]\"");

	chomp($lines[0]);
	my ($measurement_time, $measurement_value) = split(',', $lines[0]);

	if (not defined $measurement_time or $measurement_time eq "") {
		my $msg = "script returned invalid output: does not contain measurement time";
		return (-1, $msg);
	}

	if (not defined $measurement_value or $measurement_value eq "") {
		my $msg = "script returned invalid output: does not contain link status";
		return (-1, $msg);
	}

	$measurement_value = lc($measurement_value);

	return (0, $measurement_time, $measurement_value);
}

1;
