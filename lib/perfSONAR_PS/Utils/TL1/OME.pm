package perfSONAR_PS::Utils::TL1::OME;

use warnings;
use strict;

use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);
use Data::Dumper;

use base 'perfSONAR_PS::Utils::TL1::Base';
#use fields 'CRSSBYNAME', 'ETHSBYAID', 'OCNSBYAID', 'OCNSBYNAME', 'READ_CRS', 'READ_ETH', 'READ_OCN';
use fields 'ETHSBYAID', 'OCNSBYAID', 'OCNSBYNAME', 'READ_ETH', 'READ_OCN';

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

    $parameters->{"type"} = "ome";
    $parameters->{"logger"} = get_logger("perfSONAR_PS::Collectors::LinkStatus::Agent::TL1::OME");

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

sub readStats {
    my ($self) = @_;

    print "Connecting - ".time."\n";
    $self->{TL1AGENT}->connect();
    print "Connected - ".time."\n";
    $self->{TL1AGENT}->login();
    print "Logged In- ".time."\n";

#    if ($self->{READ_CRS}) {
#        $self->readCRSs();
#    }

    if ($self->{READ_OCN}) {
        $self->readOCNs();
    }

    if ($self->{READ_ETH}) {
        $self->readETHs();
    }

    $self->{CACHE_TIME} = time;
    $self->{TL1AGENT}->disconnect();

    return;
}

sub readETHs {
    my ($self) = @_;

    my %eths = ();

# "ETH-1-1-4::AN=ENABLE,ANSTATUS=COMPLETED,ANETHDPX=FULL,ANSPEED=1000,ANPAUSETX=DISABLE,ANPAUSERX=DISABLE,ADVETHDPX=FULL,ADVSPEED=1000,ADVFLOWCTRL=ASYM,ETHDPX=FULL,SPEED=1000,FLOWCTRL=ASYM,PAUSETX=ENABLE,PAUSERX=DISABLE,PAUSERXOVERRIDE=ENABLE,MTU=9600,TXCON=ENABLE,PASSCTRL=DISABLE,PAUSETXOVERRIDE=DISABLE,RXIDLE=0,CFPRF=CFPRF-1-4,PHYSADDR=001158FF5354:IS"

    my @results = $self->send_cmd("RTRV-ETH::ETH-1-ALL:1234;");

    foreach my $line (@results) {
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
        my @results = $self->send_cmd("RTRV-OC".$i."::OC".$i."-1-ALL:1234;");

        foreach my $line (@results) {
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

#sub readCRSs {
#    my ($self) = @_;
#
#    my %crss = ();
#
#    my @results = $self->send_cmd("RTRV-CRS-ALL:::1234;");
#
#    foreach my $line (@results) {
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

1;

# vim: expandtab shiftwidth=4 tabstop=4
