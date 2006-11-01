Version:
--------
	20061101

Installation:
-------------

	Perl Modules
	------------
		Net::SNMP
		DBI
		Time::HiRes
		XML::XPath
		IO::File
		use POSIX qw(setsid)	[shouldn't need to install]
			
			I would suggest using CPAN:
		
			perl -MCPAN -e shell
				install MODULE_NAME
		
		Sleepycat::DbXml 'simple'
				
                        Visit & Download:
                                http://dev.sleepycat.com/downloads/optreg.html?fname=dbxml-2.2.13.tar.gz&prod=xml

                        Install
                                tar -zxf dbxml-2.2.13.tar.gz
                                cd dbxml-2.2.13
                                ./buildall.sh --enable-perl --enable-java
                                        Builds into ./install, I moved this to /usr/local/dbxml-2.2.13
                                        personally.
                        Set Paths:
                                In /etc/profile (or ~/.bashrc)
                                        LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/dbxml-2.2.13/lib
                                        export LD_LIBRARY_PATH

                                        PATH=$PATH:/usr/local/dbxml-2.2/bin
                                        export PATH

                        You will need to create an XMLDB directory where the collections are stored,
                        I created ~/netradar/MP/SNMP/xmldb personally, but as long as server.conf
                        points to where it is located, it doesnt matter.
				
				
			
	collect.conf
	-----------
		Add the contact information for SNMP servers, 
		follow the format at the top of the file.

	conf-store.pl
	-------------
		Use this to automatically generate a store.xml file
		based on the output of your ifconfig (tested only on
		Fedora (RH) based systems).
	
	values.conf
	-----------
		SNMP Variables to consider when making the store.xml
		
		store.xml
		---------
			Store your metadata info here, the supplied example shows
			the 2 interfaces (in each direction direction) for a single
			machine.  You can of course add more for different SNMP
			variables. 		
		
	loadStorage.pl
	--------------
		Reads store.xml, and stores the contents into the XML
		DB.  Will not insert duplicates.  This is called at
		server startup, but really only matters whenever you
		set up the initial environment for the XML DB		
		
	db.conf
	-------
		Database info that should reflect your database
		setup.
		
		
	SQL Files
	---------
		Dont touch these, really.  I have included them to
		provide insight into the database schema.  db.sql is
		suitable for us in MySQL and db-lite.sql is for SQLite
		databases.				
			
	SQLite3
	-------
		You will need this library, you can get it here:
		
		http://www.sqlite.org/
		
		once installed, use it like this:
		
		To start the database:
			.read db-lite.sql
			.exit		
		
		sqlite3 netradar.db
			select * from data;
			.exit
		
Usage:
------
	Collection:
	-----------
		./collect.pl (Functions as a daemon, will background automatically)
		
	Watcher:
	--------
		Edit crontab to periodically run the watcher script:
		
		# watcher.pl, run it every 5 minutes
		*/1 * * * * root       cd $NETRADAR_HOME && ./watcher.pl

		It can of course be run manually:
			./watcher.pl

FAQ:
----
	Q:
	A:
		
	
Contact:
--------
	Jason Zurawski - zurawski at eecis dot udel dot edu
	Martin Swany - swany at udel dot edu	
