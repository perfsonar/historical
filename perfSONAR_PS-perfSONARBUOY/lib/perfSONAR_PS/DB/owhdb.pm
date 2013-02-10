package perfSONAR_PS::DB::owhdb;

use strict;
use warnings;

our $VERSION = 3.3;
use DBI;
use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);
use perfSONAR_PS::Config::OWP::Utils;
use perfSONAR_PS::Utils::NetLogger;
use Time::Local;

use constant {
    DEFAULT_NS => 'http://ggf.org/ns/nmwg/characteristic/delay/summary/20110317',
    DEFAULT_NSPREFIX => 'summary'
};

sub new{
    my ($package, @args) = @_;
    my %args = validate(@args, {
					DBH => 1,
					XMLOUT => 1,
					NAMESPACE => 0,
					NSPREFIX => 0
				}
			);
			
	#Assign required arguments
    my $self = {
        'DBH' => $args{'DBH'},
        'XMLOUT' => $args{'XMLOUT'},
    };
    
    #setup NetLogger
    $self->{NETLOGGER} = get_logger("NetLogger");
    $self->{LOGGER}= get_logger("perfSONAR_PS::DB::owhdb");    
    
    #Assign optional arguments
    if($args{'NAMESPACE'}){
        $self->{'NAMESPACE'} = $args{'NAMESPACE'};
    }else{
        $self->{'NAMESPACE'} = DEFAULT_NS;
    }
    
    if($args{'NSPREFIX'}){
        $self->{'NSPREFIX'} = $args{'NSPREFIX'};
    }else{
        $self->{'NSPREFIX'} = DEFAULT_NSPREFIX;
    }
    
    bless($self, $package);
    
    return $self;
}

sub getDateTableList(){
	my($self, @args) = @_;
	my %args = validate(@args, {
                    startTime  => 1,
                    endTime     => 1,
				}
			);
        my $startTime = $args{'startTime'};
        my $endTime = $args{'endTime'};
        my $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.DB.OWHDB.getDateTableList.start");
    	$self->{NETLOGGER}->debug( $nlmsg );
	my @dateList;
	my $query = "SELECT year, month, day
				 FROM DATES;";
	my $year;
	my $month;
	my $day;
     $self->{LOGGER}->info("About to process query".$query);
    my $stmt = $self->{'DBH'}->prepare($query);
    $stmt->execute();
	
	
	$stmt->bind_columns( \$year, \$month, \$day );
	
	#from the result, filter dates based on start and endtime
	while($stmt->fetch()){
		#convert date to timestamp
		my $unixTS = timegm(0,0,0,$day,$month-1,$year);
		my $owampTableStartTime = time2owptime($unixTS);
		$unixTS = timegm(59,59,23,$day,$month-1,$year);
                my $owampTableEndTime = time2owptime($unixTS);

		#check if it falls between start and end time
		if($owampTableEndTime>=$startTime && $owampTableStartTime<=$endTime){
			#If yes, push it into dateList array
			push @dateList, sprintf "%04d%02d%02d", $year, $month, $day;			
		}		
	}
	$nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.DB.OWHDB.getDateTableList.end");
        $self->{NETLOGGER}->debug( $nlmsg );
	return \@dateList;
}


sub getNodeIdsFromIp(){
	my($self, @args) = @_;
    my %args = validate(@args, {
                tableName   => 1,
    			node_ip     => 1                  
				}
			);
	
	my $tableName = $args{'tableName'}.'_NODES';
	#query DB
	my $query = "SELECT node_id
				 FROM $tableName
				 WHERE addr=?";
				 
	my $stmt = $self->{'DBH'}->prepare($query);
    $stmt->execute($args{'node_ip'});
    $self->{LOGGER}->info("About to process query".$query);
    my $node_id;
    $stmt->bind_columns(\$node_id);
    
	my @nodeList;
	while($stmt->fetch()){
		push @nodeList, $node_id;
	}
	
	return \@nodeList;
}


sub fetchSummaryAndValueBuckets(){
    my($self, @args) = @_;
    my %args = validate(@args, {
                    tableName   => 1,
                    send_id     => 1,
                    recv_id     => 1,
                    si  => 1,
                    ei  => 1,
                    tspec_id    => 1,
                    timeType	=> 1 
				}
			);
    my %result;
    my %checkHash;
    my $dataTableName = $args{'tableName'}.'_DATA';
    my $delayTableName = $args{'tableName'}.'_DELAY';
    my $timeType = $args{'timeType'};
    my $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.DB.OWHDB.fetchSummaryAndValueBuckets.start");
    $self->{NETLOGGER}->debug( $nlmsg );
    $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.DB.OWHDB.DBaccess.start");
    $self->{NETLOGGER}->debug( $nlmsg ); 
    #DB access
    my $tspecCond = createSqlFilter('a.tspec_id', $args{'tspec_id'});
    my $sendCond = createSqlFilter('a.send_id', $args{'send_id'});
    my $recvCond = createSqlFilter('a.recv_id', $args{'recv_id'});
    my $query = "SELECT a.si, a.ei, a.stimestamp, a.etimestamp, a.start_time, a.end_time, 
    					a.min, a.max, a.minttl, a.maxttl,
    					a.sent, a.lost, a.dups, a.maxerr,
    					b.basei, b.i, b.n
    			 FROM $dataTableName as a 
    			 JOIN $delayTableName as b 
    			 ON a.send_id=b.send_id AND a.recv_id=b.recv_id AND a.tspec_id=b.tspec_id AND a.si=b.si AND a.ei=b.ei 
    			 WHERE a.si>? AND a.ei<?";
    if (defined $tspecCond && $tspecCond){
       $query .= " AND $tspecCond";
    }
    if (defined $sendCond && $sendCond){
       $query .= " AND $sendCond";
    }
    if (defined $recvCond && $recvCond){
       $query .= " AND $recvCond";
    }
    $query .= "ORDER BY a.si, b.i;";

    			
    my $stmt = $self->{'DBH'}->prepare($query);
    $stmt->execute($args{'si'}, $args{'ei'});
    
   $self->{LOGGER}->info("About to process query".$query);

    my @colnames = \($result{'si'},$result{'ei'},$result{'stimestamp'},$result{'etimestamp'},$result{'start_time'},$result{'end_time'},$result{'min'},$result{'max'},$result{'minttl'},$result{'maxttl'},$result{'sent'},$result{'loss'},$result{'dups'},$result{'maxerr'},$result{'basei'},$result{'i'},$result{'n'});
    $stmt->bind_columns( @colnames );
    my $cnt=0;
    
   $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.DB.OWHDB.DBaccess.end");
    $self->{NETLOGGER}->debug( $nlmsg );
    #create XML
    my $xmlTags;
    while($stmt->fetch()){
    	my $key = "$result{'si'}";
    	if(defined $checkHash{$key} and $checkHash{$key}){
    		
    		#create bucket tag 
    	     my %attrs = ();
        	 $attrs{"value"} = $result{'basei'} + $result{'i'};
        	 $attrs{"count"} = $result{'n'};
                $self->{'XMLOUT'}->fastCreateElement(
                        prefix      => $self->{'NSPREFIX'},
                        tag         => "value_bucket",
                        attributes  => \%attrs
                );

        	 #$xmlTags .= '<'.$self->{NSPREFIX}.':value_bucket value="'.$attrs{"value"}.'" count="'.$attrs{"count"}.'"/>';
    	}else{
    		
    		$checkHash{$key} = 1;
    		#close bucket tag for previous entry if not the entry point
    		if($cnt > 0){
			#$self->{'XMLOUT'}->addOpaque($xmlTags);
			$xmlTags = '';
    			$self->{'XMLOUT'}->endElement("value_buckets");
                	$self->{'XMLOUT'}->endElement("datum");
    		}
    		
    		#create summary tag
    		my %attributes = ();
            if ( $timeType eq "unix" ) {
            	$attributes{"timeType"}  = "unix";
                $attributes{"startTime"} = owptime2exacttime($result{'stimestamp'}) ;
                $attributes{"endTime"}   = owptime2exacttime($result{'etimestamp'}) ;
            }else {
                $attributes{"timeType"}  = "iso";
                $attributes{"startTime"} =  owpexactgmstring($result{'stimestamp'});
                $attributes{"endTime"}   =  owpexactgmstring($result{'etimestamp'}) ;
                    
            }

            #min
            $attributes{"min_delay"} = $result{'min'} if defined $result{'min'};

            # max
            $attributes{"max_delay"} = $result{'max'} if defined $result{'max'};

            # minTTL
            $attributes{"minTTL"} = $result{'minttl'} if defined $result{'minttl'};

            # maxTTL
            $attributes{"maxTTL"} = $result{'maxttl'} if defined $result{'maxttl'};

            #sent
            $attributes{"sent"} = $result{'sent'} if defined $result{'sent'};

            #lost
            $attributes{"loss"} = $result{'loss'} if defined $result{'loss'};

            #dups
            $attributes{"duplicates"} = $result{'dups'} if defined $result{'dups'};

            #err
            $attributes{"maxError"} = $result{'maxerr'} if defined $result{'maxerr'};
    		
    		$self->{'XMLOUT'}->startElement(
                   			         prefix     => $self->{'NSPREFIX'},
                    				 namespace  => $self->{'NAMESPACE'},
                    				 tag        => "datum",
                     				 attributes => \%attributes
                			);
    		$self->{'XMLOUT'}->startElement(
                                           prefix     => $self->{'NSPREFIX'},
                                           namespace  => $self->{'NAMESPACE'},
                                           tag        => "value_buckets",

	        	);	
    		#create bucket tag
    		my %attrs = ();
        	$attrs{"value"} = $result{'basei'} + $result{'i'};
        	$attrs{"count"} = $result{'n'};
        	$self->{'XMLOUT'}->fastCreateElement(
            		prefix      => $self->{'NSPREFIX'},
            		tag         => "value_bucket",
            		attributes  => \%attrs
        	);
    		#$xmlTags = '<'.$self->{NSPREFIX}.':value_bucket value="'.$attrs{"value"}.'" count="'.$attrs{"count"}.'"/>';
    		
    	}
	$cnt++;
    }
    #close everything finally
    $self->{'XMLOUT'}->endElement("value_buckets");
    $self->{'XMLOUT'}->endElement("datum");
    
    $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.DB.OWHDB.fetchSummaryAndValueBuckets.end");
    $self->{NETLOGGER}->debug( $nlmsg );
    return $cnt;

}



sub fetchSummaryData(){
 		my($self, @args) = @_;
		my %args = validate(@args, {
                    tableName   => 1,
                    send_id     => 1,
                    recv_id     => 1,
                    si  => 1,
                    ei  => 1,
                    tspec_id    => 1,
                    timeType	=> 1 
				}
			);
    my %result;
    my %checkHash;
    my $dataTableName = $args{'tableName'}.'_DATA';
    my $timeType = $args{'timeType'};
    my $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.DB.OWHDB.fetchSummaryData.start");
    $self->{NETLOGGER}->debug( $nlmsg );
    
    #DB access
    my $tspecCond = createSqlFilter('a.tspec_id', $args{'tspec_id'});
    my $sendCond = createSqlFilter('a.send_id', $args{'send_id'});
    my $recvCond = createSqlFilter('a.recv_id', $args{'recv_id'});
    my $query = "SELECT a.si, a.ei, a.stimestamp, a.etimestamp, a.start_time, a.end_time, 
    					a.min, a.max, a.minttl, a.maxttl,
    					a.sent, a.lost, a.dups, a.maxerr
    			 FROM $dataTableName AS a
    			 WHERE a.si>? AND a.ei<?";
    if (defined $tspecCond && $tspecCond){
       $query .= " AND $tspecCond";
    }
    if (defined $sendCond && $sendCond){
       $query .= " AND $sendCond";
    }   
    if (defined $recvCond && $recvCond){
       $query .= " AND $recvCond";
    }   
    $query .= "ORDER BY a.si;";
    $self->{LOGGER}->info("About to process query".$query);			
    $self->{LOGGER}->info("send_id,recv_id:".@{$args{'send_id'}}.",".@{$args{'recv_id'}});
    my $stmt = $self->{'DBH'}->prepare($query);
    $stmt->execute($args{'si'}, $args{'ei'});
    

    my @colnames = \($result{'si'},$result{'ei'},$result{'stimestamp'},$result{'etimestamp'},$result{'start_time'},$result{'end_time'},$result{'min'},$result{'max'},$result{'minttl'},$result{'maxttl'},$result{'sent'},$result{'loss'},$result{'dups'},$result{'maxerr'});
    $stmt->bind_columns( @colnames );
    my $cnt=0;
    
    #create XML
    while($stmt->fetch()){
   		$self->{LOGGER}->info("Processing DB results"); 
    		#create summary tag
    		my %attributes = ();
            if ( $timeType eq "unix" ) {
            	$attributes{"timeType"}  = "unix";
                $attributes{"startTime"} = owptime2exacttime($result{'stimestamp'}) ;
                $attributes{"endTime"}   = owptime2exacttime($result{'etimestamp'}) ;
            }else {
                $attributes{"timeType"}  = "iso";
                $attributes{"startTime"} =  owpexactgmstring($result{'stimestamp'});
                $attributes{"endTime"}   =  owpexactgmstring($result{'etimestamp'}) ;
                    
            }

            #min
            $attributes{"min_delay"} = $result{'min'} if defined $result{'min'};

            # max
            $attributes{"max_delay"} = $result{'max'} if defined $result{'max'};

            # minTTL
            $attributes{"minTTL"} = $result{'minttl'} if defined $result{'minttl'};

            # maxTTL
            $attributes{"maxTTL"} = $result{'maxttl'} if defined $result{'maxttl'};

            #sent
            $attributes{"sent"} = $result{'sent'} if defined $result{'sent'};

            #lost
            $attributes{"loss"} = $result{'loss'} if defined $result{'loss'};

            #dups
            $attributes{"duplicates"} = $result{'dups'} if defined $result{'dups'};

            #err
            $attributes{"maxError"} = $result{'maxerr'} if defined $result{'maxerr'};
    		
    		$self->{'XMLOUT'}->createElement(
                   			         prefix     => $self->{'NSPREFIX'},
                    				 namespace  => $self->{'NAMESPACE'},
                    				 tag        => "datum",
                     				 attributes => \%attributes
                			);
            $cnt++;
      } 
    $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.DB.OWHDB.fetchSummaryData.end");
    $self->{NETLOGGER}->debug( $nlmsg );
    
    return $cnt;
}

sub createSqlFilter(){
	my($dbField, $dataList) = @_;
	
	 my $sqlCond = q{};
        if ( $#{$dataList} >= 0 ) {
            foreach my $r ( @{$dataList} ) {
                $sqlCond .= " or " if $sqlCond;
                $sqlCond .= " ( " unless $sqlCond;
                $sqlCond .= " $dbField=\"" . $r . "\"";
            }
            $sqlCond .= " ) ";
        }
     return $sqlCond;
}
