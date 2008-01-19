package perfSONAR_PS::DB::XMLDB;

use fields 'ENVIRONMENT', 'CONTAINERFILE', 'NAMESPACES', 'ENV', 'MANAGER', 'CONTAINER', 'INDEX';

our $VERSION = 0.03;

use strict;
use warnings;
use Sleepycat::DbXml 'simple';
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Common;

sub new {
  my ($package, $env, $cont, $ns) = @_; 
  my $self = fields::new($package);
  if(defined $env and $env ne "") {
    $self->{ENVIRONMENT} = $env;
  }
  if(defined $cont and $cont ne "") {
    $self->{CONTAINERFILE} = $cont; 
  }
  if(defined $ns and $ns ne "") {  
    $self->{NAMESPACES} = \%{$ns};     
  }      
  return $self;
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
  if(defined $ns and $ns ne "") {   
    $self->{NAMESPACES} = \%{$ns};
  }
  else {
    $logger->error("Missing argument.");    
  }
  return;
}


sub prep {
  my ($self, $txn, $error) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::XMLDB");

  my $dbTr = "";
  my $atomic = 1;
  if(defined $txn and $txn ne "") {
    $dbTr = $txn;
    $atomic = 0;
  }
    
  eval {
    $self->{ENV} = new DbEnv(0);
    $self->{ENV}->open(
      $self->{ENVIRONMENT},
      Db::DB_JOINENV|Db::DB_INIT_MPOOL|Db::DB_CREATE|Db::DB_INIT_LOCK|Db::DB_INIT_LOG|Db::DB_INIT_TXN|Db::DB_RECOVER|Db::DB_REGISTER
    );   

    $self->{MANAGER} = new XmlManager(
      $self->{ENV},
      DbXml::DBXML_ALLOW_EXTERNAL_ACCESS|DbXml::DBXML_ALLOW_AUTO_OPEN
    );

    $dbTr = $self->{MANAGER}->createTransaction() if $atomic;  
    $self->{CONTAINER} = $self->{MANAGER}->openContainer(
      $dbTr, 
      $self->{CONTAINERFILE}, 
      Db::DB_CREATE|Db::DB_DIRTY_READ|DbXml::DBXML_TRANSACTIONAL
    );
    
    if(!$self->{CONTAINER}->getIndexNodes) {
      my $dbUC = $self->{MANAGER}->createUpdateContext(); 
      $self->{INDEX} = $self->{CONTAINER}->addIndex(
        $dbTr,
        "http://ggf.org/ns/nmwg/base/2.0/",
        "store",
        "node-element-equality-string",
        $dbUC
      ); 
    }   
    
    $dbTr->commit if $atomic; 
    undef $dbTr if $atomic; 
  };
 
  $dbTr->abort if($dbTr and $atomic);
  undef $dbTr if $atomic;
  
  if(my $e = catch std::exception) {
    my $msg = "Error \"".$e->what()."\".";
    $msg =~ s/(\n+|\s+)/ /g;
    $msg = escapeString($msg);
    $logger->error($msg);
    $$error = $msg if (defined $error);
    return -1;
  }
  elsif($e = catch DbException) {
    my $msg = "Error \"".$e->what()."\".";
    $msg =~ s/(\n+|\s+)/ /g;
    $msg = escapeString($msg);
    $logger->error($msg); 
    $$error = $msg if (defined $error);
    return -1;
  }        
  elsif($@) {
    my $msg = "Error \"".$@."\".";
    $msg =~ s/(\n+|\s+)/ /g;
    $msg = escapeString($msg);
    $logger->error($msg); 
    $$error = $msg if (defined $error);
    return -1;
  }  
  $$error = "" if (defined $error);
  return 1;
}


sub openDB {
  my ($self, $txn, $error) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::XMLDB");

  my $dbTr = "";
  my $atomic = 1;
  if(defined $txn and $txn ne "") {
    $dbTr = $txn;
    $atomic = 0;
  }  
  
  eval {
    $self->{ENV} = new DbEnv(0);
    $self->{ENV}->open(
      $self->{ENVIRONMENT},
      Db::DB_JOINENV|Db::DB_INIT_MPOOL|Db::DB_CREATE|Db::DB_INIT_LOCK|Db::DB_INIT_LOG|Db::DB_INIT_TXN
    );   

    $self->{MANAGER} = new XmlManager(
      $self->{ENV},
      DbXml::DBXML_ALLOW_EXTERNAL_ACCESS|DbXml::DBXML_ALLOW_AUTO_OPEN
    );
  
    $dbTr = $self->{MANAGER}->createTransaction() if $atomic;  
    $self->{CONTAINER} = $self->{MANAGER}->openContainer(
      $dbTr, 
      $self->{CONTAINERFILE}, 
      Db::DB_CREATE|Db::DB_DIRTY_READ|DbXml::DBXML_TRANSACTIONAL
    );
    
    if(!$self->{CONTAINER}->getIndexNodes) {
      my $dbUC = $self->{MANAGER}->createUpdateContext(); 
      $self->{INDEX} = $self->{CONTAINER}->addIndex(
        $dbTr,
        "http://ggf.org/ns/nmwg/base/2.0/",
        "store",
        "node-element-equality-string",
        $dbUC
      ); 
    }
    
    $dbTr->commit if $atomic;
    undef $dbTr if $atomic;
  };
 
  $dbTr->abort if($dbTr and $atomic);
  undef $dbTr if $atomic;
  
  if(my $e = catch std::exception) {
    my $msg = "Error \"".$e->what()."\".";
    $msg =~ s/(\n+|\s+)/ /g;
    $msg = escapeString($msg);
    $logger->error($msg);
    $$error = $msg if (defined $error);
    return -1;
  }
  elsif($e = catch DbException) {
    my $msg = "Error \"".$e->what()."\".";
    $msg =~ s/(\n+|\s+)/ /g;
    $msg = escapeString($msg);
    $logger->error($msg); 
    $$error = $msg if (defined $error);
    return -1;
  }        
  elsif($@) {
    my $msg = "Error \"".$@."\".";
    $msg =~ s/(\n+|\s+)/ /g;
    $msg = escapeString($msg);
    $logger->error($msg); 
    $$error = $msg if (defined $error);
    return -1;
  }  
  $$error = "" if (defined $error);
  return 0;
}


sub indexDB {
  my ($self, $txn, $error) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::XMLDB");

  my $dbTr = "";
  my $atomic = 1;
  if(defined $txn and $txn ne "") {
    $dbTr = $txn;
    $atomic = 0;
  }  
  
  eval {
    if(!$self->{CONTAINER}->getIndexNodes and !$self->{INDEX}) {
      my $dbUC = $self->{MANAGER}->createUpdateContext(); 
      $self->{INDEX} = $self->{CONTAINER}->addIndex(
        $dbTr,
        "http://ggf.org/ns/nmwg/base/2.0/",
        "store",
        "node-element-equality-string",
        $dbUC
      );
    }
    $dbTr->commit if $atomic;
    undef $dbTr if $atomic;
  };
 
  $dbTr->abort if($dbTr and $atomic);
  undef $dbTr if $atomic;
  
  if(my $e = catch std::exception) {
    my $msg = "Error \"".$e->what()."\".";
    $msg =~ s/(\n+|\s+)/ /g;
    $msg = escapeString($msg);
    $logger->error($msg);
    $$error = $msg if (defined $error);
    return -1;
  }
  elsif($e = catch DbException) {
    my $msg = "Error \"".$e->what()."\".";
    $msg =~ s/(\n+|\s+)/ /g;
    $msg = escapeString($msg);
    $logger->error($msg); 
    $$error = $msg if (defined $error);
    return -1;
  }        
  elsif($@) {
    my $msg = "Error \"".$@."\".";
    $msg =~ s/(\n+|\s+)/ /g;
    $msg = escapeString($msg);
    $logger->error($msg); 
    $$error = $msg if (defined $error);
    return -1;
  }  
  $$error = "" if (defined $error);
  return 0;
}


sub deIndexDB {
  my ($self, $txn, $error) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::XMLDB");

  my $dbTr = "";
  my $atomic = 1;
  if(defined $txn and $txn ne "") {
    $dbTr = $txn;
    $atomic = 0;
  }  
  
  eval {
    my $dbUC = $self->{MANAGER}->createUpdateContext(); 
    if($self->{CONTAINER}->getIndexNodes and $self->{INDEX}) {
      my $dbUC = $self->{MANAGER}->createUpdateContext(); 
      $self->{INDEX} = $self->{CONTAINER}->deleteIndex(
        $dbTr,
        "http://ggf.org/ns/nmwg/base/2.0/",
        "store",
        "node-element-equality-string",
        $dbUC
      );
    }
    $dbTr->commit if $atomic;
    undef $dbTr if $atomic;
  };
 
  $dbTr->abort if($dbTr and $atomic);
  undef $dbTr if $atomic;
  
  if(my $e = catch std::exception) {
    my $msg = "Error \"".$e->what()."\".";
    $msg =~ s/(\n+|\s+)/ /g;
    $msg = escapeString($msg);
    $logger->error($msg);
    $$error = $msg if (defined $error);
    return -1;
  }
  elsif($e = catch DbException) {
    my $msg = "Error \"".$e->what()."\".";
    $msg =~ s/(\n+|\s+)/ /g;
    $msg = escapeString($msg);
    $logger->error($msg); 
    $$error = $msg if (defined $error);
    return -1;
  }        
  elsif($@) {
    my $msg = "Error \"".$@."\".";
    $msg =~ s/(\n+|\s+)/ /g;
    $msg = escapeString($msg);
    $logger->error($msg); 
    $$error = $msg if (defined $error);
    return -1;
  }  
  $$error = "" if (defined $error);
  return 0;
}


sub getTransaction {
  my ($self, $error) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::XMLDB");
  my $dbTr = "";
  eval {
    if(defined $self->{MANAGER} and $self->{MANAGER} ne "") {
      $dbTr = $self->{MANAGER}->createTransaction();   
    }
  };
  if(my $e = catch std::exception) {
    my $msg = "Error \"".$e->what()."\".";
    $msg =~ s/(\n+|\s+)/ /g;
    $msg = escapeString($msg);
    $logger->error($msg);
    $$error = $msg if (defined $error);
  }
  elsif($e = catch DbException) {
    my $msg = "Error \"".$e->what()."\".";
    $msg =~ s/(\n+|\s+)/ /g;
    $msg = escapeString($msg);
    $logger->error($msg); 
    $$error = $msg if (defined $error);
  }        
  elsif($@) {
    my $msg = "Error \"".$@."\".";
    $msg =~ s/(\n+|\s+)/ /g;
    $msg = escapeString($msg);
    $logger->error($msg); 
    $$error = $msg if (defined $error);
  }  
  $$error = "" if (defined $error);
  return $dbTr;
}


sub commitTransaction {
  my ($self, $dbTr, $error) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::XMLDB");
  eval {
    if($dbTr and $dbTr ne "") {
      $dbTr->commit();
      undef $dbTr;   
    }
  };
  if(my $e = catch std::exception) {
    my $msg = "Error \"".$e->what()."\".";
    $msg =~ s/(\n+|\s+)/ /g;
    $msg = escapeString($msg);
    $logger->error($msg);
    $$error = $msg if (defined $error);
    return 0;
  }
  elsif($e = catch DbException) {
    my $msg = "Error \"".$e->what()."\".";
    $msg =~ s/(\n+|\s+)/ /g;
    $msg = escapeString($msg);
    $logger->error($msg); 
    $$error = $msg if (defined $error);
    return 0;
  }        
  elsif($@) {
    my $msg = "Error \"".$@."\".";
    $msg =~ s/(\n+|\s+)/ /g;
    $msg = escapeString($msg);
    $logger->error($msg); 
    $$error = $msg if (defined $error);
    return 0;
  }  
  $$error = "" if (defined $error);
  return 1;
}


sub abortTransaction {
  my ($self, $dbTr, $error) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::XMLDB");
  eval {
    if($dbTr and $dbTr ne "") {
      $dbTr->abort();
      undef $dbTr;   
    }
  };
  if(my $e = catch std::exception) {
    my $msg = "Error \"".$e->what()."\".";
    $msg =~ s/(\n+|\s+)/ /g;
    $msg = escapeString($msg);
    $logger->error($msg);
    $$error = $msg if (defined $error);
    return 0;
  }
  elsif($e = catch DbException) {
    my $msg = "Error \"".$e->what()."\".";
    $msg =~ s/(\n+|\s+)/ /g;
    $msg = escapeString($msg);
    $logger->error($msg); 
    $$error = $msg if (defined $error);
    return 0;
  }        
  elsif($@) {
    my $msg = "Error \"".$@."\".";
    $msg =~ s/(\n+|\s+)/ /g;
    $msg = escapeString($msg);
    $logger->error($msg); 
    $$error = $msg if (defined $error);
    return 0;
  }  
  $$error = "" if (defined $error);
  return 1;
}


sub query {
  my ($self, $query, $txn, $error) = @_; 
  my $logger = get_logger("perfSONAR_PS::DB::XMLDB");
  my @resString = ();

  my $dbTr = "";
  my $atomic = 1;
  if(defined $txn and $txn ne "") {
    $dbTr = $txn;
    $atomic = 0;
  }
  
  if(defined $query and $query ne "") {
    my $results = "";
    my $value = "";
    my $fullQuery = "";
    eval {
      my $contName = $self->{CONTAINER}->getName();
      
      # make sure the query is clean
      $query =~ s/&/&amp;/g;
      $query =~ s/</&lt;/g;
      $query =~ s/>/&gt;/g;      
      
      if($query =~ m/collection\(/) {  
        $query =~ s/CHANGEME/$contName/g;
        $fullQuery = $query;
      }
      else {
        $fullQuery = "collection('".$contName."')$query";
      }

      $logger->debug("Query \"".$fullQuery."\" received.");
      
      my $dbQC = $self->{MANAGER}->createQueryContext();
      foreach my $prefix (keys %{$self->{NAMESPACES}}) {
        $dbQC->setNamespace($prefix, $self->{NAMESPACES}->{$prefix});
      }          
      
      $dbTr = $self->{MANAGER}->createTransaction() if $atomic;      
      $results = $self->{MANAGER}->query($dbTr, $fullQuery, $dbQC);
      while($results->next($value)) {
        push @resString, $value."\n";
        undef $value;
      }  
      $dbTr->commit() if $atomic;
      undef $dbTr if $atomic;
    };

    $dbTr->abort if($dbTr and $atomic);
    undef $dbTr if $atomic;

    if(my $e = catch std::exception) {
      my $msg = "Error \"".$e->what()."\".";
      $msg =~ s/(\n+|\s+)/ /g;
      $msg = escapeString($msg);
      $logger->error($msg);
      $$error = $msg if (defined $error);
      return -1;
    }
    elsif($e = catch DbException) {
      my $msg = "Error \"".$e->what()."\".";
      $msg =~ s/(\n+|\s+)/ /g;
      $msg = escapeString($msg);
      $logger->error($msg); 
      $$error = $msg if (defined $error);
      return -1;
    }        
    elsif($@) {
      my $msg = "Error \"".$@."\".";
      $msg =~ s/(\n+|\s+)/ /g;
      $msg = escapeString($msg);
      $logger->error($msg); 
      $$error = $msg if (defined $error);
      return -1;
    }  
  }     
  else {
    my $msg = "Missing argument.";
    $logger->error("Missing argument"); 
    $$error = $msg if (defined $error); 
    return -1;
  }   
  $$error = "" if (defined $error);
  return @resString; 
}


sub queryForName {
  my ($self, $query, $txn, $error) = @_; 
  my $logger = get_logger("perfSONAR_PS::DB::XMLDB");
  my @resString = ();

  my $dbTr = "";
  my $atomic = 1;
  if(defined $txn and $txn ne "") {
    $dbTr = $txn;
    $atomic = 0;
  }

  if(defined $query and $query ne "") {
    my $results = "";
    my $doc = "";
    my $fullQuery = "";          
    eval {
      my $contName = $self->{CONTAINER}->getName();
      
      # make sure the query is clean
      $query =~ s/&/&amp;/g;
      $query =~ s/</&lt;/g;
      $query =~ s/>/&gt;/g;      
      
      if($query =~ m/collection\(/) {
        $query =~ s/CHANGEME/$contName/g;
        $fullQuery = $query;
      }
      else {
        $fullQuery = "collection('".$contName."')$query";
      }     
    
      $logger->debug("Query \"".$fullQuery."\" received.");

      my $dbQC = $self->{MANAGER}->createQueryContext();
      foreach my $prefix (keys %{$self->{NAMESPACES}}) {
        $dbQC->setNamespace($prefix, $self->{NAMESPACES}->{$prefix});
      }          

      $dbTr = $self->{MANAGER}->createTransaction() if $atomic;
      $results = $self->{MANAGER}->query($dbTr, $fullQuery, $dbQC);
      $doc = $self->{MANAGER}->createDocument();
      while($results->next($doc)) {
        push @resString, $doc->getName;
      }
      undef $doc;
      undef $results;
      $dbTr->commit() if $atomic;
      undef $dbTr if $atomic;
    };

    $dbTr->abort if($dbTr and $atomic);
    undef $dbTr if $atomic;

    if(my $e = catch std::exception) {
      my $msg = "Error \"".$e->what()."\".";
      $msg =~ s/(\n+|\s+)/ /g;
      $msg = escapeString($msg);
      $logger->error($msg);
      $$error = $msg if (defined $error);
      return -1;
    }
    elsif($e = catch DbException) {
      my $msg = "Error \"".$e->what()."\".";
      $msg =~ s/(\n+|\s+)/ /g;
      $msg = escapeString($msg);  
      $logger->error($msg); 
      $$error = $msg if (defined $error);
      return -1;
    }        
    elsif($@) {
      my $msg = "Error \"".$@."\".";
      $msg =~ s/(\n+|\s+)/ /g;
      $msg = escapeString($msg);  
      $logger->error($msg); 
      $$error = $msg if (defined $error);
      return -1;
    }  
  }     
  else {
    my $msg = "Missing argument.";
    $logger->error("Missing argument"); 
    $$error = $msg if (defined $error); 
    return -1;
  }   
  $$error = "" if (defined $error);
  return @resString; 
}


sub queryByName {
  my ($self, $name, $txn, $error) = @_; 
  my $logger = get_logger("perfSONAR_PS::DB::XMLDB");
  my $content = "";

  my $dbTr = "";
  my $atomic = 1;
  if(defined $txn and $txn ne "") {
    $dbTr = $txn;
    $atomic = 0;
  }

  if(defined $name and $name ne "") {
    eval {
      $logger->debug("Query for name \"".$name."\" received.");
      $dbTr = $self->{MANAGER}->createTransaction() if $atomic;
      my $document = $self->{CONTAINER}->getDocument($dbTr, $name);
      $content = $document->getName;
      $logger->debug("Document found.");
      $dbTr->commit() if $atomic;
      undef $dbTr if $atomic;
    };

    $dbTr->abort if($dbTr and $atomic);
    undef $dbTr if $atomic;

    if(my $e = catch std::exception) {
      if($e->getExceptionCode() == 11) {
        $logger->debug("Document not found.");
      }
      else {
        my $msg = "Error \"".$e->what()."\".";
        $msg =~ s/(\n+|\s+)/ /g;
        $msg = escapeString($msg);
        $logger->error($msg);
        $$error = $msg if (defined $error);
      }
    }
    elsif($e = catch DbException) {
      my $msg = "Error \"".$e->what()."\".";
      $msg =~ s/(\n+|\s+)/ /g;
      $msg = escapeString($msg);    
      $logger->error($msg);    
      $$error = $msg if (defined $error);
    }        
    elsif($@) {
      my $msg = "Error \"".$@."\".";
      $msg =~ s/(\n+|\s+)/ /g;
      $msg = escapeString($msg);  
      $logger->error($msg);  
      $$error = $msg if (defined $error);    
    }   
  }
  else {
    my $msg = "Missing argument.";
    $logger->error($msg); 
    $$error = $msg if (defined $error);  
  }  
  $$error = "" if (defined $error);
  return $content; 
}


sub getDocumentByName {
  my ($self, $name, $txn, $error) = @_; 
  my $logger = get_logger("perfSONAR_PS::DB::XMLDB");
  my $content = "";

  my $dbTr = "";
  my $atomic = 1;
  if(defined $txn and $txn ne "") {
    $dbTr = $txn;
    $atomic = 0;
  }

  if(defined $name and $name ne "") {
    eval {
      $logger->debug("Query for name \"".$name."\" received.");
      $dbTr = $self->{MANAGER}->createTransaction() if $atomic;
      my $document = $self->{CONTAINER}->getDocument($dbTr, $name);
      $content = $document->getContent;
      $logger->debug("Document found.");
      $dbTr->commit() if $atomic;
      undef $dbTr if $atomic;
    };

    $dbTr->abort if($dbTr and $atomic);
    undef $dbTr if $atomic;

    if(my $e = catch std::exception) {
      if($e->getExceptionCode() == 11) {
        my $msg = "Document not found";
        $logger->debug($msg);
        $$error = $msg if defined $error;
      }
      else {
        my $msg = "Error \"".$e->what()."\".";
        $msg =~ s/(\n+|\s+)/ /g;
        $msg = escapeString($msg);
        $logger->error($msg);
        $$error = $msg if defined $error;
      }
    }
    elsif($e = catch DbException) {
      my $msg = "Error \"".$e->what()."\".";
      $msg =~ s/(\n+|\s+)/ /g;
      $msg = escapeString($msg);     
      $logger->error($msg);
      $$error = $msg if defined $error;
    }
    elsif($@) {
      my $msg = "Error \"".$@."\".";
      $msg =~ s/(\n+|\s+)/ /g;
      $msg = escapeString($msg);  
      $logger->error($msg);
      $$error = $msg if defined $error;
    }
  }
  else {
    my $msg = "Missing argument";
    $logger->error($msg);
    $$error = $msg if defined $error;
  }
  $$error = "" if defined $error;
  return $content;
}


sub updateByName {
  my ($self, $content, $name, $txn, $error) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::XMLDB");

  my $dbTr = "";
  my $atomic = 1;
  if(defined $txn and $txn ne "") {
    $dbTr = $txn;
    $atomic = 0;
  }

  if((defined $content and $content ne "") and 
     (defined $name and $name ne "")) {    
    eval {        
      $logger->debug("Update \"".$content."\" for \"".$name."\".");
      my $myXMLDoc = $self->{MANAGER}->createDocument();
      $myXMLDoc->setContent($content);
      $myXMLDoc->setName($name); 
      
      $dbTr = $self->{MANAGER}->createTransaction() if $atomic;    
      my $dbUC = $self->{MANAGER}->createUpdateContext();       
      $self->{CONTAINER}->updateDocument($dbTr, $myXMLDoc, $dbUC);
      $dbTr->commit() if $atomic;
      undef $dbTr if $atomic;
    };
    
    $dbTr->abort if($dbTr and $atomic);
    undef $dbTr if $atomic;
    
    if(my $e = catch std::exception) {
      my $msg = "Error \"".$e->what()."\".";
      $msg =~ s/(\n+|\s+)/ /g;
      $msg = escapeString($msg);
      $logger->error($msg);
      $$error = $msg if (defined $error);
      return -1;
    }
    elsif($e = catch DbException) {
      my $msg = "Error \"".$e->what()."\".";
      $msg =~ s/(\n+|\s+)/ /g;
      $msg = escapeString($msg);   
      $logger->error($msg); 
      $$error = $msg if (defined $error);
      return -1;
    }        
    elsif($@) {
      my $msg = "Error \"".$@."\".";
      $msg =~ s/(\n+|\s+)/ /g;
      $msg = escapeString($msg);  
      $logger->error($msg); 
      $$error = $msg if (defined $error);
      return -1;
    }  
  }     
  else {
    my $msg = "Missing argument.";
    $logger->error("Missing argument"); 
    $$error = $msg if (defined $error); 
    return -1;
  }   
  $$error = "" if (defined $error);
  return 0;
}


sub count {
  my ($self, $query, $txn, $error) = @_; 
  my $logger = get_logger("perfSONAR_PS::DB::XMLDB");
  my $size = -1;

  my $dbTr = "";
  my $atomic = 1;
  if(defined $txn and $txn ne "") {
    $dbTr = $txn;
    $atomic = 0;
  }  
  
  if(defined $query and $query ne "") {
    my $results;
    
    # make sure the query is clean
    $query =~ s/&/&amp;/g;
    $query =~ s/</&lt;/g;
    $query =~ s/>/&gt;/g;    
    
    my $fullQuery = "collection('".$self->{CONTAINER}->getName()."')$query";    
    eval {            
      $logger->debug("Query \"".$fullQuery."\" received.");
      my $dbQC = $self->{MANAGER}->createQueryContext();
      foreach my $prefix (keys %{$self->{NAMESPACES}}) {
        $dbQC->setNamespace($prefix, $self->{NAMESPACES}->{$prefix});
      }
      
      $dbTr = $self->{MANAGER}->createTransaction() if $atomic;      
      $results = $self->{MANAGER}->query($dbTr, $fullQuery, $dbQC);  
      $size = $results->size();
      $dbTr->commit() if $atomic;
      undef $dbTr if $atomic;
    };

    $dbTr->abort if($dbTr and $atomic);
    undef $dbTr if $atomic;

    if(my $e = catch std::exception) {
      my $msg = "Error \"".$e->what()."\".";
      $msg =~ s/(\n+|\s+)/ /g;
      $msg = escapeString($msg);      
      $logger->error($msg);
      $$error = $msg if (defined $error);
    }
    elsif($e = catch DbException) {
      my $msg = "Error \"".$e->what()."\".";
      $msg =~ s/(\n+|\s+)/ /g;
      $msg = escapeString($msg);  
      $logger->error($msg); 
      $$error = $msg if (defined $error);
    }        
    elsif($@) {
      my $msg = "Error \"".$@."\".";
      $msg =~ s/(\n+|\s+)/ /g;
      $msg = escapeString($msg);  
      $logger->error($msg); 
      $$error = $msg if (defined $error);
    }  
  }
  else {
    my $msg = "Missing argument.";
    $logger->error($msg);   
    $$error = $msg if (defined $error); 
  } 
  $$error = "" if (defined $error);
  return $size;
}


sub insertIntoContainer {
  my ($self, $content, $name, $txn, $error) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::XMLDB");

  my $dbTr = "";
  my $atomic = 1;
  if(defined $txn and $txn ne "") {
    $dbTr = $txn;
    $atomic = 0;
  }

  if((defined $content and $content ne "") and 
     (defined $name and $name ne "")) {    
    eval {        
      $logger->debug("Insert \"".$content."\" into \"".$name."\".");
      my $myXMLDoc = $self->{MANAGER}->createDocument();
      $myXMLDoc->setContent($content);
      $myXMLDoc->setName($name); 
      
      $dbTr = $self->{MANAGER}->createTransaction() if $atomic; 
      my $dbUC = $self->{MANAGER}->createUpdateContext();       
      $self->{CONTAINER}->putDocument($dbTr, $myXMLDoc, $dbUC, 0);
      $dbTr->commit() if $atomic;
      undef $dbTr if $atomic;
    };

    $dbTr->abort if($dbTr and $atomic);
    undef $dbTr if $atomic;

    if(my $e = catch std::exception) {
      my $msg = "Error \"".$e->what()."\".";
      $msg =~ s/(\n+|\s+)/ /g;
      $msg = escapeString($msg);      
      $logger->error($msg);
      $$error = $msg if (defined $error);
      return -1;
    }
    elsif($e = catch DbException) {
      my $msg = "Error \"".$e->what()."\".";
      $msg =~ s/(\n+|\s+)/ /g;
      $msg = escapeString($msg);  
      $logger->error($msg); 
      $$error = $msg if (defined $error);
      return -1;
    }        
    elsif($@) {
      my $msg = "Error \"".$@."\".";
      $msg =~ s/(\n+|\s+)/ /g;
      $msg = escapeString($msg);  
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
  $$error = "" if (defined $error);
  return 0;
}


sub insertElement {
  my ($self, $query, $content, $txn, $error) = @_;     
  my $logger = get_logger("perfSONAR_PS::DB::XMLDB");

  my $dbTr = "";
  my $atomic = 1;
  if(defined $txn and $txn ne "") {
    $dbTr = $txn;
    $atomic = 0;
  }

  if((defined $content and $content ne "") and (defined $query  and $query ne "")) {          
    my $fullQuery = "collection('".$self->{CONTAINER}->getName()."')$query";     
    eval {
      $logger->debug("Query \"".$fullQuery."\" and content \"".$content."\" received.");
      my $dbQC = $self->{MANAGER}->createQueryContext();
      foreach my $prefix (keys %{$self->{NAMESPACES}}) {
        $dbQC->setNamespace($prefix, $self->{NAMESPACES}->{$prefix});
      }
      
      $dbTr = $self->{MANAGER}->createTransaction() if $atomic;           
      my $results = $self->{MANAGER}->query($dbTr, $fullQuery, $dbQC);
      my $myXMLMod = $self->{MANAGER}->createModify();
      my $myXMLQueryExpr = $self->{MANAGER}->prepare($dbTr, $fullQuery, $dbQC);
      $myXMLMod->addAppendStep($myXMLQueryExpr, $myXMLMod->Element, "", $content, -1);
      my $dbUC = $self->{MANAGER}->createUpdateContext();       
      $myXMLMod->execute($dbTr, $results, $dbQC, $dbUC);
      $dbTr->commit() if $atomic;
      undef $dbTr if $atomic;
    };

    $dbTr->abort if($dbTr and $atomic);
    undef $dbTr if $atomic;

    if(my $e = catch std::exception) {
      my $msg = "Error \"".$e->what()."\".";
      $msg =~ s/(\n+|\s+)/ /g;
      $msg = escapeString($msg);     
      $logger->error($msg);
      $$error = $msg if (defined $error);
      return -1;
    }
    elsif($e = catch DbException) {
      my $msg = "Error \"".$e->what()."\".";
      $msg =~ s/(\n+|\s+)/ /g;
      $msg = escapeString($msg);  
      $logger->error($msg); 
      $$error = $msg if (defined $error);
      return -1;
    }        
    elsif($@) {
      my $msg = "Error \"".$@."\".";
      $msg =~ s/(\n+|\s+)/ /g;
      $msg = escapeString($msg);  
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
  $$error = "" if (defined $error);
  return 0;
}


sub remove {
  my ($self, $name, $txn, $error) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::XMLDB");

  my $dbTr = "";
  my $atomic = 1;
  if(defined $txn and $txn ne "") {
    $dbTr = $txn;
    $atomic = 0;
  }

  if(defined $name and $name ne "") {  
    eval {
      $logger->debug("Remove \"".$name."\" received.");
      $dbTr = $self->{MANAGER}->createTransaction() if $atomic;  
      my $dbUC = $self->{MANAGER}->createUpdateContext();     
      $self->{CONTAINER}->deleteDocument($dbTr, $name, $dbUC);
      $dbTr->commit() if $atomic;
      undef $dbTr if $atomic;
    };

    $dbTr->abort if($dbTr and $atomic);
    undef $dbTr if $atomic;

    if(my $e = catch std::exception) {
      my $msg = "Error \"".$e->what()."\".";
      $msg =~ s/(\n+|\s+)/ /g;
      $msg = escapeString($msg);      
      $logger->error($msg);
      $$error = $msg if (defined $error);
      return -1;
    }
    elsif($e = catch DbException) {
      my $msg = "Error \"".$e->what()."\".";
      $msg =~ s/(\n+|\s+)/ /g;
      $msg = escapeString($msg);  
      $logger->error($msg); 
      $$error = $msg if (defined $error);
      return -1;
    }        
    elsif($@) {
      my $msg = "Error \"".$@."\".";
      $msg =~ s/(\n+|\s+)/ /g;
      $msg = escapeString($msg);  
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
  $$error = "" if (defined $error);
  return 0;
}


sub closeDB {
  my($self, $error) = @_;
  
  foreach my $key (sort keys %{$self}) {
    if($key ne "ENV" and $key ne "MANAGER") {
      undef $self->{$key};
    }
  }
  
  undef $self->{MANAGER};
  undef $self->{ENV};
  
  return;
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
such as '/usr/local/LS/xmldb'; this should not be confused with the actual 
installation directory), the third represents the "container" (a specific file that lives 
in the environment, such as 'snmpstore.dbxml'; many containers can live in a single 
environment).  The fourth argument is a hash reference containing a prefix to namespace 
mapping.  All namespaces that may appear in the container should be mapped (there is no 
harm is sending mappings that will not be used).  

=head2 setEnvironment($self, $env)

(Re-)Sets the "environment" (the directory where the xmldb was created, such as 
'/usr/local/LS/xmldb'; this should not be confused with the actual 
installation directory).

=head2 setContainer($self, $cont)

(Re-)Sets the "container" (a specific file that lives in the environment, such as 'snmpstore.dbxml'; 
many containers can live in a single environment).

=head2 setNamespaces($self, $ns)

(Re-)Sets the hash reference containing a prefix to namespace mapping.  All namespaces that may 
appear in the container should be mapped (there is no harm is sending mappings that will not be 
used).

=head2 prep($self, $txn, $error)

Prepares the database for use, this is called only once usually when the service starts up.  The
purpose of this function is to create the database (if brand new) or perform recovery operations
(if the database exists already).  A transaction element may be passed in from the caller, or
this argument can be left blank for an atomic operation.  The error argument is optional.

=head2 openDB($self, $txn, $error)

Opens the database environment and containers.  A transaction element may be passed in from 
the caller, or this argument can be left blank for an atomic operation.  The error argument 
is optional. 

=head2 indexDB($self, $txn, $error)

Creates a simple index for the database if one does not exist.  A transaction element may be 
passed in from the caller, or this argument can be left blank for an atomic operation.  The 
error argument is optional.

=head2 deIndexDB($self, $txn, $error)

Removes a simple index from the database if one does exist.  A transaction element may be passed 
in from the caller, or this argument can be left blank for an atomic operation.  The error 
argument is optional.

=head2 getTransaction($self, $error)

Creates a new transaction object.  The error argument is optional.

=head2 commitTransaction($self, $dbTr, $error)

Given a transaction object, commit it.  The error argument is optional.

=head2 abortTransaction($self, $dbTr, $error)

Given a transaction object, abort it.  The error argument is optional.

=head2 query($self, $query, $txn, $error) 

The string $query must be an XPath expression to be sent to the database.  Examples are:

  //nmwg:metadata
  
    or
    
  //nmwg:parameter[@name="SNMPVersion" and @value="1"]
  
Results are returned as an array of strings or error status.  This function should be
used for XPath statements.  The error parameter is optional and is a reference
to a scalar. The function will use it to return the error message if one
occurred, it returns the empty string otherwise.

A transaction element may be passed in from the caller, or this argument can be left 
blank for an atomic operation.  The error argument is optional.

=head2 queryForName($self, $query, $txn, $error) 

Given a query, return the 'name' of the container.  A transaction element may be passed 
in from the caller, or this argument can be left blank for an atomic operation.  The 
error argument is optional.

=head2 queryByName($self, $name, $txn, $error) 

Given a name, see if it exists in the container.   A transaction element may be passed in from 
the caller, or this argument can be left blank for an atomic operation.  The error argument 
is optional.

=head2 getDocumentByName($self, $name, $txn, $error) 

Return a document given a it's name.  A transaction element may be passed in from the caller, or
this argument can be left blank for an atomic operation.  The error argument is optional.

=head2 updateByName($self, $content, $name, $txn, $error)

Update container content by name.  A transaction element may be passed in from the caller, or
this argument can be left blank for an atomic operation.  The error argument is optional.

=head2 count($self, $query, $txn, $error) 

The string $query must also be an XPath expression that is sent to the database.  
The result of this expression is simple the number of elements that match the 
query. Returns -1 on error.  A transaction element may be passed in from the caller, or
this argument can be left blank for an atomic operation.  The error argument is optional.

=head2 insertIntoContainer($self, $content, $name, $txn, $error)

Insert the content into the container with the name.   A transaction element may be passed in 
from the caller, or this argument can be left blank for an atomic operation.  The error 
argument is optional.

=head2 insertElement($self, $query, $content, $txn, $error)     

Perform a query, and insert the content into this result.  A transaction element may be passed 
in from the caller, or this argument can be left blank for an atomic operation.  The error 
argument is optional.

=head2 remove($self, $name, $txn, $error)

Remove the container w/ the given name.  A transaction element may be passed in from the caller, or
this argument can be left blank for an atomic operation.  The error argument is optional.

=head2 closeDB($self, $error)

Frees local elements for object destruction.  
  
=head1 SEE ALSO

L<Sleepycat::DbXml>, L<perfSONAR_PS::Common>, L<Log::Log4perl>

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
