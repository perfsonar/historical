package perfSONAR_PS::RegularTesting::Tests::Powstream;

use strict;
use warnings;

our $VERSION = 3.4;

use IPC::Run qw( start pump );
use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);
use File::Temp qw(tempdir);
use File::Path qw(rmtree);

use POSIX ":sys_wait_h";

use Data::Validate::IP qw(is_ipv4);
use Data::Validate::Domain qw(is_hostname);
use Net::IP;

use perfSONAR_PS::RegularTesting::Utils::CmdRunner;
use perfSONAR_PS::RegularTesting::Utils::CmdRunner::Cmd;

use perfSONAR_PS::RegularTesting::Utils qw(owptime2datetime);

use perfSONAR_PS::RegularTesting::Parsers::Owamp qw(parse_owamp_summary_file);
use perfSONAR_PS::RegularTesting::Results::LatencyTest;
use perfSONAR_PS::RegularTesting::Results::LatencyTestDatum;

use Moose;

extends 'perfSONAR_PS::RegularTesting::Tests::Base';

has 'powstream_cmd'     => (is => 'rw', isa => 'Str', default => '/usr/bin/powstream');
has 'owstats_cmd'       => (is => 'rw', isa => 'Str', default => '/usr/bin/owstats');
has 'send_only'         => (is => 'rw', isa => 'Bool');
has 'receive_only'      => (is => 'rw', isa => 'Bool');
has 'force_ipv4'        => (is => 'rw', isa => 'Bool');
has 'force_ipv6'        => (is => 'rw', isa => 'Bool');
has 'resolution'        => (is => 'rw', isa => 'Int', default => 60);
has 'packet_length'     => (is => 'rw', isa => 'Int', default => 0);
has 'inter_packet_time' => (is => 'rw', isa => 'Num', default => 0.1);

has '_individual_tests' => (is => 'rw', isa => 'ArrayRef[HashRef]');
has '_runner'           => (is => 'rw', isa => 'perfSONAR_PS::RegularTesting::Utils::CmdRunner');

my $logger = get_logger(__PACKAGE__);

override 'type' => sub { "powstream" };

override 'allows_bidirectional' => sub { 1 };

override 'handles_own_scheduling' => sub { 1; };

override 'valid_schedule' => sub {
    my ($self, @args) = @_;
    my $parameters = validate( @args, {
                                         schedule => 0,
                                      });
    my $schedule = $parameters->{schedule};

    return 1 if ($schedule->type eq "streaming");

    return;
};

sub get_individual_tests {
    my ($self, @args) = @_;
    my $parameters = validate( @args, {
                                         test => 1,
                                      });
    my $test              = $parameters->{test};

    my @tests = ();
 
    # Build the set of set of tests that make up this bwctl test
    foreach my $target (@{ $test->targets }) {
        unless ($test->parameters->send_only) {
            push @tests, { target => $target->address, receiver => 1 };
        }
        unless ($test->parameters->receive_only) {
            push @tests, { target => $target->address, sender => 1 };
        }
    }

    return @tests;
}

override 'init_test' => sub {
    my ($self, @args) = @_;
    my $parameters = validate( @args, {
                                         test   => 1,
                                         config => 1,
                                      });
    my $test   = $parameters->{test};
    my $config = $parameters->{config};

    my @individual_tests = $self->get_individual_tests({ test => $test });

    foreach my $test (@individual_tests) {
        eval {
            $test->{results_directory} = tempdir($config->test_result_directory."/owamp_XXXXX");
        };
        if ($@) {
            die("Couldn't create directory to store results: ".$@);
        }
    }

    $self->_individual_tests(\@individual_tests);

    return;
};

override 'run_test' => sub {
    my ($self, @args) = @_;
    my $parameters = validate( @args, {
                                         test           => 1,
                                         handle_results => 1,
                                      });
    my $test              = $parameters->{test};
    my $handle_results    = $parameters->{handle_results};

    my @cmds = ();
    foreach my $individual_test (@{ $self->_individual_tests }) {
        # Calculate the total number of packets from the resolution
        my $packets = $self->resolution / $self->inter_packet_time;

        my @cmd = ();
        push @cmd, $self->powstream_cmd;
        push @cmd, '-4' if $self->force_ipv4;
        push @cmd, '-6' if $self->force_ipv6;
        push @cmd, ( '-p', '-d', $individual_test->{results_directory} );
        push @cmd, ( '-c', $packets );
        push @cmd, ( '-s', $self->packet_length ) if $self->packet_length;
        push @cmd, ( '-i', $self->inter_packet_time ) if $self->inter_packet_time;
        if ($test->local_address) {
            push @cmd, ( '-S', $test->local_address );
        }
        elsif ($test->local_interface) {
            push @cmd, ( '-S', $test->local_interface );
        }
        push @cmd, '-t' if $individual_test->{sender};
        push @cmd, $individual_test->{target};

        my $cmd = perfSONAR_PS::RegularTesting::Utils::CmdRunner::Cmd->new();

        $cmd->cmd(\@cmd);
        $cmd->private($individual_test);
        $cmd->restart_interval(300);
        $cmd->result_cb(sub {
            my ($cmd, @args) = @_;
            my $parameters = validate( @args, { stdout => 0, stderr => 0 });
            my $stdout = $parameters->{stdout};
            my $stderr = $parameters->{stderr};

            $self->handle_output({ test => $test, individual_test => $individual_test, stdout => $stdout, stderr => $stderr, handle_results => $handle_results });
        });

        push @cmds, $cmd;
    }

    $self->_runner(perfSONAR_PS::RegularTesting::Utils::CmdRunner->new());
    $self->_runner->init({ cmds => \@cmds });
    $self->_runner->run();

    return;
};

override 'stop_test' => sub {
    my ($self) = @_;

    $self->_runner->stop();

    # Remove the directories we created
    foreach my $test (@{ $self->_individual_tests }) {
        if (-d $test->{results_directory}) {
           eval {
               rmtree($test->{results_directory});
           };
           if ($@) {
               $logger->error("Couldn't remove: ".$test->{results_directory}.": ".$@);
           }
           else {
               $logger->debug("Removed: ".$test->{results_directory});
           }
        }
    }
};

sub handle_output {
    my ($self, @args) = @_;
    my $parameters = validate( @args, { test => 1, individual_test => 1, stdout => 0, stderr => 0, handle_results => 1 });
    my $test            = $parameters->{test};
    my $individual_test = $parameters->{individual_test};
    my $stdout          = $parameters->{stdout};
    my $stderr          = $parameters->{stderr};
    my $handle_results  = $parameters->{handle_results};

    foreach my $file (@$stdout) {
        ($file) = ($file =~ /(.*)/); # untaint the silly filename

        chomp($file);

        unless ($file =~ /(.*).(sum)$/) {
            unlink($file);
            next;
        }

        my $source = $individual_test->{sender}?$test->local_address:$individual_test->{target};
        my $destination = $individual_test->{receiver}?$individual_test->{target}:$test->local_address;


        my $results = $self->build_results({
                                             source => $source,
                                             destination => $destination,
                                             schedule => $test->schedule,
                                             summary_file => $file,
                                          });
        unless ($results) {
            $logger->error("Problem parsing test results");
            next;
        }
        else {
            eval {
                $handle_results->(results => $results);
            };
            if ($@) {
                $logger->error("Problem saving results: $results");
            }
        }

        unlink($file);
    }

    return;
}

sub build_results {
    my ($self, @args) = @_;
    my $parameters = validate( @args, { 
                                         source => 1,
                                         destination => 1,
                                         schedule => 0,
                                         summary_file => 1,
                                      });
    my $source         = $parameters->{source};
    my $destination    = $parameters->{destination};
    my $schedule       = $parameters->{schedule};
    my $summary_file   = $parameters->{summary_file};

    my $summary         = parse_owamp_summary_file({ summary_file => $summary_file });

    unless ($summary) {
        $logger->error("Problem parsing test results");
        return;
    }

    use Data::Dumper;
    #$logger->debug("Raw output: ".Dumper($raw));
    $logger->debug("Summary output: ".Dumper($summary));

    my $results = perfSONAR_PS::RegularTesting::Results::LatencyTest->new();

    # Fill in the information we know about the test
    $results->source($self->build_endpoint(address => $source, protocol => "udp" ));
    $results->destination($self->build_endpoint(address => $destination, protocol => "udp" ));

    $results->packet_count($self->resolution/$self->inter_packet_time);
    $results->packet_size($self->packet_length);
    $results->inter_packet_time($self->inter_packet_time);

    my $from_addr = $summary->{FROM_ADDR};
    my $to_addr = $summary->{TO_ADDR};

    $from_addr =~ s/%.*//;
    $to_addr =~ s/%.*//;

    $results->source->address($from_addr) if $from_addr;
    $results->destination->address($to_addr) if $to_addr;
    $results->start_time(owptime2datetime($summary->{START_TIME}));
    $results->end_time(owptime2datetime($summary->{END_TIME}));


    # Add the summarized results since adding the raw results is absurdly
    # expensive for powstream tests...
    $results->packets_sent($summary->{SENT});
    $results->packets_received($summary->{SENT} - $summary->{LOST});
    $results->duplicate_packets($summary->{DUPS});

    $results->histogram_bucket_size($summary->{BUCKET_WIDTH});

    my %delays = ();
    foreach my $bucket (keys %{ $summary->{BUCKETS} }) {
        $delays{$bucket * $summary->{BUCKET_WIDTH}} = $summary->{BUCKETS}->{$bucket};
    }
    $results->delay_histogram(\%delays);

    my %ttls = ();
    %ttls = %{ $summary->{TTLBUCKETS} } if $summary->{TTLBUCKETS};
    $results->ttl_histogram(\%ttls);

    $results->raw_results("");

    # XXX: look into error conditions

    # XXX: I'm guessing the raw results should be the owp? I'm dunno
    $results->raw_results("");

    use Data::Dumper;
    $logger->debug("Results: ".Dumper($results->unparse));

    return $results;
};

sub build_endpoint {
    my ($self, @args) = @_;
    my $parameters = validate( @args, { 
                                         address  => 1,
                                         port     => 0,
                                         protocol => 0,
                                      });
    my $address        = $parameters->{address};
    my $port           = $parameters->{port};
    my $protocol       = $parameters->{protocol};

    my $endpoint = perfSONAR_PS::RegularTesting::Results::Endpoint->new();

    if ( is_ipv4( $address ) or 
         &Net::IP::ip_is_ipv6( $address ) ) {
        $endpoint->address($address);
    }
    else {
        $endpoint->hostname($address);
    }

    $endpoint->port($port) if $port;
    $endpoint->protocol($protocol) if $protocol;

    return $endpoint;
}

1;
