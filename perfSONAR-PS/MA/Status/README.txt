Version:
--------
	20070706

Installation:
-------------

	Perl Modules
	------------
		XML::Writer
		XML::Writer::String
		XML::XPath
		XML::Parser
		DBI
		Time::HiRes
		IO::File
		Log::Log4perl

		I would suggest using CPAN

		perl -MCPAN -e shell install MODULE_NAME
			
	SQL Files
	---------
		Dont touch these, really.  I have included them to
		provide insight into the database schema. db-lite.sql is for
		SQLite databases.
		
	status.conf
	-----------
		If you need to change database info, or server
		port (this relates to the client contact port, so
		watch what you pick).  
		
	links.conf
	----------
		Store your link information here. The supplied example shows
		a few different links that require a variety of methods to
		obtain their status.

Usage:
------
	./status.pl (output will arrive on the screen
	this can be redirected with standard unix mechanisms
	into /dev/null or whatever.)
	
FAQ:
----
	Q:
	A:
		
	
Contact:
--------
	Aaron Brown - aaron ar internet2 dot edu
