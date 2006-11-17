#!/usr/bin/perl

package Netradar::DB::XMLDB;
use Carp;
use Sleepycat::DbXml 'simple';


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
}


sub query {
  my ($self, $query) = @_;
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
  };
  if (my $e = catch std::exception) {
    croak("Query $fullQuery failed\t-\t".$e->what());
    exit( -1 );
  }
  elsif ($@) {
    croak("Query $fullQuery failed\t-\t".$@);
    exit( -1 );
  }     
  return @resString;
}


sub count {
  my ($self, $query) = @_;
  my $results;
  my $fullQuery = "collection('".$self->{CONTAINER}->getName()."')$query";
  eval {
    $results = $self->{MANAGER}->query($fullQuery, $self->{QUERYCONTEXT});		
  };
  if (my $e = catch std::exception) {
    croak("Query $fullQuery failed\t-\t".$e->what());
    exit( -1 );
  }
  elsif ($@) {
    croak("Query $fullQuery failed\t-\t".$@);
    exit( -1 );
  }      
  return $results->size();
}


sub insert {
  my ($self, $content, $name) = @_;
  eval {
    my $myXMLDoc = $self->{MANAGER}->createDocument();
    $myXMLDoc->setContent($content);
    $myXMLDoc->setName($name); 
    $self->{CONTAINER}->putDocument($self->{TRANSACTION}, $myXMLDoc, $self->{UPDATECONTEXT}, 0);
    $self->{TRANSACTION}->commit();
  };
  if (my $e = catch std::exception) {
    croak("Query $fullQuery failed\t-\t".$e->what());
    exit( -1 );
  }
  elsif ($@) {
    croak("Query $fullQuery failed\t-\t".$@);
    exit( -1 );
  }      
  return;
}


sub remove {
  my ($self, $content, $name) = @_;
  eval {
    my $myXMLDoc = $self->{MANAGER}->createDocument();
    $myXMLDoc->setContent($content); 
    $self->{CONTAINER}->deleteDocument($self->{TRANSACTION}, $myXMLDoc, $self->{UPDATECONTEXT});
    $self->{TRANSACTION}->commit();
  };
  if (my $e = catch std::exception) {
    croak("Query $fullQuery failed\t-\t".$e->what());
    exit( -1 );
  }
  elsif ($@) {
    croak("Query $fullQuery failed\t-\t".$@);
    exit( -1 );
  }   
  return;
}


1;
