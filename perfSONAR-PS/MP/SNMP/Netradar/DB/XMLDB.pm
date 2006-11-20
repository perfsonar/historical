#!/usr/bin/perl

package Netradar::DB::XMLDB;
use Carp;
use Sleepycat::DbXml 'simple';

our $VERSION = '0.01';

sub new {
  my ($package, $env, $cont, $namespaces) = @_;   
  if(!defined $env && !defined $conf && !defined $namespaces) {
    croak("Missing argument to Netradar::DB::XMLDB constructor.\n");
  }
  my %ns = %{$namespaces};  
  my %hash = ();
  $hash{"ENVIRONMENT"} = $env;
  $hash{"CONTAINERFILE"} = $cont;
  $hash{"NAMESPACES"} = \%ns;
  bless \%hash => $package;
}


sub openDB {
  my ($self) = @_;
  eval {
    my $env = new DbEnv(0);
    $env->set_cachesize(0, 64 * 1024, 1);
    $env->open(
      $self->{ENVIRONMENT},
      Db::DB_INIT_MPOOL|Db::DB_CREATE|Db::DB_INIT_LOCK|Db::DB_INIT_LOG|Db::DB_INIT_TXN
    );
  
    $self->{MANAGER} = new XmlManager($env);
    $self->{TRANSACTION} = $self->{MANAGER}->createTransaction();  
    $self->{CONTAINER} = $self->{MANAGER}->openContainer(
      $self->{TRANSACTION}, 
      $self->{CONTAINERFILE}, 
      Db::DB_CREATE
    );
    $self->{TRANSACTION}->commit();
  };
  if (my $e = catch std::exception) {
    croak("Netradar::DB::XMLDB Error: ".$e->what());
    exit(-1);
  }
  elsif ($@) {
    croak("Netradar::DB::XMLDB Error: ".$@);  
    exit(-1);
  } 
}


sub setup {
  my ($self) = @_;
  eval {
    $self->{TRANSACTION} = $self->{MANAGER}->createTransaction();  
    $self->{UPDATECONTEXT} = $self->{MANAGER}->createUpdateContext();            
    $self->{QUERYCONTEXT} = $self->{MANAGER}->createQueryContext();
    foreach my $prefix (keys %{$self->{NAMESPACES}}) {
      $self->{QUERYCONTEXT}->setNamespace($prefix, $self->{NAMESPACES}->{$prefix});
    }
  };
  if (my $e = catch std::exception) {
    croak("Netradar::DB::XMLDB Error: ".$e->what());
    exit(-1);
  }
  elsif ($@) {
    croak("Netradar::DB::XMLDB Error: ".$@);  
    exit(-1);
  }   
  return;
}


sub closeDB {
  my ($self) = @_;
  return;
}


sub query {
  my ($self, $query) = @_;
  setup($self);
  my $results = "";
  my $value = "";
  my @resString = ();
  my $fullQuery = "collection('".$self->{CONTAINER}->getName()."')$query";
  eval {
    $results = $self->{MANAGER}->query($fullQuery, $self->{QUERYCONTEXT});
    while( $results->next($value) ) {
      push @resString, $value."\n";
    }	
    $value = "";
    $self->{TRANSACTION}->commit();
  };
  if (my $e = catch std::exception) {
    croak("Query " . $fullQuery . " failed\t-\t".$e->what());
    exit( -1 );
  }
  elsif ($@) {
    croak("Query " . $fullQuery . " failed\t-\t".$@);
    exit( -1 );
  }     
  return @resString;
}


sub count {
  my ($self, $query) = @_;
  setup($self);
  my $results;
  my $fullQuery = "collection('".$self->{CONTAINER}->getName()."')$query";
  eval {
    $results = $self->{MANAGER}->query($fullQuery, $self->{QUERYCONTEXT});	
    $self->{TRANSACTION}->commit();	
  };
  if (my $e = catch std::exception) {
    croak("Query " . $fullQuery . " failed\t-\t".$e->what());
    exit( -1 );
  }
  elsif ($@) {
    croak("Query " . $fullQuery . " failed\t-\t".$@);
    exit( -1 );
  }      
  return $results->size();
}


sub insert {
  my ($self, $content, $name) = @_;
  setup($self);  
  eval {
    my $myXMLDoc = $self->{MANAGER}->createDocument();
    $myXMLDoc->setContent($content);
    $myXMLDoc->setName($name); 
    $self->{CONTAINER}->putDocument($self->{TRANSACTION}, $myXMLDoc, $self->{UPDATECONTEXT}, 0);
    $self->{TRANSACTION}->commit();
  };
  if (my $e = catch std::exception) {
    croak("Insert \"" . $content . "\" failed\t-\t".$e->what());
    exit( -1 );
  }
  elsif ($@) {
    croak("Insert \"" . $content . "\" failed\t-\t".$@);
    exit( -1 );
  }      
  return;
}


sub remove {
  my ($self, $name) = @_;
  setup($self);  
  eval {
    $self->{CONTAINER}->deleteDocument($self->{TRANSACTION}, $name, $self->{UPDATECONTEXT});
    $self->{TRANSACTION}->commit();    
  };
  if (my $e = catch std::exception) {
    croak("Remove \"" . $content . "\" failed\t-\t".$e->what());
    exit( -1 );
  }
  elsif ($@) {
    croak("remove \"" . $content . "\" failed\t-\t".$@);
    exit( -1 );
  }   
  return;
}


1;

__END__
=head1 NAME

Netradar::DB::XMLDB - A module that provides methods for dealing with the Sleepycat [Oracle] XML database.

=head1 DESCRIPTION

This module wraps methods and techniques from the Sleepycat::DbXml API for interacting with the 
Sleepycat [Oracle] XML database (version 2.2.13 as tested).  The module is to be treated as an 
object, where each instance of the object represents a direct connection to a single database and
collection.  Each method may then be invoked on the object for the specific database.  

=head1 SYNOPSIS

    use Netradar::DB::XMLDB;

    my %ns = (
      nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
      netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
      nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
      snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/"    
    );
  
    my $db = new Netradar::DB::XMLDB(
      "/home/jason/Netradar/MP/SNMP/xmldb", 
      "snmpstore.dbxml",
      \%ns
    );

    $db->openDB;

    print "There are " , $db->count("//nmwg:metadata") , " elements in the XMLDB.\n\n";

    my @resultsString = $db->query("//nmwg:metadata");   
    if($#resultsString != -1) {    
      for(my $x = 0; $x <= $#resultsString; $x++) {	
        print $x , ": " , $resultsString[$x], "\n";
      }
    }
    else {
      print "Nothing Found.\n";
    }  

    my $xml = "<nmwg:metadata xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\" id=\"test\" />";
    $db->insert($xml, "test");

    $db->remove("test");

    $db->closeDB;    

=head1 DETAILS

The Sleepycat::DbXml API is simple, but does require a lot of helper code that creates many 
objects and catches many errors.  The methods presented here are rather simple by comparison.

=head1 API

The API of Netradar::DB::XMLDB is rather simple, and attempts to
mirror the API of the other Netradar::DB::* modules.  

=head2 new($env, $cont, \%ns)

The first 2 arguments are strings, the first representing the "environment" (the directory
where the xmldb was created, such as '/home/jason/Netradar/MP/SNMP/xmldb'; this should not
be confused with the actual installation directory), the second representing the "container" 
(a specific file that lives in the environment, such as 'snmpstore.dbxml'; many containers
can live in a single environment).  The third argument is a hash reference containing a 
prefix to namespace mapping.  All namespaces that may appear in the container should be
mapped (there is no harm is sending mappings that will not be used).  

=head2 openDB

Opens and initializes objects for interacting with the database such as managers and 
containers.

=head2 setup

Creates transactions and contexts for actions such as queries, inserts, and deletes.

=head2 closeDB

The XMLDB does not need to be closed, so this function does nothing.  It is kept to 
match the API's of the other Netradar::DB::* modules. 

=head2 query($query)

The string $query must be an XPath expression to be sent to the database.  Examples are:

  //nmwg:metadata
  
    or
    
  //nmwg:parameter[@name="SNMPVersion" && @value="1"]
  
Results are returned as an array of strings.

=head2 count($query)

The string $query must also be an XPath expression that is sent to the database.  
The result of this expression is simple the number of elements that match the 
query.

=head2 insert($content, $name)

The first argument, '$content', is XML markup in string form.  It should of course be
well formed.  The second argument, '$name', is the name to be used in the database
for this content.  Think of this as the 'primary key'.  Most times the 'id' field of
the XML element can be used for the name safely.  

=head2 remove($name)

The only argument here, '$name', is the name (primary key) of the element to be removed
from the database.   

=head1 SEE ALSO

L<Netradar::Common>, L<Netradar::DB::SQL>, L<Netradar::DB::RRD>, L<Netradar::DB::File>

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
