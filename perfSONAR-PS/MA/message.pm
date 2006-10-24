package message;

$DBNAME = "";
$DBUSER = "";
$DBPASS = "";
$XMLDBENV = "";
$XMLDBCONT = "";

$all_path_status = 0;

%namespaces = ();

# ################################################ #
# Sub:		new
# Args:		N/A
# Purpose:	create object
# ################################################ #
sub new {
	bless {};
	readConf("./server.conf");
	shift;
}

# ################################################ #
# Sub:		message
# Args:		$class - this package
#		$writer - XMLWriter object
#		$rawxml - xml message contents
#		$sent - nmwg:store hash
# Purpose:	process nmwg messages
# ################################################ #
sub message {
	($class, $writer, $rawxml) = @_;

	# Identify specialized messages here
	# (pronounced "giant hack")
	$xp_hack = XML::XPath->new( xml => $rawxml );
	$xp_hack->clear_namespaces();
	$xp_hack->set_namespace('nmwg', 'http://ggf.org/ns/nmwg/base/2.0/');
	$nodeset_h = $xp_hack->find('//nmwg:metadata/nmwg:eventType/text() = "Path.Status"');

	if($nodeset_h > 0) {
		$all_path_status = 1;
	}

	# reference the nmwg:store containing 
	# info about what we know
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
				$md{$node2->getPrefix .":" . $node2->getLocalName . "-"
						. $attr2->getLocalName} = $attr2->getNodeValue;
			}
			%md = goDeep($node2, \%md, $node2->getPrefix .":" . $node2->getLocalName);
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
					%d = goDeep($node3, \%d, $node3->getPrefix .":" . $node3->getLocalName);
					$data{$d{"nmwg:data-metadataIdRef"}} = \%d;
				}
			}
		}
	}

	# at this point we know all d's and the md's that
	# match them.	 We need to worry about both subject
	# and md chaining though... so merge mds when the 
	# subject/metadata - metadataIdRef tells us to do so
	$flag = 1;
	while($flag) {
		$flag = 0;
		foreach my $m (keys %metadata) {
			if($metadata{$m}{"nmwg:metadata/netutil:subject-metadataIdRef"}) {
				foreach my $m2 (keys %{$metadata{$metadata{$m}{"nmwg:metadata/netutil:subject-metadataIdRef"}}}) {
					if($metadata{$m}{$m2} ne $metadata{$metadata{$m}{"nmwg:metadata/netutil:subject-metadataIdRef"}}{$m2} &&
						 $m2 ne "nmwg:metadata/netutil:subject-metadataIdRef" && $m2 ne "nmwg:metadata/metadata-metadataIdRef") {
						$metadata{$m}{$m2} = $metadata{$metadata{$m}{"nmwg:metadata/netutil:subject-metadataIdRef"}}{$m2};
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
	# md reference to the store.	If we get a total/
	# partial match, we are good.
	foreach my $d (keys %data) {
		@mdid = ();
		foreach my $m (keys %metadata) {
			if($data{$d}{"nmwg:data-metadataIdRef"} eq $m) {


				$qs = "/nmwg:metadata[";
				$qf = 0;
				foreach my $m2 (keys %{$metadata{$m}}) {

					if(!($m2 =~ m/^.*parameter.*$/) &&
						 !($m2 =~ m/^.*netutil:subject-id$/) &&
						 !($m2 =~ m/^.*netutil:subject-metadataIdRef$/) &&
						 !($m2 =~ m/^nmwg:metadata-metadataIdRef$/) &&
						 !($m2 =~ m/^nmwg:metadata-id$/)) {

						$disp = $m2;
						$disp =~ s/nmwg:metadata\///;
						@attr = split(/-/, $m2);

						if(!($qf)) {
							if($#attr) {
								$disp =~ s/-.*//;
								$qs = $qs . $disp . "[\@" . $attr[1] . "=\"" . $metadata{$m}{$m2} . "\"]";
							}
							else {
								$qs = $qs . $disp . "[text()=\"" . $metadata{$m}{$m2} . "\"]";
							}
							$qf++;
						}
						else {
							if($#attr) {
								$disp =~ s/-.*//;
								$qs = $qs . " and " . $disp . "[\@" . $attr[1] . "=\"" . $metadata{$m}{$m2} . "\"]";
							}
							else {
								$qs = $qs . " and " . $disp . "[text()=\"" . $metadata{$m}{$m2} . "\"]";
							}
						}
					}
				}

				$qs = $qs . "]";

				my @resultsString = ();

				# Special message handling
				# (giant hack continues)
				if ($all_path_status eq 1) {
					$qs = "/nmwg:metadata[nmwg:subject[nmtl2:link|nmwgtopo3:node]]";
				}
				if ($DEBUG > 1) {
					print "QS: $qs\n";
				}

				eval {
					my $env = new DbEnv(0);
					$env->set_cachesize(0, 64 * 1024, 1);
					$env->open($XMLDBENV,
										 Db::DB_INIT_MPOOL |
										 Db::DB_CREATE |
										 Db::DB_INIT_LOCK |
										 Db::DB_INIT_LOG |
										 Db::DB_INIT_TXN);

					my $theMgr = new XmlManager($env);
					my $containerTxn = $theMgr->createTransaction();
					my $container = $theMgr->openContainer($containerTxn, $XMLDBCONT, Db::DB_CREATE);
					$containerTxn->commit();
					my $updateContext = $theMgr->createUpdateContext();

					my $query_txn = $theMgr->createTransaction();
					my $context2 = $theMgr->createQueryContext();
					$context2->setNamespace( "nmwg" => "http://ggf.org/ns/nmwg/base/2.0/");
					$context2->setNamespace( "netutil" => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/");
					$context2->setNamespace( "nmwgt" => "http://ggf.org/ns/nmwg/topology/2.0/");
					$context2->setNamespace( "ping" => "http://ggf.org/ns/nmwg/tools/ping/2.0/");
					$context2->setNamespace( "nmtl2" => "http://ggf.org/ns/nmwg/topology/l2/3.0/");
					$context2->setNamespace( "nmwgtopo3" => "http://ggf.org/ns/nmwg/topology/base/3.0/");

					@resultsString = getContents($theMgr, $container->getName(), $qs, $context2);
				};
				if (my $e = catch std::exception) {
					warn "Error adding XML data to container $XMLDBCONT\n" ;
					warn $e->what() . "\n";
					exit(-1);
				}
				elsif ($@) {
					warn "Error adding XML data to container $XMLDBCONT\n" ;
					warn $@;
					exit(-1);
				}


				if($#resultsString != -1) {

					for($x = 0; $x <= $#resultsString; $x++) {	
						$xp = XML::XPath->new( xml => $resultsString[$x] );
						$xp->clear_namespaces();

						$xp->set_namespace('nmwg', 'http://ggf.org/ns/nmwg/base/2.0/');
						$xp->set_namespace('netutil', 'http://ggf.org/ns/nmwg/characteristic/utilization/2.0/');
						$xp->set_namespace('nmwgt', 'http://ggf.org/ns/nmwg/topology/2.0/');
						$xp->set_namespace('ping', 'http://ggf.org/ns/nmwg/tools/ping/2.0/');

						$nodeset = $xp->find('//nmwg:metadata');
						if($nodeset->size() <= 0) {
							$writer->characters("Metadata element not found or in wrong namespace.");
						}
						else {
							foreach my $node ($nodeset->get_nodelist) {

								$writer->raw(XML::XPath::XMLParser::as_string($node));

								# if the query above is expanded to get more than a
								# single metadata block, then this part needs to be
								# more careful about what it does.  In the all_path
								# case, the nodeset contains links and nodes and we
								# only want to go to the DB for links.  For now, we
								# can skip further processing of "node" elements.

								$xp2 = XML::XPath->new( xml => XML::XPath::XMLParser::as_string($node) );
								$xp2->clear_namespaces();
								$xp2->set_namespace('nmwg', 'http://ggf.org/ns/nmwg/base/2.0/');
								$xp2->set_namespace('nmtl2',
																		'http://ggf.org/ns/nmwg/topology/l2/3.0/');
								$xp2->set_namespace('nmwgtopo3',
																		'http://ggf.org/ns/nmwg/topology/base/3.0/');

								# try to use xp2 to find if this is a topo node.
								# if it is, skip it.
								$nodeset = $xp2->find('/nmwg:metadata/nmwg:subject/nmwgtopo3:node');
								$s = $nodeset->size();
								if ($DEBUG > 3) {
									print ("$s nodes match that\n");
									foreach my $n3 ($nodeset->get_nodelist) {
										$txt = XML::XPath::XMLParser::as_string($n3);
										print ("they are: $txt\n");
									}
								}
								if($s > 0) { next; }

								my $eventType = "*";
								$nodeset = $xp2->find('//nmwg:parameter[@name="eventType"]');
								if($nodeset->size() > 0) {
									foreach my $node2 ($nodeset->get_nodelist) {
										$eventType = $node2->getAttribute("value");
									}
								}

								$mdId = $node->getAttribute("id");

								$cooked = genuid();

								if ($all_path_status ne 1) {
									## bogus for the general case
									$writer->startTag("nmwg:metadata",
																		"id" => $cooked);
									$writer->emptyTag("netutil:subject",
																		"id" => genuid(),
																		"metadataIdRef" => $mdId);
								}

								$sel = "select service_name, to_char(ts,'yyyy-mm-dd,hh24:mi:ss'), ifoperstatus from spectrum.mon where service_name=\'" . $mdId . "\'";
								#$sel = "select * from data where id=\"" . $mdId . "\" and ";
								#$sel = $sel . "eventtype=\"" . $eventType . "\"";

								# if there are parameters
								if($metadata{$m}{"nmwg:metadata/nmwg:parameters-id"}) {
									$writer->startTag("nmwg:parameters",
																		"id" => genuid());

									if($metadata{$m}{"nmwg:metadata/nmwg:parameters/select:parameter-time-gte"}) {
										$writer->startTag("select:parameter",
																			"name" => "time",
																			"operator" => "gte");
										$writer->characters($metadata{$m}{"nmwg:metadata/nmwg:parameters/select:parameter-time-gte"});
										$writer->endTag("select:parameter");

										$sel = $sel . " and time >= \"" . $metadata{$m}{"nmwg:metadata/nmwg:parameters/select:parameter-time-gte"} . "\"";
									}
									elsif($metadata{$m}{"nmwg:metadata/nmwg:parameters/select:parameter-time-lte"}) {
										$writer->startTag("select:parameter", 
																			"name" => "time",
																			"operator" => "lte");
										$writer->characters($metadata{$m}{"nmwg:metadata/nmwg:parameters/select:parameter-time-lte"});
										$writer->endTag("select:parameter");

										$sel = $sel . " and time <= \"" . $metadata{$m}{"nmwg:metadata/nmwg:parameters/select:parameter-time-lte"} . "\"";					
									}	
									elsif($metadata{$m}{"nmwg:metadata/nmwg:parameters/select:parameter-time-lt"}) {
										$writer->startTag("select:parameter", 
																			"name" => "time",
																			"operator" => "lt");
										$writer->characters($metadata{$m}{"nmwg:metadata/nmwg:parameters/select:parameter-time-lt"});
										$writer->endTag("select:parameter");
										
										$sel = $sel . " and time < \"" . $metadata{$m}{"nmwg:metadata/nmwg:parameters/select:parameter-time-lt"} . "\"";
									}
									elsif($metadata{$m}{"nmwg:metadata/nmwg:parameters/select:parameter-time-gt"}) {
										$writer->startTag("select:parameter", 
																			"name" => "time",
																			"operator" => "gt");
										$writer->characters($metadata{$m}{"nmwg:metadata/nmwg:parameters/select:parameter-time-gt"});
										$writer->endTag("select:parameter");
										
										$sel = $sel . " and time > \"" . $metadata{$m}{"nmwg:metadata/nmwg:parameters/select:parameter-time-gt"} . "\"";
									}
									# MS time eq
									elsif($metadata{$m}{"nmwg:metadata/nmwg:parameters/select:parameter-time-eq"}) {
										$writer->startTag("select:parameter", 
																			"name" => "time",
																			"operator" => "eq");
										$writer->characters($metadata{$m}{"nmwg:metadata/nmwg:parameters/select:parameter-time-eq"});
										$writer->endTag("select:parameter");
										
										if ($metadata{$m}{"nmwg:metadata/nmwg:parameters/select:parameter-time-eq"} eq "now") {
											print "woohoo\n";	
											exit(0);
										}
										else {
											$sel = $sel . " and time == \"" . $metadata{$m}{"nmwg:metadata/nmwg:parameters/select:parameter-time-eq"} . "\"";
										}	
									}
									elsif($metadata{$m}{"nmwg:metadata/nmwg:parameters/select:parameter-time-ne"}) {
										$writer->startTag("select:parameter", 
																			"name" => "time",
																			"operator" => "ne");
										$writer->characters($metadata{$m}{"nmwg:metadata/nmwg:parameters/select:parameter-time-ne"});
										$writer->endTag("select:parameter");
										
										$sel = $sel . " and time != \"" . $metadata{$m}{"nmwg:metadata/nmwg:parameters/select:parameter-time-ne"} . "\"";
									}
									else {
										print "woo2\n";
										exit(0);
									}

									$writer->endTag("nmwg:parameters");
								}
								if ($all_path_status ne 1) {
								$writer->endTag("nmwg:metadata");
								}

								$sel = $sel . "and ts = (select max(ts) from spectrum.mon where service_name=\'" . $mdId . "\')";

								#XXX				$sel = $sel . ";";
								# we have the query string, execute and wrap the results
								# in the datum elements...or error out

								$dbh = DBI->connect("$DBNAME","$DBUSER","$DBPASS")
									|| die "Database unavailable";		

								if ($all_path_status eq 1) {
									$writer->startTag("nmwg:data",
																		"metadataIdRef" => $mdId,
																		"id" => genuid());
								}

								else {
									$writer->startTag("nmwg:data",
																		"metadataIdRef" => $cooked,
																		"id" => genuid());
								}

								$array_ref = $dbh->selectall_arrayref($sel);
								if($#{$array_ref} != -1) {
									for($z = 0; $z <= $#{$array_ref}; $z++) {
										if($array_ref->[$z][2]) {
											$value_string = 'Up';
										}
										else {
											$value_string = 'Down';
										}
										$isotime = $array_ref->[$z][1];
										# the Oracle formatter wouldn't put the T in the
										# ISO timestamp, so there is a comma.
										$isotime =~ s/\,/T/;
										$isotime = "$isotime+1:00";
										$writer->startTag("ifevt:datum",
																			"timeType" => "ISO",
																			"timeValue" => $isotime);
										$writer->startTag("ifevt:stateOper");
										$writer->characters($value_string);
										$writer->endTag("ifevt:stateOper");
										$writer->startTag("ifevt:stateAdmin");
										$writer->characters("Unknown");
										$writer->endTag("ifevt:stateAdmin");
										$writer->endTag("ifevt:datum");
									}
								}
								else {
									$writer->startTag("nmwgr:datum");
									$writer->characters("No datum elements found on this server.\n");
									$writer->endTag("nmwgr:datum");
								}
								$writer->endTag("nmwg:data");

								$dbh->disconnect(); 
							}
						}
					}
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
# Sub:		readConf													 #
# Args:		$file - Filename to read					 #
# Purpose:	Read and store info.							 #
# ################################################ #
sub readConf {
	my ($file)	= @_;
	my $CONF = new IO::File("<$file") or die "Cannot open 'readConf' $file: $!\n" ;
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
# Sub:		goDeep														 #
# Args:		$set - set of children nodes			 #
#								$sent - flattened hash of metadata #
#												values passed through the	 #
#												recursion.								 #
# Purpose:	Keep enterning the metadata block	 #
#								revealing all important elements/	 #
#								attributes/values.								 #
# ################################################ #
sub goDeep {
	my ($set, $sent, $path) = @_;
	my %b = %{$sent};	 
	foreach my $element ($set->getChildNodes) {		

		$value = $element->getNodeValue;
		$value =~ s/\n//g;	
		$value =~ s/\s{2}//g;	 

		if($value != "" || $value != " " || !($element->getNodeValue =~ m/\n/)) { 
			if($element->getNodeType == 3) {
				if($element->getParentNode->getLocalName eq "parameter") {			
					if($element->getParentNode->getAttribute("name") && $element->getParentNode->getAttribute("operator")) {	
						$b{$path . "-" . $element->getParentNode->getAttribute("name") . "-" . $element->getParentNode->getAttribute("operator")} = $value;
						%b = goDeep($element, \%b, $path);		
					}
					elsif($element->getParentNode->getAttribute("name") && !($element->getParentNode->getAttribute("value"))) {	 
						$b{$path . "-" . $element->getParentNode->getAttribute("name")} = $value;
						%b = goDeep($element, \%b, $path);
					}			
				}
				else {
					$b{$path} = $element->getNodeValue;	
					%b = goDeep($element, \%b, $path);	
				}
			}
			else {
				if($element->getLocalName eq "parameter") {	
					if($element->getAttribute("name") && $element->getAttribute("value")) {
						$b{$path."/".$element->getPrefix .":" . $element->getLocalName . "-" . $element->getAttribute("name")} = $element->getAttribute("value");
						%b = goDeep($element, \%b, $path."/".$element->getPrefix .":" . $element->getLocalName);
					}
					elsif($element->getAttribute("name") && $element->getAttribute("operator")) {
						$b{$path."/".$element->getPrefix .":" . $element->getLocalName . "-" . $element->getAttribute("name") . "-" . $element->getAttribute("operator")} = $value;
						%b = goDeep($element, \%b, $path."/".$element->getPrefix .":" . $element->getLocalName);		
					}
				}
				else {
					foreach my $attr2 ($element->getAttributes) {
						$b{$path."/".$element->getPrefix .":" . $element->getLocalName . "-" . $attr2->getLocalName} = $attr2->getNodeValue;
					}			 
					%b = goDeep($element, \%b, $path."/".$element->getPrefix .":" . $element->getLocalName);
				}
			}			 
		}
	}
	return %b;
}


# ################################################ #
# Sub:		genuid														 #
# Args:		N/A																 #
# Purpose:	Generate a random number					 #
# ################################################ #
sub genuid {
	my($r) = int( rand( 16777216 ) );
	return ( $r + 1048576 );
}


# ################################################ #
# Sub:		getContents												 #
# Args:		$mgr - db connection manager			 #
#		$cname - collection name					 #
#		$query - What we are searching for #
#		$context - query context					 #
# Purpose:	Given the input, perform a query	 #
#								and return the results						 #
# ################################################ #
sub getContents($$$$) {
	my $mgr = shift ;
	my $cname = shift ;
	my $query = shift ;
	my $context = shift ;
	my $results = "";
	my $value = "";
	
	my @resString = ();
	my $fullQuery = "collection('$cname')$query";

	if ($DEBUG > 1) {
		print "QUERY: $query\n";
	}
	eval {
		$results = $mgr->query($fullQuery, $context);
		while( $results->next($value) ) {
			push @resString, $value."\n";
		}
		$value = "";
	};
	if (my $e = catch std::exception) {
		warn "Query $fullQuery failed\n";
		warn $e->what() . "\n";
		exit( -1 );
	}
	elsif ($@) {
		warn "Query $fullQuery failed\n";
		warn $@;
		exit( -1 );
	}
	return @resString;
}

1;
