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
	$center = "SCINET";
}

my $center_address = $cgi->param('center_address');

my $alpha = $cgi->param('alpha');
$alpha = "1.0" unless (defined $alpha);

my $plot_min = $cgi->param('plot_min');
if ($plot_min) {
	$plot_min = 1;
} else {
	$plot_min = 0;
}

my $text_mode = $cgi->param('text_mode');

# ###############################
#
# OWP specific libraries and defaults
#

use lib "/home/aaron/owamp/lib";

use OWP;
use OWP::Utils;
use owdb;

my %amidefaults;
BEGIN{
    %amidefaults = (
        CONFDIR => "/opt/perfsonar_ps/perfsonarbuoy_owamp/etc",
        LIBDIR  => "/opt/perfsonar_ps/perfsonarbuoy_owamp/lib",
    );
}

my $conf = new OWP::Conf(%amidefaults);

# ###############################
#
# Unroll the owmesh file, get anything we need from there (mesh defns + database info)
#

my $dbhost = $conf->get_val(ATTR=>'OWCentralHost');
my $dbtype = $conf->must_get_val(ATTR=>'CentralDBType');
my $dbname = $conf->must_get_val(ATTR=>'OWPCentralDBName');
my $dbuser = $conf->must_get_val(ATTR=>'CGIDBUser');
my $dbpass = $conf->get_val(ATTR=>'CGIDBPass');

# ###############################
#
# Time information (e.g. we want to check for the most recent of the last 5 test results)
#

my $duration  = 5;		# Minutes

my $endTime = time;

my $startTime = $endTime - $duration*60;


# ###############################
#
# Connect to the database, get the actual data
#

$dbhost = "localhost" unless ($dbhost);

my $dbsource = $dbtype . ":" . $dbname . ":".$dbhost;

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

my ($status, $res) = owdb_lookup_nodes({ first  => owptstampi(time2owptime($startTime)), last => owptstampi(time2owptime($endTime)), dbh => $dbh });

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

			
			unless ( ($send_stats->{min_delay} and $send_stats->{max_delay}) or ($recv_stats->{min_delay} and $recv_stats->{max_delay}) ) {
				#print "No match\n";
				next;
			}

			my $send_loss = $send_stats->{loss};
			my $send_loss_units = "%";

			my $recv_loss = $recv_stats->{loss};
			my $recv_loss_units = "%";

			$res = convert_units($send_stats->{jitter});
			my $send_jitter = $res->{value};
			my $send_jitter_units = $res->{units};

			$res = convert_units($recv_stats->{jitter});
			my $recv_jitter = $res->{value};
			my $recv_jitter_units = $res->{units};

			$res = convert_units($send_stats->{min_delay});
			my $send_min_delay = $res->{value};
			my $send_min_delay_units = $res->{units};

			$res = convert_units($recv_stats->{min_delay});
			my $recv_min_delay = $res->{value};
			my $recv_min_delay_units = $res->{units};

			$res = convert_units($send_stats->{max_delay});
			my $send_max_delay = $res->{value};
			my $send_max_delay_units = $res->{units};

			$res = convert_units($recv_stats->{max_delay});
			my $recv_max_delay = $res->{value};
			my $recv_max_delay_units = $res->{units};

			$pair{'receive'} = {
				source => $other_node,
				source_address => $other_address,
				destination => $node,
				destination_address => $node_address,
				max_delay => $recv_max_delay,
				max_delay_units => $recv_max_delay_units,
				min_delay => $recv_min_delay,
				min_delay_units => $recv_min_delay_units,
				jitter    => $recv_jitter,
				jitter_units => $recv_jitter_units,
				loss => $recv_loss,
				loss_units => $recv_loss_units,
			};

			$pair{'send'} = {
				source => $node,
				source_address => $node_address,
				destination => $other_node,
				destination_address => $other_address,
				max_delay => $send_max_delay,
				max_delay_units => $send_max_delay_units,
				min_delay => $send_min_delay,
				min_delay_units => $send_min_delay_units,
				jitter    => $send_jitter,
				jitter_units => $send_jitter_units,
				loss => $send_loss,
				loss_units => $send_loss_units,
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
$vars{alpha} = $alpha;
$vars{plot_min} = $plot_min;
$vars{text_mode} = $text_mode;

my $html;

my $tt = Template->new( INCLUDE_PATH => '.' ) or die( "Couldn't initialize template toolkit" );
$tt->process( "owamp_star.tmpl", \%vars, \$html ) or die $tt->error();

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
 
    my $max_jitter;
    my $alpha_min = "0.0";
    my $alpha_max = "0.99";

    my %owpvals = ();

    my $owdb = owdb_prep(
		DBH         => $dbh,
		SEND_NAME   => $source,
		SEND_ADDR   => $source_address,
		RECV_NAME   => $destination,
		RECV_ADDR   => $destination_address,
		FIRST       => owptstampi( time2owptime($start) ),
		LAST        => owptstampi( time2owptime($end) ),
		ALPHAS      => [ $alpha_min, $alpha_max ],
		OWHASH      => \%owpvals,
		);

    unless ($owdb) {
	    my $msg = "Unable to init owp data request";
	    return (-1, $msg);
    }

    my ($loss, $max_delay, $min_delay, $jitter);

    while ( my $nbucks = owdb_fetch( OWDBH => $owdb ) ) {
            my $loss_percentage = $owpvals{'LOST'} / $owpvals{'SENT'} * 100;

            my $max = $owpvals{'MAX'} * 1000;
            my $min = $owpvals{'MIN'} * 1000;

            $loss = $loss_percentage if (not $loss or $loss_percentage > $loss);
            $max_delay = $max if (not $max_delay or $max > $max_delay);
            $min_delay = $min if (not $min_delay or $min < $min_delay);
            my $jitter_value = $owpvals{ALPHAS}->{$alpha_max} - $owpvals{ALPHAS}->{$alpha_min};
            $jitter_value *= 1000;

            $jitter = $jitter_value if (not $jitter or $jitter_value > $jitter);
    }

    return (0, { loss => $loss, max_delay => $max_delay, min_delay => $min_delay, jitter => $jitter });
}

sub convert_units {
	my ($value) = @_;

	my $units = "ms";

	return ({ value => $value, units => $units });
}
