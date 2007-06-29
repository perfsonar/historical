#!/usr/bin/perl -w

package perfSONAR_PS::LS::Base;

use warnings;
use Carp qw( carp );
use Exporter;
use Log::Log4perl qw(get_logger);

use perfSONAR_PS::Transport;
use perfSONAR_PS::Messages;

@ISA = ('Exporter');
@EXPORT = ();


sub new {
  my ($package, $conf, $ns) = @_; 
  my %hash = ();
  if(defined $conf and $conf ne "") {
    $hash{"CONF"} = \%{$conf};
  }
  if(defined $ns and $ns ne "") {  
    $hash{"NAMESPACES"} = \%{$ns};     
  }     
  $hash{"LISTENER"} = "";
  $hash{"REQUESTNAMESPACES"} = "";
  $hash{"RESPONSE"} = "";    
  %{$hash{"RESULTS"}} = ();  
  %{$hash{"TIME"}} = ();
    
  bless \%hash => $package;
}


sub setConf {
  my ($self, $conf) = @_;   
  my $logger = get_logger("perfSONAR_PS::LS::Base");
  
  if(defined $conf and $conf ne "") {
    $self->{CONF} = \%{$conf};
  }
  else {
    $logger->error("Missing argument."); 
  }
  return;
}


sub setNamespaces {
  my ($self, $ns) = @_;    
  my $logger = get_logger("perfSONAR_PS::LS::Base");
  
  if(defined $namespaces and $namespaces ne "") {   
    $self->{NAMESPACES} = \%{$ns};
  }
  else {
    $logger->error("Missing argument.");       
  }
  return;
}


sub init {
  my($self) = @_;  
  my $logger = get_logger("perfSONAR_PS::LS::Base");
  
  if(defined $self->{CONF} and $self->{CONF} ne "") {
    $self->{LISTENER} = new perfSONAR_PS::Transport(
      \%{$self->{NAMESPACES}},
      $self->{CONF}->{"PORT"}, 
      $self->{CONF}->{"ENDPOINT"}, 
      "", 
      "", 
      "");  
    $self->{LISTENER}->startDaemon;
  }
  else {
    $logger->error("Missing 'conf' object."); 
  }
  return;
}


sub respond {
  my($self) = @_;
  my $logger = get_logger("perfSONAR_PS::LS::Base");
  
  $logger->debug("Sending response.");
  $self->{LISTENER}->setResponse($self->{RESPONSE}, 1);

  $logger->debug("Closing call.");
  $self->{LISTENER}->closeCall; 
  return;
}


1;


__END__
=head1 NAME

perfSONAR_PS::LS::Base - A module that provides basic methods for LSs.

=head1 DESCRIPTION

This module aims to offer simple methods for dealing with requests for information, and the 
related tasks of interacting with backend storage.  

=head1 SYNOPSIS

    use perfSONAR_PS::LS::Base;

    my %conf = ();
    $conf{"METADATA_DB_TYPE"} = "xmldb";
    $conf{"METADATA_DB_NAME"} = "/home/jason/perfSONAR-PS/LS/xmldb";
    $conf{"METADATA_DB_FILE"} = "store.dbxml";
    
    my %ns = (
      nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
      netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
      nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
      snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/"    
    );
    
    my $self = perfSONAR_PS::LS::Base->new(\%conf, \%ns);

    # or
    # $self = perfSONAR_PS::LS::Base->new;
    # $self->setConf(\%conf);
    # $self->setNamespaces(\%ns);              

    $self->init;
    
    my $response = $self->respond;

=head1 DETAILS

This API is a work in progress, and still does not reflect the general access needed in an LS.

=head1 API

The offered API is simple, but offers the key functions we need in a measurement archive. 

=head2 new(\%conf, \%ns)

The accepted arguments may also be ommited in favor of the 'set' functions.

=head2 setConf(\%conf)

(Re-)Sets the value for the 'conf' hash. 

=head2 init()

Initialize the underlying transportation medium.  This function depends
on certain conf file values.

=head2 respond()

Send message stored in $self->{RESPONSE}.

=head1 SEE ALSO

L<Carp>, L<Exporter>, L<perfSONAR_PS::Transport>, 
L<perfSONAR_PS::Messages>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 VERSION

$Id:$

=head1 AUTHOR

Jason Zurawski, <zurawski@internet2.edu>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Internet2

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
