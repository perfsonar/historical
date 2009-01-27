package perfSONAR_PS::Utils::TL1::HDXc;

use warnings;
use strict;

use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);
use Data::Dumper;

use base 'perfSONAR_PS::Utils::TL1::Base';
use fields 'CRSSBYNAME', 'ETHSBYAID', 'OCNSBYAID', 'OCNSBYNAME', 'SECTSBYAID', 'LINESBYAID', 'LINESBYNAME', 'SECT_PMS', 'LINE_PMS', 'READ_CRS', 'READ_ETH', 'READ_OCN', 'READ_SECT', 'READ_LINE', 'READ_SECT_PM', 'READ_LINE_PM', 'READ_ALARMS', 'ALARMS';

sub initialize {
    my ($self, @params) = @_;

    my $parameters = validate(@params,
            {
            address => 1,
            port => 1,
            username => 1,
            password => 1,
            cache_time => 1,
            prompt => 0,
            });

    $parameters->{"type"} = "hdxc";
    $parameters->{"logger"} = get_logger("perfSONAR_PS::Collectors::LinkStatus::Agent::TL1::HDXc");
    $parameters->{"prompt"} = ";" if (not $parameters->{prompt});
    $parameters->{"port"} = "23" if (not $parameters->{port});

    $self->{READ_LINE_PM} = ();
    $self->{READ_SECT_PM} = ();

    return $self->SUPER::initialize($parameters);
}

sub getVCG {
    my ($self, $name) = @_;

    return;
}

sub getSNC {
    my ($self, $name) = @_;

    return;
}

sub getETH {
    my ($self, $aid) = @_;

    return;
}

sub getOCN {
    my ($self, $aid) = @_;
    my $do_reload_stats = 0;

    if (not $self->{READ_OCN}) {
        $do_reload_stats = 1;
        $self->{READ_OCN} = 1;
    }

    if ($self->{CACHE_TIME} + $self->{CACHE_DURATION} < time or $do_reload_stats) {
        $self->readStats();
    }

    if (not defined $aid) {
        return $self->{OCNSBYAID};
    }

    return $self->{OCNSBYAID}->{$aid};
}

sub getOCH {
    return;
}

sub getGTP {
    my ($self, $name) = @_;

    return;
}

sub getSect {

    my ($self, $aid) = @_;
    my $do_reload_stats = 0;

    if (not $self->{READ_SECT}) {
        $do_reload_stats = 1;
        $self->{READ_SECT} = 1;
    }

    if ($self->{CACHE_TIME} + $self->{CACHE_DURATION} < time or $do_reload_stats) {
        $self->readStats();
    }

    if (not $aid) {
        return $self->{SECTSBYAID};
    } else {
        return $self->{SECTSBYAID}->{$aid};
    }
}

sub getLineByName {
    my ($self, $name) = @_;
    my $do_reload_stats = 0;

    if (not $self->{READ_LINE}) {
        $do_reload_stats = 1;
        $self->{READ_LINE} = 1;
    }

    if ($self->{CACHE_TIME} + $self->{CACHE_DURATION} < time or $do_reload_stats) {
        $self->readStats();
    }

    if (not $name) {
        return $self->{LINESBYNAME};
    } else {
        return $self->{LINESBYNAME}->{$name};
    }
}

sub getLine {
    my ($self, $aid) = @_;
    my $do_reload_stats = 0;

    if (not $self->{READ_LINE}) {
        $do_reload_stats = 1;
        $self->{READ_LINE} = 1;
    }

    if ($self->{CACHE_TIME} + $self->{CACHE_DURATION} < time or $do_reload_stats) {
        $self->readStats();
    }

    if (not $aid) {
        return $self->{LINESBYAID};
    } else {
        $self->{LOGGER}->debug("Reading information on aid '$aid': ".$self->{LINESBYAID}->{$aid}." -- ".Dumper($self->{LINESBYAID}));
        return $self->{LINESBYAID}->{$aid};
    }
}

sub getCrossconnect {
    my ($self, $name) = @_;
    my $do_reload_stats = 0;

    if (not $self->{READ_CRS}) {
        $do_reload_stats = 1;
        $self->{READ_CRS} = 1;
    }

    if ($self->{CACHE_TIME} + $self->{CACHE_DURATION} < time or $do_reload_stats) {
        $self->readStats();
    }

    if (not defined $name) {
        return $self->{CRSSBYNAME};
    }

    return $self->{CRSSBYNAME}->{$name};
}

sub getETH_PM {
    my ($self, $aid, $type) = @_;

    return;
}

sub getSTS_PM {
    my ($self, $aid, $type) = @_;

    return;
}

sub getOCN_PM {
    my ($self, $aid, $type) = @_;

    return;
}

sub getLine_PM {
    my $self = shift;
    my %args = @_;
    my $do_reload_stats = 0;

    my $index = $args{'index'};
    my $name = $args{'variable_name'};
    my $aid= $args{'aid'};

    if (not $index) {
        $index = 0;
    }

    if (not $self->{READ_LINE_PM}->{$index}) {
        $do_reload_stats = 1;
        $self->{READ_LINE_PM}->{$index} = 1;
    }

    if ($self->{CACHE_TIME} + $self->{CACHE_DURATION} < time or $do_reload_stats) {
        $self->readStats();
    }

    if (not $aid) {
        return $self->{LINE_PMS}->{$index};
    }

    if (not $name) {
        return $self->{LINE_PMS}->{$index}->{$aid};
    }

    return $self->{LINE_PMS}->{$index}->{$aid}->{$name};
}

sub getSect_PM {
    my $self = shift;
    my %args = @_;
    my $do_reload_stats = 0;

    my $index = $args{'index'};
    my $name = $args{'variable_name'};
    my $aid= $args{'aid'};

    if (not $index) {
        $index = 0;
    }

    if (not $self->{READ_SECT_PM}->{$index}) {
        $do_reload_stats = 1;
        $self->{READ_SECT_PM}->{$index} = 1;
    }

    if ($self->{CACHE_TIME} + $self->{CACHE_DURATION} < time or $do_reload_stats) {
        $self->readStats();
    }

    if (not $aid) {
        return $self->{SECT_PMS}->{$index};
    }

    if (not $name) {
        return $self->{SECT_PMS}->{$index}->{$aid};
    }

    return $self->{SECT_PMS}->{$index}->{$aid}->{$name};
}

sub getAlarms {
    my ($self) = shift;
    my %args = @_;

    my $do_reload_stats = 0;

    if (not $self->{READ_ALARMS}) {
        $do_reload_stats = 1;
        $self->{READ_ALARMS} = 1;
    }

    if ($self->{CACHE_TIME} + $self->{CACHE_DURATION} < time or $do_reload_stats) {
        $self->readStats();
    }

    if (not $self->{ALARMS}) {
        return undef;
    }

    my @ret_alarms = ();

    foreach my $alarm (@{ $self->{ALARMS} }) {
        my $matches = 1;
        foreach my $key (keys %args) {
            if ($alarm->{$key}) {
                if ($alarm->{$key} ne $args{$key}) {
                    $matches = 1;
                }
            }
        }

        if ($matches) {
            push @ret_alarms, $alarm;
        }
    }

    return \@ret_alarms;
}

sub readStats {
    my ($self) = @_;

    $self->connect();
    $self->login();

    if ($self->{READ_CRS}) {
        $self->readCRSs();
    }

    if ($self->{READ_OCN}) {
        $self->readOCNs();
    }

    if ($self->{READ_SECT}) {
        $self->readSECTs();
    }

    if ($self->{READ_SECT_PM}) {
        foreach my $index (keys %{ $self->{READ_SECT_PM} }) {
            $self->readSect_PM($index);
        }
    }

    if ($self->{READ_LINE}) {
        $self->readLINEs();
    }

    if ($self->{READ_LINE_PM}) {
        foreach my $index (keys %{ $self->{READ_LINE_PM} }) {
            $self->readLine_PM($index);
        }
    }

    if ($self->{READ_ALARMS}) {
        $self->readAlarms();
    }

    $self->{CACHE_TIME} = time;
    $self->disconnect();

    return;
}

sub readSECTs {
    my ($self) = @_;

    my %sects = ();

    my ($successStatus, $results) = $self->send_cmd("RTRV-SECT:::".$self->{CTAG}.";");

    $self->{LOGGER}->debug("got SECT lines\n");

    foreach my $line (@$results) {
        $self->{LOGGER}->debug($line."\n");

        if ($line =~ /(\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)/) {
            $self->setMachineTime("$1-$2-$3 $4:$5:$6");
            next;
        }


        if ($line =~ /"([^:]*):[^:]*:[^:]*:([A-Z]*),([A-Z]*)"/) {
            my ($aid, $name, $pst, $sst);

            $aid = $1;
            $pst = $2;
            $sst = $3;

            my %status = ( sst => $sst, pst => $pst );

            $sects{$aid} = \%status;
        }
    }

    $self->{SECTSBYAID} = \%sects;

    return;
}

sub readLINEs {
    my ($self) = @_;

    my %lines = ();
    my %lines_name = ();

    my $stime = time;

    $self->{LOGGER}->debug("Sending readLin: ".$stime."\n");

    my ($successStatus, $results) = $self->send_cmd("RTRV-LINE:::".$self->{CTAG}.";");

    my $etime = time;

    $self->{LOGGER}->debug("Return from readLin: ".$etime." -- ".($etime-$stime)."\n");

    $self->{LOGGER}->debug("got LINE lines\n");

    foreach my $line (@$results) {
        $self->{LOGGER}->debug($line."\n");

        $self->{LOGGER}->debug("Received line: ".$line);
        if ($line =~ /(\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)/) {
            $self->setMachineTime("$1-$2-$3 $4:$5:$6");
            next;
        }


        if ($line =~ /"([^:]*):.*:.*LABEL=\\"([^\\]*)\\".*:([A-Z]*)"/) {
            my ($aid, $name, $pst, $sst);

            $aid = $1;
            $name = $2;
            $pst = $3;

            my %status = ( sst => $sst, pst => $pst );

            $lines{$aid} = \%status;
            if ($name) {
                $lines_name{$name} = \%status;
            }
        }
    }

    $self->{LINESBYAID} = \%lines;
    $self->{LINESBYNAME} = \%lines_name;

    return;
}

sub readOCNs {
    my ($self) = @_;

    my %ocns = ();
    my %ocns_name = ();

    foreach my $i (3, 12, 48, 192) {
        my ($successStatus, $results) = $self->send_cmd("RTRV-OC".$i.":::".$self->{CTAG}.";");

        $self->{LOGGER}->debug("got OC$i lines\n");

        foreach my $line (@$results) {
            $self->{LOGGER}->debug($line."\n");

            if ($line =~ /(\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)/) {
                $self->setMachineTime("$1-$2-$3 $4:$5:$6");
                next;
            }

            if ($line =~ /"(OC$i[^:]*)/) {
                my ($aid, $name, $pst, $sst);

                $aid = $1;

                if ($line =~ /LABEL=\\"([^\\]*)\\"/) {
                    $name = $1;
                    $self->{LOGGER}->debug("Found name: $name\n");
                }

                if ($line =~ /.*:([A-Z]*),([A-Z]*)"/) {
                    $pst = $1;
                    $sst = $2;
                }

                my %status = ( sst => $sst, pst => $pst );

                $ocns{$aid} = \%status;
                $ocns_name{$name} = \%status;
            }
        }
    }

    $self->{OCNSBYAID} = \%ocns;
    $self->{OCNSBYNAME} = \%ocns_name;

    return;
}

sub readCRSs {
    my ($self) = @_;

    my %crss = ();

    my ($successStatus, $results) = $self->send_cmd("RTRV-CRS-ALL:::".$self->{CTAG}.";");

    $self->{LOGGER}->debug("got CRS lines\n");

    foreach my $line (@$results) {
        $self->{LOGGER}->debug($line."\n");

        if ($line =~ /(\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)/) {
            $self->setMachineTime("$1-$2-$3 $4:$5:$6");
            next;
        }

        if ($line =~ /LABEL=\\"([^\\]*)\\"/) {
            my ($pst, $sst, $name);
            $name = $1;

            if ($line =~ /AST=([^,]*)/) {
                $pst = $1;
            }
            if ($line =~ /\".*:.*:.*:(.*)"/) {
                $sst = $1;
                if ($sst eq "") {
                    $sst = "ACTIVE";
                }
            }

            my %status = ( pst => $pst, sst => $sst );

            $crss{$name} = \%status;
        }
    }

    $self->{CRSSBYNAME} = \%crss;

    return;
}

sub readLine_PM {
    my ($self, $index) = @_;

    my %pms = ();

    my $results;

    my $stime = time;

    $self->{LOGGER}->debug("Sending readLin_PM: ".$stime."\n");

    if ($index) {
        (my $successStatus, $results) = $self->send_cmd("RTRV-PM-LINE:::".$self->{CTAG}."::ALL-L:INDEX=$index;");
    } else {
        (my $successStatus, $results) = $self->send_cmd("RTRV-PM-LINE:::".$self->{CTAG}."::ALL-L:;");
    }

    my $etime = time;

    $self->{LOGGER}->debug("Return from readLin_PM: ".$etime." -- ".($etime-$stime)."\n");

    $self->{LOGGER}->debug("got LINE_PM lines\n");

    foreach my $line (@$results) {

        $self->{LOGGER}->debug("LINE: $line");

        if ($line =~ /(\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)/) {
            $self->setMachineTime("$1-$2-$3 $4:$5:$6");
            next;
        }

        if ($line =~ /"([^:]*):([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^"]*)"/) {
            my $aid = $1;
            my $pm_type = $2;
            my $pm_value = $3;
            my $validity = $4;
            my $location = $5;
            my $direction = $6;
            my $time_period = $7;
            my $monitoring_date = $8;
            my $monitoring_time = $9;

            my %pm = (
                aid => $aid,
                aid_type => "line",
                type => $pm_type,
                value => $pm_value,
                validity => $validity,
                location => $location,
                direction => $direction,
                time_period => $time_period,
                monitoring_date => $monitoring_date,
                monitoring_time => $monitoring_time,
            );

            $pms{$aid}->{$pm_type} = \%pm;
        }
    }

    $self->{LINE_PMS}->{$index} = \%pms;
}

sub readSect_PM {
    my ($self, $index) = @_;
    my %pms = ();

    my $results;

    if ($index) {
        (my $successStatus, $results) = $self->send_cmd("RTRV-PM-SECT:::".$self->{CTAG}."::ALL-S:INDEX=$index;");
    } else {
        (my $successStatus, $results) = $self->send_cmd("RTRV-PM-SECT:::".$self->{CTAG}."::ALL-S:;");
    }

    $self->{LOGGER}->debug("got SECT_PM lines\n");

    foreach my $line (@$results) {
        $self->{LOGGER}->debug($line."\n");

#        "OC192S-1-501-2-1:SEFS-S,505,PRTL,NEND,RCV,15-MIN,06-16,14-15"
        if ($line =~ /(\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)/) {
            $self->setMachineTime("$1-$2-$3 $4:$5:$6");
            next;
        }

        if ($line =~ /"([^:]*):([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^"]*)"/) {
            my $aid = $1;
            my $pm_type = $2;
            my $pm_value = $3;
            my $validity = $4;
            my $location = $5;
            my $direction = $6;
            my $time_period = $7;
            my $monitoring_date = $8;
            my $monitoring_time = $9;

            my %pm = (
                aid => $aid,
                aid_type => "sect",
                type => $pm_type,
                value => $pm_value,
                validity => $validity,
                location => $location,
                direction => $direction,
                time_period => $time_period,
                monitoring_date => $monitoring_date,
                monitoring_time => $monitoring_time,
            );

            $pms{$aid}->{$pm_type} = \%pm;
        }
    }

    $self->{SECT_PMS}->{$index} = \%pms;
}

sub readAlarms {
    my ($self) = @_;

    my @alarms = ();

    my ($successStatus, $results) = $self->send_cmd("RTRV-ALM-ALL:::".$self->{CTAG}."::;");

    $self->{LOGGER}->debug("Got ALM line\n");    

    foreach my $line (@$results) {
        $self->{LOGGER}->debug("LINE: ".$line."\n");

#       "OC192-1-5-1,OC192:OPR-OCH,-3.06,PRTL,NEND,RCV,15-MIN,06-16,15-15,0"
        if ($line =~ /(\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)/) {
            $self->setMachineTime("$1-$2-$3 $4:$5:$6");
            next;
        }

#   "ETH10G-1-10-4,ETH10G:CR,LOS,SA,01-07,07-34-55,NEND,RCV:\"Loss Of Signal\",NONE:0100000295-0008-0673,:YEAR=2006,MODE=NONE"

        if ($line =~ /"([^,]*),([^:]*):([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^:]*):([^,]*),([^:]*):([^,]*),([^:]*):YEAR=([^,]*),MODE=([^"]*)"/) {
            $self->{LOGGER}->debug("Found a good line\n");

            my $facility = $1;
            my $facility_type = $2;
            my $severity = $3;
            my $alarmType = $4;
            my $serviceAffecting = $5;
            my $date = $6;
            my $time = $7;
            my $location = $8;
            my $direction = $9;
            my $description = $10;
            my $something1 = $11;
            my $alarmId = $12;
            my $something2 = $13;
            my $year = $14;
            my $mode = $15;

            $self->{LOGGER}->debug("DESCRIPTION: '$description'\n");
            $description =~ s/\\"//g;
            $self->{LOGGER}->debug("DESCRIPTION: '$description'\n");

            my %alarm = (
                facility => $facility,
                facility_type => $facility_type,
                severity => $severity,
                alarmType => $alarmType,
                description => $description,
                serviceAffecting => $serviceAffecting,
                date => $date,
                time => $time,
                location => $location,
                direction => $direction,
                alarmId => $alarmId,
                year => $year,
                mode => $mode,
            );

            push @alarms, \%alarm;
        }
    }

    $self->{ALARMS} = \@alarms;
}

sub login {
    my ($self) = @_;

    my ($status, $lines) = $self->send_cmd("ACT-USER::".$self->{USERNAME}.":".$self->{CTAG}."::".$self->{PASSWORD}.";");

    if ($status != 1) {
        return -1;
    }

    $self->send_cmd("INH-MSG-ALL:::".$self->{CTAG}.";");

    return 0;
}

1;

# vim: expandtab shiftwidth=4 tabstop=4
