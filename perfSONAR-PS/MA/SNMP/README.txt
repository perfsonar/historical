Version:
--------
	20070417

Installation:
-------------

	Perl Modules
	------------
		IO::File;
		XML::XPath;
		HTTP::Daemon;
		HTTP::Response;
		HTTP::Headers;
		HTTP::Status;
		XML::Writer;
		XML::Writer::String;
		LWP::UserAgent;
		Time::HiRes
		XML::LibXML

			I would suggest using CPAN to install:
		
				perl -MCPAN -e shell
					install MODULE_NAME
							
		RRDp (Installed with rrdtool)
		
		Sleepycat::DbXml (This is now optional)
				
                        Visit & Download:
                                http://www.oracle.com/technology/software/products/berkeley-db/htdocs/popup/xml/2.2.13/xml-targz.html
                        
			Install
                                tar -zxf dbxml-2.2.13.tar.gz
                                cd dbxml-2.2.13
                                ./buildall.sh --enable-perl --enable-java --prefix=/usr/local/dbxml-2.2.13

                        Set Paths:
                                In /etc/profile (or ~/.bashrc)
                                        LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/dbxml-2.2.13/lib
                                        export LD_LIBRARY_PATH

                                        PATH=$PATH:/usr/local/dbxml-2.2/bin
                                        export PATH

                        You will need to create an XMLDB directory where the collections are stored,
                        I created ~/perfSONAR-PS/MA/SNMP/xmldb personally, but as long as the conf file
                        points to where it is located, it doesnt matter.
						
	snmpMA.conf
	------------
		Database and other collection related info that should reflect your setup.
		
		Comments at top of file tell you what you need.


store.xml File (instead of XMLDB):
----------------------------------

	1) Edit the 'store.xml' file to reflect the metadata to rrd mapping
	

XMLDB (optional step):
----------------------

To 'load' the XMLDB, there are two steps:

	1) Edit the 'store.xml' file to reflect the metadata to rrd mapping

	2) Use the 'loadXMLDB.pl' utility function to load the database:
		
		./loadXMLDB.pl --environment=/path/to/env/xmldb --container=container.dbxml --filename=/path/to/store.xml [--verbose]

RRD Files:
----------

There are 2 RRD files in my store, here is how they were set up:
	
	rrdtool create lager.rrd --start N --step 1 \
	DS:eth0-in:COUNTER:5:U:U \
	DS:eth0-out:COUNTER:5:U:U \
	RRA:AVERAGE:0.5:10:60480
	
	rrdtool create stout.rrd --start N --step 1 \
	DS:eth0-in:COUNTER:5:U:U \
	DS:eth0-out:COUNTER:5:U:U \
	DS:eth1-in:COUNTER:5:U:U \
	DS:eth1-out:COUNTER:5:U:U \
	RRA:AVERAGE:0.5:10:60480

Store Layout:
-------------

For the 1st RRD file, we would need a metadata layout such as this:

  <nmwg:metadata id="someid" xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/">
    <netutil:subject xmlns:netutil="http://ggf.org/ns/nmwg/characteristic/utilization/2.0/" id="someid">
      <nmwgt:interface xmlns:nmwgt="http://ggf.org/ns/nmwg/topology/2.0/">
        <nmwgt:ifAddress type="ipv4">SOME IP</nmwgt:ifAddress>
        <nmwgt:hostName>lager</nmwgt:hostName>
        <nmwgt:ifName>eth0</nmwgt:ifName>
        <nmwgt:direction>in</nmwgt:direction>
        <nmwgt:capacity>100000000</nmwgt:capacity>
      </nmwgt:interface>
    </netutil:subject>
    <nmwg:eventType></nmwg:eventType>
  </nmwg:metadata>

  <nmwg:data id="someid" metadataIdRef="someid" xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/">
    <nmwg:key id="someid">
      <nmwg:parameters id="someid">
        <nmwg:parameter name="type">rrd</nmwg:parameter>
        <nmwg:parameter name="valueUnits">Bps</nmwg:parameter>	
        <nmwg:parameter name="file">/home/jason/perfSONAR-PS/MA/SNMP/lager.rrd</nmwg:parameter>
        <nmwg:parameter name="dataSource">eth0-in</nmwg:parameter>
      </nmwg:parameters>
    </nmwg:key>  
  </nmwg:data>
	
Something similar would be needed for the opposite 'direction'.	
	
Usage:
------
	The MA:
	-------
		./snmpMA.pl (--verbose for debug [non background] mode)

	The Client:
	-----------
		./client.pl --server=localhost --port=8080 --endpoint=/axis/services/MA request.xml

FAQ:
----
	Q:
	A:
			
Contact:
--------
	Jason Zurawski - zurawski at internet2 dot edu
