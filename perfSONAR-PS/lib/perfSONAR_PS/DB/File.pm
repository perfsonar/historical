#!/usr/bin/perl

package perfSONAR_PS::DB::File;


use XML::LibXML;
use Log::Log4perl qw(get_logger);


sub new {
  my ($package, $file) = @_; 
  my %hash = ();
  if(defined $file and $file ne "") {
    $hash{"FILE"} = $file;
  }  
  bless \%hash => $package;
}


sub setFile {
  my ($self, $file) = @_;  
  my $logger = get_logger("perfSONAR_PS::DB::File");
  if(defined $file and $file ne "") {
    $self->{FILE} = $file;
  }
  else {
    $logger->error("Missing argument.");  
  }
  return;
}


sub openDB {
  my ($self) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::File");
  if(defined $self->{FILE}) {    
    my $parser = XML::LibXML->new();
    $self->{XML} = $parser->parse_file($self->{FILE});  
  }
  else {
    $logger->error("Cannot open database, missing filename.");      
    return -1;
  }                  
  return 0;
}


sub closeDB {
  my ($self) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::File");
  if(defined $self->{XML} and $self->{XML} ne "") {
    if (defined open(FILE, ">".$self->{FILE})) {
      print FILE $self->{XML}->toString;
      close(FILE);
      return 0;
    } else {
      $logger->error("Couldn't open output file \"".$self->{FILE}."\"");
      return -1;
    }
  }
  else {
    $logger->error("LibXML DOM structure not defined.");  
    return -1;
  }
}


sub query {
  my ($self, $query) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::File");
  my @results = ();
  if(defined $query and $query ne "") {
    $logger->debug("Query \"".$query."\" received.");
    if(defined $self->{XML} and $self->{XML} ne "") {
      my $nodeset = $self->{XML}->find($query);
      foreach my $node (@{$nodeset}) {            	    
        push @results, $node->toString;
      }
      return @results;
    }
    else {
      $logger->error("LibXML DOM structure not defined."); 
      return -1;
    }
  }
  else {
    $logger->error("Missing argument.");
    return -1;
  }  
}


sub count {
  my ($self, $query) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::File");
  if(defined $query and $query ne "") {    
    $logger->debug("Query \"".$query."\" received.");
    if(defined $self->{XML} and $self->{XML} ne "") {
      my $nodeset = $self->{XML}->find($query);
      return $nodeset->size();  
    }
    else {
      $logger->error("LibXML DOM structure not defined."); 
      return -1;
    }
  }
  else {
    $logger->error("Missing argument.");
    return -1;
  } 
}


sub getDOM {
  my ($self) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::File");
  if(defined $self->{XML} and $self->{XML} ne "") {
    return $self->{XML};  
  }
  else {
    $logger->error("LibXML DOM structure not defined."); 
  }
  return ""; 
}


sub setDOM {
  my($self, $dom) = @_;
  if(defined $dom and $dom ne "") {    
    $self->{XML} = $dom;
  }
  else {
    $logger->error("Missing argument.");
  }   
  return;
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
  
    my $file = new perfSONAR_PS::DB::File(
      "./store.xml"
    );

    # or also:
    # 
    # my $file = new perfSONAR_PS::DB::File;
    # $file->setFile("./store.xml");  
    
    $file->openDB();

    print "There are " , $file->count("//nmwg:metadata") , " elements in the file.\n";

    my @results = $file->query("//nmwg:metadata");
    foreach my $r (@results) {
      print $r , "\n";
    }

    $file->closeDB();
    
    # If a DOM already exists...
    
    my $dom = XML::LibXML::Document->new("1.0", "UTF-8");
    $file->setDOM($dom);
    
    # or getting back the DOM...
    
    my $dom2 = $file->getDOM();
    
=head1 DETAILS

The API is very simple for now, and does not offer things like insert or delete.  At this time
the necessary tooling for XML (XPath, DOM, SAX, etc) does not provide an efficient or prudent
solution to these tasks, so they will probably not be added to this module.  If you wish to 
edit your XML file, do so out of band.   

=head1 API

The API of perfSONAR_PS::DB::File is rather simple, and attempts to mirror the API of 
the other perfSONAR_PS::DB::* modules.  

=head2 new($file)

The only argument is a string representing the file to be opened.

=head2 setFile($file)

(Re-)Sets the name of the file to be used.

=head2 openDB

Opens the file, and creates the necessary objects to read and query the contents. Will return 0
on success and -1 on failure.

=head2 closeDB

Closes the file. Returns 0 on success and -1 on failure.

=head2 query($query)

The '$query' string is an XPath expression that will be performed on the open file.  The results
are returned as an array of strings. Will return -1 on error.

=head2 count($query)

The '$query' string is an XPath expression that will be performed on the open file.  The results
this time are a count of the number of elements that match the XPath expression. Will return -1
on error.

=head2 getDOM()

Returns the internal XML::LibXML DOM object. Will return "" on error.

=head2 setDOM($dom)

Sets the value of of the internal XML::LibXML DOM object.
  
=head1 SEE ALSO

L<XML::LibXML>, L<perfSONAR_PS::Common>, L<Log::Log4perl>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 VERSION

$Id:$

=head1 AUTHOR

Jason Zurawski, E<lt>zurawski@internet2.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Internet2

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.
