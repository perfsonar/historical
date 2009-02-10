package perfSONAR_PS::DB::Status;

use strict;
use warnings;
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::DB::SQL;
use perfSONAR_PS::Status::Link;
use perfSONAR_PS::Status::Common;
use Data::Dumper;

our $VERSION = 0.09;

use fields "READ_ONLY", "DBI_STRING", "DB_USERNAME", "DB_PASSWORD", "DB_TABLE", "DB_OPEN", "DATADB";

sub new {
	my ($package, $dbi_string, $db_username, $db_password, $table, $read_only) = @_;

	my $self = fields::new($package);

	if ($read_only) {
		$self->{"READ_ONLY"} = 1;
	} else {
		$self->{"READ_ONLY"} = 0;
	}

	if (defined $dbi_string and $dbi_string ne "") { 
		$self->{"DBI_STRING"} = $dbi_string;
	}

	if (defined $db_username and $db_username ne "") { 
		$self->{"DB_USERNAME"} = $db_username;
	}

	if (defined $db_password and $db_password ne "") { 
		$self->{"DB_PASSWORD"} = $db_password;
	}

	if (defined $table and $table ne "") { 
		$self->{"DB_TABLE"} = $table;
	} else {
		$self->{"DB_TABLE"} = "ps_status";
	}

	$self->{"DB_OPEN"} = 0;
	$self->{"DATADB"} = "";

	return $self;
}

sub open {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::Client::Status::SQL");

	return (0, "") if ($self->{DB_OPEN} != 0);

        my @dbSchema = ("element_id", "start_time", "end_time", "oper_status", "admin_status"); 

	$logger->debug("Table: ".$self->{DB_TABLE});

	$self->{DATADB} = new perfSONAR_PS::DB::SQL({ name => $self->{DBI_STRING}, user => $self->{DB_USERNAME}, pass => $self->{DB_PASSWORD}, schema => \@dbSchema });
	if (not defined $self->{DATADB}) {
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

sub close {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::Client::Status::SQL");

	return 0 if ($self->{DB_OPEN} == 0);

	$self->{DB_OPEN} = 0;

	return $self->{DATADB}->closeDB;
}

sub setDBIString {
	my ($self, $dbi_string) = @_;

	$self->close();

	$self->{DB_OPEN} = 0;
	$self->{DBI_STRING} = $dbi_string;

    return;
}

sub dbIsOpen {
	my ($self) = @_;
	return $self->{DB_OPEN};
}

sub getDBIString {
	my ($self) = @_;

	return $self->{DBI_STRING};
}

sub getAll {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::Client::Status::SQL");

	return (-1, "Database is not open") if ($self->{DB_OPEN} == 0);

	my $elements = $self->{DATADB}->query({ query => "select distinct element_id from ".$self->{DB_TABLE} });
	if ($elements == -1) {
		$logger->error("Couldn't grab list of elements");
		return (-1, "Couldn't grab list of elements");
	}

	my %elements = ();

	foreach my $element_ref (@{ $elements }) {
		my @element = @{ $element_ref };

		my $states = $self->{DATADB}->query({ query => "select start_time, end_time, oper_status, admin_status from ".$self->{DB_TABLE}." where element_id=\'".$element[0]."\' order by start_time" });
		if ($states == -1) {
			$logger->error("Couldn't grab information for element ".$element[0]);
			return (-1, "Couldn't grab information for element ".$element[0]);
		}

		foreach my $state_ref (@{ $states }) {
			my @state = @{ $state_ref };

			my $new_element = new perfSONAR_PS::Status::Link($element[0], $state[0], $state[1], $state[2], $state[3]);
			if (not defined $elements{$element[0]}) {
				$elements{$element[0]} = ();
			}
			push @{ $elements{$element[0]} }, $new_element;
		}
	}

	return (0, \%elements);
}

sub getUniqueIDs {
	my ($self) = @_;
	my $logger = get_logger("perfSONAR_PS::Client::Status::SQL");

	return (-1, "Database is not open") if ($self->{DB_OPEN} == 0);

	my $elements = $self->{DATADB}->query({ query => "select distinct element_id from ".$self->{DB_TABLE} });
	if ($elements == -1) {
		$logger->error("Couldn't grab list of elements");
		return (-1, "Couldn't grab list of elements");
	}

	my @element_ids = ();
	foreach my $element_ref (@{ $elements }) {
		my @element = @{ $element_ref };

		push @element_ids, $element[0];
	}

	return (0, \@element_ids);
}

sub getElementStatus {
	my ($self, $element_ids, $start_time, $end_time) = @_;
	my $logger = get_logger("perfSONAR_PS::Client::Status::SQL");

	return (-1, "Database is not open") if ($self->{DB_OPEN} == 0);

	my %elements;

	foreach my $element_id (@{ $element_ids }) {
		my $query;

		$query = "select start_time, end_time, oper_status, admin_status from ".$self->{DB_TABLE}." where element_id=\'".$element_id."\'";

        if ($end_time) {
            $query .= " and start_time <= \'".$end_time."\'";
        }

        if ($start_time) {
            $query .= "and end_time >= \'".$start_time."\'";
        }

        $query .= " order by start_time";

		my $states = $self->{DATADB}->query({ query => $query });
		if ($states == -1) {
			$logger->error("Couldn't grab information for node ".$element_id);
			return (-1, "Couldn't grab information for node ".$element_id);
		}

		foreach my $state_ref (@{ $states }) {
			my @state = @{ $state_ref };
			my $new_element;

            $state[0] = $start_time if ($state[0] < $start_time);
            $state[1] = $end_time if ($state[1] > $end_time);

			$new_element = new perfSONAR_PS::Status::Link($element_id, $state[0], $state[1], $state[2], $state[3]);

            if (not defined $elements{$element_id}) {
                my @newa = ();
                $elements{$element_id} = \@newa;
            }

			push @{ $elements{$element_id} }, $new_element;
		}
	}

	return (0, \%elements);
}

sub updateStatus {
	my($self, $time, $element_id, $oper_value, $admin_value, $do_update) = @_;
	my $logger = get_logger("perfSONAR_PS::Client::Status::SQL");
	my $prev_end_time;

	$oper_value = lc($oper_value);
	$admin_value = lc($admin_value);

	if (!isValidOperState($oper_value)) {
		return (-1, "Invalid operational state: $oper_value");
	}

	if (!isValidAdminState($admin_value)) {
		return (-1, "Invalid administrative state: $admin_value");
	}

	return (-1, "Database is not open") if ($self->{DB_OPEN} == 0);

	return (-1, "Database is Read-Only") if ($self->{READ_ONLY} == 1);

    my $query = "select end_time, oper_status, admin_status from ".$self->{DB_TABLE}." where element_id=\'".$element_id."\' order by end_time limit 1";

    my $states = $self->{DATADB}->query({ query => $query });
    if ($states == -1) {
        $logger->error("Couldn't grab information for node ".$element_id);
        return (-1, "Couldn't grab information for node ".$element_id);
    }

    $logger->debug("Size of: ".scalar(@$states)." -- ".Dumper($states));

    if (scalar(@$states) > 0) {
        $prev_end_time = $states->[0]->[0];

        if ($prev_end_time >= $time) {
            my $msg = "Update in the past for $element_id: most recent data was obtained for ".$prev_end_time;
            $logger->error($msg);
            return (-1, $msg);
        }

        if ($do_update) {
            if ($states->[0]->[1] ne $oper_value) {
                my $msg = "Oper value differs for $element_id";
                $logger->warn($msg);
                $do_update = 0;
            } elsif ($states->[0]->[2] ne $admin_value) {
                my $msg = "Admin value differs for $element_id";
                $logger->warn($msg);
                $do_update = 0;
            }
        }
    }
    else {
        $do_update = 0;
    }

	if ($do_update) {
		$logger->debug("Updating $element_id");

		my %updateValues = (
				end_time => $time,
				);

		my %where = (
				element_id => "'".$element_id."'",
				end_time => $prev_end_time,
			    );

		if ($self->{DATADB}->update({ table => $self->{DB_TABLE}, wherevalues => \%where, updatevalues => \%updateValues }) == -1) {
			my $msg = "Couldn't update element status for element $element_id";
			$logger->error($msg);
			return (-1, $msg);
		}
	} else {
		my %insertValues = (
				element_id => $element_id,
				start_time => $time,
				end_time => $time,
				oper_status => $oper_value,
				admin_status => $admin_value,
				);

		if ($self->{DATADB}->insert({ table => $self->{DB_TABLE}, argvalues => \%insertValues }) == -1) {
			my $msg = "Couldn't update element status for element $element_id";

			$logger->error($msg);
			return (-1, $msg);
		}
	}

	return (0, "");
}

1;

__END__

=head1 NAME

perfSONAR_PS::Client::Status::SQL - A module that provides methods for
interacting with a Status MA database directly.

=head1 DESCRIPTION

This module allows one to interact with the Status MA SQL Backend directly
using a standard set of methods. The API provided is identical to the API for
interacting with the MAs via its Web Services interface. Thus, a client written
to read from or update a Status MA can be easily modified to interact directly
with its underlying database allowing more efficient interactions if required.

The module is to be treated as an object, where each instance of the object
represents a connection to a single database. Each method may then be invoked
on the object for the specific database.  

=head1 SYNOPSIS

	use perfSONAR_PS::Client::Status::SQL;

	my $status_client = new perfSONAR_PS::Client::Status::SQL("DBI:SQLite:dbname=status.db");
	if (not defined $status_client) {
		print "Problem creating client for status MA\n";
		exit(-1);
	}

	my ($status, $res) = $status_client->open;
	if ($status != 0) {
		print "Problem opening status MA: $res\n";
		exit(-1);
	}

	($status, $res) = $status_client->getAll();
	if ($status != 0) {
		print "Problem getting complete database: $res\n";
		exit(-1);
	}

	my @elements = (); 

	foreach my $id (keys %{ $res }) {
		print "Link ID: $id\n";

		foreach my $element ( @{ $res->{$id} }) {
			print "\t" . $element->getStartTime . " - " . $element->getEndTime . "\n";
			print "\t-Knowledge Level: " . $element->getKnowledge . "\n";
			print "\t-operStatus: " . $element->getOperStatus . "\n";
			print "\t-adminStatus: " . $element->getAdminStatus . "\n";
		}
	
		push @elements, $id;
	}

	($status, $res) = $status_client->getElementStatus(\@elements, "");
	if ($status != 0) {
		print "Problem obtaining most recent element status: $res\n";
		exit(-1);
	}

	foreach my $id (keys %{ $res }) {
		print "Link ID: $id\n";

		foreach my $element ( @{ $res->{$id} }) {
			print "-operStatus: " . $element->getOperStatus . "\n";
			print "-adminStatus: " . $element->getAdminStatus . "\n";
		}
	}

	($status, $res) = $status_client->getLinkHistory(\@elements);
	if ($status != 0) {
		print "Problem obtaining element history: $res\n";
		exit(-1);
	}

	foreach my $id (keys %{ $res }) {
		print "Link ID: $id\n";
	
		foreach my $element ( @{ $res->{$id} }) {
			print "-operStatus: " . $element->getOperStatus . "\n";
			print "-adminStatus: " . $element->getAdminStatus . "\n";
		}
	}

=head1 DETAILS

=head1 API

The API os perfSONAR_PS::Client::Status::SQL is rather simple and greatly
resembles the messages types received by the server. It is also identical to
the perfSONAR_PS::Client::Status::MA API allowing easy construction of
programs that can interface via the MA server or directly with the database.

=head2 new($package, $dbi_string)

The new function takes a DBI connection string as its first argument. This
specifies which DB to read from/write to.

=head2 open($self)

The open function opens the database to read from/write to. The function
returns an array containing two items. The first is the return status of the
function, 0 on success and non-zero on failure. The second is the error message
generated if applicable.

=head2 close($self)

The close function closes the associated database. It returns 0 on success and
-1 on failure.

=head2 setDBIString($self, $dbi_string)

The setDBIString function changes the database that the instance uses. If open,
it closes the current database.

=head2 dbIsOpen($self)

The dbIsOpen function checks whether the database backend is currently open. If so, it returns 1, if not, 0.

=head2 getDBIString($self)

The getDBIString function returns the current DBI string

=head2 getAll($self)

The getAll function gets the full contents of the database. It returns the
results as a hash with the key being the element id. Each element of the hash is
an array of perfSONAR_PS::Status::Link structures containing a the status
of the specified element at a certain point in time.

=head2 getLinkHistory($self, $element_ids)

The getLinkHistory function returns the complete history of a set of elements. The
$element_ids parameter is a reference to an array of element ids. It returns the
results as a hash with the key being the element id. Each element of the hash is
an array of perfSONAR_PS::Status::Link structures containing a the status
of the specified element at a certain point in time.

=head2 getElementStatus($self, $element_ids, $time)

The getElementStatus function returns the element status at the specified time. The
$element_ids parameter is a reference to an array of element ids. $time is the time
at which you'd like to know each element's status. $time is a perfSONAR_PS::Time
element. If $time is an undefined, it returns the most recent information it
has about each element. It returns the results as a hash with the key being the
element id. Each element of the hash is an array of perfSONAR_PS::Status::Link
structures containing a the status of the specified element at a certain point in
time.

=head2 updateStatus($self, $time, $element_id, $oper_value, $admin_value, $do_update) 

The updateStatus function adds a new data point for the specified element.
$time is a unix timestamp corresponding to when the measurement occured.
$element_id is the element to update. $oper_value is the current operational status
and $admin_value is the current administrative status.  $do_update tells
whether or not we should try to update the a given range of information(e.g. if
you were polling the element and knew that nothing had changed from the previous
iteration, you could set $do_update to 1 and the server would elongate the
previous range instead of creating a new one).

=head2 getUniqueIDs($self)

This function is ONLY available in the SQL client as the functionality it is
not exposed by the MA. It does more or less what it sounds like, it returns a
list of unique element ids that appear in the database. This is used by the MA to
get the list of IDs to register with the LS.

=head1 SEE ALSO

L<perfSONAR_PS::DB::SQL>, L<perfSONAR_PS::Status::Link>,L<perfSONAR_PS::Client::Status::MA>, L<Log::Log4perl>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 VERSION

$Id$

=head1 AUTHOR

Aaron Brown, aaron@internet2.edu

=head1 LICENSE
 
You should have received a copy of the Internet2 Intellectual Property Framework along
with this software.  If not, see <http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT
 
Copyright (c) 2004-2007, Internet2 and the University of Delaware

All rights reserved.

=cut
# vim: expandtab shiftwidth=4 tabstop=4
