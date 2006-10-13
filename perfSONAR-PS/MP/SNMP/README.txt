Version:
--------
	20061013

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
			
	collect.conf
	-----------
		Add the contact information for SNMP servers, 
		follow the format at the top of the file.
		
	store.xml
	---------
		Store your metadata info here, the supplied example shows
		the 2 interfaces (in each direction direction) for each of the
		9 nodes in our cluster. 		
		
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
