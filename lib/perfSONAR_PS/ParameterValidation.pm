package perfSONAR_PS::ParameterValidation;

use strict;
use warnings;

use Params::Validate qw(:all);
use Log::Log4perl qw(get_logger :nowarn);

use base 'Exporter';

our @EXPORT = ( 'validateParams', 'validateParamsPos' );

our $logger = get_logger("perfSONAR_PS::ParameterValidation");

use Data::Dumper;

sub validateParams(\@$) {
	my ($params, $options) = @_;

	if ($logger->is_debug()) {
		my @a = @{ $params };
		return validate(@a, $options);
	} else {
		if (ref $params->[0]) {
			# we were passed the parameters in hash form
			$params = $params->[0];
		} elsif (scalar(@{ $params }) % 2 == 0) {
			# if we were passed as the elements as a hash in array form.
			$params = {@{ $params }};

		} else {
			$params = undef;
		}

		return wantarray ? %{ $params } : $params;
	}
}

sub validateParamsPos(\@@) {
	my ($params, @options) = @_;

	if ($logger->is_debug()) {
		my @a = @{ $params };
#		print "Opts: ".Dumper(@options)."\n";
		return validate_pos(@a, @options);
	} else {
		return wantarray ? @{ $params } : $params;
	}
}
