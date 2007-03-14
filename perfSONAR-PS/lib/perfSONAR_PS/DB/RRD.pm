#!/usr/bin/perl

package perfSONAR_PS::DB::RRD;
use RRDp;
use perfSONAR_PS::Common;
@ISA = ('Exporter');
@EXPORT = ();
	   
our $VERSION = '0.03';

sub new {
  my ($package, $log, $path, $name, $dss, $error, $debug) = @_;   
  my %hash = ();
  $hash{"FILENAME"} = "perfSONAR_PS::DB::RRD";
  $hash{"FUNCTION"} = "\"new\"";
  if(defined $log and $log ne "") {
    $hash{"LOGFILE"} = $log;
  }    
  if(defined $path and $path ne "") {
    $hash{"PATH"} = $path;
  }
  if(defined $name and $name ne "") {
    $hash{"NAME"} = $name;
  }
  if(defined $dss and $dss ne "") {
    $hash{"DATASOURCES"} = \%{$dss};  
  }  
  if(defined $error and $error ne "") {
    if($error == 1) {
      $RRDp::error_mode = 'catch';
    }
    else {
      undef $RRDp::error_mode;
    }
  }
  if(defined $debug and $debug ne "") {
    $hash{"DEBUG"} = $debug;  
  }   
  bless \%hash => $package;
}


sub setLog {
  my ($self, $log) = @_;  
  $self->{FUNCTION} = "\"setLog\"";  
  if(defined $log and $log ne "") {
    $self->{LOGFILE} = $log;
  }
  else {
    error("Missing argument", __LINE__);    
  }
  return;
}


sub setFile {
  my ($self, $file) = @_;  
  $self->{FUNCTION} = "\"setFile\"";  
  if(defined $file and $file ne "") {
    $self->{NAME} = $file;
  }
  else {
    error("Missing argument", __LINE__);  
  }
  return;
}


sub setPath {
  my ($self, $path) = @_;  
  $self->{FUNCTION} = "\"setPath\"";  
  if(defined $path and $path ne "") {
    $self->{PATH} = $path;
  }
  else {
    error("Missing argument", __LINE__);  
  }
  return;
}


sub setVariables {
  my ($self, $dss) = @_;  
  $self->{FUNCTION} = "\"setVariables\""; 
  if(defined $dss and $dss ne "") { 
    $hash{"DATASOURCES"} = \%{$dss};
  }
  else {
    error("Missing argument", __LINE__);  
  }
  return;
}


sub setVariable {
  my ($self, $dss) = @_;  
  $self->{FUNCTION} = "\"setVariable\""; 
  if(defined $dss and $dss ne "") {
    $self->{DATASOURCES}->{$dss} = "";
  }
  else {
    error("Missing argument", __LINE__);
  }
  return;
}


sub setError {
  my ($self, $error) = @_;  
  $self->{FUNCTION} = "\"setError\"";  
  if(defined $error and $error ne "") {
    if($error == 1) {
      $RRDp::error_mode = 'catch';
    }
    else {
      undef $RRDp::error_mode;
    }
  }
  else {
    error("Missing argument", __LINE__);
  }
  return;
}


sub setDebug {
  my ($self, $debug) = @_;  
  $self->{FUNCTION} = "\"setDebug\"";  
  if(defined $debug and $debug ne "") {
    $self->{DEBUG} = $debug;
  }
  else {
    error("Missing argument", __LINE__);
  }
  return;
}


sub getErrorMessage {
  my ($self) = @_;
  if($RRDp::error) {
    return $RRDp::error;
  }
  else {
    return "";
  }
}


sub openDB {
  my ($self) = @_;
  $self->{FUNCTION} = "\"openDB\""; 
  if(defined $self->{PATH} and defined $self->{NAME}) {
    RRDp::start $self->{PATH};
    print $self->{FILENAME}.":\tdatabase open in ".$self->{FUNCTION}."\n" if($self->{DEBUG});
  }
  else {
    error("Missing path or name in object", __LINE__);        
  }
  return;
}


sub closeDB {
  my ($self) = @_;   
  $self->{FUNCTION} = "\"closeDB\"";   
  if((defined $self->{PATH} and $self->{PATH} ne "") and 
     (defined $self->{NAME} and $self->{NAME} ne "")){
    my $status = RRDp::end;  
    print $self->{FILENAME}.":\tdatabase close in ".$self->{FUNCTION}."\n" if($self->{DEBUG});
    if($status) {
      error($self->{PATH}." has returned status \"".$status."\" on closing", __LINE__);    
    }
  }
  else {
    error("rrdtool is not open", __LINE__);  
  }
  return;
}


sub query {
  my ($self, $cf, $resolution, $start, $end) = @_; 
  $self->{FUNCTION} = "\"query\"";   
  my %rrd_result = ();
  my @rrd_headings = ();  

  if(defined $cf and $cf ne "") {  
    $cmd = "fetch " . $self->{NAME} . " " . $cf;
    if(defined $resolution and $resolution ne "") {
      $cmd = $cmd . " -r " . $resolution;
    }    
    if(defined $start and $start ne "") {
      $cmd = $cmd . " -s " . $start;
    }
    if(defined $end and $end ne "") {
      $cmd = $cmd . " -e " . $end;
    }
  
    print $self->{FILENAME}.":\tcommand \".$cmd.\" in ".$self->{FUNCTION}."\n" if($self->{DEBUG});
    
    RRDp::cmd $cmd;
    my $answer = RRDp::read;     

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
      print $self->{FILENAME}.":\tdatabase error in ".$self->{FUNCTION}."\n" if($self->{DEBUG});
      %rrd_result = ();
      $rrd_result{ANSWER} = $$answer;
    }
  }    
  else {
    error("Missing argument", __LINE__); 
  }
  return %rrd_result; 
}


sub insert {
  my ($self, $time, $ds, $value) = @_;
  $self->{FUNCTION} = "\"insert\"";   
  if((defined $time and $time ne "") and
     (defined $ds and $ds ne "") and 
     (defined $value and $value ne "")) { 
    $self->{COMMIT}->{$time}->{$ds} = $value;
  }
  else { 
    error("Missing argument", __LINE__); 
  }  
}


sub insertCommit {
  my ($self) = @_;
  $self->{FUNCTION} = "\"insertCommit\""; 
  my $answer = "";
  my @result = ();
  foreach my $time (keys %{$self->{COMMIT}}) {
    my $cmd = "updatev " . $self->{NAME} . " -t ";
    my $template = "";
    my $values = "";
    my $counter = 0;
    foreach my $ds (keys %{$self->{COMMIT}->{$time}}) {
      if($counter == 0) {
        $template = $template . $ds;
        $values = $values . $time . ":" . $self->{COMMIT}->{$time}->{$ds};
      }
      else {
        $template = $template . ":" . $ds;
        $values = $values . ":" . $self->{COMMIT}->{$time}->{$ds};
      }
      $counter++;
    }     
    if((!defined $template or $template eq "") or (!defined $values or $values eq "")){
      error("rrdtool cannot update when datasource values are not specified", __LINE__);  
    }
    else {
      delete $self->{COMMIT}->{$time};
      $cmd = $cmd . $template . " " . $values;     
      print $self->{FILENAME}.":\tcommand \".$cmd.\" in ".$self->{FUNCTION}."\n" if($self->{DEBUG});
      RRDp::cmd $cmd;
      $answer = RRDp::read; 
      push @result, $$answer; 
    } 
  }
  return @result;
}


sub firstValue {
  my ($self) = @_;   
  $self->{FUNCTION} = "\"firstValue\"";   
  RRDp::cmd "first " . $self->{NAME};
  $answer = RRDp::read;   
  return $$answer;
}


sub lastValue {
  my ($self) = @_;   
  $self->{FUNCTION} = "\"lastValue\"";     
  RRDp::cmd "last " . $self->{NAME};
  $answer = RRDp::read;   
  return $$answer;
}


sub error {
  my($msg, $line) = @_;  
  $line = "N/A" if(!defined $line or $line eq "");
  print $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}." at line ".$line.".\n" if($self->{"DEBUG"});
  printError($self->{"LOGFILE"}, $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}." at line ".$line.".") 
    if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");    
  return;
}


1;


__END__
=head1 NAME

perfSONAR_PS::DB::RRD - A module that provides methods for dealing with rrd files through the RRDp
perl module.

=head1 DESCRIPTION

This module builds on the simple offerings of RRDp (simple a series of pipes to communicate
with rrd files) to offer some common functionality.    

=head1 SYNOPSIS

    use perfSONAR_PS::DB::RRD;

    my $rrd = new perfSONAR_PS::DB::RRD(
      "./error.log",
      "/usr/local/rrdtool/bin/rrdtool" , 
      "/home/jason/rrd/stout/stout.rrd",
      {'eth0-in'=>"" , 'eth0-out'=>"", 'eth1-in'=>"" , 'eth1-out'=>""},
      1
    );

    # or also:
    # 
    # my $rrd = new perfSONAR_PS::DB::RRD;
    # $rrd->setLog("./error.log");
    # $rrd->setFile("/home/jason/rrd/stout/stout.rrd");
    # $rrd->setPath("/usr/local/rrdtool/bin/rrdtool");  
    # $rrd->setVariables({'eth0-in'=>"" , 'eth0-out'=>"", 'eth1-in'=>"" , 'eth1-out'=>""});  
    # $rrd->setVariable("eth0-in");
    # ...
    # $rrd->setError(1);  
    # $rrd->setDebug($debug);     

    # For reference, here is the create string for the rrd file:
    #
    # rrdtool create stout.rrd \
    # --start N --step 1 \
    # DS:eth0-in:COUNTER:1:U:U \ 
    # DS:eth0-out:COUNTER:1:U:U \
    # DS:eth1-in:COUNTER:1:U:U \
    # DS:eth1-out:COUNTER:1:U:U \
    # RRA:AVERAGE:0.5:10:60480

    # will also 'open' a connection to a file:
    $rrd->openDB();

    my %rrd_result = $rrd->query(
      "AVERAGE", 
      "", 
      "1163525343", 
      "1163525373"
    );

    if($rrd->getErrorMessage()) {
      print "Query Error: " , $rrd->getErrorMessage() , "; query returned: " , $rrd_result{ANSWER} , "\n";
    }
    else {
      my @keys = keys(%rrd_result);
      foreach $a (sort(keys(%rrd_result))) {
        foreach $b (sort(keys(%{$rrd_result{$a}}))) {
          print $a , " - " , $b , "\t-->" , $rrd_result{$a}{$b} , "<--\n"; 
        }
        print "\n";
      }
    }

    $rrd->insert("N", "eth0-in", "1");
    $rrd->insert("N", "eth0-out", "2");
    $rrd->insert("N", "eth1-in", "3");
    $rrd->insert("N", "eth1-out", "4");
                  
    my $insert = $rrd->insertCommit();

    if($rrd->getErrorMessage()) {
      print "Insert Error: " , $rrd->getErrorMessage() , "; insert returned: " , $insert , "\n";
    }

    print "last: " , $rrd->lastValue , "\n";
    if($rrd->getErrorMessage()) {
      print "last Error: " , $rrd->getErrorMessage() , "\n";
    }

    print "first: " , $rrd->firstValue , "\n";
    if($rrd->getErrorMessage()) {
      print "first Error: " , $rrd->getErrorMessage() , "\n";
    }
    
    $rrd->closeDB;    

=head1 DETAILS

RRDp was never meant to a rich API; it's goal is simply to provide a method of interacting
with the underlying RRD files.  The module is to be treated as an object, where each 
instance of the object represents a direct connection to a single rrd file.  Each method 
may then be invoked on the object for the specific database.  

=head1 API

The API of perfSONAR_PS::DB::RRD is rather simple, and attempts to mirror the API of the 
other perfSONAR_PS::DB::* modules.  

=head2 new($log, $path, $file, %datasources, $error)

The 'log' argument is the name of the log file where error or warning information may be 
recorded.  The second represents the path to the rrdtool executable, the third represents 
an actual rrd file.  The fourth can be a hash containing the names of the datasources in 
the rrd file. The final argument is a boolean indicating if errors should be thrown.  
All arguments are optional, and the 'set' functions (setLog($log), setFile($file), 
setPath($path), setVariables(%datasources), setVariables($ds), setError($error)) are 
capable of setting the information as well.  

=head2 setLog($log)

(Re-)Sets the name of the log file to be used.

=head2 setPath($path)

(Re-)Sets the value of the 'path' to the rrdtool executable.

=head2 setFile($file)

(Re-)Sets the value of the name of the rrd 'file' we wish to read from.

=head2 setVariables(\%variables)

Passes a hash of 'datasource' variables names to the object.

=head2 setVariable($variable)

Adds $variable to the hash of datasources in the rrd file.

=head2 setError($error)

(Re-)Sets the value of the error variable (only 1 or 0), which allows you to utilize the
getErrorMessage() function.

=head2 setDebug($debug)

(Re-)Sets the value of the $debug switch.

=head2 getErrorMessage()

Returns the value of an internal error variable ($RRDp::error) if this value happened to 
be set after executing an rrd command.  Note that this will always return nothing if
the error level is set to 0.

=head2 openDB()

Open is used to start the reading process from an rrd file, by preparing named pipes
that will interact with the rrd file.

=head2 closeDB()

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

=head2 insert($time, $ds, $value)

The first value represents time in seconds since epoch (1970-01-01), or the
value 'N' (or 'n').  The second argument is a datasource in the rrd file.  The 
final argument is the value the datasource is measured to have at the particular 
moment in time.  The insert function does not 'finalize' interaction with the rrd 
file, but instead prepares the potential values.  Running insertCommit() will
physically update the file.

=head2 insertCommit()

Takes the values that are stored in the datasource variables and the particular 
instant in time, and sends the changes to the rrd file.

=head2 firstValue

Returns the 'last' timestamp in the RRD file.  

=head2 lastValue

Returns the 'first' timestamp in the RRD file.  

=head2 error($msg, $line)	

A 'message' argument is used to print error information to the screen and log files 
(if present).  The 'line' argument can be attained through the __LINE__ compiler directive.  
Meant to be used internally.

=head1 SEE ALSO

L<RRDp>, L<perfSONAR_PS::Common>, L<perfSONAR_PS::Transport>, L<perfSONAR_PS::DB::SQL>, 
L<perfSONAR_PS::DB::XMLDB>, L<perfSONAR_PS::DB::File>, L<perfSONAR_PS::MP::SNMP>, 
L<perfSONAR_PS::MP::Ping>, L<perfSONAR_PS::MA::General>, L<perfSONAR_PS::MA::SNMP>, 
L<perfSONAR_PS::MA::Ping>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 AUTHOR

Jason Zurawski, E<lt>zurawski@internet2.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Jason Zurawski

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.
