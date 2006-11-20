#!/usr/bin/perl

package Netradar::DB::RRD;
use Carp;
use RRDp;


sub new {
  my ($package, $path, $name) = @_;   
  if(!defined $path) {
    croak("Netradar::DB::RRD: Missing argument 'path' to constructor.\n");
  }
  my %hash = ();
  $hash{PATH} = $path;
  RRDp::start $path;
  if($name) {
    $hash{NAME} = $name;
  }
  bless \%hash => $package;
}


sub openDB {
  my ($self, $name) = @_;   
  $hash{NAME} = $name;
  if(!defined $name) {
    croak("Netradar::DB::RRD: Missing argument 'name' to openDB.\n");
  }  
  return;
}


sub closeDB {
  my ($self) = @_;   
  my $status = RRDp::end;
  return $status;
}


sub query {
  my ($self, $cf, $resolution, $start, $end) = @_; 
  my %rrd_result = ();
  my @rrd_headings = ();

  $cmd = "fetch " . $self->{NAME} . " " . $cf;
  if($resolution) {
    $cmd = $cmd . " -r " . $resolution;
  }
  if($start) {
    $cmd = $cmd . " -s " . $start;
  }
  if($end) {
    $cmd = $cmd . " -e " . $end;
  }    
  RRDp::cmd $cmd;
  $answer = RRDp::read;     
  
  my @array = split(/\n/,$$answer);
  for(my $x = 0; $x <= $#{@array}; $x++) {
    if($x == 0) {
      @rrd_headings = split(/\s+/,$array[$x]);
    }
    elsif($x > 1) {
      my @line = split(/\s+/,$array[$x]);
      $line[0] =~ s/://;
      for(my $z = 1; $z <= $#{@line}; $z++) {
        if($line[$z] eq "nan") {
          $rrd_result{$line[0]}{$rrd_headings[$z]} = $line[$z];
        }
        else {
          $rrd_result{$line[0]}{$rrd_headings[$z]} = eval($line[$z]);
        }
      }   
    }
  }
  
  if($RRDp::error) {
    return $RRDp::error;
  }
  else {
    return %rrd_result;
  }    
}


sub insert {
  my ($self, $time, $values, $names) = @_;
  my @v = @{$values};  
  $cmd = "update " . $self->{NAME};
  if($names) {
    my @n = @{$names};
    $cmd = $cmd . " -t ";
    for(my $x = 0; $x <= $#{@n}; $x++) {
      if($x == 0) {
        $cmd = $cmd . $n[$x];
      }
      else {
        $cmd = $cmd . ":" . $n[$x];
      }
    }
  }
  $cmd = $cmd . " " . $time . ":";
  for(my $y = 0; $y <= $#{@v}; $y++) {
    if($y == 0) {
      $cmd = $cmd . $v[$y];
    }
    else {
      $cmd = $cmd . ":" . $v[$y];
    }
  }   
  RRDp::cmd $cmd;
  $answer = RRDp::read; 

  if($RRDp::error) {
    return $RRDp::error;
  }
  else {
    return $$answer;
  }  
}


sub firstValue {
  my ($self) = @_;   
  $cmd = "first " . $self->{NAME};
  RRDp::cmd $cmd;
  $answer = RRDp::read;   
  return $$answer;
}


sub lastValue {
  my ($self) = @_;   
  $cmd = "last " . $self->{NAME};
  RRDp::cmd $cmd;
  $answer = RRDp::read;   
  return $$answer;
}


1;
