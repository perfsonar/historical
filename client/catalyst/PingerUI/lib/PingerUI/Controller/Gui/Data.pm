package PingerUI::Controller::Gui::Data;

use strict;
use warnings;
use parent 'Catalyst::Controller';

=head1 NAME

PingerUI::Controller::Gui::Data - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index

=cut

sub index :Path :Args(0) {
    my ( $self, $c ) = @_;

    $c->response->body('Matched PingerUI::Controller::Gui::Data in Gui::Data.');
}


=head1 AUTHOR

PingER

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
