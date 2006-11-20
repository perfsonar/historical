#!/usr/bin/perl

package Netradar::DB::File;
use Carp;
use IO::File;
use XML::XPath;

our $VERSION = '0.01';

sub new {
  my ($package, $file, $namespaces) = @_;   
  if(!defined $file && !defined $namespaces) {
    croak("Missing argument to Netradar::DB::File constructor.\n");
  }
  my %ns = %{$namespaces};  
  my %hash = ();
  $hash{FILE} = $file;
  $hash{NAMESPACES} = \%ns;
  bless \%hash => $package;
}


sub openDB {
  my ($self) = @_;
  $self->{XML} = new IO::File("<".$self->{FILE}) || 
    croak("Netradar::DB::File: Cannot open file " . $self->{FILE} . "\n");
  $XML = $self->{XML};
  while (<$XML>) {
    if(!($_ =~ m/^<\?xml.*/)) {
      $self->{XMLCONTENT} .= $_;
    }
  }                
  $self->{XPATH} = XML::XPath->new( xml => $self->{XMLCONTENT} );
  $self->{XPATH}->clear_namespaces();
  foreach my $prefix (keys %{$self->{NAMESPACES}}) {
    $self->{XPATH}->set_namespace($prefix, $self->{NAMESPACES}->{$prefix});
  }  
  return;
}


sub closeDB {
  my ($self) = @_;
  $self->{XML}->close();
  return;
}


sub query {
  my ($self, $query) = @_;
  my @results = ();
  my $nodeset = $self->{XPATH}->find($query);
  if($nodeset->size() <= 0) {
    $results[0] = "Netradar::DB::File: Nothing matching query " . $query . " found.\n"; 	 
  }
  else {
    foreach my $node ($nodeset->get_nodelist) {            	    
      push @results, XML::XPath::XMLParser::as_string($node);
    }
  }    
  return @results;
}


sub count {
  my ($self, $query) = @_;
  my $nodeset = $self->{XPATH}->find($query);
  return $nodeset->size;
}


1;

__END__
=head1 NAME

Netradar::DB::File - A module that provides methods for adding 'database like' functions to files 
that contain XML markup.

=head1 DESCRIPTION

This purpose of this module is to ease the burden for someone who simply wishes to use a flat
file as an XML database.  It should be known that this is not recommended as performance will
no doubt suffer, but the ability to do so can be valuable.  The module is to be treated as an 
object, where each instance of the object represents a direct connection to a file.  Each method 
may then be invoked on the object for the specific database.  

=head1 SYNOPSIS

    use Netradar::DB::File;

    my %ns = (
      nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
      netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
      nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
      snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/"    
    );
  
    my $file = new Netradar::DB::File(
      "./store.xml",
      \%ns
    );

    $file->openDB();

    print "There are " , $file->count("//nmwg:metadata") , " elements in the file.\n";

    my @results = $file->query("//nmwg:metadata");
    foreach my $r (@results) {
      print $r , "\n";
    }

    $file->closeDB();
    
=head1 DETAILS

The API is very simple for now, and does not offer things like insert or delete, although
there are plans to do this in the future.  

=head1 API

The API of Netradar::DB::File is rather simple, and attempts to mirror the API of 
the other Netradar::DB::* modules.  

=head2 new($file, \%ns)

The first argument is a strings representing the file to be opened.  The second argument is 
a hash reference containing a prefix to namespace mapping.  All namespaces that may appear 
in the file should be mapped (there is no harm is sending mappings that will not be 
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

L<Netradar::Common>, L<Netradar::DB::SQL>, L<Netradar::DB::RRD>, L<Netradar::DB::XMLDB>

To join the 'netradar' mailing list, please visit:

  http://moonshine.pc.cis.udel.edu/mailman/listinfo/netradar

The netradar subversion repository is located at:

  https://damsl.cis.udel.edu/svn/netradar/
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 AUTHOR

Jason Zurawski, E<lt>zurawski@eecis.udel.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2006 by Jason Zurawski

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.
