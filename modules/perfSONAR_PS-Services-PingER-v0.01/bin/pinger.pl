#!/usr/bin/perl -w -I lib

=head1 NAME

pinger.pl - PingER Measurement Point and Measurement Archive

=head1 DESCRIPTION

PingER provides a framework to collect and analyze network performance between end hosts using
the ICMP 'ping' protocol to measure network latency, network loss and network jitter.

=head1 SYNOPSIS

./pinger.pl [--verbose --help --config=config.file --piddir=/path/to/pid/dir --pidfile=filename.pid]\n";

The verbose flag allows lots of debug options to print to the screen.  If the option is
omitted the service will run in daemon mode.
=cut

our $VERSION = "0.10";

use warnings;
use strict;
use Getopt::Long;
use Time::HiRes qw( gettimeofday );
use POSIX qw( setsid );
use File::Basename;
use Fcntl qw(:DEFAULT :flock);
use POSIX ":sys_wait_h";
use Cwd;
use Config::General;
use Module::Load;
use Data::Dumper;
use HTTP::Daemon;

sub psService($$$);
sub registerLS($);
sub daemonize();
sub managePID($$);
sub killChildren();
sub signalHandler();
sub handleRequest($$$);

# this value should be set by the installation scripts
my $was_installed = 0;

my $libdir;
my $confdir;
my $dirname;

if ($was_installed) {
    # XXX in this case, libdir needs to be set to the directory that the modules
    # were installed to, and confdir needs to be set to the directory that
    # logger.conf et al. were installed in.
    $libdir = "";
    $confdir = "";
    $dirname = "";
} else {
    # we need a fully-qualified directory name in case we daemonize so that we
    # can still access scripts or other files specified in configuration files
    # in a relative manner. Also, we need to know the location in reference to
    # the binary so that users can launch the daemon from wherever but specify
    # scripts and whatnot relative to the binary.

    $dirname = dirname($0);

    if (!($dirname =~ /^\//)) {
        $dirname = getcwd . "/" . $dirname;
    }

    $confdir = $dirname;

    # we need to figure out what the library is at compile time so that "use lib"
    # doesn't fail. To do this, we enclose the calculation of it in a BEGIN block.
    BEGIN {
        $libdir = dirname($0)."/../../lib";
    }
}

use lib "$libdir";

use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;
use perfSONAR_PS::Request;
use perfSONAR_PS::RequestHandler;
use perfSONAR_PS::XML::Document_string;
use perfSONAR_PS::Error_compat qw/:try/;

$0 = "pinger.pl ($$)";

my %child_pids = ();

$SIG{PIPE} = 'IGNORE';
$SIG{ALRM} = 'IGNORE';
$SIG{INT} = \&signalHandler;
$SIG{TERM} = \&signalHandler;

my $DEBUGFLAG = '';
my $READ_ONLY = '';
my $HELP = '';
my $CONFIG_FILE  = '';
my $LOGGER_CONF  = '';
my $PIDDIR = '';
my $PIDFILE = '';
my $LOGOUTPUT = '';

my $status = GetOptions (
        'config=s' => \$CONFIG_FILE,
        'logger=s' => \$LOGGER_CONF,
        'output=s' => \$LOGOUTPUT,
        'piddir=s' => \$PIDDIR,
        'pidfile=s' => \$PIDFILE,
        'verbose' => \$DEBUGFLAG,
        'help' => \$HELP);

if(!$status or $HELP) {
    print "$0: starts the PingER daemon.\n";
    print "\t$0 [--verbose --help --config=config.file --piddir=/path/to/pid/dir --pidfile=filename.pid --logger=logger/filename.conf]\n";
    exit(1);
}

my $logger;
if (!defined $LOGGER_CONF or $LOGGER_CONF eq "") {
    use Log::Log4perl qw(:easy);

    my $output_level = $DEBUG;
    if($DEBUGFLAG) {
        $output_level = $DEBUG;
    }

    my %logger_opts = (
        level => $output_level,
        layout => '%d (%P) %p> %F{1}:%L %M - %m%n',
    );

    if (defined $LOGOUTPUT and $LOGOUTPUT ne "") {
        $logger_opts{file} = $LOGOUTPUT;
    }

    Log::Log4perl->easy_init( \%logger_opts );
    $logger = get_logger("perfSONAR_PS");
} else {
    use Log::Log4perl qw(get_logger :levels);

    my $output_level = $INFO;
    if($DEBUGFLAG) {
        $output_level = $DEBUG;
    }
 
    Log::Log4perl->init($LOGGER_CONF);
    $logger = get_logger("perfSONAR_PS");
    $logger->level($output_level);
}

if (!defined $CONFIG_FILE or $CONFIG_FILE eq "") {
    $CONFIG_FILE = $confdir."/pinger.conf";
}

# Read in configuration information
my $config =  new Config::General($CONFIG_FILE);
my %conf = $config->getall;

if (!defined $conf{"max_worker_lifetime"} or $conf{"max_worker_lifetime"} eq "") {
    $logger->warn("Setting maximum worker lifetime at 60 seconds");
    $conf{"max_worker_lifetime"} = 60;
}

if (!defined $conf{"max_worker_processes"} or $conf{"max_worker_processes"} eq "") {
    $logger->warn("Setting maximum worker processes at 32");
    $conf{"max_worker_processes"} = 32;
}

if (!defined $conf{"ls_registration_interval"} or $conf{"ls_registration_interval"} eq "") {
    $logger->warn("Setting LS registration interval at 60 minutes");
    $conf{"ls_registration_interval"} = 60;
}

# turn the interval from minutes to seconds
$conf{"ls_registration_interval"} *= 60;

if (!defined $conf{"disable_echo"} or $conf{"disable_echo"} eq "") {
    $logger->warn("Enabling echo service for each endpoint unless specified otherwise");
    $conf{"disable_echo"} = 0;
}

if (!defined $conf{"reaper_interval"} or $conf{"reaper_interval"} eq "") {
    $logger->warn("Setting reaper interval to 20 seconds");
    $conf{"reaper_interval"} = 20;
}

if (!defined $PIDDIR or $PIDDIR eq "") {
    if (defined $conf{"pid_dir"} and $conf{"pid_dir"} ne "") {
        $PIDDIR = $conf{"pid_dir"};
    } else {
        $PIDDIR = "/var/run";
    }
}

if (!defined $PIDFILE or $PIDFILE eq "") {
    if (defined $conf{"pid_file"} and $conf{"pid_file"} ne "") {
        $PIDFILE = $conf{"pid_file"};
    } else {
        $PIDFILE = "pinger.pid";
    }
}

managePID($PIDDIR, $PIDFILE);

$logger->debug("Starting '".$$."'");

my @ls_services;

my %loaded_modules = ();
my $echo_module = "perfSONAR_PS::Services::Echo";

my %handlers = ();
my %listeners = ();
my %modules_loaded = ();
my %port_configs = ();
my %service_configs = ();

if (!defined $conf{"port"}) {
    my $logger->error("No ports defined");
    exit(-1);
}

foreach my $port (keys %{ $conf{"port"} }) {
    my %port_conf = %{ mergeConfig(\%conf, $conf{"port"}->{$port}) };

    $service_configs{$port} = \%port_conf;

    if (!defined $conf{"port"}->{$port}->{"endpoint"}) {
        $logger->warn("No endpoints specified for port $port");
        next;
    }

    my $listener = HTTP::Daemon->new(
                        LocalPort => $port,
                        ReuseAddr => 1,
                        Timeout => $port_conf{"reaper_interval"},
                    ); 
    if (!defined $listener != 0) {
        $logger->error("Couldn't start daemon on port $port");
        exit(-1);
    }

    $listeners{$port} = $listener;

    $handlers{$port} = ();

    $service_configs{$port}->{"endpoint"} = ();

    my $num_endpoints = 0;

    foreach my $endpoint (keys %{ $conf{"port"}->{$port}->{"endpoint"} }) {
        my %endpoint_conf = %{ mergeConfig(\%port_conf, $conf{"port"}->{$port}->{"endpoint"}->{$endpoint}) };

        $service_configs{$port}->{"endpoint"}->{$endpoint} = \%endpoint_conf;

        next if (defined $endpoint_conf{"disabled"} and $endpoint_conf{"disabled"} == 1);

        $logger->debug("Adding endpoint $endpoint to $port");

        $handlers{$port}->{$endpoint} = perfSONAR_PS::RequestHandler->new();

        if (!defined $endpoint_conf{"module"} or $endpoint_conf{"module"} eq "") {
            $logger->error("No module specified for $port:$endpoint");
            exit(-1);
        }

        if (!defined $modules_loaded{$endpoint_conf{"module"}}) {
            load $endpoint_conf{"module"};
            $modules_loaded{$endpoint_conf{"module"}} = 1;
        }

        my $service = $endpoint_conf{"module"}->new(\%endpoint_conf, $port, $endpoint, $dirname);
        if ($service->init($handlers{$port}->{$endpoint}) != 0) {
            $logger->error("Failed to initialize module ".$endpoint_conf{"module"}." on $port:$endpoint");
            exit(-1);
        }

        if ($service->needLS()) {
            my %ls_child_args = ();
            $ls_child_args{"service"} = $service;
            $ls_child_args{"conf"} = \%endpoint_conf;
            $ls_child_args{"port"} = $port;
            $ls_child_args{"endpoint"} = $endpoint;
            push @ls_services, \%ls_child_args;
        }

        # the echo module is loaded by default unless otherwise specified
        if ((!defined $endpoint_conf{"disable_echo"} or $endpoint_conf{"disable_echo"} == 0) and
                (!defined $conf{"disable_echo"} or $conf{"disable_echo"} == 0)) {
            if (!defined $modules_loaded{$echo_module}) {
                load $echo_module;
                $modules_loaded{$echo_module} = 1;
            }

            my $echo = $echo_module->new(\%endpoint_conf, $port, $endpoint, $dirname);
            if ($echo->init($handlers{$port}->{$endpoint}) != 0) {
                $logger->error("Failed to initialize echo module on $port:$endpoint");
                exit(-1);
            }
        }

        $num_endpoints++;
    }

    if ($num_endpoints == 0) {
        $logger->warn("No endpoints enabled for port $port");

        delete($listeners{$port});
        delete($handlers{$port});
        delete($service_configs{$port});
    }
}

# Daemonize if not in debug mode. This must be done before forking off children
# so that the children are daemonized as well.
if(!$DEBUGFLAG) {
# flush the buffer
    $| = 1;
#	&daemonize;
}

foreach my $port (keys %listeners) {
    my $pid = fork();
    if ($pid == 0) {
        %child_pids = ();
        $0 .= " - Listener ($port)";
        psService($listeners{$port}, $handlers{$port}, $service_configs{$port});
        exit(0);
    } elsif ($pid < 0) {
        $logger->error("Couldn't spawn listener child");
        killChildren();
        exit(-1);
    } else {
        $child_pids{$pid} = "";
    }
}

foreach my $ls_args (@ls_services) {
    my $ls_pid = fork();
    if ($ls_pid == 0) {
        %child_pids = ();
        $0 .= " - LS Registration (".$ls_args->{"port"}.":".$ls_args->{"endpoint"}.")";;
        registerLS($ls_args);
        exit(0);
    } elsif ($ls_pid < 0) {
        $logger->error("Couldn't spawn LS");
        killChildren();
        exit(-1);
    }

    $child_pids{$ls_pid} = "";
}

foreach my $pid (keys %child_pids) {
    waitpid($pid, 0);
}

=head2 psService
This function will wait for requests using the specified listener. It
will then select the appropriate endpoint request handler, spawn a new
process to handle the request and pass the request to the request handler.
The function also tracks the processes spawned and kills them if they
go on for too long, responding to the request with an error.
=cut
sub psService($$$) {
    my ($listener, $handlers, $service_config) = @_;
    my $max_worker_processes;

    $logger->debug("Starting '".$$."' as the MA.");

    $max_worker_processes = $service_config->{"max_worker_processes"};

    while(1) {
        if ($max_worker_processes > 0) {
            while (%child_pids and scalar(keys %child_pids) >= $max_worker_processes) {
                $logger->debug("Waiting for a slot to open");
                my $kid = waitpid(-1, 0);
                if ($kid > 0) {
                    delete $child_pids{$kid};
                }
            }
        }

        if (%child_pids) {
            my $time = time;

            $logger->debug("Reaping children (total: " .scalar  (keys %child_pids) . ") at time " . $time );

            # reap any children that have finished or outlived their allotted time
            foreach my $pid (keys %child_pids) {
                if (waitpid($pid, WNOHANG))  {
                    $logger->debug("Child $pid exited.");
                    delete $child_pids{$pid};
                } elsif ($child_pids{$pid}->{"timeout_time"} <= $time) {
                    $logger->error("Pid $pid timed out.");
                    kill 9, $pid;

                    my $ret_message = new perfSONAR_PS::XML::Document_string();
                    my $msg = "Timeout occurred, current limit is ".$child_pids{$pid}->{"child_timeout_length"}." seconds. Try decreasing the breadth of your search if possible.";
                    getResultCodeMessage($ret_message, "message.".genuid(), "", "", "response", "error.perfSONAR_PS.MA", $msg, undef, 1);

                    my $response = HTTP::Response->new();
                    $response->message("success");
                    $response->header('Content-Type' => 'text/xml');
                    $response->header('user-agent' => 'perfSONAR-PS/1.0b');
                    $response->content(makeEnvelope($ret_message->getValue()));
                    $child_pids{$pid}->{"listener"}->send_response($response);
                    $child_pids{$pid}->{"listener"}->close();
                }
            }
        }

        my $handle = $listener->accept;
        if (!defined $handle) {
            my $msg = "Accept returned nothing, likely a timeout occurred";
            $logger->debug($msg);
        } else {
            $logger->info("Received incoming connection from:\t".$handle->peerhost());
            my $pid = fork();
            if ($pid == 0) {
                %child_pids = ();

                $0 .= " - ".$handle->peerhost();

                my $http_request = $handle->get_request;
                if (!defined $http_request) {
                    my $msg = "No HTTP Request received from host:\t".$handle->peerhost();
                    $logger->error($msg);
                    $handle->close;
                    exit(-1);
                }

                my $request = perfSONAR_PS::Request->new($handle, $http_request);
                if (!defined $handlers->{$request->getEndpoint()}) {
                    my $ret_message = new perfSONAR_PS::XML::Document_string();
                    my $msg = "Received message with has invalid endpoint: ".$request->getEndpoint();
                    getResultCodeMessage($ret_message, "message.".genuid(), "", "", "response", "error.perfSONAR_PS.transport", $msg, undef, 1);
                    $request->setResponse($ret_message->getValue());
                    $request->finish();
                } else {
                    $0 .= " - ".$request->getEndpoint();
                    handleRequest($handlers->{$request->getEndpoint()}, $request, $service_config->{"endpoint"}->{$request->getEndpoint()});
                }
                exit(0);
            } elsif ($pid < 0) {
                $logger->error("Error spawning child");
            } else {
                my $max_worker_lifetime =  $service_config->{"max_worker_lifetime"};
                my %child_info = ();
                $child_info{"listener"} = $handle;
                $child_info{"timeout_time"} = time + $max_worker_lifetime;
                $child_info{"child_timeout_length"} = $max_worker_lifetime;
                $child_pids{$pid} = \%child_info;
            }
        }
    }
}

=head2 registerLS($args)
    The registerLS function is called in a separate process or thread and
    is responsible for calling the specified service's 'registerLS'
    function regularly.
=cut
sub registerLS($) {
    my ($args) = @_;

    my $service = $args->{"service"};
    my $default_interval = $args->{"conf"}->{"ls_registration_interval"};

    $logger->debug("Starting '".$$."' for LS registration");

    while(1) {
        my $sleep_time;

        $service->registerLS(\$sleep_time);

        if (!defined $sleep_time or $sleep_time eq "") {
            $sleep_time = $default_interval;
        }

        $logger->debug("Sleeping for $sleep_time");

        sleep($sleep_time);
    }
}

=head2 handleRequest($handler, $request, $endpoint_conf);
This function is a wrapper around the handler's handleRequest function.
It's purpose is to ensure that if a crash occurs or a perfSONAR_PS::Error_compat
message is thrown, the client receives a proper response.
=cut
sub handleRequest($$$) {
    my ($handler, $request, $endpoint_conf) = @_;

    my $messageId = "";


    try {
        my $error;

        if($request->getRawRequest->method ne "POST") {
            my $msg = "Received message with 'INVALID REQUEST', are you using a web browser?";
            $logger->error($msg);     
            throw perfSONAR_PS::Error_compat("error.perfSONAR_PS.MA", $msg);
        }

        my $action = $request->getRawRequest->headers->{"soapaction"};
        if (!$action =~ m/^.*message\/$/) {
            my $msg = "Received message with 'INVALID ACTION TYPE'.";
            $logger->error($msg);     
            throw perfSONAR_PS::Error_compat("error.perfSONAR_PS.MA", $msg);
        }

        $request->parse(\$error);
        if (defined $error and $error ne "") {
            throw perfSONAR_PS::Error_compat("error.transport.parse_error", "Error parsing request: $error");
        }

        my $message = $request->getRequestDOM()->getDocumentElement();;
        $messageId = $message->getAttribute("id");
        $handler->handleMessage($message, $request, $endpoint_conf);
    }
    catch perfSONAR_PS::Error_compat with {
        my $ex = shift;

        my $msg = "Error handling request: ".$ex->eventType." => \"".$ex->errorMessage."\"";
        $logger->error($msg);


        my $ret_message = new perfSONAR_PS::XML::Document_string();
        getResultCodeMessage($ret_message, "message.".genuid(), $messageId, "", "response", $ex->eventType, $ex->errorMessage, undef, 1);
        $request->setResponse($ret_message->getValue());
    }
    otherwise { 
        my $ex = shift;
        my $msg = "Unhandled exception or crash: $ex";
        $logger->error($msg);

        my $ret_message = new perfSONAR_PS::XML::Document_string();
        getResultCodeMessage($ret_message, "message.".genuid(), $messageId, "", "response", "error.perfSONAR_PS.MA", "An internal error occurred", undef, 1);
        $request->setResponse($ret_message->getValue());
    };

    $request->finish();
}

=head2 daemonize
Sends the program to the background by eliminating ties to the calling terminal.
=cut
sub daemonize() {
    chdir '/' or die "Can't chdir to /: $!";
    open STDIN, '/dev/null' or die "Can't read /dev/null: $!";
    open STDOUT, '>>/dev/null' or die "Can't write to /dev/null: $!";
    open STDERR, '>>/dev/null' or die "Can't write to /dev/null: $!";
    defined(my $pid = fork) or die "Can't fork: $!";
    exit if $pid;
    setsid or die "Can't start a new session: $!";
    umask 0;
}

=head2 managePID($piddir, $pidfile);
The managePID function checks for the existence of the specified file in
the specified directory. If found, it checks to see if the process in the
file still exists. If there is no running process, it writes its pid to the
file. If there is, the function performs a die alerting the user that the
process is already running.
=cut
sub managePID($$) {
    my($piddir, $pidfile) = @_;
    die "Can't write pidfile: $pidfile\n" unless -w $piddir;
    $pidfile = $piddir ."/".$pidfile;
    sysopen(PIDFILE, $pidfile, O_RDWR | O_CREAT);
    flock(PIDFILE, LOCK_EX);
    my $p_id = <PIDFILE>;
    chomp($p_id);
    if($p_id ne "") {
        open(PSVIEW, "ps -p ".$p_id." |");
        my @output = <PSVIEW>;
        close(PSVIEW);
        if(!$?) {
            die "$0 already running: $p_id\n";
        }
        else {
            truncate(PIDFILE, 0);
            seek(PIDFILE, 0, 0);
            print PIDFILE "$$\n";
        }
    }
    else {
        print PIDFILE "$$\n";
    }
    flock(PIDFILE, LOCK_UN);
    close(PIDFILE);
    return;
}

=head2 killChildren
Kills all the children for this process off. It uses global variables
because this function is used by the signal handler to kill off all
child processes.
=cut
sub killChildren() {
    foreach my $pid (keys %child_pids) {
        kill("SIGINT", $pid);
    }
}

=head2 signalHandler
Kills all the children for the process and then exits
=cut
sub signalHandler() {
    killChildren();
    exit(0);
}

=head1 SEE ALSO

L<perfSONAR_PS::Services::Base>, L<perfSONAR_PS::Services::MA::General>, L<perfSONAR_PS::Common>,
L<perfSONAR_PS::Messages>, L<perfSONAR_PS::Transport>,
L<perfSONAR_PS::Client::Status::MA>, L<perfSONAR_PS::Client::Topology::MA>

To join the 'perfSONAR-PS' mailing list, please visit:

https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

https://svn.internet2.edu/svn/perfSONAR-PS

Questions and comments can be directed to the author, or the mailing list.

=head1 VERSION

$Id:$

=head1 AUTHOR

Aaron Brown, aaron@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework along
with this software.  If not, see <http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2004-2007, Internet2 and the University of Delaware

All rights reserved.

=cut

# vim: expandtab shiftwidth=4 tabstop=4
