#!/usr/bin/perl -w

package perfSONAR_PS::LS::Base;

use warnings;
use Exporter;
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Transport;
use perfSONAR_PS::Messages;

@ISA = ('Exporter');
@EXPORT = ();


sub new {
  my ($package, $conf, $port, $endpoint, $directory) = @_;
  my %hash = ();
  if(defined $conf and $conf ne "") {
    $hash{"CONF"} = \%{$conf};
  }
  if(defined $ns and $ns ne "") {  
    $hash{"NAMESPACES"} = \%{$ns};     
  } 
  if(defined $directory and $directory ne "") {
    $hash{"DIRECTORY"} = $directory;
  }
  if (defined $port and $port ne "") {
	  $hash{"PORT"} = $port;
  }

  if (defined $endpoint and $endpoint ne "") {
	  $hash{"ENDPOINT"} = $endpoint;
  }

  $hash{"LISTENER"} = "";
  $hash{"REQUESTNAMESPACES"} = "";
  $hash{"RESPONSE"} = "";    
    
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


sub setDirectory {
  my ($self, $directory) = @_;   
  my $logger = get_logger("perfSONAR_PS::MA::Base");
  
  if(defined $directory and $directory ne "") {
    $self->{DIRECTORY} = $directory;
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
    return $self->{LISTENER}->startDaemon;
  }
  else {
    $logger->error("Missing 'conf' object."); 
    return -1;
  }
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

    my $dirname = dirname($0);
    if (!($dirname =~ /^\//)) {
      $dirname = getcwd . "/" . $dirname;
    }

    my %conf = ();
    $conf{"METADATA_DB_TYPE"} = "xmldb";
    $conf{"METADATA_DB_NAME"} = "/home/jason/perfSONAR-PS/LS/xmldb";
    $conf{"METADATA_DB_FILE"} = "store.dbxml";
    $conf{"METADATA_DB_CONTROL_FILE"} = "control.dbxml";
    
    my %ns = (
      nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
      netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
      nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
      snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/",
      select => "http://ggf.org/ns/nmwg/ops/select/2.0/",
      perfsonar => "http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/",
      psservice => "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/",
      xquery => "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xquery/1.0/",
      xpath => "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xpath/1.0/"
    );
    
    my $self = perfSONAR_PS::LS::Base->new(\%conf, \%ns, $directory);
    if($self->init != 0) {
      print "Couldn't initialize\n";
      exit(-1);
    }
    # or
    # $self = perfSONAR_PS::LS::Base->new;
    # $self->setConf(\%conf);
    # $self->setNamespaces(\%ns);              

    $self->init;

=head1 DETAILS

This API is a work in progress, and still does not reflect the general access needed in an LS.

=head1 API

The offered API is simple, but offers the key functions we need in a measurement archive. 

=head2 new($self, \%conf, \%ns, $directory)

The accepted arguments may also be ommited in favor of the 'set' functions.

=head2 setConf($self, \%conf)

(Re-)Sets the value for the 'conf' hash. 

=head2 setNamespaces($self, \%ns)

(Re-)Sets the hash reference containing a prefix to namespace mapping.  All namespaces that may 
appear in the container should be mapped (there is no harm is sending mappings that will not be 
used).

=head2 setDirectory($self, $dir) 

(Re-)Sets the value for the 'directory', in the event that we are detached from the
calling terminal.

=head2 init()

Initialize the underlying transportation medium.  This function depends
on certain conf file values.

=head1 SEE ALSO

L<Exporter>, L<Log::Log4perl>, L<perfSONAR_PS::Transport>, 
L<perfSONAR_PS::Messages>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list.  Bugs,
feature requests, and improvements can be directed here:

 https://bugs.internet2.edu/jira/browse/PSPS

=head1 VERSION

$Id$

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework along 
with this software.  If not, see <http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2004-2007, Internet2 and the University of Delaware

All rights reserved.

=cut

