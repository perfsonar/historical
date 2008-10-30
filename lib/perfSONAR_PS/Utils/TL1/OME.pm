package perfSONAR_PS::Utils::TL1::OME;

use warnings;
use strict;

use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);
use Data::Dumper;

use base 'perfSONAR_PS::Utils::TL1::Base';
use fields 'ETHSBYAID', 'OCNSBYAID', 'OCNSBYNAME', 'READ_ETH', 'READ_OCN', 'READ_PM', 'PMS', 'READ_ALARMS', 'ALARMS';

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

    $parameters->{"type"} = "ome";
    $parameters->{"logger"} = get_logger("perfSONAR_PS::Collectors::LinkStatus::Agent::TL1::OME");
    $parameters->{"prompt"} = "<" if (not $parameters->{"prompt"});
    $parameters->{"port"} = "23" if (not $parameters->{"port"});

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
    my $do_reload_stats = 0;

    if (not $self->{READ_ETH}) {
        $do_reload_stats = 1;
        $self->{READ_ETH} = 1;
    }

    if ($self->{CACHE_TIME} + $self->{CACHE_DURATION} < time or $do_reload_stats) {
        $self->readStats();
    }

    if (not defined $aid) {
        return $self->{ETHSBYAID};
    }

    return $self->{ETHSBYAID}->{$aid};
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
    return;
}

sub getLineByName {
    return;
}

sub getLine {
    return;
}

sub getCrossconnect {
    return;
#    my ($self, $name) = @_;
#    my $do_reload_stats = 0;
#
#    if (not $self->{READ_CRS}) {
#        $do_reload_stats = 1;
#        $self->{READ_CRS} = 1;
#    }
#
#    if ($self->{CACHE_TIME} + $self->{CACHE_DURATION} < time or $do_reload_stats) {
#        $self->readStats();
#    }
#
#    if (not defined $name) {
#        return $self->{CRSSBYNAME};
#    }
#
#    return $self->{CRSSBYNAME}->{$name};
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

sub getETH_PM {
    my $self = shift;
    my %args = @_;

    my %aid_types = ( "eth" => 1, "eth10g" => 1 );
    $args{"aid_types"} = \%aid_types;

    return $self->__get_PM(%args);
}

sub getSTS_PM {
    my $self = shift;
    my %args = @_;

    my %aid_types = ( "sts1" => 1, "sts3c" => 1, "sts12c" => 1, "sts24c" => 1, "sts48c" => 1, "sts192c" );
    $args{"aid_types"} = \%aid_types;

    return $self->__get_PM(%args);
}

sub getOCN_PM {
    my $self = shift;
    my %args = @_;

    my %aid_types = ( "oc3" => 1, "oc12" => 1, "oc48" => 1, "oc192" => 1 );
    $args{"aid_types"} = \%aid_types;

    return $self->__get_PM(%args);
}

sub __get_PM {
    my $self = shift;
    my %args = @_;

    my $aid = $args{'aid'};
    my $type = $args{'variable_name'};
    my $index = $args{'index'};
    my $valid_aid_types = $args{'index'};

    my $do_reload_stats = 0;

    if (not $index) {
        $index = 0;
    }

    if (not $self->{READ_PM}->{$index}) {
        $do_reload_stats = 1;
        $self->{READ_PM} = 1;
    }

    if ($self->{CACHE_TIME} + $self->{CACHE_DURATION} < time or $do_reload_stats) {
        $self->readStats();
    }

    if ($aid and $type) {
        return $self->{PMS}->{$index}->{$aid}->{$type};
    }

    my %pm = ();
    foreach my $curr_aid (keys %{ $self->{PMS}->{$index} }) {
        next unless (not $aid or $aid eq $curr_aid);

        foreach my $curr_type (keys %{ $self->{PMS}->{$index}->{$curr_aid} }) {
            next unless (not $type or $type eq $curr_type);

            my $pm = $self->{PMS}->{$index}->{$curr_aid}->{$curr_type};

            next unless ($valid_aid_types->{lc($pm->{aid_type})});

            $pm{$curr_aid}->{$curr_type} = $pm;
        }
    }

    return \%pm;
}

sub readStats {
    my ($self) = @_;

    $self->connect();
    $self->login();

#    if ($self->{READ_CRS}) {
#        $self->readCRSs();
#    }

    if ($self->{READ_OCN}) {
        $self->readOCNs();
    }

    if ($self->{READ_ETH}) {
        $self->readETHs();
    }

    if ($self->{READ_PM}) {
        $self->readPMs();
    }

    if ($self->{READ_ALARMS}) {
        $self->readAlarms();
    }

    $self->{CACHE_TIME} = time;
    $self->disconnect();

    return;
}

sub readETHs {
    my ($self) = @_;

    my %eths = ();

# "ETH-1-1-4::AN=ENABLE,ANSTATUS=COMPLETED,ANETHDPX=FULL,ANSPEED=1000,ANPAUSETX=DISABLE,ANPAUSERX=DISABLE,ADVETHDPX=FULL,ADVSPEED=1000,ADVFLOWCTRL=ASYM,ETHDPX=FULL,SPEED=1000,FLOWCTRL=ASYM,PAUSETX=ENABLE,PAUSERX=DISABLE,PAUSERXOVERRIDE=ENABLE,MTU=9600,TXCON=ENABLE,PASSCTRL=DISABLE,PAUSETXOVERRIDE=DISABLE,RXIDLE=0,CFPRF=CFPRF-1-4,PHYSADDR=001158FF5354:IS"

    my ($successStatus, $results) = $self->send_cmd("RTRV-ETH::ETH-1-ALL:".$self->{CTAG}.";");

    $self->{LOGGER}->debug("Got ETH line\n");    

    foreach my $line (@$results) {
        $self->{LOGGER}->debug($line."\n");

        if ($line =~ /(\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)/) {
            $self->setMachineTime("$1-$2-$3 $4:$5:$6");
            next;
        }

        if ($line =~ /"(ETH[^:]*)/) {
            my ($aid, $name, $pst, $sst);

            $aid = $1;

            if ($line =~ /.*:([A-Za-z0-9-_&]*),([A-Za-z0-9-_&]*)"/) {
                $pst = $1;
                $sst = $2;
            } elsif ($line =~ /.*:([A-Za-z0-9-_&]*)"/) {
                $pst = $1;
            }

            my %status = ( sst => $sst, pst => $pst );

            $eths{$aid} = \%status;
        }
    }

    $self->{ETHSBYAID} = \%eths;

    return;
}

sub readOCNs {
    my ($self) = @_;

    my %ocns = ();
    my %ocns_name = ();

    foreach my $i (3, 12, 48, 192) {
        my ($successStatus, $results) = $self->send_cmd("RTRV-OC".$i."::OC".$i."-1-ALL:".$self->{CTAG}.";");

        $self->{LOGGER}->debug("Got OC$i line\n");    

        foreach my $line (@$results) {
            $self->{LOGGER}->debug($line."\n");

            if ($line =~ /(\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)/) {
                $self->setMachineTime("$1-$2-$3 $4:$5:$6");
                next;
            }

            if ($line =~ /"(OC$i[^:]*)/) {
                my ($aid, $pst, $sst);

                $aid = $1;

                if ($line =~ /.*:([A-Za-z0-9-_&]*),([A-Za-z0-9-_&]*)"/) {
                    $pst = $1;
                    $sst = $2;
                }

                my %status = ( sst => $sst, pst => $pst );

                $ocns{$aid} = \%status;
            }
        }
    }

    $self->{OCNSBYAID} = \%ocns;

    return;
}

sub readPMs {
    my ($self) = @_;
    my %pms = ();

    my ($successStatus, $results) = $self->send_cmd("RTRV-PM-ALL::ALL:".$self->{CTAG}."::,,,,,,,1:;");

    $self->{LOGGER}->debug("Got PM line\n");    

    foreach my $line (@$results) {
        $self->{LOGGER}->debug($line."\n");

#       "OC192-1-5-1,OC192:OPR-OCH,-3.06,PRTL,NEND,RCV,15-MIN,06-16,15-15,0"
        if ($line =~ /(\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)/) {
            $self->setMachineTime("$1-$2-$3 $4:$5:$6");
            next;
        }

        if ($line =~ /"([^,]*),([^:]*):([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^",]*),?1?"/) {
            my $aid = $1;
            my $aid_type = $2;
            my $pm_type = $3;
            my $pm_value = $4;
            my $validity = $5;
            my $location = $6;
            my $direction = $7;
            my $time_period = $8;
            my $monitoring_date = $9;
            my $monitoring_time = $10;

            my %pm = (
                aid => $aid,
                aid_type => $aid_type,
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

    $self->{PMS} = \%pms;
}

sub readAlarms {
    my ($self) = @_;

    my @alarms = ();

    my ($successStatus, $results) = $self->send_cmd("RTRV-ALM-ALL:::".$self->{CTAG}."::;");

    if ($successStatus != 1) {
        $self->{ALARMS} = undef;
        return;
    }

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

# Possible monitoring types:
# CV-S - Coding Violations
# ES-S - Errored Seconds - Section 
# SES-S - Severely Errored Seconds - Section 
# SEFS-S - Severely Errored Frame Seconds - Section 
# CV-L - Coding Violations - Line 
# ES-L - Errored Seconds - Line 
# SES-L - Severely Errored Seconds - Line 
# UAS-L - Unavailable Seconds - Line 
# FC-L - Failure Count - Line 
# OPR-OCH - Optical Power Receive - Optical Channel. When tmper=1- UNT this is a gauge value; when tmper=1-15-MIN, 1-DAY this is a snapshot value 
# OPT-OCH - Optical Power Transmit - Optical Channel 
# OPRN-OCH - Optical Power Receive - Normalised - Optical Channel 
# OPTN-OCH - Optical Power Transmit - Normalised - Optical Channel 
# CV-OTU - Coding Violations - OTU 
# ES-OTU - Errored Seconds - OTU
# SES-OTU Severely Errored Seconds - OTU 
# SEFS-OTU Severely Errored Framing Seconds - OTU 
# FEC-OTU Forward Error Corrections - OTU 
# HCCS-OTU High Correction Count Seconds - OTU 
# CV-ODU Coding Violations - ODU 
# ES-ODU Errored Seconds - ODU 
# SES-ODU Severely Errored Seconds - ODU 
# UAS-ODU Unavailable Seconds - ODU 
# FC-ODU Failure Count - ODU 
# CV-PCS Coding Violations ? Physical Coding Sublayer 
# ES-PCS Errored Seconds - Physical Coding Sublayer 
# SES-PCS Severely Errored Seconds - Physical Coding Sublayer 
# UAS-PCS Unavailable Seconds - Physical Coding Sublayer 
# ES-E Errored Seconds ? ETH 
# SES-E Severely Errored Seconds ? ETH 
# UAS-E Unavailable Seconds ? ETH 
# INFRAMES-E Number of frames received (binned OM) - Ethernet, valid only for Ethernet and WAN 
# INFRAMESERR-E Number of errored frames received ? ETH 
# INFRAMEDISCDS-E Number of ingress discarded frames due to congestion or overflow ? ETH 
# DFR-E Aggregate count of discarded frames ? ETH 
# OUTFRAMES-E Number of frames transmitted (binned OM)- Ethernet 
# FCSERR-E Frame Check Sequence Errors (binned OM) - Ethernet 
# PFBERE-OTU Post-FEC Bit Error Rate Estimates - OTU. When tmper=1-UNT this is a gauge value; when tmper=1-15-MIN, 1-DAY this is a snapshot value 
# PRFBER-OTU Pre-FEC Bit Error Rate - OTU 
# ES-W Errored Seconds - WAN 
# SES-W Severely Errored Seconds ? WAN 
# UAS-W Unavailable Seconds ? WAN 
# INFRAMES-W Number of frames received (binned OM) - WAN 
# INFRAMESERR-W Number of errored frames received ? WAN 
# OUTFRAMES-W ANumber of frames transmitted (binned OM)- WAN 
# ES-W Errored Seconds ? WAN 
# SES-W Severely Errored Seconds ? WAN 
# UAS-W Unavailable Seconds ? WAN 
# INFRAMES-W Number of frames received (binned OM) - WAN 
# INFRAMESERR-W Number of errored frames received ? WAN 
# OUTFRAMES-W ANumber of frames transmitted (binned OM)- WAN 


#   "OC192-1-5-1,OC192:OPR-OCH,-3.06,PRTL,NEND,RCV,15-MIN,06-16,15-15,0"
#   "OC192-1-5-1,OC192:OPT-OCH,-2.15,PRTL,NEND,TRMT,15-MIN,06-16,15-15,0"
#   "OC192-1-5-1,OC192:OPRN-OCH,58,PRTL,NEND,RCV,15-MIN,06-16,15-15,0"
#   "OC192-1-6-1,OC192:OPR-OCH,-2.78,PRTL,NEND,RCV,15-MIN,06-16,15-15,0"
#   "OC192-1-6-1,OC192:OPT-OCH,-2.25,PRTL,NEND,TRMT,15-MIN,06-16,15-15,0"
#   "OC192-1-6-1,OC192:OPRN-OCH,64,PRTL,NEND,RCV,15-MIN,06-16,15-15,0"
#   "OC192-1-9-1,OC192:OPR-OCH,0.36,ADJ,NEND,RCV,15-MIN,06-16,15-15,0"
#   "OC192-1-9-1,OC192:OPT-OCH,-2.27,PRTL,NEND,TRMT,15-MIN,06-16,15-15,0"
#   "OC192-1-9-1,OC192:OPRN-OCH,100,ADJ,NEND,RCV,15-MIN,06-16,15-15,0"
#   "STS3C-1-6-1-64,STS3C:UAS-P,311,PRTL,NEND,RCV,15-MIN,06-16,15-15,0"
#   "STS3C-1-6-1-67,STS3C:UAS-P,311,PRTL,NEND,RCV,15-MIN,06-16,15-15,0"
#   "STS3C-1-6-1-70,STS3C:UAS-P,311,PRTL,NEND,RCV,15-MIN,06-16,15-15,0"
#   "STS3C-1-6-1-73,STS3C:UAS-P,311,PRTL,NEND,RCV,15-MIN,06-16,15-15,0"
#   "STS3C-1-6-1-76,STS3C:UAS-P,311,PRTL,NEND,RCV,15-MIN,06-16,15-15,0"
#   "STS3C-1-6-1-79,STS3C:UAS-P,311,PRTL,NEND,RCV,15-MIN,06-16,15-15,0"
#   "STS3C-1-6-1-82,STS3C:UAS-P,311,PRTL,NEND,RCV,15-MIN,06-16,15-15,0"
#   "WAN-1-2-2,WAN:UAS-W,314,PRTL,NEND,RCV,15-MIN,06-16,15-15,0"
#   "ETH-1-2-2,ETH:UAS-E,314,PRTL,NEND,RCV,15-MIN,06-16,15-15,0"

#sub readCRSs {
#    my ($self) = @_;
#
#    my %crss = ();
#
#    my ($successStatus, $results) = $self->send_cmd("RTRV-CRS-ALL:::".$self->{CTAG}.";");
#
#    foreach my $line (@$results) {
#        if ($line =~ /LABEL=\\"([^\\]*)\\"/) {
#            my ($pst, $sst, $name);
#            $name = $1;
#
#            if ($line =~ /AST=([^,]*)/) {
#                $pst = $1;
#            }
#            if ($line =~ /\".*:.*:.*:(.*)"/) {
#                $sst = $1;
#                if ($sst eq "") {
#                    $sst = "ACTIVE";
#                }
#            }
#
#            my %status = ( pst => $pst, sst => $sst );
#
#            $crss{$name} = \%status;
#        }
#    }
#
#    $self->{CRSSBYNAME} = \%crss;
#
#    return;
#}

sub login {
    my ($self) = @_;

    $self->{LOGGER}->debug("PASSWORD: $self->{PASSWORD}\n");

    my ($status, $lines) = $self->send_cmd("ACT-USER::".$self->{USERNAME}.":".$self->{CTAG}."::\"".$self->{PASSWORD}."\";");

    if ($status != 1) {
        return -1;
    }

    $self->send_cmd("INH-MSG-ALL:::".$self->{CTAG}.";");

    return 0;
}

1;

# vim: expandtab shiftwidth=4 tabstop=4
