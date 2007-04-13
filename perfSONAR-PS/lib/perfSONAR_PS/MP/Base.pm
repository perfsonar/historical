#!/usr/bin/perl

package perfSONAR_PS::MP::Base;

@ISA = ('Exporter');
@EXPORT = ();

sub new {
  my ($package, $conf, $ns, $store) = @_; 
  my %hash = ();
  $hash{"FILENAME"} = "perfSONAR_PS::MP::Base";
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

  %{$hash{"METADATAMARKS"}} = ();
  %{$hash{"DATAMARKS"}} = ();
  %{$hash{"DATADB"}} = ();
  %{$hash{"LOOKUP"}} = ();
  %{$hash{"AGENT"}} = ();
      
  bless \%hash => $package;
}


sub setConf {
  my ($self, $conf) = @_;  
  $self->{FILENAME} = "perfSONAR_PS::MP::Base";  
  $self->{FUNCTION} = "\"setHost\"";  
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
  $self->{FILENAME} = "perfSONAR_PS::MP::Base";  
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
  $self->{FILENAME} = "perfSONAR_PS::MP::Base";    
  $self->{FUNCTION} = "\"setStore\"";  
  if(defined $store and $store ne "") {
    $self->{STORE} = $store;
  }
  else {
    error("Missing argument", __LINE__); 
  }
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

perfSONAR_PS::MP::Base - A module that provides basic methods for MP services.

=head1 DESCRIPTION

The purpose of this module is to create simple objects that contain all necessary information
to create other MP based objects.  

=head1 SYNOPSIS

    use perfSONAR_PS::MP::Base;
    
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
    
    my $mp = new perfSONAR_PS::MP::Base(\%conf, \%ns, "", "");

    # or 
    # my $mp = new perfSONAR_PS::MP::Base;
    # $mp->setConf(\%conf);
    # $mp->setNamespaces(\%ns);
    # $mp->setStore($store);
            
=head1 DETAILS

This API is a work in progress, but is starting to capture the basics of an MP.

=head1 API

The offered API is simple, but offers the key functions we need in a measurement point. 

=head2 new(\%conf, \%ns, \%metadata, \%data)

The first argument represents the 'conf' hash from the calling MP.  The second argument
is a hash of namespace values.  The final 2 values are structures containing metadata or 
data information.  

=head2 setConf(\%conf)

(Re-)Sets the value for the 'conf' hash.  

=head2 setNamespaces(\%ns)

(Re-)Sets the value for the 'namespace' hash. 

=head2 setStore($store) 

(Re-)Sets the value for the 'store' object, which is really just a XML::LibXML::Document. 

=head2 error($msg, $line)	

A 'message' argument is used to print error information to the screen and log files 
(if present).  The 'line' argument can be attained through the __LINE__ compiler directive.  
Meant to be used internally.

=head1 SEE ALSO

L<XML::LibXML::Document>

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
