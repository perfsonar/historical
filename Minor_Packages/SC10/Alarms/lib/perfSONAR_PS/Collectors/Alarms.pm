package perfSONAR_PS::Collectors::Alarms;

use Data::Dumper;

use strict;
use warnings;
use Log::Log4perl qw(get_logger);
use Time::HiRes qw( gettimeofday );
use Module::Load;

use perfSONAR_PS::Common;
use perfSONAR_PS::DB::File;
use perfSONAR_PS::DB::Alarms;
use perfSONAR_PS::Utils::TL1::OME;
use perfSONAR_PS::Utils::TL1::HDXc;
use perfSONAR_PS::Utils::TL1::Ciena;
use perfSONAR_PS::Utils::TL1::Cisco;
use perfSONAR_PS::Utils::TL1::Infinera;
use perfSONAR_PS::Utils::TL1::Fujitsu;
use perfSONAR_PS::Utils::TL1::Alcatel;
use Digest::MD5  qw(md5_hex);

use base 'perfSONAR_PS::Collectors::Base';

use fields 'DB_CLIENT', 'ROUTERS', 'PREV_CONNECT_FAILED';

our $VERSION = 0.09;

sub init {
    my ($self) = @_;
    $self->{LOGGER} = get_logger("perfSONAR_PS::Collectors::Alarms");

    use Data::Dumper;

    print "CONF: ".Dumper($self->{CONF});

    if (not $self->{CONF}->{"routers_file"}) {
        $self->{LOGGER}->error("No routers file in configuration");
        return -1;
    }

    my $file = $self->{CONF}->{"routers_file"};
    if (defined $self->{DIRECTORY}) {
        if (!($file =~ "^/")) {
            $file = $self->{DIRECTORY}."/".$file;
        }
    }

    if ($self->parseRoutersFile($file) != 0) {
        $self->{LOGGER}->error("couldn't load counters to record");
        return -1;
    }

    if (defined $self->{CONF}->{"ma_type"}) {
        if (lc($self->{CONF}->{"ma_type"}) eq "sqlite") {
            if (not defined $self->{CONF}->{"ma_file"} or $self->{CONF}->{"ma_file"} eq "") {
                $self->{LOGGER}->error("You specified a SQLite Database, but then did not specify a database file(ma_file)");
                return -1;
            }

            my $file = $self->{CONF}->{"ma_file"};
            if (defined $self->{DIRECTORY}) {
                if (!($file =~ "^/")) {
                    $file = $self->{DIRECTORY}."/".$file;
                }
            }

            $self->{DB_CLIENT} = perfSONAR_PS::DB::Alarms->new("DBI:SQLite:dbname=".$file);
        }
    } else {
        $self->{LOGGER}->error("Need to specify a location to store the status reports");
        return -1;
    }

    my ($status, $res) = $self->{DB_CLIENT}->open();
    if ($status != 0) {
        my $msg = "Couldn't open newly created client: $res";
        $self->{LOGGER}->error($msg);
        return -1;
    }

    $self->{DB_CLIENT}->close();

    $self->{PREV_CONNECT_FAILED} = {};

    return 0;
}

sub parseRoutersFile {
    my($self, $file) = @_;
    my $routers_config;

    $self->{LOGGER}->debug("Reading $file");

    my $filedb = perfSONAR_PS::DB::File->new( { file => $file } );
    $filedb->openDB;
    $routers_config = $filedb->getDOM();

    my @routers = ();

    foreach my $router ($routers_config->getElementsByTagName("router")) {
        my ($status, $res) = $self->parseRouter($router);
        if ($status != 0) {
            my $msg = "Failure parsing element: $res";
            $self->{LOGGER}->error($msg);
            return -1;
        }

        push @routers, $res;
    }

    $self->{ROUTERS} = \@routers;

    return 0;
}

sub parseRouter {
    my ($self, $router_desc) = @_;

    my @counters = ();

    my $type = $router_desc->findvalue("./type");
    if (not $type) {
        my $msg = "Switch does not have a 'type' field";
        $self->{LOGGER}->error($msg);
        return (-1, $msg);
    }

    my $username = $router_desc->findvalue('username');
    my $password = $router_desc->findvalue('password');
    my $address = $router_desc->findvalue('address');
    my $port = $router_desc->findvalue('port');

    my $name = $router_desc->findvalue('name');

    unless ($address and $username and $password and $name) {
        my $msg = "Router is missing elements needed to access the host. Required: type, address, port, username, password, name";
        $self->{LOGGER}->error($msg);
        return (-1, $msg);
    }

    my %metadata = ();
    $metadata{"name"} = $name;
    $metadata{"address"} = $address;

    my $new_agent;

    if ($type eq "ome") {
        $new_agent = perfSONAR_PS::Utils::TL1::OME->new();
    } elsif ($type eq "ciena") {
        $new_agent = perfSONAR_PS::Utils::TL1::Ciena->new();
    } elsif ($type eq "cisco") {
        $new_agent = perfSONAR_PS::Utils::TL1::Cisco->new();
    } elsif ($type eq "infinera") {
        $new_agent = perfSONAR_PS::Utils::TL1::Infinera->new();
    } elsif ($type eq "fujitsu") {
        $new_agent = perfSONAR_PS::Utils::TL1::Fujitsu->new();
    } elsif ($type eq "alcatel") {
        $new_agent = perfSONAR_PS::Utils::TL1::Alcatel->new();
    } else {
        my $msg = "Router has unknown type, $type, must be either 'ome', 'cisco' or 'ciena'";
        $self->{LOGGER}->error($msg);
        return (-1, $msg);
    }

    my $res = $new_agent->initialize({
                        address => $address,
                        port => $port,
                        username => $username,
                        password => $password,
                        cache_time => 30,
                   });
    if ($res != 0) {
        # XXX Error
    }

    my %router = ();

    $router{"METADATA"} = \%metadata;
    $router{"AGENT"} = $new_agent;

    return (0, \%router);
}

sub collectMeasurements {
    my($self, $sleeptime) = @_;
    my ($status, $res);

    my $next_runtime = time + $self->{CONF}->{"collection_interval"};

    $self->{LOGGER}->info("Collecting alarms");

    ($status, $res) = $self->{DB_CLIENT}->open();
    if ($status != 0) {
        my $msg = "Couldn't open connection to database: $res";
        $self->{LOGGER}->error($msg);
        return (-1, $msg);
    }

    ($status, $res) = $self->{DB_CLIENT}->getMetadata();
    if ($status != 0) {
        my $msg = "Couldn't load list of metadata: $res";
        $self->{LOGGER}->error($msg);
        return (-1, $msg);
    }

    my %metadata_ids = ();
    foreach my $md (@$res) {
        $metadata_ids{$md->{name}} = $md->{id};
    }

    foreach my $router (@{$self->{ROUTERS}}) {
        $self->{LOGGER}->info("Current router: ".$router->{METADATA}->{name});

        my $metadata_id = $metadata_ids{$router->{METADATA}->{name}};

        unless ($metadata_id) {
            ($status, $res) = $self->{DB_CLIENT}->addMetadata({ name => $router->{METADATA}->{name}, address => $router->{METADATA}->{address} });
            if ($status != 0) {
                my $msg = "Couldn't add information for host ".$router->{METADATA}->{name}.": ".$res;
                $self->{LOGGER}->error($msg);
                next;
            }

            $metadata_id = $res;
        }

        $self->{LOGGER}->debug("Metadata ID: $metadata_id\n");

        my $localTime = time;
        my $machineTime;
        if ($router->{AGENT}->connect() == 0) {
            $self->{LOGGER}->debug("Calling get_alarms");
            ($status, $res) = $router->{AGENT}->get_alarms();
            $router->{AGENT}->disconnect();
            $machineTime = $router->{AGENT}->getMachineTime();
        }
        else {
            $self->{LOGGER}->debug("Couldn't connect");
            $status = -1;
            $res = "Problem connecting to host";
        }

        my $alarms;

        if ($status == 0) {
            $alarms = $res;

            $self->{PREV_CONNECT_FAILED}->{$metadata_id} = undef;
        }
        else {
            $self->{LOGGER}->debug("Get alarms returned junk");
            # Generate a measurement alarm

            my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
            $mon++;
            $year += 1900;

            $machineTime = "$year-$mon-$mday $hour:$min:$sec";

            if ($self->{PREV_CONNECT_FAILED}->{$metadata_id}) {
                $alarms = [ $self->{PREV_CONNECT_FAILED}->{$metadata_id} ];
            }
            else {
                my %alarm = ();
                $alarm{alarmType} = "MEASUREMENT-CONNECTFAILED";
                $alarm{serviceAffecting} = "NSA";
                $alarm{description} = "Measurement Software Couldn't Connect To Device";
                $alarm{facility} = "pS-Alarms-Collector";
                $alarm{facility_type} = "perfSONAR";
                $alarm{severity} = 'CR';
                $alarm{time} = $hour."-".$min."-".$sec;
                $alarm{date} = $mon."-".$mday;
                $alarm{year} = $year;

                $alarms = [ \%alarm ];

                $self->{PREV_CONNECT_FAILED}->{$metadata_id} = \%alarm;
            }
        }

        # No alarms, add the 'MEASUREMENT-NOALARMS' Alarm...
        if (scalar(@$alarms) == 0) {
            $self->{LOGGER}->debug("Get alarms returned no alarms");
           
            my ($switch_date, $switch_time) = split(' ', $machineTime);

            my ($switch_year, $switch_month, $switch_day) = split('-', $switch_date);
            my ($switch_hour, $switch_minute, $switch_second) = split(':', $switch_time);

            my %alarm = ();
            $alarm{alarmType} = "MEASUREMENT-NOALARMS";
            $alarm{serviceAffecting} = "NSA";
            $alarm{description} = "Measurement Software Found No Alarms";
            $alarm{facility} = "pS-Alarms-Collector";
            $alarm{facility_type} = "perfSONAR";
            $alarm{severity} = 'MN';
            $alarm{time} = $switch_hour."-".$switch_minute."-".$switch_second;
            $alarm{date} = $switch_month."-".$switch_day;
            $alarm{year} = $switch_year;

            $alarms = [ \%alarm ];
        }

        foreach my $alarm (@$alarms) {
            my $alarmId;

            # Correct some differences between the various TL1 dialects

            # Generate an alarm id if one doesn't already exist
            if (not $alarm->{alarmId}) {
                my $tmp = "";
                foreach my $key (sort keys %{ $alarm }) {
                    $tmp .= $alarm->{$key};
                }
                $alarm->{alarmId} = md5_hex($tmp);
            }

            # If no 'year' element, guess the year
            if (not $alarm->{year}) {
                # guess the year of the interval based on the current machine time
                my ($month, $day) = split('-', $alarm->{date});
                my ($hour, $minute) = split('-', $alarm->{time});
                my ($switch_date, $switch_time) = split(' ', $machineTime);

                my ($switch_year, $switch_month, $switch_day) = split('-', $switch_date);
                my ($switch_hour, $switch_minute, $switch_second) = split(':', $switch_time);

                my $year;

                if ($switch_month eq $month) {
                    $year = $switch_year;
                } elsif ($switch_month ne $month) {
                    if ($switch_month == 1) {
                        $year = $switch_year - 1;
                    } else {
                        $year = $switch_year;
                    }
                }

                $alarm->{year} = $year;
            }

            my $serviceAffecting;
            if ($alarm->{serviceAffecting} eq "SA") {
                $serviceAffecting = "true";
            } else {
                $serviceAffecting = "false";
            }

            # Calculate the difference between the local measurement time and the machine time
            my ($router_date, $router_time) = split(' ', $machineTime);

            my ($router_year, $router_month, $router_day) = split('-', $router_date);
            my ($router_hour, $router_minute, $router_second) = split(':', $router_time);

            my $currentMachineTimestamp = POSIX::mktime($router_second, $router_minute, $router_hour, $router_day, $router_month - 1, $router_year - 1900);

            my $diff = $localTime - $currentMachineTimestamp;

            print STDERR "currentMachineTimestamp: $currentMachineTimestamp ($router_year/$router_month/$router_day $router_hour:$router_minute:$router_second)\n";
            print STDERR "LocalTime: $localTime\n";
            print STDERR "Diff: $diff\n";

            # Convert the start time to a timestamp and use the diff to calculate the 'local' start time
            my $machine_start_year = $alarm->{year};
            my ($machine_start_month, $machine_start_day) = split('-', $alarm->{date});
            my ($machine_start_hour, $machine_start_minute, $machine_start_second) = split('-', $alarm->{time});

            my $startMachineTimestamp = POSIX::mktime($machine_start_second, $machine_start_minute, $machine_start_hour, $machine_start_day, $machine_start_month - 1, $machine_start_year - 1900);
            my $startLocalTimestamp = $startMachineTimestamp + $diff;

            ($status, $res) = $self->{DB_CLIENT}->addAlarm({
                                                                metadataId => $metadata_id,
                                                                facility => $alarm->{facility},
                                                                severity => $alarm->{severity},
                                                                type => $alarm->{alarmType},
                                                                alarmId => $alarm->{alarmId},
                                                                description => $alarm->{description},
                                                                serviceAffecting => $serviceAffecting,
                                                                measuredStartTime => $startLocalTimestamp,
                                                                machineStartTime => $startMachineTimestamp,
                                                                observationTime => $localTime,
                                                            });
            if ($status != 0) {
                $self->{LOGGER}->error("Couldn't add alarm ".$alarm->{alarmId});
                next;
            }
        }
    }

    ($status, $res) = $self->{DB_CLIENT}->close();
    if ($status != 0) {
        my $msg = "Couldn't close connection to database: $res";
        $self->{LOGGER}->error($msg);
    }

    if ($sleeptime) {
        $$sleeptime = $next_runtime - time;

        $$sleeptime = 0 if ($$sleeptime <= 0);
    }

    return;
}

1;

__END__

=head1 NAME

perfSONAR_PS::Collectors::Alarms - A module that will collect router alarm
information and store the results into a Measurement Archive.

=head1 DESCRIPTION

This module loads a set of links and can be used to collect status information
on those links and store the results into a Link Status MA.

=head1 SYNOPSIS

=head1 DETAILS

This module is meant to be used to periodically collect information about Link
Status. It can do this by running scripts or consulting SNMP servers directly.
It reads a configuration file that contains the set of links to track. It can
then be used to periodically obtain the status and then store the results into
a measurement archive. 

It includes a submodule SNMPAgent that provides a caching SNMP poller allowing
easier interaction with SNMP servers.

=head1 API

=head2 init($self)
    This function initializes the collector. It returns 0 on success and -1
    on failure.

=head2 collectMeasurements($self)
    This function is called by external users to collect and store the
    status for all links.

=head1 SEE ALSO

To join the 'perfSONAR-PS' mailing list, please visit:

https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

https://svn.internet2.edu/svn/perfSONAR-PS

Questions and comments can be directed to the author, or the mailing list.

=head1 VERSION

$Id:$

=head1 AUTHOR

Aaron Brown, E<lt>aaron@internet2.eduE<gt>, Jason Zurawski, E<lt>zurawski@internet2.eduE<gt>

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework along
with this software.  If not, see <http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2004-2007, Internet2 and the University of Delaware

All rights reserved.

=cut

# vim: expandtab shiftwidth=4 tabstop=4
