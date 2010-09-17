#!/usr/bin/perl

use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../lib";

my $CONFIG_FILE = "$Bin/../etc/alarms_cgi.conf";

use Config::General;
use CGI;
use Log::Log4perl qw(:easy);
use Template;
use DateTime;

use Data::Dumper;
use perfSONAR_PS::DB::Alarms;

my $duration = 5;
my $alarms_template_file = "alarm_counts.cgi.tmpl";
my $alarms_template_dir  = "$Bin/../etc/templates";
my $database = "alarms.db";
my $images_path = "images";
my $timezone = "America/Chicago";

my $config =  new Config::General($CONFIG_FILE);
my %conf = $config->getall;

$duration = $conf{"duration"} if ($conf{"duration"});
$alarms_template_file = $conf{"alarms_template_file"} if ($conf{"alarms_template_file"});
$database = $conf{"database"} if ($conf{"database"});
$images_path = $conf{"images_path"} if ($conf{"images_path"});
$timezone = $conf{"timezone"} if ($conf{"timezone"});

my %ignoreFilters = ();
if ($conf{"filter"}) {
	my $filters_ref = $conf{"filter"};
	if (ref($filters_ref) ne "ARRAY") {
		my @tmp = ();
		push @tmp, $filters_ref;
		$filters_ref = \@tmp;
	}

	foreach my $filter (@$filters_ref) {
		my ($field, $regex) = split(':', $filter, 2);

		if (not $field or not $regex) {
			next;
		}

		if (not $ignoreFilters{$field}) {
			my @tmp = ();
			$ignoreFilters{$field} = \@tmp;
		}

		push @{ $ignoreFilters{$field} }, $regex;
	}
}

my $cgi = CGI->new();

my $start;
my $end;
my $facility;
my $severity;
my $description;
my $serviceAffecting;

my ($status, $res);

my $client = perfSONAR_PS::DB::Alarms->new("DBI:SQLite:dbname=".$database, q{}, q{}, "ps_tl1_alarms", 1);

($status, $res) = $client->open();


if ($cgi->param('startTime') and $cgi->param('endTime')) {
	$start = $cgi->param('startTime');
	$end = $cgi->param('endTime');

	unless ($end <= time && $end + ($duration * 60) <= time) {
		# if they keep hitting forward and run into "current", redirect
		# them to something with empty parameters.
		print $cgi->redirect(-URL => $cgi->url(-full=>1));
	}
} elsif ($conf{"initial_time"}) {
	$end = $conf{"initial_time"};
	$start = $end - 60*$duration;
} else {
	$end = time;
	$start = $end - 60*$duration;
}

my %timeFilters = ();
$timeFilters{"startTime"} = $start;
$timeFilters{"endTime"} = $end;

my %alarmFilters = ();
#if ($facility) {
#	$alarmFilters{facility} = $facility;
#}
#if ($severity) {
#	$alarmFilters{severity} = $severity;
#}
#if ($description) {
#	$alarmFilters{description} = $description;
#}
#if ($serviceAffecting) {
#	$alarmFilters{serviceAffecting} = $serviceAffecting;
#}

($status, $res) = $client->getAlarms({ timeFilters => \%timeFilters, alarmFilters => \%alarmFilters  });
my $alarms_list = $res;

($status, $res) = $client->getMetadata();
my $metadata_list = $res;

$client->close();

my %host_counts = ();

foreach my $alarm_info (@$alarms_list) {
	my $machineName = $alarm_info->{metadata}->{name};

	my $criticalAlarms = 0;
	my $majorAlarms = 0;
	my $minorAlarms = 0;

	my $non_measurement_alarms = 0;
	my $measurement_alarms = 0;

	foreach my $alarm (@{ $alarm_info->{data} }) {
		my $skip = 0;

		foreach my $field (keys %ignoreFilters) {
			if ($alarm->{$field}) {
				foreach my $filter (@{ $ignoreFilters{$field} }) {
					if ($alarm->{$field} =~ /$filter/) {
						$skip = 1;
					}
				}
			}
		}

		next if ($skip);

		next if ($alarm->{"type"} eq "MEASUREMENT-NOALARMS");

		if ($alarm->{"type"} eq "MEASUREMENT-CONNECTFAILED") {
			$measurement_alarms++;
			next;
		}

		if ($alarm->{"severity"} eq "CR") {
			$criticalAlarms++;
		} elsif ($alarm->{"severity"} eq "MJ") {
			$majorAlarms++;
		} elsif ($alarm->{"severity"} eq "MN") {
			$minorAlarms++;
		} 

		$non_measurement_alarms++;
	}

	my %counts = (
		name => $machineName,
		measurementAlarms => $measurement_alarms,
		nonMeasurementAlarms => $non_measurement_alarms,
		criticalAlarms => $criticalAlarms,
		majorAlarms => $majorAlarms,
		minorAlarms => $minorAlarms,
	);

	$host_counts{$machineName} = \%counts;
}

foreach my $md (@$metadata_list) {
	next if ($host_counts{$md->{name}});

	my %counts = (
		name => $md->{name},
		no_data => 1,
	);

	$host_counts{$md->{name}} = \%counts;
}

my @output_host_info = sort { $a->{name} cmp $b->{name} } values %host_counts;

my %vars = ();
$vars{start} = format_date($start);
$vars{end} = format_date($end);
$vars{nextStartTime} = $end if ($end <= time);
$vars{nextEndTime} = $end + ($duration * 60) if ($end + ($duration * 60) <= time);
$vars{prevStartTime} = $start - ($duration * 60);
$vars{prevEndTime} = $start;
$vars{duration} = $duration;
$vars{images_path} = $images_path ;
$vars{machines} = \@output_host_info;

my $tt = Template->new( INCLUDE_PATH => $alarms_template_dir );
my $html;
$tt->process($alarms_template_file, \%vars, \$html);

print $cgi->header();
print $html;

exit 0;

sub format_date {
	my ($ts) = @_;

	my $dt = DateTime->from_epoch({ epoch => $ts });
	$dt->set_time_zone($timezone);
	my $time_str = $dt->strftime("%Y-%m-%d %H:%M:%S %Z");

	return $time_str;
}
