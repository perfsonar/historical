#!/usr/bin/perl

use Statistics::Descriptive;
use Log::Log4perl qw(get_logger :levels);



#######################################################################
package IEPM::PingER::Statistics::RTT;
#######################################################################

our $logger = Log::Log4perl::get_logger("IEPM::PingER::Statistics::RTT");

sub calculate
{
  my $rtts = shift; # reference to list of rtts
  
  $logger->debug("input: $rtts");
  if ( $rtts !~ /ARRAY/ ) {
    $logger->fatal( "Input needs to be a reference to an array of rtt values ($rtts).");
    return ( undef, undef, undef, undef );
  }
  
  $logger->debug( "size: " . scalar @$rtts );
   if ( scalar @$rtts > 0 ) {

     my $stat = Statistics::Descriptive::Full->new();

     for( my $i=0; $i<scalar @$rtts; $i++ ) {

        return  ( undef, undef, undef, undef ) unless ( $rtts->[$i] =~ /^\s*\d\.?\d*\s*$/ );
  	$stat->add_data( $rtts->[$i] );
     }
     my $min = $stat->min();
     my $max = $stat->max();
     my $mean = $stat->mean();
     my $median = $stat->median();

     return ( $min == 0 ? undef : $min, $mean == 0 ? undef : $mean, $max == 0 ? undef : $max, $median == 0 ? undef : $median );
	  
   } else {
  	  return ( undef, undef, undef, undef );
   }
}

#######################################################################
package IEPM::PingER::Statistics::IPD;
#######################################################################

our $logger = Log::Log4perl::get_logger("IEPM::PingER::Statistics::IPD");

use strict;

sub calculate
{
  my $rtts = shift; # reference to list of rtts
  
  $logger->debug("input: $rtts");
  if ( $rtts !~ /ARRAY/ ) {
    $logger->fatal( "Input needs to be a reference to an array of latency values.");
    return ( undef, undef, undef, undef, undef );
  }
 
  my $size = scalar @$rtts;
  $logger->debug( "Size: " . $size ); 
  
  # need special case as we can not determine the ipd for only one packet
  if ( $size > 1 ) {

    my $stat = Statistics::Descriptive::Full->new();
 
        return  ( undef, undef, undef, undef, undef ) unless ( $rtts->[0] =~ /^\s*\d\.?\d*\s*$/ );

  	  my @ipds = ();
	  for( my $i=1; $i<scalar @$rtts; $i++ ) {
  	
            return  ( undef, undef, undef, undef, undef ) unless ( $rtts->[$i] =~ /^\s*\d\.?\d*\s*$/ );
	    my $ipd = $rtts->[$i] - $rtts->[$i-1];
	    $ipd = sprintf( "%.3f", abs( $ipd ) );;
	    $logger->debug( " adding $ipd"); 
	    $stat->add_data($ipd);

	  }
	  
	  my $seventyfifth = $stat->percentile(75);
	  my $twentyfifth = $stat->percentile(25);
	  my $iqr = undef;
	  if ( defined $seventyfifth && defined $seventyfifth ) {
	  	$iqr = $seventyfifth - $twentyfifth;
	  }
	  
	  return ( $stat->min(), $stat->mean(), $stat->max(), $stat->median(),  $iqr );

  } else {
    return ( undef, undef, undef, undef, undef );
  }
}



#######################################################################
package IEPM::PingER::Statistics::Other;
#######################################################################

our $logger = Log::Log4perl::get_logger("IEPM::PingER::Statistics::Other");

###
# takes in a reference to a list of sequence numbers
###
sub calculate
{
  my $sent = shift;
  my $recv = shift;

  my $seqs = shift;

  
  $logger->debug( "input: sent $sent, recv $recv, seqs $seqs");
  if ( $seqs !~ /ARRAY/ ) {
    $logger->fatal( "Input needs to be a reference to an array of packet sequence values.");
    return ( undef, undef );
  }
  
  return ( undef, undef ) if scalar @$seqs < 2;
  
  # dups and ooo
  my $dups = 0;
  my $ooo = 0;
  
  # seen initiate with first element as loop doesn't
  
  # ooo
  my %seen = ();
  $seen{$seqs->[0]}++;
  $logger->debug("Searching for Out of Order packets");

  #doubel check the input
  return (undef,undef) if ( $seqs->[0] > $sent );

  for( my $i=1; $i<scalar @$seqs; $i++) {
    
    return (undef, undef) if ( $seqs->[$i] > $sent );

    $logger->debug( " Looking at " . $seqs->[$i] );
    if ( $seqs->[$i] >= $seqs->[$i-1] ) { # note => means that dups are not counted as out of order
      # okay
    } else {
      $logger->debug( " Found duplicate at $i / $seqs->[$i]");
      $ooo++;
    }
    # dups
    $seen{$seqs->[$i]}++;
  }


  $logger->debug("Searching for Duplicate packets");
  # analyse dups
  foreach my $k ( keys %seen ) {
  	$logger->debug( " Saw packet #$k " . $seen{$k} . " times");
    if( $seen{$k} > 1 ) {
      $dups++;
    }
  }
  
  return ( $dups == 0 ? 'false' : 'true', $ooo == 0 ? 'false' : 'true' );
}



#######################################################################
package IEPM::PingER::Statistics::Loss;
#######################################################################

our $logger = Log::Log4perl::get_logger("IEPM::PingER::Statistics::Loss");

###
# takes in a reference to a list of sequence numbers
###
sub calculate
{
  my $sent = shift;
  my $recv = shift;
  
  $logger->debug("input: $sent / $recv");
  if ( ! defined $sent || ! defined $recv || $sent < $recv ) {
    $logger->fatal( "Error in parsing loss with sent ($sent), recieved ($recv).");
    return undef;
  }
  
  return 100 - 100 * ( $recv / $sent );
}


#######################################################################
package IEPM::PingER::Statistics::Loss::CLP;
#######################################################################

###
# Conditional Loss Probability (CLP) defined in Characterizing End-to-end
# Packet Delay and Loss in the Internet by J. Bolot in the Journal of
# High-Speed Networks, vol 2, no. 3 pp 305-323 December 1993.
# See: http://citeseer.ist.psu.edu/bolot93characterizing.html
###

our $logger = Log::Log4perl::get_logger("IEPM::PingER::Statistics::Loss::CLP");

###
# takes in a reference to a list of sequence numbers
###
sub calculate
{
  my $pktSent = shift;
  my $pktRcvd = shift;
  my $seqs = shift;
  
  $logger->debug( "input: sent $pktSent / recv $pktRcvd ($seqs)");
  if ( $seqs !~ /ARRAY/ ) {
    $logger->fatal( "Input should be list of sequence numbers.");
  }
  # undef if no data  
  return undef if scalar @$seqs < 1;
  
  if ( $pktRcvd != scalar @$seqs ) {
    $logger->fatal( "pkts recvd ($pktRcvd) is not equal to size of array (@$seqs)");
    return undef;
  }

  my @lost_packets=();
  my @icmp_seqs = @$seqs;  
  my $consecutive_packet_loss=0;
  
  $logger->debug( "Determining lost packets from sequence (@$seqs)");
  for my $i (0 ..  $pktSent - 1 ) {
     $logger->debug( " Looking at packet #$i");
     if(!defined($icmp_seqs[$i])) {
       $logger->debug( "  seqs[$i] not defined (sent '$pktSent' recv '$pktRcvd') for @$seqs" );
     }
     if($icmp_seqs[$i] != $i) {
       return undef if ( $icmp_seqs[$i] > $pktSent );
       push @lost_packets, $i;
       unshift @icmp_seqs, "0";
       $logger->debug( "  Found lost packet #$i (lost: @lost_packets) / (all: @icmp_seqs)");
     }
  }

  $logger->debug( "Determining consequtively lost packets");

  for my $j (1 .. scalar @lost_packets - 1) {	
  	$logger->debug( " Looking at lost pkt #" . $lost_packets[$j] . " compared to pkt #" . $lost_packets[$j-1]);
    if ($lost_packets[$j]==$lost_packets[$j-1]+1) {
      $consecutive_packet_loss++;
      $logger->debug( "  Consequtively lost packets = $consecutive_packet_loss");
    }
  }
  my $clp = undef;
  my $lost_packets = $pktSent - $pktRcvd;
  if ( $lost_packets > 1  ) {
    $clp = sprintf "%3.3f", $consecutive_packet_loss*100/($lost_packets - 1);
  }
  return $clp;
  
}



1;