package SimpleLSBootStrap::ClientDaemonHandler;

use strict;
use warnings;

=head1 NAME

SimpleLSBootStrap::ClientDaemonHandler.pm - Downloads list of lookup services and 
determines which to use

=head1 DESCRIPTION

Downloads list of lookup services and determines which to use

=cut

our $VERSION = 3.3;

use Carp;
use Log::Log4perl qw/get_logger/;
use LWP::UserAgent;
use YAML::Syck;
use URI;
use JSON qw( decode_json);

use fields 'LOGGER', 'CONF', 'NEXT_UPDATE';

=head2 new()

This call instantiates new objects. The object's "init" function must be called
before any interaction can occur.

=cut

sub new {
    my $class = shift;

    my $self = fields::new( $class );

    $self->{LOGGER} = get_logger( $class );
    
    return $self;
}

=head2 init()

This call initialize the fields. Must be called prior to interaction 
with module.

=cut
sub init {
    my ( $self, $conf ) = @_;
    
    $self->{CONF} = $conf;
    $self->{NEXT_UPDATE} = 0;
}

=head2 handle()

Determine the lookup service choice and write to file

=cut
sub handle {
    my ( $self ) = @_;
    
    #Check if we need to run
    my $curr_time = time;
    if ($curr_time < $self->{NEXT_UPDATE}) {
        # Sleep until it's time to run again.
        sleep($self->{NEXT_UPDATE} - $curr_time);
    }
    
    if(time >= $self->{NEXT_UPDATE}){
        $self->{LOGGER}->info(perfSONAR_PS::Utils::NetLogger::format( "SimpleLSBootStrap.ClientDaemonHandler.handle.start"));
        eval{ $self->_find_hosts() };
        if($@){
            $self->{NEXT_UPDATE} = time + $self->{CONF}->{'update_interval'};
            $self->{LOGGER}->error(perfSONAR_PS::Utils::NetLogger::format( "SimpleLSBootStrap.ClientDaemonHandler.handle.end", { status => -1, next_update => $self->{NEXT_UPDATE}, msg => $@ }));
        }else{
            $self->{NEXT_UPDATE} = time + $self->{CONF}->{'update_interval'};
            $self->{LOGGER}->info(perfSONAR_PS::Utils::NetLogger::format( "SimpleLSBootStrap.ClientDaemonHandler.handle.end", { next_update => $self->{NEXT_UPDATE}}));
        }
    }
}

sub _find_hosts {
    my( $self ) = @_;
    
    my $string = YAML::Syck::LoadFile($self->{CONF}->{hosts_file});
    my @hosts = @{$string->{'hosts'}};
    if (!@hosts){
      croak "No hosts in list";
    }
    my $err_msg = '';   
    my $minPriority = 100;
    my $minPriorityHost = "";
    foreach my $host(@hosts){
        my $locator = $host->{'locator'};
        if(!defined $locator){
            $err_msg .= 'No locator for host.';
            next;
        }
        
        #Pull down file
        my $ua = new LWP::UserAgent();
        $ua->agent("SimpleLSBootStrap-v1.0");
        my $http_request = HTTP::Request->new( GET => $locator );
        my $http_response = $ua->request($http_request);
        if (!$http_response->is_success) {
            $err_msg .= "$locator returned response code " . $http_response->code . '.';
            next;
        }
        
        #Convert to JSON
        my $json = new JSON;
        $json = $json->relaxed;
        my $activehostlist;
        eval{ $activehostlist = $json->decode($http_response->content)};
        if(!$activehostlist){
            $err_msg .= "Unable to decode JSON. " . $@;
            next;
        }
        my @activeHosts = @{$activehostlist->{'hosts'}};
        
        #Determine URL
        foreach my $activehost(@activeHosts){
            my $priority = $activehost->{'priority'};
            my $status = $activehost->{'status'};
            
            if(defined $status && $status eq "alive" && defined $priority && $priority<=$minPriority){
                $minPriority = 	$priority;
                $minPriorityHost = $activehost->{'locator'};
                
            }
        }                
    }
    
    #verify we found host
    if(!$minPriorityHost){
        croak "No active LS found: " . $err_msg;
    }
    
    #Output to file
    open FOUT, ">". $self->{CONF}->{output_file} or croak 'Unable to write to ' . $self->{CONF}->{output_file};
    print FOUT $minPriorityHost;
    close FOUT;
}

__END__

=head1 SEE ALSO

L<Archive::Tar>, L<Carp>, L<File::Copy::Recursive>, 
L<File::Path>, L<HTTP::Request>, L<Log::Log4perl>, 
L<LWP::UserAgent>, L<Net::Ping>, L<URI::URL>,
L<perfSONAR_PS::Utils::ParameterValidation>

To join the 'perfSONAR-PS Users' mailing list, please visit:

  https://lists.internet2.edu/sympa/info/perfsonar-ps-users

The perfSONAR-PS subversion repository is located at:

  http://anonsvn.internet2.edu/svn/perfSONAR-PS/trunk

Questions and comments can be directed to the author, or the mailing list.
Bugs, feature requests, and improvements can be directed here:

  http://code.google.com/p/perfsonar-ps/issues/list

=head1 VERSION

$Id: daemon.pl 3949 2010-03-12 18:04:21Z alake $

=head1 AUTHOR

Andy Lake, andy@es.net

=head1 LICENSE

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=head1 COPYRIGHT

Copyright (c) 2010, Internet2

All rights reserved.

=cut
