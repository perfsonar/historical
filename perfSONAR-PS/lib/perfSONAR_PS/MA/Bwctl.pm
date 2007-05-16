#!/usr/bin/perl

package skeletonMA;
use Carp qw( croak );
use XML::XPath;
use perfSONAR_PS::Common;
use perfSONAR_PS::DB::File;
use perfSONAR_PS::DB::XMLDB;
use perfSONAR_PS::DB::RRD;
use perfSONAR_PS::DB::SQL;
use perfSONAR_PS::MA::General;

use Data::Dumper;

@ISA = ('Exporter');
@EXPORT = ();

our $VERSION = '0.02';
sub new {
  my ($package, $conf, $ns, $metadata, $data) = @_; 
  my %hash = ();
  $hash{"FILENAME"} = "skeletonMA";
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


sub setMetadata {
  my ($self, $metadata) = @_;      
  $self->{FUNCTION} = "\"setMetadata\"";  
  if(defined $metadata and $metadata ne "") {
    $self->{METADATA} = \%{$metadata};
  }
  else {
    error("Missing argument", __LINE__);  
  }
  return;
}


sub setData {
  my ($self, $data) = @_;      
  $self->{FUNCTION} = "\"setData\"";  
  if(defined $data and $data ne "") {
    $self->{DATA} = \%{$data};
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

skeletonMA - A module starting point for MA functions...

=head1 DESCRIPTION

...  

=head1 SYNOPSIS

    use skeletonMA;

    my %conf = ();
    $conf{"METADATA_DB_TYPE"} = "xmldb";
    $conf{"METADATA_DB_NAME"} = "/home/jason/perfSONAR-PS/MP/SNMP/xmldb";
    $conf{"METADATA_DB_FILE"} = "store.dbxml";
    $conf{"LOGFILE"} = "./log/perfSONAR-PS-error.log";

    my %ns = (
      nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
      netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
      nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
      snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/"    
    );

    my $ma = skeletonMA->new(\%conf, \%ns, "", "");
    
    # or
    # $ma = skeletonMA->new;
    # $ma->setConf(\%conf);
    # $ma->setNamespaces(\%ns);
    # $ma->setMetadata("");
    # $ma->setData("");     

=head1 DETAILS

This API is a work in progress, and still does not reflect the general access needed in an MA.
Additional logic is needed to address issues such as different backend storage facilities.  

=head1 API

The offered API is simple, but offers the key functions we need in a measurement archive. 

=head2 new(\%conf)

The only argument represents the 'conf' hash from the calling MA.

=head2 setConf(\%conf)

(Re-)Sets the value for the 'conf' hash. 

=head2 setNamespaces(\%ns)

(Re-)Sets the value for the 'namespace' hash. 

=head2 setMetadata(\%metadata) 

(Re-)Sets the value for the 'metadata' object. 

=head2 setData(\%data) 

(Re-)Sets the value for the 'data' object. 

=head2 error($msg, $line)	

A 'message' argument is used to print error information to the screen and log files 
(if present).  The 'line' argument can be attained through the __LINE__ compiler directive.  
Meant to be used internally.

=head1 SEE ALSO

L<Carp>, L<XML::XPath>, L<perfSONAR_PS::Common>, L<perfSONAR_PS::DB::File>, 
L<perfSONAR_PS::DB::XMLDB>, L<perfSONAR_PS::DB::RRD>, L<perfSONAR_PS::DB::SQL>, 
L<perfSONAR_PS::MA::General>, L<Data::Dumper>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 VERSION

$Id: skeletonMA.pm 132 2007-03-14 21:35:51Z zurawski $

=head1 AUTHOR

Jason Zurawski, E<lt>zurawski@internet2.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Jason Zurawski

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.
