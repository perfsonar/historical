#!/usr/bin/perl -w

package perfSONAR_PS::MA::Echo;

use warnings;
use strict;
use Exporter;
use Log::Log4perl qw(get_logger);

use perfSONAR_PS::MA::Base;
use perfSONAR_PS::MA::General;
use perfSONAR_PS::Common;
use perfSONAR_PS::Messages;

sub new {
	my ($package, $conf, $directory) = @_;

	my %hash = ();

	if(defined $conf and $conf ne "") {
		$hash{"CONF"} = \%{$conf};
	}

	if (defined $directory and $directory ne "") {
		$hash{"DIRECTORY"} = $directory;
	}

	bless \%hash => $package;
}

sub init {
	my ($self, $handler) = @_;
	my $logger = get_logger("perfSONAR_PS::MA::Echo");

	$handler->add("", "EchoRequest", "http://schemas.perfsonar.net/tools/admin/echo/2.0", $self);
	$handler->add("", "EchoRequest", "http://schemas.perfsonar.net/tools/admin/echo/ls/2.0", $self);
	$handler->add("", "EchoRequest", "http://schemas.perfsonar.net/tools/admin/echo/ma/2.0", $self);
	$handler->addRegex("", "EchoRequest", "^echo.*", $self);

	$handler->setMessageResponseType("", "EchoRequest", "EchoResponse");

	return 0;
}

sub needLS() {
	return 0;
}

sub handleEvent($$$$$$$$$) {
	my ($self, $output, $endpoint, $messageType, $message_parameters, $eventType, $md, $d, $raw_message) = @_;

	my $retMetadata;
	my $retData;
	my $mdID = "metadata.".genuid();
	my $msg = "The echo request has passed.";

	my @ret_elements = ();

	getResultCodeMetadata($output, $mdID, $md->getAttribute("id"), "success.echo");
	getResultCodeData($output, "data.".genuid(), $mdID, $msg, 1);

	return ("", "");
}

1;

__END__
=head1 NAME

perfSONAR_PS::MA::Skeleton - A skeleton of an MA module that can be modified as needed.

=head1 DESCRIPTION

This module aims to be easily modifiable to support new and different MA types.

=head1 SYNOPSIS

use perfSONAR_PS::MA::Skeleton;

my %conf;

my $default_ma_conf = &perfSONAR_PS::MA::Skeleton::getDefaultConfig();
if (defined $default_ma_conf) {
	foreach my $key (keys %{ $default_ma_conf }) {
		$conf{$key} = $default_ma_conf->{$key};
	}
}

if (readConfiguration($CONFIG_FILE, \%conf) != 0) {
	print "Couldn't read config file: $CONFIG_FILE\n";
	exit(-1);
}

my %ns = (
		nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
		ifevt => "http://ggf.org/ns/nmwg/event/status/base/2.0/",
		nmtopo => "http://ogf.org/schema/network/topology/base/20070828/",
	 );

my $ma = perfSONAR_PS::MA::Skeleton->new(\%conf, \%ns);

# or
# $ma = perfSONAR_PS::MA::Skeleton->new;
# $ma->setConf(\%conf);
# $ma->setNamespaces(\%ns);

if ($ma->init != 0) {
	print "Error: couldn't initialize measurement archive\n";
	exit(-1);
}

$ma->registerLS;

while(1) {
	my $request = $ma->receive;
	$ma->handleRequest($request);
}

=head1 API

The offered API is simple, but offers the key functions needed in a measurement archive.

=head2 getDefaultConfig

	Returns a reference to a hash containing default configuration options

=head2 getDefaultNamespaces

	Returns a reference to a hash containing the set of namespaces used by
	the MA

=head2 init

       Initializes the MA and validates the entries in the
       configuration file. Returns 0 on success and -1 on failure.

=head2 registerLS($self)

	Registers the data contained in the MA with the configured LS.

=head2 receive($self)

	Grabs an incoming message from transport object to begin processing. It
	completes the processing if the message was handled by a lower layer.
	If not, it returns the Request structure.

=head2 handleRequest($self, $request)

	Handles the specified request returned from receive()

=head2 __handleRequest($self)

	Validates that the message is one that we can handle, calls the
	appropriate function for the message type and builds the response
	message.

=head2 handleMessage($self, $messageType, $message)
	Handles the specific message. This should entail iterating through the
	metadata/data pairs and handling each one.

=head2 handleMetadataPair($$$$) {
	Handles a specific metadata/data request.


=head1 SEE ALSO

L<perfSONAR_PS::MA::Base>, L<perfSONAR_PS::MA::General>, L<perfSONAR_PS::Common>,
L<perfSONAR_PS::Messages>, L<perfSONAR_PS::LS::Register>


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
