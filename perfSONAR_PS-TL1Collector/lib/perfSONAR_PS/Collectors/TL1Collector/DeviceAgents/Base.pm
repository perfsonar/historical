package perfSONAR_PS::Collectors::TL1Collector::DeviceAgents::Base;

use strict;
use warnings;

our $VERSION = 3.1;

=head1 NAME

perfSONAR_PS::Collectors::TL1Collector::DeviceAgents::Base

=head1 DESCRIPTION

TBD

=cut

use Params::Validate qw(:all);
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Utils::ParameterValidation;
use Data::Dumper;

use fields 'POLLING_INTERVAL', 'NEXT_RUNTIME', 'LOGGER', 'IDENTIFIER_PATTERN', 'DATA_CLIENT';

=head2 new($class)

TBD

=cut

sub new {
    my ( $class ) = @_;

    my $self = fields::new( $class );

    $self->{LOGGER} = get_logger( $class );

    return $self;
}

=head2 init( $self, { data_client, polling_interval, identifier_pattern } )

TBD

=cut

sub init {
    my ( $self, @params ) = @_;

    my $args = validateParams(
        @params,
        {
            data_client        => 1,
            polling_interval   => 0,
            identifier_pattern => 0,
        }
    );

    $self->{POLLING_INTERVAL} = $args->{polling_interval};

    unless ( $self->{POLLING_INTERVAL} ) {
        $self->{LOGGER}->warn( "No polling interval set for worker. Defaulting to 60 seconds" );
        $self->{POLLING_INTERVAL} = 60;
    }

    $self->{IDENTIFIER_PATTERN} = $args->{identifier_pattern};
    $self->{DATA_CLIENT}        = $args->{data_client};

    return 0;
}

=head2 run($self)

TBD

=cut

sub run {
    my ( $self ) = @_;

    my $prev_update_successful;
    my %metadata_added    = ();
    my %topology_id_added = ();

    my $initial_pause = $$%30;
    $self->{LOGGER}->debug("Initial pause time: $initial_pause");
    sleep($initial_pause);

    while ( 1 ) {
        if ( $self->{NEXT_RUNTIME} ) {
            $self->{LOGGER}->debug("Sleeping for : ".($self->{NEXT_RUNTIME} - time ));
            sleep( $self->{NEXT_RUNTIME} - time );
        }

        $self->{NEXT_RUNTIME} = time + $self->{POLLING_INTERVAL};

        my ( $status, $res );

        unless ( $self->connect() ) {
            $self->{LOGGER}->error( "Could not connect to host" );
            next;
        }

        my $curr_time = time;

        ( $status, $res ) = $self->check_facilities();
        if ( $status != 0 ) {
            my $msg = "Facilities check failed: $res";
            $self->{LOGGER}->error( $msg );
            next;
        }

        $self->{LOGGER}->debug( "Facilities: " . Dumper( $res ) );
        my $time = time;

        foreach my $counter (@{ $res }) {
            my $metadata = $counter->{metadata};

            unless ( $counter->{metadata}->{urn} ) {
                my $name = $counter->{metadata}->{port_name};
                my $id = $self->{IDENTIFIER_PATTERN};
                $id =~ s/\%facility%/$name/g;
                $metadata->{urn} = $id;
            }
            
            my $key = $self->{DATA_CLIENT}->add_metadata({
                                            data_type => $counter->{data_type},
                                            urn => $metadata->{urn},
                                            host_name => $metadata->{host_name},
                                            port_name => $metadata->{port_name},
                                            direction => $metadata->{direction},
                                            capacity  => $metadata->{capacity},
                                            description => $metadata->{description},
                                        });

            unless ($key) {
                $self->{LOGGER}->error("Couldn't save data of type ".$counter->{data_type}." about element: ".$metadata->{urn}.": $res");
                next;
            }

            if ($metadata->{direction}) {
                $self->{LOGGER}->debug("Key: $key URN: $metadata->{urn} direction: $metadata->{direction} data_type: $counter->{data_type}");
            } else {
                $self->{LOGGER}->debug("Key: $key URN: $metadata->{urn} direction: both data_type: $counter->{data_type}");
            }
            $self->{DATA_CLIENT}->add_data({ metadata_key => $key, time => $time, values => $counter->{values} });
        }

        $self->disconnect();
    }

    return;
}

1;

__END__

=head1 SEE ALSO

L<Params::Validate>, L<Log::Log4perl>,
L<perfSONAR_PS::Utils::ParameterValidation>, L<Data::Dumper>

To join the 'perfSONAR Users' mailing list, please visit:

  https://mail.internet2.edu/wws/info/perfsonar-user

The perfSONAR-PS subversion repository is located at:

  http://anonsvn.internet2.edu/svn/perfSONAR-PS/trunk

Questions and comments can be directed to the author, or the mailing list.
Bugs, feature requests, and improvements can be directed here:

  http://code.google.com/p/perfsonar-ps/issues/list

=head1 VERSION

$Id$

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
