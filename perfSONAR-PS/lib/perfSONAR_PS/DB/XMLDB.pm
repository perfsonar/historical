#!/usr/bin/perl

package perfSONAR_PS::DB::XMLDB;

use Sleepycat::DbXml 'simple';
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Common;

sub new {
  my ($package, $env, $cont, $ns) = @_; 
  my %hash = ();
  if(defined $env and $env ne "") {
    $hash{"ENVIRONMENT"} = $env;
  }
  if(defined $cont and $cont ne "") {
    $hash{"CONTAINERFILE"} = $cont; 
  }
  if(defined $ns and $ns ne "") {  
    $hash{"NAMESPACES"} = \%{$ns};     
  }      
  bless \%hash => $package;
}


sub setEnvironment {
  my ($self, $env) = @_;  
  my $logger = get_logger("perfSONAR_PS::DB::XMLDB");
  if(defined $env and $env ne "") {
    $self->{ENVIRONMENT} = $env;
  }
  else {
    $logger->error("Missing argument.");    
  }
  return;
}


sub setContainer {
  my ($self, $cont) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::XMLDB");
  if(defined $cont and $cont ne "") {
    $self->{CONTAINERFILE} = $cont;
  }
  else {
    $logger->error("Missing argument.");
  }
  return;
}


sub setNamespaces {
  my ($self, $ns) = @_;  
  my $logger = get_logger("perfSONAR_PS::DB::XMLDB");
  if(defined $namespaces and $namespaces ne "") {   
    $self->{NAMESPACES} = \%{$ns};
  }
  else {
    $logger->error("Missing argument.");    
  }
  return;
}


sub openDB {
  my ($self) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::XMLDB");
  eval {
    $self->{ENV} = new DbEnv(0);
    $self->{ENV}->set_cachesize(0, 64 * 1024, 1);
    $self->{ENV}->open(
      $self->{ENVIRONMENT},
      Db::DB_INIT_MPOOL|Db::DB_CREATE|Db::DB_INIT_LOCK|Db::DB_INIT_LOG|Db::DB_INIT_TXN
    );   
    $self->{MANAGER} = new XmlManager($self->{ENV});
    $self->{TRANSACTION} = $self->{MANAGER}->createTransaction();  
    $self->{CONTAINER} = $self->{MANAGER}->openContainer(
      $self->{TRANSACTION}, 
      $self->{CONTAINERFILE}, 
      Db::DB_CREATE|Db::DB_DIRTY_READ
    );
    $self->{TRANSACTION}->commit();
  };
  if(my $e = catch std::exception) {
    $logger->error("Error \"".$e->what()."\".");
    return -1;
  }
  elsif($e = catch DbException) {
    $logger->error("Error \"".$e->what()."\".");       
    return -1;
  }        
  elsif($@) {
    $logger->error("Error \"".$@."\".");      
    return -1;
  } 

  return 0;
}


sub xQuery {
  my ($self, $query, $error) = @_; 
  my $logger = get_logger("perfSONAR_PS::DB::XMLDB");
  my @resString = ();
  if(defined $query and $query ne "") {
    my $results = "";
    my $value = "";  
    my $stuff = $self->{CONTAINER}->getName();
    $query =~ s/CHANGEME/$stuff/g;
    eval {
      $logger->debug("Query \"".$query."\" received.");
      $self->{QUERYCONTEXT} = $self->{MANAGER}->createQueryContext();
      foreach my $prefix (keys %{$self->{NAMESPACES}}) {
        $self->{QUERYCONTEXT}->setNamespace($prefix, $self->{NAMESPACES}->{$prefix});
      }          
      $self->{TRANSACTION} = $self->{MANAGER}->createTransaction();
      $results = $self->{MANAGER}->query($self->{TRANSACTION}, $query, $self->{QUERYCONTEXT});
      while( $results->next($value) ) {    
        push @resString, $value."\n";
      }	
      $value = "";
      $self->{TRANSACTION}->commit();
    };
    if(my $e = catch std::exception) {
      my $msg = "Error \"".$e->what()."\".";
      $logger->error($msg);
      $$error = $msg if (defined $error);
      return -1;
    }
    elsif($e = catch DbException) {
      my $msg = "Error \"".$e->what()."\".";    
      $logger->error($msg);
      $$error = $msg if (defined $error);
      return -1;
    }        
    elsif($@) {
      my $msg = "Error \"".$@."\".";      
      $logger->error($msg);
      $$error = $msg if (defined $error);
      return -1;
    }   
  }
  else {
    my $msg = "Missing argument";   
    $logger->error($msg);
    $$error = $msg if (defined $error);
    return -1;
  } 
  $$error = "" if (defined $error);
  return @resString; 
}


sub query {
  my ($self, $query, $error) = @_; 
  my $logger = get_logger("perfSONAR_PS::DB::XMLDB");
  my @resString = ();
  if(defined $query and $query ne "") {
    my $results = "";
    my $value = "";
    my $fullQuery = "collection('".$self->{CONTAINER}->getName()."')$query";  
    eval {
      $logger->debug("Query \"".$fullQuery."\" received.");
      $self->{QUERYCONTEXT} = $self->{MANAGER}->createQueryContext();
      foreach my $prefix (keys %{$self->{NAMESPACES}}) {
        $self->{QUERYCONTEXT}->setNamespace($prefix, $self->{NAMESPACES}->{$prefix});
      }          
      $self->{TRANSACTION} = $self->{MANAGER}->createTransaction();
      $results = $self->{MANAGER}->query($self->{TRANSACTION}, $fullQuery, $self->{QUERYCONTEXT});
      while( $results->next($value) ) {
	$logger->info("Results: $value");
        push @resString, $value."\n";
      }	
      $value = "";
      $self->{TRANSACTION}->commit();
    };
    if(my $e = catch std::exception) {
      my $msg = "Error \"".$e->what()."\".";
      $logger->error($msg);
      $$error = $msg if (defined $error);
      return -1;
    }
    elsif($e = catch DbException) {
      my $msg = "Error \"".$e->what()."\".";    
      $logger->error($msg);
      $$error = $msg if (defined $error);
      return -1;
    }        
    elsif($@) {
      my $msg = "Error \"".$@."\".";      
      $logger->error($msg);
      $$error = $msg if (defined $error);
      return -1;
    }   
  }
  else {
    $msg = "Missing argument";   
    $logger->error($msg);
    $$error = $msg if (defined $error);
    return -1;
  } 
  $$error = "" if (defined $error);
  return @resString; 
}


sub queryForName {
  my ($self, $query) = @_; 
  my $logger = get_logger("perfSONAR_PS::DB::XMLDB");
  my @resString = ();
  if(defined $query and $query ne "") {
    my $results = "";
    my $doc = "";
    my $fullQuery = "collection('".$self->{CONTAINER}->getName()."')$query";  
    eval {
      $logger->debug("Query \"".$fullQuery."\" received.");
      $self->{QUERYCONTEXT} = $self->{MANAGER}->createQueryContext();
      foreach my $prefix (keys %{$self->{NAMESPACES}}) {
        $self->{QUERYCONTEXT}->setNamespace($prefix, $self->{NAMESPACES}->{$prefix});
      }          
      $self->{TRANSACTION} = $self->{MANAGER}->createTransaction();
      $results = $self->{MANAGER}->query($self->{TRANSACTION}, $fullQuery, $self->{QUERYCONTEXT});
      $doc = $self->{MANAGER}->createDocument();
      while( $results->next($doc) ) {
        push @resString, $doc->getName;
      }
      undef $doc;
      undef $results;
      $self->{TRANSACTION}->commit();
    };
    if(my $e = catch std::exception) {
      $logger->error("Error \"".$e->what()."\".");
      return -1;
    }
    elsif($e = catch DbException) {
      $logger->error("Error \"".$e->what()."\".");    
      return -1;
    }        
    elsif($@) {
      $logger->error("Error \"".$@."\".");      
      return -1;
    }   
  }
  else {
    $logger->error("Missing argument");   
    return -1;
  } 
  return @resString; 
}


sub queryByName {
  my ($self, $name) = @_; 
  my $logger = get_logger("perfSONAR_PS::DB::XMLDB");
  my $content = "";
  if(defined $name and $name ne "") {
    eval {
      $logger->debug("Query for name \"".$name."\" received.");
      $self->{TRANSACTION} = $self->{MANAGER}->createTransaction();
      my $document = $self->{CONTAINER}->getDocument($self->{TRANSACTION}, $name);
      $content = $document->getName;
      $self->{TRANSACTION}->commit();
      $logger->debug("Document found.");
    };
    if(my $e = catch std::exception) {
      if($e->getExceptionCode() == 11) {
        $logger->debug("Document not found.");
        return 0;
      }
      else {
        $logger->error("Error \"".$e->what()."\".");
        return -1;      
      }
    }
    elsif($e = catch DbException) {
      $logger->error("Error \"".$e->what()."\".");    
      return -1;
    }        
    elsif($@) {
      $logger->error("Error \"".$@."\".");      
      return -1;
    }   
  }
  else {
    $logger->error("Missing argument");   
    return -1;
  }  
  return $content; 
}

sub getDocumentByName {
  my ($self, $name, $error) = @_; 
  my $logger = get_logger("perfSONAR_PS::DB::XMLDB");
  my $content = "";
  if(defined $name and $name ne "") {
    eval {
      $logger->debug("Query for name \"".$name."\" received.");
      $self->{TRANSACTION} = $self->{MANAGER}->createTransaction();
      my $document = $self->{CONTAINER}->getDocument($self->{TRANSACTION}, $name);
      $content = $document->getContent;
      $self->{TRANSACTION}->commit();
    };
    if(my $e = catch std::exception) {
      if($e->getExceptionCode() == 11) {
        my $msg = "Document not found";
        $logger->debug($msg);
        $$error = $msg if defined $error;
	return "";
      }
      else {
        my $msg = "Error \"".$e->what()."\".";
        $logger->error($msg);
        $$error = $msg if defined $error;
	return "";
      }
    }
    elsif($e = catch DbException) {
      my $msg = "Error \"".$e->what()."\".";
      $logger->error($msg);
      $$error = $msg if defined $error;
      return "";
    }
    elsif($@) {
      my $msg = "Error \"".$@."\".";
      $logger->error($msg);
      $$error = $msg if defined $error;
      return "";
    }
  }
  else {
    my $msg = "Missing argument";
    $logger->error($msg);
    $$error = $msg if defined $error;
    return "";
  }

  $$error = "" if defined $error;
  return ($content);
}

sub updateByName {
  my ($self, $content, $name) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::XMLDB");
  if((defined $content and $content ne "") and 
     (defined $name and $name ne "")) {    
    eval {        
      $logger->debug("Update \"".$content."\" for \"".$name."\".");
      my $myXMLDoc = $self->{MANAGER}->createDocument();
      $myXMLDoc->setContent($content);
      $myXMLDoc->setName($name); 
      $self->{TRANSACTION} = $self->{MANAGER}->createTransaction();     
      $self->{UPDATECONTEXT} = $self->{MANAGER}->createUpdateContext();       
      $self->{CONTAINER}->updateDocument($self->{TRANSACTION}, $myXMLDoc, $self->{UPDATECONTEXT});
      $self->{TRANSACTION}->commit();
    };
    if(my $e = catch std::exception) {
      $logger->error("Error \"".$e->what()."\".");
      return -1;
    }
    elsif($e = catch DbException) {
      $logger->error("Error \"".$e->what()."\"."); 
      return -1;
    }        
    elsif($@) {
      $logger->error("Error \"".$@."\"."); 
      return -1;
    }  
  }     
  else {
    $logger->error("Missing argument");  
    return -1;
  }   

  return 0;
}


sub count {
  my ($self, $query) = @_; 
  my $logger = get_logger("perfSONAR_PS::DB::XMLDB");
  my $results;
  if(defined $query and $query ne "") {
    my $fullQuery = "collection('".$self->{CONTAINER}->getName()."')$query";    
    eval {            
      $logger->debug("Query \"".$fullQuery."\" received.");
      $self->{QUERYCONTEXT} = $self->{MANAGER}->createQueryContext();
      foreach my $prefix (keys %{$self->{NAMESPACES}}) {
        $self->{QUERYCONTEXT}->setNamespace($prefix, $self->{NAMESPACES}->{$prefix});
      }
      $self->{TRANSACTION} = $self->{MANAGER}->createTransaction();            
      $results = $self->{MANAGER}->query($self->{TRANSACTION}, $fullQuery, $self->{QUERYCONTEXT});	
      $self->{TRANSACTION}->commit();	
      return $results->size();
    };
    if(my $e = catch std::exception) {
      $logger->error("Error \"".$e->what()."\".");
    }
    elsif($e = catch DbException) {
      $logger->error("Error \"".$e->what()."\".");  
    }        
    elsif($@) {
      $logger->error("Error \"".$@."\".");    
    }       
  }
  else {
    $logger->error("Missing argument.");    
  } 

  return -1;
}


sub insertIntoContainer {
  my ($self, $content, $name) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::XMLDB");
  if((defined $content and $content ne "") and 
     (defined $name and $name ne "")) {    
    eval {        
      $logger->debug("Insert \"".$content."\" into \"".$name."\".");
      my $myXMLDoc = $self->{MANAGER}->createDocument();
      $myXMLDoc->setContent($content);
      $myXMLDoc->setName($name); 
      $self->{TRANSACTION} = $self->{MANAGER}->createTransaction();     
      $self->{UPDATECONTEXT} = $self->{MANAGER}->createUpdateContext();       
      $self->{CONTAINER}->putDocument($self->{TRANSACTION}, $myXMLDoc, $self->{UPDATECONTEXT}, 0);
      $self->{TRANSACTION}->commit();
    };
    if(my $e = catch std::exception) {
      $logger->error("Error \"".$e->what()."\".");
      return -1;
    }
    elsif($e = catch DbException) {
      $logger->error("Error \"".$e->what()."\"."); 
      return -1;
    }        
    elsif($@) {
      $logger->error("Error \"".$@."\"."); 
      return -1;
    }  
  }     
  else {
    $logger->error("Missing argument");  
    return -1;
  }   

  return 0;
}


sub insertElement {
  my ($self, $query, $content) = @_;     
  my $logger = get_logger("perfSONAR_PS::DB::XMLDB");
  if((defined $content and $content ne "") and (defined $query  and $query ne "")) {          
    my $fullQuery = "collection('".$self->{CONTAINER}->getName()."')$query";     
    eval {
      $logger->debug("Query \"".$fullQuery."\" and content \"".$content."\" received.");
      $self->{TRANSACTION} = $self->{MANAGER}->createTransaction();             
      $self->{QUERYCONTEXT} = $self->{MANAGER}->createQueryContext();
      foreach my $prefix (keys %{$self->{NAMESPACES}}) {
        $self->{QUERYCONTEXT}->setNamespace($prefix, $self->{NAMESPACES}->{$prefix});
      }
      my $results = $self->{MANAGER}->query($self->{TRANSACTION}, $fullQuery, $self->{QUERYCONTEXT});
      my $myXMLMod = $self->{MANAGER}->createModify();
      my $myXMLQueryExpr = $self->{MANAGER}->prepare($self->{TRANSACTION}, $fullQuery, $self->{QUERYCONTEXT});
      $myXMLMod->addAppendStep($myXMLQueryExpr, $myXMLMod->Element, "", $content, -1);
      $self->{UPDATECONTEXT} = $self->{MANAGER}->createUpdateContext();       
      $myXMLMod->execute($self->{TRANSACTION}, $results, $self->{QUERYCONTEXT}, $self->{UPDATECONTEXT});
      $self->{TRANSACTION}->commit();
    };
    if(my $e = catch std::exception) {
      $logger->error("Error \"".$e->what()."\".");
      return -1;
    }
    elsif($e = catch DbException) {
      $logger->error("Error \"".$e->what()."\".");    
      return -1;
    }        
    elsif($@) {
      $logger->error("Error \"".$@."\".");      
      return -1;
    }  
  }     
  else {
    $logger->error("Missing argument."); 
    return -1;
  }   

  return 0;
}


sub remove {
  my ($self, $name) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::XMLDB");
  if(defined $name and $name ne "") {  
    eval {
      $logger->debug("Remove \"".$name."\" received.");
      $self->{TRANSACTION} = $self->{MANAGER}->createTransaction();  
      $self->{UPDATECONTEXT} = $self->{MANAGER}->createUpdateContext();     
      $self->{CONTAINER}->deleteDocument($self->{TRANSACTION}, $name, $self->{UPDATECONTEXT});
      $self->{TRANSACTION}->commit();    
    };
    if(my $e = catch std::exception) {
      $logger->error("Error \"".$e->what()."\".");	
      return -1;
    }
    elsif($e = catch DbException) {
      $logger->error("Error \"".$e->what()."\".");      
      return -1;
    }        
    elsif($@) {
      $logger->error("Error \"".$@."\".");	
      return -1;
    }  
  }     
  else {
    $logger->error("Missing argument.");  
    return -1;
  }   

  return 0;
}

sub closeDB {
  # Perl auto-closes the DB so a specific function to do so is
  # unnecessary, but keeps the API consistent
}


1;


__END__
=head1 NAME

perfSONAR_PS::DB::XMLDB - A module that provides methods for dealing with the Sleepycat [Oracle] 
XML database.

=head1 DESCRIPTION

This module wraps methods and techniques from the Sleepycat::DbXml API for interacting with the 
Sleepycat [Oracle] XML database (version 2.2.13 as tested).  The module is to be treated as an 
object, where each instance of the object represents a direct connection to a single database and
collection.  Each method may then be invoked on the object for the specific database.  

=head1 SYNOPSIS

    use perfSONAR_PS::DB::XMLDB;

    my %ns = (
      nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
      netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
      nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
      snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/"    
    );
  
    my $db = new perfSONAR_PS::DB::XMLDB(
      "/home/jason/Netradar/MP/SNMP/xmldb", 
      "snmpstore.dbxml",
      \%ns
    );

    # or also:
    # 
    # my $db = new perfSONAR_PS::DB::XMLDB;
    # $db->setEnvironment("/home/jason/Netradar/MP/SNMP/xmldb");
    # $db->setContainer("snmpstore.dbxml");
    # $db->setNamespaces(\%ns);    
    
    if ($db->openDB == -1) {
      print "Error opening database\n";
    }

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
    if ($db->insertIntoContainer($xml, "test") == -1) {
      print "Couldn't insert node into container\n";
    }

    my $xml2 = "<nmwg:subject xmlns:nmwg='http://ggf.org/ns/nmwg/base/2.0/'/>";
    if ($db->insertElement("/nmwg:metadata[\@id='test']", $xml2) == -1) {
      print "Couldn't insert element\n";
    }

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

    if ($db->remove("test") == -1) {
      print "Error removing test\n";
    }

=head1 DETAILS

The Sleepycat::DbXml API is simple, but does require a lot of helper code that creates many 
objects and catches many errors.  The methods presented here are rather simple by comparison.

=head1 API

The API of perfSONAR_PS::DB::XMLDB is rather simple, and attempts to
mirror the API of the other perfSONAR_PS::DB::* modules.  

=head2 new($package, $env, $cont, $ns)

The first argument represents the "environment" (the directory where the xmldb was created, 
such as '/home/jason/Netradar/MP/SNMP/xmldb'; this should not be confused with the actual 
installation directory), the third represents the "container" (a specific file that lives 
in the environment, such as 'snmpstore.dbxml'; many containers can live in a single 
environment).  The fourth argument is a hash reference containing a prefix to namespace 
mapping.  All namespaces that may appear in the container should be mapped (there is no 
harm is sending mappings that will not be used).  

=head2 setEnvironment($self, $env)

(Re-)Sets the "environment" (the directory where the xmldb was created, such as 
'/home/jason/Netradar/MP/SNMP/xmldb'; this should not be confused with the actual 
installation directory).

=head2 setContainer($self, $cont)

(Re-)Sets the "container" (a specific file that lives in the environment, such as 'snmpstore.dbxml'; 
many containers can live in a single environment).

=head2 setNamespaces($self, $ns)

(Re-)Sets the hash reference containing a prefix to namespace mapping.  All namespaces that may 
appear in the container should be mapped (there is no harm is sending mappings that will not be 
used).

=head2 openDB($self)

Opens the database

=head2 xQuery($self, $query, \$error)


The string $query must be an XPath expression to be sent to the database.  Examples are:

  //nmwg:metadata
  
    or
    
  //nmwg:parameter[@name="SNMPVersion" and @value="1"]
  
Results are returned as an array of strings or error status.  This function
should be used for XQuery statements.  The error parameter is optional and
is a reference to a scalar. The function will use it to return the error
message if one occurred, it returns the empty string otherwise.

=head2 query($self, $query, \$error)


The string $query must be an XPath expression to be sent to the database.  Examples are:

  //nmwg:metadata
  
    or
    
  //nmwg:parameter[@name="SNMPVersion" and @value="1"]
  
Results are returned as an array of strings or error status.  This function should be
used for XPath statements.  The error parameter is optional and is a reference
to a scalar. The function will use it to return the error message if one
occurred, it returns the empty string otherwise.


=head2 queryForName($self, $query)

Given a query, return the 'name' of the container.

=head2 queryByName($self, $name)

Given a name, see if it exists in the container.  

=head2 updateByName($self, $content, $name)

Update container content by name. 

=head2 count($self, $query)

The string $query must also be an XPath expression that is sent to the database.  
The result of this expression is simple the number of elements that match the 
query. Returns -1 on error.

=head2 insertIntoContainer($self, $content, $name)

Insert the content into the container with the name.  

=head2 insertElement($self, $query, $content)

Perform a query, and insert the content into this result.

=head2 remove($self, $name)

Remove the container w/ the given name.  
  
=head1 SEE ALSO

L<Sleepycat::DbXml>, L<perfSONAR_PS::Common>, L<Log::Log4perl>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 VERSION

$Id: SNMP.pm 227 2007-06-13 12:25:52Z zurawski $

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Internet2

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
