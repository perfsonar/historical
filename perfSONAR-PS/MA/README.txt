Version:
--------
	20060517

Installation:
-------------

	Perl Modules
	------------
		HTTP::Daemon
		HTTP::Response
		HTTP::Headers
		HTTP::Status
		XML::Writer
		XML::Writer::String
		XML::XPath
		XML::Parser
		DBI
		Time::HiRes
		Sleepycat::DbXml 'simple'
		IO::File
	
		I would suggest using CPAN (for all except the Sleepycat Package):
		
		perl -MCPAN -e shell
			install MODULE_NAME
			
		Sleepycat
		---------
			Visit & Download:
				http://dev.sleepycat.com/downloads/optreg.html?fname=dbxml-2.2.13.tar.gz&prod=xml
			
			Install
				tar -zxf dbxml-2.2.13.tar.gz
				cd dbxml-2.2.13
				./buildall.sh --enable-perl --enable-java 
					Builds into ./install, I moved this to /usr/local/bdbxml-2.2.13
					personally. 
			Set Paths:
				In /etc/profile (or ~/.bashrc)
					LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/bdbxml-2.2.13/lib
					export LD_LIBRARY_PATH

					PATH=$PATH:/usr/local/bdbxml-2.2/bin	
					export PATH
					
			You will need to create an XMLDB directory where the collections are stored,
			I created ~/netradar/MA/xmldb personally, but as long as server.conf
			points to where it is located, it doesnt matter.
	SQL Files
	---------
		Dont touch these, really.  I have included them to
		provide insight into the database schema.  db.sql is
		suitable for us in MySQL and db-lite.sql is for SQLite
		databases.
		
	server.conf
	-----------
		If you need to change database info, or server
		port (this relates to the client contact port, so
		watch what you pick).  
		
	store.xml
	---------
		Store your md info here, the supplied example shows
		the 2 interfaces (in two directions) for each of the
		9 nodes in our cluster.  					

Usage:
------
	./server.pl (output will arrive on the screen
	this can be redirected with standard unix mechanisms
	into /dev/null or whatever.)
	
FAQ:
----
	Q:
	A:
		
	
Contact:
--------
	Jason Zurawski - zurawski at eecis dot udel dot edu
	Martin Swany - swany at udel dot edu	
