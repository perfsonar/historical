package  perfSONAR_PS::FT_DATATYPES::v1_0::nmwg::Message::Parameters::Parameter;

use strict;
use warnings;
use utf8;
use English qw(-no_match_vars);
use version; our $VERSION = 'v1.0';

=head1 NAME

perfSONAR_PS::FT_DATATYPES::v1_0::nmwg::Message::Parameters::Parameter  -  this is data binding class for  'parameter'  element from the XML schema namespace nmwg

=head1 DESCRIPTION

Object representation of the parameter element of the nmwg XML namespace.
Object fields are:


    Scalar:     value,
    Scalar:     name,


The constructor accepts only single parameter, it could be a hashref with keyd  parameters hash  or DOM of the  'parameter' element
Alternative way to create this object is to pass hashref to this hash: { xml => <xml string> }
Please remember that namespace prefix is used as namespace id for mapping which not how it was intended by XML standard. The consequence of that
is if you serve some XML on one end of the webservices pipeline then the same namespace prefixes MUST be used on the one for the same namespace URNs.
This constraint can be fixed in the future releases.

Note: this class utilizes L<Log::Log4perl> module, see corresponded docs on CPAN.

=head1 SYNOPSIS

          use perfSONAR_PS::FT_DATATYPES::v1_0::nmwg::Message::Parameters::Parameter;
          use Log::Log4perl qw(:easy);

          Log::Log4perl->easy_init();

          my $el =  perfSONAR_PS::FT_DATATYPES::v1_0::nmwg::Message::Parameters::Parameter->new($DOM_Obj);

          my $xml_string = $el->asString();

          my $el2 = perfSONAR_PS::FT_DATATYPES::v1_0::nmwg::Message::Parameters::Parameter->new({xml => $xml_string});


          see more available methods below


=head1   METHODS

=cut


use XML::LibXML;
use Scalar::Util qw(blessed);
use Log::Log4perl qw(get_logger);
use Readonly;
    
use perfSONAR_PS::FT_DATATYPES::v1_0::Element qw(getElement);
use perfSONAR_PS::FT_DATATYPES::v1_0::NSMap;
use fields qw(nsmap idmap LOGGER value name   text );


=head2 new({})

 creates   object, accepts DOM with element's tree or hashref to the list of
 keyed parameters:

         value   => undef,
         name   => undef,
 text => 'text'

returns: $self

=cut

Readonly::Scalar our $COLUMN_SEPARATOR => ':';
Readonly::Scalar our $CLASSPATH =>  'perfSONAR_PS::FT_DATATYPES::v1_0::nmwg::Message::Parameters::Parameter';
Readonly::Scalar our $LOCALNAME => 'parameter';

sub new {
    my ($that, $param) = @_;
    my $class = ref($that) || $that;
    my $self =  fields::new($class );
    $self->set_LOGGER(get_logger($CLASSPATH));
    $self->set_nsmap(perfSONAR_PS::FT_DATATYPES::v1_0::NSMap->new());
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
	    $parser->expand_xinclude(1);
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
 returns parameter object DOM

=cut

sub getDOM {
    my ($self, $parent) = @_;
    my $parameter;
    eval { 
        my @nss;    
        unless($parent) {
            my $nsses = $self->registerNamespaces(); 
            @nss = map {$_  if($_ && $_  ne  $self->get_nsmap->mapname( $LOCALNAME ))}  keys %{$nsses};
            push(@nss,  $self->get_nsmap->mapname( $LOCALNAME ));
        } 
        push  @nss, $self->get_nsmap->mapname( $LOCALNAME ) unless  @nss;
        $parameter = getElement({name =>   $LOCALNAME, 
	                      parent => $parent,
			      ns  =>    \@nss,
                              attributes => [

                                                     ['value' =>  $self->get_value],

                                           ['name' =>  (($self->get_name    =~ m/(user|streams|srcpath|destpath|program|stripes|buffersize|blocksize|startTime|endTime|setLimit)$/)?$self->get_name:undef)],

                                               ],
                                            'text' => (!($self->get_value)?$self->get_text:undef),

                               });
        };
    if($EVAL_ERROR) {
         $self->get_LOGGER->logdie(" Failed at creating DOM: $EVAL_ERROR");
    }
      return $parameter;
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



=head2 get_value

 accessor  for value, assumes hash based class

=cut

sub get_value {
    my($self) = @_;
    return $self->{value};
}

=head2 set_value

mutator for value, assumes hash based class

=cut

sub set_value {
    my($self,$value) = @_;
    if($value) {
        $self->{value} = $value;
    }
    return   $self->{value};
}



=head2 get_name

 accessor  for name, assumes hash based class

=cut

sub get_name {
    my($self) = @_;
    return $self->{name};
}

=head2 set_name

mutator for name, assumes hash based class

=cut

sub set_name {
    my($self,$value) = @_;
    if($value) {
        $self->{name} = $value;
    }
    return   $self->{name};
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

     my %defined_table = ( 'time' => [   'end',    'start',  ],  'limit' => [   'setLimit',  ],  'Metadata' => [   'Program',    'Stripes',    'DestPath',    'Streams',    'BufferSize',    'SrcPath',    'User',    'BlockSize',  ],  );
     $query->{time}{start}= [ 'perfSONAR_PS::FT_DATATYPES::v1_0::nmwg::Message::Parameters::Parameter' ] if!(defined $query->{time}{start}) || ref($query->{time}{start});
     $query->{time}{end}= [ 'perfSONAR_PS::FT_DATATYPES::v1_0::nmwg::Message::Parameters::Parameter' ] if!(defined $query->{time}{end}) || ref($query->{time}{end});
     $query->{limit}{setLimit}= [ 'perfSONAR_PS::FT_DATATYPES::v1_0::nmwg::Message::Parameters::Parameter' ] if!(defined $query->{limit}{setLimit}) || ref($query->{limit}{setLimit});
     $query->{Metadata}{Program}= [ 'perfSONAR_PS::FT_DATATYPES::v1_0::nmwg::Message::Parameters::Parameter' ] if!(defined $query->{Metadata}{Program}) || ref($query->{Metadata}{Program});
     $query->{Metadata}{Stripes}= [ 'perfSONAR_PS::FT_DATATYPES::v1_0::nmwg::Message::Parameters::Parameter' ] if!(defined $query->{Metadata}{Stripes}) || ref($query->{Metadata}{Stripes});
     $query->{Metadata}{Streams}= [ 'perfSONAR_PS::FT_DATATYPES::v1_0::nmwg::Message::Parameters::Parameter' ] if!(defined $query->{Metadata}{Streams}) || ref($query->{Metadata}{Streams});
     $query->{Metadata}{DestPath}= [ 'perfSONAR_PS::FT_DATATYPES::v1_0::nmwg::Message::Parameters::Parameter' ] if!(defined $query->{Metadata}{DestPath}) || ref($query->{Metadata}{DestPath});
     $query->{Metadata}{User}= [ 'perfSONAR_PS::FT_DATATYPES::v1_0::nmwg::Message::Parameters::Parameter' ] if!(defined $query->{Metadata}{User}) || ref($query->{Metadata}{User});
     $query->{Metadata}{SrcPath}= [ 'perfSONAR_PS::FT_DATATYPES::v1_0::nmwg::Message::Parameters::Parameter' ] if!(defined $query->{Metadata}{SrcPath}) || ref($query->{Metadata}{SrcPath});
     $query->{Metadata}{BufferSize}= [ 'perfSONAR_PS::FT_DATATYPES::v1_0::nmwg::Message::Parameters::Parameter' ] if!(defined $query->{Metadata}{BufferSize}) || ref($query->{Metadata}{BufferSize});
     $query->{Metadata}{BlockSize}= [ 'perfSONAR_PS::FT_DATATYPES::v1_0::nmwg::Message::Parameters::Parameter' ] if!(defined $query->{Metadata}{BlockSize}) || ref($query->{Metadata}{BlockSize});
     $query->{time}{start}= [ 'perfSONAR_PS::FT_DATATYPES::v1_0::nmwg::Message::Parameters::Parameter' ] if!(defined $query->{time}{start}) || ref($query->{time}{start});
     $query->{time}{end}= [ 'perfSONAR_PS::FT_DATATYPES::v1_0::nmwg::Message::Parameters::Parameter' ] if!(defined $query->{time}{end}) || ref($query->{time}{end});
     $query->{limit}{setLimit}= [ 'perfSONAR_PS::FT_DATATYPES::v1_0::nmwg::Message::Parameters::Parameter' ] if!(defined $query->{limit}{setLimit}) || ref($query->{limit}{setLimit});
     $query->{Metadata}{Program}= [ 'perfSONAR_PS::FT_DATATYPES::v1_0::nmwg::Message::Parameters::Parameter' ] if!(defined $query->{Metadata}{Program}) || ref($query->{Metadata}{Program});
     $query->{Metadata}{Stripes}= [ 'perfSONAR_PS::FT_DATATYPES::v1_0::nmwg::Message::Parameters::Parameter' ] if!(defined $query->{Metadata}{Stripes}) || ref($query->{Metadata}{Stripes});
     $query->{Metadata}{Streams}= [ 'perfSONAR_PS::FT_DATATYPES::v1_0::nmwg::Message::Parameters::Parameter' ] if!(defined $query->{Metadata}{Streams}) || ref($query->{Metadata}{Streams});
     $query->{Metadata}{DestPath}= [ 'perfSONAR_PS::FT_DATATYPES::v1_0::nmwg::Message::Parameters::Parameter' ] if!(defined $query->{Metadata}{DestPath}) || ref($query->{Metadata}{DestPath});
     $query->{Metadata}{User}= [ 'perfSONAR_PS::FT_DATATYPES::v1_0::nmwg::Message::Parameters::Parameter' ] if!(defined $query->{Metadata}{User}) || ref($query->{Metadata}{User});
     $query->{Metadata}{SrcPath}= [ 'perfSONAR_PS::FT_DATATYPES::v1_0::nmwg::Message::Parameters::Parameter' ] if!(defined $query->{Metadata}{SrcPath}) || ref($query->{Metadata}{SrcPath});
     $query->{Metadata}{BufferSize}= [ 'perfSONAR_PS::FT_DATATYPES::v1_0::nmwg::Message::Parameters::Parameter' ] if!(defined $query->{Metadata}{BufferSize}) || ref($query->{Metadata}{BufferSize});
     $query->{Metadata}{BlockSize}= [ 'perfSONAR_PS::FT_DATATYPES::v1_0::nmwg::Message::Parameters::Parameter' ] if!(defined $query->{Metadata}{BlockSize}) || ref($query->{Metadata}{BlockSize});

    eval {
        foreach my $table  ( keys %defined_table) {
            foreach my $entry (@{$defined_table{$table}}) {
                if(ref($query->{$table}{$entry}) eq 'ARRAY') {
                    foreach my $classes (@{$query->{$table}{$entry}}) {
                         if($classes && $classes eq 'perfSONAR_PS::FT_DATATYPES::v1_0::nmwg::Message::Parameters::Parameter') {
        
                            if    ($self->get_value && ( (  ( ($self->get_name eq 'startTime')  && $entry eq 'start') or  ( ($self->get_name eq 'endTime')  && $entry eq 'end')) || (  ( ($self->get_name eq 'setLimit')  && $entry eq 'setLimit')) || (  ( ($self->get_name eq 'program')  && $entry eq 'Program') or  ( ($self->get_name eq 'stripes')  && $entry eq 'Stripes') or  ( ($self->get_name eq 'streams')  && $entry eq 'Streams') or  ( ($self->get_name eq 'destpath')  && $entry eq 'DestPath') or  ( ($self->get_name eq 'user')  && $entry eq 'User') or  ( ($self->get_name eq 'srcpath')  && $entry eq 'SrcPath') or  ( ($self->get_name eq 'buffersize')  && $entry eq 'BufferSize') or  ( ($self->get_name eq 'blocksize')  && $entry eq 'BlockSize')) )) {
                                $query->{$table}{$entry} =  $self->get_value;
                                $self->get_LOGGER->debug(" Got value for SQL query $table.$entry: " . $self->get_value);
                                last;  
                            }

                            elsif ($self->get_text && ( (  ( ($self->get_name eq 'startTime')  && $entry eq 'start') or  ( ($self->get_name eq 'endTime')  && $entry eq 'end')) || (  ( ($self->get_name eq 'setLimit')  && $entry eq 'setLimit')) || (  ( ($self->get_name eq 'program')  && $entry eq 'Program') or  ( ($self->get_name eq 'stripes')  && $entry eq 'Stripes') or  ( ($self->get_name eq 'streams')  && $entry eq 'Streams') or  ( ($self->get_name eq 'destpath')  && $entry eq 'DestPath') or  ( ($self->get_name eq 'user')  && $entry eq 'User') or  ( ($self->get_name eq 'srcpath')  && $entry eq 'SrcPath') or  ( ($self->get_name eq 'buffersize')  && $entry eq 'BufferSize') or  ( ($self->get_name eq 'blocksize')  && $entry eq 'BlockSize')) )) {
                                $query->{$table}{$entry} =  $self->get_text;
                                $self->get_LOGGER->debug(" Got value for SQL query $table.$entry: " . $self->get_text);
                                last;  
                            }


                         }
                     }
                 }
             }
        }
    };
    if($EVAL_ERROR) {
            $self->get_LOGGER->logdie("SQL query building is failed  here " . $EVAL_ERROR);
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
    
    return;
}

=head2  asString()

 shortcut to get DOM and convert into the XML string
 returns nicely formatted XML string  representation of the  parameter object

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
 returns parameter  object

=cut

sub fromDOM {
    my ($self, $dom) = @_;

    $self->set_value($dom->getAttribute('value')) if($dom->getAttribute('value'));

    $self->get_LOGGER->debug("Attribute value= ". $self->get_value) if $self->get_value;
    $self->set_name($dom->getAttribute('name')) if($dom->getAttribute('name') && ($dom->getAttribute('name')   =~ m/(user|streams|srcpath|destpath|program|stripes|buffersize|blocksize|startTime|endTime|setLimit)$/));

    $self->get_LOGGER->debug("Attribute name= ". $self->get_name) if $self->get_name;
    $self->set_text($dom->textContent) if(!($self->get_value) && $dom->textContent);

    return $self;
}


1;

__END__


=head1  SEE ALSO

Automatically generated by L<XML::RelaxNG::Compact::PXB> 

=head1 AUTHOR

Fahad Satti

=head1 COPYRIGHT

Copyright (c) 2009, Fahad Satti. All rights reserved.

=head1 LICENSE

This program is free software.
You can redistribute it and/or modify it under the same terms as Perl itself.

=cut


