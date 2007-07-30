package perfSONAR_PS::MA::Status::Client::SQL;

use strict;
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::DB::SQL;
use perfSONAR_PS::MA::Status::Link;

sub new {
	my ($package, $dbi_string) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status::Client::SQL");

	my %hash;

	if (defined $dbi_string and $dbi_string ne "") { 
		$hash{"DBI_STRING"} = $dbi_string;
	}

	$hash{"DB_OPEN"} = 0;
	$hash{"DATADB"} = "";

	bless \%hash => $package;
}

sub open($) {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status::Client::SQL");

	return (0, "") if ($self->{DB_OPEN} != 0);

	$self->{DATADB} = new perfSONAR_PS::DB::SQL($self->{DBI_STRING});
	if (!defined $self->{DATADB}) {
		my $msg = "Couldn't open specified database";
		$logger->error($msg);
		return (-1, $msg);
	}

	my $status = $self->{DATADB}->openDB;
	if ($status == -1) {
		my $msg = "Couldn't open status database";
		$logger->error($msg);
		return (-1, $msg);
	}

	$self->{DB_OPEN} = 1;

	return (0, "");
}

sub close($) {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status::Client::SQL");

	return 0 if ($self->{DB_OPEN} == 0);

	$self->{DB_OPEN} = 0;

	return $self->{DATADB}->closeDB;
}

sub setDBIString($$) {
	my ($self, $dbi_string) = @_;

	$self->{DB_OPEN} = 0;
	$self->{DBI_STRING} = $dbi_string;
}

sub dbIsOpen($) {
	my ($self) = @_;
	return $self->{DB_OPEN};
}

sub getDBIString($$) {
	my ($self) = @_;

	return $self->{DBI_STRING};
}

sub getAll($) {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status::Client::SQL");

	return (-1, "Database is not open") if ($self->{DB_OPEN} == 0);

	my $links = $self->{DATADB}->query("select distinct link_id from link_status");
	if ($links == -1) {
		$logger->error("Couldn't grab list of links");
		return (-1, "Couldn't grab list of links");
	}

	my %links = ();

	foreach my $link_ref (@{ $links }) {
		my @link = @{ $link_ref };

		my $states = $self->{DATADB}->query("select link_knowledge, start_time, end_time, oper_status, admin_status from link_status where link_id=\'".$link[0]."\' order by end_time");
		if ($states == -1) {
			$logger->error("Couldn't grab information for link ".$link[0]);
			return (-1, "Couldn't grab information for link ".$link[0]);
		}

		foreach my $state_ref (@{ $states }) {
			my @state = @{ $state_ref };

			my $new_link = new perfSONAR_PS::MA::Status::Link($link[0], $state[0], $state[1], $state[2], $state[3], $state[4]);
			if (!defined $links{$link[0]}) {
				$links{$link[0]} = ();
			}
			push @{ $links{$link[0]} }, $new_link;
		}
	}

	return (0, \%links);
}

sub getLinkHistory($$$) {
	my ($self, $link_ids, $time) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status::Client::SQL");

	return (-1, "Database is not open") if ($self->{DB_OPEN} == 0);

	my $query = "select link_id, link_knowledge, start_time, end_time, oper_status, admin_status from link_status ";
	my $i = 0;
	foreach my $link_id (@{ $link_ids }) {
		if ($i == 0) {
			$query .= "where (link_id=\'".$link_id."\'";
		} else {
			$query .= "or link_id=\'".$link_id."\'";
		}
		$i++;
	}
	$query .= ")";

	if (defined $time and $time ne "") {
		$query .= "and end_time => $time and start_time <= $time";
	}

	my $status = $self->{DATADB}->openDB;
	if ($status == -1) {
		my $msg = "Couldn't open status database";
		$logger->error($msg);
		return (-1, $msg);
	}

	my $states = $self->{DATADB}->query($query);
	if ($states == -1) {
		$logger->error("Couldn't grab link history information");
		return (-1, "Couldn't grab link history information");
	}

	my %links = ();

	foreach my $state_ref (@{ $states }) {
		my @state = @{ $state_ref };

		my $new_link = new perfSONAR_PS::MA::Status::Link($state[0], $state[1], $state[2], $state[3], $state[4], $state[5]);
		if (!defined $links{$state[0]}) {
			$links{$state[0]} = ();
		}

		push @{ $links{$state[0]} }, $new_link;
	}

	return (0, \%links);
}

sub getLastLinkStatus($$$) {
	my ($self, $link_ids) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Status::Client::SQL");

	return (-1, "Database is not open") if ($self->{DB_OPEN} == 0);

	my $status = $self->{DATADB}->openDB;
	if ($status == -1) {
		my $msg = "Couldn't open status database";
		$logger->error($msg);
		return (-1, $msg);
	}

	my %links;

	foreach my $link_id (@{ $link_ids }) {
		my $states = $self->{DATADB}->query("select link_knowledge, start_time, end_time, oper_status, admin_status from link_status where link_id=\'".$link_id."\' order by end_time desc limit 1");
		if ($states == -1) {
			$logger->error("Couldn't grab information for node ".$link_id);
			return (-1, "Couldn't grab information for node ".$link_id);
		}

		foreach my $state_ref (@{ $states }) {
			my @state = @{ $state_ref };
			my $new_link;

			$new_link = new perfSONAR_PS::MA::Status::Link($link_id, $state[0], $state[1], $state[2], $state[3], $state[4]);
			$links{$link_id} = ($new_link);
		}
	}

	return (0, \%links);
}

1;
