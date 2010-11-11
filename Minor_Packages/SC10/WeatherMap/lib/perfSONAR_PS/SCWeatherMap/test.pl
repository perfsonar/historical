use strict;
use warnings;

use lib 'lib';
use Data::Dumper;

use perfSONAR_PS::DB::ESxSNMP_API;

my $db = new perfSONAR_PS::DB::ESxSNMP_API("http://monitor.sc09.org:8001/");

my $outgoing_interfaces;
my %collect_routers = (
		"core-sw-1" => {
			"xe-4/0/0" => { 
				endpoint => "nlr",
			},
			"xe-5/0/0" => { 
				endpoint => "nlr",
			},
			"xe-0/0/0" => { 
				endpoint => "nlr",
			},
			"xe-1/0/0" => { 
				endpoint => "esnet",
			},
			"xe-7/3/0" => { 
				endpoint => "esnet",
			},
			"xe-2/0/0" => { 
				endpoint => "ion",
			},
		}
);

my @booths = (
	{
		vlan_range => "3703-3705",
		name => "Utah",
		endpoint => "utah",
	},
	{
		vlan_range => "3706,3820,810-815,3100-3102",
		name => "Caltech",
		endpoint => "caltech",
	},
	{
		vlan_range => "3709",
		name => "SDSC",
		endpoint => "sdsc",
	},
	{
		vlan_range => "3710,2820-2829",
		name => "KISTI",
		endpoint => "kisti",
	},
	{
		vlan_range => "3103-3109,2860-2863,2890-2899",
		name => "NICT",
		endpoint => "nict",
	},
	{
		vlan_range => "3800-3801",
		name => "PIONIER",
		endpoint => "pionier",
	},
	{
		vlan_range => "3110-3114,3561-3563",
		name => "Internet2",
		endpoint => "internet2",
	},
	{
		vlan_range => "3033",
		name => "Northrop Grumman",
		endpoint => "ngc",
	},
	{
		vlan_range => "3810,2600-2609",
		name => "Dutch Pavilion",
		endpoint => "uva",
	},
	{
		vlan_range => "2846-2848,2506-2508",
		name => "University of Tokyo",
		endpoint => "tokyo",
	},
	{
		vlan_range => "96,2720-2723",
		name => "NCDM",
		endpoint => "ncdm ",
	},
	{
		vlan_range => "821",
		name => "Georgia Tech",
		endpoint => "gatech",
	},
	{
		vlan_range => "459",
		name => "KAUST",
		endpoint => "kaust ",
	},
	{
		vlan_range => "459",
		name => "KAUST",
		endpoint => "kaust ",
	},
);

#xe-4/0/0 - nlr
#xe-5/0/0 - nlr
#xe-0/0/0 - nlr              
#xe-1/0/0 - esnet
#xe-2/0/0 - internet2
#xe-7/3/0 - esnet

my %vlans = ();

my $routers = $db->get_routers;
foreach my $child (@{ $routers->{children} }) {
	next unless ($collect_routers{$child->{name}});

	my $router_name = $child->{name};

	my $interfaces = $db->get_interfaces($child->{name});
	foreach my $iface_child (@{ $interfaces->{children} }) {
		foreach my $monitored_interface (keys %{ $collect_routers{$child->{name}} }) {
			if ($iface_child->{name} =~ /$monitored_interface\.([0-9]+)/) {
				my $vlan = $1;

				unless ($vlans{$router_name}) {
					$vlans{$router_name} = {};
				}

				unless ($vlans{$router_name}->{$monitored_interface}) {
					$vlans{$router_name}->{$monitored_interface} = ();
				}

				push @{ $vlans{$router_name}->{$monitored_interface} }, $vlan;
			}
		}
	}
}

my $end_time = time;
my $start_time = $end_time - 5*60;

my %booth_statuses = ();

foreach my $router (keys %vlans) {
	foreach my $iface (keys %{ $vlans{$router} }) {
		foreach my $vlan (@{ $vlans{$router}->{$iface} }) {
			foreach my $booth_info (@booths) {

				my @ranges = split(',', $booth_info->{vlan_range});
				foreach my $range (@ranges) {
					my ($min, $max) = split('-', $range);
					$max = $min unless ($max);

					next unless ($min <= $vlan and $max >= $vlan);

					# Found a known vlan
					my $src_endpoint = $booth_info->{endpoint};
					my $dst_endpoint = $collect_routers{$router}->{$iface}->{endpoint};

					unless ($booth_statuses{$src_endpoint}) {
						$booth_statuses{$src_endpoint} = {};
					}

					unless ($booth_statuses{$src_endpoint}->{$dst_endpoint}->{data}) {
						$booth_statuses{$src_endpoint}->{$dst_endpoint}->{data} = {};
					}

					my $data = $booth_statuses{$src_endpoint}->{$dst_endpoint}->{data};

					fill_data(router => $router, interface => $iface.".".$vlan, start_time => $start_time, end_time => $end_time, dbh => $db, data => $data);
				}
			}
		}
	}
}

print Dumper(\%booth_statuses);

exit 0;

sub fill_data {
	my %args = @_;

	my $router = $args{router};
	my $interface = $args{interface};
	my $start_time = $args{start_time};
	my $end_time = $args{end_time};
	my $dbh = $args{dbh};
	my $existing_data = $args{data};

	my $active = 0;

	foreach my $direction ("in", "out") {
		my $data = $db->get_interface_data($router, $interface, $start_time, $end_time, $direction);
		foreach my $datum (@{ $data->{data} }) {
			$existing_data->{$datum->[0]} = () unless ($existing_data->{$datum->[0]});
			$existing_data->{$datum->[0]}->{$direction} = 0 unless ($existing_data->{$datum->[0]}->{$direction});

			$datum->[1] *= 8;
			$existing_data->{$datum->[0]}->{$direction} += $datum->[1];
		}
	}

	return;
}
