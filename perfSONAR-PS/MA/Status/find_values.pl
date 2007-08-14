#!/usr/bin/perl
#################
# find_values.pl
#     This is a sample script to show how status information about a given link
#     should be output. It simply randomly selects a state based on the
#     argument passed.
#
#     A real script might consult an SNMP MA or consult the router via the CLI
#
#     The script should output something like:
#
#     timestamp,[state]
#################

my $type = shift;

my @oper_states = (
	"up",
	"down",
	"degraded",
);

my @admin_states = (
	"normaloperation",
	"maintenance",
	"troubleshooting",
	"underrepair",
);

srand($$ . time);

my $state;

if ($type eq "admin") {
	my $n = int(rand($#admin_states));
	$state = $admin_states[$n];
} elsif ($type eq "oper") {
	my $n = int(rand($#oper_states));
	$state = $oper_states[$n];
} else {
	$state = "unknown";
}

$msg = time() . "," . $state;
print $msg;
