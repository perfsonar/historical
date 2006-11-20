#!/usr/bin/perl

package Netradar::DB::RRD;
use Carp;
use RRDp;

our $VERSION = '0.01';

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

__END__
=head1 NAME

Netradar::DB::RRD - A module that provides methods for dealing with rrd files through the RRDp
perl module.

=head1 DESCRIPTION

This module builds on the simple offerings of RRDp (simple a series of pipes to communicate
with rrd files) to offer some common functionality.    

=head1 SYNOPSIS

    use Netradar::DB::RRD;

    my $rrd = new Netradar::DB::RRD(
      "/usr/local/rrdtool/bin/rrdtool" , 
      "/home/jason/rrd/stout/stout.rrd"
    );

    # For reference, here is the create string for the rrd file:
    #
    # rrdtool create stout.rrd \
    # --start N --step 1 \
    # DS:eth0-in:COUNTER:1:U:U \ 
    # DS:eth0-out:COUNTER:1:U:U \
    # DS:eth1-in:COUNTER:1:U:U \
    # DS:eth1-out:COUNTER:1:U:U \
    # RRA:AVERAGE:0.5:10:60480

    # will also open a connection to a file:
    #$rrd->openDB("/home/jason/rrd/stout/stout.rrd");

    my %rrd_result = $rrd->query(
      "AVERAGE", 
      "", 
      "1163525343", 
      "1163525373"
    );

    my @keys = keys(%rrd_result);
    foreach $a (sort(keys(%rrd_result))) {
      foreach $b (sort(keys(%{$rrd_result{$a}}))) {
        print $a , " - " , $b , "\t-->" , $rrd_result{$a}{$b} , "<--\n"; 
      }
      print "\n";
    }
  
    my @test = ("1", "2", "3", "4");
    my @test2 = (
      "eth0-in", 
      "eth0-out", 
      "eth1-in", 
      "eth1-out"
    );
    my $insert = $rrd->insert("N", \@test, \@test2);

    if($insert) {
      print $insert , "\n";
    }

    print "last: " , $rrd->lastValue , "\n";

    print "first: " , $rrd->firstValue , "\n";

    $rrd->closeDB;    

=head1 DETAILS

RRDp was never meant to a rich API; it's goal is simply to provide a method of interacting
with the underlying RRD files.  The module is to be treated as an object, where each 
instance of the object represents a direct connection to a single rrd file.  Each method 
may then be invoked on the object for the specific database.  

=head1 API

The API of Netradar::DB::RRD is rather simple, and attempts to mirror the API of the 
other Netradar::DB::* modules.  

=head2 new($path, $file)

The arguments are strings, the first representing the path to the rrdtool executable, 
the second representing an actual rrd file.  The second argument is optional, and the
openDB($name) function is capable of setting the file as well.  

=head2 openDB($name)

Opens sets the name of the rrd file, it technically does not need to be 'opened' but
the method name is kept for API similarity.  

=head2 closeDB

Closes the connection to the rrd file.  

=head2 query($cf, $resolution, $start, $end)

The '$cf' is the consolidation function to call (AVERAGE,MIN,MAX,LAST), The 
'$resolution' is the interval you want the values to have (seconds per value).  
The '$start' and '$end' are the starting and ending times of the series, these
are measured in seconds since epoch (1970-01-01).  It is also possible to
use the directive 'N' (or 'n') to imply 'now'.  The value of 'N' may also
be manipulated (N-100).   

The results (if any) are returned in a 'hash of hashes' of the form:

  $results{TIME}{DS} = VALUE
  
The example use shows how to retrieve and order these values.  

=head2 insert($time, \@values, \@template)

The first value represents time in seconds since epoch (1970-01-01), or the
value 'N' (or 'n').  The second argument is an array of values to insert.  Be sure
to have the proper number of elements and a proper 'order' for this to work.  The
third argument is optional, and represents a 'template' where you can specify
which values map to the appropriate DS values in the rrd file. 

If an error occurs, it will be returned, otherwise the return value should be
empty.  

=head2 firstValue

Returns the 'last' timestamp in the RRD file.  

=head2 lastValue

Returns the 'first' timestamp in the RRD file.  

=head1 SEE ALSO

L<Netradar::Common>, L<Netradar::DB::SQL>, L<Netradar::DB::XMLDB>, L<Netradar::DB::File>

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
