Howto					03/07/07
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
software.  Questions should be referred to the mailing list 
(https://mail.internet2.edu/wws/info/i2-perfsonar) and not the 
author directly.  

This tutorial will be centering on the development of a 'Ping' 
MP and MA from the supplied skeleton classes (and help from 
the additional modules already created).  

The 'frozen' version of the Ping MP/MA will live in this directory
as well after completion to further illustrate the steps, the
functioning Ping MA will no doubt experience a great increase
in functionality and complexity over time.

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

Other directives such as:

  MP_SAMPLE_RATE?1
  PORT?8080
  ENDPOINT?/axis/services/MP
  LS_REGISTRATION_INTERVAL?60
  LS_INSTANCE?http://lager:8080/axis/services/LS
  LOGFILE?./log/perfSONAR-PS-error.log

Can be adjusted as well to suit your own personal setup.  If you find
the need to add new directives, please do so.  Make sure to document
your changes.


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
              timeout  in  absence  of any responses, otherwise ping waits for
              two RTTs.


For the sake of this tutorial we will only be concerned with the '-c' 
parameter, but most other parameters will be handled in the same way.

An example of a ping would be:

[jason@lager perfSONAR_PS]$ ping -c 1 ellis.internet2.edu
PING ellis.internet2.edu (207.75.164.31) 56(84) bytes of data.
64 bytes from ellis.internet2.edu (207.75.164.31): icmp_seq=1 ttl=51 time=41.5 ms

--- ellis.internet2.edu ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 41.559/41.559/41.559/0.000 ms

To model this measurement a little closer, consider the two actors:

	Source Computer:
		Hostname: 	lager (The machine that 'kicked off')
		IP Address:	192.168.0.200
		
	Destination Computer:
		Hostname:	ellis.internet2.edu
		IP Address:	207.75.164.31

	Parameter(s)
		Count = 1

We can construct a metadata description (following known NMW-WG formatted 
examples) using this information:

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

The necessary parts of this result can be described as:

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
sent bytes (it doesn't matter which value, as long as you note somewhere that the
header is or is not included; we will choose to include the header), the sequence
number, the ttl, the measured value, and of course the starting time of the
measurement (which must be observed external to the ping operation).  This last 
item will need to be adjusted for the various factors such as where in the 
sequence the measurement has occurred, etc.  

To store this info we will be using an SQL database (specifically SQLite, but the
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
which will contain the remaining data in a separated fashion, such as:

  numBytes=64,seqNum=1,ttl=51 

The reason for this simple arrangement is that the secondary values do not make the
measurement unique; the time, value, eventType, and ID do this.  Secondly, it will
be rare that searching on these values would occur; the common case (the case that
should be the fastest) will involve searching on the other 4 items.  With this 
arrangement it is also possible for other forms of measurement to live in the
same SQL database.  

The designer is of course free to make the schema as complex as they like, although
interoperability with other MAs may be challenging.  

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
	
Step 3 (A Quick Test):
----------------------

Try to run the pingMP.pl program at this stage:

[jason@lager Ping]$ $PSPSREPO/MP/Ping/./pingMP.pl -v
Starting '0' as main
Starting '1' as MP2
Starting '2' as MA on port '8080' and endpoint '/axis/services/MP'.
Starting '3' as to register with LS 'http://lager:8080/axis/services/LS'.

Perhaps in a separate window, try to run the client:

[jason@lager client]$ $PSPSREPO/client/./client.pl --server=lager \
--port=8080 --endpoint=/axis/services/MP request.xml 

<nmwg:message xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/" type="response">
    <nmwg:metadata id="result-code-17177452">
    <nmwg:eventType>success</nmwg:eventType>
  </nmwg:metadata>
  <nmwg:data id="result-code-description-14877242" metadataIdRef="result-code-17177452">
    <nmwgr:datum xmlns:nmwgr="http://ggf.org/ns/nmwg/result/2.0/">success</nmwgr:datum>
  </nmwg:data>
</nmwg:message>

The MP window should also display the received message:

Request:        <nmwg:message xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/" xmlns:netutil="http://ggf.org/ns/nmwg/characteristic/utilization/2.0/" xmlns:nmwgt="http://ggf.org/ns/nmwg/topology/2.0/" type="request" id="msg1">

...DATA...

</nmwg:message>

From this quick demonstration, we can see that a lot of the busy work
when it comes to the MA is done already, handling the requests as they come in
and preparing responses.  Using existing tooling, we can start to construct the
various parts of the MA and MP.

Step 4 (MP Construction):
-------------------------

If we were to make a checklist of things the MP should do, we could write
it thus:

  1). Connect to backend storage (xmldb/file)

  2). Create objects for each metadata/data block pair
  
  3). Establish which of these metadata blocks are 'valid'
      (i.e. have data triggers, will be used to make 
       measurements and store data).

  4). Create 'collection' objects that will perform the
      measurement, parse the results, and store into the
      backend.
      
  5). Manage time gathering functions.
  
  6). In a loop, gather time, perform measurement, store, 
      then repeat.
      
Using the SNMP MP as our starting point, we can do each of these
tasks by writing code for both the MP/Ping.pm module and the 
pingMP.pl calling program.  Much of the 'nuts and bolts' already 
exists.

The first and second tasks are coupled together with some of the
framework code, connecting to the backend storage will give us
results that we will need to store in locally used objects.  The
first lines of code for the pingMP.pl file [measurementPoint 
function] (borrowed from the SNMP code base) can be written like 
this:


  my $mp = new perfSONAR_PS::MP::Ping(\%conf, \%ns, "", "");
  $mp->parseMetadata;


The goal of these lines of code is to make the MP object, pass it the
conf hash (which contains information about the metadata storage) and
call a function to prepare the initial metadata and data objects.  We 
now can turn our attention to the MP/Ping.pm module.  

This module contains a sub-module that will perform the actual 
collection of data.  For now, this extra object is not important
so we will not focus on editing it.  Turn your attention to the second
half of the object.  Some functions are already entered (such as some
basic set methods and the creation step), we will be adding a new
function to match what we have called in the program: 'parseMetadata'.

We can (and should) borrow some of the SNMP code to get started:


sub parseMetadata {
  my($self) = @_;
  $self->{FILENAME} = "perfSONAR_PS::MP::Ping";    
  $self->{FUNCTION} = "\"parseMetadata\"";
  
  if($self->{CONF}->{"METADATA_DB_TYPE"} eq "xmldb") {  
    # handling code for XMLDBs ...      
  }
  elsif($self->{CONF}->{"METADATA_DB_TYPE"} eq "file") {
    # handling code for files ...  
  }
  elsif(($self->{CONF}->{"METADATA_DB_TYPE"} eq "mysql") or 
        ($self->{CONF}->{"METADATA_DB_TYPE"} eq "sqlite")) {
    my $msg = "'METADATA_DB_TYPE' of '".$self->{CONF}->{"METADATA_DB_TYPE"}."' is not yet supported.";
    printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}) 
      if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne ""); 
  }  
  else {
    my $msg = "'METADATA_DB_TYPE' of '".$self->{CONF}->{"METADATA_DB_TYPE"}."' is invalid.";
    printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}) 
      if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne ""); 
  }
  return;
}


This basic shell gives us our first real flow altering choice: handling different 
types of backend metadata storage.  For now it really only makes sense to read
the metadata information from a file or the XMLDB.  In the future it may be 
possible to use other databases to store the metadata info (such as sql?) but 
the common two methods are what we will focus on.  Starting with the XMLDB
portion of the if statement, we want to make some objects to interact with
the XMLDB, extract info, and then store the results into some custom objects.

We can start by making the connection to the XMLDB (NOTE: reading up on the 
DB::XMLDB module may be useful here; I will not present a detailed description 
of why this creation statement works the way it does as the information is 
reprinted in the perldoc):


    my $metadatadb = new perfSONAR_PS::DB::XMLDB(
      $self->{CONF}->{"LOGFILE"},
      $self->{CONF}->{"METADATA_DB_NAME"}, 
      $self->{CONF}->{"METADATA_DB_FILE"},
      \%{$self->{NAMESPACES}}
    );

    $metadatadb->openDB;


Note that these statements depends on the $self->{CONF} variable, which depends on the
pingMP.conf file.  It is important to verify the information in the conf file for
correctness or undesirable effects may occur.

Once we establish the DB connection, we can send a query to retrieve all of the data
elements:


    my $query = "//nmwg:metadata";
    my @resultsStringMD = $metadatadb->query($query);   
    if($#resultsStringMD != -1) {    
      # handling code...
    }
    else {
      my $msg = $self->{FILENAME} .":\tXMLDB returned 0 results for query '". $query ."' in function " . $self->{FUNCTION};      
      printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}) 
        if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne "");          
    } 


Some things to note about this step are the relative simplicity of the query, and the 
handling of the results.  The query is asking for all nmwg:metadata elements.  This is
ok at this stage, but may cause some trouble in the future.  If the backend storage were
to be populated with information that is NOT related to the ping MP (such as SNMP 
information) we would get it in this query.  A more complex query will need to be used
if this is the case.

The second thing is the handling of the results.  If the DB returns zero results, 
resultsString's length will be -1.  We can then send a descriptive message to the log
file (using some magic from the perfSONAR_PS::Common module).  The case where we have 
results should be dealt with in a loop (iterating over each result):


      for(my $x = 0; $x <= $#resultsStringMD; $x++) {     	
	parse($resultsStringMD[$x], \%{$self->{METADATA}}, \%{$self->{NAMESPACES}}, $query);
      }


The 'parse' function lives in perfSONAR_PS::Common, and will iterate over the XML 
result (each member of the resultsString) and store the resulting hash objects
into the $self->{METADATA} object.  As it stands right now 'parse' is intelligent
enough to handle interfaces and endPointPairs from the v2 of the nmwg schema.  Future
additions will handle more subjects, so editing parse will normally not be the job
of the MP developer.

For debugging purposes, we can insert something else after the for loop to show us
what we have just done:


      print "Metadata:\t" , Dumper($self->{METADATA}) , "\n";


Now lets test it out, if we were to run the MP again we should see this:


[jason@lager Ping]$ ./pingMP.pl -v
Starting '0' as main
Starting '1' as MP2
Starting '2' as MA on port '8080' and endpoint '/axis/services/MP'.
Starting '3' as to register with LS 'http://lager:8080/axis/services/LS'.
Metadata:       $VAR1 = {
          'meta1' => {
                     'nmwg:metadata/ping:subject/nmwgt:endPointPair/nmwgt:dst-value' => 'ellis.internet2.edu',
                     'nmwg:metadata/ping:parameters/nmwg:parameter-count' => '1',
                     'nmwg:metadata/ping:subject/nmwgt:endPointPair/nmwgt:src-value' => 'lager',
                     'nmwg:metadata/ping:subject/nmwgt:endPointPair/nmwgt:dst-type' => 'hostname',
                     'nmwg:metadata-id' => 'meta1',
                     'nmwg:metadata/ping:subject/nmwgt:endPointPair/nmwgt:src-type' => 'hostname',
                     'nmwg:metadata/ping:parameters-id' => 'param1',
                     'nmwg:metadata/ping:subject-id' => 'sub1'
                   }
        };


The Data::Dumper output gives an idea of the structure of the metadata 
object.  Basically, we are given the full path to each item, and its
value.  We will use these values in time to build the collection
objects.  We now need to use the same idea to gather all of the data
objects from the metadata storage.  We will add all of this code immediately
after the if/else clause for the metadata:


    $query = "//nmwg:data";
    my @resultsStringD = $metadatadb->query($query);   
    if($#resultsStringD != -1) {    
      for(my $x = 0; $x <= $#resultsStringD; $x++) { 	
        parse($resultsStringD[$x], \%{$self->{DATA}}, \%{$self->{NAMESPACES}}, $query);
      }

      print "Data:\t" , Dumper($self->{DATA}) , "\n";
    }
    else {
      my $msg = $self->{FILENAME} .":\tXMLDB returned 0 results for query '". $query ."' in function " . $self->{FUNCTION};
      printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}) 
        if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne ""); 
    }          
    cleanMetadata($self); 


Note that this code is basically the same, except for the search for 
'data' elements and the additional step after the clause: 'cleanMetadata'.

The 'cleanMetadata' function can be reused from the SNMP code base:


sub cleanMetadata {
  my($self) = @_;
  $self->{FILENAME} = "perfSONAR_PS::MP::Ping";  
  $self->{FUNCTION} = "\"cleanMetadata\"";
    
  chainMetadata($self->{METADATA}); 

  foreach my $m (keys %{$self->{METADATA}}) {
    my $count = countRefs($m, \%{$self->{DATA}}, "nmwg:data-metadataIdRef");
    if($count == 0) {
      delete $self->{METADATA}->{$m};
    } 
    else {
      $self->{METADATAMARKS}->{$m} = $count;
    }
  }  
  return;
}


The purpose of this function is twofold: call the chain metadata function
to resolve any chains that exist in the storage (see perfSONAR_PS::Common for
a full explanation on chaining) and to 'eliminate' metadata blocks that
do not have a corresponding data trigger.

The results after these additions should look like this:


[jason@lager Ping]$ ./pingMP.pl -v
Starting '0' as main
Starting '1' as MP2
Starting '2' as MA on port '8080' and endpoint '/axis/services/MP'.
Metadata:       $VAR1 = {
          'meta1' => {
                     'nmwg:metadata/ping:subject/nmwgt:endPointPair/nmwgt:dst-value' => 'ellis.internet2.edu',
                     'nmwg:metadata/ping:parameters/nmwg:parameter-count' => '1',
                     'nmwg:metadata/ping:subject/nmwgt:endPointPair/nmwgt:src-value' => 'lager',
                     'nmwg:metadata/ping:subject/nmwgt:endPointPair/nmwgt:dst-type' => 'hostname',
                     'nmwg:metadata-id' => 'meta1',
                     'nmwg:metadata/ping:subject/nmwgt:endPointPair/nmwgt:src-type' => 'hostname',
                     'nmwg:metadata/ping:parameters-id' => 'param1',
                     'nmwg:metadata/ping:subject-id' => 'sub1'
                   }
        };

Data:   $VAR1 = {
          'data1' => {
                     'nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type' => 'sqlite',
                     'nmwg:data-metadataIdRef' => 'meta1',
                     'nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-table' => 'data',
                     'nmwg:data/nmwg:key-id' => '1',
                     'nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-file' => '/home/jason/perfSONAR-PS/MP/Ping/perfSONAR_PS.db',
                     'nmwg:data/nmwg:key/nmwg:parameters-id' => '2',
                     'nmwg:data-id' => 'data1'
                   }
        };

Starting '3' as to register with LS 'http://lager:8080/axis/services/LS'.


We now can see that our data block has been read in as well (stored in the 
$self->{DATA} object) and if we did have any chains to resolve, the work
would have been completed.

The next step is to do something similar with the 'file' type of database.
Using the file is much easier and can be accomplished using the same code
from the SNMP codebase:


    my $xml = readXML($conf{"METADATA_DB_FILE"});
    parse($xml, \%{$self->{METADATA}}, \%{$self->{NAMESPACES}}, "//nmwg:metadata");
    parse($xml, \%{$self->{DATA}}, \%{$self->{NAMESPACES}}, "//nmwg:data");	
    cleanMetadata($self);


This code will be placed in the elsif section of the 'parseMetadata' function 
that deals with the 'file' type of storage.  Even though we are not currently 
using a file as our storage, it is now possible to do so.  

The 'parseMetadata' function is now complete.  This takes care of the first
2 steps, and partially addresses step 3.  We will now focus on completing 
step 3, to create data objects and eliminate any more 'unusable' metadata
and data pairs.

Turn your attention back to the pingMP.pl file.  We need to add some
more calls here to establish connections to the backend storage medium(s) 
(in this case the sqlite database[s]).  We can start simple with:


  $mp->prepareData;
  
  
Now we must create the prepareData function in the MP/Ping.pm module that
will perform the actions of setting up connections to the various databases
that may be specified.  Our task is a bit easier here in that we only
have a single database we are working with.  More complex examples
can be seen in the SNMP code base.

Consider this shell of a function:


sub prepareData {
  my($self) = @_;
  $self->{FILENAME} = "perfSONAR_PS::MP::Ping";  
  $self->{FUNCTION} = "\"prepareData\"";
      
  foreach my $d (keys %{$self->{DATA}}) {
    if($self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "sqlite"){

      # create datadb object ...

    }
    elsif(($self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "rrd") or 
          ($self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} eq "mysql")) {
      my $msg = "Data DB of type '". $self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} ."' is not supported by this MP.";
      printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}) 
        if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne "");    
      removeReferences($self, $self->{DATA}->{$d}->{"nmwg:data-metadataIdRef"});
    }
    else {
      my $msg = "Data DB of type '". $self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type"} ."' is not supported by this MP.";
      printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}) 
        if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne ""); 
      removeReferences($self, $self->{DATA}->{$d}->{"nmwg:data-metadataIdRef"});
    }  
  }  
       
  return;
}


Like in 'parseMetadata', we need to have options based on the 'type' of database that is
specified in the data object.  The basic idea is thus:

  1). Loop through each object in the database hash
  
  2). Examine the 'type' which is really 'nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type'
  
  3). We will only care about 'sqlite' here; MySQL works in a similar way, but we will ignore
      all other types besides sqlite for right now.

  4). Of the types we ignore, we want to 'remove' references (there is no sense in collecting 
      data for something we can't store).  We will call a 'removeReferences' function that
      will remove the data blocks, as well as corresponding metadata blocks.  We need to 
      be careful when doing this however, so we 'count' references on the metadata blocks, and
      only remove when we are positive NOTHING is using a particular block.
      
Consider this for the 'removeReferences' function (also borrowed from the SNMP code base):


sub removeReferences {
  my($self, $id) = @_;
  $self->{FILENAME} = "perfSONAR_PS::MP::Ping";  
  $self->{FUNCTION} = "\"removeReferences\"";      
  my $remove = countRefs($id, $self->{METADATA}, "nmwg:metadata-id");
  if($remove > 0) {
    $self->{METADATAMARKS}->{$id} = $self->{METADATAMARKS}->{$id} - $remove;
    if($self->{METADATAMARKS}->{$id} == 0) {
      delete $self->{METADATAMARKS}->{$id};
      delete $self->{METADATA}->{$id};
    }     
  }
  return;
}


Using a function from perfSONAR_PS::Common, we aim to count the references that a 
particular block pair has (based on id matching).  We can then delete the 
metadata block if it meets the criteria.  We need to count references to be sure
that a particular metadata is truly not being used.  

Now comes the actual meat of this function: establishing a database connection
object.  We will be working in the blank if statement from above.  


      if(!defined $self->{DATADB}->{$self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-file"}}) {        
	my @dbSchema = ("id", "time", "value", "eventtype", "misc");
	$self->{DATADB}->{$self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-file"}} = 
          new perfSONAR_PS::DB::SQL($self->{CONF}->{"LOGFILE"},
	                               "DBI:SQLite:dbname=".$self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-file"}, 
                                       "",
                                       "",
				       \@dbSchema);
      }


This will create a new object (only one time) for each sqlite database that is seen
in each of the data objects.  We are sure to load this object with the log file reference, 
and the database name (plus some DBI information for SQLite).  We do not need to supply
a username and password for this database.  Additionally we supply the database schema
for the 'table' in question.  The DB::SQL module right now assumes a single table for 
each database.  In the future we will change this behavior to accommodate multi-table 
setups, but for now this method suits us well.  

With the datadb object(s) created, and any unused metadata/data pairs removed we have
completed step 3.  Step 4 focus on the creation of the 'collection' objects that will
make a measurement, parse the output, and prepare the results for consumption.  Step
5 will also be taken into consideration here because we can keep time at the agent
level during execution of each measurement.  

We can now turn our attention back to pingMP.pl to add another line:


  $mp->prepareCollectors;
  
  
This allows us to start making the 'collection agent' objects that will perform the ping
measurements.  These are represented as a separate object within the MP/Ping.pm module.
This particular code is located at the top of the object.  Before getting into the 
structure of the collector, we will create the shell of the 'prepareCollectors' function:


sub prepareCollectors {
  my($self) = @_;
  $self->{FILENAME} = "perfSONAR_PS::MP::Ping";  
  $self->{FUNCTION} = "\"prepareCollectors\"";
        
  foreach my $m (keys %{$self->{METADATA}}) {
    if($self->{METADATAMARKS}->{$m}) {

      # for each valid metadata block ...

    }
  }
  return;
}


The basic idea here is to cycle through the remaining metadata blocks, and
establish the necessary information that is needed to make a ping 
measurement (destination host, parameters, etc.).  Lets look at the metadata
object a little closer:


          'meta1' => {
                     'nmwg:metadata/ping:subject/nmwgt:endPointPair/nmwgt:dst-value' => 'ellis.internet2.edu',
                     'nmwg:metadata/ping:parameters/nmwg:parameter-count' => '1',
                     'nmwg:metadata/ping:subject/nmwgt:endPointPair/nmwgt:src-value' => 'lager',
                     'nmwg:metadata/ping:subject/nmwgt:endPointPair/nmwgt:dst-type' => 'hostname',
                     'nmwg:metadata-id' => 'meta1',
                     'nmwg:metadata/ping:subject/nmwgt:endPointPair/nmwgt:src-type' => 'hostname',
                     'nmwg:metadata/ping:parameters-id' => 'param1',
                     'nmwg:metadata/ping:subject-id' => 'sub1'
                   }
		   
		   
From this object we should extract the following for use in the (basic) ping command:

  'nmwg:metadata/ping:subject/nmwgt:endPointPair/nmwgt:dst-value' => 'ellis.internet2.edu',
  'nmwg:metadata/ping:parameters/nmwg:parameter-count' => '1',

If there where more parameters specified, we could of course use them.  We now need to go 
about constructing an agent that will translate these statements into a usable command.
As we consider constructing the command, we realize that we could use a hard coded value
for the location of the ping binary.  We could just insert this into the function, but
a proper location for something like this is in the pingMP.conf file:


  PING?/bin/ping


We can now address this info by:


  $self->{CONF}->{"PING"}
  
  
Now we can consider this small chunk of code, to be inserted into the blank if 
statement:


      my $commandString = $self->{CONF}->{"PING"}." ";
      my $host = "";
      foreach my $m2 (keys %{$self->{METADATA}->{$m}}) {
        if($m2 =~ m/.*dst-value$/) {
          $host = $self->{METADATA}->{$m}->{$m2};
        }
        elsif($m2 =~ m/.*ping:parameters\/nmwg:parameter-count$/) {
          $commandString = $commandString . "-c " . $self->{METADATA}->{$m}->{$m2} . " ";
        }
      }  
      
      if(!defined $host or $host eq "") {
        my $msg = "Destination host not specified.";
        printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}) 
          if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne ""); 
      }
      else {
        $commandString = $commandString . $host;
        print "CMD: " , $commandString , "\n";
	
	# Create collection object ...
      }
      
      
      
Now we should go about running the program again, to see what we spit out (in 
addition to other things):      


CMD: /usr/bin/ping -c 1 ellis.internet2.edu


This code chunk will iterate through all of the keys of the metadata object, and
extract only the necessary values (in this case the host and the one parameter
we are interested in).  More things can be extracted if necessary.  After this stage,
we started to form the command string.  If we don't have a host (really the only thing
that is necessary) we can throw of an error the way we have previously done
this operation.  

The next step involves some construction of the actual agent object.  We know that
the agent is to execute a command when called to do so.  We also know that the agent
should parse the output of the command, and make the results available somehow.  

Here is the modification we will be making to both the 'new' and helper functions:


sub new {
  my ($package, $log, $cmd) = @_; 
  my %hash = ();
  $hash{"FILENAME"} = "perfSONAR_PS::MP::Ping::Agent";
  $hash{"FUNCTION"} = "\"new\"";
  if(defined $log and $log ne "") {
    $hash{"LOGFILE"} = $log;
  }  
  if(defined $cmd and $cmd ne "") {
    $hash{"CMD"} = $cmd;
  }  
  
  %{$hash{"RESULTS"}} = ();
  
  bless \%hash => $package;
}

sub setCommand {
  my ($self, $cmd) = @_;  
  $self->{FILENAME} = "perfSONAR_PS::MP::Ping::Agent";
  $self->{FUNCTION} = "\"setCommand\"";  
  if(defined $cmd and $cmd ne "") {
    $self->{CMD} = $cmd;
  }
  else {
    printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION}) 
      if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");    
  }
  return;
}


We acknowledge that the 'cmd' is important to the agent, and that we should have the 
ability to load (and change) this value.  We also know we will need a hash of some sort 
to store the results of the command.  We now must devise a way to execute and parse 
the output of the command.  Borrowing some terminology from the SNMP module we can 
make a function called 'collect':


sub collect {
  my ($self) = @_;
  $self->{FILENAME} = "perfSONAR_PS::MP::Ping::Agent";  
  $self->{FUNCTION} = "\"collect\""; 
  if(defined $self->{CMD} and $self->{CMD} ne "") {   
    undef $self->{RESULTS};
     

    
  }
  else {
    printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION}) 
      if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");    
  }
  return;
}


The shell of this function basically indicates we can't collect unless the 
command is defined.  We also wish to clear out the old results before going
any further.  The next step is to acquire the time, and execute the command:


    my($sec, $frac) = Time::HiRes::gettimeofday;
    my $time = eval($sec.".".$frac);
        
    open(CMD, $self->{CMD}." |") or 
      croak($self->{"LOGFILE"}, $self->{FILENAME}.":\tCannot open \"".$self->{CMD}."\" in ".$self->{FUNCTION}." at line ".__LINE__.".");
    my @results = <CMD>;    
    close(CMD);
    
    # deal with the results array ...
    
Using a file handle trick, we can get the output of the command (logging
errors in the event of a problem) and store the results in an array.  Lets take
a look at the output of the command one more time (with some line numbering):


[jason@lager perfSONAR_PS]$ ping -c 3 ellis.internet2.edu
0:	PING ellis.internet2.edu (207.75.164.31) 56(84) bytes of data.
1:	64 bytes from ellis.internet2.edu (207.75.164.31): icmp_seq=1 ttl=51 time=41.0 ms
2:	64 bytes from ellis.internet2.edu (207.75.164.31): icmp_seq=2 ttl=51 time=40.7 ms
3:	64 bytes from ellis.internet2.edu (207.75.164.31): icmp_seq=3 ttl=51 time=41.3 ms
4:	
5:	--- ellis.internet2.edu ping statistics ---
6:	3 packets transmitted, 3 received, 0% packet loss, time 1999ms
7:	rtt min/avg/max/mdev = 40.741/41.049/41.340/0.244 ms


By observation we can see that we are only interested in lines 1 - 3, the rest 
can be ignored at this time.  We could start a loop at 1 (ignoring line 0) and
execute until the array length - 5.  The perl shortcut '$#results' actually
gives us the last numbered element in the array, we could use the following
loop to handle all of the 'result' lines:


    for(my $x = 1; $x <= ($#results-4); $x++) { 
     
      # handle each line of results ...

    }


Note that we basically address each 'probe' differently.  This fact will be used 
for storage considerations.  The middle of the loop needs to parse the output first 
and foremost; using some regular expression matching can help to extract the useful 
bits.  Consider this result line:


  64 bytes from ellis.internet2.edu (207.75.164.31): icmp_seq=1 ttl=51 time=41.0 ms


We could split this at the semi-colon to get two strings:


  64 bytes from ellis.internet2.edu (207.75.164.31)
  icmp_seq=1 ttl=51 time=41.0 ms


The first string really has only one useful information chunk (the bytes), the second
chunk everything else we need (seq_num, ttl, value).  Consider this code segment:


      my @resultString = split(/:/,$results[$x]);        
      ($self->{RESULTS}->{$x}->{"bytes"} = $resultString[0]) =~ s/\sbytes.*$//;
      for ($resultString[1]) {
        s/\n//;
        s/^\s*//;
      }
    
      my @tok = split(/ /, $resultString[1]);
      foreach my $t (@tok) {
        if($t =~ m/^.*=.*$/) {
          (my $first = $t) =~ s/=.*$//;
	  (my $second = $t) =~ s/^.*=//;
	  $self->{RESULTS}->{$x}->{$first} = $second;  
        }
        else {
          $self->{RESULTS}->{$x}->{"units"} = $t;
        }
      }


We first extract and store the value for bytes, then using a tokenizer on 
the space character we can extract the other data units.  We store these
in the $self->{RESULTS} hash.  Finally we deal with keeping time for each
measurement:


      $self->{RESULTS}->{$x}->{"timeValue"} = $time + eval($self->{RESULTS}->{$x}->{"time"}/1000);
      $time = $time + eval($self->{RESULTS}->{$x}->{"time"}/1000);


The time for each ping is really the start time of the command + the value 
of each measurement (to indicate time is advancing).  We finally address the issue
of returning the RESULTS hash with a simple function:


sub getResults {
  my ($self) = @_;
  $self->{FILENAME} = "perfSONAR_PS::MP::Ping::Agent";  
  $self->{FUNCTION} = "\"getResults\""; 
  if(defined $self->{RESULTS} and $self->{RESULTS} ne "") {   
    return $self->{RESULTS};
  }
  else {
    printError($self->{"LOGFILE"}, $self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION}) 
      if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");    
  }
  return;
}


This hash structure (when Dumped()'ed) looks like this:


$VAR1 = {
          '1' => {
                   'bytes' => '64',
                   'time' => '40.7',
                   'ttl' => '51',
                   'icmp_seq' => '1',
                   'timeValue' => '1173291972.5321',
                   'units' => 'ms'
                 },
          '3' => {
                   'bytes' => '64',
                   'time' => '40.5',
                   'ttl' => '51',
                   'icmp_seq' => '3',
                   'timeValue' => '1173291972.6142',
                   'units' => 'ms'
                 },
          '2' => {
                   'bytes' => '64',
                   'time' => '41.6',
                   'ttl' => '51',
                   'icmp_seq' => '2',
                   'timeValue' => '1173291972.5737',
                   'units' => 'ms'
                 }
        };


Notice that each probe is separated and addressed by sequence number.  Later when extracting
information from this structure, we will need to take this fact into consideration.  

This completes Steps 4 and 5 as described out above.  The agent is basically complete
at this point (handling errors or interesting behavior is also necessary, but
beyond the scope of this tutorial).  We turn our attention to the last step, 
step 6 which is a function to continuously pole the agents and store the results.

In pingMP.pl, recall the structure of the 'measurementPoint' function:


sub measurementPoint {
  if($DEBUG) {
    print "Starting '".threads->tid()."' as MP2\n";
  }

  my $mp = new perfSONAR_PS::MP::Ping(\%conf, \%ns, "", "");
  $mp->parseMetadata;
  $mp->prepareData;
  $mp->prepareCollectors;  

  while(1) {

    # collect measurements.  
    
    sleep($conf{"MP_SAMPLE_RATE"});
  }
  return;  
}


We will now turn our attention to the body of the loop with this simple
statement:


    $mp->collectMeasurements;


The 'collectMeasurements' function will represent the last function of
the MP/Ping.pm module for the time being.  Start with a simple shell:


sub collectMeasurements {
  my($self) = @_;
  $self->{FILENAME} = "perfSONAR_PS::MP::Ping";  
  $self->{FUNCTION} = "\"collectMeasurements\"";
  
  foreach my $p (keys %{$self->{PING}}) {
    print "Collecting for '" , $p , "'.\n";
    $self->{PING}->{$p}->collect;
  }
  
  foreach my $d (keys %{$self->{DATA}}) {

  }
		
  return;
}


The first step of this function is to execute all known agents and gather
their output.  After this step, we want to start inserting the data into
the necessary data dbs.  We choose to iterate over the 'data' objects
in this loop for the simple reason that there may be multiple data blocks
(with corresponding metadata blocks) that use the SAME database.  If this
where the case, there would be only ONE database object.  By iterating
over the data objects, we make sure all corresponding metadata objects
are represented.  

The inside of the data loop should do the following:


    $self->{DATADB}->{$self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-file"}}->openDB;
    my $results = $self->{PING}->{$self->{DATA}->{$d}->{"nmwg:data-metadataIdRef"}}->getResults;
    foreach my $r (sort keys %{$results}) {
      
      print "inserting \"".$self->{DATA}->{$d}->{"nmwg:data-metadataIdRef"}.
            "\", \"".$results->{$r}->{"timeValue"}."\", \"".$results->{$r}->{"time"}.
	    "\", \"ping\", \""."numBytes=".$results->{$r}->{"bytes"}.",ttl=".
	    $results->{$r}->{"ttl"}.",seqNum=".$results->{$r}->{"icmp_seq"}.
	    ",units=".$results->{$r}->{"units"}."\" into table ".
	    $self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-table"}.
	    ".\n";
      
      my %dbSchemaValues = (
        id => $self->{DATA}->{$d}->{"nmwg:data-metadataIdRef"}, 
        time => $results->{$r}->{"timeValue"}, 
        value => $results->{$r}->{"time"}, 
        eventtype => "ping",  
        misc => "numBytes=".$results->{$r}->{"bytes"}.",ttl=".$results->{$r}->{"ttl"}.",seqNum=".$results->{$r}->{"icmp_seq"}.",units=".$results->{$r}->{"units"}
      );  
      
      $self->{DATADB}->{$self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-file"}}->insert(
        $self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-table"},
	\%dbSchemaValues
      );
      
    }
    $self->{DATADB}->{$self->{DATA}->{$d}->{"nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-file"}}->closeDB;


We first open the proper database.  Secondly, we extract the results for the 
proper metadata agent.  Remember that our RESULTS hash stores the output of
each 'run' as an internal hash, so we need to do some fancy maneuvering to extract
each run in order.  For debugging I have included a print statement to show what will
be inserted into the database.  

We prepare a hash that corresponds to the database schema, and load this hash with the 
collected values.  Finally, we execute the insert statement using the proper database
object.  After inserting all necessary values, we close the database.  

This concludes the basic framework of the MP, a final test of our work gives us this output:


[jason@lager Ping]$ ./pingMP.pl -v
Starting '0' as main
Starting '1' as MP2
Starting '2' as MA on port '8080' and endpoint '/axis/services/MP'.
Starting '3' as to register with LS 'http://lager:8080/axis/services/LS'.
Metadata:       $VAR1 = {
          'meta1' => {
                     'nmwg:metadata/ping:subject/nmwgt:endPointPair/nmwgt:dst-value' => 'ellis.internet2.edu',
                     'nmwg:metadata/ping:parameters/nmwg:parameter-count' => '3',
                     'nmwg:metadata/nmwg:eventType' => 'http://ggf.org/ns/nmwg/tools/ping/2.0/',
                     'nmwg:metadata/ping:subject/nmwgt:endPointPair/nmwgt:src-value' => 'lager',
                     'nmwg:metadata/ping:subject/nmwgt:endPointPair/nmwgt:dst-type' => 'hostname',
                     'nmwg:metadata-id' => 'meta1',
                     'nmwg:metadata/ping:subject/nmwgt:endPointPair/nmwgt:src-type' => 'hostname',
                     'nmwg:metadata/ping:parameters-id' => 'param1',
                     'nmwg:metadata/ping:subject-id' => 'sub1'
                   }
        };

Data:   $VAR1 = {
          'data1' => {
                     'nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-type' => 'sqlite',
                     'nmwg:data-metadataIdRef' => 'meta1',
                     'nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-table' => 'data',
                     'nmwg:data/nmwg:key-id' => '1',
                     'nmwg:data/nmwg:key/nmwg:parameters/nmwg:parameter-file' => '/home/jason/perfSONAR-PS/MP/Ping/perfSONAR_PS.db',
                     'nmwg:data/nmwg:key/nmwg:parameters-id' => '2',
                     'nmwg:data-id' => 'data1'
                   }
        };

Collecting for 'meta1'.
inserting "meta1", "1173292206.24313", "41.1", "ping", "numBytes=64,ttl=51,seqNum=1,units=ms" into table data.
inserting "meta1", "1173292206.28383", "40.7", "ping", "numBytes=64,ttl=51,seqNum=2,units=ms" into table data.
inserting "meta1", "1173292206.32503", "41.2", "ping", "numBytes=64,ttl=51,seqNum=3,units=ms" into table data.

Collecting for 'meta1'.
inserting "meta1", "1173292209.16113", "41.0", "ping", "numBytes=64,ttl=51,seqNum=1,units=ms" into table data.
inserting "meta1", "1173292209.20143", "40.3", "ping", "numBytes=64,ttl=51,seqNum=2,units=ms" into table data.
inserting "meta1", "1173292209.24243", "41.0", "ping", "numBytes=64,ttl=51,seqNum=3,units=ms" into table data.

Collecting for 'meta1'.
inserting "meta1", "1173292212.22133", "42.8", "ping", "numBytes=64,ttl=51,seqNum=1,units=ms" into table data.
inserting "meta1", "1173292212.26293", "41.6", "ping", "numBytes=64,ttl=51,seqNum=2,units=ms" into table data.
inserting "meta1", "1173292212.30413", "41.2", "ping", "numBytes=64,ttl=51,seqNum=3,units=ms" into table data.


We should also check SQLite to see if the data is actually being inserted:


[jason@lager Ping]$ sqlite3 perfSONAR_PS.db 
SQLite version 3.3.6
Enter ".help" for instructions
sqlite> select * from data;
meta1|1173292206.24313|41.1|ping|numBytes=64,ttl=51,seqNum=1,units=ms
meta1|1173292206.28383|40.7|ping|numBytes=64,ttl=51,seqNum=2,units=ms
meta1|1173292206.32503|41.2|ping|numBytes=64,ttl=51,seqNum=3,units=ms
meta1|1173292209.16113|41|ping|numBytes=64,ttl=51,seqNum=1,units=ms
meta1|1173292209.20143|40.3|ping|numBytes=64,ttl=51,seqNum=2,units=ms
meta1|1173292209.24243|41|ping|numBytes=64,ttl=51,seqNum=3,units=ms
meta1|1173292212.22133|42.8|ping|numBytes=64,ttl=51,seqNum=1,units=ms
meta1|1173292212.26293|41.6|ping|numBytes=64,ttl=51,seqNum=2,units=ms
meta1|1173292212.30413|41.2|ping|numBytes=64,ttl=51,seqNum=3,units=ms
sqlite> .exit


Thus completes the simple Ping MP.  Take this time to edit the perldoc
at the bottom describing the functions that have been added or changed.  
Also remove debugging statements.  The next step is the ability to handle
user queries and extract usable information from the archives.  



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
