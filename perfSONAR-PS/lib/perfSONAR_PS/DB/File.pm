#!/usr/bin/perl

package perfSONAR_PS::DB::File;
use Carp;
use IO::File;
use XML::XPath;
@ISA = ('Exporter');
@EXPORT = ();

our $VERSION = '0.02';

sub new {
  my ($package, $file, $namespaces) = @_; 
  my %hash = ();
  $hash{"FILENAME"} = "perfSONAR-PS::DB::File";
  $hash{"FUNCTION"} = "\"new\"";
  if(defined $file) {
    $hash{"FILE"} = $file;
  }
  if(defined $namespaces) {
    my %ns = %{$namespaces};  
    $hash{"NAMESPACES"} = \%ns;  
  }    
  bless \%hash => $package;
}


sub setFile {
  my ($self, $file) = @_;  
  $self->{FUNCTION} = "\"setFile\"";  
  if(defined $file) {
    $self->{FILE} = $file;
  }
  else {
    croak($self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION});
  }
  return;
}


sub setNamespaces {
  my ($self, $namespaces) = @_;  
  $self->{FUNCTION} = "\"setNamespaces\""; 
  if(defined $namespaces) {   
    my %ns = %{$namespaces};
    $self->{NAMESPACES} = \%ns;
  }
  else {
    croak($self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION});
  }
  return;
}


sub openDB {
  my ($self) = @_;
  $self->{FUNCTION} = "\"openDB\"";    
  if(defined $self->{FILE}) {    
    $self->{XML} = new IO::File("<".$self->{FILE}) || 
      croak("perfSONAR-PS::DB::File: Cannot open file " . $self->{FILE} . "\n");
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
      croak($self->{FILENAME}.":\tMissing \"namespaces\" in object; used in function ".$self->{FUNCTION});
    }
  }
  else {
    croak($self->{FILENAME}.":\tMissing \"file\" in object; used in function ".$self->{FUNCTION});
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
    croak($self->{FILENAME}.":\tfilehandle not open in function ".$self->{FUNCTION});
  }
  return;
}


sub query {
  my ($self, $query) = @_;
  $self->{FUNCTION} = "\"query\"";        
  my @results = ();
  if(defined $query) {  
    if(defined $self->{XPATH}) {
      my $nodeset = $self->{XPATH}->find($query);
      if($nodeset->size() <= 0) {
        $results[0] = "perfSONAR-PS::DB::File: Nothing matching query " . $query . " found.\n"; 	 
      }
      else {
        foreach my $node ($nodeset->get_nodelist) {            	    
          push @results, XML::XPath::XMLParser::as_string($node);
        }
      }
    }
    else {
      croak($self->{FILENAME}.":\tXPath structures not defined in function ".$self->{FUNCTION});
    }        
  }
  else {
    croak($self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION});
  }  
  return @results;
}


sub count {
  my ($self, $query) = @_;
  $self->{FUNCTION} = "\"count\"";  
  my $nodeset = 0;
  if(defined $query) {    
    if(defined $self->{XPATH}) {
      $nodeset = $self->{XPATH}->find($query);
    }
    else {
      croak($self->{FILENAME}.":\tXPath structures not defined in function ".$self->{FUNCTION});
    }   
  }
  else {
    croak($self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION});
  } 
  return $nodeset->size;   
}


1;

__END__
=head1 NAME

perfSONAR-PS::DB::File - A module that provides methods for adding 'database like' functions to files 
that contain XML markup.

=head1 DESCRIPTION

This purpose of this module is to ease the burden for someone who simply wishes to use a flat
file as an XML database.  It should be known that this is not recommended as performance will
no doubt suffer, but the ability to do so can be valuable.  The module is to be treated as an 
object, where each instance of the object represents a direct connection to a file.  Each method 
may then be invoked on the object for the specific database.  

=head1 SYNOPSIS

    use perfSONAR-PS::DB::File;

    my %ns = (
      nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
      netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
      nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
      snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/"    
    );
  
    my $file = new perfSONAR-PS::DB::File(
      "./store.xml",
      \%ns
    );

    # or also:
    # 
    # my $file = new perfSONAR-PS::DB::File;
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

The API of perfSONAR-PS::DB::File is rather simple, and attempts to mirror the API of 
the other perfSONAR-PS::DB::* modules.  

=head2 new($file, \%ns)

The first argument is a strings representing the file to be opened.  The second argument is 
a hash reference containing a prefix to namespace mapping.  All namespaces that may appear 
in the file should be mapped (there is no harm is sending mappings that will not be 
used).  

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

L<perfSONAR-PS::Common>, L<perfSONAR-PS::DB::SQL>, L<perfSONAR-PS::DB::RRD>, L<perfSONAR-PS::DB::XMLDB>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 AUTHOR

Jason Zurawski, E<lt>zurawski@eecis.udel.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2006 by Jason Zurawski

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.
