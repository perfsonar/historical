#!/usr/bin/perl -w 

use strict;
use warnings;

use Params::Validate qw(:all);
use CGI;
use CGI::Carp qw(fatalsToBrowser);
use Template;
use DBI;
use Data::Dumper;

# ###############################
#
# Make sure we get any URL arguments (e.g. we need the mesh name)
#

my $cgi = CGI->new();
print $cgi->header();
my $template = q{};

my $center;
if ( $cgi->param('center') ) {
	$center = $cgi->param('center');
}
else {
#    die "Mesh name not provided, aborting.  Set ?name=SOMENAME in the URL."
	$center = "SCINET1G";
	$center = "SCINET10G2";
	$center = "SCINET10G1";
}

my $duration = $cgi->param('duration');
$duration = 1 unless ($duration);

my $end_time = $cgi->param('end_time');
$end_time = time unless ($end_time);

my $start_time = $cgi->param('start_time');
$start_time = $end_time - $duration * 24 * 60 * 60;

# ###############################
#
# Time information (e.g. we want to check for the most recent of the last 5 test results)
#

my $duration  = 2;		# Days

my $endTime = time;

my $startTime = $endTime - $duration*24*60*60;



my $center_address = $cgi->param('center_address');


# ###############################
#
# OWP specific libraries and defaults
#

use lib "/home/aaron/owamp/lib";

use OWP;
use OWP::Utils;
use bwdb;

my %amidefaults;
BEGIN{
    %amidefaults = (
        CONFDIR => "/opt/perfsonar_ps/perfsonarbuoy_bwctl/etc",
        LIBDIR  => "/opt/perfsonar_ps/perfsonarbuoy_bwctl/lib",
    );
}

my $conf = new OWP::Conf(%amidefaults);

# ###############################
#
# Unroll the owmesh file, get anything we need from there (mesh defns + database info)
#

my $dbhost = $conf->must_get_val(ATTR=>'BWCentralHost');
my $dbtype = $conf->must_get_val(ATTR=>'CentralDBType');
my $dbname = $conf->must_get_val(ATTR=>'BWCentralDBName');
my $dbuser = $conf->must_get_val(ATTR=>'CGIDBUser');
my $dbpass = $conf->get_val(ATTR=>'CGIDBPass');

# ###############################
#
# Connect to the database, get the actual data
#

my $dbsource = $dbtype . ":" . $dbname . ":localhost";

my $dbh = DBI->connect(
    $dbsource,
    $dbuser,
    $dbpass,
    {
        RaiseError => 0,
        PrintError => 1
    }
) || croak "Couldn't connect to database";

use Data::Dumper;

my ($status, $res) = bwdb_lookup_nodes({ first  => owptstampi(time2owptime($startTime)), last => owptstampi(time2owptime($endTime)), dbh => $dbh });

if ($status != 0) {
	die($res);
}

my $nodes = $res;

my %node_values = ();

unless ($nodes->{$center}) {
	die("Unknown node: $center");
}

$node_values{$center} = {};

foreach my $node_address_block (@{ $nodes->{$center} }) {
	my $node = $center;
	my $node_address = $node_address_block->{addr};

	next if ($center_address and $center_address ne $node_address);

	foreach my $other_node (keys %$nodes) {
		next if ($other_node eq $node);

		unless ($node_values{$node}->{$other_node}) {
			$node_values{$node}->{$other_node} = ();
		}

		my @measurement_results = ();

		foreach my $other_address_block (@{ $nodes->{$other_node} }) {
			my $other_address = $other_address_block->{addr};
			my ($status, $res);

			#print "Checking $node/$node_address -> $other_node/$other_address\n";
			($status, $res) = calculate_link_stats({
					dbh => $dbh,
					source => $node,
					source_address => $node_address,
					destination => $other_node,
					destination_address => $other_address,
					start => $startTime,
					end => $endTime });

			my $send_stats = $res;

			($status, $res) = calculate_link_stats({
					dbh => $dbh,
					source => $other_node,
					source_address => $other_address,
					destination => $node,
					destination_address => $node_address,
					start => $startTime,
					end => $endTime });
			my $recv_stats = $res;

			my %pair = ();

			
			unless ( ($send_stats->{min_throughput} and $send_stats->{max_throughput}) or ($recv_stats->{min_throughput} and $recv_stats->{max_throughput}) ) {
				#print "No match\n";
				next;
			}

			$res = convert_units($send_stats->{min_throughput});
			my $send_min_throughput = $res->{value};
			my $send_min_throughput_units = $res->{units};

			$res = convert_units($recv_stats->{min_throughput});
			my $recv_min_throughput = $res->{value};
			my $recv_min_throughput_units = $res->{units};

			$res = convert_units($send_stats->{max_throughput});
			my $send_max_throughput = $res->{value};
			my $send_max_throughput_units = $res->{units};

			$res = convert_units($recv_stats->{max_throughput});
			my $recv_max_throughput = $res->{value};
			my $recv_max_throughput_units = $res->{units};

			$pair{'receive'} = {
				source => $other_node,
				source_address => $other_address,
				destination => $node,
				destination_address => $node_address,
				max_throughput => $recv_max_throughput,
				max_throughput_units => $recv_max_throughput_units,
				min_throughput => $recv_min_throughput,
				min_throughput_units => $recv_min_throughput_units,
			};

			$pair{'send'} = {
				source => $node,
				source_address => $node_address,
				destination => $other_node,
				destination_address => $other_address,
				max_throughput => $send_max_throughput,
				max_throughput_units => $send_max_throughput_units,
				min_throughput => $send_min_throughput,
				min_throughput_units => $send_min_throughput_units,
			};

			$pair{'address'} = $other_address;

			push @measurement_results, \%pair;
		}

		unless ($node_values{$center}->{$other_node}) {
			my %node_info = ();
			$node_info{'name'} = $other_node;
			$node_info{'description'} = $nodes->{$other_node}->[scalar(@{ $nodes->{$other_node} }) - 1]->{longname};
			$node_info{'measurement_results'} = [];

			$node_values{$center}->{$other_node} = \%node_info;
		}

		push @{ $node_values{$center}->{$other_node}->{'measurement_results'} }, @measurement_results;
	}
}

my @results = values %{ $node_values{$center} };

@results = sort { $a->{description} cmp $b->{description} } @results;

my %vars = ();
$vars{primary_node} = $center;
$vars{primary_node_desc} = $nodes->{$center}->[0]->{longname};
$vars{results} = \@results;

my $html;

my $tt = Template->new( INCLUDE_PATH => '.' ) or die( "Couldn't initialize template toolkit" );
$tt->process( "bwctl_star.tmpl", \%vars, \$html ) or die $tt->error();

print $html;

exit 0;


sub calculate_link_stats{
    my $args = validate( @_, { dbh => 1, source => 1, source_address => 0, destination => 1, destination_address => 0, start => 1, end => 1 } );
  
    my $dbh =  $args->{dbh};
    my $source =  $args->{source};
    my $source_address =  $args->{source_address};
    my $destination =  $args->{destination};
    my $destination_address =  $args->{destination_address};
    my $start =  $args->{start};
    my $end =  $args->{end};
 
    my %bwvals = ();

    #$self->{LOGGER}->debug("Looking up stats for $source -> $destination");

    my $bwdb = bwdb_prep(
		DBH         => $dbh,
		SEND_NAME   => $source,
		SEND_ADDR   => $source_address,
		RECV_NAME   => $destination,
		RECV_ADDR   => $destination_address,
		FIRST       => owptstampi( time2owptime($start) ),
		LAST        => owptstampi( time2owptime($end) ),
		BWHASH      => \%bwvals,
		);

    unless ($bwdb) {
	    my $msg = "Unable to init owp data request";
	    #$self->{LOGGER}->error($msg);
	    return (-1, $msg);
    }

    my ($max_throughput, $min_throughput, $num_throughputs, $sum_throughputs, $last_throughput);

    my @throughputs = ();

    while ( bwdb_fetch( BWDBH => $bwdb ) ) {
	    #$self->{LOGGER}->debug("Got bucket for $source -> $destination");

	    my $test_time = owptime2exacttime( $bwvals{'TIME'} );
	    my $test_throughput = eval( $bwvals{'THROUGHPUT'} );

	    push @throughputs, $test_throughput;
            $num_throughputs++;
	    $sum_throughputs += $test_throughput;

 	    $max_throughput = $test_throughput if (not $max_throughput or $max_throughput < $test_throughput);
 	    $min_throughput = $test_throughput if (not $min_throughput or $min_throughput > $test_throughput);

	    # they come out in order
            $last_throughput = $test_throughput;
    }

    my $avg_throughput = undef;
    $avg_throughput = $sum_throughputs / $num_throughputs if ($num_throughputs);

    @throughputs = sort @throughputs;

    my $med_throughput = $throughputs[int($#throughputs/2)];

    #$self->{LOGGER}->debug("Max for $source -> $destination: $max_throughput");

    return (0, { max_throughput => $max_throughput, min_throughput => $min_throughput, average_throughput => $avg_throughput, median_throughput => $med_throughput, last_throughput => $last_throughput });
}

sub convert_units {
	my ($value) = @_;

	my $units = "";

	return ({ value => $value, units => $units }) if (not $value or $value < 1000);

	$value /= 1000;
	$units = "K";

	return ({ value => $value, units => $units }) if ($value < 1000);

	$value /= 1000;
	$units = "M";

	return ({ value => $value, units => $units }) if ($value < 1000);

	$value /= 1000;
	$units = "G";

	return ({ value => $value, units => $units });
}
