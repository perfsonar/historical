package perfSONAR_PS::MP::Agent::Ping;


=head1 NAME

perfSONAR_PS::MP::Agent::Ping - A module that will run a ping and
return it's output in a suitable internal data structure.

=head1 DESCRIPTION

Inherited perfSONAR_PS::MP::Agent::CommandLine class that allows a command to 
be executed. This class overwrites the parse and 

=head1 SYNOPSIS

  # create and setup a new Agent  
  my $agent = perfSONAR_PS::MP::Agent::Ping( );
  $agent->init();
  
  # collect the results (i.e. run the command)
  if( $mp->collectMeasurements() == 0 )
  {
  	
  	# get the raw datastructure for the measurement
  	use Data::Dumper;
  	print "Results:\n" . Dumper $self->results() . "\n";

  }
  # opps! something went wrong! :(
  else {
    
    print STDERR "Command: '" . $self->commandString() . "' failed with result '" . $self->results() . "': " . $agent->error() . "\n"; 
    
  }


=cut

# derive from teh base agent class
use perfSONAR_PS::MP::Agent::CommandLine;
our @ISA = qw(perfSONAR_PS::MP::Agent::CommandLine);

use Log::Log4perl qw(get_logger);
our $logger = Log::Log4perl::get_logger( 'perfSONAR_PS::MP::Agent::Ping' );

# command line
our $command = '/bin/ping -c %count% -i %interval% -s %packetSize% -t %ttl% %destination%';

=head2 new( $command, $options, $namespace)

Creates a new ping agent class

=cut
sub new
{
	my $package = shift;
	
	my %hash = ();
	# grab from the global variable
    if(defined $command and $command ne "") {
      $hash{"CMD"} = $command;
    }
    $hash{"OPTIONS"} = {};
  	%{$hash{"RESULTS"}} = ();

  	bless \%hash => $package;
}


=head2 init()

inherited from parent classes. makes sure that the ping executable is existing.

=cute


=head2 command()

accessor/mutator for the ping executable file

=cut
sub command
{
	my $self = shift;
	my $cmdpath = shift;
	
	if ( $cmdpath ) {
		$self->{'CMD'} = $cmdpath;
	}

	return $self->{'CMD'};
}



=head2 cont( $string )

accessor/mutator method to set the number of packets to ping to

=cut
sub count
{
	my $self = shift;
	my $count = shift;
	
	if ( $count ) {
		$self->{'OPTIONS'}->{count} = $count;
	}

	return $self->{'OPTIONS'}->{count};
}

=head2 interval( $string )

accessor/mutator method to set the period between packet pings

=cut
sub interval
{
	my $self = shift;
	my $int = shift;
	
	if ( $int ) {
		$self->{'OPTIONS'}->{interval} = $int;
	}

	return $self->{'OPTIONS'}->{interval};
}



=head2 deadline( $string )

accessor/mutator method to set the deadline value of the pings

=cut
sub deadline
{
	my $self = shift;
	my $deadline = shift;
	
	if ( $deadline ) {
		$self->{'OPTIONS'}->{deadline} = $deadline;
	}

	return $self->{'OPTIONS'}->{deadline};
}

=head2 packetSize( $string )

accessor/mutator method to set the packetSize of the pings

=cut
sub packetSize
{
	my $self = shift;
	my $size = shift;
	
	if ( $size ) {
		$self->{'OPTIONS'}->{packetSize} = $size;
	}

	return $self->{'OPTIONS'}->{packetSize};
}

=head2 ttl( $string )

accessor/mutator method to set the ttl of the pings

=cut
sub ttl
{
	my $self = shift;
	my $ttl = shift;
	
	if ( $ttl ) {
		$self->{'OPTIONS'}->{ttl} = $ttl;
	}

	return $self->{'OPTIONS'}->{ttl};
}




=head2 parse()

parses the output from a command line measurement of pings

=cut
sub parse
{
	my $self = shift;
	my $cmdOutput = shift;
    # use this as indication of the start of the test in epoch secs
    my $time = shift; # work out start time of time
	my $endtime = shift;
	
	my $cmdRan = shift;
	       
    for( my $x = 1; $x < scalar @$cmdOutput - 4; $x++ ) {
    	
    	$logger->debug( "Analysing line: " . $cmdOutput->[$x] );
    	my @string = split /:/, $cmdOutput->[$x];
    	my $v = {};
		( $v->{'bytes'} = $string[0] ) =~ s/\s*bytes.*$//;
		foreach my $t ( split /\s+/, $string[1] ) {
		  $logger->debug( "looking at $t");
          if( $t =~ m/(.*)=(\s*\d+\.?\d*)/ ) { 
	        $v->{$1} = $2;
	        $logger->debug( "  found $1 with $2");
          } else {
            $v->{'units'} = $t; 
          }
		}
		
		$ping->{$x-1} = { 
			'timeValue' => $time + eval($v->{'time'}/1000), #timestamp,
			'time' => $v->{'time'}, # rtt
			'seqNum' => $v->{'icmp_seq'}, #seq
			'ttl' => $v->{'ttl'}, #ttl
			'numByte' => $v->{'bytes'}, #bytes
			'units' => $v->{'units'} || 'ms',
			"timeType" => "unix",
		};        
	        	
  		# next time stamp
     	$time = $time + eval($v->{'time'}/1000);
    
    }

	# set the internal results
	$self->results( $ping );

	return 0;
}




1;

