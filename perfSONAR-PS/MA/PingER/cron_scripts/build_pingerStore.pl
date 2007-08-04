#! /usr/bin/perl -w
use strict;
use Carp;
use DBI;
select(STDOUT);
$| = 1;
 
my $username = 'www';
my $list_pairs_fl = '/home/netadmin/new_pinger/data/pinger_store.xml';
my %list_big=();
my $header =  qq(<?xml version="1.0" encoding="UTF-8"?>
 <nmwg:store type="store"
                  xmlns="http://ggf.org/ns/nmwg/base/2.0/" 
                 xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/" 
                 xmlns:pinger="http://ggf.org/ns/nmwg/tools/pinger/2.0/"
                 xmlns:topo="http://ggf.org/ns/nmwg/topology/2.0/"> 
		 
		 <!--  metadata section  -->
); 
open  PAIRFL, "+>$list_pairs_fl" or croak("Cant open ... $list_pairs_fl"); 
print PAIRFL $header;
 
my $dbh =  DBI->connect("DBI:mysql:pingerMA:localhost", $username, '',
                                                {RaiseError => 0,
                                                 PrintError => 0}) or 
           croak("Cant connect to database, please try later or send message to pinger\@fnal.gov " . $DBI::errstr);
my $select_stm = qq{select  metaID, ip_name_src,  ip_name_dst, ip_address_src, ip_address_dst, transport, packetSize, count, packetInterval  from metaData  };
my $sth =  $dbh->prepare("$select_stm");
   $sth->execute() or croak(" OOops , cant query MySQl DB: ". $DBI::errstr);
  
while(my($meta, $src_n, $dst_n, $src_ip, $dst_ip, $transp, $pingsz, $pkg_s, $inter) = $sth->fetchrow_array()) {
  print PAIRFL qq{ 
  <nmwg:metadata  xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/" id="meta$meta">
    <pinger:subject xmlns:pinger="http://ggf.org/ns/nmwg/tools/pinger/2.0/" id="subject$meta"> 
      <topo:endPointPair xmlns:topo="http://ggf.org/ns/nmwg/topology/2.0/">
        <topo:src type="ipv4" value="$src_n"/>
        <topo:dst type="ipv4" value="$dst_n"/>
      </topo:endPointPair>
    </pinger:subject>
    <pinger:parameters  xmlns:pinger="http://ggf.org/ns/nmwg/tools/pinger/2.0/">
      <nmwg:parameter name="count" value="$pkg_s"/>
      <nmwg:parameter name="interval" value="$inter"/>
      <nmwg:parameter name="packetSize" value="$pingsz"/> 
    </pinger:parameters>
  </nmwg:metadata>
  
    <nmwg:data xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/" id="data$meta" metadataIdRef="meta$meta">
       <nmwg:key>
               <nmwg:parameters> 
                   <nmwg:parameter name="type">mysql</nmwg:parameter>
                 
               </nmwg:parameters>
           </nmwg:key>
 </nmwg:data>

  };
 
}
print PAIRFL  " </nmwg:store>";
close PAIRFL;
$sth->finish();
$dbh->disconnect if $dbh; 
 
 

