package  perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::nmtb::Topology::Domain::Node::Contact;

use strict;
use warnings;
use utf8;
use English qw(-no_match_vars);
use version; our $VERSION = 'v2.0';

=head1 NAME

perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::nmtb::Topology::Domain::Node::Contact  -  this is data binding class for  'contact'  element from the XML schema namespace nmtb

=head1 DESCRIPTION

Object representation of the contact element of the nmtb XML namespace.
Object fields are:


    Object reference:   email => type ,
    Object reference:   phoneNumber => type ,
    Object reference:   administrator => type ,
    Object reference:   institution => type ,


The constructor accepts only single parameter, it could be a hashref with keyd  parameters hash  or DOM of the  'contact' element
Alternative way to create this object is to pass hashref to this hash: { xml => <xml string> }
Please remember that namespace prefix is used as namespace id for mapping which not how it was intended by XML standard. The consequence of that
is if you serve some XML on one end of the webservices pipeline then the same namespace prefixes MUST be used on the one for the same namespace URNs.
This constraint can be fixed in the future releases.

Note: this class utilizes L<Log::Log4perl> module, see corresponded docs on CPAN.

=head1 SYNOPSIS

          use perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::nmtb::Topology::Domain::Node::Contact;
          use Log::Log4perl qw(:easy);

          Log::Log4perl->easy_init();

          my $el =  perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::nmtb::Topology::Domain::Node::Contact->new($DOM_Obj);

          my $xml_string = $el->asString();

          my $el2 = perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::nmtb::Topology::Domain::Node::Contact->new({xml => $xml_string});


          see more available methods below


=head1   METHODS

=cut


use XML::LibXML;
use Scalar::Util qw(blessed);
use Log::Log4perl qw(get_logger);
use Readonly;
    
use perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::Element qw(getElement);
use perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::NSMap;
use fields qw(nsmap idmap LOGGER   email phoneNumber administrator institution);


=head2 new({})

 creates   object, accepts DOM with element's tree or hashref to the list of
 keyd parameters:


returns: $self

=cut

Readonly::Scalar our $COLUMN_SEPARATOR => ':';
Readonly::Scalar our $CLASSPATH =>  'perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::nmtb::Topology::Domain::Node::Contact';
Readonly::Scalar our $LOCALNAME => 'contact';

sub new {
    my ($that, $param) = @_;
    my $class = ref($that) || $that;
    my $self =  fields::new($class );
    $self->set_LOGGER(get_logger( $CLASSPATH ));
    $self->set_nsmap(perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::NSMap->new());
    $self->get_nsmap->mapname($LOCALNAME, 'nmtb');


    if($param) {
        if(blessed $param && $param->can('getName')  && ($param->getName =~ m/$LOCALNAME$/xm) ) {
            return  $self->fromDOM($param);
        } elsif(ref($param) ne 'HASH')   {
            $self->get_LOGGER->logdie("ONLY hash ref accepted as param " . $param );
            return;
        }
        if($param->{xml}) {
            my $parser = XML::LibXML->new();
            my $dom;
            eval {
                my $doc = $parser->parse_string($param->{xml});
                $dom = $doc->getDocumentElement;
            };
            if($EVAL_ERROR) {
                $self->get_LOGGER->logdie(" Failed to parse XML :" . $param->{xml} . " \n ERROR: \n" . $EVAL_ERROR);
                return;
            }
            return  $self->fromDOM($dom);
        }
        $self->get_LOGGER->debug("Parsing parameters: " . (join ' : ', keys %{$param}));


        foreach my $param_key (keys %{$param}) {
            $self->{$param_key} = $param->{$param_key} if $self->can("get_$param_key");
        }
        $self->get_LOGGER->debug("Done");
    }
    return $self;
}

=head2   getDOM ($parent)

 accepts parent DOM  serializes current object into the DOM, attaches it to the parent DOM tree and
 returns contact object DOM

=cut

sub getDOM {
    my ($self, $parent) = @_;
    my $contact;
    eval { 
        my @nss;    
        unless($parent) {
            my $nsses = $self->registerNamespaces(); 
            @nss = map {$_  if($_ && $_  ne  $self->get_nsmap->mapname( $LOCALNAME ))}  keys %{$nsses};
            push(@nss,  $self->get_nsmap->mapname( $LOCALNAME ));
        } 
        push  @nss, $self->get_nsmap->mapname( $LOCALNAME ) unless  @nss;
        $contact = getElement({name =>   $LOCALNAME, 
	                      parent => $parent,
			      ns  =>    \@nss,
                              attributes => [

                                               ],
                               });
        };
    if($EVAL_ERROR) {
         $self->get_LOGGER->logdie(" Failed at creating DOM: $EVAL_ERROR");
    }


    foreach my $textnode (qw/email phoneNumber administrator institution/) {
        if($self->{$textnode}) {
            my  $domtext  =  getElement({name => $textnode,
                                          parent => $contact,
                                          ns => [$self->get_nsmap->mapname($LOCALNAME)],
                                         text => $self->{$textnode},
                              });
           $domtext?$contact->appendChild($domtext):$self->get_LOGGER->logdie("Failed to append new text element $textnode  to  contact");
        }
    }
        
      return $contact;
}


=head2 get_LOGGER

 accessor  for LOGGER, assumes hash based class

=cut

sub get_LOGGER {
    my($self) = @_;
    return $self->{LOGGER};
}

=head2 set_LOGGER

mutator for LOGGER, assumes hash based class

=cut

sub set_LOGGER {
    my($self,$value) = @_;
    if($value) {
        $self->{LOGGER} = $value;
    }
    return   $self->{LOGGER};
}



=head2 get_nsmap

 accessor  for nsmap, assumes hash based class

=cut

sub get_nsmap {
    my($self) = @_;
    return $self->{nsmap};
}

=head2 set_nsmap

mutator for nsmap, assumes hash based class

=cut

sub set_nsmap {
    my($self,$value) = @_;
    if($value) {
        $self->{nsmap} = $value;
    }
    return   $self->{nsmap};
}



=head2 get_idmap

 accessor  for idmap, assumes hash based class

=cut

sub get_idmap {
    my($self) = @_;
    return $self->{idmap};
}

=head2 set_idmap

mutator for idmap, assumes hash based class

=cut

sub set_idmap {
    my($self,$value) = @_;
    if($value) {
        $self->{idmap} = $value;
    }
    return   $self->{idmap};
}



=head2 get_text

 accessor  for text, assumes hash based class

=cut

sub get_text {
    my($self) = @_;
    return $self->{text};
}

=head2 set_text

mutator for text, assumes hash based class

=cut

sub set_text {
    my($self,$value) = @_;
    if($value) {
        $self->{text} = $value;
    }
    return   $self->{text};
}



=head2 get_email

 accessor  for email, assumes hash based class

=cut

sub get_email {
    my($self) = @_;
    return $self->{email};
}

=head2 set_email

mutator for email, assumes hash based class

=cut

sub set_email {
    my($self,$value) = @_;
    if($value) {
        $self->{email} = $value;
    }
    return   $self->{email};
}



=head2 get_phoneNumber

 accessor  for phoneNumber, assumes hash based class

=cut

sub get_phoneNumber {
    my($self) = @_;
    return $self->{phoneNumber};
}

=head2 set_phoneNumber

mutator for phoneNumber, assumes hash based class

=cut

sub set_phoneNumber {
    my($self,$value) = @_;
    if($value) {
        $self->{phoneNumber} = $value;
    }
    return   $self->{phoneNumber};
}



=head2 get_administrator

 accessor  for administrator, assumes hash based class

=cut

sub get_administrator {
    my($self) = @_;
    return $self->{administrator};
}

=head2 set_administrator

mutator for administrator, assumes hash based class

=cut

sub set_administrator {
    my($self,$value) = @_;
    if($value) {
        $self->{administrator} = $value;
    }
    return   $self->{administrator};
}



=head2 get_institution

 accessor  for institution, assumes hash based class

=cut

sub get_institution {
    my($self) = @_;
    return $self->{institution};
}

=head2 set_institution

mutator for institution, assumes hash based class

=cut

sub set_institution {
    my($self,$value) = @_;
    if($value) {
        $self->{institution} = $value;
    }
    return   $self->{institution};
}



=head2  querySQL ()

 depending on SQL mapping declaration it will return some hash ref  to the  declared fields
 for example querySQL ()
 
 Accepts one optional parameter - query hashref, it will fill this hashref
 
 will return:
    
    { <table_name1> =>  {<field name1> => <value>, ...},...}

=cut

sub  querySQL {
    my ($self, $query) = @_;

    return $query;
}



=head2  buildIdMap()

 if any of subelements has id then get a map of it in form of
 hashref to { element}{id} = index in array and store in the idmap field

=cut

sub  buildIdMap {
    my $self = shift;
    my %map = ();
    
    return;
}

=head2  asString()

 shortcut to get DOM and convert into the XML string
 returns nicely formatted XML string  representation of the  contact object

=cut

sub asString {
    my $self = shift;
    my $dom = $self->getDOM();
    return $dom->toString('1');
}

=head2 registerNamespaces ()

 will parse all subelements
 returns reference to hash with namespace prefixes
 
 most parsers are expecting to see namespace registration info in the document root element declaration

=cut

sub registerNamespaces {
    my ($self, $nsids) = @_;

    my $local_nss = {reverse %{$self->get_nsmap->mapname}};
    unless($nsids) {
        $nsids = $local_nss;
    }  else {
        %{$nsids} = (%{$local_nss}, %{$nsids});
    }

    return $nsids;
}


=head2  fromDOM ($)

 accepts parent XML DOM  element  tree as parameter
 returns contact  object

=cut

sub fromDOM {
    my ($self, $dom) = @_;

    foreach my $childnode ($dom->childNodes) {
        my  $getname  = $childnode->getName;
        my ($nsid, $tagname) = split $COLUMN_SEPARATOR, $getname;
        next unless($nsid && $tagname);
	my $element;
	
      if ($childnode->textContent && $self->can("get_$tagname")) {
            $self->{$tagname} =  $childnode->textContent; ## text node
        }
    }
    $self->buildIdMap;
    $self->registerNamespaces;
    return $self;
}


1;

__END__


=head1  SEE ALSO

Automatically generated by L<XML::RelaxNG::Compact::PXB> 

=head1 AUTHOR

Maxim Grigoriev

=head1 COPYRIGHT

Copyright (c) 2008, Fermi Research Alliance (FRA)

=head1 LICENSE

You should have received a copy of the Fermitool license along with this software.

=cut


