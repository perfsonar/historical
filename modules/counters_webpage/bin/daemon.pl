use strict;
use warnings;

use lib 'lib';
use Data::Dumper;
use perfSONAR_PS::Common;
use perfSONAR_PS::Utils::TL1::CoreDirector;
use perfSONAR_PS::Utils::TL1::OME;
use Log::Log4perl qw( :easy );
use Config::General;
use Scalar::Util qw(looks_like_number);
use HTML::Template::Expr;

use FindBin qw($Bin);
use lib "$Bin/../lib";
my $confdir = "$Bin/../etc";

my $CONFIG_FILE = $confdir."/raw_counters.conf";
my $DEBUGFLAG = 1;

my $logtype = $INFO;
if ($DEBUGFLAG) {
	$logtype = $DEBUG;
}

Log::Log4perl->easy_init($logtype);

my $logger = get_logger("daemon.pl");

my %child_pids = ();

$SIG{INT} = \&signalHandler;
$SIG{TERM} = \&signalHandler;

my $config =  new Config::General($CONFIG_FILE);
my %conf = $config->getall;

if (not $conf{"html_dir"}) {
	$conf{"html_dir"} = ".";
}

if (not $conf{"template_file"}) {
	$conf{"template_file"} = "raw_counters.tmpl";
}

if ($conf{"template_file"} !~ /^\//) {
	$conf{"template_file"} = $confdir."/".$conf{"template_file"};
}

if (not $conf{"collection_interval"}) {
	$conf{"collection_interval"} = 60;
}

if (ref($conf{"switch"}) ne "ARRAY") {
	my @tmp = ();
	push @tmp, $conf{"switch"};
	$conf{"switch"} = \@tmp;
}

if (not $conf{"switch"}) {
	die("no switches defined");
}

# Validate the config
foreach my $switch (@{ $conf{"switch"} }) {
	my $type = lc($switch->{type});
	my $username = $switch->{username};
	my $password = $switch->{password};
	my $address = $switch->{address};
	my $port = $switch->{port};

	if (not $type or not $address or not $username or not $password) {
		my $msg = "Switch is missing elements needed to access the host. Required: type, address, username, password";
		die($msg);
	}

	if ($type eq "coredirector") {
		if ($switch->{"ethernet"}) {
			if ($switch->{"ethernet"}->{"counter"}) {
				if (ref($switch->{"ethernet"}->{"counter"}) ne "ARRAY") {
					my @tmp = ();
					push @tmp, $switch->{"ethernet"}->{"counter"};
					$switch->{"ethernet"}->{"counter"} = \@tmp;
				}
			}

			if ($switch->{"ethernet"}->{"port"}) {
				if (ref($switch->{"ethernet"}->{"port"}) ne "ARRAY") {
					my @tmp = ();
					push @tmp, $switch->{"ethernet"}->{"port"};
					$switch->{"ethernet"}->{"port"} = \@tmp;
				}
			}
		}

		if ($switch->{"vlan"}) {
			if ($switch->{"vlan"}->{"counter"}) {
				if (ref($switch->{"vlan"}->{"counter"}) ne "ARRAY") {
					my @tmp = ();
					push @tmp, $switch->{"vlan"}->{"counter"};
					$switch->{"vlan"}->{"counter"} = \@tmp;
				}
			}

			if ($switch->{"vlan"}->{"number"}) {
				if (ref($switch->{"vlan"}->{"number"}) ne "ARRAY") {
					my @tmp = ();
					push @tmp, $switch->{"vlan"}->{"number"};
					$switch->{"vlan"}->{"number"} = \@tmp;
				}
			}
		}

		if ($switch->{"optical"}) {
			if ($switch->{"optical"}->{"counter"}) {
				if (ref($switch->{"optical"}->{"counter"}) ne "ARRAY") {
					my @tmp = ();
					push @tmp, $switch->{"optical"}->{"counter"};
					$switch->{"optical"}->{"counter"} = \@tmp;
				}
			}

			if ($switch->{"optical"}->{"number"}) {
				if (ref($switch->{"optical"}->{"number"}) ne "ARRAY") {
					my @tmp = ();
					push @tmp, $switch->{"optical"}->{"number"};
					$switch->{"optical"}->{"number"} = \@tmp;
				}
			}
		}
	} elsif ($type eq "ome") {
		if ($switch->{"ethernet"}) {
			if ($switch->{"ethernet"}->{"counter"}) {
				if (ref($switch->{"ethernet"}->{"counter"}) ne "ARRAY") {
					my @tmp = ();
					push @tmp, $switch->{"ethernet"}->{"counter"};
					$switch->{"ethernet"}->{"counter"} = \@tmp;
				}
			}

			if ($switch->{"ethernet"}->{"port"}) {
				if (ref($switch->{"ethernet"}->{"port"}) ne "ARRAY") {
					my @tmp = ();
					push @tmp, $switch->{"ethernet"}->{"port"};
					$switch->{"ethernet"}->{"port"} = \@tmp;
				}
			}
		}

		if ($switch->{"optical"}) {
			if ($switch->{"optical"}->{"counter"}) {
				if (ref($switch->{"optical"}->{"counter"}) ne "ARRAY") {
					my @tmp = ();
					push @tmp, $switch->{"optical"}->{"counter"};
					$switch->{"optical"}->{"counter"} = \@tmp;
				}
			}

			if ($switch->{"optical"}->{"number"}) {
				if (ref($switch->{"optical"}->{"number"}) ne "ARRAY") {
					my @tmp = ();
					push @tmp, $switch->{"optical"}->{"number"};
					$switch->{"optical"}->{"number"} = \@tmp;
				}
			}
		}
	}
}

foreach my $switch (@{ $conf{"switch"} }) {
	my $type = lc($switch->{type});
	my $username = $switch->{username};
	my $password = $switch->{password};
	my $address = $switch->{address};
	my $port = $switch->{port};

	my $pid = fork();
	if ($pid == 0) {
		my %junk = ();
		my $config = mergeHash( \%conf, $switch, \%junk );
		if ($switch->{type} eq "coredirector") {
			handleSwitch_coreDirector($config);
		} elsif ($switch->{type} eq "ome") {
			handleSwitch_OME($config);
		} else {
			exit(0);
		}
	}

	$child_pids{$pid} = 1;
}

foreach my $pid (keys %child_pids) {
    waitpid($pid, 0);
}

sub handleSwitch_coreDirector {
	my ($switch) = @_;

	my $ciena = perfSONAR_PS::Utils::TL1::CoreDirector->new();
	$ciena->initialize({
						cache_time => 60,
						address => $switch->{address},
						username => $switch->{username},
						password => $switch->{password},
						port => $switch->{port},
					});

	my $prev_vlans = ();
	my $prev_ocns = ();
	my $prev_eths = ();

	while (1) {
		my %curr_vlans = ();
		my %curr_ocns = ();
		my %curr_eths = ();

		$logger->info("Collecting stats for ".($switch->{"name"}?$switch->{"name"}:$switch->{"address"}));

		if ($ciena->connect()) {
			$logger->error("Connect failed to ".($switch->{"name"}?$switch->{"name"}:$switch->{"address"}));
			sleep($switch->{"collection_interval"});
			next;
		}

		my $measured_time = time;

		my ($status, $eflows) = $ciena->getEFLOW();
		if ($status == 0) {
		for my $name (sort keys %$eflows) {
			my $eflow = $eflows->{$name};

			if (not $eflow->{"outervlanidrange"}) {
				next;
			}

			my %vlan = ();
			$vlan{"number"} = $eflow->{"outervlanidrange"};
			if ($eflows->{$name}->{ingressporttype} eq "ETTP") {
				$vlan{"ingress"} = $eflow->{ingressportname};
			}
			if ($eflows->{$name}->{egressporttype} eq "ETTP") {
				$vlan{"egress"} = $eflow->{egressportname};
			}

			my $eflow_pms;

			if (not $switch->{"vlan"}->{"counter"}) {
				my $status;
				($status, $eflow_pms) = $ciena->getEFLOW_PM($name);
				next if ($status != 0);
			} else {
				my %counters = ();

				foreach my $counter (@{ $switch->{"vlan"}->{"counter"} }) {
					my $pm;
					my $status;

					($status, $pm) = $ciena->getEFLOW_PM($name, $counter);
					next if ($status != 0);

					$counters{$counter} = $pm;
				}

				$eflow_pms = \%counters;
			}

			$vlan{"pms"} = $eflow_pms;

			$curr_vlans{$vlan{"number"}} = \%vlan;
		}
		}

		if ($switch->{"ethernet"} and $switch->{"ethernet"}->{"port"}) {
			foreach my $port (@{ $switch->{"ethernet"}->{"port"} }) {
				my %eth = ();

				my $eth_pms;

				if (not $switch->{"ethernet"}->{"counter"}) {
					my $status;
					($status, $eth_pms) = $ciena->getETH_PM($port);
					next if ($status != 0);
				} else {
					my %counters = ();

					foreach my $counter (@{ $switch->{"ethernet"}->{"counter"} }) {
						my $pm;
						my $status;

						($status, $pm) = $ciena->getETH_PM($port, $counter);
						next if ($status != 0);

						$counters{$counter} = $pm;
					}

					$eth_pms = \%counters;
				}

				$eth{"name"} = $port;
				$eth{"pms"} = $eth_pms;

				$curr_eths{$port} = \%eth;
			}
		}

		if ($switch->{"optical"} and $switch->{"optical"}->{"port"}) {
			foreach my $port (@{ $switch->{"optical"}->{"port"} }) {
				my %ocn = ();

				my $ocn_pms;

				if (not $switch->{"optical"}->{"counter"}) {
					my $status;
					($status, $ocn_pms) = $ciena->getOCN_PM($port);
					next if ($status != 0);
				} else {
					my %counters = ();

					foreach my $counter (@{ $switch->{"optical"}->{"counter"} }) {
						my $pm;
						my $status;

						($status, $pm) = $ciena->getOCN_PM($port, $counter);
						next if ($status != 0);

						$counters{$counter} = $pm;
					}

					$ocn_pms = \%counters;
				}

				$ocn{"name"} = $port;
				$ocn{"pms"} = $ocn_pms;

				$curr_ocns{$port} = \%ocn;
			}
		}

		$ciena->disconnect();

		my $template = HTML::Template::Expr->new(filename => $switch->{"template_file"});

		my @display_vlans = ();
		foreach my $vlan_num (sort keys %curr_vlans) {
			my %display_vlan = ();

			my $vlan = $curr_vlans{$vlan_num};

			my @perf_counters = ();
			foreach my $name (sort keys %{ $vlan->{pms} }) {
				my %counter = ();
				$counter{"name"} = $name;
				$counter{"value"} = $vlan->{pms}->{$name}->{value};
				$counter{"period_start"} = $vlan->{pms}->{$name}->{time_period_start};
				$counter{"measured_time"} = $ciena->getMachineTime();

				if ($prev_vlans and $prev_vlans->{$vlan_num} and $prev_vlans->{$vlan_num}->{pms}->{$name}) {
					if ($prev_vlans->{$vlan_num}->{pms}->{$name}->{"time"} eq $vlan->{pms}->{$name}->{"time"} and
						$prev_vlans->{$vlan_num}->{pms}->{$name}->{"date"} eq $vlan->{pms}->{$name}->{"date"} and
						looks_like_number($vlan->{pms}->{$name}->{"value"})) {
						$counter{"change"} = $vlan->{pms}->{$name}->{"value"} - $prev_vlans->{$vlan_num}->{pms}->{$name}->{"value"};
					}
				}

				push @perf_counters, \%counter;
			}

			$display_vlan{"number"} = $vlan->{number};
			$display_vlan{"ingress"} = $vlan->{ingress};
			$display_vlan{"egress"} = $vlan->{egress};
			$display_vlan{"counters"} = \@perf_counters;

			push @display_vlans, \%display_vlan;
		}

		my @display_eths = ();
		foreach my $port (sort keys %curr_eths) {
			my %display_eth = ();

			my $eth = $curr_eths{$port};

			$display_eth{"port"} = $port;

			my @perf_counters = ();
			foreach my $name (sort keys %{ $eth->{pms} }) {
				my %counter = ();
				$counter{"name"} = $name;
				$counter{"value"} = $eth->{pms}->{$name}->{value};
				$counter{"period_start"} = $eth->{pms}->{$name}->{time_period_start};
				$counter{"measured_time"} = $ciena->getMachineTime();

				if ($prev_eths and $prev_eths->{$port} and $prev_eths->{$port}->{pms}->{$name}) {
					if ($prev_eths->{$port}->{pms}->{$name}->{"time"} eq $eth->{pms}->{$name}->{"time"} and
						$prev_eths->{$port}->{pms}->{$name}->{"date"} eq $eth->{pms}->{$name}->{"date"} and
						looks_like_number($eth->{pms}->{$name}->{"value"})) {
						$counter{"change"} = $eth->{pms}->{$name}->{"value"} - $prev_eths->{$port}->{pms}->{$name}->{"value"};
					}
				}

				push @perf_counters, \%counter;
			}

			$display_eth{"port"} = $port;
			$display_eth{"counters"} = \@perf_counters;

			push @display_eths, \%display_eth;
		}

		my @display_ocns = ();
		foreach my $port (sort keys %curr_ocns) {
			my %display_ocn = ();

			my $ocn = $curr_ocns{$port};

			my @perf_counters = ();
			foreach my $name (sort keys %{ $ocn->{pms} }) {
				my %counter = ();
				$counter{"name"} = $name;
				$counter{"value"} = $ocn->{pms}->{$name}->{value};
				$counter{"period_start"} = $ocn->{pms}->{$name}->{time_period_start};
				$counter{"measured_time"} = $ciena->getMachineTime();

				if ($prev_ocns and $prev_ocns->{$port} and $prev_ocns->{$port}->{pms}->{$name}) {
					if ($prev_ocns->{$port}->{pms}->{$name}->{"time"} eq $ocn->{pms}->{$name}->{"time"} and
						$prev_ocns->{$port}->{pms}->{$name}->{"date"} eq $ocn->{pms}->{$name}->{"date"} and
						looks_like_number($ocn->{pms}->{$name}->{"value"})) {
						$counter{"change"} = $ocn->{pms}->{$name}->{"value"} - $prev_ocns->{$port}->{pms}->{$name}->{"value"};
					}
				}

				push @perf_counters, \%counter;
			}

			$display_ocn{"port"} = $port;
			$display_ocn{"counters"} = \@perf_counters;
			push @display_ocns, \%display_ocn;
		}

		$template->param( collection_interval => $switch->{"collection_interval"} );
		if (not $switch->{name}) {
			$template->param( hostname => $switch->{"address"});
		} else {
			$template->param( hostname => $switch->{"name"});
		}
		$template->param( vlans => \@display_vlans );
		#$template->param( vlans => \@display_vlans ) if ($#display_vlans > -1);
		$template->param( ethernet_ports => \@display_eths ) if (scalar(@display_eths) > 0);
		$template->param( optical_ports => \@display_ocns ) if (scalar(@display_ocns) > 0);

		open(HTML, ">".$switch->{"html_dir"}."/".$switch->{"address"}.".html");
		print HTML $template->output();
		close(HTML);

		$prev_vlans = \%curr_vlans;
		$prev_eths = \%curr_eths;
		$prev_ocns = \%curr_ocns;

		$logger->info("Waiting ".$switch->{"collection_interval"}." seconds till next collection interval for ".($switch->{"name"}?$switch->{"name"}:$switch->{"address"}));

		sleep($switch->{"collection_interval"});
	}
}

sub handleSwitch_OME {
	my ($switch) = @_;

	my $ome = perfSONAR_PS::Utils::TL1::OME->new();
	$ome->initialize({
						cache_time => 60,
						address => $switch->{address},
						username => $switch->{username},
						password => $switch->{password},
						port => $switch->{port},
					});

	my $prev_ocns = ();
	my $prev_eths = ();

	while (1) {
		my %curr_ocns = ();
		my %curr_eths = ();

		$logger->info("Collecting stats for ".($switch->{"name"}?$switch->{"name"}:$switch->{"address"}));

		if ($ome->connect()) {
			$logger->info("Connect failed to ".($switch->{"name"}?$switch->{"name"}:$switch->{"address"}));
			sleep($switch->{"collection_interval"});
			next;
		}

		my $measured_time = time;

		if ($switch->{"ethernet"} and $switch->{"ethernet"}->{"port"}) {
			foreach my $port (@{ $switch->{"ethernet"}->{"port"} }) {
				my %eth = ();

				my $eth_pms;

				if (not $switch->{"ethernet"}->{"counter"}) {
					my $status;
					($status, $eth_pms) = $ome->getETH_PM($port);
					next if ($status != 0);
				} else {
					my %counters = ();

					foreach my $counter (@{ $switch->{"ethernet"}->{"counter"} }) {
						my $pm;
						my $status;

						($status, $pm) = $ome->getETH_PM($port, $counter);
						next if ($status != 0);

						$counters{$counter} = $pm;
					}

					$eth_pms = \%counters;
				}

				$eth{"name"} = $port;
				$eth{"pms"} = $eth_pms;

				$curr_eths{$port} = \%eth;
			}
		}

		if ($switch->{"optical"} and $switch->{"optical"}->{"port"}) {
			foreach my $port (@{ $switch->{"optical"}->{"port"} }) {
				my %ocn = ();

				my $ocn_pms;

				if (not $switch->{"optical"}->{"counter"}) {
					my $status;
					($status, $ocn_pms) = $ome->getOCN_PM($port);
					next if ($status != 0);
				} else {
					my %counters = ();

					foreach my $counter (@{ $switch->{"optical"}->{"counter"} }) {
						my $pm;
						my $status;

						($status, $pm) = $ome->getOCN_PM($port, $counter);
						next if ($status != 0);

						$counters{$counter} = $pm;
					}

					$ocn_pms = \%counters;
				}

				$ocn{"name"} = $port;
				$ocn{"pms"} = $ocn_pms;

				$curr_ocns{$port} = \%ocn;
			}
		}

		$ome->disconnect();

		my $template = HTML::Template::Expr->new(filename => $switch->{"template_file"});

		my @display_eths = ();
		foreach my $port (sort keys %curr_eths) {
			my %display_eth = ();

			my $eth = $curr_eths{$port};

			$display_eth{"port"} = $port;

			my @perf_counters = ();
			foreach my $name (sort keys %{ $eth->{pms} }) {
				my %counter = ();
				$counter{"name"} = $name;
				$counter{"value"} = $eth->{pms}->{$name}->{value};
				$counter{"period_start"} = $eth->{pms}->{$name}->{time_period_start};
				$counter{"measured_time"} = $ome->getMachineTime();

				if ($prev_eths and $prev_eths->{$port} and $prev_eths->{$port}->{pms}->{$name}) {
					if ($prev_eths->{$port}->{pms}->{$name}->{"time"} and $prev_eths->{$port}->{pms}->{$name}->{"date"} and
						$prev_eths->{$port}->{pms}->{$name}->{"time"} eq $eth->{pms}->{$name}->{"time"} and
						$prev_eths->{$port}->{pms}->{$name}->{"date"} eq $eth->{pms}->{$name}->{"date"} and
						looks_like_number($eth->{pms}->{$name}->{"value"})) {
						$counter{"change"} = $eth->{pms}->{$name}->{"value"} - $prev_eths->{$port}->{pms}->{$name}->{"value"};
					}
				}

				push @perf_counters, \%counter;
			}

			$display_eth{"port"} = $port;
			$display_eth{"counters"} = \@perf_counters;

			push @display_eths, \%display_eth;
		}

		my @display_ocns = ();
		foreach my $port (sort keys %curr_ocns) {
			my %display_ocn = ();

			my $ocn = $curr_ocns{$port};

			my @perf_counters = ();
			foreach my $name (sort keys %{ $ocn->{pms} }) {
				my %counter = ();
				$counter{"name"} = $name;
				$counter{"value"} = $ocn->{pms}->{$name}->{value};
				$counter{"period_start"} = $ocn->{pms}->{$name}->{time_period_start};
				$counter{"measured_time"} = $ome->getMachineTime();

				if ($prev_ocns and $prev_ocns->{$port} and $prev_ocns->{$port}->{pms}->{$name}) {
					if ($prev_ocns->{$port}->{pms}->{$name}->{"time"} eq $ocn->{pms}->{$name}->{"time"} and
						$prev_ocns->{$port}->{pms}->{$name}->{"date"} eq $ocn->{pms}->{$name}->{"date"} and
						looks_like_number($ocn->{pms}->{$name}->{"value"})) {
						$counter{"change"} = $ocn->{pms}->{$name}->{"value"} - $prev_ocns->{$port}->{pms}->{$name}->{"value"};
					}
				}

				push @perf_counters, \%counter;
			}

			$display_ocn{"port"} = $port;
			$display_ocn{"counters"} = \@perf_counters;
			push @display_ocns, \%display_ocn;
		}

		$template->param( collection_interval => $switch->{"collection_interval"} );
		if (not $switch->{name}) {
			$template->param( hostname => $switch->{"address"});
		} else {
			$template->param( hostname => $switch->{"name"});
		}
		$template->param( ethernet_ports => \@display_eths );
		$template->param( optical_ports => \@display_ocns );

		open(HTML, ">".$switch->{"html_dir"}."/".$switch->{"address"}.".html");
		print HTML $template->output();
		close(HTML);

		$prev_eths = \%curr_eths;
		$prev_ocns = \%curr_ocns;

		$logger->info("Waiting ".$switch->{"collection_interval"}." seconds till next collection interval for ".($switch->{"name"}?$switch->{"name"}:$switch->{"address"}));

		sleep($switch->{"collection_interval"});
	}
}

=head2 killChildren
Kills all the children for this process off. It uses global variables
because this function is used by the signal handler to kill off all
child processes.
=cut
sub killChildren() {
    foreach my $pid (keys %child_pids) {
        kill("SIGKILL", $pid);
    }
}

=head2 signalHandler
Kills all the children for the process and then exits
=cut
sub signalHandler() {
    killChildren();
    exit(0);
}
