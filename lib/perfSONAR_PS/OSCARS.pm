package perfSONAR_PS::OSCARS;

use strict;
use warnings;
use IO::Handle;
use Cwd;
use Data::Dumper;

our @ISA = ('Exporter');
our @EXPORT = ('queryCircuits', 'getActiveCircuits', 'getTopology');

sub exec_input($$);
sub queryCircuits($$$$);
sub getActiveCircuits($$$);
sub getClasspath();
sub getTopology($$$);

sub getTopology($$$) {
	my ($url, $client_dir, $repo_dir) = @_;
	my $prev_dir = cwd;
	my @ids = ();

	chdir($client_dir);

	my ($status, $classpath) = getClasspath();
	if ($status == -1) {
		return;
	}

	my @input = ( "\n" );
	my $lines = exec_input("java -cp $classpath GetNetworkTopologyClient $repo_dir $url", \@input);

	my $topology = "";
	my $in_topology = 0;
	foreach my $line (@{ $lines }) {
		chomp($line);
		next if (not $line);
		if ($in_topology) {
			if ($line =~ /Topology End/) {
				$in_topology = 0;
			} else {
				$topology .= $line;
			}
		} elsif ($line =~ /Topology Start/) {
			$in_topology = 1;
		}
	}

	chdir($prev_dir);

	return $topology;
}

sub queryCircuits($$$$) {
	my ($url, $client_dir, $repo_dir, $circuit_ids) = @_;
	my $prev_dir = cwd;

	my (%paths, %pids);

	chdir($client_dir);

	my ($status, $classpath) = getClasspath();

	if ($status == -1) {
		return \%paths;
	}

	foreach my $id (@{ $circuit_ids }) {
		my ($parent_fd, $child_fd);
		pipe($parent_fd, $child_fd);
		my $pid = fork();
		if ($pid != 0) {
			$pids{$pid} = $parent_fd;
		} else {
			my @input = ();
			my $in_path = 0;

			my $lines = exec_input("java -cp $classpath QueryReservationCLI -repo $repo_dir -url $url -gri $id", \@input);
			my $ret = "$id";
			foreach my $line (@{ $lines }) {
				if ($line =~ /Path:/) {
					$in_path = 1;
				} elsif ($line =~ /\t(.*)$/ and $in_path) {
					$ret .= ",$1";
				} else {
					$in_path = 0;
				}
			}

			print $child_fd $ret;
			exit(0);
		}
	}

	foreach my $pid (keys %pids) {
		waitpid($pid, 0);
		my $line;
		read $pids{$pid}, $line, 1024;
		my ($id, @links) = split(',', $line);
		$paths{$id} = \@links;
	}

	chdir($prev_dir);

	return \%paths;
}

sub getActiveCircuits($$$) {
	my ($url, $client_dir, $repo_dir) = @_;
	my $prev_dir = cwd;
	my @ids = ();

	chdir($client_dir);

	my ($status, $classpath) = getClasspath();
	if ($status == -1) {
		return \@ids;
	}

	my @input = ( "\n" );
	my $lines = exec_input("java -cp $classpath ListReservationCLI -repo $repo_dir -url $url -active", \@input);
	my $i = 0;
	my ($curr_id, $owner);
	my %pids = ();
	my %paths = ();

	foreach my $line (@{ $lines }) {
		chomp($line);

		if ($line =~ /GRI: (.*)$/) {
			$curr_id = $1;
		} elsif ($line =~ /Login: (.*)$/) {
			$owner = $1;
		} elsif ($line =~ /Status: (.*)$/) {
			$status = $1;
			push @ids, $curr_id;
		}
	}

	chdir($prev_dir);

	return \@ids;
}

sub getClasspath() {
	my $classpath = ".";

	if (!defined $ENV{"AXIS2_HOME"} or $ENV{"AXIS2_HOME"} eq "") {
		return (-1, "Environmental variable AXIS2_HOME undefined");
	}

	my $dir = $ENV{"AXIS2_HOME"}."/lib";

	opendir(DIR, $dir);
	while((my $entry = readdir(DIR))) {
		if ($entry =~ /\.jar$/) {
			$classpath .= ":$dir/$entry";
		}
	}
	closedir(DIR);
	$classpath .= ":OSCARS-client-api.jar:OSCARS-client-examples.jar";

	return (0, $classpath);
}

sub exec_input($$) {
	my ($cmd, $input) = @_;
	my $pid;
	my @lines = ();

	pipe(PC_READER, PC_WRITER);
	pipe(CP_READER, CP_WRITER);
	PC_WRITER->autoflush(1);
	CP_WRITER->autoflush(1);
	if ($pid = fork()) {
		close(CP_WRITER);
		close(PC_READER);
		foreach my $line (@{ $input }) {
			print PC_WRITER $line;
			sleep(1);
		}
		while(<CP_READER>) {
			push @lines, $_;
		}

		waitpid($pid, 0);
	} else {
		close(PC_WRITER);
		close(CP_READER);
		open(STDOUT, ">&", \*CP_WRITER);
		open(STDERR, ">&", \*CP_WRITER);
		open(STDIN, ">&", \*PC_READER);
		exec $cmd;
	}

	return \@lines;
}
