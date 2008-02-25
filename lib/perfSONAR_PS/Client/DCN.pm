package perfSONAR_PS::Client::DCN;

use fields 'INSTANCE', 'LOGGER';

use strict;
use warnings;

our $VERSION = 0.01;

=head1 NAME

perfSONAR_PS::Client::DCN - Simple library to implement some perfSONAR calls
that DCN tools will require.

=head1 DESCRIPTION

The goal of this module is to provide some simple library calls that DCN
software may implement to receive information from perfSONAR deployments.

=cut

use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);

use perfSONAR_PS::Common qw( genuid makeEnvelope find extract );
use perfSONAR_PS::Transport;
use perfSONAR_PS::Client::Echo;

=head2 new($package { instance })

Constructor for object.  Optional argument of 'instance' is the LS instance
to be contacted for queries.  This can also be set via 'setInstance'.

=cut

sub new {
  my ( $package, @args ) = @_;
  my $parameters = validate(@args, { instance => 0 });

  my $self = fields::new($package);

  $self->{LOGGER} = get_logger("perfSONAR_PS::Client::DCN");
  if(exists $parameters->{"instance"} and $parameters->{"instance"} ne "") {
    $self->{INSTANCE} = $parameters->{"instance"};
  }
  return $self;
}

=head2 setInstance($self { instance })

Required argument 'instance' is the LS instance to be contacted for queries.  

=cut

sub setInstance {
  my ( $self, @args ) = @_;
  my $parameters = validate(@args, { instance => 1 });
  $self->{INSTANCE} = $parameters->{"instance"};
  return;
}

=head2 callLS($self { query })

Calls the LS instance and returns the response message (if any). 

=cut

sub callLS {
  my ( $self, @args ) = @_;
  my $parameters = validate(@args, { query => 1 });

  unless($self->{INSTANCE}) {
    $self->{LOGGER}->error("Instance not defined.");
    return;
  }

  my $echo_service = perfSONAR_PS::Client::Echo->new($self->{INSTANCE});
  my ($status, $res) = $echo_service->ping();
  if($status == -1) {
    $self->{LOGGER}->error("Ping to ".$self->{INSTANCE}." failed: $res");
    return;
  }
  
  my ($host, $port, $endpoint) = &perfSONAR_PS::Transport::splitURI($self->{INSTANCE});
  if (!defined $host && !defined $port && !defined $endpoint) {
    return;
  }
  my $sender = new perfSONAR_PS::Transport($host, $port, $endpoint);
  unless($sender) {
    $self->{LOGGER}->error("LS could not be contaced.");
    return;
  }

  my $error = q{};
  my $responseContent = $sender->sendReceive(makeEnvelope($self->createQuery({ query => $parameters->{query}})), "", \$error);
  if($error ne "") {
    $self->{LOGGER}->error("sendReceive failed: $error");
    return -1;
  }
  
  my $msg = q{};
  my $parser = XML::LibXML->new();
  if(defined $responseContent and $responseContent ne "" and
     !($responseContent =~ m/^\d+/)) {
    my $doc = q{};
    eval {
      $doc = $parser->parse_string($responseContent);
    };
    if($@) {
      $self->{LOGGER}->error("Parser failed: ".$@);
      return;
    }
    else {
      $msg = $doc->getDocumentElement->getElementsByTagNameNS("http://ggf.org/ns/nmwg/base/2.0/", "message")->get_node(1);
    }
  }
  return $msg;
}

=head2 nameToId

Given a name (i.e. DNS 'hostname') return any matching link ids.

=cut

sub nameToId {
  my ( $self, @args ) = @_;
  my $parameters = validate(@args, { name => 1 });
  my @ids = ();

  my $query = "declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\";\n";
  $query .= "declare namespace nmtb=\"http://ogf.org/schema/network/topology/base/20070828/\";\n";
  $query .= "/nmwg:store[\@type=\"LSStore\"]/nmwg:data/nmtb:node[nmtb:address/text()=\"".$parameters->{name}."\"]\n";   
  my $msg = $self->callLS({ query => $query });
  unless($msg) {
    $self->{LOGGER}->error("Message element not found in return.");
    return;
  }
      
  my $links = find($msg, ".//psservice:datum/nmtb:node/nmtb:relation[\@type=\"connectionLink\"]/nmtb:linkIdRef", 0);
  if($links) {
    foreach my $l ($links->get_nodelist) {
      my $value = extract( $l, 0 );
      push @ids, $value if $value;
    }
  }
  else {
    $self->{LOGGER}->error("No link elements found in return.");
    return;
  }

  return \@ids;
}

=head2 idToName

Given a link id return any matching names (i.e. DNS 'hostname').

=cut

sub idToName {
  my ( $self, @args ) = @_;
  my $parameters = validate(@args, { id => 1 });
  my @names = ();

  my $query = "declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\";\n";
  $query .= "declare namespace nmtb=\"http://ogf.org/schema/network/topology/base/20070828/\";\n";
  $query .= "/nmwg:store[\@type=\"LSStore\"]/nmwg:data/nmtb:node[nmtb:relation[\@type=\"connectionLink\"]/nmtb:linkIdRef[text()=\"".$parameters->{id}."\"]]\n";


  my $msg = $self->callLS({ query => $query });
  unless($msg) {
    $self->{LOGGER}->error("Message element not found in return.");
    return;
  }

  my $hostnames = find($msg, ".//psservice:datum/nmtb:node/nmtb:address[\@type=\"hostname\"]", 0);
  if($hostnames) {
    foreach my $hn ($hostnames->get_nodelist) {
      my $value = extract( $hn, 0 );
      push @names, $value if $value;
    }
  }
  else {
    $self->{LOGGER}->error("No name elements found in return.");
    return;
  }

  return \@names;
}

=head2 createQuery($self { query })

Construct a query message for the LS, supplying the specifics of the query to
this function.  

=cut

sub createQuery {
  my ( $self, @args ) = @_;
  my $parameters = validate(@args, { query => 1 });  

  my $request = q{};
  my $mdId = "metadata.".genuid();
  $request .= "<nmwg:message type=\"LSQueryRequest\" id=\"message.".genuid()."\"\n";
  $request .= "              xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"\n";
  $request .= "              xmlns:xquery=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xquery/1.0/\">\n";
  $request .= "  <nmwg:metadata id=\"".$mdId."\">\n";
  $request .= "    <xquery:subject id=\"subject.".genuid()."\">\n";
  $request .= $parameters->{query};
  $request .= "    </xquery:subject>\n";
  $request .= "    <nmwg:eventType>http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xquery/1.0</nmwg:eventType>\n";
  $request .= "  <xquery:parameters id=\"parameters.".genuid()."\">\n";
  $request .= "    <nmwg:parameter name=\"lsOutput\">native</nmwg:parameter>\n";
  $request .= "  </xquery:parameters>\n";
  $request .= "  </nmwg:metadata>\n";
  $request .= "  <nmwg:data metadataIdRef=\"".$mdId."\" id=\"data.".genuid()."\"/>\n";
  $request .= "</nmwg:message>\n";

  return $request;
}

1;

__END__


=head1 SEE ALSO

L<Log::Log4perl>

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

Copyright (c) 2004-2008, Internet2 and the University of Delaware

All rights reserved.

=cut

