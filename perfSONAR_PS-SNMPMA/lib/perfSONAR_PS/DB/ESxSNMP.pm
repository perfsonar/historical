package perfSONAR_PS::DB::ESxSNMP;

use fields 'LOGGER', 'PATH', 'NAME', 'DATASOURCES', 'COMMIT', 'SERVER_URL', 'CLIENT';

use strict;
use warnings;

our $VERSION = 0.09;

=head1 NAME

perfSONAR_PS::DB::ESxSNMP - A module that provides a simple API for dealing

=head1 DESCRIPTION

A module that provides a simple API for dealing with data stored in an ESxSNMP
DB.  This module makes ESxSNMP look like any other perfSONAR_PS database.

=cut    

use perfSONAR_PS::DB::ESxSNMP_API;

use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);

use perfSONAR_PS::Common;
use perfSONAR_PS::Utils::ParameterValidation;

use Data::Dumper;
=head2 new($package, { server, name, error })

Create a new ESxSNMP object.  All arguments are optional:

 * server - ESxSNMP DB server to query, format: hostname[:port]
 * error - Flag to allow ESxSNMP to pass back error values

The arguments can be set (and re-set) via the appropriate function calls. 

=cut

sub new {
    my ( $package, @args ) = @_;
    my $parameters = validateParams( @args, { server_url => 0, error => 0 } );

    my $self = fields::new($package);
    $self->{LOGGER} = get_logger("perfSONAR_PS::DB::ESxSNMP");
    $self->{NAME} = "NAME";

    if ( exists $parameters->{server_url} and $parameters->{server_url} ) {
        $self->{SERVER_URL} = $parameters->{server_url};
    }
    if ( exists $parameters->{error} and $parameters->{error} ) {
        if ( $parameters->{error} == 1 ) {
            $self->{LOGGER}->debug("Setting error mode.");
        }
        else {
            undef $ESxSNMPp::error_mode;
            $self->{LOGGER}->debug("Unsetting error mode.");
        }
    }

    $self->{CLIENT} = perfSONAR_PS::DB::ESxSNMP_API->new($self->{SERVER_URL});

    return $self;
}

=head2 setServer($self, { file })

Sets the ESxSNMP filename for the ESxSNMP object.

=cut

sub setServerURL {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { server => 1 } );

    if ( exists $parameters->{server_url} and $parameters->{server_url} ) {
        $self->{SERVER_URL} = $parameters->{server_url};
        return 0;
    } else {
        return -1;
    }
}

=head2 setVariables($self, { dss })

Sets several variables (as a hash reference) in the ESxSNMP object.

=cut

sub setVariables {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { dss => 1 } );

    $self->{DATASOURCES} = \%{ $parameters->{dss} };
    return 0;
}

=head2 setVariable($self, { dss })

Sets a variable value in the ESxSNMP object.

=cut

sub setVariable {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { ds => 1 } );

    $self->{DATASOURCES}->{ $parameters->{ds} } = q{};
    return 0;
}

=head2 setError($self, { error })

Sets the error variable for the ESxSNMP object.

=cut

sub setError {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { error => 1 } );

    if ( $parameters->{error} == 1 ) {
        $ESxSNMPp::error_mode = 'catch';
        $self->{LOGGER}->debug("Setting error mode.");
    }
    else {
        undef $ESxSNMPp::error_mode;
        $self->{LOGGER}->debug("Unsetting error mode.");
    }
    return 0;
}

=head2 getErrorMessage($self, { })

Gets any error returned for this ESxSNMP object.

=cut

sub getErrorMessage {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, {} );

    # XXX:jdugan needs to be implemented
    warn "getErrorMessage not implemented for ESxSNMP";

    return;
}

=head2 openDB($self, { })

Opens a connection to the ESxSNMP DB server.

=cut

sub openDB {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, {} );

    $self->{CLIENT} = perfSONAR_PS::DB::ESxSNMP_API->new($self->{SERVER_URL});

    return 0;
}

=head2 closeDB($self, { })

Closes a connection to the ESxSNMP DB server.

=cut

sub closeDB {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, {} );

    return 0;
}

=head2 info($self, { })

Get info about the given ESxSNMP variable.
 
=cut

sub info {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { } );

    $self->{LOGGER}->warn("ESxSNMP insert not implemented");
    return;
}

=head2 query($self, { name, cf, resolution, start, end })

Query a ESxSNMP with specific times/resolutions.  Returns a ref to a list of
lists of the form ((timestamp0, value0), ..., (timestampN, valueN)).

=cut

sub query {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { name => 1, cf => 1, resolution => 1, start => 1, end => 1 } );

    my %result   = ();
    my @headings = ();
    unless ( $parameters->{cf} ) {
        $self->{LOGGER}->debug("No consolidation function provided.");
    }

    $self->{LOGGER}->info("Booyah! " . $parameters->{name});

    my $q = $parameters->{name} . 
        "?begin=" .  $parameters->{start} .
        "&end=" . $parameters->{end};

        # XXX add cf & resolution
        #$parameters->{cf},
        #$parameters->{resolution});

    $self->{LOGGER}->info("Booyah! " . $q);
    my $answer = $self->{CLIENT}->get_uri($q);
    #$self->{LOGGER}->error(Dumper($answer));

    # XXX improve error handling

    unless($answer && $answer != -1) {
        $self->{LOGGER}->error("unable to fetch data");
        return;
    }

    foreach my $d ( @{$answer->{'data'}} ) {
        $d->[1] *= 8;
    }

    return $answer->{'data'};
}

=head2 insert($self, { time, ds, value })

'Inserts' a time/value pair for a given variable.  These are not inserted
into the ESxSNMP, but will wait until we enter into the commit phase (i.e. by
calling the commit function).  This allows us to stack up a bunch of values
first, and reuse time figures. 

=cut

sub insert {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { time => 1, ds => 1, value => 1 } );

    $self->{LOGGER}->warn("ESxSNMP insert not implemented");

    return 0;
}

=head2 insertCommit($self, { })

'Commits' all outstanding variables time/data pairs for a given ESxSNMP.

=cut

sub insertCommit {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, {} );

    $self->{LOGGER}->warn("ESxSNMP insert not implemented");

    return;
}

=head2 firstValue($self, { }) 

Returns the first value of an ESxSNMP.

=cut

sub firstValue {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, {} );

    $self->{LOGGER}->warn("ESxSNMP firstValue not implemented");
    return;
}

=head2 lastValue($self, { })

Returns the last value of an ESxSNMP. 

=cut

sub lastValue {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, {} );

    $self->{LOGGER}->warn("ESxSNMP lastValue not implemented");
    return;
}

=head2 lastTime($self, { })

Returns the last time the ESxSNMP was updated. 

=cut

sub lastTime {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, {} );

    $self->{LOGGER}->warn("ESxSNMP lastTime not implemented");
    return;
}

1;

__END__

=head1 SYNOPSIS

    use perfSONAR_PS::DB::ESxSNMP;

    my $rrd = new perfSONAR_PS::DB::ESxSNMP( {
      name => "/home/jason/rrd/stout/stout.rrd",
      dss => {'eth0-in'=>"" , 'eth0-out'=>"", 'eth1-in'=>"" , 'eth1-out'=>""},
      error => 1 }
    );

    # or also:
    # 
    # my $rrd = new perfSONAR_PS::DB::ESxSNMP;
    # $rrd->setFile({ path => "/home/jason/rrd/stout/stout.rrd" });
    # $rrd->setPath({ file => "/usr/local/rrdtool/bin/rrdtool" });  
    # $rrd->setVariables({ dss => {'eth0-in'=>"" , 'eth0-out'=>"", 'eth1-in'=>"" , 'eth1-out'=>""} });  
    # $rrd->setVariable({ dss => "eth0-in" });
    # ...
    # $rrd->setError({ error => 1});     

    # For reference, here is the create string for the rrd file:
    #
    # rrdtool create stout.rrd \
    # --start N --step 1 \
    # DS:eth0-in:COUNTER:1:U:U \ 
    # DS:eth0-out:COUNTER:1:U:U \
    # DS:eth1-in:COUNTER:1:U:U \
    # DS:eth1-out:COUNTER:1:U:U \
    # RRA:AVERAGE:0.5:10:60480

    # will also 'open' a connection to a file:
    if($rrd->openDB == -1) {
      print "Error opening database\n";
    }

    my %rrd_result = $rrd->query({
      cf => "AVERAGE", 
      resolution => "", 
      end => "1163525343", 
      start => "1163525373" });

    if($rrd->getErrorMessage) {
      print "Query Error: " , $rrd->getErrorMessage , "; query returned: " , $rrd_result{ANSWER} , "\n";
    }
    else {
      my @keys = keys(%rrd_result);
      foreach $a (sort(keys(%rrd_result))) {
        foreach $b (sort(keys(%{$rrd_result{$a}}))) {
          print $a , " - " , $b , "\t-->" , $rrd_result{$a}{$b} , "<--\n"; 
        }
        print "\n";
      }
    }

    $rrd->insert({ time => "N", ds => "eth0-in", value => "1" });
    $rrd->insert({ time => "N", ds => "eth0-out", value => "2" });
    $rrd->insert({ time => "N", ds => "eth1-in", value => "3" });
    $rrd->insert({ time => "N", ds => "eth1-out", value => "4" });
                  
    my $insert = $rrd->insertCommit;

    if($rrd->getErrorMessage) {
      print "Insert Error: " , $rrd->getErrorMessage , "; insert returned: " , $insert , "\n";
    }

    print "last: " , $rrd->lastValue , "\n";
    if($rrd->getErrorMessage) {
      print "last Error: " , $rrd->getErrorMessage , "\n";
    }

    print "first: " , $rrd->firstValue , "\n";
    if($rrd->getErrorMessage) {
      print "first Error: " , $rrd->getErrorMessage , "\n";
    }
    
    if($rrd->closeDB == -1) {
      print "Error closing database\n";
    }
    
=head1 SEE ALSO

L<ESxSNMP>, L<ESDB>, L<Thrift>, L<Log::Log4perl>, L<Params::Validate>, L<perfSONAR_PS::Common>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list.  Bugs,
feature requests, and improvements can be directed here:

  https://bugs.internet2.edu/jira/browse/PSPS

=head1 VERSION

$Id$

=head1 AUTHOR

Jon Dugan, jdugan@es.net

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

Copyright (c) 2004-2008, Internet2 and the University of Delaware

All rights reserved.

=cut
# vim: expandtab shiftwidth=4 tabstop=4
