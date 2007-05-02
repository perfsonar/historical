#!/usr/bin/perl -w

use strict;
use XML::LibXML;

my $in = shift;
my $out = shift;

my $parser = XML::LibXML->new();
my $dom = $parser->parse_file($in); 

open(WRITE, ">".$out);

my %names = ();
foreach my $n ($dom->getDocumentElement->childNodes) {
  if($n->nodeName ne "\#text") {
    $names{$n->nodeName}++;
  }
}

my %nodes = ();
my %nodes2 = ();
foreach my $n ($dom->getElementsByTagName("ndl:Device")) {
  my $id = $n->getAttribute("rdf:about");
  $id =~ s/&/and/g;
  $nodes{$id}++; 
  if(!defined $nodes2{$id}) {
    $nodes2{$id} = 0;
  }
}
foreach my $n ($dom->getElementsByTagName("ndl:connectedTo")) {
  my $id = $n->getAttribute("rdf:resource");
  $id =~ s/&/and/g; 
  $nodes{$id}++; 
  if(!defined $nodes2{$id}) {
    $nodes2{$id} = 0;
  }
}

print WRITE "<nmwg:store xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"\n";
print WRITE "            xmlns:nmtopo=\"http://ggf.org/ns/nmwg/topology/base/3.0/\">\n";

print WRITE "  <nmwg:metadata id=\"m1\">\n";

my %links = ();
foreach my $name (keys %names) {
  if($name eq "ndl:Device") {           
    foreach my $n ($dom->getElementsByTagName($name)) {
      my $id = $n->getAttribute("rdf:about");
      $id =~ s/&/and/g;
  
      if(!$nodes2{$id}) {
        $nodes2{$id}++;
        print WRITE "    <nmtopo:node id=\"".$id."\">\n";
        print WRITE "      <nmtopo:name>".$id."</nmtopo:name>\n";
        if($n->find("./ndl:name")) {
          print WRITE "      <nmtopo:hostName>".$n->find("./ndl:name")->get_node(1)->textContent."</nmtopo:hostName>\n";
        }
        if($n->find("./ndl:locatedAt")) {
          my $loc = "";
          if($loc = $dom->find("//ndl:Location[\@rdf:about=\"".
           $n->find("./ndl:locatedAt")->get_node(1)->getAttribute("rdf:resource")."\"]")) {
            if($loc->get_node(1)->find("./geo:lat")->get_node(1)->textContent) {
              print WRITE "      <nmtopo:latitude>".$loc->get_node(1)->find("./geo:lat")->get_node(1)->textContent.
               "</nmtopo:latitude>\n";
            }
            if($loc->get_node(1)->find("./geo:long")->get_node(1)->textContent) {
              print WRITE "      <nmtopo:longitude>".$loc->get_node(1)->find("./geo:long")->get_node(1)->textContent.
               "</nmtopo:longitude>\n";              
            }        
          }
        }
        if($n->find("./ndl:hasInterface")) {
          foreach my $int ($n->find("./ndl:hasInterface")->get_nodelist()) {
            my $intf = "";
            if($intf = $dom->find("//ndl:Interface[\@rdf:about=\"".$int->getAttribute("rdf:resource")."\"]")) {
              my $iid = $intf->get_node(1)->getAttribute("rdf:about");
              $iid =~ s/&/and/g;

              if($intf->get_node(1)->find("./ndl:name")->get_node(1)->textContent) {                    
                print WRITE "      <nmtopo:interface id=\"".$iid."\">\n";
                my $name = $intf->get_node(1)->find("./ndl:name")->get_node(1)->textContent;               
                print WRITE "        <nmtopo:hostName>".$name."</nmtopo:hostName>\n";
                $name =~ s/^.*://;
                print WRITE "        <nmtopo:ifName>".$name."</nmtopo:ifName>\n";
                print WRITE "      </nmtopo:interface>\n";
                
                if($intf->get_node(1)->find("./ndl:connectedTo")) { 
                  my $lid = $intf->get_node(1)->find("./ndl:connectedTo")->get_node(1)->getAttribute("rdf:resource");
                  $lid =~ s/&/and/g;

                  my $llid = $id."-".$lid;                 
                  $links{$llid} = "    <nmtopo:link id=\"".$llid."\">\n";
                  $links{$llid} = $links{$llid}."      <nmtopo:node nodeIdRef=\"".$id."\" />\n";  
                  $links{$llid} = $links{$llid}."      <nmtopo:node nodeIdRef=\"".$lid."\" />\n"; 
                  $links{$llid} = $links{$llid}."    </nmtopo:link>\n";                  
                }
              }     
            }
          }
        }      
        print WRITE "    </nmtopo:node>\n";      
      }
    }
  }
} 

print WRITE "\n\n";

foreach my $n (sort keys %nodes2) {
  if(!$nodes2{$n}) {
    print WRITE "    <nmtopo:node id=\"".$n."\">\n";
    print WRITE "      <nmtopo:name>".$n."</nmtopo:name>\n";
    print WRITE "    </nmtopo:node>\n";    
    $nodes2{$n}++;
  }
}

foreach my $l (sort keys %links) {
  print WRITE $links{$l};
}

print WRITE "  </nmwg:metadata>\n";
print WRITE "</nmwg:store>\n";

close(WRITE);

