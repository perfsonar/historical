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
my $alarms_template_file = "alarms.cgi.tmpl";
my $alarms_template_dir  = "$Bin/../etc/templates";
my $database = "alarms.db";
my $images_path = "images";
my $timezone = "America/Los_Angeles";

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

my $node = $cgi->param("node");

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

# construct the "alarms" table like Template Toolkit will be expecting
my $found_alarm = 0;
my @output_alarms = ();
my %hosts_with_data = ();

foreach my $alarm_info (@$alarms_list) {
	my $machineName = $alarm_info->{metadata}->{name};

	$hosts_with_data{$machineName} = 1;

	next if ($node and $node ne $alarm_info->{metadata}->{name});

	foreach my $alarm (@{ $alarm_info->{data} }) {
		# Skip if it's the "we have no alarms" 'alarm'. Need some way
		# of saying "no alarms", and this is the only way in the DB to
		# do so.
		next if ($alarm->{type} eq "MEASUREMENT-NOALARMS");

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

		$found_alarm = 1;
		my $color;
		if ($alarm->{"severity"} eq "CR") {
			$color="red";
		} elsif ($alarm->{"severity"} eq "MJ") {
			$color="orange"
		} elsif ($alarm->{"severity"} eq "MN") {
			$color="yellow"
		} elsif ($alarm->{serviceAffecting} eq "false") {
			$color="lightgray"
		}; 

		$color = "purple" if ($alarm->{type} eq "MEASUREMENT-CONNECTFAILED");

		my %current = ();
		$current{"machineName"} = $machineName;
		#$current{"alarmStartTime"} = scalar localtime($alarm->{'startTime'});
		$current{"alarmStartTime"} = format_date($alarm->{'startTime'});
		$current{"alarmFacility"} = $alarm->{'facility'};
		$current{"alarmSeverity"} = $alarm->{'severity'};
		$current{"alarmDescription"} = $alarm->{'description'};
		$current{"alarmType"} = $alarm->{'type'};
		$current{"alarmServiceAffecting"} = $alarm->{'serviceAffecting'};
		$current{"color"} = $color;

		push @output_alarms, \%current;
	}
}

my @no_data_hosts = ();
foreach my $md (@$metadata_list) {
	next if ($hosts_with_data{$md->{name}});

	next if ($node and $md->{name} ne $node);

	push @no_data_hosts, $md->{name};
}

# sort the no_data_hosts and output_alarms since it's easier here than in TT
@output_alarms = sort { $a->{machineName}.$a->{alarmFacility}.$a->{alarmStartTime} cmp $b->{machineName}.$b->{alarmFacility}.$b->{alarmStartTime} } @output_alarms;
@no_data_hosts = sort @no_data_hosts;

my %vars = ();
$vars{start} = format_date($start);
$vars{end} = format_date($end);
$vars{nextStartTime} = $end if ($end <= time);
$vars{nextEndTime} = $end + ($duration * 60) if ($end + ($duration * 60) <= time);
$vars{prevStartTime} = $start - ($duration * 60);
$vars{prevEndTime} = $start;
$vars{duration} = $duration;
$vars{images_path} = $images_path ;
$vars{alarms} = \@output_alarms;
$vars{no_data_hosts} = \@no_data_hosts;

open(TMP, ">/tmp/aaron");
print TMP Dumper(\%vars);
close(TMP);

my $tt = Template->new( INCLUDE_PATH => $alarms_template_dir );
my $html;
$tt->process($alarms_template_file, \%vars, \$html) or die $tt->error();

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
