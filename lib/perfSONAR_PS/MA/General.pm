#!/usr/bin/perl -w

package perfSONAR_PS::MA::General;

use warnings;
use Exporter;
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;

@ISA = ('Exporter');
@EXPORT = ('getMetadataXQuery', 'getDataXQuery', 'getTime', 
           'getDataSQL', 'getDataRRD', 'adjustRRDTime');


sub getMetadataXQuery {
  my($node, $queryString) = @_;   
  my $logger = get_logger("perfSONAR_PS::MA::General");
  if(defined $node and $node ne "") {
    my $query = getSPXQuery($node, "");
    my $eventTypeQuery = getEventTypeXQuery($node, "");
    if($eventTypeQuery) {
      if($query) {
        $query = $query . " and ";
      }
      $query = $query . $eventTypeQuery . "]";
    }
    return $query;
  }
  else {
    $logger->error("Missing argument.");
  }  
  return "";
}


sub getSPXQuery {
  my($node, $queryString) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::General");

  if(!defined $node or $node eq "") {
    $logger->error("Missing argument.");
  }
  elsif($node->getType == 8) {
    $logger->debug("Ignoring comment.");
  }
  else {
    my $queryCount = 0;
    if($node->nodeType != 3) {
      if(!($node->nodePath() =~ m/select:parameters\/nmwg:parameter/)) {
        (my $path = $node->nodePath()) =~ s/\/nmwg:message//;
        $path =~ s/\?//g;
        $path =~ s/\/nmwg:metadata//;
        $path =~ s/\/nmwg:data//;
        $path =~ s/\[\d+\]//g;
        $path =~ s/^\///g;    
        $path =~ s/nmwg:subject/*[local-name()=\"subject\"]/;
        
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
  }
  return $queryString;
}


sub getEventTypeXQuery {
  my($node, $queryString) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::General");

  if(!defined $node or $node eq "") {
    $logger->error("Missing argument.");
  }
  elsif($node->getType == 8) {
    $logger->debug("Ignoring comment.");
  }
  else {
    if($node->nodeType != 3) {
      (my $path = $node->nodePath()) =~ s/\/nmwg:message//;
      $path =~ s/\?//g;
      $path =~ s/\/nmwg:metadata//;
      $path =~ s/\/nmwg:data//;
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
  }
  return $queryString;
}


sub getDataXQuery {
  my($node, $queryString) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::General");

  if(!defined $node or $node eq "") {
    $logger->error("Missing argument.");
  }
  elsif($node->getType == 8) {
    $logger->debug("Ignoring comment.");
  }
  else {
    my $queryCount = 0;
    if($node->nodeType != 3) {
      (my $path = $node->nodePath()) =~ s/\/nmwg:message//;
      $path =~ s/\?//g;
      $path =~ s/\/nmwg:metadata//;
      $path =~ s/\/nmwg:data//;
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
            (my $path2 = $c->nodePath()) =~ s/\/nmwg:message//;
            $path =~ s/\?//g;
            $path2 =~ s/\/nmwg:metadata//;
            $path2 =~ s/\/nmwg:data//;            
            $path2 =~ s/\[\d+\]//g;
            $path2 =~ s/^\///g; 
            $queryString = getDataXQuery($c, $queryString);
          }
        }
      }
    }
  }
  return $queryString;
}


sub xQueryParameters {
  my($node, $path, $queryCount, $queryString) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::General");

  if(!defined $node or $node eq "") {
    $logger->error("Missing argument.");
  }
  elsif($node->getType == 8) {
    $logger->debug("Ignoring comment.");
  }
  else {
    my %paramHash = ();
    if($node->hasChildNodes()) {  
      my $last = "";
      foreach my $c ($node->childNodes) {
        (my $path2 = $c->nodePath()) =~ s/\/nmwg:message//;
        $path =~ s/\?//g;
        $path2 =~ s/\/nmwg:metadata//;
        $path2 =~ s/\/nmwg:data//;        
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
                (my $value = $c->firstChild->textContent) =~ s/\s{2}//g;
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
  }
  return ($queryCount, $queryString);
}


sub xQueryAttributes {
  my($node, $path, $queryCount, $queryString) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::General");
  my $counter = 0;

  if(!defined $node or $node eq "") {
    $logger->error("Missing argument.");
  }
  elsif($node->getType == 8) {
    $logger->debug("Ignoring comment.");
  }
  else {
    foreach my $attr ($node->attributes) {
      if($attr->isa('XML::LibXML::Attr')) {
        if($path eq "" or $path =~ m/metadata$/ or $path =~ m/data$/ or
           $path =~ m/subject$/ or $path =~ m/\*\[local-name\(\)=\"subject\"\]$/ or 
           $path =~ m/parameters$/ or $path =~ m/key$/ or
           $path =~ m/service$/ or $path =~ m/eventType$/) {
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
            $counter++;
          }
        }
        else {
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
          $counter++;
        }
      }
    } 
    
    if($counter) {
      my @children = $node->childNodes;
      if($#children == 0) {
        if($node->firstChild->nodeType == 3) {        
          (my $value = $node->firstChild->textContent) =~ s/\s{2}//g;
          if(!$value) {
            $queryString = $queryString . "]";
          }
        }
      }
      else {
        $queryString = $queryString . "]";
      }
    } 
  }
  return ($queryCount, $queryString);
}


sub xQueryText {
  my($node, $path, $queryCount, $queryString) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::General");

  if(!defined $node or $node eq "") {
    $logger->error("Missing argument.");
  }
  elsif($node->getType == 8) {
    $logger->debug("Ignoring comment.");
  }
  else {
    my @children = $node->childNodes;
    if($#children == 0) {
      if($node->firstChild->nodeType == 3) {        
        (my $value = $node->firstChild->textContent) =~ s/\s{2}//g;
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
            $queryString = $queryString . "]";
          }                   
          return ($queryCount, $queryString);
        }        
      }
    }
    if($queryCount) {
#      $queryString = $queryString . "]";
    } 
  } 
  return ($queryCount, $queryString); 
}


sub xQueryEventType {
  my($node, $path, $queryString) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::General");

  if(!defined $node or $node eq "") {
    $logger->error("Missing argument.");
  }
  elsif($node->getType == 8) {
    $logger->debug("Ignoring comment.");
  }
  else {
    my @children = $node->childNodes;
    if($#children == 0) {
      if($node->firstChild->nodeType == 3) {        
        (my $value = $node->firstChild->textContent) =~ s/\s{2}//g;
        if($value) {  
          if($queryString) {         
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


sub getTime {
  my($request, $ma, $id) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::General");
  
  undef $ma->{TIME};
  
  if((defined $ma and $ma ne "") and
     (defined $id and $id ne "")) {

    my $m = find($request->getRequestDOM(), "//".$request->getNamespaces()->{"http://ggf.org/ns/nmwg/base/2.0/"}.":metadata[\@id=\"".$id."\"]", 1);

    my $prefix = "";
    my $nmwg = $request->getNamespaces()->{"http://ggf.org/ns/nmwg/base/2.0/"};
    my $tm = $request->getNamespaces()->{"http://ggf.org/ns/nmwg/time/2.0/"};
    if($request->getNamespaces()->{"http://ggf.org/ns/nmwg/ops/select/2.0/"}) {
      $prefix = $request->getNamespaces()->{"http://ggf.org/ns/nmwg/ops/select/2.0/"};
    }
    else {
      $prefix = $request->getNamespaces()->{"http://ggf.org/ns/nmwg/base/2.0/"};
    }

    if(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"consolidationFunction\"]")) {
      $ma->{TIME}->{"CF"} = extract(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"consolidationFunction\"]", 1), 1);
    }
    elsif(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"consolidationFunction\"]")) {
      $ma->{TIME}->{"CF"} = extract(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"consolidationFunction\"]", 1), 1);
    }
    elsif(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"consolidationFunction\"]")) {
      $ma->{TIME}->{"CF"} = extract(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"consolidationFunction\"]", 1), 1);
    }

    if(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"resolution\"]")) {
      $ma->{TIME}->{"RESOLUTION"} = extract(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"resolution\"]", 1), 1);
    }
    elsif(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"resolution\"]")) {
      $ma->{TIME}->{"RESOLUTION"} = extract(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"resolution\"]", 1), 1);
    }
    elsif(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"resolution\"]")) {
      $ma->{TIME}->{"RESOLUTION"} = extract(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"resolution\"]", 1), 1);
    }
    
    if(!$ma->{TIME}->{"RESOLUTION"} or
       !($ma->{TIME}->{"RESOLUTION"} =~ m/^\d+$/)) {
      if($ma->{CONF}->{"DEFAULT_RESOLUTION"}) {
        $ma->{TIME}->{"RESOLUTION"} = $ma->{CONF}->{"DEFAULT_RESOLUTION"};
      }
      else {
        $ma->{TIME}->{"RESOLUTION"} = 1;
      }
    }
        
    if(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"startTime\"]")) {
      $ma->{TIME}->{"START"} = findTime(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"startTime\"]", 1), $tm, "start");
    }
    elsif(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"startTime\"]")) {
      $ma->{TIME}->{"START"} = findTime(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"startTime\"]", 1), $tm, "start");
    }
    elsif(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"startTime\"]")) {
      $ma->{TIME}->{"START"} = findTime(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"startTime\"]", 1), $tm, "start");
    }
    
    if(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"endTime\"]")) {
      $ma->{TIME}->{"END"} = findTime(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"endTime\"]", 1), $tm, "end");
    }
    elsif(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"endTime\"]")) {
      $ma->{TIME}->{"END"} = findTime(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"endTime\"]", 1), $tm, "end");
    }
    elsif(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"endTime\"]")) {
      $ma->{TIME}->{"END"} = findTime(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"endTime\"]", 1), $tm, "end");
    }
    
    if(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"time\" and \@operator=\"gte\"]")) {
      $ma->{TIME}->{"START"} = findTime(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"time\" and \@operator=\"gte\"]", 1), $tm, "start");
    }
    elsif(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"gte\"]")) {
      $ma->{TIME}->{"START"} = findTime(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"gte\"]", 1), $tm, "start");
    }
    elsif(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"gte\"]")) {
      $ma->{TIME}->{"START"} = findTime(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"gte\"]", 1), $tm, "start");
    }

    if(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"time\" and \@operator=\"lte\"]")) {
      $ma->{TIME}->{"END"} = findTime(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"time\" and \@operator=\"lte\"]", 1), $tm, "end");    
    }
    elsif(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"lte\"]")) {
      $ma->{TIME}->{"END"} = findTime(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"lte\"]", 1), $tm, "end");    
    }
    elsif(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"lte\"]")) {
      $ma->{TIME}->{"END"} = findTime(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"lte\"]", 1), $tm, "end");    
    }

    if(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"time\" and \@operator=\"gt\"]")) {
      $ma->{TIME}->{"START"} = eval(findTime(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"time\" and \@operator=\"gt\"]", 1), $tm, "start")+$ma->{TIME}->{"RESOLUTION"});
    }
    elsif(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"gt\"]")) {
      $ma->{TIME}->{"START"} = eval(findTime(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"gt\"]", 1), $tm, "start")+$ma->{TIME}->{"RESOLUTION"});
    }
    elsif(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"gt\"]")) {
      $ma->{TIME}->{"START"} = eval(findTime(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"gt\"]", 1), $tm, "start")+$ma->{TIME}->{"RESOLUTION"});
    }

    if(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"time\" and \@operator=\"lt\"]")) {
      $ma->{TIME}->{"END"} = eval(findTime(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"time\" and \@operator=\"lt\"]", 1), $tm, "end")+$ma->{TIME}->{"RESOLUTION"});
    }
    elsif(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"lt\"]")) {
      $ma->{TIME}->{"END"} = eval(findTime(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"lt\"]", 1), $tm, "end")+$ma->{TIME}->{"RESOLUTION"});
    }
    elsif(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"lt\"]")) {
      $ma->{TIME}->{"END"} = eval(findTime(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"lt\"]", 1), $tm, "end")+$ma->{TIME}->{"RESOLUTION"});
    }

    if(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"time\" and \@operator=\"eq\"]")) {
      $ma->{TIME}->{"START"} = findTime(find($m, ".//".$prefix.":parameters/".$prefix.":parameter[\@name=\"time\" and \@operator=\"eq\"]", 1), $tm, "");
      $ma->{TIME}->{"END"} = $ma->{TIME}->{"START"};
    }
    elsif(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"eq\"]")) {
      $ma->{TIME}->{"START"} = findTime(find($m, ".//".$prefix.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"eq\"]", 1), $tm, "");
      $ma->{TIME}->{"END"} = $ma->{TIME}->{"START"};
    }
    elsif(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"eq\"]")) {
      $ma->{TIME}->{"START"} = findTime(find($m, ".//".$nmwg.":parameters/".$nmwg.":parameter[\@name=\"time\" and \@operator=\"eq\"]", 1), $tm, "");
      $ma->{TIME}->{"END"} = $ma->{TIME}->{"START"};
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
  if(defined $parameter and $parameter ne "") {
    if($timePrefix and find($parameter, "./".$timePrefix.":time")) {
      my $timeElement = find($parameter, "./".$timePrefix.":time", 1);
      if($timeElement->getAttribute("type") =~ m/ISO/i) {
        return convertISO(extract($timeElement, 1));
      }
      else {
        return extract($timeElement, 0);
      }
    }
    elsif($timePrefix and $type and find($parameter, "./".$timePrefix.":".$type)) {
      my $timeElement = find($parameter, "./".$timePrefix.":".$type, 1);
      if($timeElement->getAttribute("type") =~ m/ISO/i) {
        return convertISO(extract($timeElement, 1));
      }
      else {
        return extract($timeElement, 1);
      }    
    }
    elsif($parameter->hasChildNodes()) {
      foreach my $p ($parameter->childNodes) {
        if($p->nodeType == 3) {
          (my $value = $p->textContent) =~ s/\s*//g;
          if($value) {
            return $value;
          }
        }
      }
    }  
  }
  else {
    $logger->error("Missing argument.");
  }
  return "";
}


sub getDataSQL {
  my($ma, $d, $dbSchema) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::General");
  
  my $file = extract(find($d, "./nmwg:key//nmwg:parameter[\@name=\"file\"]", 1), 1);
  if(defined $ma->{DIRECTORY}) {
    if(!($file =~ "^/")) {
      $file = $ma->{DIRECTORY}."/".$file;
    }
  }
  
  my $table = extract(find($d, "./nmwg:key//nmwg:parameter[\@name=\"table\"]", 1), 1);

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
  
  my $datadb = new perfSONAR_PS::DB::SQL(
    "DBI:SQLite:dbname=".$file,
    "", 
    "",
    \@dbSchema
  );
          
  $datadb->openDB();  
  my $result = $datadb->query($query);
  $datadb->closeDB();
  return $result;
}


sub getDataRRD {
  my($ma, $d, $mid, $did) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::General");
  
  my %result = ();
  my $file = extract(find($d, "./nmwg:key//nmwg:parameter[\@name=\"file\"]", 1), 1);
  if(defined $ma->{DIRECTORY}) {
    if(!($file =~ "^/")) {
      $file = $ma->{DIRECTORY}."/".$file;
    }
  }
  
  my $datadb = new perfSONAR_PS::DB::RRD(
    $ma->{CONF}->{"RRDTOOL"}, 
    $file,
    "",
    1
  );
  $datadb->openDB();
  
  if(!$ma->{TIME}->{"CF"} or 
     ($ma->{TIME}->{"CF"} ne "AVERAGE" and $ma->{TIME}->{"CF"} ne "MIN" and 
      $ma->{TIME}->{"CF"} ne "MAX" and $ma->{TIME}->{"CF"} ne "LAST")) {
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
    $datadb->closeDB();  
    return %result;
  }
  else {
    $datadb->closeDB();
    return %rrd_result;
  }
}


sub adjustRRDTime {
  my($ma) = @_;
  my $logger = get_logger("perfSONAR_PS::MA::General");
  my($sec, $frac) = Time::HiRes::gettimeofday;

  my $oldStart = $ma->{TIME}->{"START"};
  my $oldEnd = $ma->{TIME}->{"END"};
  if($ma->{TIME}->{"RESOLUTION"} and $ma->{TIME}->{"RESOLUTION"} =~ m/^\d+$/) {
    if($ma->{TIME}->{"START"} % $ma->{TIME}->{"RESOLUTION"}){
      $ma->{TIME}->{"START"} = int($ma->{TIME}->{"START"}/$ma->{TIME}->{"RESOLUTION"} + 1)*$ma->{TIME}->{"RESOLUTION"};
    }
    if($ma->{TIME}->{"END"} % $ma->{TIME}->{"RESOLUTION"}){
      $ma->{TIME}->{"END"} = int($ma->{TIME}->{"END"}/$ma->{TIME}->{"RESOLUTION"})*$ma->{TIME}->{"RESOLUTION"};
    }
  }  
  if($ma->{TIME}->{"START"} and $ma->{TIME}->{"RESOLUTION"} and $ma->{TIME}->{"RESOLUTION"} =~ m/^\d+$/) {
    $ma->{TIME}->{"START"} = $ma->{TIME}->{"START"} - $ma->{TIME}->{"RESOLUTION"};
  }

  if($ma->{TIME}->{"START"} and $ma->{TIME}->{"START"} =~ m/^\d+$/ and 
     $ma->{TIME}->{"RESOLUTION"} and $ma->{TIME}->{"RESOLUTION"} =~ m/^\d+$/) {
    while($ma->{TIME}->{"START"} > ($sec-($ma->{TIME}->{"RESOLUTION"}*2))) {
      $ma->{TIME}->{"START"} -= $ma->{TIME}->{"RESOLUTION"};
    }
  }

  if($ma->{TIME}->{"END"} and $ma->{TIME}->{"END"} =~ m/^\d+$/ and 
     $ma->{TIME}->{"RESOLUTION"} and $ma->{TIME}->{"RESOLUTION"} =~ m/^\d+$/) {
    while($ma->{TIME}->{"END"} > ($sec-($ma->{TIME}->{"RESOLUTION"}*2))) {
      $ma->{TIME}->{"END"} -= $ma->{TIME}->{"RESOLUTION"};
    }
  }
  return;
}


1;


__END__
=head1 NAME

perfSONAR_PS::MA::General - A module that provides methods for general tasks that MAs need to 
perform, such as querying for results.

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

Given a metadata node, constructs and returns an XQuery statement.

=head2 getSPXQuery($node, $queryString)

Helper function for the subject and parameters portion of a metadata element.  Used
by 'getMetadataXQuery', not to be called externally. 

=head2 getEventTypeXQuery($node, $queryString)

Helper function for the eventType portion of a metadata element.  Used
by 'getMetadataXQuery', not to be called externally. 

=head2 getDataXQuery($node, $queryString)

Given a data node, constructs and returns an XQuery statement.

=head2 xQueryParameters($node, $path, $queryCount, $queryString)

Helper function for the parameters portion of NMWG elements, not to 
be called externally. 

=head2 xQueryAttributes($node, $path, $queryCount, $queryString)

Helper function for the attributes portion of NMWG elements, not to 
be called externally. 

=head2 xQueryText($node, $path, $queryCount, $queryString)

Helper function for the text portion of NMWG elements, not to 
be called externally.  

=head2 xQueryEventType($node, $path, $queryString)

Helper function for the eventTYpe portion of NMWG elements, not to 
be called externally. 

=head2 getTime($request, $ma, $id)

Performs the task of extracting time/cf/resolution information from the
request message. 

=head2 findTime($parameter, $timePrefix, $type)

Extracts the time values from the parameter elements, and converts formats
if necessary.  

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

=head1 SEE ALSO

L<Exporter>, L<Log::Log4perl>, L<perfSONAR_PS::Common>, 
L<perfSONAR_PS::Messages>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list.  Bugs,
feature requests, and improvements can be directed here:

 https://bugs.internet2.edu/jira/browse/PSPS

=head1 VERSION

$Id: General.pm 692 2007-11-02 12:36:04Z zurawski $

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework along 
with this software.  If not, see <http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2004-2007, Internet2 and the University of Delaware

All rights reserved.

=cut

