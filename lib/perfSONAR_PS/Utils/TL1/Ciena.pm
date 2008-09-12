package perfSONAR_PS::Utils::TL1::Ciena;

use warnings;
use strict;

use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);
use Data::Dumper;

use base 'perfSONAR_PS::Utils::TL1::Base';
use fields 'EFLOWSBYNAME', 'CRSSBYNAME', 'ETHSBYAID', 'GTPSBYNAME', 'OCNSBYAID', 'SNCSBYNAME', 'VCGSBYNAME', 'STSSBYNAME', 'READ_CRS', 'READ_ETH', 'READ_GTP', 'READ_OCN', 'READ_SNC', 'READ_VCG', 'READ_STS', 'OCN_PMs', 'ETH_PMs', 'STS_PMs', 'EFLOW_PMs';

sub initialize {
    my ($self, @params) = @_;

    my $parameters = validate(@params,
            {
            address => 1,
            port => 1,
            username => 1,
            password => 1,
            cache_time => 1,
            });

    $parameters->{"type"} = "ciena";
    $parameters->{"logger"} = get_logger("perfSONAR_PS::Collectors::LinkStatus::Agent::TL1::Ciena");

    return $self->SUPER::initialize($parameters);
}

sub getVCG {
    my ($self, $name) = @_;
    my $do_reload_stats = 0;

    if (not $self->{READ_VCG}) {
        $do_reload_stats = 1;
        $self->{READ_VCG} = 1;
    }

    if ($self->{CACHE_TIME} + $self->{CACHE_DURATION} < time or $do_reload_stats) {
        $self->readStats();
    }

    if (not defined $name) {
        return $self->{VCGSBYNAME};
    }

    return $self->{VCGSBYNAME}->{$name};
}

sub getSNC {
    my ($self, $name) = @_;
    my $do_reload_stats = 0;

    if (not $self->{READ_SNC}) {
        $do_reload_stats = 1;
        $self->{READ_SNC} = 1;
    }

    if ($self->{CACHE_TIME} + $self->{CACHE_DURATION} < time or $do_reload_stats) {
        $self->readStats();
    }

    if (not defined $name) {
        return $self->{SNCSBYNAME};
    }

    return $self->{SNCSBYNAME}->{$name};
}

sub getCTP {
    my ($self, $name) = @_;
    my $do_reload_stats = 0;

    if (not $self->{READ_STS}) {
        $do_reload_stats = 1;
        $self->{READ_STS} = 1;
    }

    if ($self->{CACHE_TIME} + $self->{CACHE_DURATION} < time or $do_reload_stats) {
        $self->readStats();
    }

    if (not defined $name) {
        return $self->{STSSBYNAME};
    }

    return $self->{STSSBYNAME}->{$name};
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
    my $do_reload_stats = 0;

    if (not $self->{READ_GTP}) {
        $do_reload_stats = 1;
        $self->{READ_GTP} = 1;
    }

    if ($self->{CACHE_TIME} + $self->{CACHE_DURATION} < time or $do_reload_stats) {
        $self->readStats();
    }

    if (not defined $name) {
        return $self->{GTPSBYNAME};
    }

    return $self->{GTPSBYNAME}->{$name};
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

sub getSTS_PM {
    my ($self, $aid, $type) = @_;

    my @results = $self->send_cmd("RTRV-PM-STSPC::\"$aid\":1234;");

    my %pm_results = ();

    foreach my $line (@results) {
        if ($line =~ /"([^,]*),STSPC:([^,]*),([^,]*),([^,]*),([^,]),([^,]),([^,]*),.*"/) {
            my $aid = $1;
            my $monitoredType = $2;
            my $monitoredValue = $3;
            my $validity = $4;
            my $location = $5;
            my $direction = $6;
            my $timeperiod = $7;

            if (not defined $pm_results{$aid}) {
                $pm_results{$aid} = ();
            }

            my %result = ();
            $result{"type"} = $monitoredType;
            $result{"value"} = $monitoredValue;
            $result{"validity"} = $validity;
            $result{"location"} = $location;
            $result{"direction"} = $direction;
            $result{"timePeriod"} = $timeperiod;

            $pm_results{$aid}->{$monitoredType} = \%result;
        }
    }

    if ($type) {
        return $pm_results{$type};
    } else {
        return \%pm_results;
    }
}

sub getETH_PM {
    my ($self, $aid, $type) = @_;

    my @results = $self->send_cmd("RTRV-PM-GIGE::\"$aid\":1234::;");

    my %pm_results = ();

    foreach my $line (@results) {
        # "1-A-1-1:OVER_SIZE,0,PRTL,15-MIN,08-01,16-00"

        if ($line =~ /"(.*):([^:,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*)"/) {
            my $aid = $1;
            my $monitoredType = $2;
            my $monitoredValue = $3;
            my $validity = $4;
            my $timeperiod = $5;
            my $monitordate = $6;
            my $monitortime = $7;

            my %result = ();
            $result{"type"} = $monitoredType;
            $result{"value"} = $monitoredValue;
            $result{"validity"} = $validity;
            $result{"timePeriod"} = $timeperiod;
            $result{"date"} = $monitordate;
            $result{"time"} = $monitortime;

            $pm_results{$monitoredType} = \%result;
        }
    }

    if ($type) {
        return $pm_results{$type};
    } else {
        return \%pm_results;
    }
}

sub getEFLOW_PM {
    my ($self, $name, $type) = @_;

    my @results = $self->send_cmd("RTRV-PM-EFLOW::\"$name\":1234::;");

    my %pm_results = ();

    foreach my $line (@results) {
        # "dcs_eflow_dcs_vcg_39610_in:OUT_GREEN,7,CMPL,15-MIN,09-11,19-00"

        if ($line =~ /"(.*):([^:,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*)"/) {
            my $name = $1;
            my $monitoredType = $2;
            my $monitoredValue = $3;
            my $validity = $4;
            my $timeperiod = $5;
            my $monitordate = $6;
            my $monitortime = $7;

            my %result = ();
            $result{"type"} = $monitoredType;
            $result{"value"} = $monitoredValue;
            $result{"validity"} = $validity;
            $result{"timePeriod"} = $timeperiod;
            $result{"date"} = $monitordate;
            $result{"time"} = $monitortime;

            $pm_results{$monitoredType} = \%result;
        }
    }

    if ($type) {
        return $pm_results{$type};
    } else {
        return \%pm_results;
    }
}

sub getVCG_PM {
    my ($self, $name, $type) = @_;

    print "VCG: '$name'\n";

    my @results = $self->send_cmd("RTRV-PM-VCG::\"$name\":1234::;");

    my %pm_results = ();

    foreach my $line (@results) {
        #    "1-A-4-1:1-96:IN_PACKETS,0,CMPL,15-MIN,09-11,19-00"

        if ($line =~ /"(.*):([^:,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*)"/) {
            my $name = $1;
            my $monitoredType = $2;
            my $monitoredValue = $3;
            my $validity = $4;
            my $timeperiod = $5;
            my $monitordate = $6;
            my $monitortime = $7;

            my %result = ();
            $result{"type"} = $monitoredType;
            $result{"value"} = $monitoredValue;
            $result{"validity"} = $validity;
            $result{"timePeriod"} = $timeperiod;
            $result{"date"} = $monitordate;
            $result{"time"} = $monitortime;

            $pm_results{$monitoredType} = \%result;
        }
    }

    if ($type) {
        return $pm_results{$type};
    } else {
        return \%pm_results;
    }
}

sub getOCN_PM {
    my ($self, $aid, $type) = @_;

    my %crss = ();

    print "SEND_CMD: RTRV-PM-OCN\n";
    my @results = $self->send_cmd("RTRV-PM-OCN::$aid:1234::;");
    print "DONE CMD: RTRV-PM-OCN\n";

    my %pm_results = ();

    foreach my $line (@results) {
     #   "1-A-3-1,OC192:OPR,0,PRTL,NEND,RCV,15-MIN,05-30,01-00,LOW,LOW,LOW,LOW,0"

        if ($line =~ /"([^,]*),OC([0-9]+):([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*)"/) {
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

            my %result = ();
            $result{"type"} = $monitoredType;
            $result{"value"} = $monitoredValue;
            $result{"validity"} = $validity;
            $result{"location"} = $location;
            $result{"direction"} = $direction;
            $result{"timePeriod"} = $timeperiod;
            $result{"date"} = $monitordate;
            $result{"time"} = $monitortime;
            $result{"actual"} = $actual;
            $result{"low"} = $low;
            $result{"high"} = $high;
            $result{"average"} = $average;
            $result{"normalized"} = $normalized;

            $pm_results{$monitoredType} = \%result;
        }
    }

    if ($type) {
        return $pm_results{$type};
    } else {
        return \%pm_results;
    }
}

sub readStats {
    my ($self) = @_;

    print "LOGGING IN\n";
    $self->login();
    print "LOGGED IN\n";

    if ($self->{READ_CRS}) {
        $self->readCRSs();
    }

    if ($self->{READ_GTP}) {
        $self->readGTPs();
    }

    if ($self->{READ_SNC}) {
        $self->readSNCs();
    }

    if ($self->{READ_STS}) {
        $self->readSTSs();
    }

    if ($self->{READ_OCN}) {
        $self->readOCNs();
    }

    if ($self->{READ_VCG}) {
        $self->readVCGs();
    }

    $self->{CACHE_TIME} = time;

    $self->logout();

    print "CRS: ".Dumper($self->{CRSSBYNAME});
    print "ETHS: ".Dumper($self->{ETHSBYAID});
    print "GTPS: ".Dumper($self->{GTPSBYNAME});
    print "OCNS: ".Dumper($self->{OCNSBYAID});
    print "SNCS: ".Dumper($self->{SNCSBYNAME});
    print "VCGS: ".Dumper($self->{VCGSBYNAME});
    print "STS: ".Dumper($self->{STSSBYNAME});

    return;
}

sub readGTPs {
    my ($self) = @_;

    my %gtps = ();

    my @results = $self->send_cmd("RTRV-GTP::ALL:1234;");

    foreach my $line (@results) {
        if ($line =~ /"([^,]*),.*[^A-Z]PST=([^,]*),.*SST=([^,]*).*"/) {
            my %status = ( pst => $2, sst => $3 );

            $gtps{$1} = \%status;
        }
    }

    $self->{GTPSBYNAME} = \%gtps;

    return;
}

sub readSTSs {
    my ($self) = @_;

    my %stss = ();

    my @results = $self->send_cmd("RTRV-STSPC:::1234;");

    foreach my $line (@results) {
        if ($line =~ /"([^,]*),.*[^A-Z]PST=([^,]*),.*SST=([^,]*).*"/) {
            my %status = ( pst => $2, sst => $3 );

            $stss{$1} = \%status;
        }
    }

    $self->{STSSBYNAME} = \%stss;

    return;
}

sub readVCGs {
    my ($self) = @_;

    my %vcgs = ();

    my @results = $self->send_cmd("RTRV-VCG::ALL:1234;");

    print "VCGs: ".Dumper(\@results);

    foreach my $line (@results) {
        if ($line =~ /"([^,]*),PST=([^,]*),.*SST=\[[a-zA-Z-]+[,a-zA-Z-]*\]/) {
            my %status = ( pst => $2, sst => $3 );

            $vcgs{$1} = \%status;
        }
    }

    $self->{VCGSBYNAME} = \%vcgs;

    return;
}

sub readSNCs {
    my ($self) = @_;

    my %sncs = ();

    my @results = $self->send_cmd("RTRV-SNC-STSPC::ALL:1234;");

    foreach my $line (@results) {
        if ($line =~ /"([^,]*),.*[^A-Z]PST=([^,]*).*STATE=([^,]*).*"/) {
            my %status = ( pst => $2, state => $3 );

            $sncs{$1} = \%status;
        }
    }

    $self->{SNCSBYNAME} = \%sncs;

    return;
}

sub readOCNs {
    my ($self) = @_;

    my %ocns = ();

    print "Sending command\n";

    my @results = $self->send_cmd("RTRV-OCN::ALL:1234;");

    foreach my $line (@results) {
        if ($line =~ /"([^,]*),.*[^A-Z]PST=([^,]*).*"/) {
            my %status = ( pst => $2 );

            $ocns{$1} = \%status;
        }
    }

    $self->{OCNSBYAID} = \%ocns;

    return;
}

sub readCRSs {
    my ($self) = @_;

    my %crss = ();

    my @results = $self->send_cmd("RTRV-CRS:::1234;");

    foreach my $line (@results) {
        if ($line =~ /NAME=([^,]*)/) {
            my ($pst, $sst, $name);
            $name = $1;

            if ($line =~ /PST=([^,]*)/) {
                $pst = $1;
            }
            if ($line =~ /SST=([^,]*)/) {
                $sst = $1;
            }

            my %status = ( pst => $pst, sst => $sst );

            $crss{$name} = \%status;
        }
    }

    $self->{CRSSBYNAME} = \%crss;

    return;
}

1;

# vim: expandtab shiftwidth=4 tabstop=4
