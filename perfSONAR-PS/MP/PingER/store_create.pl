#!/usr/bin/perl -I ../../lib

use Template;

my $vars = {};
$vars->{pings} = ();


foreach my $name ( qw/ atlang-hstnng.abilene.ucaid.edu mon.es.net / )
{
	my $ping = {};
	$ping->{ip_name_src} = 'iepm-resp.slac.stanford.edu';
	$ping->{ip_number_src} = '134.79.240.36';
	$ping->{ip_name_dst} = $name;
	$ping->{ip_number_dst} = '198.32.8.34';
	$ping->{count} = 10;
	$ping->{interval} = 1;
	$ping->{packetSize} = 100;
	$ping->{ttl} = 64;
	$ping->{testPeriod} = 30;
	$ping->{testOffsetType} = 'Flat';
	$ping->{testOffset} = 0;
	$ping->{storeType} = 'MA';
	$ping->{storeFile} = 'http://localhost:8080/';

	push @{$vars->{pings}}, $ping;

}

my $tt = Template->new();
$tt->process( 'store.tmpl', $vars ) or die "Could not process template";

1;
