package perfSONAR_PS::Utils::TL1::CoreDirector;

use warnings;
use strict;

use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);
use perfSONAR_PS::Utils::ParameterValidation;
use Data::Dumper;

use base 'perfSONAR_PS::Utils::TL1::Base';
use fields 'ALARMS', 'COUNTERS', 'EFLOWSBYNAME', 'CRSSBYNAME', 'ETHSBYAID', 'GTPSBYNAME', 'OCNSBYAID', 'SNCSBYNAME', 'VCGSBYNAME', 'STSSBYNAME',
            'ALARMS_CACHE_TIME', 'EFLOWSBYNAME_CACHE_TIME', 'CRSSBYNAME_CACHE_TIME', 'ETHSBYAID_CACHE_TIME', 'GTPSBYNAME_CACHE_TIME', 'OCNSBYAID_CACHE_TIME', 'SNCSBYNAME_CACHE_TIME', 'VCGSBYNAME_CACHE_TIME', 'STSSBYNAME_CACHE_TIME';

sub initialize {
    my ($self, @params) = @_;

    my $parameters = validate(@params,
            {
            address => 1,
            port => 0,
            username => 1,
            password => 1,
            cache_time => 1,
            });

    $parameters->{"type"} = "coredirector";
    $parameters->{"logger"} = get_logger("perfSONAR_PS::Collectors::LinkStatus::Agent::TL1::CoreDirector");
    $parameters->{"prompt"} = ";" if (not $parameters->{"prompt"});
    $parameters->{"port"} = "10201" if (not $parameters->{"port"});

    $self->{ALARMS_CACHE_TIME} = 0;
    $self->{EFLOWSBYNAME_CACHE_TIME} = 0;
    $self->{CRSSBYNAME_CACHE_TIME} = 0;
    $self->{ETHSBYAID_CACHE_TIME} = 0;
    $self->{GTPSBYNAME_CACHE_TIME} = 0;
    $self->{OCNSBYAID_CACHE_TIME} = 0;
    $self->{SNCSBYNAME_CACHE_TIME} = 0;
    $self->{VCGSBYNAME_CACHE_TIME} = 0;
    $self->{STSSBYNAME_CACHE_TIME} = 0;

    return $self->SUPER::initialize($parameters);
}

sub getVCG {
    my ($self, $facility_name) = @_;

    if ($self->{VCGSBYNAME_CACHE_TIME} + $self->{CACHE_DURATION} < time) {
        my %vcgs = ();

        my ($successStatus, $results) = $self->send_cmd("RTRV-VCG::ALL:".$self->{CTAG}.";");

        $self->{LOGGER}->debug("Got VCG Lines\n");

        foreach my $line (@$results) {
            $self->{LOGGER}->debug($line."\n");

#"1-A-3-1:189-190,PST=OOS-AU,SST=[ALM,ACT],ALIAS=nms-oexp2.newy:FPGA2_TO_nms-oexp2.hous:FPGA2,SUPPTTP=1-A-3-1,CRCTYPE=CRC_32,SPICHANNEL=,DEGRADETHRESHOLD=2,CONCATIFTYPE=SONET,STSSIZE=STS1,TUNNELPEERTYPE=ETTP,TUNNELPEERNAME=1-A-3-1-9,MEMBERFAILCRITERIA=DLOM&LOP_P&AIS_P,GFPFCSENABLED=NO,DEFAULTJ1ENABLED=YES,LCASENABLED=NO,LCASHOLDOFFTIMER=1,LCASRSACKTIMER=2,CONFIGMONCHANNEL=1-A-3-1:189-190-CTP-189,ACTUALMONCHANNEL=,SCRAMBLINGBITENABLED=YES,FRAMINGMODE=GFP,GROUPMEM=189&&190,PROVBW=2,OPERBW=0,MAPPERBUFFERALLOCATION=AUTO,MAPPERBUFFERSAVAILABLE=56,MEMBERDETAIL={[1-A-3-1:189-190-CTP-190 190  LCAS_NA 255 NA LCAS_NA 255 NA]&[1-A-3-1:189-190-CTP-189 189  LCAS_NA 255 NA LCAS_NA 255 NA]},EFFIBASESEV=NR,VCGFAILUREBASESEV=NR"

            if ($line =~ /"([^,]*),(.*PST.*)"/) {
                my %vcg = ();

                my @pairs = split(",", $2);
                foreach my $pair (@pairs) {
                    my ($variable, $value) = split("=", $pair);
                    $variable = lc($variable);

                    $vcg{$variable} = $value;
                }

                $vcg{name} = $1;
                $vcgs{$1} = \%vcg;
            }
        }

        $self->{VCGSBYNAME} = \%vcgs;
        $self->{VCGSBYNAME_CACHE_TIME} = time;
    }

    if (not defined $facility_name) {
        return $self->{VCGSBYNAME};
    }

    return $self->{VCGSBYNAME}->{$facility_name};
}

sub getSNC {
    my ($self, $facility_name) = @_;

    if ($self->{SNCSBYNAME_CACHE_TIME} + $self->{CACHE_DURATION} < time) {
        my %sncs = ();

        my ($successStatus, $results) = $self->send_cmd("RTRV-SNC-STSPC::ALL:".$self->{CTAG}.";");

        $self->{LOGGER}->debug("Got SNC Lines\n");

        foreach my $line (@$results) {
            $self->{LOGGER}->debug($line."\n");

            if ($line =~ /"([^,]*),.*[^A-Z]PST=([^,]*).*STATE=([^,]*).*"/) {
                my %status = ( pst => $2, state => $3 );

                $sncs{$1} = \%status;
            }
        }

        $self->{SNCSBYNAME} = \%sncs;
        $self->{SNCSBYNAME_CACHE_TIME} = time;
    }

    if (not defined $facility_name) {
        return $self->{SNCSBYNAME};
    }

    return $self->{SNCSBYNAME}->{$facility_name};
}

sub getSTS {
    my ($self, $facility_name) = @_;

    if ($self->{STSSBYNAME_CACHE_TIME} + $self->{CACHE_DURATION} < time) {
        my %stss = ();

        my ($successStatus, $results) = $self->send_cmd("RTRV-STSPC:::".$self->{CTAG}.";");

        $self->{LOGGER}->debug("Got STSPC Lines\n");

        foreach my $line (@$results) {
            $self->{LOGGER}->debug($line."\n");

            if ($line =~ /"([^,]*),.*[^A-Z]PST=([^,]*),.*SST=([^,]*).*"/) {
                my %status = ( pst => $2, sst => $3 );

                $stss{$1} = \%status;
            }
        }

        $self->{STSSBYNAME} = \%stss;
        $self->{STSSBYNAME_CACHE_TIME} = time;
    }

    if (not defined $facility_name) {
        return $self->{STSSBYNAME};
    }

    return $self->{STSSBYNAME}->{$facility_name};
}

sub getETH {
    my ($self, $facility_name) = @_;

    die("Not yet implemented");
}

sub getOCN {
    my ($self, $facility_name) = @_;

    if ($self->{OCNSBYAID_CACHE_TIME} + $self->{CACHE_DURATION} < time) {
        my %ocns = ();

        my ($successStatus, $results) = $self->send_cmd("RTRV-OCN::ALL:".$self->{CTAG}.";");

        $self->{LOGGER}->debug("Got OCN Lines\n");

        foreach my $line (@$results) {
            $self->{LOGGER}->debug($line."\n");

            if ($line =~ /"([^,]*),.*[^A-Z]PST=([^,]*).*"/) {
                my %status = ( pst => $2 );

                $ocns{$1} = \%status;
            }
        }

        $self->{OCNSBYAID} = \%ocns;
        $self->{OCNSBYAID_CACHE_TIME} = time;
    }

    if (not defined $facility_name) {
        return $self->{OCNSBYAID};
    }

    return $self->{OCNSBYAID}->{$facility_name};
}

sub getEFLOW {
    my ($self, $facility_name) = @_;

    if ($self->{EFLOWSBYNAME_CACHE_TIME} + $self->{CACHE_DURATION} < time) {
        my %eflows = ();

        my ($successStatus, $results) = $self->send_cmd("RTRV-EFLOW::ALL:".$self->{CTAG}.";");

        $self->{LOGGER}->debug("Got EFLOW Lines\n");

        foreach my $line (@$results) {
            $self->{LOGGER}->debug($line."\n");

#      "1-A-3-1-9_1-A-3-1:189-190:INGRESSPORTTYPE=ETTP,INGRESSPORTNAME=1-A-3-1-9,PKTTYPE=ALL,PRIORITY=,EGRESSPORTTYPE=VCG,EGRESSPORTNAME=1-A-3-1:189-190,COSMAPPING=COS_PORT_DEFAULT,ENABLEPOLICING=NO,BWPROFILE=,TAGSTOREMOVE=REMOVE_NONE,TAGSTOADD=ADD_NONE,OUTERTAGTYPE=0x0000,OUTERVLANID=0,SECONDTAGTYPE=0x0000,SECONDVLANID=0,INHERITPRIORITY=NO,NEWPRIORITY=0,COLLECTPM=NO,SYSTEMCREATED=YES"
            if ($line =~ /"(.+?):(([A-Z]+=[^,]*,)+[A-Z]+=[^,]*)"/) {
                my %eflow = ();
                my @pairs = split(",", $2);
                foreach my $pair (@pairs) {
                    my ($variable, $value) = split("=", $pair);

                    $variable = lc($variable);

                    $eflow{$variable} = $value;
                }

                $eflow{name} = $1;
                $eflows{$1} = \%eflow;
            }
        }

        $self->{EFLOWSBYNAME} = \%eflows;
        $self->{EFLOWSBYNAME_CACHE_TIME} = time;
    }

    if (not defined $facility_name) {
        return $self->{EFLOWSBYNAME};
    }

    return $self->{EFLOWSBYNAME}->{$facility_name};
}

sub getGTP {
    my ($self, $facility_name) = @_;

    if ($self->{GTPSBYNAME_CACHE_TIME} + $self->{CACHE_DURATION} < time) {
        my %gtps = ();

        my ($successStatus, $results) = $self->send_cmd("RTRV-GTP::ALL:".$self->{CTAG}.";");

        $self->{LOGGER}->debug("Got GTP Lines\n");

        foreach my $line (@$results) {
            $self->{LOGGER}->debug($line."\n");

            if ($line =~ /"([^,]*),.*[^A-Z]PST=([^,]*),.*SST=([^,]*).*"/) {
                my %status = ( pst => $2, sst => $3 );

                $gtps{$1} = \%status;
            }
        }

        $self->{GTPSBYNAME} = \%gtps;
        $self->{GTPSBYNAME_CACHE_TIME} = time;
    }

    if (not defined $facility_name) {
        return $self->{GTPSBYNAME};
    }

    return $self->{GTPSBYNAME}->{$facility_name};
}

sub getCrossconnect {
    my ($self, $facility_name) = @_;

    if ($self->{CRSSBYNAME_CACHE_TIME} + $self->{CACHE_DURATION} < time) {
        my %crss = ();

        my ($successStatus, $results) = $self->send_cmd("RTRV-CRS:::".$self->{CTAG}.";");

        $self->{LOGGER}->debug("Got CRS Lines\n");

        foreach my $line (@$results) {
            $self->{LOGGER}->debug($line."\n");

            if ($line =~ /NAME=([^,]*)/) {
                my ($pst, $sst, $facility_name);
                $facility_name = $1;

                if ($line =~ /PST=([^,]*)/) {
                    $pst = $1;
                }
                if ($line =~ /SST=([^,]*)/) {
                    $sst = $1;
                }

                my %status = ( pst => $pst, sst => $sst );

                $crss{$facility_name} = \%status;
            }
        }

        $self->{CRSSBYNAME} = \%crss;
        $self->{CRSSBYNAME_CACHE_TIME} = time;
    }

    if (not defined $facility_name) {
        return $self->{CRSSBYNAME};
    }

    return $self->{CRSSBYNAME}->{$facility_name};
}

sub getSTS_PM {
    my ($self, $facility_name, $pm_type) = @_;

    my ($successStatus, $results);
    if (not $facility_name or $facility_name eq "ALL") {
        ($successStatus, $results) = $self->send_cmd("RTRV-PM-STSPC::ALL:".$self->{CTAG}.";");
    } else {
        ($successStatus, $results) = $self->send_cmd("RTRV-PM-STSPC::\"$facility_name\":".$self->{CTAG}.";");
    }

    if ($successStatus == -1) {
        return undef;
    }

    my %pm_results = ();

    foreach my $line (@$results) {
#    "1-A-2-1-157,STSPC:ESP,0,CMPL,NEND,RCV,15-MIN,01-28,21-45"
        if ($line =~ /"([^,]*),STSPC:([^,]*),([^,]*),([^,]*),([^,]),([^,]),([^,]*),([^,])*,([^"])*"/) {
            my $facility_name = $1;
            my $monitoredType = $2;
            my $monitoredValue = $3;
            my $validity = $4;
            my $location = $5;
            my $direction = $6;
            my $timeperiod = $7;
            my $monitordate = $8;
            my $monitortime = $9;

            if (not defined $pm_results{$facility_name}) {
                $pm_results{$facility_name} = ();
            }

            my $monitoredPeriodStart = $self->convertPMDateTime($monitordate, $monitortime);

            my %result = (
                facility => $facility_name,
                facility_type => "sts",
                type => $monitoredType,
                value => $monitoredValue,
                time_period => $timeperiod,
                time_period_start => $monitoredPeriodStart,
                measurement_time => time,
                machine_time => $self->getMachineTime(),
                date => $monitordate,
                time => $monitortime,
                validity => $validity,
            );
            $pm_results{$facility_name}->{$monitoredType} = \%result;
        }
    }

    if ($pm_type) {
        return $pm_results{$facility_name}->{$pm_type};
    } elsif ($facility_name and $facility_name ne "ALL") {
        return $pm_results{$facility_name};
    } else {
        return \%pm_results;
    }
}

sub getETH_PM {
    my ($self, $facility_name, $pm_type) = @_;

    if (not $facility_name) {
        $facility_name = "ALL";
    }

    if (not $self->{COUNTERS}->{eth}->{$facility_name}->{CACHE_TIME} or
            $self->{COUNTERS}->{eth}->{$facility_name}->{CACHE_TIME} + $self->{CACHE_DURATION} < time) {

        my ($successStatus, $results);
        if ($facility_name eq "ALL") {
            ($successStatus, $results) = $self->send_cmd("RTRV-PM-GIGE::ALL:".$self->{CTAG}."::;");
        } else {
            ($successStatus, $results) = $self->send_cmd("RTRV-PM-GIGE::\"$facility_name\":".$self->{CTAG}."::;");
        }

        if ($successStatus == -1) {
            return undef;
        }

        my %pm_results = ();

        foreach my $line (@$results) {
# "1-A-1-1:OVER_SIZE,0,PRTL,15-MIN,08-01,16-00"

            if ($line =~ /"(.*):([^:,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*)"/) {
                my $facility_name = $1;
                my $monitoredType = $2;
                my $monitoredValue = $3;
                my $validity = $4;
                my $timeperiod = $5;
                my $monitordate = $6;
                my $monitortime = $7;

                my $monitoredPeriodStart = $self->convertPMDateTime($monitordate, $monitortime);

                my %result = (
                        facility => $facility_name,
                        facility_type => "eth",
                        type => $monitoredType,
                        value => $monitoredValue,
                        time_period => $timeperiod,
                        time_period_start => $monitoredPeriodStart,
                        measurement_time => time,
                        machine_time => $self->getMachineTime(),
                        date => $monitordate,
                        time => $monitortime,
                        validity => $validity,
                        );
                if (not defined $pm_results{$facility_name}) {
                    my %new = ();
                    $pm_results{$facility_name} = \%new;
                }

                $pm_results{$facility_name}->{$monitoredType} = \%result;
            }
        }

        $self->{COUNTERS}->{eth}->{$facility_name}->{CACHE_TIME} = time;
        $self->{COUNTERS}->{eth}->{$facility_name}->{COUNTERS} = \%pm_results;
    } else {
        $self->{LOGGER}->debug("Returning cached");
    }

    if ($pm_type) {
        return $self->{COUNTERS}->{eth}->{$facility_name}->{COUNTERS}->{$facility_name}->{$pm_type};
    } elsif ($facility_name ne "ALL") {
        return $self->{COUNTERS}->{eth}->{$facility_name}->{COUNTERS}->{$facility_name};
    } else {
        return $self->{COUNTERS}->{eth}->{$facility_name}->{COUNTERS};
    }
}

sub getEFLOW_PM {
    my ($self, $facility_name, $pm_type) = @_;

    if (not $facility_name) {
        $facility_name = "ALL";
    }

    if (not $self->{COUNTERS}->{eflow}->{$facility_name}->{CACHE_TIME} or
            $self->{COUNTERS}->{eflow}->{$facility_name}->{CACHE_TIME} + $self->{CACHE_DURATION} < time) {

        my ($successStatus, $results) = $self->send_cmd("RTRV-PM-EFLOW::\"$facility_name\":".$self->{CTAG}."::;");
        if ($successStatus == -1) {
            return undef;
        }

        my %pm_results = ();

        foreach my $line (@$results) {
            # "dcs_eflow_dcs_vcg_39610_in:OUT_GREEN,7,CMPL,15-MIN,09-11,19-00"

            if ($line =~ /"(.*):([^:,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*)"/) {
                my $facility_name = $1;
                my $monitoredType = $2;
                my $monitoredValue = $3;
                my $validity = $4;
                my $timeperiod = $5;
                my $monitordate = $6;
                my $monitortime = $7;

                my $monitoredPeriodStart = $self->convertPMDateTime($monitordate, $monitortime);

                my %result = (
                        facility => $facility_name,
                        facility_type => "eflow",
                        type => $monitoredType,
                        value => $monitoredValue,
                        time_period => $timeperiod,
                        time_period_start => $monitoredPeriodStart,
                        measurement_time => time,
                        machine_time => $self->getMachineTime(),
                        date => $monitordate,
                        time => $monitortime,
                        validity => $validity,
                        );

                if (not defined $pm_results{$facility_name}) {
                    my %new = ();
                    $pm_results{$facility_name} = \%new;
                }

                $pm_results{$facility_name}->{$monitoredType} = \%result;
            }
        }
    
        $self->{COUNTERS}->{eflow}->{$facility_name}->{CACHE_TIME} = time;
        $self->{COUNTERS}->{eflow}->{$facility_name}->{COUNTERS} = \%pm_results;
    } else {
        $self->{LOGGER}->debug("Returning cached");
    }

    if ($pm_type) {
        return $self->{COUNTERS}->{eflow}->{$facility_name}->{COUNTERS}->{$facility_name}->{$pm_type};
    } elsif ($facility_name ne "ALL") {
        return $self->{COUNTERS}->{eflow}->{$facility_name}->{COUNTERS}->{$facility_name};
    } else {
        return $self->{COUNTERS}->{eflow}->{$facility_name}->{COUNTERS};
    }
}

sub getVCG_PM {
    my ($self, $facility_name, $pm_type) = @_;

    if (not $facility_name) {
        $facility_name = "ALL";
    }

    $self->{LOGGER}->debug("VCG: '$facility_name'\n");

    if (not $self->{COUNTERS}->{vcg}->{$facility_name}->{CACHE_TIME} or
            $self->{COUNTERS}->{vcg}->{$facility_name}->{CACHE_TIME} + $self->{CACHE_DURATION} < time) {

        my ($successStatus, $results) = $self->send_cmd("RTRV-PM-VCG::\"$facility_name\":".$self->{CTAG}."::;");
        if ($successStatus == -1) {
            return undef;
        }

        my %pm_results = ();

        foreach my $line (@$results) {
            #    "1-A-4-1:1-96:IN_PACKETS,0,CMPL,15-MIN,09-11,19-00"
            $self->{LOGGER}->debug("Checking $line");
            if ($line =~ /"$facility_name:([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^"]*)"/) {
                $self->{LOGGER}->debug("PM found");
                my $monitoredType = $1;
                my $monitoredValue = $2;
                my $validity = $3;
                my $timeperiod = $4;
                my $monitordate = $5;
                my $monitortime = $6;

                my $monitoredPeriodStart = $self->convertPMDateTime($monitordate, $monitortime);

                my %result = (
                        facility => $facility_name,
                        facility_type => "vcg",
                        type => $monitoredType,
                        value => $monitoredValue,
                        time_period => $timeperiod,
                        time_period_start => $monitoredPeriodStart,
                        measurement_time => time,
                        machine_time => $self->getMachineTime(),
                        date => $monitordate,
                        time => $monitortime,
                        validity => $validity,
                        );

                if (not defined $pm_results{$facility_name}) {
                    my %new = ();
                    $pm_results{$facility_name} = \%new;
                }

                $pm_results{$facility_name}->{$monitoredType} = \%result;

                $self->{LOGGER}->debug("PM found");
            }
        }

        $self->{COUNTERS}->{vcg}->{$facility_name}->{CACHE_TIME} = time;
        $self->{COUNTERS}->{vcg}->{$facility_name}->{COUNTERS} = \%pm_results;
    } else {
        $self->{LOGGER}->debug("Returning cached");
    }


    if ($pm_type) {
        return $self->{COUNTERS}->{vcg}->{$facility_name}->{COUNTERS}->{$facility_name}->{$pm_type};
    } elsif ($facility_name ne "ALL") {
        return $self->{COUNTERS}->{vcg}->{$facility_name}->{COUNTERS}->{$facility_name};
    } else {
        return $self->{COUNTERS}->{vcg}->{$facility_name}->{COUNTERS};
    }
}

sub getOCN_PM {
    my ($self, $facility_name, $pm_type) = @_;

    if (not $facility_name) {
        $facility_name = "ALL";
    }

    if (not $self->{COUNTERS}->{ocn}->{$facility_name}->{CACHE_TIME} or
            $self->{COUNTERS}->{ocn}->{$facility_name}->{CACHE_TIME} + $self->{CACHE_DURATION} < time) {

        my ($successStatus, $results) = $self->send_cmd("RTRV-PM-OCN::$facility_name:".$self->{CTAG}."::;");
        if ($successStatus == -1) {
            return undef;
        }

        my %pm_results = ();

        foreach my $line (@$results) {
            #   "1-A-3-1,OC192:OPR,0,PRTL,NEND,RCV,15-MIN,05-30,01-00,LOW,LOW,LOW,LOW,0"
            if ($line =~ /"([^,]*),OC([0-9]+):([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*)"/) {
                my $facility_name = $1;
                my $facility_name_type = $2;
                my $monitoredType = $3;
                my $monitoredValue = $4;
                my $validity = $5;
                my $location = $6;
                my $direction = $7;
                my $timeperiod = $8;
                my $monitordate = $9;
                my $monitortime = $10;
                my $actual = $11;
                my $low = $12;
                my $high = $13;
                my $average = $14;
                my $normalized = $15;

                my $monitoredPeriodStart = $self->convertPMDateTime($monitordate, $monitortime);

                my %result = (
                        facility => $facility_name,
                        facility_type => "vcg",
                        type => $monitoredType,
                        value => $monitoredValue,
                        time_period => $timeperiod,
                        time_period_start => $monitoredPeriodStart,
                        measurement_time => time,
                        machine_time => $self->getMachineTime(),
                        date => $monitordate,
                        time => $monitortime,
                        validity => $validity,
                        actual => $actual,
                        low => $low,
                        high => $high,
                        average => $average,
                        normalized => $normalized,
                        );

                if (not defined $pm_results{$facility_name}) {
                    my %new = ();
                    $pm_results{$facility_name} = \%new;
                }

                $pm_results{$facility_name}->{$monitoredType} = \%result;
            }
        }

        $self->{COUNTERS}->{ocn}->{$facility_name}->{CACHE_TIME} = time;
        $self->{COUNTERS}->{ocn}->{$facility_name}->{COUNTERS} = \%pm_results;
    } else {
        $self->{LOGGER}->debug("Returning cached");
    }


    if ($pm_type) {
        return $self->{COUNTERS}->{ocn}->{$facility_name}->{COUNTERS}->{$facility_name}->{$pm_type};
    } elsif ($facility_name ne "ALL") {
        return $self->{COUNTERS}->{ocn}->{$facility_name}->{COUNTERS}->{$facility_name};
    } else {
        return $self->{COUNTERS}->{ocn}->{$facility_name}->{COUNTERS};
    }
}

sub getAlarms {
    my ($self, $alarm_to_match) = @_;

    if ($self->{ALARMS_CACHE_TIME} + $self->{CACHE_DURATION} < time) {
        my @alarms = ();

        $self->{LOGGER}->debug("looking up alarms");

        my ($successStatus, $results) = $self->send_cmd("RTRV-ALM-ALL:::".$self->{CTAG}."::;");

        $self->{LOGGER}->debug("Results: ".Dumper($results));

        if ($successStatus != 1) {
            $self->{ALARMS} = undef;
            return;
        }

        #   "TimingInput_BITS_2,REF:MN,SYNCCLK,NSA,2008-08-28,15:12:03,,:\"LOS on synchronization reference as seen by TM1\","
        #   "TimingInput_BITS_2,REF:MN,SYNCCLK,NSA,2008-08-28,15:12:11,,:\"LOS on synchronization reference as seen by TM2\","

        foreach my $line (@$results) {
            if ($line =~ /"([^,]*),([^:]*):([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^:]*):(\\".*\\"),(.*)"/) {
                my $facility = $1;
                my $facility_type = $2;
                my $severity = $3;
                my $alarmType = $4;
                my $serviceAffecting = $5;
                my $date = $6;
                my $time = $7;
                my $unknown1 = $8;
                my $unknown2 = $9;
                my $description = $10;
                my $unknown3 = $11;

                $description =~ s/\\"//g;

                my %alarm = (
                        facility => $facility,
                        facility_type => $facility_type,
                        severity => $severity,
                        alarmType => $alarmType,
                        service_affecting => $serviceAffecting,
                        date => $date,
                        time => $time,
                        description => $description,
                        );

                push @alarms, \%alarm;
            }
        }

        $self->{ALARMS} = \@alarms;
        $self->{ALARMS_CACHE_TIME} = time;
    }

    my @ret_alarms = ();

    foreach my $alarm (@{ $self->{ALARMS} }) {
        my $matches = 1;
        if ($alarm_to_match) {
            foreach my $key (keys %$alarm_to_match) {
                if ($alarm->{$key}) {
                    if ($alarm->{$key} ne $alarm_to_match->{$key}) {
                        $matches = 1;
                    }
                }
            }
        }

        if ($matches) {
            push @ret_alarms, $alarm;
        }
    }

    return \@ret_alarms;
}

sub waitEvent {
    my ($self, @args) = @_;
    my $args = validateParams(@args, 
            {
                timeout => { type => SCALAR },
            });

    my ($status, $lines);
    if ($args->{timeout} ) {
        ($status, $lines) = $self->waitMessage({ type => "event", timeout => $args->{timeout} });
    } else {
        ($status, $lines) = $self->waitMessage({ type => "event" });
    }

    if ($status != 0 or not defined $lines) {
        return (-1, undef);
    }

    foreach my $line (@{ $lines }) {
        # "EMSUser:LOGBUFR90,TC,01-28,23-00-23,,,,,:\"The Audit Log Buffer has reached 90 percent full\""
        if ($line =~ /"([^:]*):([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^:]*):(\\".*\\")/) {
            my $facility = $1;
            my $condtype = $2;
            my $effect = $3;
            my $date = $4;
            my $time = $5;
            my $unknown1 = $6;
            my $unknown2 = $7;
            my $unknown3 = $8;
            my $unknown4 = $9;
            my $unknown5 = $10;
            my $description = $11;

            $self->{LOGGER}->debug("DESCRIPTION: '$description'\n");
            $description =~ s/\\"//g;
            $self->{LOGGER}->debug("DESCRIPTION: '$description'\n");

            my %event = (
                facility => $facility,
                eventType => $condtype,
                effect => $effect,
                date => $date,
                time => $time,
#                location => $location,
#                direction => $direction,
#                value => $monitoredValue,
#                threshold => $thresholdLevel,
#                period => $timePeriod,
                description => $description,
                );

            return (0, \%event);
        }
    }

    return (-1, undef);
}

sub waitAlarm {
    my ($self, @args) = @_;
    my $args = validateParams(@args, 
            {
                timeout => { type => SCALAR },
            });

    my ($status, $lines);
    if ($args->{timeout} ) {
        ($status, $lines) = $self->waitMessage({ type => "alarm", timeout => $args->{timeout} });
    } else {
        ($status, $lines) = $self->waitMessage({ type => "alarm" });
    }

    if ($status != 0 or not defined $lines) {
        return (-1, undef);
    }

    foreach my $line (@$lines) {
        if ($line =~ /"([^,]*),([^:]*):([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^:]*):(\\".*\\"),(.*)"/) {
            my $facility = $1;
            my $facility_type = $2;
            my $severity = $3;
            my $alarmType = $4;
            my $serviceAffecting = $5;
            my $date = $6;
            my $time = $7;
            my $unknown1 = $8;
            my $unknown2 = $9;
            my $description = $10;
            my $unknown3 = $11;

            $description =~ s/\\"//g;

            my %alarm = (
                    facility => $facility,
                    facility_type => $facility_type,
                    severity => $severity,
                    alarmType => $alarmType,
                    service_affecting => $serviceAffecting,
                    date => $date,
                    time => $time,
                    description => $description,
                    );

            return (0, \%alarm);
        }
    }

    return (-1, undef);
}

sub login {
    my ($self, @params) = @_;
    my $parameters = validate(@params,
            {
                inhibitMessages => { type => SCALAR, optional => 1, default => 1 },
            });
 
    my ($status, $lines) = $self->send_cmd("ACT-USER::".$self->{USERNAME}.":".$self->{CTAG}."::".$self->{PASSWORD}.";");

    if ($status != 1) {
        return 0;
    }

    if ($parameters->{inhibitMessages}) {
        $self->send_cmd("INH-MSG-ALL:::".$self->{CTAG}.";");
    }

    return 1;
}

sub logout {
  my ($self) = @_;

  $self->send_cmd("CANC-USER::".$self->{USERNAME}.":".$self->{CTAG}.";");
}

1;

# vim: expandtab shiftwidth=4 tabstop=4
