package perfSONAR_PS::DB::Cricket;

use fields 'LOGGER', 'FILE', 'STORE', 'RRDTOOL', 'CRICKET_HOME', 'CRICKET_INSTALL', 'CRICKET_DATA', 'CRICKET_CONFIG';

use strict;
use warnings;

our $VERSION = 0.10;

use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);

use perfSONAR_PS::ParameterValidation;

=head1 NAME

Cricket.pm - Module used to interact with the cricket network monitoring system.

=head1 DESCRIPTION

This module acts as a conduit between the format installed via cricket, and the required perfSONAR 
specification.  The overall flow is to find the cricket environment, read the necessary 
configuration files, and finally generate a store file that may be used by the SNMP MA.


=head2 new($package, { file })

Create a new object.  

=cut

sub new {
    my ( $package, @args ) = @_;
    my $parameters = validateParams( @args, { conf => 0, file => 0, home => 1, install => 1, data => 1, config => 1 } );

    my $self = fields::new($package);
    $self->{STORE} = q{}; 
    $self->{RRDTOOL} = "/usr/bin/rrdtool"; 
    $self->{LOGGER} = get_logger("perfSONAR_PS::DB::Cricket");
    if ( exists $parameters->{file} and $parameters->{file} ) {
        $self->{FILE} = $parameters->{file};
    }

    $self->{CRICKET_HOME} = $parameters->{home};
    $self->{CRICKET_INSTALL} = $parameters->{install};
    $self->{CRICKET_DATA} = $parameters->{data};
    $self->{CRICKET_CONFIG} = $parameters->{config};

    # Fake a 'use lib' (N.B. that use lib is evaluated at compile time, we
    #  don't want that here since this is based on a configuration option
    unshift @INC, $self->{CRICKET_INSTALL}."/lib";
    
    # Try To use the cricket-conf script, note that its related to the specified
    #  directories
    eval "require '$self->{CRICKET_INSTALL}/cricket-conf.pl'";
    if ( !$Common::global::gInstallRoot && -l $0 ) {
        eval {
            my $link = readlink($0);
            my $dir = (($link =~ m:^(.*/):)[0] || "./") . ".";
            require "$dir/cricket-conf.pl";
        }
    }
    eval "require '/home/cricket/cricket/cricket-conf.pl'" unless $Common::global::gInstallRoot;
    
    # Finally set some other values, note that avoiding 'use' is really a pain
    #  in this case
    $Common::global::gInstallRoot ||= $self->{CRICKET_INSTALL};
    $Common::global::gConfigRoot ||= $self->{CRICKET_CONFIG};
    require ConfigTree::Cache;

    return $self;
}

=head2 setFile($self, { file })

set the output store file.

=cut

sub setFile {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { file => 1 } );

    if ( $parameters->{file} =~ m/\.xml$/mx ) {
        $self->{FILE} = $parameters->{file};
        return 0;
    }
    else {
        $self->{LOGGER}->error("Cannot set filename.");
        return -1;
    }
}

=head2 openDB($self, {  })

Open the connection to the cacti databases, iterate through making the store.xml
file.

=cut

sub openDB {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, {  } );

    $Common::global::gCT = new ConfigTree::Cache;
    my $gCT = $Common::global::gCT;
    $gCT->Base($Common::global::gConfigRoot);

    if ( not $gCT->init() ) {
        $self->{LOGGER}->error("Failed to open compiled config tree from $Common::global::gConfigRoot/config.db: $!");
    }

    my $gError = '';
    my($recomp, $why) = $gCT->needsRecompile();
    if ($recomp) {
        $gError .= "Config tree needs to be recompiled: $why";
    }

    my $dataDir = "$ENV{CRICKET_HOME}/cricket-data";

    my %master = ();
    foreach my $thing (keys %{$gCT}) {
        if($thing eq "DbRef") {	
            foreach my $thing2 (keys %{$gCT->{$thing}}) {
                if($thing2 =~ m/^d.*(switch|router)-interfaces\// and !($thing2 =~ m/chassis-generic/)) {
                    my @line = split(/:/, $thing2);
                    $master{$dataDir.$line[1]}->{$line[4]} = $gCT->{$thing}->{$thing2};
                }
            }
        }
    }    

    my $rrd = new perfSONAR_PS::DB::RRD( { path => $self->{"RRDTOOL"}, error => 1 } );    
    $rrd->openDB;

    $self->{STORE} .= $self->printHeader();
    my $counter = 0;
    foreach my $item (keys %master) {
        if(!($item =~ m/\.sc07\.org$/)) {
# XXX 8/4/08
# HACK - need to address this...
            (my $temp = $item) =~ s/$dataDir\/(router|switch)-interfaces\///;

            my @address = split(/\//, $temp);

# Should use an html cleanser
            (my $des = $master{$item}->{"long-desc"}) =~ s/<BR>/ /g;
            $des =~ s/&/&amp;/g;
            $des =~ s/</&lt;/g;
            $des =~ s/>/&gt;/g;
            $des =~ s/'/&apos;/g;
            $des =~ s/"/&quot;/g;

            my $okChar = '-a-zA-Z0-9_.@\s';
            $des =~  s/[^$okChar]/ /go;

            (my $des2 = $master{$item}->{"short-desc"}) =~ s/<BR>/ /g;
            $des2 =~ s/&/&amp;/g;
            $des2 =~ s/</&lt;/g;
            $des2 =~ s/>/&gt;/g;
            $des2 =~ s/'/&apos;/g;
            $des2 =~ s/"/&quot;/g;
            $des2 =~  s/[^$okChar]/ /go;

            $self->{STORE} .= $self->printInterface( { ipAddress => $master{$item}->{"ip"}, rrddb => $rrd, id => $counter, hostName => $address[0], ifName => $master{$item}->{"interface-name"}, direction => "in", capacity => $master{$item}->{"rrd-max"}, des => $des, des2 => $des2, file => $item, ds => "ds0" } );
            $self->{STORE} .= $self->printInterface( { ipAddress => $master{$item}->{"ip"}, rrddb => $rrd, id => $counter, hostName => $address[0], ifName => $master{$item}->{"interface-name"},direction => "out", capacity => $master{$item}->{"rrd-max"}, des => $des, des2 => $des2, file => $item, ds => "ds1" } );
            $counter++;
        }
    }
    $self->{STORE} .=  $self->printFooter();
    $rrd->closeDB;

    return 0;
}

=head2 printHeader($self, { })

Print out the store header

=cut

sub printHeader {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, {  } );
    
    my $output = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
    $output .= "<nmwg:store  xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"\n";
    $output .= "             xmlns:netutil=\"http://ggf.org/ns/nmwg/characteristic/utilization/2.0/\"\n";
    $output .= "             xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\"\n";
    $output .= "             xmlns:snmp=\"http://ggf.org/ns/nmwg/tools/snmp/2.0/\">\n\n";
    return $output;
}

=head2 printInterface($self, { })

Print out the interface direction

=cut

sub printInterface {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, { rrddb => 0, id => 1, hostName => 1, ifName => 1, ipAddress => 0, direction => 1, capacity => 1, des => 1, des2 => 0, file => 1, ds => 1 } );

    my $output = "  <nmwg:metadata xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\" id=\"metadata-".$parameters->{direction}."-".$parameters->{id}."\">\n";  
    $output .= "    <netutil:subject xmlns:netutil=\"http://ggf.org/ns/nmwg/characteristic/utilization/2.0/\" id=\"subject-".$parameters->{direction}."-".$parameters->{id}."\">\n";
    $output .= "      <nmwgt:interface xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\">\n";  
    $output .= "        <nmwgt:ipAddress>".$parameters->{ipAddress}."</nmwgt:ipAddress>\n" if $parameters->{ipAddress};
    $output .= "        <nmwgt:hostName>".$parameters->{hostName}."</nmwgt:hostName>\n" if $parameters->{hostName};
    $output .= "        <nmwgt:ifName>".$parameters->{ifName}."</nmwgt:ifName>\n" if $parameters->{ifName};
    $output .= "        <nmwgt:ifIndex>".$parameters->{ifName}."</nmwgt:ifIndex>\n" if $parameters->{ifIndex};
    $output .= "        <nmwgt:direction>".$parameters->{direction}."</nmwgt:direction>\n" if $parameters->{direction};
    if ( $parameters->{capacity} ) {
        if($parameters->{capacity} eq "4294967295") {
            $output .= "        <nmwgt:capacity>10000000000</nmwgt:capacity>\n";
        }  
        else {
            $output .= "        <nmwgt:capacity>".$parameters->{capacity}."</nmwgt:capacity>\n";
        } 
    }
    $output .= "        <nmwgt:description>".$parameters->{des}."</nmwgt:description>\n" if $parameters->{des}; 
    if ( $parameters->{des2} ) {
        $output .= "        <nmwgt:ifDescription>".$parameters->{des2}."</nmwgt:ifDescription>\n";
    } 
    else { 
        $output .= "        <nmwgt:ifDescription>".$parameters->{des}."</nmwgt:ifDescription>\n" if $parameters->{des};
    }
    $output .= "      </nmwgt:interface>\n";  
    $output .= "    </netutil:subject>\n";
    $output .= "    <nmwg:eventType>http://ggf.org/ns/nmwg/tools/snmp/2.0</nmwg:eventType>\n";
    $output .= "    <nmwg:eventType>http://ggf.org/ns/nmwg/characteristic/utilization/2.0</nmwg:eventType>\n";
    $output .= "    <nmwg:parameters id=\"parameters-".$parameters->{direction}."-".$parameters->{id}."\">\n";
    $output .= "      <nmwg:parameter name=\"supportedEventType\">http://ggf.org/ns/nmwg/tools/snmp/2.0</nmwg:parameter>\n";
    $output .= "      <nmwg:parameter name=\"supportedEventType\">http://ggf.org/ns/nmwg/characteristic/utilization/2.0</nmwg:parameter>\n";
    $output .= "    </nmwg:parameters>\n";
    $output .= "  </nmwg:metadata>\n\n";

    $output .= "  <nmwg:data xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\" id=\"data-".$parameters->{direction}."-".$parameters->{id}."\" metadataIdRef=\"metadata-".$parameters->{direction}."-".$parameters->{id}."\">\n";
    $output .= "    <nmwg:key id=\"key-".$parameters->{direction}."-".$parameters->{id}."\">\n";
    $output .= "      <nmwg:parameters id=\"pkey-".$parameters->{direction}."-".$parameters->{id}."\">\n";
    $output .= "        <nmwg:parameter name=\"supportedEventType\">http://ggf.org/ns/nmwg/tools/snmp/2.0</nmwg:parameter>\n";
    $output .= "        <nmwg:parameter name=\"supportedEventType\">http://ggf.org/ns/nmwg/characteristic/utilization/2.0</nmwg:parameter>\n";
    $output .= "        <nmwg:parameter name=\"type\">rrd</nmwg:parameter>\n";
    $output .= "        <nmwg:parameter name=\"file\">".$parameters->{file}.".rrd</nmwg:parameter>\n";
    $output .= "        <nmwg:parameter name=\"valueUnits\">Bps</nmwg:parameter>\n";
    $output .= "        <nmwg:parameter name=\"dataSource\">".$parameters->{ds}."</nmwg:parameter>\n";
   
    if ( exists $parameters->{rrddb} ) {
        $parameters->{rrddb}->setFile( { file => $parameters->{file}.".rrd" } );
        my $rrd_result = $parameters->{rrddb}->info();
        unless ( $parameters->{rrddb}->getErrorMessage ) {
            my %lookup = ();
            foreach my $rra ( sort keys %{$rrd_result->{"rra"}} ) {
                push @{$lookup{$rrd_result->{"rra"}->{$rra}->{"cf"}}}, ($rrd_result->{"rra"}->{$rra}->{"pdp_per_row"}*$rrd_result->{"step"});
            }
            foreach my $cf ( keys %lookup ) {
                $output .= "        <nmwg:parameter name=\"consolidationFunction\" value=\"".$cf."\">\n";
                foreach my $res ( @{$lookup{$cf}} ) {
                    $output .= "          <nmwg:parameter name=\"resolution\">".$res."</nmwg:parameter>\n";
                }
                $output .= "        </nmwg:parameter>\n";
            }    
        }
    }
    $output .= "      </nmwg:parameters>\n";
    $output .= "    </nmwg:key>\n";
    $output .= "  </nmwg:data>\n\n";

    return $output;
}

=head2 printFooter($self, { })

Print the closing of the store.xml file.

=cut

sub printFooter {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, {  } );
    return "</nmwg:store>\n";
}

=head2 commitDB($self, { })

If the output file has been set, and there is content in the cricket xml storage,
write this to the output file.

=cut

sub commitDB {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, {  } );

    unless ( $self->{FILE} ) {
        $self->{LOGGER}->error("Output file not set, aborting.");
        return -1;
    }
    if ( $self->{STORE} ) {
        open(OUTPUT, ">".$self->{FILE});
        print OUTPUT $self->{STORE};
        close(OUTPUT);
        return 0;
    }
    $self->{LOGGER}->error("Cricket xml content is empty, did you call \"openDB\"?");     
    return -1;
}

=head2 closeDB($self, { })

'Closes' the store.xml database that is created from the cricket data by
commiting the changes.

=cut

sub closeDB {
    my ( $self, @args ) = @_;
    my $parameters = validateParams( @args, {  } );
    $self->commitDB();
    return;
}

1;

__END__

=head1 SYNOPSIS

    use perfSONAR_PS::DB::Cricket;
    
=head1 SEE ALSO

L<Log::Log4perl>, L<Params::Validate>

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

Jason Zurawski, zurawski@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework along 
with this software.  If not, see <http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2008, Internet2

All rights reserved.

=cut
