package perfSONAR_PS::Utils::TL1::Base;

use warnings;
use strict;

use Net::Telnet;
use Data::Dumper;

use Params::Validate qw(:all);

use fields 'USERNAME', 'PASSWORD', 'TYPE', 'ADDRESS', 'PORT', 'CACHE_DURATION', 'CACHE_TIME', 'LOGGER', 'MACHINE_TIME', 'PROMPT', 'CTAG', 'TELNET';

sub new {
    my ($class) = @_;

    my $self = fields::new($class);

    return $self;
}

sub initialize {
    my ($self, @params) = @_;

    #my $parameters = validateParams(@params,
    my $parameters = validate(@params,
            {
            type => 1,
            address => 1,
            port => 1,
            username => 1,
            password => 1,
            cache_time => 1,
            logger => 1,
            prompt => 1,
            ctag => 0,
            });

    print Dumper($parameters);

    $self->{USERNAME} = $parameters->{username};
    $self->{PASSWORD} = $parameters->{password};
    $self->{TYPE} = $parameters->{type};
    $self->{ADDRESS} = $parameters->{address};
    $self->{PORT} = $parameters->{port};
    $self->{PROMPT} = $parameters->{prompt};

    if ($parameters->{ctag}) {
        $self->{CTAG} = $parameters->{ctag};
    } else {
        $self->{CTAG} = int(rand(1000));
    }

    $self->{CACHE_TIME} = 0;
    $self->{CACHE_DURATION} = $parameters->{cache_time};

    $self->{LOGGER} = $parameters->{logger};

    return $self;
}

sub getType {
    my ($self) = @_;

    return $self->{TYPE};
}

sub setType {
    my ($self, $type) = @_;

    $self->{TYPE} = $type;

    return;
}

sub setUsername {
    my ($self, $username) = @_;

    $self->{USERNAME} = $username;

    return;
}

sub getUsername {
    my ($self) = @_;

    return $self->{USERNAME};
}

sub setPassword {
    my ($self, $password) = @_;

    $self->{PASSWORD} = $password;

    return;
}

sub getPassword {
    my ($self) = @_;

    return $self->{PASSWORD};
}

sub setAddress {
    my ($self, $address) = @_;

    $self->{ADDRESS} = $address;

    return;
}

sub getAddress {
    my ($self) = @_;

    return $self->{ADDRESS};
}

sub setAgent {
    my ($self, $agent) = @_;

    $self->{TL1AGENT} = $agent;

    return;
}

sub getAgent {
    my ($self) = @_;

    return $self->{TL1AGENT};
}

sub setCacheTime {
    my ($self, $time) = @_;

    $self->{CACHE_TIME} = $time;

    return $self->{CACHE_TIME};
}

sub getCacheTime {
    my ($self) = @_;

    return $self->{CACHE_TIME};
}

sub connect {
    my ($self) = @_;

    print Dumper($self->{ADDRESS});

    if ($self->{TELNET} = Net::Telnet->new(Host => $self->{ADDRESS}, Port => $self->{PORT}, Timeout => 15)) {
        return 0;
    }

    $self->{TELNET} = undef;

    return -1;
}

sub login {
    die("This method must be overriden by a subclass");
}

sub disconnect {
    my ($self) = @_;

    if (not $self->{TELNET}) {
        return;
    }

    $self->{TELNET}->close;
    $self->{TELNET} = undef;

    return;
}

sub send_cmd {
    my ($self, $cmd) = @_;
    
    if (not $self->{TELNET}) {
        return (-1, undef);
    }

    print "Sending cmd: $cmd\n";

    my $res = $self->{TELNET}->send($cmd);

	my $buf;

    my $successStatus = -1;

	while(my $line = $self->{TELNET}->getline()) {
        print "LINE: $line";

		next if ($line =~ /$cmd/);

		$buf .= $line;

		if ($line =~ /^\s*M\s+$self->{CTAG}\s+(COMPLD|DENY)/) {
            if ($1 eq "COMPLD") {
                $successStatus = 1;
            } elsif ($1 eq "DENY") {
                $successStatus = 0;
            }

			my ($prematch, $junk) = $self->{TELNET}->waitfor("/^".$self->{PROMPT}."/gm");

            print "PREMATCH: $prematch\n";

			$res .= $prematch;

            last;
		}
	}

    my @lines = split('\n', $res);

    return ($successStatus, \@lines);
}

sub setMachineTime {
    my ($self, $time) = @_;

    my ($curr_date, $curr_time) = split(" ", $time);
    my ($year, $month, $day) = split("-", $curr_date);

    # make sure it's in 4 digit year form
    if (length($year) == 2) {
        # I don't see why it'd ever not be +2000, but...
        if ($year < 70) {
            $year += 2000;
        } else {
            $year += 1900;
        }
    }

    $self->{MACHINE_TIME} = "$year-$month-$day $curr_time";

    print "NEW MACHINE TIME: ".$self->{MACHINE_TIME}."\n";
}

sub getMachineTime {
    my ($self) = @_;

    return $self->{MACHINE_TIME};
}

1;

# vim: expandtab shiftwidth=4 tabstop=4
