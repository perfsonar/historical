package message;

$DBNAME = "";
$DBUSER = "";
$DBPASS = "";
$XMLDBENV = "";
$XMLDBCONT = "";

%namespaces = ();
%store_metadata = ();

# ################################################ #
# Sub:		new                                #
# Args:		N/A                                #
# Purpose:	create object                      #
# ################################################ #
sub new {
  bless {};
  readConf("./server.conf");
  shift;
}

# ################################################ #
# Sub:		message                            #
# Args:		$class - this package              #
#		$writer - XMLWriter object         #
#		$rawxml - xml message contents     #
#		$sent - nmwg:store hash            #
# Purpose:	process nmwg messages              #
# ################################################ #
sub message {
  ($class, $writer, $rawxml, $sent) = @_;
  
  					# reference the nmwg:store containing 
					# info about what we know
  %store_metadata = %{$sent};

  $xp2 = XML::XPath->new( xml => $rawxml );
  $xp2->clear_namespaces();
  $xp2->set_namespace('nmwg', 'http://ggf.org/ns/nmwg/base/2.0/');
  $nodeset2 = $xp2->find('//nmwg:metadata');
  					# search for each metadata element
  if($nodeset2->size() <= 0) {
    $writer->characters("Metadata element not found or in wrong namespace.");
  }
  else {
    %metadata = ();
    %data = ();
    foreach my $node2 ($nodeset2->get_nodelist) {
      my %md = ();
      foreach my $attr2 ($node2->getAttributes) {
        $md{$node2->getPrefix .":" . $node2->getLocalName . "-" . $attr2->getLocalName} = $attr2->getNodeValue;
      }      
      %md = goDeep($node2, \%md);
      $metadata{$md{"nmwg:metadata-id"}} = \%md;            
           
					# We really only care about data (triggers)
					# that match up to a known md...     
      $xp3 = XML::XPath->new( xml => $rawxml );
      $xp3->clear_namespaces();
      $xp3->set_namespace('nmwg', 'http://ggf.org/ns/nmwg/base/2.0/');
      $nodeset3 = $xp3->find('//nmwg:data[@metadataIdRef="'.$md{"nmwg:metadata-id"}.'"]');

      if($nodeset3->size() > 0) {
        foreach my $node3 ($nodeset3->get_nodelist) {		

          my %d = ();
          foreach my $attr ($node3->getAttributes) {
            $d{$node3->getPrefix .":" . $node3->getLocalName . "-" . $attr->getLocalName} = $attr->getNodeValue;
          }      
          %d = goDeep($node3, \%d);
          $data{$d{"nmwg:data-metadataIdRef"}} = \%d;    	  
	}
      }  
    }
  }
	

					# at this point we know all d's and the md's that
					# match them.  We need to worry about both subject
					# and md chaining though... so merge mds when the 
					# subject/metadata - metadataIdRef tells us to do so
  $flag = 1;
  while($flag) {
    $flag = 0;
    foreach my $m (keys %metadata) {
      if($metadata{$m}{"netutil:subject-metadataIdRef"}) {
        foreach my $m2 (keys %{$metadata{$metadata{$m}{"netutil:subject-metadataIdRef"}}}) {	  
          if($metadata{$m}{$m2} ne $metadata{$metadata{$m}{"netutil:subject-metadataIdRef"}}{$m2} && 
	     $m2 ne "netutil:subject-metadataIdRef" && $m2 ne "metadata-metadataIdRef") {
	    $metadata{$m}{$m2} = $metadata{$metadata{$m}{"netutil:subject-metadataIdRef"}}{$m2};
	    $flag = 1;
	  }	
	}          
      }
      if($metadata{$m}{"nmwg:metadata-metadataIdRef"}) {
        foreach my $m2 (keys %{$metadata{$metadata{$m}{"nmwg:metadata-metadataIdRef"}}}) {
          if($metadata{$m}{$m2} ne $metadata{$metadata{$m}{"nmwg:metadata-metadataIdRef"}}{$m2} && 
	     $m2 ne "nmwg:subject-metadataIdRef" && $m2 ne "nmwg:metadata-metadataIdRef") {  
	    $metadata{$m}{$m2} = $metadata{$metadata{$m}{"nmwg:metadata-metadataIdRef"}}{$m2};
	    $flag = 1;
	  }        
	}          
      }
    }  
  }
  

					# Now we only want to return results for data
					# elements, look at each one, and match it's
					# md reference to the store.  If we get a total/
					# partial match, we are good.
  foreach my $d (keys %data) {  
    @mdid = ();
    foreach my $m (keys %metadata) {
      if($data{$d}{"nmwg:data-metadataIdRef"} eq $m) {

        foreach my $sm (keys %store_metadata) {
          $flag = 1;             
          foreach my $sm2 (keys %{$store_metadata{$sm}}) {  
            if(!($sm2 =~ m/^.*parameter.*$/) && !($sm2 =~ m/^netutil:subject-id*$/) && 
	       !($sm2 =~ m/^netutil:subject-metadataIdRef*$/) && !($sm2 =~ m/^nmwg:metadata-metadataIdRef*$/) && 
	       !($sm2 =~ m/^nmwg:metadata-id*$/)) {          
	      if($store_metadata{$sm}{$sm2} ne $metadata{$m}{$sm2}) {                
		if(!($store_metadata{$sm}{$sm2} eq "" || $metadata{$m}{$sm2} eq "")) {	          
		  $flag = 0;
	          last;
                }
              }
            }		    
          }
          if($flag) {	  
            push @mdid, $sm;
          }
        }		
	
					# we were able to match to at least one md, start
					# to prepare xml for the return trip  
        if($#mdid != -1) {    
          $cooked = genuid();

          foreach $id (@mdid) {  
            $writer->startTag("nmwg:metadata",
#                             "id" => $m);  		
                              "id" => $cooked);  
            if($store_metadata{$id}{"netutil:subject-id"}) {
              $writer->startTag("netutil:subject",
                                "id" => $store_metadata{$id}{"netutil:subject-id"});  
            }
            else {
              $writer->startTag("netutil:subject",
                                "id" => genuid());  			
            }
            $writer->startTag("nmwgt:interface");
            foreach $sub (keys %{$store_metadata{$id}}) {  
              if($sub =~ m/^nmwgt:ifAddress$/) {
                $writer->startTag("nmwgt:" . $sub,
                                  "type" => $store_metadata{$id}{"nmwgt:ifAddress-type"});
	        $writer->characters($store_metadata{$id}{$sub});
	        $writer->endTag("nmwgt:" . $sub);	  
 	      }
              elsif(!($sub =~ m/^.*parameter.*$/) && !($sub =~ m/^nmwg:eventType$/) && 
	            !($sub =~ m/^nmwgt:ifAddress-type$/) && !($sub =~ m/^netutil:subject-id$/)) {
                $writer->startTag("nmwgt:" . $sub);
	        $writer->characters($store_metadata{$id}{$sub});
	        $writer->endTag("nmwgt:" . $sub);
	      }
            }	
            $writer->endTag("nmwgt:interface");
            $writer->endTag("netutil:subject");			
            if($store_metadata{$id}{"eventType"}) {
              $writer->startTag("nmwgt:eventType");
	      $writer->characters($store_metadata{$id}{"nmwg:eventType"});
	      $writer->endTag("nmwgt:eventType");	  
            }
		
	    if($metadata{$m}{"select:parameter-time-gte"} || $metadata{$m}{"select:parameter-time-lte"} ||
	       $metadata{$m}{"select:parameter-time-gt"} || $metadata{$m}{"select:parameter-time-lt"} ||
	       $metadata{$m}{"select:parameter-time-eq"} || $metadata{$m}{"select:parameter-time-ne"}) {
              $writer->startTag("nmwg:parameters",
	                        "id" => genuid());
			    
	      if($metadata{$m}{"select:parameter-time-gte"}) {
                $writer->startTag("select:parameter", 
	                          "name" => "time",
		    	          "operator" => "gte");
	        $writer->characters($metadata{$m}{"select:parameter-time-gte"});
                $writer->endTag("select:parameter");
	      }
	      if($metadata{$m}{"select:parameter-time-lte"}) {
                $writer->startTag("select:parameter", 
	                          "name" => "time",
			          "operator" => "lte");
	        $writer->characters($metadata{$m}{"select:parameter-time-lte"});
                $writer->endTag("select:parameter");
	      }	
	      if($metadata{$m}{"select:parameter-time-lt"}) {
                $writer->startTag("select:parameter", 
	                          "name" => "time",
			          "operator" => "lt");
	        $writer->characters($metadata{$m}{"select:parameter-time-lt"});
                $writer->endTag("select:parameter");
	      }
	      if($metadata{$m}{"select:parameter-time-gt"}) {
                $writer->startTag("select:parameter", 
	                          "name" => "time",
			          "operator" => "gt");
	        $writer->characters($metadata{$m}{"select:parameter-time-gt"});
                $writer->endTag("select:parameter");
 	      }
	      if($metadata{$m}{"select:parameter-time-eq"}) {
                $writer->startTag("select:parameter", 
	                          "name" => "time",
			          "operator" => "eq");
	        $writer->characters($metadata{$m}{"select:parameter-time-eq"});
                $writer->endTag("select:parameter");
	      }
	      if($metadata{$m}{"select:parameter-time-ne"}) {
                $writer->startTag("select:parameter", 
	                          "name" => "time",
			          "operator" => "ne");
	        $writer->characters($metadata{$m}{"select:parameter-time-ne"});
                $writer->endTag("select:parameter");
	      }	  
	      $writer->endTag("nmwg:parameters");	 
	    }
            $writer->endTag("nmwg:metadata");   
          }
					# connect to the db, form the query
					# that should net us some data.
					
          $dbh = DBI->connect("$DBNAME","$DBUSER","$DBPASS")
            || die "Database unavailable";
          foreach $id (@mdid) {  
            $writer->startTag("nmwg:data",
#                             "metadataIdRef" => $id,
                              "metadataIdRef" => $cooked,
	  	              "id" => genuid());		 
        
	    $sel = "select * from data where id=\"" . $id . "\" and ";
	    $sel = $sel . "eventtype=\"" . $store_metadata{$id}{"nmwg:parameter-eventType"} . "\"";
        
					# this is hacky, but we need to be able to filter
					# somehow	
	
	    if($metadata{$m}{"select:parameter-time-gte"}) {
	      $sel = $sel . " and time >= \"" . $metadata{$m}{"select:parameter-time-gte"} . "\"";
	    }
	    if($metadata{$m}{"select:parameter-time-lte"}) {
	      $sel = $sel . " and time <= \"" . $metadata{$m}{"select:parameter-time-lte"} . "\"";
	    }	
	    if($metadata{$m}{"select:parameter-time-lt"}) {
	      $sel = $sel . " and time < \"" . $metadata{$m}{"select:parameter-time-lt"} . "\"";	
	    }
	    if($metadata{$m}{"select:parameter-time-gt"}) {
	      $sel = $sel . " and time > \"" . $metadata{$m}{"select:parameter-time-gt"} . "\"";	
	    }
	    if($metadata{$m}{"select:parameter-time-eq"}) {
	      $sel = $sel . " and time == \"" . $metadata{$m}{"select:parameter-time-eq"} . "\"";	
	    }
	    if($metadata{$m}{"select:parameter-time-ne"}) {
	      $sel = $sel . " and time != \"" . $metadata{$m}{"select:parameter-time-ne"} . "\"";
	    }
	    $sel = $sel . ";";
					# we have the query string, execute and wrap the results
					# in the datum elements...or error out
		
	    $array_ref = $dbh->selectall_arrayref($sel);
            if($#{$array_ref} != -1) {
              for($z = 0; $z <= $#{$array_ref}; $z++) {						 
	        $writer->emptyTag("netutil:datum",
	                          "timeValue" => $array_ref->[$z][1], 
	    	 	          "value" => $array_ref->[$z][2]);	    
	      }
	    }
	    else {
              $writer->startTag("nmwgr:datum");        
              $writer->characters("No datum elements found on this server.\n");
              $writer->endTag("nmwgr:datum");	    
	    }
            $writer->endTag("nmwg:data");   
          }
          $dbh->disconnect(); 

        }
        else {
          				# error out on this particular md
          $writer->startTag("nmwg:data",
                            "id" => genuid());        
          $writer->startTag("nmwgr:datum");        
          $writer->characters("No matching metadata found on this server.\n");
          $writer->endTag("nmwgr:datum");
          $writer->endTag("nmwg:data");			  
        }
      }
    }	     
  }
  return $writer;
}

# ################################################ #
# Sub:		readConf                           #
# Args:		$file - Filename to read           #
# Purpose:	Read and store info.               #
# ################################################ #
sub readConf {
  my ($file)  = @_;
  my $CONF = new IO::File("<$file") or die "Cannot open 'readDBConf' $file: $!\n" ;
  while (<$CONF>) {
    if(!($_ =~ m/^#.*$/)) {
      $_ =~ s/\n//;
      if($_ =~ m/^DB=.*$/) {
        $_ =~ s/DB=//;
        $DBNAME = $_;
      }
      elsif($_ =~ m/^USER=.*$/) {
        $_ =~ s/USER=//;
        $DBUSER = $_;
      }
      elsif($_ =~ m/^PASS=.*$/) {
        $_ =~ s/PASS=//;
        $DBPASS = $_;
      }  
      elsif($_ =~ m/^XMLDBENV=.*$/) {
        $_ =~ s/XMLDBENV=//;
        $XMLDBENV = $_;
      }  
      elsif($_ =~ m/^XMLDBCONT=.*$/) {
        $_ =~ s/XMLDBCONT=//;
        $XMLDBCONT = $_;
      }
    }
  }          
  $CONF->close();
  return; 
}

# ################################################ #
# Sub:		goDeep                             #
# Args:		$set - set of children nodes       #
#               $sent - flattened hash of metadata #
#                       values passed through the  #
#                       recursion.                 #
# Purpose:	Keep enterning the metadata block  #
#               revealing all important elements/  #
#               attributes/values.                 #
# ################################################ #
sub goDeep {
  my ($set, $sent) = @_;
  my %b = %{$sent};  
  foreach my $element ($set->getChildNodes) {   
  
    $value = $element->getNodeValue;
    $value =~ s/\n//g;  
    $value =~ s/\s{2}//g;  
    
    if($value != "" || $value != " " || !($element->getNodeValue =~ m/\n/)) { 
      if($element->getNodeType == 3) {
        if($element->getParentNode->getLocalName eq "parameter") {		  
	  if($element->getParentNode->getAttribute("name") && $element->getParentNode->getAttribute("operator")) {	
            $b{$element->getParentNode->getPrefix .":" . $element->getParentNode->getLocalName . "-" . $element->getParentNode->getAttribute("name") . "-" . $element->getParentNode->getAttribute("operator")} = $value;
            %b = goDeep($element, \%b);	  
	  }
	  elsif($element->getParentNode->getAttribute("name") && !($element->getParentNode->getAttribute("value"))) {  
            $b{$element->getParentNode->getPrefix .":" . $element->getParentNode->getLocalName . "-" . $element->getParentNode->getAttribute("name")} = $value;
            %b = goDeep($element, \%b);
	  }	 	  
	}
	else {
          $b{$element->getParentNode->getPrefix .":" . $element->getParentNode->getLocalName} = $element->getNodeValue;	
	  %b = goDeep($element, \%b);	
	}
      }
      else {
        if($element->getLocalName eq "parameter") {	
	  if($element->getAttribute("name") && $element->getAttribute("value")) {
            $b{$element->getPrefix .":" . $element->getLocalName . "-" . $element->getAttribute("name")} = $element->getAttribute("value");
            %b = goDeep($element, \%b);
	  }
	  elsif($element->getAttribute("name") && $element->getAttribute("operator")) {
            $b{$element->getPrefix .":" . $element->getLocalName . "-" . $element->getAttribute("name") . "-" . $element->getAttribute("operator")} = $value;
            %b = goDeep($element, \%b);	  
	  }
	}
	else {
          foreach my $attr2 ($element->getAttributes) {
	   $b{$element->getPrefix .":" . $element->getLocalName . "-" . $attr2->getLocalName} = $attr2->getNodeValue;
          }      
          %b = goDeep($element, \%b);
	}
      }      
    }
  }
  return %b;
}

# ################################################ #
# Sub:		genuid                             #
# Args:		N/A                                #
# Purpose:	Generate a random number           #
# ################################################ #
sub genuid {
  my($r) = int( rand( 16777216 ) );
  return ( $r + 1048576 );
}

1;
