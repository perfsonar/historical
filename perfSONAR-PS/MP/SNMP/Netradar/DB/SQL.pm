#!/usr/bin/perl

package Netradar::DB::SQL;
use Carp;
use DBI;


sub new {
  my ($package, $name, $user, $pass) = @_;   
  if(!defined $name) {
    croak("Netradar::DB::SQL: Missing argument to constructor.\n");
  }
  my %hash = ();
  $hash{NAME} = $name;
  $hash{USER} = $user;
  $hash{PASSWORD} = $pass;
  bless \%hash => $package;
}


sub openDB {
  my ($self) = @_;   
  $self->{HANDLE} = DBI->connect(
    $self->{NAME},
    $self->{USER},
    $self->{PASSWORD}
  ) || croak("Netradar::DB::SQL: Database ".$self->{NAME}." unavailable with user ".$self->{NAME}." and password ".$self->{PASSWORD});  
  return;
}


sub closeDB {
  my ($self) = @_;   
  $self->{HANDLE}->disconnect();
  return;
}


sub query {
  my ($self, $query) = @_;
  my $results = (); 
  my $sth = $self->{HANDLE}->prepare($query);
  $sth->execute() || 
    croak("Netradar::DB::SQL: Query error: ", $sth->errstr);    
  $results  = $sth->fetchall_arrayref;
  return $results;
}


sub count {
  my ($self, $query) = @_;
  my $results = (); 
  my $sth = $self->{HANDLE}->prepare($query);
  $sth->execute() || 
    croak("Netradar::DB::SQL: Query error: ", $sth->errstr);    
  $results  = $sth->fetchall_arrayref;
  return $#{$results}+1;
}


sub insert {
  my ($self, $table, $arglist, $argvalues) = @_;   
  my @list = @{$arglist};
  my %values = %{$argvalues};

  my $insert = "insert into " . $table . " (";
  for(my $x = 0; $x <= $#list; $x++) {
    if($x == 0) {
      $insert = $insert.$list[$x];
    }
    else {
      $insert = $insert.", ".$list[$x];
    }
  }
  $insert = $insert.") values (";
  for(my $x = 0; $x <= $#list; $x++) {
    if($x == 0) {
      $insert = $insert."?";
    }
    else {
      $insert = $insert.", ?";
    }
  }  
  $insert = $insert.")";

  my $sth = $self->{HANDLE}->prepare($insert);
  for(my $x = 0; $x <= $#list; $x++) {
    $sth->bind_param($x+1, $values{$list[$x]});
  }
  $sth->execute() || 
    croak("Netradar::DB::SQL: Insert error: ", $sth->errstr);
  return;
}


sub remove {
  my ($self, $delete) = @_;
  my $results = (); 
  my $sth = $self->{HANDLE}->prepare($delete);
  $sth->execute() || 
    croak("Netradar::DB::SQL: Delete error: ", $sth->errstr);    
  return;
}


1;
