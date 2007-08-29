#
#  pinger beacons ( basically everything about Beacon site  )
#     
#     alias is an alias of the site name  for pingtables ( something like FNAL.GOV for pinger.fnal.gov)
#     dataurl is URL to ping_data.pl CGI sciprt for now, then LS will take over this function
#     traceurl is URL to traceroute.pl CGI sciprt for now, then LS will take over this function
#    
#   Notes: boolean is used for boolean ( since some DB lacks support for boolean type)
#         
#  
#
# 
#
CREATE  TABLE beacons (
  ip_name text NOT NULL,
  alias    text,   
  address_id   int,   
  website  text,
  dataurl  text,
  traceurl  text,
  longitude  real,
  latitude  real,
  contact_id int, 
  updated timestamp,
  FOREIGN KEY ( contact_id) references contacts ( contact_id), 
  FOREIGN KEY ( address_id) references address  (  address_id), 
  PRIMARY KEY (ip_name)); 
#
#   the full address of the site , could be couple of sites per address
#
CREATE  TABLE address (
  address_id  int,
  institution  text,
  address_line text,
  city  text,
  country  text,
  region_id  smallint,
  FOREIGN KEY ( region_id) references  regions( region_id), 
  PRIMARY KEY (address_id));

#
#   each site can be assigned to some region of the world( Asia, Europe, North_America etc)
#
CREATE TABLE regions (
  region_id  smallint,
  name text,
  PRIMARY KEY (region_id));
#
#   each site can have multiple contact names and addresses
#
CREATE TABLE contacts (
  contact_id int,
  person text,
  email text,
  PRIMARY KEY (contact_id));
# 
# ------------------------------------The part above is for beacons and pinger website ( means administering tasks)--
#
#----------------------------------------------- The part below is for collection and pinger MA----------------------
#
# ipaddr  table to keep track on what ip address was assigned with pinger hostname
#   ip_number has length of 64 - to accomodate possible IPv6 
#
CREATE TABLE host (
 ip_name text NOT NULL, 
 ip_number text NOT NULL,
-- active_start  bigint NOT NULL, 
-- active_end bigint  NOT NULL, 
 comments text, 
 PRIMARY KEY  (ip_name, ip_number) ); --, active_end)); 

#
#     meta data table ( [eriod is an interval, since interval is reserved word )
#
CREATE TABLE  metaData  (
 metaID   SERIAL,
 ip_name_src text,
 ip_name_dst text,
 transport text  NOT NULL,
 packetSize smallint   NOT NULL,
 count smallint   NOT NULL,
 packetInterval smallint,
 deadline smallint,
 ttl smallint,
 INDEX (ip_name_src, ip_name_dst, packetSize, count),
 FOREIGN KEY (ip_name_src) references host (ip_name),
 FOREIGN KEY (ip_name_dst) references host (ip_name),
 PRIMARY KEY  (metaID));


#
#   pinger data table, some fields have names differnt from XML schema since there where
#   inherited from the current pinger data table
#   its named data_yyyyMM to separate from old format - pairs_yyyyMM
#
CREATE TABLE  data_200707  (
 metaID   BIGINT   NOT NULL,
 minRtt real,
 meanRtt real,
 medianRtt real,
 maxRtt real,
 timestamp bigint NOT NULL,
 minIpd real,
 meanIpd real,
 maxIpd real,
 duplicates boolean,
 outOfOrder  boolean,
 clp real,
 iqrIpd real,
 lossPercent  real, 
 rtts text, -- should be stored as csv of ping rtts
 seqNums text, -- should be stored as csv of ping sequence numbers
 INDEX (meanRtt, medianRtt, lossPercent, meanIpd, clp),
 FOREIGN KEY (metaID) references metaData (metaID),
 PRIMARY KEY  (metaID, timestamp));


