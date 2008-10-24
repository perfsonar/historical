#!/usr/bin/perl



### function sto return stuff about ip/dns address
package utils::addresses;
use Socket;

our $logger = Log::Log4perl::get_logger( 'utils::addresses');


sub getDNS
{
	my $ip = shift;
	my $dns = undef;

	$logger->debug( "IN: ip: $ip, dns: $dns");
	# ip is actual ip, get the dns
	if ( &isIpAddress( $ip ) ) {
		$logger->debug( "Fetching dns for ip $ip" );
		$dns = gethostbyaddr( inet_aton($ip), AF_INET )
			unless $ip eq '172.16.12.1';	# blatant hack to reduce time for fnal lookup
	}
	# ip is dns, get the ip
	else {
		$dns = $ip;
		$logger->debug("Fetching ip for dns $dns" );
		my $i = inet_aton($dns);

		if ( $i ne '' ) {
			$ip = inet_ntoa( $i );
		}
		else {
			$logger->warn( "unknown dns for ip $ip\n" );
		}
	}

	$logger->debug( "OUT: ip: $ip, dns: $dns" );
	undef $dns if $dns eq '';
	undef $ip if $ip eq '';
	return ( $ip, $dns );
}

sub isIpAddress
{
	my $ip = shift;
	if ( $ip =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/ ) {
		$ip = $1 . '.' . $2 . '.'  .$3 . '.' . $4;
		return undef if  ( $1 > 255 || $2 > 255 || $3 > 255 || $4 > 255 );
		return $ip;
	}
	return undef;
}

1;
