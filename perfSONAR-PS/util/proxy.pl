#!/usr/bin/perl -I ../lib

=head1 NAME

proxy - a simple http application level proxy to divert perfSONAR requests to another host

=head1 DESCRIPTION

SLAC, for example, has very strict restrictions on the use of visible web servers. Most of the important network monitoring machines have placed in 'Internet Free Zones' so that external (non SLAC) access is prohibited.

This application level proxy allows an Internet visible host to rely messages to such a host; allowing access to the 'hidden' host without messing around with rsync etc. of the files.

Note that the 'hidden' host still needs to run a perfSONAR_PS MA or MP.

=head1 SYNOPSIS

  

=cut


use warnings;
use strict;
use threads;
use POSIX qw( setsid );
use Getopt::Long;

use Log::Log4perl qw( get_logger :levels );

use perfSONAR_PS::Messages;
use perfSONAR_PS::Transport;
use perfSONAR_PS::Common;


# local setup vairables
our $PORT = 8080;
our $ENDPOINT = 'axis/services/snmpMA';

# rempte proxy to host
our $rPORT = 8080;
our $rHOST = 'lanmon-dev.slac.stanford.edu';
our $rENDPOINT = 'axis/services/snmpMA';

our $DAEMON = 0;

# parse ocmmandline
our $help_needed;

my $ok = GetOptions (
			'lport=s'		=> \$PORT,
			'lendpoint=s'	=> \$ENDPOINT,
			'rhost=s'		=> \$rHOST,
			'rport=s'		=> \$rPORT,
			'rendpoint=s'	=> \$rENDPOINT,
			'daemon'	=> \$DAEMON,
			);

if ( ! $ok or $help_needed ) {
	print "$0: application level proxy for http requests.\n";
	print "    ./$0.pl [--lport=n --lendpoint=ENDPOINT --rhost=xxx.yyy.zzz --rport=n --rendpoint=ENDPOINT --daemon]\n";
	exit 1;
}


my %ns = (
  nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
  netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
  nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
  select => "http://ggf.org/ns/nmwg/ops/select/2.0/"
);


if ( $DAEMON ) {
  $| = 1;
  chdir '/' or die "Can't chdir to /: $!";
  open STDIN, '/dev/null' or die "Can't read /dev/null: $!";
  open STDOUT, '>>/dev/null' or die "Can't write to /dev/null: $!";
  open STDERR, '>>/dev/null' or die "Can't write to /dev/null: $!";
  defined(my $pid = fork) or die "Can't fork: $!";
  exit if $pid;
  setsid or die "Can't start a new session: $!";
  umask 0;
}


# logging
Log::Log4perl->init( "../MA/SNMP/logger.conf" );
my $logger = get_logger( "perfSONAR_PS" );

# start thread
my $proxyThread = threads->new( \&proxy );

if ( ! defined $proxyThread ) {
  $logger->fatal("Thread creation has failed... exiting." );
  exit(1);
}


$proxyThread->join();




sub proxy()
{
  $logger->debug( "Starting '". threads->tid() . "' as the proxy." );

  while( 1 ) {
    my $runThread = threads->new( \&proxyQuery );
    if( ! defined $runThread  ) {
	$logger->fatal( "Thread creation failed... exiting." );
	exit( 1 );
    }
    $runThread->join();
  }

  return;
}


sub proxyQuery 
{
  $logger->debug("Starting '" . threads->tid() . "' as the execution path." );

  my $listener = new perfSONAR_PS::Transport(
        \%ns, $PORT, $ENDPOINT, "", "", ""
  );
  $listener->startDaemon;
  if ( ! defined $listener->{DAEMON} ) {
    $logger->fatal( "Cannot start daemon." );
    exit ( 1);
  }

  # deal with incoming request
  my $resp = undef;
  my $readValue = $listener->acceptCall;
  if ( $readValue == 0 ) {
    $logger->debug( "Received 'shadow' request from below; no action required." );
    $resp = $listener->getResponse();
  }
  # this is where we do something interesting: we simply rely the message to the defined host etc and wait for a reply and sent that back
  elsif ( $readValue == 1 ) {
    $logger->debug( "Received request to act on." );
    
    # foramt the request into an object to send to the rHost
    my $msg = $listener->{REQUEST}->content;
    
    # create the rRequest message from the above
    my $proxy = new perfSONAR_PS::Transport("", "", "", $rHOST, $rPORT, $rENDPOINT );
    $logger->debug( "Sending:\n$msg" );
    $resp = $proxy->sendReceive( $msg );
    $logger->debug( "Recvd:\n$resp" );

  }
  else {
    my $msg = "Send Request was not expected: " . $listener->{REQUEST}->uri . ", " . $listener->{REQUEST}->method . ", " . $listener->{REQUEST}->headers->{'soapaction'} . "." ;
    $logger->error( $msg );
    $resp = getResultCodeMessage( "", "", "response", "error.transport.soap", $msg );
  }

  # send response
  $logger->debug( "Sending back response..." );
  $listener->setResponse( $resp );

  $logger->debug( "Closing call." );
  $listener->closeCall;


  return;
}



=head1 REQUIRES


perfSONAR_PS::Transport;
Getopt::Long;
Log::Log4perl;

=head1 AUTHOR

Yee-Ting Li <ytl@slac.stanford.edu>

=head1 VERSION

Current version is this one ;) 

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Yee-Ting Li 

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut

