#!/usr/bin/perl

package perfSONAR_PS::MP::General;
use Carp qw( carp );
use Exporter;  
use perfSONAR_PS::Common;

@ISA = ('Exporter');
@EXPORT = ( 'cleanMetadata', 'removeReferences' );

sub cleanMetadata {
  my($mp) = @_;
  $mp->{FILENAME} = "perfSONAR_PS::MP::General";  
  $mp->{FUNCTION} = "\"cleanMetadata\"";
    
  chainMetadata($mp->{METADATA}); 

  foreach my $m (keys %{$mp->{METADATA}}) {
    my $count = countRefs($m, \%{$mp->{DATA}}, "nmwg:data-metadataIdRef");
    if($count == 0) {
      delete $mp->{METADATA}->{$m};
    } 
    else {
      $mp->{METADATAMARKS}->{$m} = $count;
    }
  }  
  return;
}


sub removeReferences {
  my($mp, $id) = @_;
  $mp->{FILENAME} = "perfSONAR_PS::MP::General";  
  $mp->{FUNCTION} = "\"removeReferences\"";      
  my $remove = countRefs($id, $mp->{METADATA}, "nmwg:metadata-id");
  if($remove > 0) {
    $mp->{METADATAMARKS}->{$id} = $mp->{METADATAMARKS}->{$id} - $remove;
    if($mp->{METADATAMARKS}->{$id} == 0) {
      delete $mp->{METADATAMARKS}->{$id};
      delete $mp->{METADATA}->{$id};
    }     
  }
  return;
}


1;


__END__
=head1 NAME

perfSONAR_PS::MP::General - A module that provides methods for general tasks that MPs need to 
perform, such as creating messages or result code structures.  

=head1 DESCRIPTION

This module is a catch all for common methods (for now) of MPs in the perfSONAR-PS framework.  
As such there is no 'common thread' that each method shares.  This module IS NOT an object, 
and the methods can be invoked directly (and sparingly).  

=head1 SYNOPSIS


    use perfSONAR_PS::MP::General;
    
    my $mp = perfSONAR_PS::MP::...;
    
    # do mp stuff ...
    
    cleanMetadata(\%{$mp}); 
    
    removeReferences(\%{$mp}, $id_value);
    
    
=head1 DETAILS

The API for this module aims to be simple; note that this is not an object and 
each method does not have the 'self knowledge' of variables that may travel 
between functions.  

=head1 API

The offered API is basic for now, until more common features to MPs can be identified
and utilized in this module.

=head2 cleanMetadata($mp)

Chains, and removes unused metadata values from the metadata object located in the 
passed 'MP' object.

=head2 removeReferences($mp, $id)

Removes a value from the an object (data/metadata) located in the passed 'MP' object 
and only if the value is equal to the supplied id. 

=head1 SEE ALSO

L<Carp>, L<Exporter>, L<perfSONAR_PS::Common>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 VERSION

$Id:$

=head1 AUTHOR

Jason Zurawski, E<lt>zurawski@internet2.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Jason Zurawski

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.
