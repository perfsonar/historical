#!/usr/bin/perl -w

use strict;
use warnings;

=head1  NAME  

FT_client.pl
 
=head1 DESCRIPTION

This script provides a client script to query the MA service for data.

This query can be customised by passing values, for parameters to the script. These parameters include the source and destination ip addresses, source and destination path, number of streams utilised for the transfer and many other similar parameters.

The script uses FT.pm module under lib/perfSONAR_PS/Client dir. This script passes matadeta parameters at first and receives metadata in an object, it then passes this object to the client script once again, this time to fetch the metadata keys.
These keys are then used to make a data request, if so desired by the user. This request is again made through using the Client/FT.pm module. the module, returns the data object, which is then passed to it again. This time the module removes all the extra information from the object. This returned result is then used to display all the information, to the user.

=cut

use FindBin qw($Bin);
use lib "$Bin/../lib";

use perfSONAR_PS::Client::FT;
use Data::Dumper;
use Getopt::Long;
use POSIX qw(strftime);
use DateTime;

use Log::Log4perl qw(:easy);

my $debug;
my $url = 'http://localhost:9000/perfSONAR_PS/services/FT/MA';
my $help;
my $srcip            = '192.168.117.128';
my $dstip            = '131.225.107.12';
my $Epoch_Start_Time = 1220000000;
my $Epoch_End_Time   = 1225408002;
my $time_start;
my $time_end;
my $metaParam = {};
my $stripes;
my $buffer;
my $block;
my $SrcPath;
my $DestPath;
my $streams;
my $program;
my $user;
my $data;
my $ok = GetOptions(
    'debug|d'          => \$debug,
    'url=s'            => \$url,
    'data'             => \$data,
    'help|?|h'         => \$help,
    'src=s'            => \$srcip,
    'dst=s'            => \$dstip,
    'stripes=s'        => \$stripes,
    'streams=s'        => \$streams,
    'SrcPath'          => \$SrcPath,
    'DestPath'         => \$DestPath,
    'buffer=s'         => \$buffer,
    'block=s'          => \$block,
    'program=s'        => \$program,
    'user=s'           => \$user,
    'initEpochTime=i'  => \$Epoch_Start_Time,
    'finalEpochTime=i' => \$Epoch_End_Time,
    'initUtcTime=s'    => \$time_start,
    'finalUtcTime=s'   => \$time_end,
);

if ( !$ok || !$url || $help ) {
    print
" $0: sends an  XML request over SOAP to the FT MA and prints response \n";
    print " $0   [--url=<FT_MA_url, default is localhost> --debug|-d ] \n";
    print "\t-d\t\tSwitch to debug level\n";
    print "\t--debug\t\tSame as -d\n";
    print "\t--url\t\tUrl to the MA Service(FT)\n";
    print "\t     \t\tdefault is localhost\n";
    print "\t--data\t\tOutput Data as well\n";
    print "\t--src\t\tsource ip (string)\n";
    print "\t--dst\t\tdestination ip (string)\n";
    print "\t--SrcPath\t\tSource file path(string)\n";
    print "\t--DestPath\t\tDestination file path(string)\n";
    print "\t--stripes\t\tmetadata param: number of stripes\n";
    print "\t--buffer\t\tmetadata param: bufer size\n";
    print "\t--block\t\tmetadata param: block size\n";
    print "\t--streams\t\tmetadata param: number of streams\n";
    print "\t--program\t\tmetadata param: program used for file transfer\n";
    print
      "\t--user\t\tmetadata param: user, who requested the file transfer \n";
    print "\t--initEpochTime\t\t initial Time limit in Epoch (integer)\n";
    print "\t--finalEpochTime\t\t Final Time limit in Epoch (integer)\n";
    print "\t--initUtcTime\t\t initial Time limit in UTC (string)\n";
    print "\t--finalUtcTime\t\t final Time limit in UTC (string)\n";
    print "\t-h\t\tPrint this help\n";
    print "\t--help\t\tSame as -h\n";
    exit 0;
}
my $level = $INFO;
if ($debug) {
    print "Switching to Debug Level, expect a lot of output.\n";
    $level = $DEBUG;
}
if ($data) {
    print "Will Output data as well\n";
}
set_LOGGER( $level, "ft_client" );

get_LOGGER()
  ->info("-----------------------METADATA--------------------------\n");

if ($stripes) {
    $metaParam->{'stripes'} = $stripes;
}
if ($streams) {
    $metaParam->{'streams'} = $streams;
}
if ($SrcPath) {
    $metaParam->{'srcpath'} = $SrcPath;
}
if ($DestPath) {
    $metaParam->{'destpath'} = $DestPath;
}
if ($block) {
    $metaParam->{'blockize'} = $block;
}
if ($program) {
    $metaParam->{'program'} = $program;
}
if ($buffer) {
    $metaParam->{'buffersize'} = $buffer;
}
if ($user) {
    $metaParam->{'user'} = $user;
}

#print $metaParam{'stripes'};
#print Dumper($metaParam);
my $ma = new perfSONAR_PS::Client::FT( { instance => $url } );

#my $metaDataRequestStart = time();
my $result;
if ( scalar( keys(%$metaParam) ) < 1 ) {

    #print "empty\n";
    $result = $ma->metadataKeyRequest(
        {

            # src_name => $srcip,
            # dst_name => $dstip
        }
    );
}
else {

    #print "not empty \n";
    
	$result = $ma->metadataKeyRequest(
        {
            src_name   => $srcip,
            dst_name   => $dstip,
            parameters => $metaParam,
        }
    );
}

#my $metaDataRequestEnd = time();

my $metaids = $ma->getMetaData($result);

#my $metaDataExtracted = time();

#my $formatTime      = sub { strftime " %Y-%m-%d %H:%M", localtime( shift ) };

my %keys = ();

#my $metaDataMapStart = time();

foreach my $meta ( keys %{$metaids} ) {
    get_LOGGER()
      ->info(
"Metadata: src=$metaids->{$meta}{src} dst=$metaids->{$meta}{dst} \nMetadata Key(s):"
      );
    map { get_LOGGER()->info(" $_ :") } @{ $metaids->{$meta}{keys} };
    get_LOGGER()->info("\n");
    map { $keys{$_}++ } @{ $metaids->{$meta}{keys} };
}

#my $metaDataMapEnd = time();

#my $DataRequestStart;
#my $DataRequestEnd;
#my $DataExtractionEnd;
#my $DataMappingEnd;

if ( $data && %keys ) {

    get_LOGGER()
      ->info(
"--------------------------------------DATA---------------------------------------\n"
      );

    if ( !$time_start && !$time_end ) {
        my $StartDT = DateTime->from_epoch( epoch => $Epoch_Start_Time );
        my $EndDT   = DateTime->from_epoch( epoch => $Epoch_End_Time );
        $time_start =
            $StartDT->ymd('-') . 'T'
          . $StartDT->hms(':') . '.'
          . $StartDT->nanosecond() . 'Z';
        $time_end =
            $EndDT->ymd('-') . 'T'
          . $EndDT->hms(':') . '.'
          . $EndDT->nanosecond() . 'Z';
    }

    #print ("\n$time_start\t -\t $time_end\n");

    $ma = new perfSONAR_PS::Client::FT( { instance => $url } );

    #$DataRequestStart = time();

    my $dresult = $ma->setupDataRequest(
        {
            start => $time_start,
            end   => $time_end,
            keys  => [ keys %keys ],
        }
    );

    #$DataRequestEnd = time();

    my $data_md = $ma->getData($dresult);

    #$DataExtractionEnd = time();

    #PrintData($data_md,0);

    foreach my $key_id ( keys %{$data_md} ) {
        get_LOGGER()->info("\n---- Key: $key_id \n");
        foreach my $id ( keys %{ $data_md->{$key_id}{data} } ) {
            foreach my $timev ( keys %{ $data_md->{$key_id}{data}{$id} } ) {

         #               print "Data: tm=" . $ptime->( $timev ) . "\n datums: ";
                get_LOGGER()->info( "Data: tm=" . $timev . "\n datums: " );
                map {
                    get_LOGGER()
                      ->info("$_ = $data_md->{$key_id}{data}{$id}{$timev}{$_} ")
                } keys %{ $data_md->{$key_id}{data}{$id}{$timev} };
                get_LOGGER()->info("\n");
            }

        }
    }

    #$DataMappingEnd = time();

}

#get_LOGGER()->info("Time Results");
#my $mdReqTime = $metaDataRequestEnd - $metaDataRequestStart;
#get_LOGGER()->info("MetaData Request = " . $mdReqTime);
#$mdReqTime =  $metaDataExtracted - $metaDataRequestEnd;
#get_LOGGER()->info("MetaData id Request(Time to get all metadata ids) = " . $mdReqTime);
#$mdReqTime = $metaDataMapStart - $metaDataMapEnd;
#get_LOGGER()->info("MetaData Mapping Time = " . $mdReqTime);

#if ( $data && %keys ) {
#my $dReqTime = $DataRequestEnd - $DataRequestStart;
#get_LOGGER()->info("Data Request = " . $dReqTime);
#$dReqTime = $DataExtractionEnd - $DataRequestEnd;
#get_LOGGER()->info("Data id Request(Time to get all metadata ids) = " . $dReqTime);
#$dReqTime = $DataMappingEnd - $DataExtractionEnd;
#get_LOGGER()->info("Data Mapping Time = " . $dReqTime);

#}

get_LOGGER()
  ->info(
"-------------------------------------END-----------------------------------------\n"
  );

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


