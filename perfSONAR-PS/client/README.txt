
Version:
--------
	20060517

Installation:
-------------

	Perl Modules
	------------
		XML::Writer
		XML::Writer::String
		XML::XPath
		LWP::UserAgent
		use IO::File
		
		I would suggest using CPAN:
		
		perl -MCPAN -e shell
			install MODULE_NAME
			
	client.conf
	-----------
		Edit the port and hostname to that
		of the MA.		
			
	MA
	--
		You will need an MA to contact of course, 
		I have only tested this against the MA included
		in this package but because you are simply 
		sending SOAP encoded messages it should work
		with perfSONAR or older versions of the NMWG
		server.
		
Usage:
------
	./client FILENAME.xml (output will arrive on the screen
	this can be redirected with standard unix mechanisms)
	
	Edit the request file to twidle your request.
	
FAQ:
----
	Q:
	A:
		
	
Contact:
--------
	Jason Zurawski - zurawski at eecis dot udel dot edu
	Martin Swany - swany at udel dot edu	

