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
  my ($self) = @_;   
  return;
}


sub count {
  my ($self) = @_;   
  return;
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
    croak("Netradar::DB::SQL: insert error: ", $sth->errstr);
  return;
}


sub remove {
  my ($self) = @_;   
  return;
}


1;
