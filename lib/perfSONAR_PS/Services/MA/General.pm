package perfSONAR_PS::Services::MA::General;

use base 'Exporter';

use warnings;

our $VERSION = 0.07;

=head1 NAME

perfSONAR_PS::Services::MA::General - A module that provides methods for
general tasks that MAs need to perform, such as querying for results.

=head1 DESCRIPTION

This module is a catch all for common methods (for now) of MAs in the
perfSONAR-PS framework.  As such there is no 'common thread' that each method
shares.  This module IS NOT an object, and the methods can be invoked directly
(and sparingly).  

=cut

use Exporter;
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;

@EXPORT = ( 'getMetadataXQuery', 'getDataXQuery', 'getDataSQL', 'getDataRRD', 'adjustRRDTime', 'parseTime' );

=head2 getMetadataXQuery($node, $queryString)

Given a metadata node, constructs and returns an XQuery statement.

=cut

sub getMetadataXQuery {
    my ( $node, $queryString ) = @_;
    my $logger = get_logger("perfSONAR_PS::Services::MA::General");

    unless ( defined $node and $node ) {
        $logger->error("Missing argument.");
        return;
    }

    my $query = getSPXQuery( $node, q{} );
    my $eventTypeQuery = getEventTypeXQuery( $node, q{} );
    if ($eventTypeQuery) {
        if ($query) {
            $query = $query . " and ";
        }
        $query = $query . $eventTypeQuery . "]";
    }
    return $query;
}

=head2 getSPXQuery($node, $queryString)

Helper function for the subject and parameters portion of a metadata element.
Used by 'getMetadataXQuery', not to be called externally. 

=cut

sub getSPXQuery {
    my ( $node, $queryString ) = @_;
    my $logger = get_logger("perfSONAR_PS::Services::MA::General");

    unless ( defined $node and $node ) {
        $logger->error("Missing argument.");
        return $queryString;
    }

    unless ( $node->getType == 8 ) {
        my $queryCount = 0;
        if ( $node->nodeType != 3 ) {
            if ( !( $node->nodePath() =~ m/select:parameters\/nmwg:parameter/mx ) ) {
                ( my $path = $node->nodePath() ) =~ s/\/nmwg:message//mx;
                $path =~ s/\?//gmx;
                $path =~ s/\/nmwg:metadata//mx;
                $path =~ s/\/nmwg:data//mx;

                # XXX Jason 2/25/06
                # Would this be required elsewhere?
                $path =~ s/\/.*:node//mx;
                $path =~ s/\[\d+\]//gmx;
                $path =~ s/^\///gmx;
                $path =~ s/nmwg:subject/*[local-name()=\"subject\"]/mx;

                if ( $path ne "nmwg:eventType" and ( not $path =~ m/parameters$/mx ) ) {
                    ( $queryCount, $queryString ) = xQueryAttributes( $node, $path, $queryCount, $queryString );
                    if ( $node->hasChildNodes() ) {
                        ( $queryCount, $queryString ) = xQueryText( $node, $path, $queryCount, $queryString );
                        foreach my $c ( $node->childNodes ) {
                            $queryString = getSPXQuery( $c, $queryString );
                        }
                    }
                }
                elsif ( $path =~ m/parameters$/mx ) {
                    if ( $node->hasChildNodes() ) {
                        ( $queryCount, $queryString ) = xQueryParameters( $node, $path, $queryCount, $queryString );
                    }
                }
            }
        }
    }
    return $queryString;
}

=head2 getEventTypeXQuery($node, $queryString)

Helper function for the eventType portion of a metadata element.  Used
by 'getMetadataXQuery', not to be called externally. 

=cut

sub getEventTypeXQuery {
    my ( $node, $queryString ) = @_;
    my $logger = get_logger("perfSONAR_PS::Services::MA::General");

    unless ( defined $node and $node ) {
        $logger->error("Missing argument.");
        return $queryString;
    }

    unless ( $node->getType == 8 ) {
        if ( $node->nodeType != 3 ) {
            ( my $path = $node->nodePath() ) =~ s/\/nmwg:message//mx;
            $path =~ s/\?//gmx;
            $path =~ s/\/nmwg:metadata//mx;
            $path =~ s/\/nmwg:data//mx;
            $path =~ s/\[\d+\]//gmx;
            $path =~ s/^\///gmx;
            if ( $path eq "nmwg:eventType" ) {
                if ( $node->hasChildNodes() ) {
                    $queryString = xQueryEventType( $node, $path, $queryString );
                }
            }
            foreach my $c ( $node->childNodes ) {
                $queryString = getEventTypeXQuery( $c, $queryString );
            }
        }
    }
    return $queryString;
}

=head2 getDataXQuery($node, $queryString)

Given a data node, constructs and returns an XQuery statement.

=cut

sub getDataXQuery {
    my ( $node, $queryString ) = @_;
    my $logger = get_logger("perfSONAR_PS::Services::MA::General");

    unless ( defined $node and $node ) {
        $logger->error("Missing argument.");
        return $queryString;
    }

    unless ( $node->getType == 8 ) {
        my $queryCount = 0;
        if ( $node->nodeType != 3 ) {
            ( my $path = $node->nodePath() ) =~ s/\/nmwg:message//mx;
            $path =~ s/\?//gmx;
            $path =~ s/\/nmwg:metadata//mx;
            $path =~ s/\/nmwg:data//mx;
            $path =~ s/\[\d+\]//gmx;
            $path =~ s/^\///gmx;

            if (   $path =~ m/nmwg:parameters$/mx
                or $path =~ m/snmp:parameters$/mx
                or $path =~ m/netutil:parameters$/mx
                or $path =~ m/neterr:parameters$/mx
                or $path =~ m/netdisc:parameters$/mx )
            {
                ( $queryCount, $queryString ) = xQueryParameters( $node, $path, $queryCount, $queryString ) if ( $node->hasChildNodes() );
            }
            else {
                ( $queryCount, $queryString ) = xQueryAttributes( $node, $path, $queryCount, $queryString );
                if ( $node->hasChildNodes() ) {
                    ( $queryCount, $queryString ) = xQueryText( $node, $path, $queryCount, $queryString );
                    foreach my $c ( $node->childNodes ) {
                        ( my $path2 = $c->nodePath() ) =~ s/\/nmwg:message//mx;
                        $path  =~ s/\?//mxg;
                        $path2 =~ s/\/nmwg:metadata//mx;
                        $path2 =~ s/\/nmwg:data//mx;
                        $path2 =~ s/\[\d+\]//gmx;
                        $path2 =~ s/^\///gmx;
                        $queryString = getDataXQuery( $c, $queryString );
                    }
                }
            }
        }
    }
    return $queryString;
}

=head2 xQueryParameters($node, $path, $queryCount, $queryString)

Helper function for the parameters portion of NMWG elements, not to 
be called externally. 

=cut

sub xQueryParameters {
    my ( $node, $path, $queryCount, $queryString ) = @_;
    my $logger = get_logger("perfSONAR_PS::Services::MA::General");

    unless ( defined $node and $node ) {
        $logger->error("Missing argument.");
        return $queryString;
    }

    unless ( $node->getType == 8 ) {
        my %paramHash = ();
        if ( $node->hasChildNodes() ) {
            my $attrString = q{};
            foreach my $c ( $node->childNodes ) {
                ( my $path2 = $c->nodePath() ) =~ s/\/nmwg:message//mx;
                $path  =~ s/\?//gmx;
                $path2 =~ s/\/nmwg:metadata//mx;
                $path2 =~ s/\/nmwg:data//mx;
                $path2 =~ s/\[\d+\]//gmx;
                $path2 =~ s/^\///gmx;

                if (   $path2 =~ m/nmwg:parameters\/nmwg:parameter$/mx
                    or $path2 =~ m/snmp:parameters\/nmwg:parameter$/mx
                    or $path2 =~ m/netutil:parameters\/nmwg:parameter$/mx
                    or $path2 =~ m/netdisc:parameters\/nmwg:parameter$/mx
                    or $path2 =~ m/neterr:parameters\/nmwg:parameter$/mx )
                {
                    foreach my $attr ( $c->attributes ) {
                        if ( $attr->isa('XML::LibXML::Attr') ) {
                            if ( $attr->getName eq "name" ) {
                                $attrString = "\@name=\"" . $attr->getValue . "\"";
                            }
                            else {
                                if (    ( $attrString ne "\@name=\"startTime\"" )
                                    and ( $attrString ne "\@name=\"endTime\"" )
                                    and ( $attrString ne "\@name=\"time\"" )
                                    and ( $attrString ne "\@name=\"resolution\"" )
                                    and ( $attrString ne "\@name=\"consolidationFunction\"" ) )
                                {
                                    if ( $paramHash{$attrString} ) {
                                        $paramHash{$attrString} .= " or " . $attrString . "and \@" . $attr->getName . "=\"" . $attr->getValue . "\"";
                                        $paramHash{$attrString} .= " or " . $attrString . " and text()=\"" . $attr->getValue . "\"" if ( $attr->getName eq "value" );
                                    }
                                    else {
                                        $paramHash{$attrString} = $attrString . "and \@" . $attr->getName . "=\"" . $attr->getValue . "\"";
                                        $paramHash{$attrString} .= " or " . $attrString . " and text()=\"" . $attr->getValue . "\"" if ( $attr->getName eq "value" );
                                    }
                                }
                            }
                        }
                    }

                    if (    ( $attrString ne "\@name=\"startTime\"" )
                        and ( $attrString ne "\@name=\"endTime\"" )
                        and ( $attrString ne "\@name=\"time\"" )
                        and ( $attrString ne "\@name=\"resolution\"" )
                        and ( $attrString ne "\@name=\"consolidationFunction\"" ) )
                    {
                        if ( $c->childNodes->size() >= 1 ) {
                            if ( $c->firstChild->nodeType == 3 ) {
                                ( my $value = $c->firstChild->textContent ) =~ s/\s{2}//gmx;
                                if ($value) {
                                    if ( $paramHash{$attrString} ) {
                                        $paramHash{$attrString} .= " or " . $attrString . " and \@value=\"" . $value . "\" or " . $attrString . " and text()=\"" . $value . "\"";
                                    }
                                    else {
                                        $paramHash{$attrString} = $attrString . " and \@value=\"" . $value . "\" or " . $attrString . " and text()=\"" . $value . "\"";
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        foreach my $key ( sort keys %paramHash ) {
            $queryString = $queryString . " and " if ($queryString);
            if ( $path eq "nmwg:parameters" ) {
                $queryString = $queryString . "./*[local-name()=\"parameters\"]/nmwg:parameter[";
            }
            else {
                $queryString = $queryString . $path . "/nmwg:parameter[";
            }
            $queryString = $queryString . $paramHash{$key} . "]";
        }
    }
    return ( $queryCount, $queryString );
}

=head2 xQueryAttributes($node, $path, $queryCount, $queryString)

Helper function for the attributes portion of NMWG elements, not to 
be called externally. 

=cut

sub xQueryAttributes {
    my ( $node, $path, $queryCount, $queryString ) = @_;
    my $logger  = get_logger("perfSONAR_PS::Services::MA::General");
    my $counter = 0;

    unless ( defined $node and $node ) {
        $logger->error("Missing argument.");
        return $queryString;
    }

    unless ( $node->getType == 8 ) {
        foreach my $attr ( $node->attributes ) {
            if ( $attr->isa('XML::LibXML::Attr') ) {
                if (   ( not $path )
                    or $path =~ m/metadata$/mx
                    or $path =~ m/data$/mx
                    or $path =~ m/subject$/mx
                    or $path =~ m/\*\[local-name\(\)=\"subject\"\]$/mx
                    or $path =~ m/parameters$/mx
                    or $path =~ m/key$/mx
                    or $path =~ m/service$/mx
                    or $path =~ m/eventType$/mx
                    or $path =~ m/node$/mx )
                {
                    if ( $attr->getName ne "id" and ( not $attr->getName =~ m/.*IdRef$/mx ) ) {
                        if ( $queryCount == 0 ) {
                            $queryString = $queryString . " and " if ($queryString);
                            $queryString = $queryString . $path . "[";
                            $queryString = $queryString . "\@" . $attr->getName . "=\"" . $attr->getValue . "\"";
                            $queryCount++;
                        }
                        else {
                            $queryString = $queryString . " and \@" . $attr->getName . "=\"" . $attr->getValue . "\"";
                        }
                        $counter++;
                    }
                }
                else {
                    if ( $queryCount == 0 ) {
                        $queryString = $queryString . " and " if ($queryString);
                        $queryString = $queryString . $path . "[";
                        $queryString = $queryString . "\@" . $attr->getName . "=\"" . $attr->getValue . "\"";
                        $queryCount++;
                    }
                    else {
                        $queryString = $queryString . " and \@" . $attr->getName . "=\"" . $attr->getValue . "\"";
                    }
                    $counter++;
                }
            }
        }

        if ($counter) {
            my @children = $node->childNodes;
            if ( $#children == 0 ) {
                if ( $node->firstChild->nodeType == 3 ) {
                    ( my $value = $node->firstChild->textContent ) =~ s/\s{2}//gmx;
                    $queryString = $queryString . "]" if ( !$value );
                }
            }
            else {
                $queryString = $queryString . "]";
            }
        }
    }
    return ( $queryCount, $queryString );
}

=head2 xQueryText($node, $path, $queryCount, $queryString)

Helper function for the text portion of NMWG elements, not to 
be called externally.  

=cut

sub xQueryText {
    my ( $node, $path, $queryCount, $queryString ) = @_;
    my $logger = get_logger("perfSONAR_PS::Services::MA::General");

    unless ( defined $node and $node ) {
        $logger->error("Missing argument.");
        return $queryString;
    }

    unless ( $node->getType == 8 ) {
        my @children = $node->childNodes;
        if ( $#children == 0 ) {
            if ( $node->firstChild->nodeType == 3 ) {
                ( my $value = $node->firstChild->textContent ) =~ s/\s{2}//gmx;
                if ($value) {
                    if ( $queryCount == 0 ) {
                        $queryString = $queryString . " and " if ($queryString);
                        $queryString = $queryString . $path . "[";
                        $queryString = $queryString . "text()=\"" . $value . "\"";
                        $queryCount++;
                    }
                    else {
                        $queryString = $queryString . " and text()=\"" . $value . "\"";
                    }
                    $queryString = $queryString . "]" if ($queryCount);
                    return ( $queryCount, $queryString );
                }
            }
        }

        #    if($queryCount) {
        #      $queryString = $queryString . "]";
        #    }
    }
    return ( $queryCount, $queryString );
}

=head2 xQueryEventType($node, $path, $queryString)

Helper function for the eventTYpe portion of NMWG elements, not to 
be called externally. 

=cut

sub xQueryEventType {
    my ( $node, $path, $queryString ) = @_;
    my $logger = get_logger("perfSONAR_PS::Services::MA::General");

    unless ( defined $node and $node ) {
        $logger->error("Missing argument.");
        return $queryString;
    }

    unless ( $node->getType == 8 ) {
        my @children = $node->childNodes;
        if ( $#children == 0 ) {
            if ( $node->firstChild->nodeType == 3 ) {
                ( my $value = $node->firstChild->textContent ) =~ s/\s{2}//gmx;
                if ($value) {
                    if ($queryString) {
                        $queryString = $queryString . " or ";
                    }
                    else {
                        $queryString = $queryString . $path . "[";
                    }
                    $queryString = $queryString . "text()=\"" . $value . "\"";

                    #          return $queryString;
                }
            }
        }
    }
    return $queryString;
}

=head2 getDataSQL($ma, $d, $dbSchema)

Returns either an error or the actual results of an SQL database query.

=cut

sub getDataSQL {
    my ( $directory, $file, $table, $timeSettings, $dbSchema ) = @_;
    my $logger = get_logger("perfSONAR_PS::Services::MA::General");

    if ($directory) {
        if ( !( $file =~ "^/" ) ) {
            $file = $directory . "/" . $file;
        }
    }

    my $query = q{};
    if ( $timeSettings->{"START"} or $timeSettings->{"END"} ) {
        $query = "select * from " . $table . " where id=\"" . $d->getAttribute("metadataIdRef") . "\" and";
        my $queryCount = 0;
        if ( $timeSettings->{"START"} ) {
            $query = $query . " time > " . $timeSettings->{"START"};
            $queryCount++;
        }
        if ( $timeSettings->{"END"} ) {
            if ($queryCount) {
                $query = $query . " and time < " . $timeSettings->{"END"} . ";";
            }
            else {
                $query = $query . " time < " . $timeSettings->{"END"} . ";";
            }
        }
    }
    else {
        $query = "select * from " . $table . " where id=\"" . $d->getAttribute("metadataIdRef") . "\";";
    }

    my $datadb = new perfSONAR_PS::DB::SQL( { name => "DBI:SQLite:dbname=" . $file, schema => \@dbSchema } );

    $datadb->openDB;
    my $result = $datadb->query( { query => $query } );
    $datadb->closeDB;
    return $result;
}

=head2 getDataRRD($ma, $d, $mid)

Returns either an error or the actual results of an RRD database query.

=cut

sub getDataRRD {
    my ( $directory, $file, $timeSettings, $rrdtool ) = @_;
    my $logger = get_logger("perfSONAR_PS::Services::MA::General");

    my %result = ();
    if ($directory) {
        if ( !( $file =~ "^/" ) ) {
            $file = $directory . "/" . $file;
        }
    }

    my $datadb = new perfSONAR_PS::DB::RRD( { path => $rrdtool, name => $file, error => 1 } );
    $datadb->openDB;

    if (
        not $timeSettings->{"CF"}
        or (    $timeSettings->{"CF"} ne "AVERAGE"
            and $timeSettings->{"CF"} ne "MIN"
            and $timeSettings->{"CF"} ne "MAX"
            and $timeSettings->{"CF"} ne "LAST" )
        )
    {
        $timeSettings->{"CF"} = "AVERAGE";
    }

    my %rrd_result = $datadb->query(
        {
            cf         => $timeSettings->{"CF"},
            resolution => $timeSettings->{"RESOLUTION"},
            start      => $timeSettings->{"START"},
            end        => $timeSettings->{"END"}
        }
    );

    if ( $datadb->getErrorMessage ) {
        my $msg = "Query error \"" . $datadb->getErrorMessage . "\"; query returned \"" . $rrd_result{ANSWER} . "\"";
        $logger->error($msg);
        $result{"ERROR"} = $msg;
        $datadb->closeDB;
        return %result;
    }
    else {
        $datadb->closeDB;
        return %rrd_result;
    }
}

=head2 adjustRRDTime($ma)

Given an MA object, this will 'adjust' the time values in an data request
that will end up quering an RRD database.  The time values are only
'adjusted' if the resolution value makes them 'uneven' (i.e. if you are
requesting data between 1 and 70 with a resolution of 60, RRD will default
to a higher resolution becaues the boundaries are not exact).  We adjust
the start/end times to better fit the requested resolution.

=cut

sub adjustRRDTime {
    my ($timeSettings) = @_;
    my $logger = get_logger("perfSONAR_PS::Services::MA::General");
    my ( $sec, $frac ) = Time::HiRes::gettimeofday;

    return if ( ( not defined $timeSettings->{"START"} ) and ( not defined $timeSettings->{"END"} ) );

    my $oldStart = $timeSettings->{"START"};
    my $oldEnd   = $timeSettings->{"END"};
    if ( $timeSettings->{"RESOLUTION"} and $timeSettings->{"RESOLUTION"} =~ m/^\d+$/mx ) {
        if ( $timeSettings->{"START"} % $timeSettings->{"RESOLUTION"} ) {
            $timeSettings->{"START"} = int( $timeSettings->{"START"} / $timeSettings->{"RESOLUTION"} + 1 ) * $timeSettings->{"RESOLUTION"};
        }
        if ( $timeSettings->{"END"} % $timeSettings->{"RESOLUTION"} ) {
            $timeSettings->{"END"} = int( $timeSettings->{"END"} / $timeSettings->{"RESOLUTION"} ) * $timeSettings->{"RESOLUTION"};
        }
    }

    # XXX: Jason 2/24
    # When run over and over this will alter the START time for an RRD range.
    #
    #  if($timeSettings->{"START"} and $timeSettings->{"RESOLUTION"} and $timeSettings->{"RESOLUTION"} =~ m/^\d+$/) {
    #    $timeSettings->{"START"} = $timeSettings->{"START"} - $timeSettings->{"RESOLUTION"};
    #  }

    if (    $timeSettings->{"START"}
        and $timeSettings->{"START"} =~ m/^\d+$/mx
        and $timeSettings->{"RESOLUTION"}
        and $timeSettings->{"RESOLUTION"} =~ m/^\d+$/mx )
    {
        while ( $timeSettings->{"START"} > ( $sec - ( $timeSettings->{"RESOLUTION"} * 2 ) ) ) {
            $timeSettings->{"START"} -= $timeSettings->{"RESOLUTION"};
        }
    }

    if (    $timeSettings->{"END"}
        and $timeSettings->{"END"} =~ m/^\d+$/mx
        and $timeSettings->{"RESOLUTION"}
        and $timeSettings->{"RESOLUTION"} =~ m/^\d+$/mx )
    {
        while ( $timeSettings->{"END"} > ( $sec - ( $timeSettings->{"RESOLUTION"} * 2 ) ) ) {
            $timeSettings->{"END"} -= $timeSettings->{"RESOLUTION"};
        }
    }
    return;
}

=head2 parseTime($parameter, $timePrefix, $type)

Performs the task of extracting time information from the request message.

=cut

sub parseTime {
    my ( $parameter, $timePrefix, $type ) = @_;
    my $logger = get_logger("perfSONAR_PS::Services::MA::General");

    if ( defined $parameter and $parameter ) {
        if ( $timePrefix and find( $parameter, "./" . $timePrefix . ":time", 1 ) ) {
            my $timeElement = find( $parameter, "./" . $timePrefix . ":time", 1 );
            if ( $timeElement->getAttribute("type") =~ m/ISO/imx ) {
                return convertISO( extract( $timeElement, 1 ) );
            }
            else {
                return extract( $timeElement, 0 );
            }
        }
        elsif ( $timePrefix and $type and find( $parameter, "./" . $timePrefix . ":" . $type, 1 ) ) {
            my $timeElement = find( $parameter, "./" . $timePrefix . ":" . $type, 1 );
            if ( $timeElement->getAttribute("type") =~ m/ISO/imx ) {
                return convertISO( extract( $timeElement, 1 ) );
            }
            else {
                return extract( $timeElement, 1 );
            }
        }
        elsif ( $parameter->hasChildNodes() ) {
            foreach my $p ( $parameter->childNodes ) {
                if ( $p->nodeType == 3 ) {
                    ( my $value = $p->textContent ) =~ s/\s*//gmx;
                    if ($value) {
                        return $value;
                    }
                }
            }
        }
    }
    else {
        $logger->error("Missing argument.");
    }
    return;
}

1;

__END__

=head1 SEE ALSO

L<Exporter>, L<Log::Log4perl>, L<perfSONAR_PS::Common>, 
L<perfSONAR_PS::Messages>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list.
Bugs, feature requests, and improvements can be directed here:

 https://bugs.internet2.edu/jira/browse/PSPS

=head1 VERSION

$Id$

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework
along with this software.  If not, see
<http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2004-2008, Internet2 and the University of Delaware

All rights reserved.

=cut

