
#PASTOR: Code generated by XML::Pastor/1.0.3 at 'Wed Jul  1 15:32:04 2009'

use utf8;
use strict;
use warnings;
no warnings qw(uninitialized);

use XML::Pastor;



#================================================================

package OSCARS::Type::mplsInfo;


our @ISA=qw(XML::Pastor::ComplexType);

OSCARS::Type::mplsInfo->mk_accessors( qw(burstLimit lspClass));

OSCARS::Type::mplsInfo->XmlSchemaType( bless( {
                 'attributeInfo' => {},
                 'attributePrefix' => '_',
                 'attributes' => [],
                 'baseClasses' => [
                                    'XML::Pastor::ComplexType'
                                  ],
                 'class' => 'OSCARS::Type::mplsInfo',
                 'contentType' => 'complex',
                 'elementInfo' => {
                                  'burstLimit' => bless( {
                                                         'class' => 'XML::Pastor::Builtin::int',
                                                         'metaClass' => 'OSCARS::Pastor::Meta',
                                                         'name' => 'burstLimit',
                                                         'scope' => 'local',
                                                         'targetNamespace' => 'http://oscars.es.net/OSCARS',
                                                         'type' => 'int|http://www.w3.org/2001/XMLSchema'
                                                       }, 'XML::Pastor::Schema::Element' ),
                                  'lspClass' => bless( {
                                                       'class' => 'XML::Pastor::Builtin::string',
                                                       'maxOccurs' => '1',
                                                       'metaClass' => 'OSCARS::Pastor::Meta',
                                                       'minOccurs' => '0',
                                                       'name' => 'lspClass',
                                                       'scope' => 'local',
                                                       'targetNamespace' => 'http://oscars.es.net/OSCARS',
                                                       'type' => 'string|http://www.w3.org/2001/XMLSchema'
                                                     }, 'XML::Pastor::Schema::Element' )
                                },
                 'elements' => [
                                 'burstLimit',
                                 'lspClass'
                               ],
                 'isRedefinable' => 1,
                 'metaClass' => 'OSCARS::Pastor::Meta',
                 'name' => 'mplsInfo',
                 'scope' => 'global',
                 'targetNamespace' => 'http://oscars.es.net/OSCARS'
               }, 'XML::Pastor::Schema::ComplexType' ) );

1;


__END__



=head1 NAME

B<OSCARS::Type::mplsInfo>  -  A class generated by L<XML::Pastor> . 


=head1 ISA

This class descends from L<XML::Pastor::ComplexType>.


=head1 CODE GENERATION

This module was automatically generated by L<XML::Pastor> version 1.0.3 at 'Wed Jul  1 15:32:04 2009'


=head1 CHILD ELEMENT ACCESSORS

=over

=item B<burstLimit>()      - See L<XML::Pastor::Builtin::int>.

=item B<lspClass>()      - See L<XML::Pastor::Builtin::string>.

=back


=head1 SEE ALSO

L<XML::Pastor::ComplexType>, L<XML::Pastor>, L<XML::Pastor::Type>, L<XML::Pastor::ComplexType>, L<XML::Pastor::SimpleType>


=cut