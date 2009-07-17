package PingerUI::Controller::Root;

use strict;
use warnings;
use parent 'Catalyst::Controller';

#
# Sets the actions in this controller to be registered with no prefix
# so they function identically to actions created in MyApp.pm
#
__PACKAGE__->config->{namespace} = '';

=head1 NAME

PingerUI::Controller::Root - Root Controller for PingerUI

=head1 DESCRIPTION

[enter your description here]

=head1 METHODS

=cut

=head2 index

=cut

sub index :Path :Args(0) {
    my ( $self, $c ) = @_;

    # Hello World
    $c->response->body( $c->welcome_message );
}

sub default :Path {
    my ( $self, $c ) = @_;
    $c->response->body( 'Page not found' );
    $c->response->status(404);
}


 # called after all actions are finished
sub end : Private {
   my ( $self, $c ) = @_;
   $c->response->header('Cache-Control' => 'no-cache');

   if ( scalar @{ $c->error } ) {
        $c->stash->{message} =  $c->error; 
        $c->stash->{template} = 'gui/error.tmpl';
   } # handle errors
   return if $c->res->body; # already have a response
}


=head2 end

Attempt to render a view, if needed.

=cut

sub end : ActionClass('RenderView') {}

=head1 AUTHOR

PingER

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
