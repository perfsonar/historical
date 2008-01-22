package perfSONAR_PS::DB::RRD;

use fields 'PATH', 'NAME', 'DATASOURCES', 'COMMIT';

our $VERSION = 0.06;

use strict;
use warnings;
use RRDp;
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Common;

sub new {
  my ($package, $path, $name, $dss, $error) = @_;   

  my $self = fields::new($package);
  if(defined $path and $path ne "") {
    $self->{PATH} = $path;
  }
  if(defined $name and $name ne "") {
    $self->{NAME} = $name;
  }
  if(defined $dss and $dss ne "") {
    $self->{DATASOURCES} = \%{$dss};  
  }  
  if(defined $error and $error ne "") {
    if($error == 1) {
      $RRDp::error_mode = 'catch';
    }
    else {
      undef $RRDp::error_mode;
    }
  }  
  return $self;
}


sub setFile {
  my ($self, $file) = @_;  
  my $logger = get_logger("perfSONAR_PS::DB::RRD");
  if(defined $file and $file ne "") {
    $self->{NAME} = $file;
  }
  else {
    $logger->error("Missing argument.");  
  }
  return;
}


sub setPath {
  my ($self, $path) = @_;  
  my $logger = get_logger("perfSONAR_PS::DB::RRD");
  if(defined $path and $path ne "") {
    $self->{PATH} = $path;
  }
  else {
    $logger->error("Missing argument.");  
  }
  return;
}


sub setVariables {
  my ($self, $dss) = @_;  
  my $logger = get_logger("perfSONAR_PS::DB::RRD");
  if(defined $dss and $dss ne "") { 
    $self->{DATASOURCES} = \%{$dss};
  }
  else {
    $logger->error("Missing argument.");  
  }
  return;
}


sub setVariable {
  my ($self, $dss) = @_;  
  my $logger = get_logger("perfSONAR_PS::DB::RRD");
  if(defined $dss and $dss ne "") {
    $self->{DATASOURCES}->{$dss} = "";
  }
  else {
    $logger->error("Missing argument.");
  }
  return;
}


sub setError {
  my ($self, $error) = @_;  
  my $logger = get_logger("perfSONAR_PS::DB::RRD");
  if(defined $error and $error ne "") {
    if($error == 1) {
      $RRDp::error_mode = 'catch';
    }
    else {
      undef $RRDp::error_mode;
    }
  }
  else {
    $logger->error("Missing argument.");
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
  my $logger = get_logger("perfSONAR_PS::DB::RRD");
  if(defined $self->{PATH} and defined $self->{NAME}) {
    RRDp::start $self->{PATH};
    return 0;
  }
  else {
    $logger->error("Missing path or name in object.");        
    return -1;
  }
}


sub closeDB {
  my ($self) = @_;   
  my $logger = get_logger("perfSONAR_PS::DB::RRD");
  if((defined $self->{PATH} and $self->{PATH} ne "") and 
     (defined $self->{NAME} and $self->{NAME} ne "")){
    my $status = RRDp::end;  
    if($status) {
      $logger->error($self->{PATH}." has returned status \"".$status."\" on closing.");    
      return -1;
    }
    return 0;
  }
  else {
    $logger->error("RRD not open.");  
    return -1;
  }
}


sub query {
  my ($self, $cf, $resolution, $start, $end) = @_; 
  my $logger = get_logger("perfSONAR_PS::DB::RRD");
  my %rrd_result = ();
  my @rrd_headings = ();  
  if(defined $cf and $cf ne "") {  
    my $cmd = "fetch " . $self->{NAME} . " " . $cf;
    if(defined $resolution and $resolution ne "") {
      $cmd = $cmd . " -r " . $resolution;
    }    
    if(defined $start and $start ne "") {
      $cmd = $cmd . " -s " . $start;
    }
    if(defined $end and $end ne "") {
      $cmd = $cmd . " -e " . $end;
    }

    RRDp::cmd $cmd;    
    my $answer = RRDp::read;      
    if($RRDp::error) {   
      $logger->error("Database error \"".$RRDp::error."\"."); 
      %rrd_result = ();
      $rrd_result{ANSWER} = $RRDp::error;
    }
    else {   
      if(defined $$answer and $$answer ne "") {
        my @array = split(/\n/,$$answer);
        for(my $x = 0; $x <= $#{@array}; $x++) {
          if($x == 0) {
            @rrd_headings = split(/\s+/,$array[$x]);
          }
          elsif($x > 1) {
            if(defined $array[$x] and $array[$x] ne "") {
              my @line = split(/\s+/,$array[$x]);
              $line[0] =~ s/://;
              for(my $z = 1; $z <= $#{@rrd_headings}; $z++) {
                if($line[$z]) {
                  $rrd_result{$line[0]}{$rrd_headings[$z]} = $line[$z];
                }
              }
            }   
          }
        }
      }
    }
  }    
  else {
    $logger->error("Missing argument."); 
  }
  return %rrd_result; 
}


sub insert {
  my ($self, $time, $ds, $value) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::RRD");
  if((defined $time and $time ne "") and
     (defined $ds and $ds ne "") and 
     (defined $value and $value ne "")) { 
    $self->{COMMIT}->{$time}->{$ds} = $value;
  }
  else { 
    $logger->error("Missing argument(s)."); 
  }  
}


sub insertCommit {
  my ($self) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::RRD");
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
      $logger->error("RRDTool cannot update when datasource values are not specified.");  
    }
    else {
      delete $self->{COMMIT}->{$time};
      $cmd = $cmd . $template . " " . $values;     
      RRDp::cmd $cmd;
      $answer = RRDp::read; 
      if($RRDp::error) {   
        # do nothing
      }
      else {
        push @result, $$answer; 
      }
    } 
  }
  return @result;
}


sub firstValue {
  my ($self) = @_;
  RRDp::cmd "first " . $self->{NAME};
  my $answer = RRDp::read;   
  if(!$RRDp::error) {   
    chomp($$answer);
    return $$answer;
  }
  return "";
}


sub lastValue {
  my ($self) = @_;
  RRDp::cmd "last " . $self->{NAME};
  my $answer = RRDp::read;   
  if(!$RRDp::error) {   
    chomp($$answer);
    return $$answer;
  }
  return "";
}


sub lastTime {
  my ($self) = @_;
  RRDp::cmd "lastupdate " . $self->{NAME};
  my $answer = RRDp::read;
  my @result = split(/\n/, $$answer);
  my @time = split(/:/, $result[$#result]);
  if(!$RRDp::error and $time[0]) {
    return $time[0];
  }
  return "";
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
      "/usr/local/rrdtool/bin/rrdtool" , 
      "/home/jason/rrd/stout/stout.rrd",
      {'eth0-in'=>"" , 'eth0-out'=>"", 'eth1-in'=>"" , 'eth1-out'=>""},
      1
    );

    # or also:
    # 
    # my $rrd = new perfSONAR_PS::DB::RRD;
    # $rrd->setFile("/home/jason/rrd/stout/stout.rrd");
    # $rrd->setPath("/usr/local/rrdtool/bin/rrdtool");  
    # $rrd->setVariables({'eth0-in'=>"" , 'eth0-out'=>"", 'eth1-in'=>"" , 'eth1-out'=>""});  
    # $rrd->setVariable("eth0-in");
    # ...
    # $rrd->setError(1);     

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
    if ($rrd->openDB() == -1) {
      print "Error opening database\n";
    }

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
    
    if ($rrd->closeDB == -1) {
      print "Error closing database\n";
    }
    
=head1 DETAILS

RRDp was never meant to a rich API; it's goal is simply to provide a method of interacting
with the underlying RRD files.  The module is to be treated as an object, where each 
instance of the object represents a direct connection to a single rrd file.  Each method 
may then be invoked on the object for the specific database.  

=head1 API

The API of perfSONAR_PS::DB::RRD is rather simple, and attempts to mirror the API of the 
other perfSONAR_PS::DB::* modules.  

=head2 new($package, $path, $name, $dss, $error)

The first arguments represents the path to the rrdtool executable, the second represents 
an actual rrd file.  The third can be a hash containing the names of the datasources in 
the rrd file. The final argument is a boolean indicating if errors should be thrown.  
All arguments are optional, and the 'set' functions (setLog($log), setFile($file), 
setPath($path), setVariables(%datasources), setVariables($ds), setError($error)) are 
capable of setting the information as well.  

=head2 setFile($self, $file)

Sets the RRD filename.

=head2 setPath($self, $path)

Sets the 'path' to the RRD binary.

=head2 setVariables($self, $dss)

Sets several variables (in an array) in the RRD.

=head2 setVariable($self, $dss)

Sets a variable value in the RRD.

=head2 setError($self, $error)

Sets the error variable.

=head2 getErrorMessage($self)

Gets any error returned from the underlying RRDp module. 

=head2 openDB($self)

'Opens' (creates a pipe) to an RRD.

=head2 closeDB($self)

'Closes' (terminates the pipe) of an open RRD.

=head2 query($self, $cf, $resolution, $start, $end)

Query a RRD with specific times/resolutions.

=head2 insert($self, $time, $ds, $value)

'Inserts' a time/value pair for a given variable.  These are not inserted
into the RRD, but will 'wait' until we commit.  This allows us to stack
up a bunch of values first.  and reuse time values. 

=head2 insertCommit($self)

'Commits' all outstanding variables time/data pairs for a given RRD.

=head2 firstValue($self) 

Returns the first value of an RRD

=head2 lastValue($self)

Returns the last value of an RRD. 

=head2 lastTime($self)

Returns the last time the RRD was updated. 

=head1 SEE ALSO

L<RRDp>, L<Log::Log4perl>, L<perfSONAR_PS::Common>

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
