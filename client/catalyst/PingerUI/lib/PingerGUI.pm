package PingerGUI;

use strict;
use warnings;

use Catalyst::Runtime '5.70';

# Set flags and add plugins for the application
#
#         -Debug: activates the debug mode for very useful log messages
#   ConfigLoader: will load the configuration from a Config::General file in the
#                 application's home directory
# Static::Simple: will serve static files from the application's root
#                 directory

use parent qw/Catalyst/;
use Catalyst qw/-Debug
                ConfigLoader
                Static::Simple
		Session
		Session::Store::File
		Session::State::Cookie
		StackTrace 
		/;
our $VERSION = '3.1.4';
use Catalyst::Log::Log4perl;

# Configure the application.
#
# Note that settings in pingerui.conf (or other external
# configuration file that you set up manually) take precedence
# over this when using ConfigLoader. Thus configuration
# details given here can function as a default configuration,
# with an external configuration file acting as an override for
# local deployment.
__PACKAGE__->config( 'Plugin::ConfigLoader' => { file => '/home/netadmin/LHCOPN/perfSONAR-PS/trunk/client/catalyst/PingerUI/pinger_gui_conf.yml' } );  
##__PACKAGE__->log(Catalyst::Log::Log4perl->new('logger.conf'));
# Start the application
__PACKAGE__->setup();

=head1 NAME

PingerUI - Catalyst based application

=head1 SYNOPSIS

    script/pingerui_server.pl

=head1 DESCRIPTION

 top most module for the catalyst based pinger UI

=head1 SEE ALSO

L<PingerUI::Controller::Root>, L<Catalyst>

=head1 AUTHOR

PingER

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
