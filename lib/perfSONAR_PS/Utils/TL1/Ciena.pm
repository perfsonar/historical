package perfSONAR_PS::Utils::TL1::Ciena;

use warnings;
use strict;

use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);
use Data::Dumper;

#use base 'perfSONAR_PS::Collectors::LinkStatus::Agent::TL1::Base';
use base 'perfSONAR_PS::Utils::TL1::Base';
use fields 'CRSS', 'CRSSBYNAME', 'ETHS', 'ETHSBYAID', 'GTPS', 'GTPSBYNAME', 'OCNS', 'OCNSBYAID', 'SNCS', 'SNCSBYNAME', 'VCGS', 'VCGSBYNAME';

sub initialize {
    my ($self, @params) = @_;

    #my $parameters = validateParams(@params,
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

sub addVCG {
    my ($self, $name) = @_;

    $self->{VCGS}->{$name} = 1;
}

sub getVCG {
    my ($self, $name) = @_;

    if ($self->{CACHE_TIME} + $self->{CACHE_DURATION} < time) {
        $self->readStats();
    }

    return $self->{VCGSBYNAME}->{$name};
}

sub addSNC {
    my ($self, $name) = @_;

    $self->{SNCS}->{$name} = 1;
}

sub getSNC {
    my ($self, $name) = @_;

    if ($self->{CACHE_TIME} + $self->{CACHE_DURATION} < time) {
        $self->readStats();
    }

    return $self->{SNCSBYNAME}->{$name};
}

sub addETH {
    my ($self, $aid) = @_;

    $self->{ETHS}->{$aid} = 1;
}

sub getETH {
    my ($self, $aid) = @_;

    if ($self->{CACHE_TIME} + $self->{CACHE_DURATION} < time) {
        $self->readStats();
    }

    return $self->{ETHSBYAID}->{$aid};
}

sub addOCN {
    my ($self, $aid, $rate) = @_;

    return unless ($rate eq "3" or $rate eq "12" or $rate eq "48" or $rate eq "192" or not $rate); 

    $self->{OCNS}->{$rate}->{$aid} = 1;
}

sub getOCN {
    my ($self, $aid) = @_;

    if ($self->{CACHE_TIME} + $self->{CACHE_DURATION} < time) {
        $self->readStats();
    }

    return $self->{OCNSBYAID}->{$aid};
}

sub addOCH {
    return;
}

sub getOCH {
    return;
}

sub addGTP {
    my ($self, $name) = @_;

    $self->{GTPS}->{$name} = 1;
}

sub getGTP {
    my ($self, $name) = @_;

    if ($self->{CACHE_TIME} + $self->{CACHE_DURATION} < time) {
        $self->readStats();
    }

    return $self->{GTPSBYNAME}->{$name};
}

sub addCrossconnect {
    my ($self, $name) = @_;

    $self->{CRSS}->{$name} = 1;
}

sub getCrossconnect {
    my ($self, $name) = @_;

    if ($self->{CACHE_TIME} + $self->{CACHE_DURATION} < time) {
        $self->readStats();
    }

    return $self->{CRSSBYNAME}->{$name};
}

sub readStats {
    my ($self) = @_;

    $self->{TL1AGENT}->connect();
    $self->{TL1AGENT}->login();

    if (scalar(keys %{ $self->{CRSS} }) > 0) {
        $self->readCRSs();
    }

    if (scalar(keys %{ $self->{GTPS} }) > 0) {
        $self->readGTPs();
    }

    if (scalar(keys %{ $self->{SNCS} }) > 0) {
        $self->readSNCs();
    }

    if (scalar(keys %{ $self->{OCNS} }) > 0) {
        $self->readOCNs();
    }

    if (scalar(keys %{ $self->{VCGS} }) > 0) {
        $self->readVCGs();
    }

    $self->{CACHE_TIME} = time;
    $self->{TL1AGENT}->disconnect();

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

sub readVCGs {
    my ($self) = @_;

    my %vcgs = ();

    my @results = $self->send_cmd("RTRV-VCG::ALL:1234;");

    foreach my $line (@results) {
        if ($line =~ /"([^,]*),.*[^A-Z]PST=([^,]*),.*SST=([^,]*).*"/) {
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
        if ($line =~ /"([^,]*),.*[^A-Z]PST=([^,]*).*"/) {
            my %status = ( pst => $2 );

            $sncs{$1} = \%status;
        }
    }

    $self->{SNCSBYNAME} = \%sncs;

    return;
}

sub readOCNs {
    my ($self) = @_;

    my %ocns = ();

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
