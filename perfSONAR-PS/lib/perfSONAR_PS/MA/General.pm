#!/usr/bin/perl -w

package perfSONAR_PS::MA::General;

use warnings;
use Carp qw( carp );
use Exporter;
use Log::Log4perl qw(get_logger);
use Time::Local;

use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;

@ISA = ('Exporter');
@EXPORT = ('getMetadataXQuery', 'getDataXQuery', 'getTime', 
           'getDataSQL', 'getDataRRD', 'adjustRRDTime', 
           'getMetadatXQuery');


sub getMetadataXQuery {
  my($node, $queryString) = @_;
  my $query = getSPXQuery($node, "");
  my $eventTypeQuery = getEventTypeXQuery($node, "");
  if($eventTypeQuery) {
    $query = $query . " and " . $eventTypeQuery . "]";
  }
  return $query;
}


sub getSPXQuery {
  my($node, $queryString) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::General");
  if(defined $node and $node ne "") {
    my $queryCount = 0;
    if($node->nodeType != 3) {
      if(!($node->nodePath() =~ m/select:parameters\/nmwg:parameter/)) {
        (my $path = $node->nodePath()) =~ s/\/nmwg:message\/nmwg:metadata//;
        $path =~ s/\[\d+\]//g;
        $path =~ s/^\///g;    
        if($path ne "nmwg:eventType" and !($path =~ m/parameters$/)) {
          ($queryCount, $queryString) = xQueryAttributes($node, $path, $queryCount, $queryString);
          if($node->hasChildNodes()) {          
            ($queryCount, $queryString) = xQueryText($node, $path, $queryCount, $queryString);
            foreach my $c ($node->childNodes) {
              $queryString = getSPXQuery($c, $queryString);
            }
          }
        }
        elsif($path =~ m/parameters$/) {
          if($node->hasChildNodes()) {   
            ($queryCount, $queryString) = xQueryParameters($node, $path, $queryCount, $queryString);
          }
        }
      }
    }
    return $queryString;
  }
  else {
    $logger->error("Missing argument(s).");
  }
  return "";
}


sub getEventTypeXQuery {
  my($node, $queryString) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::General");
  if(defined $node and $node ne "") {
    if($node->nodeType != 3) {
      (my $path = $node->nodePath()) =~ s/\/nmwg:message\/nmwg:metadata//;
      $path =~ s/\[\d+\]//g;
      $path =~ s/^\///g;  
      if($path eq "nmwg:eventType") {
        if($node->hasChildNodes()) {          
          $queryString = xQueryEventType($node, $path, $queryString);
        }
      }   
      foreach my $c ($node->childNodes) {
        $queryString = getEventTypeXQuery($c, $queryString);
      }        
    }
    return $queryString;
  }
  else {
    $logger->error("Missing argument(s).");
  }
  return "";
}


sub getDataXQuery {
  my($node, $queryString) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::General");
  if(defined $node and $node ne "") {
    my $queryCount = 0;
    if($node->nodeType != 3) {
      (my $path = $node->nodePath()) =~ s/\/nmwg:message\/nmwg:metadata//;
      $path =~ s/\/nmwg:message\/nmwg:data//;
      $path =~ s/\[\d+\]//g;
      $path =~ s/^\///g;    

      if($path =~ m/nmwg:parameters$/ or 
         $path =~ m/snmp:parameters$/ or 
         $path =~ m/netutil:parameters$/ or 
         $path =~ m/neterr:parameters$/ or 
         $path =~ m/netdisc:parameters$/) {
        if($node->hasChildNodes()) {   
          ($queryCount, $queryString) = xQueryParameters($node, $path, $queryCount, $queryString);
        }
      }
      else {      
        ($queryCount, $queryString) = xQueryAttributes($node, $path, $queryCount, $queryString);
        if($node->hasChildNodes()) {
          ($queryCount, $queryString) = xQueryText($node, $path, $queryCount, $queryString);    
          foreach my $c ($node->childNodes) {
            (my $path2 = $c->nodePath()) =~ s/\/nmwg:message\/nmwg:metadata//;
            $path2 =~ s/\/nmwg:message\/nmwg:data//;
            $path2 =~ s/\[\d+\]//g;
            $path2 =~ s/^\///g; 
            $queryString = getDataXQuery($c, $queryString);
          }
        }
      }
    }
    return $queryString;  
  }
  else {
    $logger->error("Missing argument(s).");
  }
  return "";
}


sub xQueryParameters {
  my($node, $path, $queryCount, $queryString) = @_;
  my %paramHash = ();
  if($node->hasChildNodes()) {  
    my $last = "";
    foreach my $c ($node->childNodes) {
      (my $path2 = $c->nodePath()) =~ s/\/nmwg:message\/nmwg:metadata//;
      $path2 =~ s/\/nmwg:message\/nmwg:data//;
      $path2 =~ s/\[\d+\]//g;
      $path2 =~ s/^\///g; 
      
      if($path2 =~ m/nmwg:parameters\/nmwg:parameter$/ or 
         $path2 =~ m/snmp:parameters\/nmwg:parameter$/ or 
         $path2 =~ m/netutil:parameters\/nmwg:parameter$/ or 
         $path2 =~ m/netdisc:parameters\/nmwg:parameter$/ or
         $path2 =~ m/neterr:parameters\/nmwg:parameter$/) {
        foreach my $attr ($c->attributes) {
          if($attr->isa('XML::LibXML::Attr')) {
            if($attr->getName eq "name") {
              $last = "\@name=\"".$attr->getValue."\"";
            }
            else {
              if(($last ne "\@name=\"startTime\"") and 
                 ($last ne "\@name=\"endTime\"") and 
                 ($last ne "\@name=\"time\"") and 
                 ($last ne "\@name=\"resolution\"") and 
                 ($last ne "\@name=\"consolidationFunction\"")) {
                if($paramHash{$last}) {
                  $paramHash{$last} .= " or ".$last."and \@".$attr->getName."=\"".$attr->getValue."\"";
                  if($attr->getName eq "value") {
                    $paramHash{$last} .= " or ".$last." and text()=\"".$attr->getValue."\"";
                  }
                }
                else {
                  $paramHash{$last} = $last."and \@".$attr->getName."=\"".$attr->getValue."\"";
                  if($attr->getName eq "value") {
                    $paramHash{$last} .= " or ".$last." and text()=\"".$attr->getValue."\"";
                  }
                }
              }
            }
          }
        }
        
        if(($last ne "\@name=\"startTime\"") and 
           ($last ne "\@name=\"endTime\"") and 
           ($last ne "\@name=\"time\"") and 
           ($last ne "\@name=\"resolution\"") and 
           ($last ne "\@name=\"consolidationFunction\"")) {      
          if($c->childNodes->size() >= 1) {
            if($c->firstChild->nodeType == 3) {        
              (my $value = $c->firstChild->textContent) =~ s/\s*//g;
              if($value) {
                if($paramHash{$last}) {
                  $paramHash{$last} .= " or ".$last." and \@value=\"".$value."\" or ".$last." and text()=\"".$value."\"";               
                }
                else {
                  $paramHash{$last} = $last." and \@value=\"".$value."\" or ".$last." and text()=\"".$value."\"";  
                }            
              }
            }
          }
        }    
      }
    }
  }  

  foreach my $key (sort keys %paramHash) {
    if($queryString) {
      $queryString = $queryString . " and ";
    }
    if($path eq "nmwg:parameters") {
      $queryString = $queryString . "./*[local-name()=\"parameters\"]/nmwg:parameter[";
    }
    else {
      $queryString = $queryString . $path . "/nmwg:parameter[";
    }
    $queryString = $queryString . $paramHash{$key} . "]";
  }

  return ($queryCount, $queryString);
}


sub xQueryAttributes {
  my($node, $path, $queryCount, $queryString) = @_;

  foreach my $attr ($node->attributes) {
    if($attr->isa('XML::LibXML::Attr')) {
      if($attr->getName ne "id" and !($attr->getName =~ m/.*IdRef$/)) {
        if($queryCount == 0) {
          if($queryString) {
            $queryString = $queryString . " and ";
          }
          $queryString = $queryString . $path . "[";
          $queryString = $queryString . "\@" . $attr->getName . "=\"" . $attr->getValue . "\"";
          $queryCount++;
        }
        else {
          $queryString = $queryString . " and \@" . $attr->getName . "=\"" . $attr->getValue . "\"";
        }
      }
    }
  }
  return ($queryCount, $queryString);
}

sub xQueryText {
  my($node, $path, $queryCount, $queryString) = @_;
  my @children = $node->childNodes;
  if($#children == 0) {
    if($node->firstChild->nodeType == 3) {        
      (my $value = $node->firstChild->textContent) =~ s/\s*//g;
      if($value) {
        if($queryCount == 0) {
          if($queryString) {
            $queryString = $queryString . " and ";
          }
          $queryString = $queryString . $path . "[";
          $queryString = $queryString . "text()=\"" . $value . "\"";
          $queryCount++;
        }
        else {
          $queryString = $queryString . " and text()=\"" . $value . "\"";
        }
        if($queryCount) {
          $queryString = $queryString . "]"
        }                   
        return ($queryCount, $queryString);
      }        
    }
  }
  if($queryCount) {
    $queryString = $queryString . "]"
  }  
  return ($queryCount, $queryString);
}


sub xQueryEventType {
  my($node, $path, $queryString) = @_;
  my @children = $node->childNodes;
  if($#children == 0) {
    if($node->firstChild->nodeType == 3) {        
      (my $value = $node->firstChild->textContent) =~ s/\s*//g;
      if($value) {
        if($queryString) {
          $queryString = $queryString . " or ";
          $queryString = $queryString . "text()=\"" . $value . "\"";
        }
        else {
          $queryString = $queryString . $path . "[";
          $queryString = $queryString . "text()=\"" . $value . "\"";
        }
        return $queryString;
      }        
    }
  }
  return $queryString;
}


sub getTime {
  my($ma, $id) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::General");
  
  undef $ma->{TIME};
  
  if((defined $ma and $ma ne "") and
     (defined $id and $id ne "")) {

    my $m = $ma->{LISTENER}->getRequestDOM()->find("//".$ma->{REQUESTNAMESPACES}->{"http://ggf.org/ns/nmwg/base/2.0/"}.":metadata[\@id=\"".$id."\"]")->get_node(1);

    my $prefix = "";
    my $nmwg = $ma->{REQUESTNAMESPACES}->{"http://ggf.org/ns/nmwg/base/2.0/"};
    if($ma->{REQUESTNAMESPACES}->{"http://ggf.org/ns/nmwg/ops/select/2.0/"}) {
      $prefix = $ma->{REQUESTNAMESPACES}->{"http://ggf.org/ns/nmwg/ops/select/2.0/"};
    }
    else {
      $prefix = $ma->{REQUESTNAMESPACES}->{"http://ggf.org/ns/nmwg/base/2.0/"};
    }

    # look for time objects...
    my $tm = $ma->{REQUESTNAMESPACES}->{"http://ggf.org/ns/nmwg/time/2.0/"};

    if($m->find(".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"startTime\"]")) {
      $ma->{TIME}->{"START"} = findTime($m->find(".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"startTime\"]")->get_node(1), $tm, "start");
    }
    if($m->find(".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"endTime\"]")) {
      $ma->{TIME}->{"END"} = findTime($m->find(".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"endTime\"]")->get_node(1), $tm, "end");
    }
    if($m->find(".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"gte\"]")) {
      $ma->{TIME}->{"START"} = findTime($m->find(".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"gte\"]")->get_node(1), $tm, "start");
    }
    if($m->find(".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"lte\"]")) {
      $ma->{TIME}->{"END"} = findTime($m->find(".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"lte\"]")->get_node(1), $tm, "end");    
    }
    if($m->find(".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"gt\"]")) {
      $ma->{TIME}->{"START"} = eval(findTime($m->find(".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"gt\"]")->get_node(1), $tm, "start")+1);
    }
    if($m->find(".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"lt\"]")) {
      $ma->{TIME}->{"END"} = eval(findTime($m->find(".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"lt\"]")->get_node(1), $tm, "end")+1);
    }
    if($m->find(".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"eq\"]")) {
      $ma->{TIME}->{"START"} = findTime($m->find(".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"eq\"]")->get_node(1), $tm, "");
      $ma->{TIME}->{"END"} = $ma->{TIME}->{"START"};
    }
    if($m->find(".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"consolidationFunction\"]")) {
      $ma->{TIME}->{"CF"} = extract($m->find(".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"consolidationFunction\"]")->get_node(1));
    }
    if($m->find(".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"resolution\"]")) {
      $ma->{TIME}->{"RESOLUTION"} = extract($m->find(".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"resolution\"]")->get_node(1));
    }
    foreach my $t (keys %{$ma->{TIME}}) {
      $ma->{TIME}->{$t} =~ s/(\n)|(\s+)//g;
    }

    if($ma->{TIME}->{"START"} and 
       $ma->{TIME}->{"END"} and 
       $ma->{TIME}->{"START"} > $ma->{TIME}->{"END"}) {
      return 0;
    }    
  }
  else {
    $logger->error("Missing argument(s).");
    return 0;
  }
  return 1;
}


sub findTime {
  my($parameter, $timePrefix, $type) = @_;
  if($timePrefix and $parameter->find("./".$timePrefix.":time")) {
    my $timeElement = $parameter->find("./".$timePrefix.":time")->get_node(1);
    if($timeElement->getAttribute("type") =~ m/ISO/i) {
      return convertISO(extract($timeElement));
    }
    else {
      return extract($timeElement);
    }
  }
  elsif($timePrefix and $type and $parameter->find("./".$timePrefix.":".$type)) {
    my $timeElement = $parameter->find("./".$timePrefix.":".$type)->get_node(1);
    if($timeElement->getAttribute("type") =~ m/ISO/i) {
      return convertISO(extract($timeElement));
    }
    else {
      return extract($timeElement);
    }    
  }
  elsif($parameter->hasChildNodes()) {
    foreach my $p ($parameter->childNodes) {
      if($p->nodeType == 3) {
        (my $value = $p->textContent) =~ s/\s*//g;
        if($value) {
          return $value;
        }
        else {
          return "";
        }
      }
    }
    return "";  
  }  
  else {
    return "";
  }
}


sub convertISO {
  my($iso) = @_;
  my($first, $second) = split(/T/, $iso);
  my($year, $mon, $day) = split(/-/, $first);
  my($hour, $min, $sec) = split(/:/, $second);
  my ($sec, $frac) = split(/\./, $sec);      
  my $zone = $frac;
  $frac =~ s/\D+//g;
  $zone =~ s/\d+//g;          
  if($zone eq "Z") {
    return timegm($sec,$min,$hour,$day,$mon-1,$year-1900);
  }
  else {
    return timelocal($sec,$min,$hour,$day,$mon-1,$year-1900);
  }
}


sub getDataSQL {
  my($ma, $d, $dbSchema) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::General");
  
  my $file = extract($d->find("./nmwg:key//nmwg:parameter[\@name=\"file\"]")->get_node(1));
  my $table = extract($d->find("./nmwg:key//nmwg:parameter[\@name=\"table\"]")->get_node(1));

  my $query = "";
  if($ma->{TIME}->{"START"} or $ma->{TIME}->{"END"}) {
    $query = "select * from ".$table." where id=\"".$d->getAttribute("metadataIdRef")."\" and";
    my $queryCount = 0;
    if($ma->{TIME}->{"START"}) {
      $query = $query." time > ".$ma->{TIME}->{"START"};
      $queryCount++;
    }
    if($ma->{TIME}->{"END"}) {
      if($queryCount) {
        $query = $query." and time < ".$ma->{TIME}->{"END"}.";";
      }
      else {
        $query = $query." time < ".$ma->{TIME}->{"END"}.";";
      }
    }
  }
  else {
    $query = "select * from ".$table." where id=\"".$d->getAttribute("metadataIdRef")."\";";
  } 
  $logger->debug("Query \"".$query."\" created.");
  
  $logger->debug("Creating connection to SQL database \"".$file."\".");
  my $datadb = new perfSONAR_PS::DB::SQL(
    "DBI:SQLite:dbname=".$file,
    "", 
    "",
    \@dbSchema
  );
		      
  $datadb->openDB();  
  my $result = $datadb->query($query);
  $datadb->closeDB();
  $logger->debug("Closing SQL database connection.");
  
  return $result;
}


sub getDataRRD {
  my($ma, $d, $mid, $did) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::General");
  
  my %result = ();
  my $file = extract($d->find("./nmwg:key//nmwg:parameter[\@name=\"file\"]")->get_node(1));
  
  $logger->debug("Creating connection to RRD \"".$file."\".");
  my $datadb = new perfSONAR_PS::DB::RRD(
    $ma->{CONF}->{"RRDTOOL"}, 
    $file,
    "",
    1
  );
  $datadb->openDB();
  
  if(!$ma->{TIME}->{"CF"}) {
    $ma->{TIME}->{"CF"} = "AVERAGE";
  }
  
  my %rrd_result = $datadb->query(
    $ma->{TIME}->{"CF"}, 
    $ma->{TIME}->{"RESOLUTION"}, 
    $ma->{TIME}->{"START"}, 
    $ma->{TIME}->{"END"}
  );
 
  if($datadb->getErrorMessage()) {
    my $msg = "Query error \"".$datadb->getErrorMessage()."\"; query returned \"".$rrd_result{ANSWER}."\"";
    $logger->error($msg);
    $result{"ERROR"} = getResultCodeData($did, $mid, $msg);
    $logger->debug("Closing connection to RRD."); 
    $datadb->closeDB();  
    return %result;
  }
  else {
    $datadb->closeDB();
    $logger->debug("Closing connection to RRD.");  
    return %rrd_result;
  }
}


sub adjustRRDTime {
  my($ma) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::General");
  my $oldStart = $ma->{TIME}->{"START"};
  my $oldEnd = $ma->{TIME}->{"END"};
  if($ma->{TIME}->{"RESOLUTION"}) {
    if($ma->{TIME}->{"START"} % $ma->{TIME}->{"RESOLUTION"}){
      $ma->{TIME}->{"START"} = int($ma->{TIME}->{"START"}/$ma->{TIME}->{"RESOLUTION"} + 1)*$ma->{TIME}->{"RESOLUTION"};
      $logger->debug("New start time \"".$ma->{TIME}->{"START"}."\".");
    }
    if($ma->{TIME}->{"END"} % $ma->{TIME}->{"RESOLUTION"}){
      $ma->{TIME}->{"END"} = int($ma->{TIME}->{"END"}/$ma->{TIME}->{"RESOLUTION"})*$ma->{TIME}->{"RESOLUTION"};
      $logger->debug("New end time \"".$ma->{TIME}->{"END"}."\".");
    }
  }  
  if($ma->{TIME}->{"START"} and $ma->{TIME}->{"RESOLUTION"}) {
    $ma->{TIME}->{"START"} = $ma->{TIME}->{"START"} - $ma->{TIME}->{"RESOLUTION"};
  }
  return;
}


#
# NOTE: (JZ - 7/30/07) The next two functions are depricated
# 


sub getMetadatXQuery {
  my($ma, $id, $data) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::General");
     
  if((defined $ma and $ma ne "") and
     (defined $id and $id ne "")) {
    my $m = $ma->{LISTENER}->getRequestDOM()->find("//".$ma->{REQUESTNAMESPACES}->{"http://ggf.org/ns/nmwg/base/2.0/"}.":metadata[\@id=\"".$id."\"]")->get_node(1);
    if($data) {
      getTime($ma, $id);
    }
    $queryString = subjectQuery($m, "");
    return $queryString;  
  }
  else {
    $logger->error("Missing argument(s).");
  }
  return "";
}


sub subjectQuery {
  my($node, $queryString) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::General");

  my $queryCount = 0;
  if($node->nodeType != 3) {
    if(!($node->nodePath() =~ m/select:parameters\/nmwg:parameter/)) {
      (my $path = $node->nodePath()) =~ s/\/nmwg:message\/nmwg:metadata//;
      $path =~ s/\[\d+\]//g;
      $path =~ s/^\///g;  
    
      foreach my $attr ($node->attributes) {
        if($attr->isa('XML::LibXML::Attr')) {
          if($attr->getName ne "id" and !($attr->getName =~ m/.*IdRef$/)) {
            if($queryCount == 0) {
              if($queryString) {
                $queryString = $queryString . " and ";
              }
              $queryString = $queryString . $path . "[";
              $queryString = $queryString . "\@" . $attr->getName . "=\"" . $attr->getValue . "\"";
              $queryCount++;
            }
            else {
              $queryString = $queryString . " and \@" . $attr->getName . "=\"" . $attr->getValue . "\"";
            }
          }
        }
      }
   
      if($node->hasChildNodes()) {
        my @children = $node->childNodes;
        if($#children == 0) {
          if($node->firstChild->nodeType == 3) {        
            (my $value = $node->firstChild->textContent) =~ s/\s*//g;
            if($value) {
              if($queryCount == 0) {
                if($queryString) {
                  $queryString = $queryString . " and ";
                }
                $queryString = $queryString . $path . "[";
                $queryString = $queryString . "text()=\"" . $value . "\"";
                $queryCount++;
              }
              else {
                $queryString = $queryString . " and text()=\"" . $value . "\"";              
              }
              if($queryCount) {
                $queryString = $queryString . "]"
              }                   
              return $queryString;
            }        
          }
        }
        if($queryCount) {
          $queryString = $queryString . "]"
        }
        foreach my $c ($node->childNodes) {
          $queryString = subjectQuery($c, $queryString);
        }
      }
    }
  }
  if($queryCount) {
    $queryString = $queryString . "]"
  }
  return $queryString;
}


1;


__END__
=head1 NAME

perfSONAR_PS::MA::General - A module that provides methods for general tasks that MAs need to 
perform, such as querying for results and performing the common 'keyRequest'.

=head1 DESCRIPTION

This module is a catch all for common methods (for now) of MAs in the perfSONAR-PS framework.  
As such there is no 'common thread' that each method shares.  This module IS NOT an object, 
and the methods can be invoked directly (and sparingly).  

=head1 SYNOPSIS

    use perfSONAR_PS::MA::General;
    use perfSONAR_PS::Common;

    # Consider this metadata:
    # 
    # <nmwg:metadata xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/" id="1">
    #   <netutil:subject xmlns:netutil="http://ggf.org/ns/nmwg/characteristic/utilization/2.0/" id="stout">
    #     <nmwgt:interface xmlns:nmwgt="http://ggf.org/ns/nmwg/topology/2.0/">
    #       <nmwgt:ifAddress type="ipv4">128.4.133.167</nmwgt:ifAddress>
    #       <nmwgt:hostName>stout</nmwgt:hostName>
    #       <nmwgt:ifName>eth1</nmwgt:ifName>
    #       <nmwgt:direction>in</nmwgt:direction>
    #     </nmwgt:interface>
    #   </netutil:subject>
    #   <select:parameters xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/" id="2">
    #     <nmwg:parameter xmlns:select="http://ggf.org/ns/nmwg/ops/select/2.0/" name="time" operator="gte">
    #       1176480310
    #     </nmwg:parameter>
    #     <nmwg:parameter xmlns:select="http://ggf.org/ns/nmwg/ops/select/2.0/" name="time" operator="lte">
    #       1176480340
    #     </nmwg:parameter>      
    #     <nmwg:parameter xmlns:select="http://ggf.org/ns/nmwg/ops/select/2.0/" name="consolidationFunction">
    #       AVERAGE
    #     </nmwg:parameter>     
    #   </select:parameters>
    # </nmwg:metadata>

    # note that $node is a LibXML node object.

    my $queryString = "/nmwg:metadata[".
      getMetadataXQuery($node, "").
      "]/\@id";

    # the query after should look like this:
    #
    # /nmwg:metadata[
    #   netutil:subject/nmwgt:interface/nmwgt:ifAddress[
    #     @type="ipv4" and text()="128.4.133.167"
    #   ] and 
    #   netutil:subject/nmwgt:interface/nmwgt:hostName[text()="stout"] and 
    #   netutil:subject/nmwgt:interface/nmwgt:ifName[text()="eth1"] and 
    #   netutil:subject/nmwgt:interface/nmwgt:direction[text()="in"]
    # ]/@id

    # The same use case works for data elements, using 'getDataXQuery'

    # the time structure should look like this:
    #
    #   {
    #     'START' => '1173723350',
    #     'END' => '1173723366'
    #     'CF' => 'AVERAGE'
    #     'RESOLUTION' => ''    
    #   };
    
    getTime($ma, $id);

    my @dbSchema = ("id", "time", "value", "eventtype", "misc");
    my $result = getDataSQL($ma, $d, \@dbSchema);  
    if($#{$result} == -1) {
      # error
    }   
    else { 
      for(my $a = 0; $a <= $#{$result}; $a++) {  
        # unroll results
      }
    }

    my $responseString = adjustRRDTime($ma);
    if(!$responseString) {
      my %rrd_result = getDataRRD($ma, $d, $mid, $did);
      if($rrd_result{ERROR}) {
        # error
      }
      else {
        foreach $a (sort(keys(%rrd_result))) {
          foreach $b (sort(keys(%{$rrd_result{$a}}))) { 
            # unroll results
          }
        }
      }
    }
    else {
      # error
    }

=head1 DETAILS

The API for this module aims to be simple; note that this is not an object and 
each method does not have the 'self knowledge' of variables that may travel 
between functions.  

=head1 API

The offered API is basic for now, until more common features to MAs can be identified
and utilized in this module.

=head2 getMetadataXQuery($node, $queryString)

Given a metadata node, constructs an XQuery statement.

=head2 getDataXQuery($node, $queryString)

Given a data node, constructs an XQuery statement.

=head2 xQueryAttributes($node, $path, $queryCount, $queryString)

Used to extract attributes from nodes when constructing an XQuery.  This 
function should not be used externally.  

=head2 xQueryText($node, $path, $queryCount, $queryString)

Used to extract text elements when constructing an XQuery.  This function 
should not be used externally.  

=head2 getTime($ma, $id)

Performs the task of extracting time/cf/resolution information from the
request message. 

=head2 getDataSQL($ma, $d, $dbSchema)

Returns either an error or the actual results of an SQL database query.

=head2 getDataRRD($ma, $d, $mid, $did)

Returns either an error or the actual results of an RRD database query.

=head2 adjustRRDTime($ma)

Given an MA object, this will 'adjust' the time values in an data request
that will end up quering an RRD database.  The time values are only
'adjusted' if the resolution value makes them 'uneven' (i.e. if you are
requesting data between 1 and 70 with a resolution of 60, RRD will default
to a higher resolution becaues the boundaries are not exact).  We adjust
the start/end times to better fit the requested resolution.

=head2 getMetadatXQuery($ma, $id, $data)

DEPRICATED

=head2 subjectQuery($node, $queryString)

DEPRICATED

=head1 SEE ALSO

L<Carp>, L<Exporter>, L<Log::Log4perl>, L<perfSONAR_PS::Common>, 
L<perfSONAR_PS::Messages>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 VERSION

$Id$

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Internet2

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
