#!/usr/bin/perl -w
#
#      $Id: owamp_grid.cgi 1803 2007-08-02 17:52:24Z boote $
#
#########################################################################
#									#
#			   Copyright (C)  2006				#
#	     			Internet2				#
#			   All Rights Reserved				#
#									#
#########################################################################
#
#	File:		owamp_grid.cgi
#
#	Author:		Jeff Boote
#			Internet2
#
#	Date:		Tue Jul 11 11:18:15 MDT 2006
use strict;
use FindBin;
# BEGIN FIXMORE HACK - DO NOT EDIT
# %amidefaults is initialized by fixmore MakeMaker hack
my %amidefaults;
BEGIN{
    %amidefaults = (
        CONFDIR	=> "$FindBin::Bin/../etc",
        LIBDIR	=> "$FindBin::Bin/../lib",
    );
}
# END FIXMORE HACK - DO NOT EDIT

# use amidefaults to find other modules $env('PERL5LIB') still works...
use lib $amidefaults{'LIBDIR'};
use Getopt::Std;
use Carp qw(cluck);
use File::Basename;
use DBI;
use CGI qw/:standard/;
use OWP;
use OWP::Utils;

# Fetch configuration options.
my $conf = new OWP::Conf(%amidefaults);

my $debug = $conf->get_val(ATTR=>'DEBUG');

my $q = new CGI;

#
# URL decomposition
#
my($base,$dir,$suffix) = fileparse($q->script_name,".cgi");
$dir =~ s#(.*)/$#$1#;
my $navfile = $dir."/nav.html";
my $selfdir = "http://".$q->virtual_host().$dir."/";
my $selfurl = $selfdir.$base.".cgi";

#
# Timestamp's
#
# TODO: owptrange needs to be combined with something to deal with 'resolution'
# data availability.
#
my $tstamp = $q->path_info;
$tstamp =~ s#^/##o;
my ($first, $last);
owptrange(\$tstamp,\$first,\$last,900);

#
# Read database options
#
my $ttype = 'OWP';
my $dbuser = $conf->must_get_val(ATTR=>'CGIDBUser',TYPE=>$ttype);
my $dbpass = $conf->get_val(ATTR=>'CGIDBPass',TYPE=>$ttype);
my $dbsource = $conf->must_get_val(ATTR=>'CentralDBType',TYPE=>$ttype) . ":" .
        $conf->must_get_val(ATTR=>'CentralDBName',TYPE=>$ttype);
my $dbhost = $conf->get_val(ATTR=>'CentralDBHost',TYPE=>$ttype) || "localhost";
my $dbport = $conf->get_val(ATTR=>'CentralDBPort',TYPE=>$ttype);
if(defined($dbport)){
    $dbhost .= ":".$dbport;
}
$dbsource .= ":" . $dbhost;

#
# Connect to database
#
my $dbh = DBI->connect($dbsource,$dbuser,$dbpass,
    {	RaiseError	=>	0,
        PrintError	=>	1
    })	|| die "Couldn't connect to database";

my $sql;
my $sth;
my @row;
my $rc;

# get resolutions
my @reslist;
$sql="SELECT res from resolutions order by res";
$sth = $dbh->prepare($sql) || die "Prep: Select resolutions";
$sth->execute() || die "Select resolutions";
while(@row = $sth->fetchrow_array){
    push @reslist, @row;
}

# get receivers
my @receivers;
$sql="SELECT DISTINCT nodes.node_name from nodes,tests where nodes.node_id=tests.recv_id";
$sth = $dbh->prepare($sql) || die "Prep:Select receivers";
$sth->execute() || die "Select receivers";
while(@row = $sth->fetchrow_array){
    push @receivers, @row;
}
@receivers = sort @receivers;

# get senders
my @senders;
$sql="SELECT DISTINCT nodes.node_name from nodes,tests where nodes.node_id=tests.send_id";
$sth = $dbh->prepare($sql) || die "Prep:Select senders";
$sth->execute() || die "Select senders";
while(@row = $sth->fetchrow_array){
    push @senders, @row;
}
@senders = sort @senders;

my %nodenames;
my $longname;
foreach $rc (@receivers){
    $nodenames{$rc} = $conf->get_val(NODE=>$rc,ATTR=>'LONGNAME');
}
foreach $rc (@senders){
    $nodenames{$rc} = $conf->get_val(NODE=>$rc,ATTR=>'LONGNAME');
}

# get tests
my %tests;
$sql="SELECT test_name from tests";
$sth = $dbh->prepare($sql) || die "Prep:Select tests";
$sth->execute() || die "Select tests";
while(@row = $sth->fetchrow_array){
    $tests{$row[0]} = $row[1];
}
my @tests = keys %tests;

# get meshes
my %meshes;
$sql="SELECT mesh_name,addr_type from meshes";
$sth = $dbh->prepare($sql) || die "Prep:Select meshes";
$sth->execute() || die "Select meshes";
while(@row = $sth->fetchrow_array){
    $meshes{$row[0]} = $row[1];
}
my @meshes = sort keys %meshes;


# TODO: Add a sort parameter to the meshes in the conf file. (Each
# mesh can have an 'Order' parameter and then the sort could key
# on that. (make it a cookie-parm..?)

# Fetch all the data
my $tname;
my %delay;
my %loss;
my %color;
TEST:
foreach $tname (keys %tests){
    my $res;

    RESOLUTION:
    foreach $res (@reslist){
        my $done=0;
        $sql = "SELECT count(*),max(min),
                sum(lost)/sum(sent)
                from OWP_${tname}
                WHERE
                res=? AND si<? AND ei>?";
        $sth = $dbh->prepare($sql) ||
        die "Prep:Select status $tname";
        $rc = $sth->execute($res,owptstampi($last),
            owptstampi($first)) or
        die "Select status $tname";
        while((@row = $sth->fetchrow_array) && $row[0]){
#            warn "tname = $tname";
#            warn "first = $first";
#            warn "last = $last";
#            warn "row(0) = ".$row[0];
#            warn "row(1) = ".$row[1];
#            warn "row(2) = ".$row[2];
            $delay{$tname} = defined($row[1]) ?  sprintf "%.3f",$row[1]*1000: '*';
            $loss{$tname} = $row[2];
            $color{$tname} =($row[2]>0) ?  'red':'white';
            $done=1;
        }
        undef $sth;

        last RESOLUTION if($done);
        $delay{$tname} = '*';
        $loss{$tname} = '*';
        $color{$tname} = 'white';
    }
}
$dbh->disconnect;

# Now display the results
my @headers;
push(@headers, -type=>'text/html',
    -expires=>'+1min');
my $now = "";
if($tstamp =~ /now/){
    push (@headers,'-Refresh' => 60);
    $now = " (now)";
}

print $q->header(@headers);
print $q->start_html(	-title=>
    "OWAMP Grid:$now ".owpgmstring($first)." --- ".owpgmstring($last),
    -author=>'owamp@internet2.edu',
    -xbase=>$selfdir,
);

print $q->start_form(-action=>"${selfdir}tselect.cgi/$tstamp"),
$q->hidden(-name=>'back',-value=>$selfurl),
$q->h3(owpgmstring($first), " --- ",owpgmstring($last),
    $q->submit(-value=>'Select Timeframe',-name=>'tframe'), ),
$q->end_form, "\n";

print "<!--#include virtual=\"$navfile\" -->\n";

my @hrow;
my $line;

undef $line;
undef @hrow;

# header rows
push @hrow, $q->th({-align => 'center',-bgcolor=>"#EEEEEE"},"OWAMP GRID") .
$q->th({-align => 'center',-bgcolor=>"#EEEEEE",
        -colspan => @receivers+2},"Receivers") . "\n";
$line = $q->th({-align => 'center',-bgcolor=>"#EEEEEE",-valign=>'center',-rowspan=>@tests+1},"Senders"). "\n";
$line .= $q->th({-bgcolor=>"#EEEEEE"},"Location"). "\n";
$line .= $q->th({-bgcolor=>"#EEEEEE"},"ISP"). "\n";

my $recv;
foreach $recv (@receivers){
    $line .= $q->th({-align => 'center'},$q->a({href=>"${selfdir}owamp_path.cgi/all/$recv/$tstamp"},$nodenames{$recv})). "\n";
}
push @hrow, $line;

# Now for the data rows
my $send;
SEND:
foreach $send (@senders){
    my $mesh;
    MESH:
    foreach $mesh (@meshes){
        my $do_mesh;

        # determine if this mesh is done by this 'send/recv combination'
        $do_mesh = 0;
        foreach $recv (@receivers){
            $tname = "${mesh}_${recv}_${send}";
            next if !exists($tests{$tname});
            $do_mesh = 1;
            last;
        }
        next MESH if(!$do_mesh);

        $line = $q->th({-align => 'center'},$q->a({href=>"${selfdir}owamp_path.cgi/$mesh/$send/$tstamp"},$nodenames{$send}));
        $line .= $q->th({-align => 'center'},
            $conf->get_val(NODE=>$send,
                ATTR=>'ADDRDESC',
                TYPE=>$meshes{$mesh}) || '') . "\n";
                
        RECV:
        foreach $recv (@receivers){
            $tname = "${mesh}_${recv}_${send}";
            if(!exists($tests{$tname})){
                $line .= $q->td({-bgcolor=>"#DDDDDD"},"");
            }
            else{

                $line .= $q->td({   -bgcolor => $color{$tname},
                        -align => 'center',
                    },
                    a({href=>"${selfdir}owamp_path.cgi/$mesh/$recv/$send/$tstamp"},
                        "$delay{$tname} / $loss{$tname}")). "\n";
            }
        }
        $line .= "\n";
        push @hrow, $line;
    }
}


print $q->h2({-align=>'center'},"OWAMP Data"), "\n";
print $q->h4({-align=>'center'},"[Latency (ms) / Packet Loss (%)]"), "\n";
print $q->table({-border=>'1',-width=>'90%'},$q->Tr(\@hrow)),"\n";
print $q->br(""),"\n";

print $q->end_html;


exit;
