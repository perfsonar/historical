#!/usr/bin/perl 
use strict;
use lib '/home/netadmin/new_pinger/lib';
use Carp;
use DBI;
use vars qw($opt_i $opt_o $opt_d $opt_m   $opt_v $opt_h); 
use Getopt::Std;
use Log::Log4perl qw(get_logger :levels);

use IEPM::PingER::Statistics;

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
our $debug = 0;

my $verbose = undef;
Log::Log4perl->init("/home/netadmin/new_pinger/data/logger.conf");

my $logger = Log::Log4perl::get_logger("add_2pinger_MA"); 

$debug = 1 if $opt_d;
$logger->level('WARN');
$logger->level('DEBUG') if $opt_d;

$verbose = 1 if $opt_v;
$logger->level('INFO') if $opt_v;

my $add_data_dir =  $opt_i;
 
die "Usage:: $0 [-d debug flag] [-v verbose flag] [-o store into the old format PingER DB] [-m store into the PingER MA DB] [-i <filename> data dir name where to look for add-xxxx-xx.txt files] " if (!$add_data_dir || $opt_h);
 
$add_data_dir = $opt_i;
my $pingerMA = $opt_m;
my $pingerOLD =$opt_o;
my $pass_fl = '/etc/my_pass';
my $username = 'pinger';
##################################

my $passwd;
open FLN, "<$pass_fl" or $logger->error(" Cant open pass file, check you userid or presence of: $pass_fl ");
$passwd = <FLN>; 
close FLN;
chomp $passwd;

my $TRANSPORT ='ICMP';
my $DBNAME = 'DBI:mysql:pingerMA:localhost';
my %metaCache = ();
my %ip_cache = ();
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

my $create_MA_host = q{
CREATE TABLE host (
 ip_name varchar(52) NOT NULL, 
 ip_number varchar(64) NOT NULL,
 comments text, 
 PRIMARY KEY  (ip_name, ip_number) );
 
};

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
 INDEX (ip_name_src, ip_name_dst,   packetSize, count, packetInterval, transport),
 FOREIGN KEY (ip_name_src) references host (ip_name),
 FOREIGN KEY (ip_name_dst) references host (ip_name),
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
   $logger->info("File:: $flname   ... all data going to MySQL table: $ad_db ");
   my $full_flname = "$add_data_dir/$flname"; 
   my($check_sth, $insert_sth,$update_sth,$insert_MA,$get_meta, $get_ip, $set_ip, $set_meta,$update_MA, $data_check ) ;   
   
   if($pingerOLD) {      
     checkAndCreateDB( $dbh,  {$ad_db => $create_Pinger} );
     $check_sth = $dbh->prepare_cached("select timestamp,  pkgs_rcvd, avrg_time from  $ad_db  where  ip_name_src = ?
   			      AND ip_name_dst = ? AND  pkg_size = ? AND timestamp = ?" )
   			      or  &grace_die("Can't prepare check select on  $ad_db ...". $DBI::errstr);
 
     $insert_sth  = $dbh->prepare_cached( "INSERT into $ad_db  VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")
   		       or  &grace_die("Can't prepare INSERT statement on  $ad_db ...". $DBI::errstr);
     $update_sth  = $dbh->prepare_cached("UPDATE  $ad_db  SET pkgs_sent  = ? , pkgs_rcvd  = ? ,
                                         min_time   = ? , avrg_time  = ? ,  max_time  = ?,
					 min_delay = ?,   ipdv = ? ,   max_delay  = ?,  dupl  = ?  where 
                                        ip_name_src  = ?  AND  ip_number_src  = ?  AND  ip_name_dst  = ?  AND ip_number_dst  = ? AND  pkg_size = ? AND  timestamp = ?" )
			  or  &grace_die("Can't prepare UPDATE statement on  $ad_db...". $DBI::errstr);  
   }
   my $ma_db = "data_$year$mon";
   
   if($pingerMA) {     
       $logger->info("                 ... and to pingerMA \n") if $pingerMA;
       checkAndCreateDB( $dbh_MA, {'host' => $create_MA_host, 'metaData' => $create_MA_meta, $ma_db =>  $create_MA_data});
       $data_check = $dbh_MA ->prepare_cached("select   lossPercent,  meanRtt, timestamp    from  $ma_db  where metaID=? and timestamp =?");
       $insert_MA =  $dbh_MA ->prepare_cached("INSERT into  $ma_db  (metaID,  minRtt, meanRtt, medianRtt, maxRtt,
                                          timestamp, minIpd,meanIpd,maxIpd,duplicates,outOfOrder,clp,iqrIpd,lossPercent ) 
                                        VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? )") or $logger->error("insert_MA   sql prepare failed: ". $DBI::errstr);
       $update_MA =  $dbh_MA ->prepare_cached(" UPDATE   $ma_db  SET   minRtt =?, meanRtt =?, medianRtt =?, maxRtt =?,
                                          minIpd =?,meanIpd =?,maxIpd =?,duplicates =?,outOfOrder =?,clp =?,iqrIpd =?,lossPercent =?  
                                          where metaID = ? and   timestamp = ?") or $logger->error("update_MA  sql prepare failed: ". $DBI::errstr);
					
      $get_meta = $dbh_MA->prepare_cached("select  a.metaID, a.count   from metaData a inner join  host b on a.ip_name_src = b.ip_name inner join host c on a.ip_name_dst = c.ip_name \
                          where   a.ip_name_src = ?    and a.ip_name_dst = ?   and a.packetSize  =? and a.count =? and a.packetInterval =? and a.transport=? and  \
                          a.metaID <> '' group by a.metaID order by a.count desc limit 1") or $logger->error("get_meta sql prepare failed: ". $DBI::errstr);	
      $get_ip = $dbh_MA->prepare_cached("select ip_number, comments from host where ip_name = ? and ip_number=?");
      $set_ip = $dbh_MA->prepare_cached("insert into host ( ip_name, ip_number, comments) values (?,?,?)");
      $set_meta = $dbh_MA->prepare_cached("insert into  metaData (ip_name_src, ip_name_dst,   packetSize, count, packetInterval, transport,\
                                          deadline, ttl) values    (?, ?, ?, ?, ?, ?, ?, ?) " ) or $logger->error("set_meta sql prepare failed: ". $DBI::errstr);					    
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
       $logger->debug("LINE:: $_");
       my $COUNT = 0;
       my ($duplicat, $reorder) =  (0, 0);     
       my ($max_delay, $min_delay, $ipdv, $median_delay) =  (0.0, 0.0, 0.0, 0.0);      
       my ($median_tm, $lossPercents, $clp,  $iqr_delay) = (0.0, 0.0, 0.0, 0.0);
       my ($seqs, $rtts) = (undef,undef);
       my(      $src_n,    $src_ip,     $dst_n,    $dst_ip,  $pingsz,  $times, $pkg_s,   $pkg_r,     $min_tm,    $avg_tm,    $max_tm, @pack_tms ) = split /\s+/; 
       
  #   /^(?:\s+)?([-\.\w]+)\s+([-\.\w]+)\s+([-\.\w]+)\s+([-\.\w]+)\s+([\.\d]+)\s+([\.\d]+)\s+([\.\d]+)(?:\s+([\.\d]+)\s+([\.\d]+)\s+([\.\d]+)\s+([\.\d]+)(?:\s+ ([\.\d]+))+)?/;
       if($src_n && $src_ip  && $dst_n && $dst_ip && $pingsz && $times && $pkg_s ) {
          $logger->info("--------------------------------------------------");     
	  $logger->debug("Array param:", join  "  ", @pack_tms);     
	  unless($src_n =~ /^[\w\.\-]+$/ && $dst_n =~ /^[\w\.\-]+$/) {
	     $skipped_lines{$ad_db}++;
	     $skipped_lines{$ma_db}++; 
	     next;
	  } 
	   
	  unless($pkg_r  && $avg_tm && $pkg_r =~ /^\d+$/ && $avg_tm =~ /^[\.\d]+$/  &&  ($pkg_r*2 - 1) ==  $#pack_tms && $pingsz <= 1500) {
	     $pkg_r = '0';$min_tm= '0';$avg_tm= '0';$max_tm= '0';$min_delay = 0;  $lossPercents = 100.0;
	  } else {
	       if(@pack_tms) {
	         ( $COUNT , $pkg_r,, ,$seqs, $rtts, $duplicat, $reorder) = &fixData($pkg_s, $pkg_r, \@pack_tms);
	         next unless $COUNT;
	         
	         $logger->debug("count=$COUNT seqs=$seqs rtts=$rtts  \n"); 
		 $lossPercents =  &IEPM::PingER::Statistics::Loss::calculate( $pkg_s, $pkg_r); 
	     
	         # hires result?
                 ($min_tm,  $avg_tm,  $max_tm,  $median_tm) = &IEPM::PingER::Statistics::RTT::calculate( $rtts  );
	         $logger->debug("RTTs:$min_tm,  $avg_tm,  $max_tm,  $median_tm \n");  
	         # ipd
                ($min_delay,  $ipdv,  $max_delay , $median_delay  ,  $iqr_delay) = &IEPM::PingER::Statistics::IPD::calculate( $rtts );
                $clp =  &IEPM::PingER::Statistics::Loss::CLP::calculate( $pkg_s, $pkg_r, $seqs );
	        $logger->debug("IPDV: $ipdv DUP : $duplicat \n");   
	      }  
	  }
          my $old_times  = $times + 315619200; 
          my  ($time_check, $check_rcv, $check_time)   = (0,0,0);
	  if($pingerOLD) {     
	    if($check_sth->execute( $src_n, $dst_n, $pingsz, $old_times)) {
	       ($time_check,$check_rcv, $check_time)   = $check_sth->fetchrow_array();   
	    } else {
	       $logger->warn("Can't  check $src_n, $dst_n, $pingsz,   $old_times" .  $DBI::errstr);
	       $skipped_lines{$ad_db}++;
	       next;
	    }
	  
            $logger->info(" Checking DB:$ad_db $src_n,$dst_n,$pingsz, $old_times \::: RCV =$check_rcv\::TIME =$check_time::");  
	    $check_sth->finish;
            unless($time_check) {     
	       $logger->info(" Inserting DB:$ad_db $src_n, $dst_n, $src_ip, $dst_ip, $pingsz, $pkg_s,
	       $pkg_r, $min_tm, $avg_tm, $max_tm,  $old_times, $min_delay, $ipdv, $max_delay ");	          
	       $insert_sth->execute($src_n, $dst_n, $src_ip, $dst_ip, $pingsz, $pkg_s, $pkg_r, $min_tm, $avg_tm, $max_tm, $old_times, $min_delay, $ipdv, $max_delay, $duplicat ) 
	                    or  $logger->warn("AT line: $total_lines{$ad_db} ... \n Can't INSERT into $ad_db new values: $src_n $dst_n $src_ip $dst_ip $pingsz $old_times   $pkg_s $pkg_r  $min_tm" . $DBI::errstr) unless $debug; 
               $insert_sth->finish unless $debug; 
	       $inserted_lines{$ad_db}++;
            } else {
	       $update_sth->execute($pkg_s, $pkg_r, $min_tm, $avg_tm, $max_tm, $min_delay, $ipdv, $max_delay, $duplicat, $src_n, $src_ip, $dst_n, $dst_ip, $pingsz,  $old_times) 
	                     or $logger->warn("Can't UPDATE  $ad_db with new values... " . $DBI::errstr) unless $debug;
               $update_sth->finish unless $debug; 
	        $logger->info(" Updating  $src_n, $dst_n, $src_ip, $dst_ip, $pingsz, $pkg_s, $pkg_r, $min_tm, $avg_tm, $max_tm, $old_times $min_delay, $ipdv, $max_delay");
	       $updated_lines{$ad_db}++;	  	  
	    }
	  }
	  
          if($pingerMA) {
	     $logger->info(" Checking META  $src_n,$dst_n,$pingsz  ::");  
	     &checkAddIP($src_n, $src_ip, $get_ip ,$set_ip, \%ip_cache) ;
	     &checkAddIP($dst_n, $dst_ip, $get_ip ,$set_ip, \%ip_cache) ;
	     
	     my $meta =  $metaCache{$src_n}{$dst_n}{$pingsz}{$COUNT}{1};
	     my $old_count = 0;
	     unless($meta) {
	        
	        if($get_meta->execute($src_n,    $dst_n,   $pingsz,  $COUNT, '1', $TRANSPORT )) {
	           ($meta, $old_count) = $get_meta->fetchrow_array();
	            if((!$meta || ($meta && $COUNT > 9 && $COUNT != $old_count)) && ($pkg_r > 0 && @pack_tms)) {
		         ## add metadata only if measurement was meanfull
		          unless($debug) {
			      $set_meta->execute($src_n ,$dst_n,  $pingsz,  $COUNT, '1', $TRANSPORT, '0', '0') 
			      or $logger->warn("Can't INSERT  meta $src_n ,$dst_n, $src_ip, $dst_ip,  $pingsz,  $COUNT ...: " . $DBI::errstr);  

		              # $meta  = $dbh_MA->last_insert_id(undef,undef, qw(metaData metaID));
		              $meta  = $dbh_MA->{q{mysql_insertid}};
		              $meta_lines++;
			      $set_meta->finish(); 
			  }
		    }  elsif($meta && $COUNT <10  ) {
		          $COUNT = $old_count;
		    }
		    $metaCache{$src_n}{$dst_n}{$pingsz}{$COUNT}{1} = $meta;
		    $get_meta->finish() if $get_meta; 
		 } else {
		     $logger->warn("Can't  check metaData $src_n, $dst_n, $src_ip, $dst_ip $pingsz $COUNT: " .  $DBI::errstr);
		     $skipped_lines{$ma_db}++; 
	             next;
		 }
		 
	    } 
	    my  ( $check_loss, $check_Rtt, $t_check)   = (0,0,0);
	  
	    if($data_check->execute( $meta ,  $times)) {
	        ( $check_loss, $check_Rtt, $t_check)   = $data_check ->fetchrow_array();   
	    } else {
	        $logger->warn("Can't  check $meta ,  $times" .  $DBI::errstr);
		$skipped_lines{$ma_db}++; 
	        next;
	    }
	    $data_check->finish();  
	    $logger->debug(" Checking DB:$ma_db $meta  ::");  

            unless($t_check) {     
	        $logger->debug(" Inserting DB:$ma_db  $meta,  $min_tm, $avg_tm, $median_tm, $max_tm,  $times, $min_delay, $ipdv, $max_delay $lossPercents ");	          
	        unless($debug) {
		    $insert_MA->execute($meta,  $min_tm, $avg_tm, $median_tm, $max_tm, $times, $min_delay, $ipdv, $max_delay, $duplicat, $reorder, $clp, $iqr_delay, $lossPercents ) 
		        or  $logger->warn("AT line: $total_lines{$ma_db} ... \n Can't INSERT into $ma_db new values:  $meta,    $min_tm, $avg_tm, $median_tm, $max_tm, $times " . $DBI::errstr); 
                    $insert_MA->finish;
	       }        
	       $inserted_lines{$ma_db}++;
            } else {
	       unless($debug) {
	          $update_MA->execute($min_tm, $avg_tm, $median_tm, $max_tm, $min_delay, $ipdv, $max_delay, $duplicat, $reorder, $clp, $iqr_delay, $lossPercents,  $meta , $times) 
	                  or  $logger->warn("Can't UPDATE  $ma_db with new values... $meta,    $min_tm, $avg_tm, $median_tm, $max_tm, $times  " . $DBI::errstr);
                  $update_MA->finish; 
	       }
	       $logger->info(" Updating MA  $meta,    $min_tm, $avg_tm, $median_tm, $max_tm, $times ");
	       $updated_lines{$ma_db}++;	  	  
	    }    
	  }
      } else {
           $logger->debug( " Line skipped:  $_");
	   $skipped_lines{$ad_db}++;
      }
   }
    
        
       
   
   close  INPUTFL;
    $logger->info( " ----------OLD DB:");
    $logger->info("Total lines:$total_lines{$ad_db} \n where \n
               Inserted rows:$inserted_lines{$ad_db}  Updated rows:$updated_lines{$ad_db}  Skipped lines:$skipped_lines{$ad_db} ");
    $logger->info(" ----------PingER MA DB:");
    $logger->info("Meta lines added: $meta_lines \n Total data table lines:$total_lines{$ma_db} \n where \n
     	 Inserted rows:$inserted_lines{$ma_db}  Updated rows:$updated_lines{$ma_db}  Skipped lines:$skipped_lines{$ma_db} ");
 
   unless($debug) {
      $logger->info("Deleting:: $add_data_dir/$flname "); 
      unlink "$add_data_dir/$flname" or warn("Can't  delete file:: $add_data_dir/$flname $!");
  }
}
$dbh->disconnect() if $dbh;
$dbh_MA->disconnect() if $dbh_MA;


sub grace_die {
 my $message = shift;
   $dbh->disconnect() if $dbh;
   $logger->error(" Abnormal exit:: $message  ");

}
# fix duplicates and sent packets  count
sub fixData {
  my ($max_seqn, $pkg_r, $vals_arref) = @_;
   
  if ( ref($vals_arref)  ne 'ARRAY' ) {
    $logger->error( "Input needs to be a reference to an array of rtt values ($vals_arref).");
    return (undef, undef, undef,  undef );
  } 
  my $arr_size =  (scalar @$vals_arref)/2;  
  my @seqs = ();
  my @rtts = ();
  my $last_seqn = 0;
  my ($duplicates, $outOfOrder) = (0,0);
  for ( my $ind = 0; $ind<$arr_size ; $ind++) {
     my $seqn = $vals_arref->[$ind];
     my $rtt =  $vals_arref->[$arr_size + $ind];
     $max_seqn = $seqn if $max_seqn<$seqn;
     if($ind && ($last_seqn  ==  $seqn)) {
        $duplicates++;
	next;
     } elsif($seqn && $last_seqn > $seqn) {
        $outOfOrder++;
     } 
     if( $rtt  =~ /^[\.\d]+$/  && $seqn =~ /^\d+$/) {
        push @seqs, $seqn;
	$last_seqn = $seqn;
        push @rtts, $rtt;
     } else {
       $logger->error("BAD data seqn=$seqn rtt=$rtt");
       return undef;
     }
  }  
  # dupicates were indicated and removed from the rtts and sequence numbers
	          
  $pkg_r = scalar @rtts if ($duplicates  && $pkg_r >  scalar @rtts );
  if ($pkg_r > $max_seqn){
    $logger->error("Still some problems with array r=$pkg_r s=$max_seqn: " .  (join ",",@seqs, @rtts) );
    return undef;
  }
  return $max_seqn, $pkg_r, \@seqs, \@rtts, $duplicates, $outOfOrder;
}
#
# check if ip address in the cache then if its in the Db, set the chache , if not then insert into the host table of pinger MA DB
#
sub checkAddIP {
   my($ip_name, $ip_addr, $get_ip ,$set_ip, $ip_cache) = @_;
   unless($ip_cache->{$ip_name}{$ip_addr}) {
     $get_ip->execute($ip_name ,   $ip_addr);
     my $ipn = undef;
     unless( ($ipn) =  $get_ip->fetchrow_array()) {
       $set_ip->execute($ip_name, $ip_addr);
       $ipn = $ip_addr;
       $set_ip->finish() if $set_ip;  
     } 
     $ip_cache->{$ip_name}{$ipn} = $ipn;
     $get_ip->finish() if $get_ip;  
   }
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
 
