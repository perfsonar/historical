#!/usr/bin/perl -w

use strict;

#use warnings;

=head1  NAME  

FT_Datatypes_Test.pl
 
=head1 DESCRIPTION

Client to test Datatypes/FT.pm module

=cut

#use FindBin qw($Bin);
use lib "../lib";

use perfSONAR_PS::Datatypes::FT;
use Data::Dumper;
use Getopt::Long;
use POSIX qw(strftime);
use DateTime;
use Cwd;
use Config::General;
use Log::Log4perl qw(:easy);
my $CONFIG_FILE = q{};
my $conf;
my $debug = q{};
my $help  = q{};
my $dbo;        #database object
my $EmptyFT;    # FT object initialised with epmty args
my $FT;         # FT object initialised with args
my $ok = GetOptions(
    'debug|d'  => \$debug,
    'help|?|h' => \$help,
    'config=s' => \$CONFIG_FILE,
);

$CONFIG_FILE = "../bin/daemon.conf" unless $CONFIG_FILE;

if ( !$ok || $help ) {
    print " $0: Tests DB module of File Transfer MA \n";
    print " $0   [ --debug|-d ] \n";
    print "\t-d\t\tSwitch to debug level\n";
    print "\t--debug\t\tSame as -d\n";
    print "\t-h\t\tPrint this help\n";
    print "\t--help\t\tSame as -h\n";
    exit 0;
}
my $level = $INFO;

if ($debug) {
    print "Switching to Debug Level, expect a lot of output.\n";
    $level = $DEBUG;
}

# The configuration directory gets passed to the modules so that relative paths
# defined in their configurations can be resolved.
$CONFIG_FILE = getcwd . "/" . $CONFIG_FILE unless $CONFIG_FILE =~ /^\//;

#$confdir = dirname( $CONFIG_FILE );

# Read in configuration information
my $config = new Config::General($CONFIG_FILE);
%$conf = $config->getall;

set_LOGGER( $level, "ft_client" );

###################### HardCoding Variables ########################

my $port               = '9000';
my $endpoint           = '/perfSONAR_PS/services/FT/MA';
my $srcip              = '192.168.117.128';
my $dstip              = '131.225.107.12';
my $user               = 'fermilab';
my $program            = 'globus-gridftp-server';
my $block              = '262144';
my $buffer             = '0';
my $stripes            = '1';
my $ServiceName        = 'ftma';
my $metadataQueryEmpty = {
    'SrcIP'   => '',
    'DestIP'  => '',
    'user'    => '',
    'program' => '',
    'block'   => '',
    'buffer'  => '',
    'stripes' => ''
};
my $metadataQueryEndPoints = {
    'SrcIP'  => $srcip,
    'DestIP' => $dstip
};
my $metadataQueryAll = {
    'SrcIP'   => $srcip,
    'DestIP'  => $dstip,
    'user'    => $user,
    'program' => $program,
    'block'   => $block,
    'buffer'  => $buffer,
    'stripes' => $stripes
};

$conf = $conf->{'port'}->{$port}->{'endpoint'}->{$endpoint}->{$ServiceName};

&getConfigValues;
&setupDB();
&setupEmptyFT();
&setupFT();

my $Epoch_Start_Time = time();

my $Epoch_End_Time = time();

my $StartDT = DateTime->from_epoch( epoch => $Epoch_Start_Time );
my $EndDT   = DateTime->from_epoch( epoch => $Epoch_End_Time );

my $time_start =
    $StartDT->ymd('-') . 'T'
  . $StartDT->hms(':') . '.'
  . $StartDT->nanosecond() . 'Z';

my $time_end =
  $EndDT->ymd('-') . 'T' . $EndDT->hms(':') . '.' . $EndDT->nanosecond() . 'Z';
print("\n$time_start\t -\t $time_end\n");

get_LOGGER()
  ->info(
"---------------------------------------------------------------------------------\n"
  );

my $Level;

sub validLevel {
    my $currVal = shift;
    my $allVal  = shift;
    if ( $currVal < 0 ) {
        return 0;
    }
    if ( ref($allVal) eq 'ARRAY' ) {
        foreach my $val (@$allVal) {
            if ( $currVal == $val || $currVal eq $val ) {
                return 1;
            }
        }
        return 0;
    }
    if ( $currVal >= 0 && $allVal eq '*' ) {
        return 1;
    }
    if ( $currVal == $allVal || $currVal eq $allVal ) {
        return 1;
    }

}

sub PrintArrayData {
    my ( $DataStructure, $DisplayLevel ) = @_;
    if ( !defined($Level) ) {
        $Level = 0;
    }
    if ( !defined($DisplayLevel) ) {
        $DisplayLevel = '*';
    }
    if ( ref($DataStructure) eq 'ARRAY' ) {
        my $ArrayCount = 0;
        foreach my $ArrayElement (@$DataStructure) {
            if ( validLevel( $Level, $DisplayLevel ) == 1 ) {
                my $output = "";
                $output .= "$Level.";
                for ( my $i = 0 ; $i < $Level ; $i++ ) {
                    $output .= "\t";
                }
                $output .= "[$ArrayCount]\t=\t$ArrayElement";
                $ArrayCount++;
                get_LOGGER()->debug("$output");
            }
            if ( ref($ArrayElement) eq 'HASH' ) {
                PrintHashData( $ArrayElement, $Level + 1 );
            }
            elsif ( ref($ArrayElement) eq 'ARRAY' ) {
                PrintArrayData( $ArrayElement, $Level + 1 );
            }
        }
    }
    elsif ( ref($DataStructure) eq 'HASH' ) {
        PrintHashData( $DataStructure, $Level );
    }
}

sub PrintHashData {
    my ( $DataStructure, $DisplayLevel ) = @_;
    if ( !defined($Level) ) {
        $Level = 0;
    }
    if ( !defined($DisplayLevel) ) {
        $DisplayLevel = '*';
    }
    if ( ref($DataStructure) eq 'HASH' ) {
        while ( my ( $key, $value ) = each(%$DataStructure) ) {

            if ( validLevel( $Level, $DisplayLevel ) == 1 ) {
                my $output = "";
                $output .= "$Level.";
                for ( my $i = 0 ; $i < $Level ; $i++ ) {
                    $output .= "\t";
                }
                $output .= "$key\t=\t$value";
                get_LOGGER()->debug("$output");
            }
            if ( ref($value) eq 'HASH' ) {
                PrintHashData( $value, $Level + 1 );
            }
            elsif ( ref($value) eq 'ARRAY' ) {
                PrintArrayData( $value, $Level + 1 );
            }
        }
    }
    elsif ( ref($DataStructure) eq 'ARRAY' ) {
        PrintArrayData( $DataStructure, $Level );
    }
}

sub PrintData {
    my ( $DataStructure, $DisplayLevel ) = @_;

    #$print $DataStructure;
    if ( !defined($Level) ) {
        $Level = 0;
    }
    if ( !defined($DisplayLevel) ) {
        $DisplayLevel = '*';
    }
    if ( ref($DataStructure) eq 'HASH' ) {
        PrintHashData( $DataStructure, $Level );
    }
    elsif ( ref($DataStructure) eq 'ARRAY' ) {
        PrintArrayData( $DataStructure, $Level );
    }
    else {
        if ( validLevel( $Level, $DisplayLevel ) == 1 ) {
            my $output = "$Level.";
            for ( my $i = 0 ; $i < $Level ; $i++ ) {
                $output .= "\t";
            }
            $output .= $DataStructure;
            get_LOGGER()->debug("$output");
        }
    }
}
my $logger;

sub set_LOGGER {
    my ( $level, $loggerName ) = @_;
    Log::Log4perl->easy_init($level);
    $logger = get_logger($loggerName);

}

sub get_LOGGER {
    if ($logger) {
        return $logger;
    }
    else {
        ## setting default value ##
        set_LOGGER( $INFO, 'ft_client' );
        return $logger;
    }
}

sub setupEmptyFT {

    # setup Empty FT object
    $logger->debug("initializing Datatypes/FT ");
    $EmptyFT = perfSONAR_PS::Datatypes::FT->new();

}

sub setupFT {
    $logger->debug("initializing Datatypes/FT with args");

    $FT = perfSONAR_PS::Datatypes::FT->new();
}

sub setupDB {

    # setup database
    $logger->debug( "initializing database " . getConf("db_type") );

    if ( getConf("db_type") eq "SQLite" || "mysql" ) {

        # setup DB  object
        eval {
            $dbo = perfSONAR_PS::DB::SQL::FT->new(
                {

                    driver   => getConf("db_type"),
                    database => getConf("db_name"),
                    host     => getConf("db_host"),
                    port     => getConf("db_port"),
                    username => getConf("db_username"),
                    password => getConf("db_password"),
                }
            );

            if ( $dbo->openDB() == 0 ) {
                database($dbo);
            }
            else {
                die " Failed to open DB" . $dbo->ERRORMSG;
                return 0;
            }
        };
    }
    if ($@) {
        $logger->logdie( "Could not open database '"
              . getConf('db_type')
              . "' for '"
              . getConf('db_name') . "' "
              . $@ );
        return 0;
    }

    return 1;
}

sub getConfigValues {

    eval {

        configureConf( 'db_host', undef,    getConf('db_host') );
        configureConf( 'db_port', undef,    getConf('db_port') );
        configureConf( 'db_type', 'SQLite', getConf('db_type') );
        configureConf( 'db_name', undef,    getConf('db_name') );

        configureConf( 'db_username', undef, getConf('db_username') );
        configureConf( 'db_password', undef, getConf('db_password') );

        configureConf( 'query_size_limit', undef, getConf('query_size_limit') );

    };
    if ($@) {
        print "error fetching values from config file\n";
        return 0;
    }

    return 1;
}

=head2 database

accessor/mutator for database instance

=cut

sub database {
    my $arg = shift;

    if ( defined $arg ) {
        $dbo = $arg;
    }

    return $dbo;
}

=head2 configureConf($self, $key, $default, $value)

TBD

=cut

sub configureConf {

    my $key     = shift;
    my $default = shift;
    my $value   = shift;

    my $fatal = shift;    # if set, then if there is no value, will return -1

    if ( defined $value ) {
        if ( $value =~ /^ARRAY/ ) {
            my $index = scalar @$value - 1;

            #$logger->info( "VALUE: $value,  SIZE: $index");

            $value = $value->[$index];
        }
        $conf->{$key} = $value;
    }
    else {
        if ( !$fatal ) {
            if ( defined $default ) {
                $conf->{$key} = $default;
                $logger->warn("Setting '$key' to '$default'");
            }
            else {
                $conf->{$key} = undef;
                $logger->warn("Setting '$key' to null");
            }
        }
        else {
            $logger->logdie("Value for '$key' is not set");
        }
    }

    return 0;
}

=head2 getConf($self, $key)

TBD

=cut

sub getConf {

    my $key = shift;
    if ( defined $conf->{$key} ) {
        $logger->info("Value for '$key' is set");
        return $conf->{$key};
    }
    else {
        return $conf->{$key};
    }
}

__END__

=head1 SEE ALSO

L<perfSONAR_PS::Client::FT>, L<Data::Dumper>, L<Getopt::Long>, L<POSIX>

To join the 'perfSONAR Users' mailing list, please visit:

  https://mail.internet2.edu/wws/info/perfsonar-user

The perfSONAR-PS subversion repository is located at:

  http://anonsvn.internet2.edu/svn/perfSONAR-PS/trunk

Questions and comments can be directed to the author, or the mailing list.
Bugs, feature requests, and improvements can be directed here:

  http://code.google.com/p/perfsonar-ps/issues/list

=head1 VERSION

$Id: FT_client.pl 2774 2009-04-17 00:13:13Z aaron $

=head1 AUTHOR

Fahad Satti


