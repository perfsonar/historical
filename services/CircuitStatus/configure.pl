#!/usr/bin/perl -w

use strict;
use warnings;
use CPAN;

sub note();
sub ask($$$$);
sub locate($$);
sub readConfiguration($$);

my $DIST_URL = "http://download.oracle.com/berkeley-db/dbxml-2.3.10.tar.gz";

print " -- perfSONAR-PS Circuit Status MP Configuration --\n";
print " - [press enter for the default choice] -\n\n";

my $file = shift;

if (!defined $file or $file eq "") {
  $file = &ask("What file should I write the configuration to? ", "circuitstatus.conf", undef, '.+');
}

my %var = ();
my %prev = ();
my $tmp;
my $need_xmldb;

if (-f $file) {
	readConfiguration($file, \%prev);
}

my $header = <<EOF
# ######################################################### #
# Use:      Lines starting with a sharp are comments, this  #
#           file needs the following directives:            #
#                                                           #
#      PORT = Listen port for the application. This should  #
#            be something that can be accessed from the     #
#            outside world.                                 #
#      ENDPOINT = An 'endPoint' is a contact string that a  #
#            service is listening on.  This is used in      #
#            conjunction with the port and hostname:        #
#                                                           #
#                 http://HOST:PORT/end/Point/String         #
#                                                           #
#      CIRCUITS_FILE = The set of circuits to collect       #
#            status information on                          #
#      CIRCUITS_FILE_TYPE = The only valid value is 'file'  #
#                                                           #
#      TOPOLOGY_MA_TYPE = MA, XML or None                   #
#      TOPOLOGY_MA_URI = The remote MA to obtain node       #
#            information from                               #
#      TOPOLOGY_MA_FILE = The file for a local MA to obtain #
#            node information from                          #
#      TOPOLOGY_MA_ENVIRONMENT = The file for a local MA to #
#            obtain node information from                   #
#                                                           #
#      STATUS_MA_TYPE = MA, LS, SQLite or MySQL             #
#      STATUS_MA_URI = The remote MA to obtain link         #
#            information from                               #
#      LS = URI of the LS to obtain status information from #
#      STATUS_MA_FILE = The local SQLite database to obtain #
#            link information from                          #
#      STATUS_MA_NAME = The MySQL database to obtain link   #
#            information from                               #
#      STATUS_MA_HOST = The MySQL host                      #
#      STATUS_MA_PORT = The MySQL port                      #
#      STATUS_MA_USERNAME = The MySQL username              #
#      STATUS_MA_PASSWORD = The MySQL password              #
#                                                           #
#      CACHE_LENGTH = The amount of time to cache the       #
#            response for current status. Setting to 0      #
#            disables caching.                              #
#      CACHE_FILE = The file in which to cache the current  #
#            results                                        #
#                                                           #
#     MAX_WORKER_PROCESSES = Maximum number of child        #
#            processes that can be spawned at a given time. #
#                                                           #
#     MAX_WORKER_LIFETIME = Maximum amount of time a child  #
#            can process before it is stopped.              #
#                                                           #
# ######################################################### #
EOF
;

my @needs = (
             [ 'warnings', '0' ],
	     [ 'strict', '0' ],
             [ 'Exporter', '0' ],
             [ 'POSIX', '0' ],
             [ 'Getopt::Long', '0' ],
             [ 'Log::Log4perl', '0' ],
             [ 'Log::Dispatch', '0' ],
             [ 'Module::Load', '0' ],
             [ 'IO::File', '0' ],
             [ 'Time::Local', '0' ],
             [ 'HTTP::Daemon', '0' ],
             [ 'LWP::UserAgent', '0' ],
             [ 'XML::XPath', '1.13' ],
             [ 'XML::LibXML', '1.62' ],
             [ 'File::Basename', '0' ],
             [ 'Time::HiRes', '0' ]
	);

$var{"PORT"} = &ask("Enter the listen port ", "8084", $prev{"PORT"}, '^\d+$');

$var{"ENDPOINT"} = &ask("Enter the listen end point ", "/perfSONAR_PS/services/circuitstatus", $prev{"ENDPOINT"}, '.+');

$var{"MAX_WORKER_PROCESSES"} = &ask("Enter the maximum number of children processes (0 means infinite) ", "0", $prev{"MAX_WORKER_PROCESSES"}, '^\d+$');

$var{"MAX_WORKER_LIFETIME"} = &ask("Enter number of seconds a child can process before it is stopped (0 means infinite) ", "0", $prev{"MAX_WORKER_LIFETIME"}, "");

$var{"CIRCUITS_FILE"} = &ask("Enter the filename of the circuits configuration file (if relative, it's relative to the installation directory) ", "circuits.conf", $prev{"CIRCUITS_FILE"}, '.+');

$var{"CIRCUITS_FILE_TYPE"} = "file";

$var{"TOPOLOGY_MA_TYPE"} = &ask("From where should I get topology information? ", "ma|xml|none", $prev{"TOPOLOGY_MA_TYPE"}, '(xml|ma|none)');

if ($var{"TOPOLOGY_MA_TYPE"} eq "xml") {
  $need_xmldb = 1;
  $var{"TOPOLOGY_MA_ENVIRONMENT"} = &ask("Enter the directory containing the XML Database (if relative, it's relative to the installation directory) ", "xmldb", $prev{"TOPOLOGY_MA_ENVIRONMENT"}, '.+');
  $var{"TOPOLOGY_MA_FILE"} = &ask("Enter the filename for the XML Database ", "topology.dbxml", $prev{"TOPOLOGY_MA_FILE"}, '.+');
} elsif ($var{"TOPOLOGY_MA_TYPE"} eq "ma") {
  $var{"TOPOLOGY_MA_URI"} = &ask("URL for the MA to use ", "", $prev{"TOPOLOGY_MA_URI"}, '^http:\/\/');
}

$var{"STATUS_MA_TYPE"} = &ask("Enter the database type to read from ", "ls|sqlite|mysql|ma", $prev{"STATUS_MA_TYPE"}, '(sqlite|mysql|ma|ls)');

if ($var{"STATUS_MA_TYPE"} eq "sqlite") {
  push @needs, [ ('DBI', '0') ];
  push @needs, [ ('DBD::SQLite', '0') ];
  $var{"STATUS_MA_NAME"} = &ask("Enter the filename of the SQLite database (if relative, it's relative to the installation directory) ", "status.db", $prev{"STATUS_MA_NAME"}, '.+');
  $tmp = &ask("Enter the table in the database to use (leave blank for the default) ", "link_status", $prev{"STATUS_MA_TABLE"}, '');
  $var{"STATUS_MA_TABLE"} = $tmp if ($tmp ne "");
} elsif ($var{"STATUS_MA_TYPE"} eq "mysql") {
  push @needs, [ ('DBI', '0') ];
  push @needs, [ ('DBD::mysql', '0') ];

  $var{"STATUS_MA_NAME"} = &ask("Enter the name of the MySQL database ", "", $prev{"STATUS_MA_NAME"}, '.+');
  $tmp = &ask("Enter the host for the MySQL database ", "localhost", $prev{"STATUS_MA_HOST"}, '.+');
  $var{"STATUS_MA_HOST"} = $tmp if ($tmp ne "");
  $tmp = &ask("Enter the port for the MySQL database (leave blank for the default) ", "", $prev{"STATUS_MA_PORT"}, '^\d*$');
  $var{"STATUS_MA_PORT"} = $tmp if ($tmp ne "");
  $tmp = &ask("Enter the username for the MySQL database (leave blank for none) ", "", $prev{"STATUS_MA_USERNAME"}, '');
  $var{"STATUS_MA_USERNAME"} = $tmp if ($tmp ne "");
  $tmp  = &ask("Enter the password for the MySQL database (leave blank for none) ", "", $prev{"STATUS_MA_PASSWORD"}, '');
  $var{"STATUS_MA_PASSWORD"} = $tmp if ($tmp ne "");
  $tmp = &ask("Enter the table in the database to use (leave blank for the default) ", "", $prev{"STATUS_MA_TABLE"}, '');
  $var{"STATUS_MA_TABLE"} = $tmp if ($tmp ne "");
} elsif ($var{"STATUS_MA_TYPE"} eq "ls") {
  $var{"LS"} = &ask("URL for the LS to lookup status MAs from ", "", $prev{"LS"}, '^http:\/\/');
}

$var{"CACHE_LENGTH"} = &ask("How many seconds should the 'current' value be cached for (set to 0 to disable caching)? ", "", $prev{"CACHE_LENGTH"}, '^\d+$');

if ($var{"CACHE_LENGTH"} > 0) {
  $var{"CACHE_FILE"} = &ask("Specify the file to cache the 'current' results in (if relative, it's relative to the installation directory) ", "path_response.cached.xml", $prev{"CACHE_FILE"}, '.+');
}

if (-f $file) {
	system("mv $file $file~");
}

print "Writing $file: ";

open(CONF, ">$file");
print CONF "# created by configure.pl - " . `date`."\n";
print CONF $header;
print CONF "\n\n";
foreach my $v (sort keys %var) {
	print CONF $v . "?" . $var{$v} . "\n";
}
close(CONF);

print "done.\n";

print "Checking dependencies for desired configuration...\n";

CPAN::Shell::setup_output;
CPAN::Index->reload;

for my $need_ref (@needs) {
  my $modname = $$need_ref[0];
  my $modver = $$need_ref[1];

  print "Checking for \"" , $modname , "\"";
  print " version \"" , $modver , "\"" if ($modver > 0);
  print ": ";
  my $mod = CPAN::Shell->expand("Module",$modname);
  if($mod) {
    if(!$mod->inst_version or $mod->inst_version < $modver) {
      print "\tFound \"".$mod->inst_version."\", installing \"".$modver."\".\n";
      eval {
        CPAN::Shell->install($mod);
      };
    }
    else {
      print "\tok\n";
    }
  }
  else {
    print "\tNot Found, installing.\n";
    eval {
      CPAN::Shell->install($modname);
    };
  }
}

if ($need_xmldb) {
  print "Checking for \"Sleepycat XML DB\": ";

  my $flag = dbxml_version();

  eval {
    require Sleepycat::DbXml;
  };

  if($@ or !$flag) {
    print "\tNot Found.\n";
    print <<EOT;
This module requires dbxml 2.(2|3).x to be installed. It is
available in the dbxml distribution:
  $DIST_URL
EOT

    $| = 1;
    print "Do you want to install it right now ([y]/n)?";
    my $in = <>;
    chomp $in;
    if($in =~ /^\s*$/ or $in =~ /y/i) {
      if($> != 0) {
        die "\nYou need to use sudo or be root to do this.\n";
      }

      my $dir = "/usr/local/dbxml-2.3.10";

      $dir = &ask("Directory to install Sleepycat XML DB to ", "$dir", undef, '.+');

      my $configure_opts = "--prefix=$dir --enable-perl";

      eval {
        install_DBXML($DIST_URL, $configure_opts);
      };
      if($@) {
        print $@;
        note();
        exit 0;
      }
    } else {
        note();
        exit 0;
    }
  } else {
    print "\tok.\n";
  }
}

sub ask($$$$) {
  my($prompt,$value,$prev_value,$regex) = @_;

  my $result;
  do {
    print $prompt;
    if (defined $prev_value) {
      print  "[", $prev_value, "]";
    } elsif (defined $value) {
      print  "[", $value, "]";
    }
    print ": ";
    $| = 1;
    $_ = <STDIN>;
    chomp;
    if(defined $_ and $_ ne "") {
      $result = $_;
    } elsif (defined $prev_value) {
      $result = $prev_value;
    } elsif (defined $value) {
      $result = $value;
    } else {
      $result = '';
    }
  } while ($regex ne '' and !($result =~ /$regex/));

  return $result;
}

sub locate($$) {
  my($command, $default) = @_;
  open(CMD, $command . " |");
  my @found = <CMD>;
  close(CMD);
  $found[0] =~ s/\n//g;
  if($found[0]) {
    return $found[0];
  }
  else {
    return $default;
  }
}

sub note() {
  print "################################################\n";
  print "# Please check the INSTALL file for additional #\n";
  print "# help.  You can download the DBXML library f- #\n";
  print "# rom:                                         #\n";
  print "# $DIST_URL\n";
  print "# and compile it using:                        #\n";
  print "#   buildall.sh --prefix=[directory] --enable-perl #\n";
  print "####################################################\n";
  return;
}

sub dbxml_version() {
  my @paths = split /:/, $ENV{PATH};
  push @paths, qw(/bin /sbin /usr /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin /usr/local/dbxml-2.3.10/bin /usr/dbxml-2.3.10/bin /opt/dbxml-2.3.10/bin);

  for(@paths) {
    if(-x "$_/dbxml") {
      open(PIPE, "$_/dbxml -V |");
      my @data = join '', <PIPE>;
      close(PIPE);

      foreach my $d (@data) {
        if($d =~ m/.*Berkeley\s{1}DB\s{1}XML\s{1}2\.(2|3).*/) {
          return 1;
        }
      }
    }
  }

  return 0;
}

sub readConfiguration($$) {
  my ($file, $conf)  = @_;

  my $CONF = new IO::File("<".$file);
  if(defined $CONF) {
    while (<$CONF>) {
      if(!($_ =~ m/^#.*$/) and !($_ =~ m/^\s+/)) {
        $_ =~ s/\n//;
        my @values = split(/\?/,$_);
        $conf->{$values[0]} = $values[1];
      }
    }
    $CONF->close();
  }
}

__END__

=head1 NAME

configure.pl - Ask a series of questions to generate a configuration file.

=head1 DESCRIPTION

Ask questions based on a service to generate a configuration file.
	
=head1 SEE ALSO

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS

Questions and comments can be directed to the author, or the mailing list.  Bugs,
feature requests, and improvements can be directed here:

https://bugs.internet2.edu/jira/browse/PSPS

=head1 VERSION

$Id$

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework along
with this software.  If not, see <http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2004-2007, Internet2 and the University of Delaware

All rights reserved.

=cut
