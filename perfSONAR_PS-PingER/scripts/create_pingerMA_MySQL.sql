drop  table if exists data;
drop  table if exists metaData; 
drop  table if exists host;
# 
# ------------------------------------The part above is for beacons and pinger website ( means administering tasks)--
#
#----------------------------------------------- The part below is for collection and pinger MA----------------------
#
# ipaddr  table to keep track on what ip address was assigned with pinger hostname
#   ip_number has length of 64 - to accomodate possible IPv6 
#
CREATE TABLE   host (
 host BIGINT NOT NULL AUTO_INCREMENT,
 ip_name varchar(52) NOT NULL, 
 ip_number varchar(64) NOT NULL,
 ip_type enum('ipv4','ipv6')  NOT NULL default 'ipv4',
 PRIMARY KEY  (host),
 UNIQUE INDEX (ip_name, ip_number) 
);

#
#     meta data table ( [eriod is an interval, since interval is reserved word )
#
CREATE TABLE   metaData  (
 metaID BIGINT NOT NULL AUTO_INCREMENT,
 src_host BIGINT NOT NULL,
 dst_host BIGINT NOT NULL, 
 transport enum('icmp','tcp','udp')   NOT NULL DEFAULT 'icmp',
 packetSize smallint   NOT NULL,
 count smallint   NOT NULL,
 packetInterval smallint,
 ttl smallint,
 INDEX (src_host, dst_host, packetSize, count),
 FOREIGN KEY (src_host) references host (host),
 FOREIGN KEY (dst_host) references host (host),
 PRIMARY KEY  (metaID));


#
#   pinger data table, some fields have names differnt from XML schema since there where
#   inherited from the current pinger data table
#   its named data_yyyyMM to separate from old format - pairs_yyyyMM
#
CREATE TABLE   data  (
 metaID   BIGINT   NOT NULL,
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
 rtts varchar(1024), -- should be stored as csv of ping rtts
 seqNums varchar(1024), -- should be stored as csv of ping sequence numbers
 INDEX (meanRtt, medianRtt, lossPercent, meanIpd, clp),
 FOREIGN KEY (metaID) references metaData (metaID),
 PRIMARY KEY  (metaID, timestamp));
