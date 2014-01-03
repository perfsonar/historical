package perfSONAR_PS::MeshConfig::Generators::perfSONARRegularTesting;
use strict;
use warnings;

our $VERSION = 3.1;

use Params::Validate qw(:all);
use Log::Log4perl qw(get_logger);
use Config::General;
use Encode qw(encode);

use utf8;

use perfSONAR_PS::MeshConfig::Generators::Base;

use perfSONAR_PS::RegularTesting::Config;
use perfSONAR_PS::RegularTesting::Test;
use perfSONAR_PS::RegularTesting::Schedulers::Streaming;
use perfSONAR_PS::RegularTesting::Tests::Powstream;
use perfSONAR_PS::RegularTesting::Schedulers::RegularInterval;
use perfSONAR_PS::RegularTesting::Tests::Bwctl;
use perfSONAR_PS::RegularTesting::Tests::Bwtraceroute;
use perfSONAR_PS::RegularTesting::Tests::Bwping;

use Moose;

extends 'perfSONAR_PS::MeshConfig::Generators::Base';

has 'regular_testing_conf'   => (is => 'rw', isa => 'HashRef');

=head1 NAME

perfSONAR_PS::MeshConfig::Generators::perfSONARRegularTesting;

=head1 DESCRIPTION

=head1 API

=cut

my $logger = get_logger(__PACKAGE__);

sub init {
    my ($self, @args) = @_;
    my $parameters = validate( @args, { 
                                         config_file     => 1,
                                         skip_duplicates => 1,
                                      });

    my $config_file     = $parameters->{config_file};
    my $skip_duplicates = $parameters->{skip_duplicates};

    $self->SUPER::init({ config_file => $config_file, skip_duplicates => $skip_duplicates });

    my $config;
    eval {
        my $conf = Config::General->new(-ConfigFile => $self->config_file);
        my %conf = $conf->getall();

        $config = perfSONAR_PS::RegularTesting::Config->parse(\%conf);

        # Remove the existing tests that were added by the mesh configuration
        my @new_tests = ();
        foreach my $test (@{ $config->tests }) {
            next if ($test->added_by_mesh);

            push @new_tests, $test;
        }

        $config->tests(\@new_tests);
    };
    if ($@) {
        my $msg = "Problem initializing pinger landmarks: ".$@;
        $logger->error($msg);
        return (-1, $msg);
    }

    $self->regular_testing_conf($config);

    return (0, "");
}

sub add_mesh_tests {
    my ($self, @args) = @_;
    my $parameters = validate( @args, { mesh => 1, tests => 1, host => 1 } );
    my $mesh  = $parameters->{mesh};
    my $tests = $parameters->{tests};
    my $host  = $parameters->{host};

    my %host_addresses = map { $_ => 1 } @{ $host->addresses };

    my %addresses_added = ();

    my $mesh_id = $mesh->description;
    $mesh_id =~ s/[^A-Za-z0-9_-]/_/g;

    my @tests = ();
    foreach my $test (@$tests) {
        if ($test->disabled) {
            $logger->debug("Skipping disabled test: ".$test->description);
            next;
        }

        $logger->debug("Adding: ".$test->description);

        eval {
            my %sender_targets = ();
            my %receiver_targets = ();

            foreach my $pair (@{ $test->members->source_destination_pairs }) {
                my $matching_hosts = $mesh->lookup_hosts({ addresses => [ $pair->{destination}->{address} ] });
                my $host_properties = $matching_hosts->[0];

                my $sender = $pair->{"source"};
                my $receiver = $pair->{"destination"};

                # skip if we're not a sender or receiver.
                next unless ($host_addresses{$sender->{address}} or $host_addresses{$receiver->{address}});

                # skip if it's a loopback test.
                next if ($host_addresses{$sender->{address}} and $host_addresses{$receiver->{address}});

                # skip if we're 'no_agent'
                next if (($host_addresses{$sender->{address}} and $sender->{no_agent}) or
                           ($host_addresses{$receiver->{address}} and $receiver->{no_agent}));

                if ($self->skip_duplicates) {
                    # Check if a specific test (i.e. same
                    # source/destination/test parameters) has been added
                    # before, and if so, don't add it.
                    my $already_added = $self->__add_test_if_not_added({ 
                                                                         source             => $pair->{source}->{address},
                                                                         destination        => $pair->{destination}->{address},
                                                                         parameters         => $test->parameters,
                                                                     });

                    if ($already_added) {
                        $logger->debug("Test between ".$pair->{source}->{address}." to ".$pair->{destination}->{address}." already exists. Not re-adding");
                        next;
                    }
                }

                if ($host_addresses{$pair->{source}->{address}}) {
                    $receiver_targets{$pair->{source}->{address}} = [] unless $receiver_targets{$pair->{source}->{address}};
                    push @{ $receiver_targets{$pair->{source}->{address}} }, $pair->{destination}->{address};
                }

                if ($host_addresses{$pair->{destination}->{address}}) {
                    $sender_targets{$pair->{destination}->{address}} = [] unless $receiver_targets{$pair->{destination}->{address}};
                    push @{ $sender_targets{$pair->{destination}->{address}} }, $pair->{source}->{address};
                }
            }

            # Produce a nicer looking config file if the sender and receiver set are the same
            my $same_targets = 1;
            foreach my $target (keys %receiver_targets) {
                next if $sender_targets{$target};

                $same_targets = 0;
                last;
            }

            foreach my $target (keys %sender_targets) {
                next if $receiver_targets{$target};

                $same_targets = 0;
                last;
            }

            if ($same_targets) {
                my ($status, $res) = $self->__build_tests({ test => $test, targets => \%receiver_targets, target_receives => 1, target_sends => 1 });
                if ($status != 0) {
                    die("Problem creating tests: ".$res);
                }

                push @tests, @$res;
            }
            else {
                my ($status, $res) = $self->__build_tests({ test => $test, targets => \%receiver_targets, target_receives => 1 });
                if ($status != 0) {
                    die("Problem creating tests: ".$res);
                }

                push @tests, @$res;

                ($status, $res) = $self->__build_tests({ test => $test, targets => \%sender_targets, target_sends => 1 });
                if ($status != 0) {
                    die("Problem creating tests: ".$res);
                }
    
                push @tests, @$res;
            }

        };
        if ($@) {
            die("Problem adding test ".$test->description.": ".$@);
        }
    }

    push @{ $self->regular_testing_conf->{test} }, @tests;

    return;
}

sub __build_tests {
    my ($self, @args) = @_;
    my $parameters = validate( @args, { test => 1, targets => 1, target_sends => 0, target_receives => 0 });
    my $test = $parameters->{test};
    my $targets = $parameters->{targets};
    my $target_sends = $parameters->{target_sends};
    my $target_receives = $parameters->{target_receives};

    my @tests = ();
    foreach my $local_address (keys %{ $targets }) {
        my $test_obj = perfSONAR_PS::RegularTesting::Test->new();
        $test_obj->added_by_mesh(1);
        $test_obj->description($test->description) if $test->description;
        $test_obj->local_address($local_address);

        my @targets = ();
        foreach my $target (@{ $targets->{$local_address} }) {
            my $target_obj = perfSONAR_PS::RegularTesting::Target->new();
            $target_obj->address($target);
            push @targets, $target_obj;
        }
        $test_obj->targets(\@targets);

        my ($schedule, $parameters);

        if ($test->parameters->type eq "pinger") {
            $parameters = perfSONAR_PS::RegularTesting::Tests::Bwping->new();

            $parameters->packet_count($test->parameters->packet_count) if $test->parameters->packet_count;
            $parameters->packet_length($test->parameters->packet_size) if $test->parameters->packet_size;
            $parameters->packet_ttl($test->parameters->packet_ttl) if $test->parameters->packet_ttl;
            $parameters->inter_packet_time($test->parameters->inter_packet_time) if $test->parameters->inter_packet_time;;
            $parameters->force_ipv4($test->parameters->ipv4_only) if $test->parameters->ipv4_only;
            $parameters->force_ipv6($test->parameters->ipv6_only) if $test->parameters->ipv6_only;

            $schedule   = perfSONAR_PS::RegularTesting::Schedulers::RegularInterval->new();
            $schedule->interval($test->parameters->test_interval);
        }
        elsif ($test->parameters->type eq "traceroute") {
            $parameters = perfSONAR_PS::RegularInterval::Tests::Bwtraceroute->new();

            $parameters->packet_length($test->parameters->packet_size) if $test->parameters->packet_size;
            $parameters->packet_first_ttl($test->parameters->first_ttl) if $test->parameters->first_ttl;
            $parameters->packet_last_ttl($test->parameters->max_ttl) if $test->parameters->max_ttl;
            $parameters->force_ipv4($test->parameters->ipv4_only) if $test->parameters->ipv4_only;
            $parameters->force_ipv6($test->parameters->ipv6_only) if $test->parameters->ipv6_only;

            $schedule   = perfSONAR_PS::RegularTesting::Schedulers::RegularInterval->new();
            $schedule->interval($test->parameters->test_interval) if $test->parameters->test_interval;
        }
        elsif ($test->parameters->type eq "perfsonarbuoy/bwctl") {
            $parameters = perfSONAR_PS::RegularTesting::Tests::Bwctl->new();
            $parameters->use_udp($test->parameters->protocol eq "udp"?1:0);
            # $test{parameters}->{streams}  = $test->parameters->streams; # XXX: needs to support streams
            $parameters->duration($test->parameters->duration) if $test->parameters->duration;
            $parameters->udp_bandwidth($test->parameters->udp_bandwidth) if $test->parameters->udp_bandwidth;
            $parameters->buffer_length($test->parameters->buffer_length) if $test->parameters->buffer_length;
            $parameters->force_ipv4($test->parameters->ipv4_only) if $test->parameters->ipv4_only;
            $parameters->force_ipv6($test->parameters->ipv6_only) if $test->parameters->ipv6_only;

            $schedule   = perfSONAR_PS::RegularTesting::Schedulers::RegularInterval->new();
            $schedule->interval($test->parameters->test_interval) if $test->parameters->test_interval;
        }
        elsif ($test->parameters->type eq "perfsonarbuoy/owamp") {
            $parameters = perfSONAR_PS::RegularTesting::Tests::Powstream->new();
            $parameters->resolution($test->parameters->sample_count * $test->parameters->packet_interval) if $test->parameters->sample_count * $test->parameters->packet_interval;
            $parameters->inter_packet_time($test->parameters->packet_interval) if $test->parameters->packet_interval;
            $parameters->force_ipv4($test->parameters->ipv4_only) if $test->parameters->ipv4_only;
            $parameters->force_ipv6($test->parameters->ipv6_only) if $test->parameters->ipv6_only;

            $schedule = perfSONAR_PS::RegularInterval::Schedulers::Streaming->new();
        }

        if ($target_sends and not $target_receives) {
            $parameters->receive_only(1);
        }

        if ($target_receives and not $target_sends) {
            $parameters->send_only(1);
        }

        $test_obj->parameters($parameters);
        $test_obj->schedule($schedule);

        push @tests, $test_obj;
    }

    return (0, \@tests);
}

sub get_regular_testing_conf {
    my ($self, @args) = @_;
    my $parameters = validate( @args, { });

    my $output;

    return $self->__generate_config_general(undef, $self->regular_testing_conf, 0);
}

1;

__END__

=head1 SEE ALSO

To join the 'perfSONAR Users' mailing list, please visit:

  https://mail.internet2.edu/wws/info/perfsonar-user

The perfSONAR-PS subversion repository is located at:

  http://anonsvn.internet2.edu/svn/perfSONAR-PS/trunk

Questions and comments can be directed to the author, or the mailing list.
Bugs, feature requests, and improvements can be directed here:

  http://code.google.com/p/perfsonar-ps/issues/list

=head1 VERSION

$Id: Base.pm 3658 2009-08-28 11:40:19Z aaron $

=head1 AUTHOR

Aaron Brown, aaron@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework
along with this software.  If not, see
<http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2004-2009, Internet2 and the University of Delaware

All rights reserved.

=cut

# vim: expandtab shiftwidth=4 tabstop=4
