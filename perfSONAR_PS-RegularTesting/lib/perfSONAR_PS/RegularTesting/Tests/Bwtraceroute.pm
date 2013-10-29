package perfSONAR_PS::RegularTesting::Tests::Bwtraceroute;

use strict;
use warnings;

our $VERSION = 3.4;

use IPC::Run qw( start pump );
use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);
use File::Temp qw(tempdir);

use perfSONAR_PS::RegularTesting::Results::TracerouteTest;

use perfSONAR_PS::RegularTesting::Parsers::Bwctl qw(parse_bwctl_output);

use Moose;

extends 'perfSONAR_PS::RegularTesting::Tests::BwctlBase';

has 'bwtraceroute_cmd' => (is => 'rw', isa => 'Str', default => '/usr/bin/bwtraceroute');
has 'tool' => (is => 'rw', isa => 'Str', default => 'traceroute');
has 'packet_length' => (is => 'rw', isa => 'Int');
has 'packet_first_ttl' => (is => 'rw', isa => 'Int', );
has 'packet_max_ttl' => (is => 'rw', isa => 'Int', );

my $logger = get_logger(__PACKAGE__);

override 'type' => sub { "bwtraceroute" };

override 'build_cmd' => sub {
    my ($self, @args) = @_;
    my $parameters = validate( @args, {
                                         source => 1,
                                         destination => 1,
                                         schedule => 0,
                                      });
    my $source         = $parameters->{source};
    my $destination    = $parameters->{destination};
    my $schedule       = $parameters->{schedule};

    my @cmd = ();
    push @cmd, $self->bwtraceroute_cmd;

    # Add the parameters from the parent class
    push @cmd, super();

    # XXX: need to set interpacket time

    push @cmd, ( '-F', $self->packet_first_ttl ) if $self->packet_first_ttl;
    push @cmd, ( '-M', $self->packet_max_ttl ) if $self->packet_max_ttl;
    push @cmd, ( '-l', $self->packet_length ) if $self->packet_length;

    # Prevent traceroute from doing DNS lookups since Net::Traceroute doesn't
    # like them...
    push @cmd, ( '-y', 'a' );

    return @cmd;
};

override 'build_results' => sub {
    my ($self, @args) = @_;
    my $parameters = validate( @args, { 
                                         source => 1,
                                         destination => 1,
                                         schedule => 0,
                                         output => 1,
                                      });
    my $source         = $parameters->{source};
    my $destination    = $parameters->{destination};
    my $schedule       = $parameters->{schedule};
    my $output         = $parameters->{output};

    my $results = perfSONAR_PS::RegularTesting::Results::TracerouteTest->new();

    # Fill in the information we know about the test
    $results->source($self->build_endpoint(address => $source, protocol => "icmp" ));
    $results->destination($self->build_endpoint(address => $destination, protocol => "icmp" ));

    $results->packet_size($self->packet_length);
    $results->packet_first_ttl($self->packet_max_ttl);
    $results->packet_max_ttl($self->packet_max_ttl);

    # Parse the bwctl output, and add it in
    my $bwctl_results = parse_bwctl_output({ stdout => $output, tool_type => $self->tool });

    $results->source->address($bwctl_results->{source}) if $bwctl_results->{source};
    $results->destination->address($bwctl_results->{destination}) if $bwctl_results->{destination};

    my @hops = ();
    if ($bwctl_results->{results}->{hops}) {
        foreach my $hop_desc (@{ $bwctl_results->{results}->{hops} }) {
            my $hop = perfSONAR_PS::RegularTesting::Results::TracerouteTestHop->new();
            $hop->ttl($hop_desc->{ttl}) if defined $hop_desc->{ttl};
            $hop->address($hop_desc->{hop}) if defined $hop_desc->{hop};
            $hop->query_number($hop_desc->{queryNum}) if defined $hop_desc->{queryNum};
            $hop->delay($hop_desc->{delay}) if defined $hop_desc->{delay};
            $hop->error($hop_desc->{error}) if defined $hop_desc->{error};
            push @hops, $hop;
        }
    }

    $results->hops(\@hops);

    if ($bwctl_results->{error}) {
        $results->error($bwctl_results->{error});
    }
    elsif ($bwctl_results->{results}->{error}) {
        $results->error($bwctl_results->{results}->{error});
    }

    $results->test_time($bwctl_results->{start_time});

    $results->raw_results($output);

    use Data::Dumper;
    $logger->debug("Results: ".Dumper($results->unparse));

    return $results;
};

1;
