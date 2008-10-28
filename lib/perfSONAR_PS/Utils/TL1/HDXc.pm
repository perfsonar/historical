package perfSONAR_PS::Utils::TL1::HDXc;

use warnings;
use strict;

use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);
use Data::Dumper;

use base 'perfSONAR_PS::Utils::TL1::Base';
use fields 'CRSSBYNAME', 'ETHSBYAID', 'OCNSBYAID', 'OCNSBYNAME', 'SECTSBYAID', 'LINESBYAID', 'LINESBYNAME', 'SECT_PMS', 'LINE_PMS', 'READ_CRS', 'READ_ETH', 'READ_OCN', 'READ_SECT', 'READ_LINE', 'READ_SECT_PM', 'READ_LINE_PM';

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
        $self->{LOGGER}->info("Reading information on aid '$aid': ".$self->{LINESBYAID}->{$aid}." -- ".Dumper($self->{LINESBYAID}));
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

    $self->{CACHE_TIME} = time;
    $self->disconnect();

    return;
}

sub readSECTs {
    my ($self) = @_;

    my %sects = ();

    my ($successStatus, $results) = $self->send_cmd("RTRV-SECT:::".$self->{CTAG}.";");

    print "got SECT lines\n";

    foreach my $line (@$results) {
        print $line."\n";

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

    $self->{LOGGER}->info("Sending readLin: ".$stime."\n");

    my ($successStatus, $results) = $self->send_cmd("RTRV-LINE:::".$self->{CTAG}.";");

    my $etime = time;

    $self->{LOGGER}->info("Return from readLin: ".$etime." -- ".($etime-$stime)."\n");

    print "got LINE lines\n";

    foreach my $line (@$results) {
        print $line."\n";

        $self->{LOGGER}->info("Received line: ".$line);
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

        print "got OC$i lines\n";

        foreach my $line (@$results) {
            print $line."\n";

            if ($line =~ /(\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)/) {
                $self->setMachineTime("$1-$2-$3 $4:$5:$6");
                next;
            }

            if ($line =~ /"(OC$i[^:]*)/) {
                my ($aid, $name, $pst, $sst);

                $aid = $1;

                if ($line =~ /LABEL=\\"([^\\]*)\\"/) {
                    $name = $1;
                    print "Found name: $name\n";
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

    print "got CRS lines\n";

    foreach my $line (@$results) {
        print $line."\n";

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

    $self->{LOGGER}->info("Sending readLin_PM: ".$stime."\n");

    if ($index) {
        (my $successStatus, $results) = $self->send_cmd("RTRV-PM-LINE:::".$self->{CTAG}."::ALL-L:INDEX=$index;");
    } else {
        (my $successStatus, $results) = $self->send_cmd("RTRV-PM-LINE:::".$self->{CTAG}."::ALL-L:;");
    }

    my $etime = time;

    $self->{LOGGER}->info("Return from readLin_PM: ".$etime." -- ".($etime-$stime)."\n");

    print "got LINE_PM lines\n";

    foreach my $line (@$results) {

        print "LINE: $line";

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

    print "got SECT_PM lines\n";

    foreach my $line (@$results) {
        print $line."\n";

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

sub login {
    my ($self) = @_;

    my ($status, $lines) = $self->send_cmd("ACT-USER::".$self->{USERNAME}.":".$self->{CTAG}."::".$self->{PASSWORD}.";");

    if ($status != 1) {
        return -1;
    }

    return 0;
}

1;

# vim: expandtab shiftwidth=4 tabstop=4
