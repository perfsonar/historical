package perfSONAR_PS::DB::File;

use version; our $VERSION = qv("0.01");

use fields 'FILE', 'XML';

use strict;
use warnings;
use XML::LibXML;
use Log::Log4perl qw(get_logger :nowarn);

sub new {
  my ($package, $file) = @_; 
  my $self = fields::new($package);
  if(defined $file and $file ne "") {
    $self->{FILE} = $file;
  }  
  return $self;
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
  my ($self, $error) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::File");
  if(defined $self->{FILE}) {    
    my $parser = XML::LibXML->new();
    $self->{XML} = $parser->parse_file($self->{FILE});  
  }
  else {
    my $msg = "Cannot open database, missing filename."; 
    $logger->error($msg);
    $$error = $msg if (defined $error);     
    return -1;
  }     
  $$error = "" if (defined $error);             
  return 0;
}


sub closeDB {
  my ($self, $error) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::File");
  if(defined $self->{XML} and $self->{XML} ne "") {
    if(defined open(FILE, ">".$self->{FILE})) {
      print FILE $self->{XML}->toString;
      close(FILE);
      $$error = "" if (defined $error);
      return 0;
    } 
    else {
      my $msg = "Couldn't open output file \"".$self->{FILE}."\"";
      $logger->error($msg);
      $$error = $msg if (defined $error);
      return -1;
    }
  }
  else {
    my $msg = "LibXML DOM structure not defined.";  
    $logger->error($msg);
    $$error = $msg if (defined $error);
    return -1;
  }
}


sub query {
  my ($self, $query, $error) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::File");
  my @results = ();
  if(defined $query and $query ne "") {
    $logger->debug("Query \"".$query."\" received.");
    if(defined $self->{XML} and $self->{XML} ne "") {
      my $nodeset = $self->{XML}->find($query);
      foreach my $node (@{$nodeset}) {                  
        push @results, $node->toString;
      }
      $$error = "" if (defined $error);
      return @results;
    }
    else {
      my $msg = "LibXML DOM structure not defined."; 
      $logger->error($msg);
      $$error = $msg if (defined $error);
      return -1;
    }
  }
  else {
    my $msg = "Missing argument.";
    $logger->error($msg);
    $$error = $msg if (defined $error);
    return -1;
  }  
}


sub querySet {
  my ($self, $query, $error) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::File");
  if(defined $query and $query ne "") {
    $logger->debug("Query \"".$query."\" received.");
    if(defined $self->{XML} and $self->{XML} ne "") {
      $$error = "" if (defined $error);
      return $self->{XML}->find($query);
    }
    else {
      my $msg = "LibXML DOM structure not defined."; 
      $logger->error($msg);
      $$error = $msg if (defined $error);
      return -1;
    }
  }
  else {
    my $msg = "Missing argument.";
    $logger->error($msg);
    $$error = $msg if (defined $error);
    return -1;
  }  
}


sub count {
  my ($self, $query, $error) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::File");
  if(defined $query and $query ne "") {    
    $logger->debug("Query \"".$query."\" received.");
    if(defined $self->{XML} and $self->{XML} ne "") {
      my $nodeset = $self->{XML}->find($query);
      $$error = "" if (defined $error);
      return $nodeset->size();  
    }
    else {
      my $msg = "LibXML DOM structure not defined."; 
      $logger->error($msg);
      $$error = $msg if (defined $error);
      return -1;
    }
  }
  else {
    my $msg = "Missing argument.";
    $logger->error($msg);
    $$error = $msg if (defined $error);
    return -1;
  } 
}


sub getDOM {
  my ($self, $error) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::File");
  if(defined $self->{XML} and $self->{XML} ne "") {
    return $self->{XML};  
  }
  else {
    my $msg = "LibXML DOM structure not defined.";
    $logger->error($msg);
    $$error = $msg if (defined $error); 
  }
  $$error = "" if (defined $error);
  return ""; 
}


sub setDOM {
  my($self, $dom, $error) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::File");
  if(defined $dom and $dom ne "") {    
    $self->{XML} = $dom;
  }
  else {
    my $msg = "Missing argument.";
    $logger->error($msg);
    $$error = $msg if (defined $error);
  }   
  $$error = "" if (defined $error);
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
    
    my $error = "";
    $file->openDB($error);

    print "There are " , $file->count("//nmwg:metadata", $error) , " elements in the file.\n";

    my @results = $file->query("//nmwg:metadata", $error);
    foreach my $r (@results) {
      print $r , "\n";
    }

    $file->closeDB($error);
    
    # If a DOM already exists...
    
    my $dom = XML::LibXML::Document->new("1.0", "UTF-8");
    $file->setDOM($dom, $error);
    
    # or getting back the DOM...
    
    my $dom2 = $file->getDOM($error);
    
=head1 DETAILS

The API is very simple for now, and does not offer things like insert or delete.  At this time
the necessary tooling for XML (XPath, DOM, SAX, etc) does not provide an efficient or prudent
solution to these tasks, so they will probably not be added to this module.  If you wish to 
edit your XML file, do so out of band.   

=head1 API

The API of perfSONAR_PS::DB::File is rather simple, and attempts to mirror the API of 
the other perfSONAR_PS::DB::* modules.  

=head2 new($package, $file)

The only argument is a string representing the file to be opened.

=head2 setFile($self, $file)

(Re-)Sets the name of the file to be used.

=head2 openDB($self, $error)          

Opens the database, will return status of operation.

=head2 closeDB($self, $error)

Close the database, will return status of operation.

=head2 query($self, $query, $error)

Given a query, returns the results or nothing.
  
=head2 querySet($self, $query, $error)

Given a query, returns the results (as a nodeset) or nothing.  
  
=head2 count($self, $query, $error)

Counts the results of a query. 

=head2 getDOM($self, $error)

Returns the internal XML::LibXML DOM object. Will return "" on error.  

=head2 setDOM($self, $dom, $error)

Sets the DOM object.
  
=head1 SEE ALSO

L<XML::LibXML>, L<Log::Log4perl>

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
