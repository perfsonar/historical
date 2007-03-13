#!/usr/bin/perl

package perfSONAR_PS::DB::File;
use IO::File;
use XML::XPath;
use perfSONAR_PS::Common;
@ISA = ('Exporter');
@EXPORT = ();

our $VERSION = '0.03';

sub new {
  my ($package, $log, $file, $ns) = @_; 
  my %hash = ();
  $hash{"FILENAME"} = "perfSONAR_PS::DB::File";
  $hash{"FUNCTION"} = "\"new\"";
  if(defined $log and $log ne "") {
    $hash{"LOGFILE"} = $log;
  }    
  if(defined $file and $file ne "") {
    $hash{"FILE"} = $file;
  }
  if(defined $ns and $ns ne "") {
    $hash{"NAMESPACES"} = \%{$ns};  
  }    
  bless \%hash => $package;
}


sub setLog {
  my ($self, $log) = @_;  
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


sub setFile {
  my ($self, $file) = @_;  
  $self->{FUNCTION} = "\"setFile\"";  
  if(defined $file and $file ne "") {
    $self->{FILE} = $file;
  }
  else {
    printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION}) 
      if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");  
  }
  return;
}


sub setNamespaces {
  my ($self, $ns) = @_;  
  $self->{FUNCTION} = "\"setNamespaces\""; 
  if(defined $ns and $ns ne "") { 
    $self->{NAMESPACES} = \%{$ns};
  }
  else {
    printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION}) 
      if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");  
  }
  return;
}


sub openDB {
  my ($self) = @_;
  $self->{FUNCTION} = "\"openDB\"";    
  if(defined $self->{FILE}) {    
    $self->{XML} = new IO::File("<".$self->{FILE}) or 
      printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tCannot open file in ".$self->{FUNCTION}) 
        if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");        
    if($self->{XML}) {
      $XML = $self->{XML};
      while (<$XML>) {
        if(!($_ =~ m/^<\?xml.*/)) {
          $self->{XMLCONTENT} .= $_;
        }
      }
      if(defined $self->{NAMESPACES}) {
        $self->{XPATH} = XML::XPath->new( xml => $self->{XMLCONTENT} );
        $self->{XPATH}->clear_namespaces();
        foreach my $prefix (keys %{$self->{NAMESPACES}}) {
          $self->{XPATH}->set_namespace($prefix, $self->{NAMESPACES}->{$prefix});
        }
      }
      else {
        printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tMissing \"namespaces\" in object; used in ".$self->{FUNCTION}) 
          if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");  
      }
    }
  }
  else {
    printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tMissing \"file\" in object; used in ".$self->{FUNCTION}) 
      if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");      
  }                  
  return;
}


sub closeDB {
  my ($self) = @_;
  $self->{FUNCTION} = "\"closeDB\""; 
  if($self->{XML}) {
    $self->{XML}->close();
  }
  else {
    printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tFile handle not open in ".$self->{FUNCTION}) 
      if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");      
  }
  return;
}


sub query {
  my ($self, $query) = @_;
  $self->{FUNCTION} = "\"query\"";        
  my @results = ();
  if(defined $query and $query ne "") {  
    if(defined $self->{XPATH}) {
      my $nodeset = $self->{XPATH}->find($query);
      if($nodeset->size() <= 0) {
        $results[0] = "perfSONAR_PS::DB::File: Nothing matching query " . $query . " found.\n"; 	 
      }
      else {
        foreach my $node ($nodeset->get_nodelist) {            	    
          push @results, XML::XPath::XMLParser::as_string($node);
        }
      }
    }
    else {
      printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tXPath structures not defined in ".$self->{FUNCTION}) 
        if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");        
    }        
  }
  else {
    printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION}) 
      if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");  
  }  
  return @results;
}


sub count {
  my ($self, $query) = @_;
  $self->{FUNCTION} = "\"count\"";  
  my $nodeset = 0;
  if(defined $query and $query ne "") {    
    if(defined $self->{XPATH}) {
      $nodeset = $self->{XPATH}->find($query);
    }
    else {
      printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tXPath structures not defined in ".$self->{FUNCTION}) 
        if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");        
    }   
  }
  else {
    printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION}) 
      if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");  
  } 
  return $nodeset->size;   
}


1;

__END__
=head1 NAME

perfSONAR_PS::DB::File - A module that provides methods for adding 'database like' functions to files 
that contain XML markup.

=head1 DESCRIPTION

This purpose of this module is to ease the burden for someone who simply wishes to use a flat
file as an XML database.  It should be known that this is not recommended as performance will
no doubt suffer, but the ability to do so can be valuable.  The module is to be treated as an 
object, where each instance of the object represents a direct connection to a file.  Each method 
may then be invoked on the object for the specific database.  

=head1 SYNOPSIS

    use perfSONAR_PS::DB::File;

    my %ns = (
      nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
      netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
      nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
      snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/"    
    );
  
    my $file = new perfSONAR_PS::DB::File(
      "./error.log",
      "./store.xml",
      \%ns
    );

    # or also:
    # 
    # my $file = new perfSONAR_PS::DB::File;
    # $file->setLog("./error.log");
    # $file->setFile("./store.xml");
    # $file->setNamespaces(\%ns);    

    $file->openDB();

    print "There are " , $file->count("//nmwg:metadata") , " elements in the file.\n";

    my @results = $file->query("//nmwg:metadata");
    foreach my $r (@results) {
      print $r , "\n";
    }

    $file->closeDB();
    
=head1 DETAILS

The API is very simple for now, and does not offer things like insert or delete.  At this time
the necessary tooling for XML (XPath, DOM, SAX, etc) does not provide an efficient or prudent
solution to these tasks, so they will probably not be added to this module.  If you wish to 
edit your XML file, do so out of band.   

=head1 API

The API of perfSONAR_PS::DB::File is rather simple, and attempts to mirror the API of 
the other perfSONAR_PS::DB::* modules.  

=head2 new($log, $file, \%ns)

The 'log' argument is the name of the log file where error or warning information may be 
recorded.  The second argument is a strings representing the file to be opened.  The third 
argument is a hash reference containing a prefix to namespace mapping.  All namespaces that 
may appear in the file should be mapped (there is no harm is sending mappings that will 
not be used).  

=head2 setLog($log)

(Re-)Sets the name of the log file to be used.

=head2 setFile($file)

(Re-)Sets the name of the file to be used.

=head2 setNamespaces(\%ns)
  
(Re-)Sets the hash reference containing a prefix to namespace mapping.  All namespaces that may 
appear in the container should be mapped (there is no harm is sending mappings that will not be 
used).

=head2 openDB

Opens the file, and creates the necessary objects to read and query the contents. 

=head2 closeDB

Closes the file.

=head2 query($query)

The '$query' string is an XPath expression that will be performed on the open file.  The results
are returned as an array of strings.  

=head2 count($query)

The '$query' string is an XPath expression that will be performed on the open file.  The results
this time are a count of the number of elements that match the XPath expression.
  
=head1 SEE ALSO

L<IO::File>, L<XML::XPath>, L<perfSONAR_PS::Common>, L<perfSONAR_PS::Transport>, 
L<perfSONAR_PS::DB::SQL>, L<perfSONAR_PS::DB::RRD>, L<perfSONAR_PS::DB::XMLDB>, 
L<perfSONAR_PS::MP::SNMP>, L<perfSONAR_PS::MP::Ping>, L<perfSONAR_PS::MA::General>, 
L<perfSONAR_PS::MA::SNMP>, L<perfSONAR_PS::MA::Ping>

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
