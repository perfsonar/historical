package  perfSONAR_PS::SONAR_DATATYPES::v2_0::nmwg::Message::Data;

use strict;
use warnings;
use utf8;
use English qw(-no_match_vars);
use version; our $VERSION = 'v2.0';

=head1 NAME

perfSONAR_PS::SONAR_DATATYPES::v2_0::nmwg::Message::Data  -  this is data binding class for  'data'  element from the XML schema namespace nmwg

=head1 DESCRIPTION

Object representation of the data element of the nmwg XML namespace.
Object fields are:


    Scalar:     metadataIdRef,
    Scalar:     id,
    Object reference:   commonTime => type ARRAY,
    Object reference:   datum => type ARRAY,
    Object reference:   key => type HASH,


The constructor accepts only single parameter, it could be a hashref with keyd  parameters hash  or DOM of the  'data' element
Alternative way to create this object is to pass hashref to this hash: { xml => <xml string> }
Please remember that namespace prefix is used as namespace id for mapping which not how it was intended by XML standard. The consequence of that
is if you serve some XML on one end of the webservices pipeline then the same namespace prefixes MUST be used on the one for the same namespace URNs.
This constraint can be fixed in the future releases.

Note: this class utilizes L<Log::Log4perl> module, see corresponded docs on CPAN.

=head1 SYNOPSIS

          use perfSONAR_PS::SONAR_DATATYPES::v2_0::nmwg::Message::Data;
          use Log::Log4perl qw(:easy);

          Log::Log4perl->easy_init();

          my $el =  perfSONAR_PS::SONAR_DATATYPES::v2_0::nmwg::Message::Data->new($DOM_Obj);

          my $xml_string = $el->asString();

          my $el2 = perfSONAR_PS::SONAR_DATATYPES::v2_0::nmwg::Message::Data->new({xml => $xml_string});


          see more available methods below


=head1   METHODS

=cut


use XML::LibXML;
use Scalar::Util qw(blessed);
use Log::Log4perl qw(get_logger);
use Readonly;
    
use perfSONAR_PS::SONAR_DATATYPES::v2_0::Element qw(getElement);
use perfSONAR_PS::SONAR_DATATYPES::v2_0::NSMap;
use perfSONAR_PS::SONAR_DATATYPES::v2_0::nmwg::Message::Data::CommonTime;
use perfSONAR_PS::SONAR_DATATYPES::v2_0::nmwgr::Message::Data::Datum;
use perfSONAR_PS::SONAR_DATATYPES::v2_0::ifevt::Message::Data::Datum;
use perfSONAR_PS::SONAR_DATATYPES::v2_0::pinger::Message::Data::Datum;
use perfSONAR_PS::SONAR_DATATYPES::v2_0::nmwg::Message::Data::Key;
use fields qw(nsmap idmap LOGGER metadataIdRef id commonTime datum key );


=head2 new({})

 creates   object, accepts DOM with element's tree or hashref to the list of
 keyd parameters:

         metadataIdRef   => undef,
         id   => undef,
         commonTime => ARRAY,
         datum => ARRAY,
         key => HASH,

returns: $self

=cut

Readonly::Scalar our $COLUMN_SEPARATOR => ':';
Readonly::Scalar our $CLASSPATH =>  'perfSONAR_PS::SONAR_DATATYPES::v2_0::nmwg::Message::Data';
Readonly::Scalar our $LOCALNAME => 'data';

sub new {
    my ($that, $param) = @_;
    my $class = ref($that) || $that;
    my $self =  fields::new($class );
    $self->set_LOGGER(get_logger( $CLASSPATH ));
    $self->set_nsmap(perfSONAR_PS::SONAR_DATATYPES::v2_0::NSMap->new());
    $self->get_nsmap->mapname($LOCALNAME, 'nmwg');


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
 returns data object DOM

=cut

sub getDOM {
    my ($self, $parent) = @_;
    my $data;
    eval { 
        my @nss;    
        unless($parent) {
            my $nsses = $self->registerNamespaces(); 
            @nss = map {$_  if($_ && $_  ne  $self->get_nsmap->mapname( $LOCALNAME ))}  keys %{$nsses};
            push(@nss,  $self->get_nsmap->mapname( $LOCALNAME ));
        } 
        push  @nss, $self->get_nsmap->mapname( $LOCALNAME ) unless  @nss;
        $data = getElement({name =>   $LOCALNAME, 
	                      parent => $parent,
			      ns  =>    \@nss,
                              attributes => [

                                                     ['metadataIdRef' =>  $self->get_metadataIdRef],

                                                     ['id' =>  $self->get_id],

                                               ],
                               });
        };
    if($EVAL_ERROR) {
         $self->get_LOGGER->logdie(" Failed at creating DOM: $EVAL_ERROR");
    }

    if($self->get_commonTime && ref($self->get_commonTime) eq 'ARRAY') {
        foreach my $subel (@{$self->get_commonTime}) {
            if(blessed $subel && $subel->can("getDOM")) {
                my $subDOM = $subel->getDOM($data);
                $subDOM?$data->appendChild($subDOM):$self->get_LOGGER->logdie("Failed to append  commonTime element  with value:" .  $subDOM->toString);
            }
        }
    }


    if(!($self->get_commonTime) && $self->get_datum && ref($self->get_datum) eq 'ARRAY') {
        foreach my $subel (@{$self->get_datum}) {
            if(blessed $subel && $subel->can("getDOM")) {
                my $subDOM = $subel->getDOM($data);
                $subDOM?$data->appendChild($subDOM):$self->get_LOGGER->logdie("Failed to append  datum element  with value:" .  $subDOM->toString);
            }
        }
    }


    if(!($self->get_commonTime && $self->get_datum) && $self->get_key && blessed $self->get_key && $self->get_key->can("getDOM")) {
        my $keyDOM = $self->get_key->getDOM($data);
        $keyDOM?$data->appendChild($keyDOM):$self->get_LOGGER->logdie("Failed to append  key element with value:" .  $keyDOM->toString);
    }

      return $data;
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



=head2 get_metadataIdRef

 accessor  for metadataIdRef, assumes hash based class

=cut

sub get_metadataIdRef {
    my($self) = @_;
    return $self->{metadataIdRef};
}

=head2 set_metadataIdRef

mutator for metadataIdRef, assumes hash based class

=cut

sub set_metadataIdRef {
    my($self,$value) = @_;
    if($value) {
        $self->{metadataIdRef} = $value;
    }
    return   $self->{metadataIdRef};
}



=head2 get_id

 accessor  for id, assumes hash based class

=cut

sub get_id {
    my($self) = @_;
    return $self->{id};
}

=head2 set_id

mutator for id, assumes hash based class

=cut

sub set_id {
    my($self,$value) = @_;
    if($value) {
        $self->{id} = $value;
    }
    return   $self->{id};
}



=head2 get_commonTime

 accessor  for commonTime, assumes hash based class

=cut

sub get_commonTime {
    my($self) = @_;
    return $self->{commonTime};
}

=head2 set_commonTime

mutator for commonTime, assumes hash based class

=cut

sub set_commonTime {
    my($self,$value) = @_;
    if($value) {
        $self->{commonTime} = $value;
    }
    return   $self->{commonTime};
}



=head2 get_datum

 accessor  for datum, assumes hash based class

=cut

sub get_datum {
    my($self) = @_;
    return $self->{datum};
}

=head2 set_datum

mutator for datum, assumes hash based class

=cut

sub set_datum {
    my($self,$value) = @_;
    if($value) {
        $self->{datum} = $value;
    }
    return   $self->{datum};
}



=head2 get_key

 accessor  for key, assumes hash based class

=cut

sub get_key {
    my($self) = @_;
    return $self->{key};
}

=head2 set_key

mutator for key, assumes hash based class

=cut

sub set_key {
    my($self,$value) = @_;
    if($value) {
        $self->{key} = $value;
    }
    return   $self->{key};
}




=head2  addCommonTime()

 if any of subelements can be an array then this method will provide
 facility to add another element to the  array and will return ref to such array
 or just set the element to a new one, if element has and 'id' attribute then it will
 create idmap  
 
 Accepts:  obj
 Returns: arrayref of objects

=cut

sub addCommonTime {
    my ($self,$new) = @_;

    $self->get_commonTime && ref($self->get_commonTime) eq 'ARRAY'?push @{$self->get_commonTime}, $new:$self->set_commonTime([$new]);
    $self->get_LOGGER->debug("Added new to commonTime");
    $self->buildIdMap; ## rebuild index map
    return $self->get_commonTime;
}

=head2  removeCommonTimeById()

 removes specific element from the array of commonTime elements by id ( if id is supported by this element )
 Accepts:  single param - id - which is id attribute of the element
 
 if there is no array then it will return undef and warning
 if it removed some id then $id will be returned

=cut

sub removeCommonTimeById {
    my ($self, $id) = @_;
    if(ref($self->get_commonTime) eq 'ARRAY' && $self->get_idmap->{commonTime} &&  exists $self->get_idmap->{commonTime}{$id}) {
        undef $self->get_commonTime->[$self->get_idmap->{commonTime}{$id}];
        my @tmp =  grep { defined $_ } @{$self->commonTime};
        $self->set_commonTime([@tmp]);
        $self->buildIdMap; ## rebuild index map
        return $id;
    } elsif(!ref($self->get_commonTime)  || ref($self->get_commonTime) ne 'ARRAY')  {
        $self->get_LOGGER->warn("Failed to remove  element because commonTime not an array for non-existent id:$id");
    } else {
        $self->get_LOGGER->warn("Failed to remove element for non-existent id:$id");
    }
    return;
}

=head2  getCommonTimeById()

 get specific element from the array of commonTime elements by id ( if id is supported by this element )
 Accepts single param - id
 
 if there is no array then it will return just an object

=cut

sub getCommonTimeById {
    my ($self, $id) = @_;

    if(ref($self->get_commonTime) eq 'ARRAY' && $self->get_idmap->{commonTime} && exists $self->get_idmap->{commonTime}{$id} ) {
        return $self->get_commonTime->[$self->get_idmap->{commonTime}{$id}];
    } elsif(!ref($self->get_commonTime) || ref($self->get_commonTime) ne 'ARRAY')  {
        return $self->get_commonTime;
    }
    $self->get_LOGGER->warn("Requested element for non-existent id:$id");
    return;
}
            



=head2  addDatum()

 if any of subelements can be an array then this method will provide
 facility to add another element to the  array and will return ref to such array
 or just set the element to a new one, if element has and 'id' attribute then it will
 create idmap  
 
 Accepts:  obj
 Returns: arrayref of objects

=cut

sub addDatum {
    my ($self,$new) = @_;

    $self->get_datum && ref($self->get_datum) eq 'ARRAY'?push @{$self->get_datum}, $new:$self->set_datum([$new]);
    $self->get_LOGGER->debug("Added new to datum");
    $self->buildIdMap; ## rebuild index map
    return $self->get_datum;
}

=head2  removeDatumById()

 removes specific element from the array of datum elements by id ( if id is supported by this element )
 Accepts:  single param - id - which is id attribute of the element
 
 if there is no array then it will return undef and warning
 if it removed some id then $id will be returned

=cut

sub removeDatumById {
    my ($self, $id) = @_;
    if(ref($self->get_datum) eq 'ARRAY' && $self->get_idmap->{datum} &&  exists $self->get_idmap->{datum}{$id}) {
        undef $self->get_datum->[$self->get_idmap->{datum}{$id}];
        my @tmp =  grep { defined $_ } @{$self->datum};
        $self->set_datum([@tmp]);
        $self->buildIdMap; ## rebuild index map
        return $id;
    } elsif(!ref($self->get_datum)  || ref($self->get_datum) ne 'ARRAY')  {
        $self->get_LOGGER->warn("Failed to remove  element because datum not an array for non-existent id:$id");
    } else {
        $self->get_LOGGER->warn("Failed to remove element for non-existent id:$id");
    }
    return;
}

=head2  getDatumById()

 get specific element from the array of datum elements by id ( if id is supported by this element )
 Accepts single param - id
 
 if there is no array then it will return just an object

=cut

sub getDatumById {
    my ($self, $id) = @_;

    if(ref($self->get_datum) eq 'ARRAY' && $self->get_idmap->{datum} && exists $self->get_idmap->{datum}{$id} ) {
        return $self->get_datum->[$self->get_idmap->{datum}{$id}];
    } elsif(!ref($self->get_datum) || ref($self->get_datum) ne 'ARRAY')  {
        return $self->get_datum;
    }
    $self->get_LOGGER->warn("Requested element for non-existent id:$id");
    return;
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


    foreach my $subname (qw/commonTime datum key/) {
        if($self->{$subname} && (ref($self->{$subname}) eq 'ARRAY' ||  blessed $self->{$subname})) {
            my @array = ref($self->{$subname}) eq 'ARRAY'?@{$self->{$subname}}:($self->{$subname});
            foreach my $el (@array) {
                if(blessed $el && $el->can('querySQL'))  {
                    $el->querySQL($query);
                    $self->get_LOGGER->debug("Querying data  for subclass $subname");
                } else {
                    $self->get_LOGGER->logdie("Failed for data Unblessed member or querySQL is not implemented by subclass $subname");
                }
           }
        }
    }
         
    return $query;
}



=head2  buildIdMap()

 if any of subelements has id then get a map of it in form of
 hashref to { element}{id} = index in array and store in the idmap field

=cut

sub  buildIdMap {
    my $self = shift;
    my %map = ();
    

    foreach my $field (qw/commonTime datum key/) {
        my @array = ref($self->{$field}) eq 'ARRAY'?@{$self->{$field}}:($self->{$field});
        my $i = 0;
        foreach my $el (@array)  {
            if($el && blessed $el && $el->can('get_id') &&  $el->get_id)  {
                $map{$field}{$el->get_id} = $i;
            }
            $i++;
        }
    }
    return $self->set_idmap(\%map);
        
}

=head2  asString()

 shortcut to get DOM and convert into the XML string
 returns nicely formatted XML string  representation of the  data object

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


    foreach my $field (qw/commonTime datum key/) {
        my @array = ref($self->{$field}) eq 'ARRAY'?@{$self->{$field}}:($self->{$field});
        foreach my $el (@array) {
            if(blessed $el &&  $el->can('registerNamespaces') ) {
                my $fromNSmap = $el->registerNamespaces($nsids);
                my %ns_idmap = %{$fromNSmap};
                foreach my $ns (keys %ns_idmap)  {
                    $nsids->{$ns}++;
                }
            }
        }
    }

    return $nsids;
}


=head2  fromDOM ($)

 accepts parent XML DOM  element  tree as parameter
 returns data  object

=cut

sub fromDOM {
    my ($self, $dom) = @_;

    $self->set_metadataIdRef($dom->getAttribute('metadataIdRef')) if($dom->getAttribute('metadataIdRef'));

    $self->get_LOGGER->debug(" Attribute metadataIdRef= ". $self->get_metadataIdRef) if $self->get_metadataIdRef;
    $self->set_id($dom->getAttribute('id')) if($dom->getAttribute('id'));

    $self->get_LOGGER->debug(" Attribute id= ". $self->get_id) if $self->get_id;
    foreach my $childnode ($dom->childNodes) {
        my  $getname  = $childnode->getName;
        my ($nsid, $tagname) = split $COLUMN_SEPARATOR, $getname;
        next unless($nsid && $tagname);
	my $element;
	
        if ($tagname eq  'commonTime' && $nsid eq 'nmwg' && $self->can("get_$tagname")) {
                eval {
                    $element = perfSONAR_PS::SONAR_DATATYPES::v2_0::nmwg::Message::Data::CommonTime->new($childnode)
                };
                if($EVAL_ERROR || !($element  && blessed $element)) {
                    $self->get_LOGGER->logdie(" Failed to load and add  CommonTime : " . $dom->toString . " error: " . $EVAL_ERROR);
                     return;
                }
               ($self->get_commonTime && ref($self->get_commonTime) eq 'ARRAY')?push @{$self->get_commonTime}, $element:
                                                                                                        $self->set_commonTime([$element]);; ### add another commonTime  
            } 
        elsif (!($self->get_commonTime) && $tagname eq  'datum' && $nsid eq 'nmwgr' && $self->can("get_$tagname")) {
                eval {
                    $element = perfSONAR_PS::SONAR_DATATYPES::v2_0::nmwgr::Message::Data::Datum->new($childnode)
                };
                if($EVAL_ERROR || !($element  && blessed $element)) {
                    $self->get_LOGGER->logdie(" Failed to load and add  Datum : " . $dom->toString . " error: " . $EVAL_ERROR);
                     return;
                }
               ($self->get_datum && ref($self->get_datum) eq 'ARRAY')?push @{$self->get_datum}, $element:
                                                                                                        $self->set_datum([$element]);; ### add another datum  
            } 
        elsif (!($self->get_commonTime) && $tagname eq  'datum' && $nsid eq 'pinger' && $self->can("get_$tagname")) {
                eval {
                    $element = perfSONAR_PS::SONAR_DATATYPES::v2_0::pinger::Message::Data::Datum->new($childnode)
                };
                if($EVAL_ERROR || !($element  && blessed $element)) {
                    $self->get_LOGGER->logdie(" Failed to load and add  Datum : " . $dom->toString . " error: " . $EVAL_ERROR);
                     return;
                }
               ($self->get_datum && ref($self->get_datum) eq 'ARRAY')?push @{$self->get_datum}, $element:
                                                                                                        $self->set_datum([$element]);; ### add another datum  
            } 
        elsif (!($self->get_commonTime) && $tagname eq  'datum' && $nsid eq 'ifevt' && $self->can("get_$tagname")) {
                eval {
                    $element = perfSONAR_PS::SONAR_DATATYPES::v2_0::ifevt::Message::Data::Datum->new($childnode)
                };
                if($EVAL_ERROR || !($element  && blessed $element)) {
                    $self->get_LOGGER->logdie(" Failed to load and add  Datum : " . $dom->toString . " error: " . $EVAL_ERROR);
                     return;
                }
               ($self->get_datum && ref($self->get_datum) eq 'ARRAY')?push @{$self->get_datum}, $element:
                                                                                                        $self->set_datum([$element]);; ### add another datum  
            } 
        elsif (!($self->get_commonTime && $self->get_datum) && $tagname eq  'key' && $nsid eq 'nmwg' && $self->can("get_$tagname")) {
                eval {
                    $element = perfSONAR_PS::SONAR_DATATYPES::v2_0::nmwg::Message::Data::Key->new($childnode)
                };
                if($EVAL_ERROR || !($element  && blessed $element)) {
                    $self->get_LOGGER->logdie(" Failed to load and add  Key : " . $dom->toString . " error: " . $EVAL_ERROR);
                     return;
                }
              $self->set_key($element); ### add another key  
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


