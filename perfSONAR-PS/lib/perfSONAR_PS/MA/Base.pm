#!/usr/bin/perl -w

package perfSONAR_PS::MA::Base;

use warnings;
use Carp qw( carp );
use Exporter;
use Log::Log4perl qw(get_logger);

use perfSONAR_PS::Transport;
use perfSONAR_PS::Messages;
use perfSONAR_PS::MA::General;

@ISA = ('Exporter');
@EXPORT = ();


sub new {
  my ($package, $conf, $ns) = @_; 
  my %hash = ();
  $hash{"FILENAME"} = "perfSONAR_PS::MA::Base";
  $hash{"FUNCTION"} = "\"new\"";
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
  my $logger = get_logger("perfSONAR_PS::MA::Base");
  
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
  my $logger = get_logger("perfSONAR_PS::MA::Base");
  
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
  my $logger = get_logger("perfSONAR_PS::MA::Base");
  
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
  return;
}


sub respond {
  my($self) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::Base");
  
  $logger->debug("Sending response.");
  $self->{LISTENER}->setResponse($self->{RESPONSE}, 1);

  $logger->debug("Closing call.");
  $self->{LISTENER}->closeCall; 
  return;
}

#
# NOTE: (JZ - 7/30/07) This function is depricated
# 

sub keyRequest {
  my($self, $metadatadb, $m, $localContent, $messageId, $messageIdRef) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::Base");
  
  my $queryString = "//nmwg:metadata[" . getMetadatXQuery($self, $m->getAttribute("id"), 0) . "]";
  $logger->debug("Query string \"".$queryString."\" created."); 
	my @resultsString = $metadatadb->query($queryString);

	if($#resultsString != -1) {
	  for(my $x = 0; $x <= $#resultsString; $x++) {
      my $parser = XML::LibXML->new();
      $doc = $parser->parse_string($resultsString[$x]);  
      my $mdset = $doc->find("//nmwg:metadata");
      my $md = $mdset->get_node(1); 

      $logger->debug("Metadata \"".$md->toString()."\" found."); 
      $localContent = $localContent . $md->toString;  
      
      $queryString = "//nmwg:data[\@metadataIdRef=\"".$md->getAttribute("id")."\"]"; 
      $logger->debug("Query string \"".$queryString."\" created."); 
	    my @dataResultsString = $metadatadb->query($queryString);	  
	      	    
	    if($#dataResultsString != -1) {    			  
        for(my $y = 0; $y <= $#dataResultsString; $y++) {
		      $logger->debug("Data \"".$dataResultsString[$y]."\" found."); 
          $localContent = $localContent . $dataResultsString[$y]; 
        } 
        $self->{RESPONSE} = getResultMessage($messageId, $messageIdRef, "MetadataKeyResponse", $localContent);      
	    }
      else {
	      my $msg = "Database \"".$self->{CONF}->{"METADATA_DB_NAME"}."\" returned 0 results for search";
        $logger->error($msg);
        $self->{RESPONSE} = getResultCodeMessage($messageId, $messageIdRef, "MetadataKeyResponse", "error.mp.snmp", $msg);
      }  
	  }
	}
	else {
	  my $msg = "Database \"".$self->{CONF}->{"METADATA_DB_FILE"}."\" returned 0 results for search";
    $logger->error($msg); 
    $self->{RESPONSE} = getResultCodeMessage($messageId, $messageIdRef, "MetadataKeyResponse", "error.mp.snmp", $msg);	     
	}
  return $localContent;
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
    
    my %ns = (
      nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
      netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
      nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
      snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/"    
    );
    
    my $self = perfSONAR_PS::MA::Base->new(\%conf, \%ns);

    # or
    # $self = perfSONAR_PS::MA::Base->new;
    # $self->setConf(\%conf);
    # $self->setNamespaces(\%ns);              

    $self->init;
    
    my $response = $self->respond;
    if(!$response) {
      $self->error($self, "Whoops...", __LINE__)
    }

=head1 DETAILS

This API is a work in progress, and still does not reflect the general access needed in an MA.
Additional logic is needed to address issues such as different backend storage facilities.  

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

=head2 keyRequest(($self, $metadatadb, $m, $localContent, $messageId, $messageIdRef)

DEPRICATED

=head1 SEE ALSO

L<Carp>, L<Exporter>, L<Log::Log4perl>, L<perfSONAR_PS::Transport>, 
L<perfSONAR_PS::Messages>, L<perfSONAR_PS::MA::General>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 VERSION

$Id$

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Internet2

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
