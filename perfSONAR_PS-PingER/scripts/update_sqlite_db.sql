CREATE TABLE host_tmp as SELECT * from host;
CREATE TABLE metaData_tmp as SELECT * from metaData;
DROP TRIGGER IF EXISTS  metaData_fki;
DROP TRIGGER IF EXISTS  metaData_fku;
DROP INDEX   IF EXISTS  metaData_idx1;

DROP table host;
DROP table metaData;

CREATE TABLE IF NOT EXISTS host (
	host  INTEGER PRIMARY KEY, 
	ip_name varchar(52) NOT NULL, 
	ip_number varchar(64) NOT NULL,
	ip_type enum('ipv4','ipv6')  NOT NULL default 'ipv4'
) ENGINE=InnoDB;

CREATE INDEX host_idx1 
  ON host (ip_name, ip_number);

CREATE TABLE IF NOT EXISTS  metaData  (
 metaID   INTEGER PRIMARY KEY, 
 src_host  INTEGER NOT NULL, 
 dst_host  INTEGER NOT NULL, 
 transport enum('icmp','tcp','udp')   NOT NULL DEFAULT 'icmp',
 packetSize smallint   NOT NULL,
 count smallint   NOT NULL,
 packetInterval smallint,
 ttl smallint
);

INSERT IGNORE INTO host (ip_name, ip_number, ip_type) 
  SELECT ip_name, ip_number, 'ipv4'
  FROM host_tmp;
INSERT IGNORE INTO metaData (metaID, src_host, dst_host, transport,  packetSize,  count,  packetInterval,  ttl ) 
  SELECT m.metaID, src.host, dst.host, m.transport, m.packetSize, m.count, m.packetInterval, m.ttl
  FROM metaData_tmp m JOIN host src on(m.ip_name_src = src.ip_name) JOIN host dst on(m.ip_name_dst = dst.ip_name);
DROP table host_tmp;
DROP table metaData_tmp;

-- 
--   indexes and triggers
--

CREATE INDEX metaData_idx1 
  ON metaData ( src_host,  dst_host, packetSize, count);

 
CREATE TRIGGER metaData_fki
  BEFORE INSERT ON metaData FOR EACH ROW 
  BEGIN
    SELECT RAISE(ROLLBACK, 'Insert on metaData violates foreign key on src_host')
      WHERE (SELECT host FROM host WHERE host = NEW.src_host)
        IS NULL;
    SELECT RAISE(ROLLBACK, 'Insert on metaData violates foreign key on dst_host')
      WHERE (SELECT host FROM host WHERE host = NEW.dst_host)
        IS NULL;
  END;
