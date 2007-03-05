Howto					03/05/07
					Jason Zurawski
					zurawski@eecis.udel.edu
---------------------------------------------------------------

Purpose:
--------

The aim of this tutorial is provide a good starting point for the
development of an MP (and related MA) in the perfSONAR-PS 
framework.  This tutorial assumes some knowledge of perl, knowledge
of many of the 'base' perfSONAR-PS modules, and knowledge of the
measurement tool that is to be used in the creation of the 
software.  Questions should be refered to the mailing list 
(https://mail.internet2.edu/wws/info/i2-perfsonar) and not the 
author directly.  

This tutorial will be centering on the development of a 'Ping' 
MP and MA from the supplied skeleton classes (and help from 
the additional modules already created).  

Step 1 (Initialization):
------------------------

Examine the contents of the $PSPSREPO/tutorial directory, these are
files that we will be using to start the process.  These files
should be placed in the correct locations, and to do so there will
need to be some additions to the directory structure.  We need to
create the following new locations:

  mkdir $PSPSREPO/MP/Ping
  mkdir $PSPSREPO/MP/Ping/log
  mkdir $PSPSREPO/MP/Ping/xmldb

Now that we have these, we can copy the files to the correct 
locations:

  cp $PSPSREPO/tutorial/skeletonMP.conf $PSPSREPO/MP/Ping/pingMP.conf
  cp $PSPSREPO/tutorial/skeletonMP.pl $PSPSREPO/MP/Ping/pingMP.pl
  cp $PSPSREPO/tutorial/store.xml $PSPSREPO/MP/Ping/store.xml
  cp $PSPSREPO/tutorial/skeletonMP.pm $PSPSREPO/lib/perfSONAR_PS/MP/Ping.pm
  cp $PSPSREPO/tutorial/skeletonMA.pm $PSPSREPO/lib/perfSONAR_PS/MA/Ping.pm

With the files renamed, and in the correct location, do some 
find/replacing on any references to 'skeletonMP' or skeletonMA' and 
replace these with the new name 'perfSONAR_PS::MP::Ping' or 
'perfSONAR_PS::MA::Ping'.  This should be done in the modules as well 
as in the pingMP conf and perl files.  

The pingMP.conf file will also need to be edited to point to the new 
correct location of the XMLDB (if you are in fact using an XMLDB; 
using a file or other form of backend storage is acceptable):

  METADATA_DB_NAME?$PSPSREPO/MP/Ping/xmldb
  METADATA_DB_FILE?pingstore.dbxml


Step 2 (Metadata Storage):
--------------------------

The next step involves the structure of the Metadata storage, we will
be editing the store.xml file for this.

A Ping measurement is point to point in nature, and we should use either
the v2 or v3 incarnation of the endPointPair topology element to describe
this measurement.  When trying to capture the intention of measurements
(especially those where no examples may exist yet) take a look at the
nmwg repository (http://anonsvn.internet2.edu/svn/nmwg/trunk/nmwg/schema/)
and examine examples or schema files to get a better idea.  Follow the 
README in this directory to get some 'expert' advice.  

Lets take a look at the ping tool:

[jason@lager perfSONAR_PS]$ ping -h
Usage: ping [-LRUbdfnqrvVaA] [-c count] [-i interval] [-w deadline]
            [-p pattern] [-s packetsize] [-t ttl] [-I interface or address]
            [-M mtu discovery hint] [-S sndbuf]
            [ -T timestamp option ] [ -Q tos ] [hop1 ...] destination
	    
The interested user can read the man page and see what each of the 
switches is capable of doing, for this tutorial we are only concerned with
the following options:

       -c count
              Stop  after  sending  count  ECHO_REQUEST packets. With deadline
              option, ping waits for count ECHO_REPLY packets, until the time-
              out expires.

       -i interval
              Wait interval seconds between sending each packet.  The  default
              is  to  wait for one second between each packet normally, or not
              to wait in flood mode. Only super-user may set interval to  val-
              ues less 0.2 seconds.

       -s packetsize
              Specifies  the  number of data bytes to be sent.  The default is
              56, which translates into 64 ICMP data bytes when combined  with
              the 8 bytes of ICMP header data.

       -t ttl Set the IP Time to Live.
       
       -w deadline
              Specify a timeout, in seconds, before ping exits  regardless  of
              how  many  packets have been sent or received. In this case ping
              does not stop after count packet are sent, it waits  either  for
              deadline  expire  or until count probes are answered or for some
              error notification from network.

       -W timeout
              Time to wait for a response, in seconds. The option affects only
              timeout  in  absense  of any responses, otherwise ping waits for
              two RTTs.

An example of a ping would be:

[jason@lager perfSONAR_PS]$ ping -c 1 ellis.internet2.edu
PING ellis.internet2.edu (207.75.164.31) 56(84) bytes of data.
64 bytes from ellis.internet2.edu (207.75.164.31): icmp_seq=1 ttl=51 time=41.5 ms

--- ellis.internet2.edu ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 41.559/41.559/41.559/0.000 ms

To model this measurement a little closer, consider the two actors:

	Source Computer:
		Hostname: 	lager
		IP Address:	192.168.0.200
		
	Destination Computer:
		Hostname:	ellis.internet2.edu
		IP Address:	207.75.164.31

	Parameter(s)
		Count = 1

We can construct a metadata description using this information:

  <nmwg:metadata id="meta1" xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/">
    <ping:subject id="sub1" xmlns:ping="http://ggf.org/ns/nmwg/tools/ping/2.0/">
      <nmwgt:endPointPair xmlns:nmwgt="http://ggf.org/ns/nmwg/topology/2.0/">
        <nmwgt:src type="hostname" value="lager" />
        <nmwgt:dst type="hostname" value="ellis.internet2.edu" />
      </nmwgt:endPointPair>
    </ping:subject>
    <ping:parameters id="param1" xmlns:ping="http://ggf.org/ns/nmwg/tools/ping/2.0/">
      <nmwg:parameter name="count">1</nmwg:parameter>      
    </ping:parameters>   
  </nmwg:metadata>

For now, this is as good as we can do with our description of the actors of
a ping relationship.  This is more than enough to get started with the MP.  The
second step is to describe the backend storage that will house the results
of this measurement.  Lets take a look at the output of the command once more:

[jason@lager perfSONAR_PS]$ ping -c 1 ellis.internet2.edu
PING ellis.internet2.edu (207.75.164.31) 56(84) bytes of data.
64 bytes from ellis.internet2.edu (207.75.164.31): icmp_seq=1 ttl=51 time=41.5 ms

--- ellis.internet2.edu ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 41.559/41.559/41.559/0.000 ms

The necessary parts of this command can be described as:

	Sent Data Bytes: 	56 (really 64 = 56 + 8 Bytes of ICMP Header)
	Sequence Number:	1
	TTL:			51
	Measured Value:		41.5 ms
	
	Statistical Information:
		MIN RTT:	41.559 ms
		MAX RTT:	41.559 ms
		AVG RTT:	41.559 ms
		MDEV RTT:	0 ms
		Transmitted:	1
		Received:	1
		Packet Loss:	0%

The actual data we will want to save (for this example) will be the number of
sent bytes (it doesn't matter which value, as long as you note somwhere that the
header is or is not included; we will choose to include the header), the sequence
number, the ttl, the measured value, and of course the starting time of the
meaurement.  This last item will need to be adjusted for the various factors such
as where in the sequence the measurement has occured, etc.  

To store this info we will be using an SQL databae (specifically sqlite, but the
commands to store into another database such as MySQL will be the same) with a 
very simple schema:

create table data (
  id                    int unsigned not null,  
  time                  int unsigned not null,
  value                 int unsigned,
  eventtype             varchar(128) not null,
  misc                  varchar(128), 
  unique (id, time, value, eventtype, misc)
);

This schema does not have explicit fields for ttl, bytes, etc.  The only explicit 
items are an ID (which is related to the metadata block), the time, the value, an
eventType (which we will use something such as 'ping' or the fully qualified name
for ping that comes from the characteristics document), and finally a 'misc' field
which will contain the remaining data in a seperated fashion, such as:

  numBytes=64,seqNum=1,ttl=51 

The reason for this simple arrangement is that the secondary values do not make the
measurement unique; the time, value, eventType, and ID do this.  Secondly, it will
be rare that searching on these values would occur; the common case (the case that
should be the fastest) will involve searching on the other 4 items.  With this 
arrangement it is also possible for other forms of measurement to live in the
same SQL database.  

The designer is of course free to make the schema as complex as they like, although
interoperability with other MAs may be challanging.  

The last part of this step is to create the data block that will describe the 
location of the ping data.  Consider this:

  <nmwg:data id="data1" metadataIdRef="meta1" 
             xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/">
    <nmwg:key id="1">
      <nmwg:parameters id="2">
        <nmwg:parameter name="type">sqlite</nmwg:parameter>
        <nmwg:parameter name="file">$PSPSREPO/MP/Ping/perfSONAR_PS.db</nmwg:parameter>
        <nmwg:parameter name="table">data</nmwg:parameter>
      </nmwg:parameters>
    </nmwg:key>  
  </nmwg:data>

We will of course need to create the sqlite database for this to work 
properly, the above schema statement can be saved to a file called
'db-lite.sql':

[jason@lager Ping]$ sqlite3 perfSONAR_PS.db
SQLite version 3.3.6
Enter ".help" for instructions
sqlite> .read db-lite.sql
sqlite> .schema data
CREATE TABLE data (
  id                    int unsigned not null,  
  time                  int unsigned not null,
  value                 int unsigned,
  eventtype             varchar(128) not null,
  misc                  varchar(128), 
  unique (id, time, value, eventtype, misc)
);
sqlite> .exit

The final version of the store.xml file should look something like this:

<?xml version="1.0" encoding="UTF-8"?>
<nmwg:store xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/"
            xmlns:nmwgt="http://ggf.org/ns/nmwg/topology/2.0/"
	    xmlns:ping="http://ggf.org/ns/nmwg/tools/ping/2.0/">

  <nmwg:metadata id="meta1" xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/">
    <ping:subject id="sub1" xmlns:ping="http://ggf.org/ns/nmwg/tools/ping/2.0/">
      <nmwgt:endPointPair xmlns:nmwgt="http://ggf.org/ns/nmwg/topology/2.0/">
        <nmwgt:src type="hostname" value="lager" />
        <nmwgt:dst type="hostname" value="ellis.internet2.edu" />
      </nmwgt:endPointPair>
    </ping:subject>
    <ping:parameters id="param1" xmlns:ping="http://ggf.org/ns/nmwg/tools/ping/2.0/">
      <nmwg:parameter name="count">1</nmwg:parameter>      
    </ping:parameters>   
  </nmwg:metadata>
  
  <nmwg:data id="data1" metadataIdRef="meta1" xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/">
    <nmwg:key id="1">
      <nmwg:parameters id="2">
        <nmwg:parameter name="type">sqlite</nmwg:parameter>
        <nmwg:parameter name="file">$PSPSREPO/MP/Ping/perfSONAR_PS.db</nmwg:parameter>
        <nmwg:parameter name="table">data</nmwg:parameter>
      </nmwg:parameters>
    </nmwg:key>  
  </nmwg:data>
  
</nmwg:store>


To load this store file into the XMLDB, we can use one of the scripts from
the '$PSPSREPO/util' directory:

$PSPSREPO/util/./loadXMLDB.pl $PSPSREPO/MP/Ping/xmldb \
pingstore.dbxml $PSPSREPO/MP/Ping/store.xml

This will load in the xml from the store file, into the XMLDB for later
use.  

Now that setup is complete, we can start to focus on the actual coding.  
	
Step 3:
-------

Step 4:
-------

Step 5:
-------

Step 6:
-------

Step 7:
-------

Step 8:
-------

Step 9:
-------

Step 10:
--------

Step 11:
--------
