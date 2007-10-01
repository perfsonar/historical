#!/usr/bin/perl -w

use strict;
use warnings;
use CPAN;

print " -- perfSONAR-PS Status MA Configuration --\n";
print " - [press enter for the default choice] -\n\n";

sub ask($$$$);
sub locate($$);
sub readConfiguration($$);

my $file = shift;

while(!defined $file or $file eq "") {
  $file = &ask("What file should I write the configuration to? ", "status.conf", undef, '.+');
}

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
#      ENABLE_MA = 0 or 1. Enables the Web Services         #
#            interface to the MA.                           #
#      ENABLE_COLLECTOR = 0 or 1. Enables the periodic      #
#            collection of status information.              #
#      ENABLE_REGISTRATION = 0 or 1. Enables the LS         #
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
#            "Link Status Measurement Archive"              #
#                                                           #
#      LINK_FILE = The set of links to collect status       #
#            information on                                 #
#      LINK_FILE_TYPE = The only valid value is 'file'      #
#                                                           #
#      STATUS_DB_TYPE = SQLite or MySQL                     #
#      STATUS_DB_NAME = The database name (the file in the  #
#             case of SQLite)                               #
#      STATUS_DB_HOST = The database host (only makes sense #
#             for MySQL)                                    #
#      STATUS_DB_PORT = The database port (only makes sense #
#             for MySQL)                                    #
#      STATUS_DB_USERNAME = The username for the database   #
#      STATUS_DB_PASSWORD = The password for the database   #
#      STATUS_DB_TABLE = The table in the database to       #
#             update                                        #
#                                                           #
#      SAMPLE_RATE = The interval of time (in seconds)      #
#             between link status updates                   #
#                                                           #
#      STATUS_MA_TYPE = MA, SQLite or MySQL (if             #
#             unspecified, the collector will store its     #
#             data into the database specified above).      #
#      STATUS_MA_URI = The location of a remote MA to       #
#             update                                        #
#      STATUS_MA_NAME = The database name (the file in the  #
#             case of SQLite, makes no sense in the case of #
#             MA)                                           #
#      STATUS_MA_HOST = The database host (only makes sense #
#             for MySQL)                                    #
#      STATUS_MA_PORT = The database port (only makes sense #
#             for MySQL)                                    #
#      STATUS_MA_USERNAME = The username for the database   #
#      STATUS_MA_PASSWORD = The password for the database   #
#      STATUS_MA_TABLE = The table in the database to       #
#             update (makes no sense in the case of MA)     #
#                                                           #
#      READ_ONLY = 0 or 1. Renders the Status MA read-only. #
#             The collector can still write to the database #
#             directly. However, any request coming in via  #
#             the web services interface will fail.         #
#                                                           #
#      MAX_WORKER_PROCESSES = Maximum number of child       #
#            processes that can be spawned at a given time. #
#                                                           #
#      MAX_WORKER_LIFETIME = Maximum amount of time a child #
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


$var{"ENABLE_MA"} = &ask("Enable the Measurement Archive? ", "0|1", $prev{"ENABLE_MA"}, '^[01]$');

if ($var{"ENABLE_MA"} == 1) {
  $var{"PORT"} = &ask("Enter the listen port ", "8082", $prev{"PORT"}, '^\d+$');

  $var{"ENDPOINT"} = &ask("Enter the listen end point ", "/perfSONAR_PS/services/status", $prev{"ENDPOINT"}, '.+');

  $var{"MAX_WORKER_PROCESSES"} = &ask("Enter the maximum number of children processes (0 means infinite) ", "0", $prev{"MAX_WORKER_PROCESSES"}, '^\d+$');

  $var{"MAX_WORKER_LIFETIME"} = &ask("Enter number of seconds a child can process before it is stopped (0 means infinite) ", "0", $prev{"MAX_WORKER_LIFETIME"}, "");

  $var{"READ_ONLY"} = &ask("Is this service read-only? ", "0|1", $prev{"READ_ONLY"}, '^[01]$');

  $var{"STATUS_DB_TYPE"} = &ask("Enter the database type to read from ", "sqlite|mysql", $prev{"STATUS_DB_TYPE"}, '(sqlite|mysql)');

  if ($var{"STATUS_DB_TYPE"} eq "sqlite") {
    push @needs, [ ('DBI', '0') ];
    push @needs, [ ('DBD::SQLite', '0') ];

    $var{"STATUS_DB_NAME"} = &ask("Enter the filename of the SQLite database (if relative, it's relative to the installation directory) ", "status.db", $prev{"STATUS_DB_NAME"}, '.+');
    $tmp = &ask("Enter the table in the database to use ", "link_status", $prev{"STATUS_DB_TABLE"}, '.+');
    $var{"STATUS_DB_TABLE"} = $tmp if ($tmp ne "");
  } elsif ($var{"STATUS_DB_TYPE"} eq "mysql") {
    push @needs, [ ('DBI', '0') ];
    push @needs, [ ('DBD::mysql', '0') ];

    $var{"STATUS_DB_NAME"} = &ask("Enter the name of the MySQL database ", "", $prev{"STATUS_DB_NAME"}, '.+');
    $var{"STATUS_DB_HOST"} = &ask("Enter the host for the MySQL database ", "localhost", $prev{"STATUS_DB_HOST"}, '.+');
    $tmp = &ask("Enter the port for the MySQL database (leave blank for the default)", "", $prev{"STATUS_DB_PORT"}, '^\d*$');
    $var{"STATUS_DB_PORT"} = $tmp if ($tmp ne "");
    $tmp = &ask("Enter the username for the MySQL database (leave blank for none) ", "", $prev{"STATUS_DB_USERNAME"}, '');
    $var{"STATUS_DB_USERNAME"} = $tmp if ($tmp ne "");
    $tmp  = &ask("Enter the password for the MySQL database (leave blank for none) ", "", $prev{"STATUS_DB_PASSWORD"}, '');
    $var{"STATUS_DB_PASSWORD"} = $tmp if ($tmp ne "");
    $tmp = &ask("Enter the table in the database to use (leave blank for the default) ", "link_status", $prev{"STATUS_DB_TABLE"} , '');
    $var{"STATUS_DB_TABLE"} = $tmp if ($tmp ne "");
  }

  $var{"ENABLE_REGISTRATION"} = &ask("Will this service register with an LS ", "0|1", $prev{"ENABLE_REGISTRATION"}, '^[01]$');

  if($var{"ENABLE_REGISTRATION"} eq "1") {
    $var{"LS_REGISTRATION_INTERVAL"} = &ask("Enter the number of minutes between LS registrations ", "30", $prev{"LS_REGISTRATION_INTERVAL"}, '^\d+$');

    $var{"LS_INSTANCE"} = &ask("URL of an LS to register with ", "http://perfSONAR2.cis.udel.edu:8181/perfSONAR_PS/services/LS", $prev{"LS_INSTANCE"}, '^http:\/\/');

    $var{"SERVICE_NAME"} = &ask("Enter a name for this service ", "Link Status MA", $prev{"SERVICE_NAME"}, '.+');

    $var{"SERVICE_TYPE"} = &ask("Enter the service type ", "MA", $prev{"SERVICE_TYPE"}, '.+');

    $var{"SERVICE_DESCRIPTION"} = &ask("Enter a service description ", "Link Status MA", $prev{"SERVICE_DESCRIPTION"}, '.+');

    my $external_hostname = &ask("External hostname for this service ", "", '', '.+');

    $var{"SERVICE_ACCESSPOINT"} = "http://".$external_hostname.":".$var{"PORT"}.$var{"ENDPOINT"};
  }
}

$var{"ENABLE_COLLECTOR"} = &ask("Enable the Link Status Collector? ", "0|1", $prev{"ENABLE_COLLECTOR"}, '^[01]$');

if ($var{"ENABLE_COLLECTOR"} == 1) {
  $var{"SAMPLE_RATE"} = &ask("Enter the number of seconds between status collections ", "60", $prev{"SAMPLE_RATE"}, '^\d+$');

  $var{"LINK_FILE"} = "links.conf";
  $var{"LINK_FILE_TYPE"} = "file";

  my $reuse = 0;
  if (defined $var{"STATUS_DB_TYPE"} and $var{"STATUS_DB_TYPE"} ne "") {
    my $reused_before;

    if (defined $prev{"STATUS_MA_TYPE"}) {
      $reused_before = 1;
    } elsif (defined $prev{"ENABLE_COLLECTOR"} and $prev{"ENABLE_COLLECTOR"} eq "1") {
      $reused_before = 0;
    }

    $reuse = &ask("Would you like to reuse the same database settings as the MA? ", "0|1", $reused_before, '^[01]$');
  }

  if ($reuse == 0) {
    $var{"STATUS_MA_TYPE"} = &ask("Enter the database type to read from ", "sqlite|mysql|ma", $prev{"STATUS_MA_TYPE"}, '(sqlite|mysql|ma)');

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
      $tmp = &ask("Enter the host for the MySQL database ", "localhost", $prev{"STATUS_MA_HOST"}, '');
      $var{"STATUS_MA_HOST"} = $tmp if ($tmp ne "");
      $tmp = &ask("Enter the port for the MySQL database (leave blank for the default) ", "", $prev{"STATUS_MA_PORT"}, '^\d*$');
      $var{"STATUS_MA_PORT"} = $tmp if ($tmp ne "");
      $tmp = &ask("Enter the username for the MySQL database (leave blank for none) ", "", $prev{"STATUS_MA_USERNAME"}, '');
      $var{"STATUS_MA_USERNAME"} = $tmp if ($tmp ne "");
      $tmp  = &ask("Enter the password for the MySQL database (leave blank for none) ", "", $prev{"STATUS_MA_PASSWORD"}, '');
      $var{"STATUS_MA_PASSWORD"} = $tmp if ($tmp ne "");
      $tmp = &ask("Enter the table in the database to use (leave blank for the default) ", "link_status", $prev{"STATUS_MA_TABLE"}, '');
      $var{"STATUS_MA_TABLE"} = $tmp if ($tmp ne "");
    } else {
      $var{"STATUS_MA_URI"} = &ask("URL for the MA to store to ", "", $prev{"STATUS_MA_URI"}, '^http:\/\/');
    }
  }
}

print "Writing $file: ";

if (-f $file) {
	system("mv $file $file~");
}

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
