#!/usr/bin/perl -I /usr/local/perfSONAR-PS/lib

use perfSONAR_PS::Common;
use perfSONAR_PS::Transport;
use XML::LibXML;
use Time::HiRes qw( gettimeofday );

&populatePostFields;
print "Content-type: text/html\r\n\r\n";

if(!defined $postFields{"LS"} or $postFields{"Reset"}) {
  &printHeader("LS Selection");
  print "    <form name=\"main\" action=\"perfAdmin2.cgi\" method=\"post\">\n";
  print "      <center>\n";
  print "        <label for=\"LS\">Please Select an LS instance: </label><br />\n";
  print "        <select multiple name=\"LS\">\n";
  print "          <option selected value=\"http://perfSONAR2.cis.udel.edu:8080/perfSONAR_PS/services/LS\">UDel</option>\n";
  print "          <option value=\"http://patdev0.internet2.edu:8081/perfSONAR_PS/services/LS\">Internet2</option>\n";
  print "        </select>\n";
  print "        <br />\n";
  print "        <input type=\"submit\" name=\"submit\" />\n";
  print "      </center>\n";
  print "    </form>\n";
}
elsif(defined $postFields{"LS"}) {
  &printHeader("LS Query Results");
  $postFields{"LS"} =~ s/%3A/:/g;
  print "    <form name=\"main\" action=\"perfAdmin2.cgi\" method=\"post\">\n";
  print "      <center>\n";
  print "        <input type=\"hidden\" name=\"LS\" value=\"".$postFields{"LS"}."\" >\n";
  print "        <input name=\"Reset\" type=\"checkbox\" value=\"1\" tabindex=\"10\"> Use another LS?</input><br />\n";
  print "        <input type=\"submit\" name=\"submit\" />\n";
  print "      </center>\n";
  print "      <br />\n";
  &display($postFields{"LS"});
  print "      <br />\n";
  print "    </form>\n";
}
&printFooter();







sub populatePostFields {
  %postFields = ();
  read( STDIN, $tmpStr, $ENV{"CONTENT_LENGTH"} );
  @parts = split(/\&/, $tmpStr);
  foreach $part (@parts) {
    ($name, $value) = split(/\=/, $part);
    $value =~ (s/%23/\#/g);
    $value =~ (s/%2F/\//g);
    $postFields{"$name"} = $value;
  }
  return;
}

sub printHeader {
  my ($title) = @_;
  print "<html>\n";
  print "  <head>\n";
  print "    <title>\n";
  print "      " , $title , "\n";
  print "    </title>\n";
  print "  </head>\n";
  print "  <body bgcolor=\"white\" text=\"black\">\n";
  print "    <hr color=\"blue\" width=\"85%\" size=\"4\" align=\"center\" />\n";
  print "    <center>\n";
  print "      <h3>\n";
  print "        perfAdmin - perfSONAR-PS Administrative Tool\n";
  print "      </h3>\n";
  print "    </center>\n";
  print "    <hr color=\"blue\" width=\"85%\" size=\"4\" align=\"center\" />\n";
  print "    <br />\n";
  return;
}

sub printFooter {
  print "  <hr color=\"blue\" width=\"85%\" size=\"4\" align=\"center\" />\n";
  print "  </body>\n";
  print "</html>\n";
  return;
}

sub display {
  my ($ls) = @_;

  my($sec, $frac) = Time::HiRes::gettimeofday;
  
  $ls =~ s/%3A/:/g; 
  (my $host = $ls) =~ s/http:\/\///; 
  (my $port = $host) =~ s/^.*://;
  (my $endpoint = $port) =~ s/^\d+\///; 
  $host =~ s/\/.*//; 
  $host =~ s/:.*//; 
  $port =~ s/\/.*//;

  my $sender = new perfSONAR_PS::Transport("", "", "", $host, $port, $endpoint); 

  my $keepalive = "";
  if($postFields{"keepalive"}) {
    $postFields{"keepalive"} =~ s/%3A/:/g;
    $keepalive = dataKeepalive($sender, $postFields{"keepalive"});
  }

  my $deregisterData = "";
  if($postFields{"deregister_data"}) {
    $postFields{"deregister_data"} =~ s/%3A/:/g;
    $postFields{"deregister_data"} =~ s/%3F/\?/g;  
    my @value = split(/\?/, $postFields{"deregister_data"});
    $postFields{"data"} = $value[0];  
    $deregisterData = dataDeregisterData($sender, $postFields{"deregister_data"});
  }

  my $deregister = "";
  if($postFields{"deregister"}) {
    $postFields{"deregister"} =~ s/%3A/:/g;    
    $deregister = dataDeregister($sender, $postFields{"deregister"});
  }

  my $xQuery = "declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\";\n"; 
  $xQuery = $xQuery . "/nmwg:metadata\n";    
  my $envelope = $sender->makeEnvelope(createLSQuery($xQuery));
  
  my $responseContent = $sender->sendReceive($envelope);  
  my $parser = XML::LibXML->new();  
  my $doc = $parser->parse_string($responseContent);  
  
  print "      <table align=\"center\" width=\"85%\" border=\"1\">\n";
  print "        <tr>\n";
  print "          <th align=\"center\">Name</th>\n";
  print "          <th align=\"center\">URL</th>\n";
  print "          <th align=\"center\">Service Type</th>\n";
  print "          <th align=\"center\">Description</th>\n";
  print "          <th align=\"center\">Expiration</th>\n";
  print "          <th align=\"center\">Data Query</th>\n";
  print "          <th align=\"center\">Data Keepalive</th>\n";
  print "          <th align=\"center\">Data Deregister</th>\n";
  print "        </tr>\n";

  if($deregisterData) {
    print $deregisterData;
  }

  if($deregister) {
    print $deregister;
  }

  foreach my $s ($doc->getDocumentElement->getElementsByTagNameNS("http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/", "service")) {      
    print "        <tr>";
    cell(extract($s->find("./psservice:serviceName")->get_node(1)));
    cell(extract($s->find("./psservice:accessPoint")->get_node(1)));
    cell(extract($s->find("./psservice:serviceType")->get_node(1)));
    cell(extract($s->find("./psservice:serviceDescription")->get_node(1)));
    
    if(extract($s->find("./psservice:accessPoint")->get_node(1))) {
      my $xQuery2 = "declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\";\n"; 
      $xQuery2 = $xQuery2 . "collection('control.dbxml')/nmwg:metadata[\@id=\"".extract($s->find("./psservice:accessPoint")->get_node(1))."\"]\n";    
      my $envelope2 = $sender->makeEnvelope(createLSQuery($xQuery2));
  
      my $responseContent2 = $sender->sendReceive($envelope2);  
      $parser = XML::LibXML->new();  
      my $doc2 = $parser->parse_string($responseContent2);  
      
      my $time = extract($doc2->getDocumentElement->getElementsByTagNameNS("http://ggf.org/ns/nmwg/base/2.0/", "parameter")->get_node(1));
      if($time) {
        my @parts = ();
        if(($sec-$time) < 0) {        
          @parts = gmtime($time-$sec);
          printf("<td align=\"center\"><font color=\"blue\">%4d D(s) %4d H(s) %4d M(s) %4d S(s)</font></td>",@parts[7,2,1,0]);        
        }
        else {
          @parts = gmtime($sec-$time);
          printf("<td align=\"center\"><font color=\"red\">%4d D(s) %4d H(s) %4d M(s) %4d S(s)</font></td>",@parts[7,2,1,0]);
        }
      }
      else {
        print "<td align=\"center\">N/A</td>";
      }
    }
    else {
      print "<td align=\"center\">N/A</td>";
    }
    
    print "<td align=\"center\"><input type=\"radio\" name=\"data\" value=\"".extract($s->find("./psservice:accessPoint")->get_node(1))."\" /></td>";
    print "<td align=\"center\"><input type=\"radio\" name=\"keepalive\" value=\"".extract($s->find("./psservice:accessPoint")->get_node(1))."\" /></td>";
    print "<td align=\"center\"><input type=\"radio\" name=\"deregister\" value=\"".extract($s->find("./psservice:accessPoint")->get_node(1))."\" /></td>";
    print "</tr>\n";
    
    if($keepalive and $postFields{"keepalive"} eq extract($s->find("./psservice:accessPoint")->get_node(1))) {
      print $keepalive;
    }
    if($postFields{"data"}) {
      $postFields{"data"} =~ s/%3A/:/g;
      if($postFields{"data"} eq extract($s->find("./psservice:accessPoint")->get_node(1))) {
        dataDisplay($sender, $postFields{"data"});
      }
    }
  }
  print "      </table>\n";
  return;
}


sub dataDisplay {
  my ($sender, $key) = @_;   
  print "        <tr>\n";
  print "          <td align=\"center\" colspan=\"8\">\n";
  print "            <table align=\"center\" width=\"100%\" border=\"1\">\n";

  my $xQuery = "declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\";\n";
  $xQuery = $xQuery . "//nmwg:data[\@metadataIdRef=\"".$key."\"]\n";
  my $envelope = $sender->makeEnvelope(createLSQuery($xQuery));
  my $responseContent = $sender->sendReceive($envelope);
  
  my $parser = XML::LibXML->new();
  my $doc = $parser->parse_string($responseContent);  

  print "          <tr>\n";
  print "            <th align=\"center\">Address</th>\n";
  print "            <th align=\"center\">Hostname</th>\n";
  print "            <th align=\"center\">Name</th>\n";
  print "            <th align=\"center\">Description</th>\n";
  print "            <th align=\"center\">Direction</th>\n";
  print "            <th align=\"center\">Data Deregister</th>\n";
  print "          </tr>\n";
  foreach my $m ($doc->getDocumentElement->getElementsByTagNameNS("http://ggf.org/ns/nmwg/topology/2.0/", "interface")) {      
    print "              <tr>";
    cell(extract($m->find("./nmwgt:ifAddress")->get_node(1)));
    cell(extract($m->find("./nmwgt:hostName")->get_node(1)));
    cell(extract($m->find("./nmwgt:ifName")->get_node(1)));
    cell(extract($m->find("./nmwgt:ifDescription")->get_node(1)));
    cell(extract($m->find("./nmwgt:direction")->get_node(1)));
    my $value = $key."?".extract($m->find("./nmwgt:ifAddress")->get_node(1))."?".extract($m->find("./nmwgt:hostName")->get_node(1))."?".extract($m->find("./nmwgt:ifName")->get_node(1))."?".extract($m->find("./nmwgt:direction")->get_node(1));
    print "<td align=\"center\"><input type=\"radio\" name=\"deregister_data\" value=\"".$value."\" /></td>";
    print "</tr>\n";
  }
  print "            </table>\n";
  print "          </td>\n";
  print "        </tr>\n";
  return;
}

sub dataKeepalive {
  my ($sender, $key) = @_;   

  my $envelope = $sender->makeEnvelope(createLSKeepalive($key));
  my $responseContent = $sender->sendReceive($envelope);
  my $parser = XML::LibXML->new();
  my $doc = $parser->parse_string($responseContent);  

  my $code = extract($doc->getDocumentElement->getElementsByTagNameNS("http://ggf.org/ns/nmwg/base/2.0/", "eventType")->get_node(1));
  my $msg = extract($doc->getDocumentElement->getElementsByTagNameNS("http://ggf.org/ns/nmwg/result/2.0/", "datum")->get_node(1));
            
  my $results = "<tr><td align=\"center\" colspan=\"8\"><table align=\"center\" width=\"100%\" border=\"1\">";
  $results = $results . "<tr><th align=\"center\">Keepalive Code</th><th align=\"center\">Keepalive Results</th></tr>";
  $results = $results . "<tr><td align=\"center\">".$code."</td><td align=\"center\">".$msg."</td></tr></table></td></tr>";
  return $results;
}

sub dataDeregister {
  my ($sender, $key) = @_;   

  my $envelope = $sender->makeEnvelope(createLSDeregister($key));
  my $responseContent = $sender->sendReceive($envelope);
  my $parser = XML::LibXML->new();
  my $doc = $parser->parse_string($responseContent);  

  my $code = extract($doc->getDocumentElement->getElementsByTagNameNS("http://ggf.org/ns/nmwg/base/2.0/", "eventType")->get_node(1));
  my $msg = extract($doc->getDocumentElement->getElementsByTagNameNS("http://ggf.org/ns/nmwg/result/2.0/", "datum")->get_node(1));
            
  my $results = "<tr><td align=\"center\" colspan=\"8\"><table align=\"center\" width=\"100%\" border=\"1\">";
  $results = $results . "<tr><th align=\"center\">Deregister Code</th><th align=\"center\">Deregister Results</th></tr>";
  $results = $results . "<tr><td align=\"center\">".$code."</td><td align=\"center\">".$msg."</td></tr></table></td></tr>";
  return $results;
}

sub dataDeregisterData {
  my ($sender, $key) = @_; 
  my @value = split(/\?/, $key);

  my $envelope = $sender->makeEnvelope(createLSDeregisterData($value[0], $value[1], $value[2], $value[3], $value[4]));
  my $responseContent = $sender->sendReceive($envelope);

  my $parser = XML::LibXML->new();
  my $doc = $parser->parse_string($responseContent);  

  my $code = extract($doc->getDocumentElement->getElementsByTagNameNS("http://ggf.org/ns/nmwg/base/2.0/", "eventType")->get_node(1));
  my $msg = extract($doc->getDocumentElement->getElementsByTagNameNS("http://ggf.org/ns/nmwg/result/2.0/", "datum")->get_node(1));
            
  my $results = "<tr><td align=\"center\" colspan=\"8\"><table align=\"center\" width=\"100%\" border=\"1\">";
  $results = $results . "<tr><th align=\"center\">Deregister Code</th><th align=\"center\">Deregister Results</th></tr>";
  $results = $results . "<tr><td align=\"center\">".$code."</td><td align=\"center\">".$msg."</td></tr></table></td></tr>";
  return $results;
}

sub cell {
  my ($node) = @_;
  print "<td align=\"center\">"; 
  if($node) {
    print $node;   
  }
  else {
    print "N/A";   
  }
  print "</td>";
  return;
}

sub createLSQuery {
  my($query) = @_;
  my $message = "\n<nmwg:message type=\"LSQueryRequest\" id=\"perfAdminQueryRequest_".genuid()."\" xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\" xmlns:xquery=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xquery/1.0/\">\n";
  $message = $message . "  <nmwg:metadata id=\"m1\">\n";
  $message = $message . "    <xquery:subject id=\"s1\">\n";
  $message = $message . $query . "\n";
  $message = $message . "    </xquery:subject>\n";
  $message = $message . "    <nmwg:eventType>http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xquery/1.0</nmwg:eventType>\n";
  $message = $message . "  </nmwg:metadata>\n";
  $message = $message . "  <nmwg:data metadataIdRef=\"m1\" id=\"d1\"/>\n";
  $message = $message . "</nmwg:message>\n";
  return $message;
}

sub createLSKeepalive {
  my($key) = @_;
  my $message = "\n<nmwg:message type=\"LSKeepaliveRequest\" id=\"perfAdminKeepaliveRequest_".genuid()."\" xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\">\n";
  $message = $message . "  <nmwg:metadata id=\"m1\">\n";
  $message = $message . "    <nmwg:key>\n";
  $message = $message . "      <nmwg:parameters id=\"keys\">\n";
  $message = $message . "        <nmwg:parameter name=\"lsKey\">".$key."</nmwg:parameter>\n";
  $message = $message . "      </nmwg:parameters>\n";
  $message = $message . "    </nmwg:key>\n";
  $message = $message . "  </nmwg:metadata>\n";
  $message = $message . "  <nmwg:data metadataIdRef=\"m1\" id=\"d1\"/>\n";
  $message = $message . "</nmwg:message>\n";
  return $message;
}

sub createLSDeregister {
  my($key) = @_;
  my $message = "\n<nmwg:message type=\"LSDeregisterRequest\" id=\"perfAdminDeregisterRequest_".genuid()."\" xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\">\n";
  $message = $message . "  <nmwg:metadata id=\"m1\">\n";
  $message = $message . "    <nmwg:key>\n";
  $message = $message . "      <nmwg:parameters id=\"keys\">\n";
  $message = $message . "        <nmwg:parameter name=\"lsKey\">".$key."</nmwg:parameter>\n";
  $message = $message . "      </nmwg:parameters>\n";
  $message = $message . "    </nmwg:key>\n";
  $message = $message . "  </nmwg:metadata>\n";
  $message = $message . "  <nmwg:data metadataIdRef=\"m1\" id=\"d1\"/>\n";
  $message = $message . "</nmwg:message>\n";
  return $message;
}

sub createLSDeregisterData {
  my($key, $ifAddress, $hostName, $ifName, $direction) = @_;
  my $message = "\n<nmwg:message type=\"LSDeregisterRequest\" id=\"perfAdminDeregisterRequest_".genuid()."\" xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\" xmlns:netutil=\"http://ggf.org/ns/nmwg/characteristic/utilization/2.0/\" xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\">\n";
  $message = $message . "  <nmwg:metadata id=\"m1\">\n";
  $message = $message . "    <nmwg:key>\n";
  $message = $message . "      <nmwg:parameters id=\"keys\">\n";
  $message = $message . "        <nmwg:parameter name=\"lsKey\">".$key."</nmwg:parameter>\n";
  $message = $message . "      </nmwg:parameters>\n";
  $message = $message . "    </nmwg:key>\n";
  $message = $message . "  </nmwg:metadata>\n";
  $message = $message . "  <nmwg:data metadataIdRef=\"m1\" id=\"d1\">\n";
  $message = $message . "    <nmwg:metadata id=\"m1\">\n";
  $message = $message . "      <netutil:subject xmlns:netutil=\"http://ggf.org/ns/nmwg/characteristic/utilization/2.0/\" id=\"s1\">\n";
  $message = $message . "        <nmwgt:interface xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\">\n";
  if($ifAddress) {
    $message = $message . "          <nmwgt:ifAddress>".$ifAddress."</nmwgt:ifAddress>\n";
  }
  if($hostName) {
    $message = $message . "          <nmwgt:hostName>".$hostName."</nmwgt:hostName>\n";
  }
  if($ifName) {
    $message = $message . "          <nmwgt:ifName>".$ifName."</nmwgt:ifName>\n";
  }
  if($direction) {
    $message = $message . "          <nmwgt:direction>".$direction."</nmwgt:direction>\n";
  }
  $message = $message . "        </nmwgt:interface>\n";
  $message = $message . "      </netutil:subject>\n";
  $message = $message . "    </nmwg:metadata>\n";
  $message = $message . "  </nmwg:data>\n";
  $message = $message . "</nmwg:message>\n";
  return $message;
}

