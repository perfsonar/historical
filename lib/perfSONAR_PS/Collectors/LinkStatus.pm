package perfSONAR_PS::Collectors::LinkStatus;

use strict;
use warnings;
use Log::Log4perl qw(get_logger);
use Time::HiRes qw( gettimeofday );
use Module::Load;
use Data::Dumper;

use perfSONAR_PS::Common;
use perfSONAR_PS::DB::File;
use perfSONAR_PS::Client::Status::MA;
use perfSONAR_PS::Status::Common;
use perfSONAR_PS::Collectors::LinkStatus::Link;
use perfSONAR_PS::Collectors::LinkStatus::Agent::SNMP;
use perfSONAR_PS::Collectors::LinkStatus::Agent::Script;
use perfSONAR_PS::Collectors::LinkStatus::Agent::Constant;
use perfSONAR_PS::Collectors::LinkStatus::Agent::TL1::HDXc;
use perfSONAR_PS::Collectors::LinkStatus::Agent::TL1::OME;
use perfSONAR_PS::Collectors::LinkStatus::Agent::TL1::CoreDirector;

use perfSONAR_PS::Utils::SNMPWalk;

use base 'perfSONAR_PS::Collectors::Base';

use fields 'CLIENT', 'ELEMENTS', 'ELEMENTSBYID', 'SNMPAGENTS', 'TL1AGENTS';

our $VERSION = 0.09;

my %link_prev_update_status = ();

sub init {
    my ($self) = @_;

    if (not defined $self->{CONF}->{"elements_file_type"} or $self->{CONF}->{"elements_file_type"} eq "") {
        $self->{LOGGER}->error("no link file type specified");
        return -1;
    }

    if($self->{CONF}->{"elements_file_type"} ne "file") {
        $self->{LOGGER}->error("invalid link file type specified: " . $self->{CONF}->{"elements_file_type"});
        return -1;
    }

    if ($self->parseElementsFile($self->{CONF}->{"elements_file"}, $self->{CONF}->{"elements_file_type"}) != 0) {
        $self->{LOGGER}->error("couldn't load links to measure");
        return -1;
    }

    if (defined $self->{CONF}->{"ma_type"}) {
        if (lc($self->{CONF}->{"ma_type"}) eq "sqlite") {
            load perfSONAR_PS::Client::Status::SQL;

            if (not defined $self->{CONF}->{"ma_file"} or $self->{CONF}->{"ma_file"} eq "") {
                $self->{LOGGER}->error("You specified a SQLite Database, but then did not specify a database file(ma_file)");
                return -1;
            }

            my $file = $self->{CONF}->{"ma_file"};
            if (defined $self->{DIRECTORY}) {
                if (!($file =~ "^/")) {
                    $file = $self->{DIRECTORY}."/".$file;
                }
            }

            $self->{CLIENT} = perfSONAR_PS::Client::Status::SQL->new("DBI:SQLite:dbname=".$file, $self->{CONF}->{"ma_table"});
        } elsif (lc($self->{CONF}->{"ma_type"}) eq "ma") {
            if (not defined $self->{CONF}->{"ma_uri"} or $self->{CONF}->{"ma_uri"} eq "") {
                $self->{LOGGER}->error("You specified to use an MA, but did not specify which one(ma_uri)");
                return -1;
            }

            $self->{CLIENT} = perfSONAR_PS::Client::Status::MA->new($self->{CONF}->{"ma_uri"});
        } elsif (lc($self->{CONF}->{"ma_type"}) eq "mysql") {
            load perfSONAR_PS::Client::Status::SQL;

            my $dbi_string = "dbi:mysql";

            if (not defined $self->{CONF}->{"ma_name"} or $self->{CONF}->{"ma_name"} eq "") {
                $self->{LOGGER}->error("You specified a MySQL Database, but did not specify the database (ma_name)");
                return -1;
            }

            $dbi_string .= ":".$self->{CONF}->{"ma_name"};

            if (not defined $self->{CONF}->{"ma_host"} or $self->{CONF}->{"ma_host"} eq "") {
                $self->{LOGGER}->error("You specified a MySQL Database, but did not specify the database host (ma_host)");
                return -1;
            }

            $dbi_string .= ":".$self->{CONF}->{"ma_host"};

            if (defined $self->{CONF}->{"ma_port"} and $self->{CONF}->{"ma_port"} ne "") {
                $dbi_string .= ":".$self->{CONF}->{"ma_port"};
            }

            $self->{CLIENT} = perfSONAR_PS::Client::Status::SQL->new($dbi_string, $self->{CONF}->{"ma_username"}, $self->{CONF}->{"ma_password"});
            if (not defined $self->{CLIENT}) {
                my $msg = "Couldn't create SQL client";
                $self->{LOGGER}->error($msg);
                return (-1, $msg);
            }
        }
    } elsif (defined $self->{CONF}->{"db_type"}) {
        if (lc($self->{CONF}->{"db_type"}) eq "sqlite") {
            load perfSONAR_PS::Client::Status::SQL;

            if (not defined $self->{CONF}->{"db_file"} or $self->{CONF}->{"db_file"} eq "") {
                $self->{LOGGER}->error("You specified a SQLite Database, but then did not specify a database file(db_file)");
                return -1;
            }

            my $file = $self->{CONF}->{"db_file"};
            if (defined $self->{DIRECTORY}) {
                if (!($file =~ "^/")) {
                    $file = $self->{DIRECTORY}."/".$file;
                }
            }

            $self->{CLIENT} = perfSONAR_PS::Client::Status::SQL->new("DBI:SQLite:dbname=".$file, $self->{CONF}->{"db_table"});
        } elsif (lc($self->{CONF}->{"db_type"}) eq "mysql") {
            load perfSONAR_PS::Client::Status::SQL;

            my $dbi_string = "dbi:mysql";

            if (not defined $self->{CONF}->{"db_name"} or $self->{CONF}->{"db_name"} eq "") {
                $self->{LOGGER}->error("You specified a MySQL Database, but did not specify the database (db_name)");
                return -1;
            }

            $dbi_string .= ":".$self->{CONF}->{"db_name"};

            if (not defined $self->{CONF}->{"db_host"} or $self->{CONF}->{"db_host"} eq "") {
                $self->{LOGGER}->error("You specified a MySQL Database, but did not specify the database host (db_host)");
                return -1;
            }

            $dbi_string .= ":".$self->{CONF}->{"db_host"};

            if (defined $self->{CONF}->{"db_port"} and $self->{CONF}->{"db_port"} ne "") {
                $dbi_string .= ":".$self->{CONF}->{"db_port"};
            }

            $self->{CLIENT} = perfSONAR_PS::Client::Status::SQL->new($dbi_string, $self->{CONF}->{"db_username"}, $self->{CONF}->{"db_password"});
            if (not defined $self->{CLIENT}) {
                my $msg = "Couldn't create SQL client";
                $self->{LOGGER}->error($msg);
                return (-1, $msg);
            }
        }
    } else {
        $self->{LOGGER}->error("Need to specify a location to store the status reports");
        return -1;
    }

    my ($status, $res) = $self->{CLIENT}->open;
    if ($status != 0) {
        my $msg = "Couldn't open newly created client: $res";
        $self->{LOGGER}->error($msg);
        return -1;
    }

    $self->{CLIENT}->close;

    return 0;
}

sub parseElementsFile {
    my($self, $file, $type) = @_;
    my $elements_config;

    if (defined $self->{DIRECTORY}) {
        if (!($file =~ "^/")) {
            $file = $self->{DIRECTORY}."/".$file;
        }
    }

    my $filedb = perfSONAR_PS::DB::File->new( { file => $file } );
    $filedb->openDB;
    $elements_config = $filedb->getDOM();

    $self->{ELEMENTSBYID} = ();

    foreach my $element ($elements_config->getElementsByTagName("element")) {
        my ($status, $res) = $self->parseElement($element);
        if ($status != 0) {
            my $msg = "Failure parsing element: $res";
            $self->{LOGGER}->error($msg);
            return -1;
        }

        my $parsed_element = $res;

        push @{ $self->{ELEMENTS} }, $parsed_element;

        foreach my $id ($parsed_element->getIDs()) {
            if (defined $self->{ELEMENTSBYID}->{$id}) {
                $self->{LOGGER}->error("Tried to redefine element $id");
                return -1;
            }

            $self->{ELEMENTSBYID}->{$id} = $parsed_element;
        }
    }

    return 0;
}

sub parseElement {
    my ($self, $element_desc) = @_;

    my $link = perfSONAR_PS::Collectors::LinkStatus::Link->new();

    foreach my $id_elm ($element_desc->getElementsByTagName("id")) {
        my $id = $id_elm->textContent;

        $link->addID($id);
    }

    if (scalar($link->getIDs()) == 0) {
        my $msg = "No ids associated with specified element";
        $self->{LOGGER}->error($msg);
        return (-1, $msg);
    }

    my $primary_time_source;

    foreach my $agent ($element_desc->getElementsByTagName("agent")) {
        my ($status, $res);

        ($status, $res) = $self->parseAgentElement($agent);
        if ($status != 0) {
            my $msg = "Problem parsing operational status agent for element: $res";
            $self->{LOGGER}->error($msg);
            return (-1, $msg);
        }

        my $is_time_source = $agent->getAttribute("primary_time_source");
        if (defined $is_time_source and $is_time_source eq "1") {
            if (defined $primary_time_source) {
                my $msg = "Link has multiple primary time sources";
                $self->{LOGGER}->error($msg);
                return (-1, $msg);
            }

            $self->{LOGGER}->debug("Setting primary time source");

            $primary_time_source = $res;
        }

        $link->addAgent($res);
    }

    $link->setPrimaryTimeSource($primary_time_source);

    if (scalar($link->getAgents()) == 0) {
        my $msg = "Didn't specify any agents for link";
        $self->{LOGGER}->error($msg);
        return (-1, $msg);
    }

    return (0, $link);
}

sub parseAgentElement {
    my ($self, $agent) = @_;

    my $new_agent;

    my $status_type = $agent->getAttribute("status_type");
    if (not defined $status_type) {
        my $msg = "Agent does not contain a status_type attribute stating which status (operational or administrative) it returns";
        $self->{LOGGER}->error($msg);
        return (-1, $msg);
    }

    if ($status_type ne "oper" and $status_type ne "operational" and $status_type ne "admin" and $status_type ne "administrative" and $status_type ne "oper/admin" and $status_type ne "admin/oper") {
        my $msg = "Agent's stated status_type is neither 'oper' nor 'admin'";
        $self->{LOGGER}->error($msg);
        return (-1, $msg);
    }

    my $type = $agent->getAttribute("type");
    if (not defined $type or $type eq "") {
        my $msg = "Agent has no type information";
        $self->{LOGGER}->debug($msg);
        return (-1, $msg);
    }

    if ($type eq "script") {
        my $script_name = $agent->findvalue("script_name");
        if (not defined $script_name or $script_name eq "") {
            my $msg = "Agent of type 'script' has no script name defined";
            $self->{LOGGER}->debug($msg);
            return (-1, $msg);
        }

        if (defined $self->{DIRECTORY}) {
            if (!($script_name =~ "^/")) {
                $script_name = $self->{DIRECTORY}."/".$script_name;
            }
        }

        if (!-x $script_name) {
            my $msg = "Agent of type 'script' has non-executable script: \"$script_name\"";
            $self->{LOGGER}->debug($msg);
            return (-1, $msg);
        }

        my $script_params = $agent->findvalue("script_parameters");

        $new_agent = perfSONAR_PS::Collectors::LinkStatus::Agent::Script->new($status_type, $script_name, $script_params);
    } elsif ($type eq "constant") {
        my $value = $agent->findvalue("value");
        if (not defined $value or $value eq "") {
            $value = $agent->findvalue("constant");
        }
        if (not defined $value or $value eq "") {
            my $msg = "Agent of type 'constant' has no value defined";
            $self->{LOGGER}->debug($msg);
            return (-1, $msg);
        }

        $new_agent = perfSONAR_PS::Collectors::LinkStatus::Agent::Constant->new($status_type, $value);
    } elsif ($type eq "snmp") {
        my $oid = $agent->findvalue("oid");
        if (not defined $oid or $oid eq "") {
            if ($status_type eq "oper") {
                $oid = "1.3.6.1.2.1.2.2.1.8";
            } elsif ($status_type eq "admin") {
                $oid = "1.3.6.1.2.1.2.2.1.7";
            }
        }

        my $hostname = $agent->findvalue('hostname');
        if (not defined $hostname or $hostname eq "") {
            my $msg = "Agent of type 'SNMP' has no hostname";
            $self->{LOGGER}->error($msg);
            return (-1, $msg);
        }

        my $ifName = $agent->findvalue('ifName');
        my $ifIndex = $agent->findvalue('ifIndex');

        if ((not defined $ifIndex or $ifIndex eq "") and (not defined $ifName or $ifName eq "")) {
            my $msg = "Agent of type 'SNMP' has no name or index specified";
            $self->{LOGGER}->error($msg);
            return (-1, $msg);
        }

        my $version = $agent->findvalue("version");
        if (not defined $version or $version eq "") {
            my $msg = "Agent of type 'SNMP' has no snmp version";
            $self->{LOGGER}->error($msg);
            return (-1, $msg);
        }

        my $community = $agent->findvalue("community");
        if (not defined $community or $community eq "") {
            my $msg = "Agent of type 'SNMP' has no community string";
            $self->{LOGGER}->error($msg);
            return (-1, $msg);
        }

        if (not defined $self->{SNMPAGENTS}->{$hostname}) {
            $self->{SNMPAGENTS}->{$hostname} = perfSONAR_PS::Collectors::LinkStatus::Agent::SNMP::Host->new( $hostname, "" , $version, $community, "");
        }

        if (not defined $ifIndex or $ifIndex eq "") {
            $self->{LOGGER}->debug("Looking up $ifName from $hostname");

            my ($status, $res) = snmpwalk($hostname, undef, "1.3.6.1.2.1.31.1.1.1.1", $community, $version);
            if ($status != 0) {
                my $msg = "Error occurred while looking up ifIndex for specified ifName $ifName in ifName table: $res";
                $self->{LOGGER}->warn($msg);
            } else {
                foreach my $oid_ref ( @{ $res } ) {
                    my $oid = $oid_ref->[0];
                    my $type = $oid_ref->[1];
                    my $value = $oid_ref->[2];

                    $self->{LOGGER}->debug("$oid = $type: $value($ifName)");
                    if ($value eq $ifName) {
                        if ($oid =~ /1\.3\.6\.1\.2\.1\.31\.1\.1\.1\.1\.(\d+)/x) {
                            $ifIndex = $1;
                        }
                    }
                }
            }

            if (not $ifIndex) {
                my ($status, $res) = snmpwalk($hostname, undef, "1.3.6.1.2.1.2.2.1.2", $community, $version);
                if ($status != 0) {
                    my $msg = "Error occurred while looking up ifIndex for ifName $ifName in ifDescr table: $res";
                    $self->{LOGGER}->warn($msg);
                } else {
                    foreach my $oid_ref ( @{ $res } ) {
                        my $oid = $oid_ref->[0];
                        my $type = $oid_ref->[1];
                        my $value = $oid_ref->[2];

                        $self->{LOGGER}->debug("$oid = $type: $value($ifName)");
                        if ($value eq $ifName) {
                            if ($oid =~ /1\.3\.6\.1\.2\.1\.2\.2\.1\.2\.(\d+)/x) {
                                $ifIndex = $1;
                            }
                        }
                    }
                }
            }

            if (not $ifIndex) {
                my $msg = "Didn't find ifName $ifName in host $hostname";
                $self->{LOGGER}->error($msg);
                return (-1, $msg);
            }
        }

        my $host_agent;

        if (defined $self->{SNMPAGENTS}->{$hostname}) {
            $host_agent = $self->{SNMPAGENTS}->{$hostname};
        }

        $new_agent = perfSONAR_PS::Collectors::LinkStatus::Agent::SNMP->new($status_type, $hostname, $ifIndex, $version, $community, $oid, $host_agent);

        if (not defined $host_agent) {
            $self->{SNMPAGENTS}->{$hostname} = $new_agent->getAgent();
        }
    } elsif ($type eq "tl1" and $agent->findvalue("device_type") and lc($agent->findvalue("device_type")) eq "ome") {
        my $username = $agent->findvalue('username');
        my $password = $agent->findvalue('password');
        my $address = $agent->findvalue('address');
        my $port = $agent->findvalue('port');

        unless ($address and $username and $password) {
            my $msg = "Agent of type 'TL1/OME' is missing elements to access the host. Required: address, username, password";
            $self->{LOGGER}->error($msg);
            return (-1, $msg);
        }

        my $facility_name = $agent->findvalue('facility_name');
        my $facility_name_type = $agent->findvalue('facility_name_type');
        my $facility_type = $agent->findvalue('facility_type');

        unless ($facility_name and $facility_type) {
            my $msg = "Agent of type 'TL1/OME' is missing elements to access the host. Required: facility_name and facility_type";
            $self->{LOGGER}->error($msg);
            return (-1, $msg);
        }
 
        my $tl1agent;

        my $key = $address."|".$port."|".$username."|".$password;

        if (defined $self->{TL1AGENTS}->{$key}) {
            $tl1agent = $self->{TL1AGENTS}->{$key};
        }

        $new_agent = perfSONAR_PS::Collectors::LinkStatus::Agent::TL1::OME->new(
                        type => $status_type,
                        address => $address,
                        port => $port,
                        username => $username,
                        password => $password,
                        agent => $tl1agent,
                        facility_name => $facility_name,
                        facility_name_type => $facility_name_type,
                        facility_type => $facility_type,
                     );

        if (not defined $tl1agent) {
            $self->{TL1AGENTS}->{$key} = $new_agent->agent;
        }   
    } elsif ($type eq "tl1" and $agent->findvalue("device_type") and lc($agent->findvalue("device_type")) eq "hdxc") {
        my $username = $agent->findvalue('username');
        my $password = $agent->findvalue('password');
        my $address = $agent->findvalue('address');
        my $port = $agent->findvalue('port');

        unless ($address and $username and $password) {
            my $msg = "Agent of type 'TL1/OME' is missing elements to access the host. Required: address, username, password";
            $self->{LOGGER}->error($msg);
            return (-1, $msg);
        }

        my $facility_name = $agent->findvalue('facility_name');
        my $facility_name_type = $agent->findvalue('facility_name_type');
        my $facility_type = $agent->findvalue('facility_type');

        unless ($facility_name and $facility_type) {
            my $msg = "Agent of type 'TL1/OME' is missing elements to access the host. Required: facility_name and facility_type";
            $self->{LOGGER}->error($msg);
            return (-1, $msg);
        }
 
        my $tl1agent;

        my $key = $address."|".$port."|".$username."|".$password;

        if (defined $self->{TL1AGENTS}->{$key}) {
            $tl1agent = $self->{TL1AGENTS}->{$key};
        }

        $new_agent = perfSONAR_PS::Collectors::LinkStatus::Agent::TL1::HDXc->new(
                        type => $status_type,
                        address => $address,
                        port => $port,
                        username => $username,
                        password => $password,
                        agent => $tl1agent,
                        facility_name => $facility_name,
                        facility_name_type => $facility_name_type,
                        facility_type => $facility_type,
                     );

        if (not defined $tl1agent) {
            $self->{TL1AGENTS}->{$key} = $new_agent->agent;
        }   
    } elsif ($type eq "tl1" and $agent->findvalue("device_type") and lc($agent->findvalue("device_type")) eq "coredirector") {
        my $username = $agent->findvalue('username');
        my $password = $agent->findvalue('password');
        my $address = $agent->findvalue('address');
        my $port = $agent->findvalue('port');

        unless ($address and $username and $password) {
            my $msg = "Agent of type 'TL1/OME' is missing elements to access the host. Required: address, username, password";
            $self->{LOGGER}->error($msg);
            return (-1, $msg);
        }

        my $facility_name = $agent->findvalue('facility_name');
        my $facility_name_type = $agent->findvalue('facility_name_type');
        my $facility_type = $agent->findvalue('facility_type');

        unless ($facility_name and $facility_type) {
            my $msg = "Agent of type 'TL1/OME' is missing elements to access the host. Required: facility_name and facility_type";
            $self->{LOGGER}->error($msg);
            return (-1, $msg);
        }

        if ($facility_type eq "vlan") { 
            my $vlan_num = $agent->findvalue('vlan');
            $facility_name = $facility_name."|".$vlan_num;
            $facility_name_type = "logical";
        }

        my $tl1agent;

        my $key = $address."|".$port."|".$username."|".$password;

        if (defined $self->{TL1AGENTS}->{$key}) {
            $tl1agent = $self->{TL1AGENTS}->{$key};
        }

        $new_agent = perfSONAR_PS::Collectors::LinkStatus::Agent::TL1::CoreDirector->new(
                        type => $status_type,
                        address => $address,
                        port => $port,
                        username => $username,
                        password => $password,
                        agent => $tl1agent,
                        facility_name => $facility_name,
                        facility_name_type => $facility_name_type,
                        facility_type => $facility_type,
                     );

        if (not defined $tl1agent) {
            $self->{TL1AGENTS}->{$key} = $new_agent->agent;
        }
    } else {
        my $msg = "Unknown agent type: \"$type\"";
        $self->{LOGGER}->error($msg);
        return (-1, $msg);
    }

    unless ($new_agent) {
        return (-1, "Error allocating module");
    }

    # here is where we could pull in the possibility of a mapping from the
    # output of the SNMP/script/whatever to "up, down, degraded, unknown"

    return (0, $new_agent);
}

sub collectMeasurements {
    my($self, $sleeptime) = @_;
    my ($status, $res);

    $self->{LOGGER}->debug("collectMeasurements()");

    ($status, $res) = $self->{CLIENT}->open;
    if ($status != 0) {
        my $msg = "Couldn't open connection to database: $res";
        $self->{LOGGER}->error($msg);
        return (-1, $msg);
    }

    $self->{LOGGER}->debug("TL1: ".Dumper($self->{TL1AGENTS}));

    foreach my $key (keys %{$self->{TL1AGENTS}}) {
        my $agent = $self->{TL1AGENTS}->{$key};

        $agent->connect();
    }

    foreach my $link (@{$self->{ELEMENTS}}) {
        my ($status, $res);

        $self->{LOGGER}->debug("Getting information on link: ".(@{$link->getIDs()}[0]));

        ($status, $res) = $link->measure();
        if ($status != 0) {
            $self->{LOGGER}->warn("Couldn't get information on link: ".(@{$link->getIDs()}[0]));
            next;
        }

        my @link_statuses = @{ $res };

        foreach my $link_id (@{ $link->getIDs() }) {
            my $do_update = 0;

            foreach my $link_status (@link_statuses) {
                $self->{LOGGER}->debug("Updating $link_id: ".$link_status->getTime()." - ".$link_status->getOperState().", ".$link_status->getAdminState());

                if (defined $link_prev_update_status{$link_id} and $link_prev_update_status{$link_id} == 0) {
                    $do_update = 1;
                }

                ($status, $res) = $self->{CLIENT}->updateLinkStatus($link_status->getTime(),
                                                                    $link_id,
                                                                    $link_status->getOperState(),
                                                                    $link_status->getAdminState(),
                                                                    $do_update);
                if ($status != 0) {
                    $self->{LOGGER}->error("Couldn't store link status for link $link_id: $res");
                }

                $link_prev_update_status{$link_id} = $status;
            }
        }
    }

    foreach my $key (keys %{$self->{TL1AGENTS}}) {
        my $agent = $self->{TL1AGENTS}->{$key};

        $agent->disconnect();
    }

    if ($sleeptime) {
        $sleeptime = $self->{CONF}->{"collection_interval"};
    }

    return;
}

1;

__END__

=head1 NAME

perfSONAR_PS::Collectors::LinkStatus - A module that will collect link status
information and store the results into a Link Status MA.

=head1 DESCRIPTION

This module loads a set of links and can be used to collect status information
on those links and store the results into a Link Status MA.

=head1 SYNOPSIS

=head1 DETAILS

This module is meant to be used to periodically collect information about Link
Status. It can do this by running scripts or consulting SNMP servers directly.
It reads a configuration file that contains the set of links to track. It can
then be used to periodically obtain the status and then store the results into
a measurement archive. 

It includes a submodule SNMPAgent that provides a caching SNMP poller allowing
easier interaction with SNMP servers.

=head1 API

=head2 init($self)
    This function initializes the collector. It returns 0 on success and -1
    on failure.

=head2 collectMeasurements($self)
    This function is called by external users to collect and store the
    status for all links.

=head1 SEE ALSO

To join the 'perfSONAR-PS' mailing list, please visit:

https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

https://svn.internet2.edu/svn/perfSONAR-PS

Questions and comments can be directed to the author, or the mailing list.

=head1 VERSION

$Id:$

=head1 AUTHOR

Aaron Brown, E<lt>aaron@internet2.eduE<gt>, Jason Zurawski, E<lt>zurawski@internet2.eduE<gt>

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework along
with this software.  If not, see <http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2004-2007, Internet2 and the University of Delaware

All rights reserved.

=cut

# vim: expandtab shiftwidth=4 tabstop=4
