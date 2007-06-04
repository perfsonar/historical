#!/usr/bin/perl

package OwampMA;
use Carp qw( croak );
use Log::Log4perl qw(get_logger);
use Data::Dumper;

use perfSONAR_PS::Common;
use perfSONAR_PS::DB::File;
use perfSONAR_PS::DB::XMLDB;
use perfSONAR_PS::DB::RRD;
use perfSONAR_PS::DB::SQL;
use perfSONAR_PS::MA::General;


@ISA = ('Exporter');
@EXPORT = ();

our $VERSION = '0.02';

sub new {
  my ($package, $conf) = @_; 
  my %hash = ();
  $hash{"FILENAME"} = "OwampMA";
  $hash{"FUNCTION"} = "\"new\"";
  if(defined $conf and $conf ne "") {
    $hash{"CONF"} = \%{$conf};
  }
  bless \%hash => $package;
}


sub setConf {
  my ($self, $conf) = @_;   
  $self->{FUNCTION} = "\"setConf\"";  
  if(defined $conf and $conf ne "") {
    $self->{CONF} = \%{$conf};
  }
  else {
    printError($self->{CONF}->{"LOGFILE"}, $self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION}) 
      if(defined $self->{CONF}->{"LOGFILE"} and $self->{CONF}->{"LOGFILE"} ne "");    
  }
  return;
}


1;


__END__
=head1 NAME

OwampMA - A module starting point for MA functions...

=head1 DESCRIPTION

...  

=head1 SYNOPSIS

    use OwampMA;

    my %conf = ();
    $conf{"METADATA_DB_TYPE"} = "xmldb";
    $conf{"METADATA_DB_NAME"} = "/home/jason/perfSONAR-PS/MP/SNMP/xmldb";
    $conf{"METADATA_DB_FILE"} = "snmpstore.dbxml";
    $conf{"RRDTOOL"} = "/usr/local/rrdtool/bin/rrdtool";
    $conf{"LOGFILE"} = "./log/perfSONAR-PS-error.log";

    my $ma = OwampMA->new(\%conf);
 

=head1 DETAILS

This API is a work in progress, and still does not reflect the general access needed in an MA.
Additional logic is needed to address issues such as different backend storage facilities.  

=head1 API

The offered API is simple, but offers the key functions we need in a measurement archive. 

=head2 new(\%conf)

The only argument represents the 'conf' hash from the calling MA.

=head2 setConf(\%conf)

(Re-)Sets the value for the 'conf' hash. 

=head1 SEE ALSO

L<perfSONAR_PS::Common>, L<perfSONAR_PS::Transport>, L<perfSONAR_PS::DB::SQL>, 
L<perfSONAR_PS::DB::RRD>, L<perfSONAR_PS::DB::File>, L<perfSONAR_PS::DB::XMLDB>, 
L<perfSONAR_PS::MP::SNMP>, L<perfSONAR_PS::MA::General>, L<perfSONAR_PS::MA::SNMP>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 AUTHOR

Jason Zurawski, E<lt>zurawski@eecis.udel.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Jason Zurawski

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.
