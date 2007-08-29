#
#  pinger host info ( basically everything about Beacon site or simple monitored host)
#     
#     alias is an alias of the site name  for pingtables ( something like FNAL.GOV for pinger.fnal.gov)
#     dataurl is URL to ping_data.pl CGI sciprt for now, then LS will take over this function
#     traceurl is URL to traceroute.pl CGI sciprt for now, then LS will take over this function
#    
#   Notes: tinyint(1) is used for boolean ( since some DB lacks support for boolean type)
#          If DB supports serial ( auto_increment ) type then all primary keys named as xxx_id should be 
#          changed to serial ( auto_increment)
#
CREATE TABLE  hostInfo  (
 ip_name  varchar(52), 
 alias    varchar(20),          
 type_id   smallint, 
 address_id   int,   
 website  varchar(100),
 dataurl  varchar(100),
 traceurl  varchar(100),
 longitude  float,
 latitude  float,
 contact_id int, 
 FOREIGN KEY ( ip_name ) references host ( ip_name ), 
 FOREIGN KEY ( contact_id) references contacts ( contact_id), 
 FOREIGN KEY ( address_id) references address  (  address_id), 
 FOREIGN KEY ( type_id) references  types( type_id), 
 PRIMARY KEY  (ip_name));

#
#   the full address of the site 
#
CREATE  TABLE address (
  address_id  int,
  institution  varchar(100),
  address_line varchar(200),
  city  varchar(50),
  country  varchar(50),
  region_id  smallint,
  FOREIGN KEY ( region_id) references  regions( region_id), 
  PRIMARY KEY (address_id));

#
#   each site can be assigned to some region of the world( Asia, Europe, North_America etc)
#
CREATE TABLE regions (
  region_id  smallint,
  name varchar(20),
  PRIMARY KEY (region_id));
 
#
#   the type of the site ( Beacon, Monitoring Host, Monitored, Disabled.. anything else ?)
#
CREATE  TABLE types (
  type_id  smallint,
  name varchar(20),
  PRIMARY KEY (type_id));
 
#
#   each site can have multiple contact names and addresses
#
CREATE TABLE contacts (
  contact_id int,
  person varchar(100),
  email varchar(100),
  PRIMARY KEY (contact_id));

#
# ipaddr  table to keep track on what ip address was assigned with pinger hostname
#
CREATE TABLE   host (
 ip_name varchar(52) NOT NULL, 
 ip_number varchar(15) NOT NULL,
-- active_start  bigint(12) NOT NULL, 
-- active_end bigint(12)  NOT NULL, 
 comments blob,
-- FOREIGN KEY (ip_name) references hostInfo (ip_name),
 PRIMARY KEY  (ip_name, ip_number)); 

#
#     meta data table 
#
CREATE TABLE  metaData  (
 metaID varchar(52) NOT NULL,
 ip_name_src varchar(52),
 ip_name_dst varchar(52),
 transport varchar  NOT NULL,
 packetSize smallint   NOT NULL,
 count smallint   NOT NULL,
 packetInterval smallint,
 deadline smallint,
 ttl smallint,
 INDEX (ip_name_src,ip_name_dst,  packetSize, count),
 FOREIGN KEY (ip_name_src, ip_name_dst) references host (ip_name, ip_name),
 PRIMARY KEY  (metaID));


#
#   pinger data table, some fields have names differnt from XML schema since there where
#   inherited from the current pinger data table
#   pkts_rcvd field left as indicator of 100% loss test ( 0 packets )
#   its named data_yyyyMM to separate from old format - pairs_yyyyMM
#
CREATE TABLE  data_200707  (
 metaID varchar(52)   NOT NULL,
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
 rtts text, -- should be stored as csv of ping rtts
 seqNums text, -- should be stored as csv of ping sequence numbers
  INDEX(meanRtt, lossPercent, meanIpd ),
  FOREIGN KEY (metaID) references metaData (metaID),
  PRIMARY KEY  (metaID ,timestamp));


