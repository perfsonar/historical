#!/usr/bin/perl

package perfSONAR_PS::MA::Base;
use perfSONAR_PS::Transport;
use XML::LibXML;

@ISA = ('Exporter');
@EXPORT = ();

sub new {
  my ($package, $conf, $ns, $store) = @_; 
  my %hash = ();
  $hash{"FILENAME"} = "perfSONAR_PS::MA::Base";
  $hash{"FUNCTION"} = "\"new\"";
  if(defined $conf and $conf ne "") {
    $hash{"CONF"} = \%{$conf};
  }
  if(defined $ns and $ns ne "") {  
    $hash{"NAMESPACES"} = \%{$ns};     
  }     
  if(defined $store and $store ne "") {
    $hash{"STORE"} = $store;
  }
  else {
    $hash{"STORE"} = "";
  }
  
  $hash{"LISTENER"} = "";
  $hash{"REQUEST"} = "";
  $hash{"REQUESTDOM"} = "";
  $hash{"RESPONSE"} = "";
    
  %{$hash{"RESULTS"}} = ();  
  %{$hash{"TIME"}} = ();
    
  bless \%hash => $package;
}


sub setConf {
  my ($self, $conf) = @_;   
  $self->{FUNCTION} = "\"setConf\"";  
  if(defined $conf and $conf ne "") {
    $self->{CONF} = \%{$conf};
  }
  else {
    error("Missing argument", __LINE__); 
  }
  return;
}


sub setNamespaces {
  my ($self, $ns) = @_;    
  $self->{FUNCTION} = "\"setNamespaces\""; 
  if(defined $namespaces and $namespaces ne "") {   
    $self->{NAMESPACES} = \%{$ns};
  }
  else {
    error("Missing argument", __LINE__);      
  }
  return;
}


sub setStore {
  my ($self, $store) = @_;  
  $self->{FUNCTION} = "\"setStore\"";  
  if(defined $store and $store ne "") {
    $self->{STORE} = $store;
  }
  else {
    error("Missing argument", __LINE__); 
  }
  return;
}


sub init {
  my($self) = @_;
  $self->{FUNCTION} = "\"init\""; 
  if(defined $self->{CONF} and $self->{CONF} ne "") {
    $self->{LISTENER} = new perfSONAR_PS::Transport(
      $self->{CONF}->{"LOGFILE"}, 
      $self->{CONF}->{"PORT"}, 
      $self->{CONF}->{"ENDPOINT"}, 
      "", 
      "", 
      "", 
      $DEBUG);  
    $self->{LISTENER}->startDaemon;
  }
  else {
    error("Missing configuration", __LINE__); 
  }
  return;
}


sub respond {
  my($self) = @_;
  $self->{FUNCTION} = "\"respond\""; 
  print $self->{FILENAME}.":\tSending response \"".$self->{RESPONSE}."\" in ".$self->{FUNCTION}."\n" if($self->{CONF}->{"DEBUG"});
  $self->{LISTENER}->setResponse($self->{RESPONSE}, 1);
  print $self->{FILENAME}.":\tClosing call in ".$self->{FUNCTION}."\n" if($self->{CONF}->{"DEBUG"}); 
  $self->{LISTENER}->closeCall; 
  return;
}


sub error {
  my($msg, $line) = @_;  
  $line = "N/A" if(!defined $line or $line eq "");
  print $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}." at line ".$line.".\n" if($self->{CONF}->{"DEBUG"});
  printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}." at line ".$line.".") 
    if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne "");    
  return;
}


1;


__END__
=head1 NAME

perfSONAR_PS::MA::Base - A module that provides basic methods for MAs.

=head1 DESCRIPTION

This module aims to offer simple methods for dealing with requests for information, and the 
related tasks of interacting with backend storage.  

=head1 SYNOPSIS

    use perfSONAR_PS::MA::Base;

    my %conf = ();
    $conf{"METADATA_DB_TYPE"} = "xmldb";
    $conf{"METADATA_DB_NAME"} = "/home/jason/perfSONAR-PS/MP/SNMP/xmldb";
    $conf{"METADATA_DB_FILE"} = "snmpstore.dbxml";
    $conf{"LOGFILE"} = "./log/perfSONAR-PS-error.log";
    $conf{"DEBUG"} = 1;
    
    my %ns = (
      nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
      netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
      nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
      snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/"    
    );
    
    my $ma = perfSONAR_PS::MA::Base->new(\%conf, \%ns, $store);

    # or
    # $ma = perfSONAR_PS::MA::Base->new;
    # $ma->setConf(\%conf);
    # $ma->setNamespaces(\%ns);    
    # $ma->setStore($store);            

    $ma->init;
    
    my $response = $ma->respond;

=head1 DETAILS

This API is a work in progress, and still does not reflect the general access needed in an MA.
Additional logic is needed to address issues such as different backend storage facilities.  

=head1 API

The offered API is simple, but offers the key functions we need in a measurement archive. 

=head2 new(\%conf, \%ns, \%metadata, \%data)

The accepted arguments may also be ommited in favor of the 'set' functions.

=head2 setConf(\%conf)

(Re-)Sets the value for the 'conf' hash. 

=head2 setStore($store) 

(Re-)Sets the value for the 'store' object, which is really just a XML::LibXML::Document

=head2 init()

Initialize the underlying transportation medium.  This function depends
on certain conf file values.

=head2 respond()

Send message stored in $self->{RESPONSE}.

=head2 error($msg, $line)	

A 'msg' argument is used to print error information to the screen and log files 
(if present).  The 'line' argument can be attained through the __LINE__ compiler directive.  
Meant to be used internally.

=head1 SEE ALSO

L<XML::LibXML::Document>, L<perfSONAR_PS::Transport>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 VERSION

$Id$

=head1 AUTHOR

Jason Zurawski, E<lt>zurawski@internet2.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Jason Zurawski

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.
