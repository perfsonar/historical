#!/usr/bin/perl -w
use strict;
use Carp;
use DBI;
use vars qw($opt_i $opt_o $opt_d $opt_m   $opt_v $opt_h); 
use Getopt::Std;
#############################################################
## version 2.1a
#
#      !!! Should be run under pinger(or root)  account !!!
#      Purpose of script:  add new data to MySQL DB table and pinger MA DB
#
#                                                   MPG, 2001 - 2007
#
#############################################################
select(STDOUT);
$| = 1;

##
#### Configure next lines #########
##
getopts("hi:dvmo");
my $debug = 0;
my $verbose = undef;
 
$debug = 1 if $opt_d;
$verbose = 1 if $opt_v;
my $add_data_dir = "/tmp/data";
unless($debug) {
   $add_data_dir = $opt_i;
   die "Usage:: $0 [-d debug flag] [-v verbose flag] [-o store into the old format PingER DB] [-m store into the PingER MA DB] [-i <filename> data dir name where to look for add-xxxx-xx.txt files] " if (!$add_data_dir || $opt_h);
}
$add_data_dir = $opt_i;
my $pingerMA = $opt_m;
my $pingerOLD =$opt_o;
my $pass_fl = '/etc/my_pass';
my $username = 'pinger';
##################################

my $passwd;
open FLN, "<$pass_fl" or croak(" Cant open pass file, check you userid or presence of: $pass_fl ");
$passwd = <FLN>; 
close FLN;
chomp $passwd;

my $TRANSPORT ='ICMP';
my $DBNAME = 'DBI:mysql:pingerMA:localhost';
my %metaCache = ();

my($dbh, $dbh_MA );
my $create_Pinger =q{create  table  <tablename> 
       (ip_name_src   char(52) binary NOT NULL, ip_name_dst  char(52) binary NOT NULL, 
        ip_number_src  char(15) binary NOT NULL,  ip_number_dst  char(15) binary NOT NULL,
	 pkg_size smallint(4) unsigned  NOT NULL, pkgs_sent smallint(4) unsigned NOT NULL,
	  pkgs_rcvd smallint(4) unsigned NOT NULL, min_time float NOT NULL,
	   avrg_time float NOT NULL, max_time float NOT NULL,
	    timestamp bigint(12) unsigned NOT NULL, min_delay  float NOT NULL,
	     ipdv FLOAT   NOT NULL,  max_delay FLOAT  NOT NULL, 
	     dupl FLOAT  NOT NULL, primary key (ip_name_src, ip_name_dst, pkg_size, timestamp))};
my $create_MA_meta 	=    
q{CREATE TABLE  metaData  (metaID BIGINT NOT NULL AUTO_INCREMENT,
 ip_name_src varchar(52),
 ip_name_dst varchar(52),
 ip_address_src varchar(64),
 ip_address_dst varchar(64),
 transport varchar(10)  NOT NULL,
 packetSize smallint   NOT NULL,
 count smallint   NOT NULL,
 packetInterval smallint,
 deadline smallint,
 ttl smallint,
 INDEX (ip_name_src, ip_name_dst, ip_address_src, ip_address_dst, packetSize, count,packetInterval, transport),
 PRIMARY KEY  (metaID))};
my $create_MA_data = 
q{ CREATE TABLE  <tablename>   (metaID   BIGINT   NOT NULL,
 minRtt float,
 meanRtt float,
 medianRtt float,
 maxRtt float,
 timestamp bigint(12) NOT NULL,
 minIpd float,
 meanIpd float,
 maxIpd float,
 duplicates tinyint(1),
 outOfOrder  tinyint(1),
 clp float,
 iqrIpd float,
 lossPercent  float,
 rtts text,  
 seqNums text,  
 INDEX (meanRtt, medianRtt, lossPercent, meanIpd, clp),
 FOREIGN KEY (metaID) references metaData (metaID),
 PRIMARY KEY  (metaID, timestamp))};
if($pingerOLD) {  
    $dbh =  DBI->connect( $DBNAME , $username, $passwd,
                                                {RaiseError => 0,
						 PrintError => 0}) or 
           &grace_die("Cant connect to database, please try later or send message to pinger\@fnal.gov " . $DBI::errstr);
} 
if($pingerMA) {  
    $dbh_MA = DBI->connect( $DBNAME , $username, $passwd,
                                                {RaiseError => 0,
						 PrintError => 0}) or 
           &grace_die("Cant connect to pingerMA database, please try later or send message to pinger\@fnal.gov " . $DBI::errstr);

}
opendir INPUT_DIR, $add_data_dir or &grace_die("Can't open $add_data_dir: $!");
my @add_files = grep /^add-ping/, readdir INPUT_DIR;

foreach  my $flname (@add_files) { 
   my ($year, $mon) = $flname =~ /add-ping-(\d+)-(\d+)\.txt/; 
   my $ad_db = "pairs_$year$mon";
   print  "File:: $flname   ... all data going to MySQL table: $ad_db \n";
   my $full_flname = "$add_data_dir/$flname"; 
   my($check_sth, $insert_sth,$update_sth,$insert_MA,$get_meta, $set_meta,$update_MA, $data_check ) ;   
   
   if($pingerOLD) {      
     checkAndCreateDB( $dbh,  {$ad_db => $create_Pinger} );
     $check_sth = $dbh->prepare("select timestamp,  pkgs_rcvd, avrg_time from  $ad_db  where  ip_name_src = ?
   			      AND ip_name_dst = ? AND  pkg_size = ? AND timestamp = ?" )
   			      or  &grace_die("Can't prepare check select on  $ad_db ...". $DBI::errstr);
 
     $insert_sth  = $dbh->prepare( "INSERT into $ad_db  VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")
   		       or  &grace_die("Can't prepare INSERT statement on  $ad_db ...". $DBI::errstr);
     $update_sth  = $dbh->prepare("UPDATE  $ad_db  SET pkgs_sent  = ? , pkgs_rcvd  = ? ,
                                         min_time   = ? , avrg_time  = ? ,  max_time  = ?,
					 min_delay = ?,   ipdv = ? ,   max_delay  = ?,  dupl  = ?  where 
                                        ip_name_src  = ?  AND  ip_number_src  = ?  AND  ip_name_dst  = ?  AND ip_number_dst  = ? AND  pkg_size = ? AND  timestamp = ?" )
			  or  &grace_die("Can't prepare UPDATE statement on  $ad_db...". $DBI::errstr);  
   }
   my $ma_db = "data_$year$mon";
   
   if($pingerMA) {     
      print  "                 ... and to pingerMA \n" if $pingerMA;
      checkAndCreateDB( $dbh_MA, {'metaData' => $create_MA_meta, $ma_db =>  $create_MA_data});
      $data_check = $dbh_MA ->prepare("select   lossPercent,  meanRtt, timestamp    from  $ma_db  where metaID=? and timestamp =?");
      $insert_MA =  $dbh_MA ->prepare("INSERT into  $ma_db  (metaID,  minRtt, meanRtt, medianRtt, maxRtt,
                                          timestamp, minIpd,meanIpd,maxIpd,duplicates,outOfOrder,clp,iqrIpd,lossPercent ) 
                                        VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? )");
     $update_MA =  $dbh_MA ->prepare(" UPDATE   $ma_db  SET   minRtt =?, meanRtt =?, medianRtt =?, maxRtt =?,
                                          minIpd =?,meanIpd =?,maxIpd =?,duplicates =?,outOfOrder =?,clp =?,iqrIpd =?,lossPercent =?  
                                          where metaID = ? and   timestamp = ?");
					
     $get_meta = $dbh_MA ->prepare("select metaID from  metaData where ip_name_src =? and  ip_name_dst  =? and ip_address_src =? and  ip_address_dst  =? and packetSize  =? and count =? and packetInterval =? and transport=?  " );	
  	
     $set_meta = $dbh_MA->prepare("insert into  metaData (ip_name_src, ip_name_dst, ip_address_src, ip_address_dst, packetSize, count, packetInterval, transport,    deadline, ttl) values
                                    (?, ?, ?, ?, ?, ?, ?, ?,?,?) " );					    
   }
   my  %total_lines = ($ad_db  => 0,  $ma_db=> 0);
   my  %inserted_lines  =  ($ad_db  => 0,  $ma_db=> 0);
   my  %updated_lines =  ($ad_db  => 0,  $ma_db=> 0);
   my  %skipped_lines =  ($ad_db  => 0,  $ma_db=> 0);
   my  $meta_lines = 0;
  
   open INPUTFL, "<$full_flname" or  &grace_die("Cant  open file: $full_flname ");
  
   while(<INPUTFL>) {
       chomp;
       $total_lines{$ad_db}++;
       $total_lines{$ma_db}++;   
       s/^(\s+)?//;
       my ($duplicat, $reorder) = qw/0 0/;     
       my ($max_delay, $min_delay, $ipdv) = qw/0. 100000. 0./;      
       my ($median, $lossPercents, $clp,  $iqr_delay) = (0.0, 0.0, 0.0, 0.0, );
       my(      $src_n,    $src_ip,     $dst_n,    $dst_ip,  $pingsz,  $times, $pkg_s,   $pkg_r,     $min_tm,    $avg_tm,    $max_tm, @pack_tms ) = split /\s+/; 
       
  #   /^(?:\s+)?([-\.\w]+)\s+([-\.\w]+)\s+([-\.\w]+)\s+([-\.\w]+)\s+([\.\d]+)\s+([\.\d]+)\s+([\.\d]+)(?:\s+([\.\d]+)\s+([\.\d]+)\s+([\.\d]+)\s+([\.\d]+)(?:\s+ ([\.\d]+))+)?/;
       if($src_n && $src_ip  && $dst_n && $dst_ip && $pingsz && $times && $pkg_s ) {
          print "--------------------------------------------------\n" if $debug || $verbose;     
	  print "Array param:", join  "  ", @pack_tms , " \n" if $debug;     
	  unless($src_n =~ /^[\w\.\-]+$/ && $dst_n =~ /^[\w\.\-]+$/) {
	     $skipped_lines{$ad_db}++;
	     $skipped_lines{$ma_db}++; 
	     next;
	  }  
	  unless($pkg_r  && $avg_tm && $pkg_r =~ /^\d+$/ && $avg_tm =~ /^[\.\d]+$/  &&  ($pkg_r*2 - 1) ==  $#pack_tms && $pingsz <= 1500) {
	     $pkg_r = '0';$min_tm= '0';$avg_tm= '0';$max_tm= '0';$min_delay = 0;  $lossPercents = 100.0;
	  } else {
	      my %pkts = ();
	      $lossPercents = ($pkg_s > 0)?($pkg_s - $pkg_r)/$pkg_s * 100.:100.;
	      my $last_seq = 0;
	      my $last_ping = 0;
	      # slow method for median O(NlogN)
	      my @sorted_pings = sort {$a <=> $b}  @pack_tms[$pkg_r..($pkg_r*2-1)];
	      my $sorted_lastind = $#sorted_pings;
	      $median = ($sorted_lastind==0)?$sorted_pings[0]:
	                       ($sorted_lastind==1)?($sorted_pings[0]+$sorted_pings[1])/2:
			            ($sorted_lastind % 2)?($sorted_pings[($sorted_lastind-1)/2]+$sorted_pings[($sorted_lastind+1)/2])/2:$sorted_pings[$sorted_lastind/2];  
	     
	        
	       for(my $i = 0; $i <  $pkg_r ; $i++) { 
	           my $cur = $pack_tms[$i];
		   
                   $duplicat = 1 if(++$pkts{$cur} > 1); 
	           $reorder = 1  if($i !=  $pack_tms[$i]   && $pkg_s == $pkg_r);   
	       
	         # check inter-packets delays
	              
		      my $idl = abs ($pack_tms[$i+$pkg_r] - $pack_tms[$i + 1+$pkg_r]) if  $pack_tms[$i + 1+$pkg_r];
	              if($idl) {
		       $max_delay = $idl if($max_delay < $idl);
                       $min_delay = $idl if($min_delay > $idl);          	             
                       $ipdv +=$idl;  
		     }    
                 }
	      
	     $ipdv= $ipdv/($pkg_r - 1) if $pkg_r > 1;
	   
	     print "IPDV: $ipdv DUP/REOR: $duplicat/$reorder\n" if $debug;     
	  }
          my $old_times  = $times + 315619200; 
          my  ($time_check, $check_rcv, $check_time)   = (0,0,0);
	  if($pingerOLD) {     
	    if($check_sth->execute( $src_n, $dst_n, $pingsz, $old_times)) {
	       ($time_check,$check_rcv, $check_time)   = $check_sth->fetchrow_array();   
	    } else {
	       carp("Can't  check $src_n, $dst_n, $pingsz,   $old_times" .  $DBI::errstr);
	       $skipped_lines{$ad_db}++;
	       next;
	    }
	  
            print " Checking DB:$ad_db $src_n,$dst_n,$pingsz, $old_times \::: RCV =$check_rcv\::TIME =$check_time\::\n" if $debug || $verbose;  
	    $check_sth->finish;
            unless($time_check) {     
	       print " Inserting DB:$ad_db $src_n, $dst_n, $src_ip, $dst_ip, $pingsz, $pkg_s, $pkg_r, $min_tm, $avg_tm, $max_tm,  $old_times, $min_delay, $ipdv, $max_delay \n" if $debug || $verbose;	          
	       $insert_sth->execute($src_n, $dst_n, $src_ip, $dst_ip, $pingsz, $pkg_s, $pkg_r, $min_tm, $avg_tm, $max_tm, $old_times, $min_delay, $ipdv, $max_delay, $duplicat ) 
	                    or  carp("AT line: $total_lines{$ad_db} ... \n Can't INSERT into $ad_db new values: $src_n $dst_n $src_ip $dst_ip $pingsz $old_times   $pkg_s $pkg_r  $min_tm" . $DBI::errstr) unless $debug; 
               $insert_sth->finish unless $debug; 
	       $inserted_lines{$ad_db}++;
            } else {
	       $update_sth->execute($pkg_s, $pkg_r, $min_tm, $avg_tm, $max_tm, $min_delay, $ipdv, $max_delay, $duplicat, $src_n, $src_ip, $dst_n, $dst_ip, $pingsz,  $old_times) 
	                     or carp("Can't UPDATE  $ad_db with new values... " . $DBI::errstr) unless $debug;
               $update_sth->finish unless $debug; 
	       print " Updating  $src_n, $dst_n, $src_ip, $dst_ip, $pingsz, $pkg_s, $pkg_r, $min_tm, $avg_tm, $max_tm, $old_times $min_delay, $ipdv, $max_delay, \n" if $debug || $verbose;
	       $updated_lines{$ad_db}++;	  	  
	    }
	  }
	  
          if($pingerMA) {
	     print " Checking META  $src_n,$dst_n,$pingsz  \::\n" if $debug || $verbose;  
	
	     my $meta =  $metaCache{$src_n}{$dst_n}{$src_ip}{$dst_ip}{$pingsz}{$pkg_s}{1};
	     unless($meta) {
	        if($get_meta->execute($src_n, $dst_n, $src_ip, $dst_ip, $pingsz, $pkg_s, '1', $TRANSPORT )) {
	           ($meta) = $get_meta->fetchrow_array();
	            unless($meta) {
		        $set_meta->execute($src_n ,$dst_n, $src_ip, $dst_ip,  $pingsz, $pkg_s, '1', $TRANSPORT, '0', '0') 
			    or carp("Can't INSERT  meta $src_n ,$dst_n, $src_ip, $dst_ip,  $pingsz, $pkg_s ... " . $DBI::errstr) unless $debug;; 

		      # $meta  = $dbh_MA->last_insert_id(undef,undef, qw(metaData metaID));
		        $meta  = $dbh_MA->{q{mysql_insertid}};
			
		       $meta_lines++;
                    }  
		    $metaCache{$src_n}{$dst_n}{$src_ip}{$dst_ip}{$pingsz}{$pkg_s}{1} = $meta;
		 } else {
		    carp("Can't  check metaData $src_n, $dst_n, $src_ip, $dst_ip $pingsz$pkg_s " .  $DBI::errstr);
		     $skipped_lines{$ma_db}++; 
	            next;
		 }
		 $get_meta->finish();   
	    } 
	    my  ( $check_loss, $check_Rtt, $t_check)   = (0,0,0);
	  
	    if($data_check->execute( $meta ,  $times)) {
	        ( $check_loss, $check_Rtt, $t_check)   = $data_check ->fetchrow_array();   
	    } else {
	        carp("Can't  check $meta ,  $times" .  $DBI::errstr);
		$skipped_lines{$ma_db}++; 
	        next;
	    }
	    $data_check->finish();  
	    print " Checking DB:$ma_db $meta   $times  \::\n" if $debug || $verbose;  

            unless( $t_check) {     
	        print " Inserting DB:$ma_db  $meta,  $min_tm, $avg_tm, $median, $max_tm,  $times, $min_delay, $ipdv, $max_delay $lossPercents \n" if $debug || $verbose;	          
	        unless($debug) {
		    $insert_MA->execute($meta,  $min_tm, $avg_tm, $median, $max_tm, $times, $min_delay, $ipdv, $max_delay, $duplicat, $reorder, $clp, $iqr_delay, $lossPercents ) 
		        or  carp("AT line: $total_lines{$ma_db} ... \n Can't INSERT into $ma_db new values:  $meta,    $min_tm, $avg_tm, $median, $max_tm, $times " . $DBI::errstr); 
                    $insert_MA->finish;
	       }        
	       $inserted_lines{$ma_db}++;
            } else {
	       unless($debug) {
	          $update_MA->execute(  $min_tm, $avg_tm, $median, $max_tm, $min_delay, $ipdv, $max_delay, $duplicat, $reorder, $clp, $iqr_delay, $lossPercents,  $meta , $times) 
	                  or carp("Can't UPDATE  $ma_db with new values... $meta,    $min_tm, $avg_tm, $median, $max_tm, $times  " . $DBI::errstr);
                  $update_MA->finish; 
	       }
	       print " Updating MA  $meta,    $min_tm, $avg_tm, $median, $max_tm, $times  \n" if $debug || $verbose;
	       $updated_lines{$ma_db}++;	  	  
	    }    
	  }
      } else {
        
         print " Line skipped:  $_" if $debug;
	 $skipped_lines{$ad_db}++;
      }
   }
   close  INPUTFL;
   print " ----------OLD DB:\n";
   print "Total lines:$total_lines{$ad_db} \n where \n    Inserted rows:$inserted_lines{$ad_db}  Updated rows:$updated_lines{$ad_db}  Skipped lines:$skipped_lines{$ad_db} \n";
   print " ----------PingER MA DB:\n";
   print "Meta lines added: $meta_lines \n Total data table lines:$total_lines{$ma_db} \n where \n    Inserted rows:$inserted_lines{$ma_db}  Updated rows:$updated_lines{$ma_db}  Skipped lines:$skipped_lines{$ma_db} \n";
 
   unless($debug) {
      print "Deleting:: $add_data_dir/$flname \n"; 
      unlink "$add_data_dir/$flname" or warn("Can't  delete file:: $add_data_dir/$flname $!");
  }
}
$dbh->disconnect() if $dbh;
$dbh_MA->disconnect() if $dbh_MA;


sub grace_die {
 my $message = shift;
   $dbh->disconnect() if $dbh;
   croak(" Abnormal exit:: $message  ");

}

sub checkAndCreateDB {
 my ( $dbhh, $sqls) = @_;
 foreach my $table (keys %{$sqls}) {
    my $show_sth =  $dbhh->prepare("desc  $table");
    $show_sth->execute();
    my @arr_desc =  $show_sth->fetchrow_array();
    $show_sth->finish;  
    if(@arr_desc == 0 || $DBI::err) {
        $sqls->{$table}  =~ s/\<tablename\>/$table/m;
        my  $create_db =  $dbhh->prepare($sqls->{$table});
        $create_db->execute() or  &grace_die("Failed to execute:  " . $sqls->{$table} . $DBI::errstr); 
        $create_db->finish;   
    }
 } 
}
 
