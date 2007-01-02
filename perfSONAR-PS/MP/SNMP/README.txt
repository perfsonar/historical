Version:
--------
	20061115

Installation:
-------------

	Perl Modules
	------------
		Time::HiRes
		use POSIX qw( setsid )	[shouldn't need to install]

		
		The following are required through the Netradar Modules
		-------------------------------------------------------	
			Net::SNMP
			DBI
			XML::XPath
			IO::File


		I would suggest using CPAN to install:
		
			perl -MCPAN -e shell
				install MODULE_NAME
							
		
		Sleepycat::DbXml (This requires special instructions)
				
                        Visit & Download:
                                http://www.oracle.com/technology/software/products/berkeley-db/htdocs/popup/xml/2.2.13/xml-targz.html
                        
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
	------------
		Database and other collection related info that should reflect your setup.
		
		
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

FAQ:
----
	Q:
	A:
			
Contact:
--------
	Jason Zurawski - zurawski at eecis dot udel dot edu
	Martin Swany - swany at udel dot edu	
