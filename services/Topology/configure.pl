#!/usr/bin/perl -w -Ilib

use strict;
use warnings;
use CPAN;

sub install_DBXML($$);
sub note();
sub ask($$$$);
sub locate($$);
sub dbxml_version();
sub readConfiguration($$);

my $DIST_URL = "http://download.oracle.com/berkeley-db/dbxml-2.3.10.tar.gz";

print " -- perfSONAR-PS Topology MA Configuration --\n";
print " - [press enter for the default choice] -\n\n";

my $file = shift;

$file = &ask("What file should I write the configuration to? ", "topology.conf", undef, '.+');

my %var = ();
my %prev = ();
my $tmp;

if (-f $file) {
	readConfiguration($file, \%prev);
}

my $header = <<EOF
# ######################################################### #
# Use:      Lines starting with a sharp are comments, this  #
#           file understands the following directives:      #
#                                                           #
#      ENABLE_REGISTRATION = 0 or 1. Disables the LS        #
#            registration                                   #
#      PORT = Listen port for the application. This should  #
#            be something that can be accessed from the     #
#            outside world.                                 #
#      ENDPOINT = An 'endPoint' is a contact string that a  #
#            service is listening on.  This is used in      #
#            conjunction with the port and hostname:        #
#                                                           #
#                 http://HOST:PORT/end/Point/String         #
#                                                           #
#      LS_INSTANCE = The LS that will be contacted to       #
#            register this service.                         #
#      LS_REGISTRATION_INTERVAL = The interval of time (in  #
#            minutes) that this service will contact the    #
#            S_INSTANCE to register itself.                 #
#      SERVICE_NAME = String describing the MA's 'name'.    #
#      SERVICE_ACCESSPOINT = String describing the          #
#            'accessPoint' of this MA.  This string is how  #
#            the service can be reached:                    #
#                                                           #
#                 http://HOST:PORT/end/Point/String         #
#      SERVICE_TYPE = String describing the 'type' of this  #
#            MA, it can be just 'MA' or 'SNMP MA', etc.     #
#            Defaults to "MA".                              #
#      SERVICE_DESCRIPTION = String describing this MA, it  #
#            can include location info, etc. Defaults to    #
#            "Topology Measurement Archive"                 #
#                                                           #
#     TOPO_DB_TYPE = XML                                    #
#     TOPO_DB_ENVIRONMENT = The directory where the         #
#            database file lives. This directory should be  #
#            specific to this database.                     #
#     TOPO_DB_FILE = The database file's name               #
#                                                           #
#     READ_ONLY = 0 or 1. Renders the MA read-only.         #
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

$var{"PORT"} = &ask("Enter the listen port ", "8083", $prev{"PORT"}, '^\d+$');

$var{"ENDPOINT"} = &ask("Enter the listen end point ", "/perfSONAR_PS/services/topology", $prev{"ENDPOINT"}, "");

$var{"MAX_WORKER_PROCESSES"} = &ask("Enter the maximum number of children processes (0 means infinite) ", "0", $prev{"MAX_WORKER_PROCESSES"}, "");

$var{"MAX_WORKER_LIFETIME"} = &ask("Enter number of seconds a child can process before it is stopped (0 means infinite) ", "0", $prev{"MAX_WORKER_LIFETIME"}, "");

$var{"TOPO_DB_TYPE"} = "XML";

$var{"TOPO_DB_ENVIRONMENT"} = &ask("Enter the directory containing the XML Database (if relative, it's relative to the installation directory) ", "xmldb", $prev{"TOPO_DB_ENVIRONMENT"}, "");

$var{"TOPO_DB_FILE"} = &ask("Enter the filename for the XML Database ", "topology.dbxml", $prev{"TOPO_DB_FILE"}, "");

$var{"READ_ONLY"} = &ask("Is this service read-only? ", "0|1", $prev{"READ_ONLY"}, '^[01]$');

$var{"ENABLE_REGISTRATION"} = &ask("Will this service register with an LS ", "0|1", $prev{"ENABLE_REGISTRATION"}, '^[01]$');

if($var{"ENABLE_REGISTRATION"} eq "1") {
  $var{"LS_REGISTRATION_INTERVAL"} = &ask("Enter the number of minutes between LS registrations ", "30", $prev{"LS_REGISTRATION_INTERVAL"}, '^\d+$');

  $var{"LS_INSTANCE"} = &ask("URL of an LS to register with ", "http://perfSONAR2.cis.udel.edu:8181/perfSONAR_PS/services/LS", $prev{"LS_INSTANCE"}, '^http:\/\/');

  $var{"SERVICE_NAME"} = &ask("Enter a name for this service ", "Topology MA", $prev{"SERVICE_NAME"}, '.+');

  $var{"SERVICE_TYPE"} = &ask("Enter the service type ", "MA", $prev{"SERVICE_TYPE"}, '.+');

  $var{"SERVICE_DESCRIPTION"} = &ask("Enter a service description ", "Topology MA", $prev{"SERVICE_DESCRIPTION"}, '.+');

  my $external_hostname;
  $external_hostname = &ask("External hostname for this service ", "", undef, '.+');

  $var{"SERVICE_ACCESSPOINT"} = "http://".$external_hostname.":".$var{"PORT"}.$var{"ENDPOINT"};
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
  }
  else {
    note();
    exit 0;
  }
} else {
  print "\tok.\n";
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

sub install_DBXML($$) {
  my ($url, $config_opts) = @_;
  my $mod = CPAN::Shell->expand("Module","LWP::Simple");
  if($mod) {
    if(!$mod->inst_version) {
      CPAN::Shell->install($mod);
    }
  }
  require LWP::Simple;
  print STDERR "Downloading ... ";
  LWP::Simple::getstore($url, basename($url)) or
    die "Cannot download $url ($!)";
  print STDERR "done.\n";
  system("gzip -dc dbxml-2.3.10.tar.gz | tar xfv -; cd dbxml-2.3.10; ./buildall.sh $config_opts") and die "Install failed: $!";
  return;
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
