#!/usr/bin/perl

package Netradar::MP::SNMP;
use Carp;
use Net::SNMP;
@ISA = ('Exporter');
@EXPORT = ();

our $VERSION = '0.02';

sub new {
  my ($package, $host, $port, $ver, $comm, $var) = @_; 
  my %hash = ();
  $hash{"FILENAME"} = "Netradar::MP::SNMP";
  $hash{"FUNCTION"} = "\"new\"";
  if(defined $host && $host ne "") {
    $hash{"HOST"} = $host;
  }
  if(defined $port && $port ne "") {
    $hash{"PORT"} = $port;
  }
  else {
    $hash{"PORT"} = 161;
  }
  if(defined $ver && $ver ne "") {
    $hash{"VERSION"} = $ver;
  }
  if(defined $comm && $comm ne "") {
    $hash{"COMMUNITY"} = $comm; 
  }
  if(defined $var && $var ne "") {
    my %vars = %{$var};  
    $hash{"VARIABLES"} = \%vars;  
  }
  bless \%hash => $package;
}


sub setHost {
  my ($self, $host) = @_;  
  $self->{FUNCTION} = "\"setHost\"";  
  if(defined $host) {
    $self->{HOST} = $host;
  }
  else {
    croak($self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION});
  }
  return;
}


sub setPort {
  my ($self, $port) = @_;  
  $self->{FUNCTION} = "\"setPort\"";  
  if(defined $port) {
    $self->{PORT} = $port;
  }
  else {
    croak($self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION});
  }
  return;
}


sub setVersion {
  my ($self, $ver) = @_;  
  $self->{FUNCTION} = "\"setVersion\"";  
  if(defined $ver) {
    $self->{VERSION} = $ver;
  }
  else {
    croak($self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION});
  }
  return;
}


sub setCommunity {
  my ($self, $comm) = @_;  
  $self->{FUNCTION} = "\"setCommunity\"";  
  if(defined $comm) {
    $self->{COMMUNITY} = $comm;
  }
  else {
    croak($self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION});
  }
  return;
}


sub setVariables {
  my ($self, $var) = @_;  
  $self->{FUNCTION} = "\"setVariables\""; 
  if(defined $var) {
    my %vars = %{$var};  
    $hash{"VARIABLES"} = \%vars;
  }
  else {
    croak($self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION});
  }
  return;
}


sub setVariable {
  my ($self, $var) = @_;  
  $self->{FUNCTION} = "\"setVariable\""; 
  if(defined $var) {
    $self->{VARIABLES}->{$var} = "";
  }
  else {
    croak($self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION});
  }
  return;
}


sub removeVariables {
  my ($self) = @_;  
  $self->{FUNCTION} = "\"removeVariables\""; 
  undef $self->{VARIABLES};
  if(defined $self->{VARIABLES}) {
    warn($self->{FILENAME}.":\tRemove failure in ".$self->{FUNCTION});
  }
  return;
}


sub removeVariable {
  my ($self, $var) = @_;  
  $self->{FUNCTION} = "\"removeVariable\""; 
  if(defined $var) {
    delete $self->{VARIABLES}->{$var};
  }
  else {
    croak($self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION});
  }
  return;
}


sub setSession {
  my ($self) = @_;
  $self->{FUNCTION} = "\"setSession\"";  
  if(defined $self->{COMMUNITY} && defined $self->{VERSION} && 
     defined $self->{HOST} && defined $self->{PORT}) {

    ($self->{SESSION}, $self->{ERROR}) = Net::SNMP->session(
      -community     => $self->{COMMUNITY},
      -version       => $self->{VERSION},
      -hostname      => $self->{HOST},
      -port          => $self->{PORT}) || 
      warn($self->{FILENAME}.":\tCouldn't open SNMP session to " . $self->{HOST} . " in ".$self->{FUNCTION});

    if(!defined($self->{SESSION})) {
      warn($self->{FILENAME}.":\tSNMP Error: " . $self->{ERROR} . " in ".$self->{FUNCTION});
    }
  }
  else {
    croak($self->{FILENAME}.":\tSession needs 'host', 'version', and 'community' to be set in ".$self->{FUNCTION});
  }  
  return;
}


sub closeSession {
  my ($self) = @_;
  $self->{FUNCTION} = "\"closeSession\"";  
  if(defined $self->{SESSION}) {
    $self->{SESSION}->close;
  }
  return;
}


sub collectVariables {
  my ($self) = @_;
  $self->{FUNCTION} = "\"collectVariables\"";    
  if(defined $self->{SESSION}) {
    my @oids = ();
    foreach my $oid (keys %{$self->{VARIABLES}}) {
      push @oids, $oid;
    }
    $self->{RESULT} = $self->{SESSION}->get_request(
      -varbindlist => \@oids
    );
    if(!defined($self->{RESULT})) {
      warn($self->{FILENAME}.":\tSNMP error in ".$self->{FUNCTION});
      return ('error' => -1);
    }    
    else {
      return %{$self->{RESULT}};
    }
  }
  else {
    warn($self->{FILENAME}.":\tSession to " . $self->{HOST} . " not found in ".$self->{FUNCTION});
      return ('error' => -1);
  }      
}


sub collect {
  my ($self, $var) = @_;
  $self->{FUNCTION} = "\"collect\"";    
  undef $self->{RESULT};
  if(defined $self->{SESSION}) {
    $self->{RESULT} = $self->{SESSION}->get_request(
      -varbindlist => [$var]
    );
    if(!defined($self->{RESULT})) {
      warn($self->{FILENAME}.":\tSNMP error: " . $self->{ERROR} . " in ".$self->{FUNCTION});
      return -1;
    }    
    else {
      return $self->{RESULT}->{$var};
    }
  }
  else {
    warn($self->{FILENAME}.":\tSession to " . $self->{HOST} . " not found in ".$self->{FUNCTION});
    return -1;
  }      
}


1;


__END__
=head1 NAME

Netradar::MP::SNMP - A module that provides methods for polling SNMP data from a resource.

=head1 DESCRIPTION

The purpose of this module is to create simple objects that contain all necessary information
to poll SNMP data from a specific resource.  The objects can then be re-used with minimal 
effort.

=head1 SYNOPSIS

    use Netradar::MP::SNMP;
    
    my %vars = (
      '.1.3.6.1.2.1.2.2.1.10.2' => ""
    );
  
    my $snmp = new Netradar::MP::SNMP(
      "lager", 161, "1", "public",
      \%vars
    );

    # or also:
    # 
    # my $snmp = new Netradar::MP::SNMP;
    # $snmp->setHost("lager");
    # $snmp->setPort(161);
    # $snmp->setVersion("1");
    # $snmp->setCommunity("public");
    # $snmp->setVariables(\%vars);

    $snmp->setSession;

    my $single_result = $snmp->collect(".1.3.6.1.2.1.2.2.1.16.2");

    $snmp->setVariable(".1.3.6.1.2.1.2.2.1.16.2");

    my %results = $snmp->collectVariables;
    foreach my $var (sort keys %results) {
      print $var , "\t-\t" , $results{$var} , "\n"; 
    }

    $snmp->removeVariable(".1.3.6.1.2.1.2.2.1.16.2");

    # to remove ALL variables
    # 
    # $snmp->removeVariables;
    
    $snmp->closeSession;

=head1 DETAILS

The Net::SNMP API is rich with features, and does offer lots of functionality we choose not to re-package
here.  Netradar for the most part is not interested in writing SNMP data, and currently only supports
versions 1 and 2 of the spec.  As such we only provide simple methods that accomplish our goals.  We do
recognize the importance of these other functions, and they may be provided in the future.

=head1 API

The offered API is simple, but offers the key functions we need in a measurement point. 

=head2 new($host, $port, $version, $community, \%variables)

The first argument is a string representing the 'host' from which to collect SNMP data.  The 
second argument is a numerical 'port' number (will default to 161 if unset).  It is also possible
to supply the port number via the host name, as in 'hostname:port'.  The third argument, 'version', 
is a string that represents the version of snmpd that is running on the target host, currently 
this module supports versions 1 and 2 only.  The fourth argument is a string representing the 
'community' that allows snmp reading on the target host.  The final argument is a hash of oids
representing the variables to be polled from the target.  All of these arguments are optional, and
may be set or re-set with the other functions.

=head2 setHost($host)

(Re-)Sets the target host for the SNMP object.

=head2 setPort($port)

(Re-)Sets the port for the target host on the SNMP object.

=head2 setVersion($version)

(Re-)Sets the version of snmpd running on the target host.

=head2 setCommunity($community)

(Re-)Sets the community that snmpd is allowing ot be read on the target host.

=head2 setSession

Establishes a connection to the target host with the supplied information.  It is 
necessary to have the host, community, and version set for this to work; port will 
default to 161 if unset.  If changes are made to any of the above variables, the 
session will need to be re-set from this function

=head2 setVariables(\%variables)

Passes a hash of 'oid' encoded variables to the object; these oids will be used 
when the 'collectVariables' routine is called to gather the proper values.

=head2 setVariable($variable)

Adds $variable to the hash of oids to be collected when the 'collectVariables' 
routine is called.

=head2 removeVariables

Removes all variables from the hash of oids.

=head2 removeVariable($variable)

Removes $variable from the hash of oids to be collected when the 'collectVariables' 
routine is called.

=head2 collectVariables

Collects all variables from the target host that are specified in the hash of oids.  The
results are returned in a hash with keys representing each oid.  Will return -1 
on error.

=head2 collect($variable)

Collects the oid represented in $variable, and returns this value.  Will return -1 
on error.

=head closeSession

Closes the session to the target host.

=head1 SEE ALSO

L<Netradar::Common>, L<Netradar::DB::SQL>, L<Netradar::DB::RRD>, L<Netradar::DB::File>, 
L<Netradar::DB::XMLDB>

To join the 'netradar' mailing list, please visit:

  http://moonshine.pc.cis.udel.edu/mailman/listinfo/netradar

The netradar subversion repository is located at:

  https://damsl.cis.udel.edu/svn/netradar/
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 AUTHOR

Jason Zurawski, E<lt>zurawski@eecis.udel.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2006 by Jason Zurawski

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.
