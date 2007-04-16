#!/bin/env perl

use HTTP::Daemon;
use HTTP::Status;

  my $d = HTTP::Daemon->new( LocalPort => 8080 ) || die;
  print "Please contact me at: <URL:", $d->url, ">\n";
  while (my $c = $d->accept) {
 
 	print 'ACCEPTING' . "\n";
 
      while (my $r = $c->get_request) {

		print $r->as_string() . "\n";

	  if ($r->method eq 'GET' and $r->url->path eq "/xyzzy") {
              # remember, this is *not* recommended practice :-)
	      $c->send_file_response("/etc/passwd");
	  }
	  else {
	      $c->send_error(RC_FORBIDDEN)
	  }
      }
      $c->close;
      undef($c);
  }
