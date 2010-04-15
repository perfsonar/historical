#!/usr/bin/perl -w

use strict;
use warnings;
use CGI;
use CGI::Ajax;
use Config::General;

use FindBin qw($Bin);
use lib "$Bin/../lib";

use perfSONAR_PS::Client::DCN;
use perfSONAR_PS::Common qw( escapeString );

my $CONFIG_DIRECTORY = "$Bin/../etc";
my $CONFIG_FILE      = $CONFIG_DIRECTORY. "/dcnAdmin.conf";

# Read in configuration information
my $config = new Config::General( $CONFIG_FILE );
my %conf   = $config->getall;

my $cgi = new CGI;

my $INSTANCE = $conf{'ls_instance'};

my $auth_user = $ENV{'REMOTE_USER'}; 

my $pjx;
# only allow authenticated users to modify
if ($auth_user) {
    $pjx = new CGI::Ajax( 'reset' => \&reset, 'query' => \&query, 'modify' => \&modify );
}
else {
    $pjx = new CGI::Ajax( 'reset' => \&reset, 'query' => \&query );
}

print $pjx->build_html( $cgi, \&display );

# Call/Display the DCN mappings

sub reset {
    return q{};
}

sub query {
    my $dcn = new perfSONAR_PS::Client::DCN( 
        { 
            instance => $INSTANCE, 
            myAddress => "https://dcn-ls.internet2.edu", 
            myName => "DCN Registration CGI", 
            myType => "dcnmap" 
        } 
    );

    return display_mappings($dcn, "");
}

sub modify {
    my ( $hostname, $linkid, $add, $institution, $longitude, $latitude, $kw ) = @_;

    my @kw = ();
    @kw = split( /\n/, $kw ) if $kw;

    my $html = q{};

    my $dcn = new perfSONAR_PS::Client::DCN( 
        { 
            instance => $INSTANCE, 
            myAddress => "https://dcn-ls.internet2.edu", 
            myName => "DCN Registration CGI", 
            myType => "dcnmap" 
        } 
    );

    my $operation_status;
    if ( $hostname and $linkid ) {
        if ( $add ) {
            my $code = $dcn->insert(
                {
                    name        => $hostname,
                    id          => $linkid,  
                    institution => $institution, 
                    longitude   => $longitude,
                    latitude    => $latitude,
                    keywords    => \@kw
                }
            );
            if ( $code == 0 ) {
                $operation_status = "Insert of \"" . $hostname . "\" and \"" . $linkid . "\" succeeded.";
            }
            else {
                $operation_status = "Insert of \"" . $hostname . "\" and \"" . $linkid . "\" failed.";
            }
        }
        else {
           my $code = $dcn->remove(
                {
                    name => $hostname,
                    id   => $linkid
                }
            );
            if ( $code == 0 ) {
                $operation_status = "Delete of \"" . $hostname . "\" and \"" . $linkid . "\" succeeded.";
            }
            else {
                $operation_status = "Delete of \"" . $hostname . "\" and \"" . $linkid . "\" failed.";
            }
        }
    }
    else {
        $operation_status = "Insert of \"" . $hostname . "\" and \"" . $linkid . "\" failed - need to specify both fields";
    }

    return display_mappings($dcn, $operation_status);
}

sub display_mappings {
    my ($dcn, $operation_status) = @_;

    my $html = q{};

    my $map = $dcn->getMappings;

    if ($operation_status) {
        $html .= "<table width=\"100%\" align=\"center\" border=\"2\">\n";
        $html .= "<tr><th align=\"center\" colspan=\"2\" >Operation Status</th></tr>\n";
        $html .= "<tr>\n";
	$html .= "<td align=\"center\" ><i>$operation_status</i></td>\n</tr>\n";
        $html .= "</tr>\n";
        $html .= "</table>\n";
        $html .= "<br>\n";
    }

    $html .= "<table border=\"0\" align=\"center\" width=\"60%\" >\n";

    if ($auth_user) {
        $html .= "<tr>\n";
        $html .= "<td colspan=\"4\" align=\"center\">\n";
        $html .= "<input type=\"submit\" name=\"insert\" ";
        $html .= "value=\"Insert\" onclick=\"modify( ";
        $html .= "['hostname', 'linkid', 'add', 'institution', 'longitude', 'latitude', 'kw'], ['resultdiv'] );\">\n";
        $html .= "<input type=\"hidden\" name=\"add\" value=\"1\" id=\"add\" >\n";
        $html .= "</td>\n";
        $html .= "</tr>\n";
    
        $html .= "<tr>\n";
        $html .= "<td align=\"center\" colspan=\"2\">\n";
        $html .= "Hostname: <input type=\"text\" name=\"hostname\" id=\"hostname\" />\n";
        $html .= "</td>\n";
        $html .= "<td align=\"center\" colspan=\"2\">\n";
        $html .= "LinkID: <input type=\"text\" name=\"linkid\" id=\"linkid\" />\n";
        $html .= "</td>\n";
        $html .= "</tr>\n";

        $html .= "<tr>\n";
        $html .= "<td align=\"center\" colspan=\"4\">\n";
        $html .= "<br><font color=\"blue\">Institution: </font><input type=\"text\" name=\"institution\" id=\"institution\" />\n";
        $html .= "</td>\n";
        $html .= "</tr>\n";

        $html .= "<tr>\n";
        $html .= "<td align=\"center\" colspan=4>\n";
        $html .= "<br><font color=\"blue\">Keywords:</font><br><textarea cols=\"30\" rows=\"5\" name=\"kw\" id=\"kw\" /></textarea><br><br>\n";
        $html .= "</td>\n";
        $html .= "</tr>\n";

        $html .= "<tr>\n";
        $html .= "<td align=\"center\" colspan=\"2\">\n";
        $html .= "<font color=\"blue\">Longitude: </font><input type=\"text\" name=\"longitude\" id=\"longitude\" />\n";
        $html .= "</td>\n";
        $html .= "<td align=\"center\" colspan=\"2\">\n";
        $html .= "<font color=\"blue\">Latitude: </font><input type=\"text\" name=\"latitude\" id=\"latitude\" />\n";
        $html .= "</td>\n";
        $html .= "</tr>\n";

        $html .= "</table><br><br><br>\n";
    }

    $html .= "<table width=\"100%\" align=\"center\" border=\"0\">\n";

    if ( $#$map == -1 ) {
        $html .= "<tr>";
        $html .= "<td align=\"center\" colspan=\"6\">";
        $html .= "<i>No data to display.</i>";
        $html .= "</td>";
        $html .= "</tr>\n";
    }
    else {
        $html .= "<tr>";
        $html .= "<th align=\"center\"><i>Name</i></th>";
        $html .= "<th align=\"center\"><i>Id</i></th>";
        $html .= "<th align=\"center\"><i>Institution</i></th>";
        $html .= "<th align=\"center\"><i>Coordinates</i></th>";
        $html .= "<th align=\"center\"><i>Keywords</i></th>";
        $html .= "<th align=\"center\"><br></th>";
        $html .= "</tr>";        

        my $counter = 0;
        foreach my $m ( @$map ) {
            $html .= "<tr>\n";
            $html .= "<td><input type=\"text\" name=\"hostname." . $counter . "\" value=\"" . $m->[0] . "\" size=\"20\" id=\"hostname." . $counter . "\" /></td>\n";
            $html .= "<td><input type=\"text\" name=\"linkid." . $counter . "\" value=\"" . $m->[1] . "\" size=\"65\" id=\"linkid." . $counter . "\" /></td>\n";

            if ( exists $m->[2] and $m->[2] ) {
                if ( $m->[2]->{institution} ) {
                    $html .= "<td>" . $m->[2]->{institution} . "</td>";
                }
                else {
                    $html .= "<td><br></td>";
                }

                if ( $m->[2]->{longitude} or $m->[2]->{latitude} ) {
                    $html .= "<td>\"" . $m->[2]->{longitude} . "\", \"" . $m->[2]->{latitude} . "\"</td>";
                }
                else {
                    $html .= "<td><br></td>";
                }

                if ( $m->[2]->{keywords} ) {
                    $html .= "<td>";
                    my $kwc = 0;
                    foreach my $kw ( @{ $m->[2]->{keywords} } ) {
                        $html .= ", " if $kwc;
                        $html .= $kw;
                        $kwc++;
                    }
                    $html .= "</td>";
                }
                else {
                    $html .= "<td><br></td>";
                }
                
                if ( $auth_user and $m->[2]->{authoratative} ) {
                    $html .= "<td>\n";
                    $html .= "<input type=\"submit\" name=\"submit." . $counter . "\" ";
                    $html .= "value=\"Delete\" onclick=\"modify( ";
                    $html .= "['hostname." . $counter . "', 'linkid." . $counter . "'], ";
                    $html .= "['resultdiv'] );\">\n";         
                    $html .= "</td>\n";       
                }
                else {
                    $html .= "<td><br></td>"; 
                }
                
            }
            else {
                $html .= "<td><br></td>";
                $html .= "<td><br></td>";
                $html .= "<td><br></td>";
                $html .= "<td><br></td>";               
            }
            $html .= "</tr>\n";
            $counter++;
        }
    }
    $html .= "</table>\n";
    $html .= "<br>\n";

    return $html;
}

# Main Page Display

sub display {

    #  my $html = $cgi->start_html(-title=>'DCN Administrative Tool',
    #			      -style=>{'src'=>'../html/dcn.css'});

    my $html = $cgi->start_html( -title => 'DCN Friendly Names' );

    $html .= $cgi->h2( { align => "center" }, "DCN Administrative Tool" ) . "\n";
    $html .= $cgi->br;
    if ( $INSTANCE ) {
        $html .= $cgi->h3( { align => "center" }, $INSTANCE ) . "\n";

        $html .= $cgi->hr( { size => "4", width => "95%" } ) . "\n";

        $html .= $cgi->br;
        $html .= $cgi->br;

        $html .= $cgi->start_table( { border => "2", cellpadding => "1", align => "center", width => "95%" } ) . "\n";

        $html .= $cgi->start_Tr;
        $html .= $cgi->start_th( { align => "center" } );
        $html .= $cgi->h3( { align => "center" }, "Connection Mappings" );
        $html .= $cgi->end_td;
        $html .= $cgi->end_Tr;

        $html .= $cgi->start_Tr;
        $html .= $cgi->start_td( { align => "center" } );
        $html .= "<input type=\"submit\" name=\"query\" ";
        $html .= "value=\"Query LS\" onclick=\"query( ";
        $html .= "[], ['resultdiv'] );\">\n";

        $html .= "<input type=\"reset\" name=\"reset\" ";
        $html .= "value=\"Reset\" onclick=\"reset( ";
        $html .= "[], ['resultdiv'] );\">\n";

        $html .= "<div id=\"resultdiv\"></div>\n";
        $html .= $cgi->end_td;
        $html .= $cgi->end_Tr;

        $html .= $cgi->end_table . "\n";

        $html .= $cgi->br;
        $html .= $cgi->br;
    }
    else {
        $html .= $cgi->h3( { align => "center" }, "hLS Instance Not Defined" ) . "\n";
    }

    $html .= $cgi->hr( { size => "4", width => "95%" } ) . "\n";

    $html .= $cgi->end_html . "\n";
    return $html;
}

