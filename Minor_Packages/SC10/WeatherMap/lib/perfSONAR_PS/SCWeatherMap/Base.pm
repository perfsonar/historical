package perfSONAR_PS::SCWeatherMap::Base;

use strict;
use warnings;

use Log::Log4perl qw(get_logger);

use fields 'LOGGER';

use perfSONAR_PS::Utils::ParameterValidation;

=head2 new()

This call instantiates new objects. The object's "init" function must be called
before any interaction can occur.

=cut

sub new {
    my $class = shift;

    my $self = fields::new( $class );

    $self->{LOGGER} = get_logger( $class );

    return $self;
}

=head2 init($self, $conf)

This function initializes the object according to the configuration options set

=cut

sub init {
    my ( $self, $conf ) = @_;

    return (0, "");
}

=head2 run
    Runs the specified filter on the given endpoints, links, icons and background info
=cut
sub run {
    my ( $self ) = @_;
    my $args = validateParams(
        @_,
        {
            current_endpoints  => 1,
            current_links      => 1,
            current_icons      => 1,
            current_background => 1,
        }
    );

    die("Needs to be overridden");
}

1;
