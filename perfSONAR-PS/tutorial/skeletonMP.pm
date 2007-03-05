#!/usr/bin/perl

package skeletonMP;
use perfSONAR_PS::Common;
use perfSONAR_PS::DB::File;
use perfSONAR_PS::DB::XMLDB;
use perfSONAR_PS::DB::RRD;
use perfSONAR_PS::DB::SQL;

use Data::Dumper;

@ISA = ('Exporter');
@EXPORT = ();
our $VERSION = '0.02';

# ================ Internal Package skeletonMP::Agent ================

package skeletonMP::Agent;
use perfSONAR_PS::Common;
sub new {
  my ($package, $log) = @_; 
  my %hash = ();
  $hash{"FILENAME"} = "skeletonMP::Agent";
  $hash{"FUNCTION"} = "\"new\"";
  if(defined $log and $log ne "") {
    $hash{"LOGFILE"} = $log;
  }  
  bless \%hash => $package;
}


sub setLog {
  my ($self, $log) = @_;  
  $self->{FILENAME} = "skeletonMP::Agent";
  $self->{FUNCTION} = "\"setLog\"";  
  if(defined $log and $log ne "") {
    $self->{LOGFILE} = $log;
  }
  else {
    printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION}) 
      if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");    
  }
  return;
}


# ================ Main Package skeletonMP ================


package skeletonMP;
sub new {
  my ($package, $conf, $ns, $metadata, $data) = @_; 
  my %hash = ();
  $hash{"FILENAME"} = "skeletonMP";
  $hash{"FUNCTION"} = "\"new\"";
  if(defined $conf and $conf ne "") {
    $hash{"CONF"} = \%{$conf};
  }
  if(defined $ns and $ns ne "") {  
    $hash{"NAMESPACES"} = \%{$ns};     
  }    
  if(defined $metadata and $metadata ne "") {
    $hash{"METADATA"} = \%{$metadata};
  }
  else {
    %{$hash{"METADATA"}} = ();
  }  
  if(defined $data and $data ne "") {
    $hash{"DATA"} = \%{$data};
  }
  else {
    %{$hash{"DATA"}} = ();
  }

  %{$hash{"METADATAMARKS"}} = ();
  %{$hash{"DATADB"}} = ();
  %{$hash{"LOOKUP"}} = ();
  %{$hash{"AGENT"}} = ();
      
  bless \%hash => $package;
}


sub setConf {
  my ($self, $conf) = @_;  
  $self->{FILENAME} = "skeletonMP";  
  $self->{FUNCTION} = "\"setHost\"";  
  if(defined $conf and $conf ne "") {
    $self->{CONF} = \%{$conf};
  }
  else {
    printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION}) 
      if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne "");    
  }
  return;
}


sub setNamespaces {
  my ($self, $ns) = @_;  
  $self->{FILENAME} = "skeletonMP";  
  $self->{FUNCTION} = "\"setNamespaces\""; 
  if(defined $namespaces and $namespaces ne "") {   
    $self->{NAMESPACES} = \%{$ns};
  }
  else {
    printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION}) 
      if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne "");    
  }
  return;
}


sub setMetadata {
  my ($self, $metadata) = @_;  
  $self->{FILENAME} = "skeletonMP";    
  $self->{FUNCTION} = "\"setMetadata\"";  
  if(defined $metadata and $metadata ne "") {
    $self->{METADATA} = \%{$metadata};
  }
  else {
    printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION}) 
      if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne "");    
  }
  return;
}


sub setData {
  my ($self, $data) = @_;  
  $self->{FILENAME} = "skeletonMP";    
  $self->{FUNCTION} = "\"setData\"";  
  if(defined $data and $data ne "") {
    $self->{DATA} = \%{$data};
  }
  else {
    printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION}) 
      if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne "");    
  }
  return;
}


1;


__END__


=head1 NAME

skeletonMP - A module starting point for MP functions...

=head1 DESCRIPTION

...

=head1 SYNOPSIS

    use skeletonMP;

    my %conf = ();
    $conf{"METADATA_DB_TYPE"} = "xmldb";
    $conf{"METADATA_DB_NAME"} = "/home/jason/perfSONAR-PS/MP/SNMP/xmldb";
    $conf{"METADATA_DB_FILE"} = "snmpstore.dbxml";
    $conf{"RRDTOOL"} = "/usr/local/rrdtool/bin/rrdtool";
    $conf{"LOGFILE"} = "./log/perfSONAR-PS-error.log";

    my %ns = (
      nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
      netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
      nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
      snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/"    
    );
    
    my $mp = new skeletonMP(\%conf, \%ns, "", "");

=head1 DETAILS

This module contains a submodule that is not meant to act as a standalone, but rather as
a specialized structure for use only in this module.  The functions include:


  new($log)

    The 'log' argument is the name of the log file where error or warning information may be 
    recorded.

  setLog($log)

    (Re-)Sets the log file for the SNMP object.


A brief description using the API:
   
    my $agent = new skeletonMP::Agent("./error.log");

    # or also:
    # 
    # my $agent = new skeletonMP::Agent;
    # $agent->setLog("./error.log");


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

=head2 setMetadata(\%metadata) 

(Re-)Sets the value for the 'metadata' object. 

=head2 setData(\%data) 

(Re-)Sets the value for the 'data' object. 

=head1 SEE ALSO

L<Net::SNMP>, L<perfSONAR_PS::Common>, L<perfSONAR_PS::Transport>, L<perfSONAR_PS::DB::SQL>, 
L<perfSONAR_PS::DB::RRD>, L<perfSONAR_PS::DB::File>, L<perfSONAR_PS::DB::XMLDB>, L<perfSONAR_PS::MP::SNMP>, 
L<perfSONAR_PS::MA::General>, L<perfSONAR_PS::MA::SNMP>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 AUTHOR

Jason Zurawski, E<lt>zurawski@eecis.udel.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Jason Zurawski

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.
