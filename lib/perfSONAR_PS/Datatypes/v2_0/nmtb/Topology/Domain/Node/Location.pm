package  perfSONAR_PS::Datatypes::v2_0::nmtb::Topology::Domain::Node::Location;
use strict;
use warnings;
use English qw( -no_match_vars);
use version; our $VERSION = qv('v2.0');
=head1 NAME

 perfSONAR_PS::Datatypes::v2_0::nmtb::Topology::Domain::Node::Location  - A base class, implements  'location'  element from the perfSONAR_PS RelaxNG schema
  
=head1 DESCRIPTION

   Object representation of the location element.
   Object fields are:
    Object reference:   continent => type ,
    Object reference:   country => type ,
    Object reference:   zipcode => type ,
    Object reference:   state => type ,
    Object reference:   institution => type ,
    Object reference:   city => type ,
    Object reference:   streetAddress => type ,
    Object reference:   floor => type ,
    Object reference:   room => type ,
    Object reference:   cage => type ,
    Object reference:   rack => type ,
    Object reference:   shelf => type ,
    Object reference:   latitude => type ,
    Object reference:   longitude => type ,
   
   The constructor accepts only single parameter, it could be a hashref to parameters hash  or DOM with  'location' element 
    
    
=head1 SYNOPSIS

              use perfSONAR_PS::Datatypes::v2_0::nmtb::Topology::Domain::Node::Location;
          
          my $el =  perfSONAR_PS::Datatypes::v2_0::nmtb::Topology::Domain::Node::Location->new($DOM_Obj);
 
=head1   METHODS

=cut
 

use XML::LibXML;
use Scalar::Util qw(blessed);
use Log::Log4perl qw(get_logger); 
use perfSONAR_PS::Datatypes::Element qw(getElement);
use perfSONAR_PS::Datatypes::Namespace;
use perfSONAR_PS::Datatypes::NSMap;
use Readonly;
use Class::Accessor::Fast;
use Class::Fields;
use base qw(Class::Accessor::Fast Class::Fields);
use fields qw(nsmap idmap refidmap   continent country zipcode state institution city streetAddress floor room cage rack shelf latitude longitude );

perfSONAR_PS::Datatypes::v2_0::nmtb::Topology::Domain::Node::Location->mk_accessors(perfSONAR_PS::Datatypes::v2_0::nmtb::Topology::Domain::Node::Location->show_fields('Public'));
  
=head2 new( )
   
      creates   object, accepts DOM with  element tree or hashref to the list of
      keyd parameters

=cut
Readonly::Scalar our $COLUMN_SEPARATOR => ':';
Readonly::Scalar our $CLASSPATH =>  'perfSONAR_PS::Datatypes::v2_0::nmtb::Topology::Domain::Node::Location';
Readonly::Scalar our $LOCALNAME => 'location';
            
sub new { 
    my $that = shift;
    my $param = shift;
 
    my $logger  = get_logger( $CLASSPATH ); 
    my $class = ref($that) || $that;
    my $self =  fields::new($class );
    $self->nsmap(perfSONAR_PS::Datatypes::NSMap->new()); 
    $self->nsmap->mapname( $LOCALNAME, 'nmtb');
    
    if($param) {
        if(blessed $param && $param->can('getName')  && ($param->getName =~ m/$LOCALNAME$/xm) ) {
            return  $self->fromDOM($param);  
          
        } elsif(ref($param) ne 'HASH')   {
            $logger->error("ONLY hash ref accepted as param " . $param ); 
            return;
        }
    if($param->{xml}) {
         my $parser = XML::LibXML->new();
             my $dom;
             eval {
                  my $doc = $parser->parse_string( $param->{xml});
          $dom = $doc->getDocumentElement;
             };
             if($EVAL_ERROR) {
                 $logger->error(" Failed to parse XML :" . $param->{xml} . " \n ERROR: \n" . $EVAL_ERROR);
                return;
             }
             return  $self->fromDOM( $dom );  
    } 
        $logger->debug("Parsing parameters: " . (join " : ", keys %{$param}));
     
        no strict 'refs';
        foreach my $param_key (keys %{$param}) {
            $self->$param_key( $param->{$param_key} ) if $self->can($param_key);
        }  
        use strict;     
   
       $logger->debug("Done ");     
    }  
    return $self;
}

 
 
=head2   getDOM ($) 
      
       accept parent DOM
       return location object DOM, generated from object contents 
  
=cut 
 
sub getDOM {
    my $self = shift;
    my $parent = shift; 
    my $logger  = get_logger( $CLASSPATH );
    my @nss; 
    ## if this is root element then register all namespaces + nmwg
    unless($parent) {
        my $nsses = $self->registerNamespaces(); 
        @nss = map {$_  if($_ && $_  ne  $self->nsmap->mapname( $LOCALNAME ))}  keys %{$nsses};
        push(@nss,  $self->nsmap->mapname( $LOCALNAME ));
    } 
    push  @nss, $self->nsmap->mapname( $LOCALNAME ) unless  @nss;
    my $location = getElement({name =>   $LOCALNAME, parent => $parent , ns => \@nss,
                             attributes => [

                                           ],
                         }); 
   foreach my $textnode (qw/continent country zipcode state institution city streetAddress floor room cage rack shelf latitude longitude /) {
       if($self->{$textnode}) { 
            my  $domtext  =  getElement({name =>   $textnode, parent => $location , ns => [$self->nsmap->mapname($LOCALNAME)],
                                          text => $self->{$textnode},
                                 });
            $domtext?$location->appendChild($domtext):$logger->error("Failed to append new text element $textnode  to  location   ");
        } 
   } 
    return $location;
}

=head2  querySQL ()

      depending on config  it will return some hash ref  to the initialized fields
    for example querySQL ()
    accepts one optional prameter - query hashref
    will return:
    { ip_name_src =>  'hepnrc1.hep.net' },}
    
=cut

sub  querySQL {
    my $self = shift;
    my $query = shift; ### undef at first and then will be hash ref
    my $logger  = get_logger( $CLASSPATH );
     
    return $query;
}

=head2 merge

      merge with another location ( append + overwrite if exists )
      we can do it differently
      method #1:
         convert to dom both objects and then get resulted object from combined dom 
      method #2 default:
         through the introspection of the object

=cut


sub merge {
    my $self = shift;
    my $new_location = shift;
    my $logger  = get_logger( $CLASSPATH );  
    unless($new_location && blessed $new_location && $new_location->can("getDOM")) {
        $logger->error(" Please supply defined object of location  ");
        return;
    } 
    ### for each field ( element or attribute )
    ### merge elements, add if its arrayref and overwrite attribtues for the same elements
    ### merge only if namespace is the same  
    foreach my $member_name ($new_location->show_fields) {
        ### double check if   objects are the same
    if($self->can($member_name)) {
        my $current_member  = $self->{$member_name};
        my $new_member      =  $new_location->{$member_name};
        ###  check if both objects are defined
        if($current_member && $new_member) {
            ### if  one of them array then just add another one
            if(blessed $current_member && blessed $new_member  && $current_member->can("merge") 
               && ( $current_member->nsmap->mapname($member_name) 
                eq  $new_member->nsmap->mapname($member_name) ) ) {
               $current_member->merge($new_member);
            $self->{$member_name} =  $current_member;
            $logger->debug("  Merged $member_name , got" . $current_member->asString);
            ### if its array then just push
            } elsif(ref($current_member) eq 'ARRAY'){
                 
           $self->{$member_name}=[$current_member, $new_member];
              
            $logger->debug("  Pushed extra to $member_name ");
            }  
        ## thats it, dont merge if new member is just a scalar
        } elsif( $new_member) {
           $self->{$member_name} = $new_member;
        }   
    } else {
        $logger->error(" This field $member_name,  found in supplied  location  is not supported by location class");
        return;
        }
    }
    return $self;
} 
 
=head2  buildIdMap()

    if any of subelements has id then get a map of it in form of
    hashref to { element}{id} = index in array and store in the idmap field

=cut

sub  buildIdMap {
    my $self = shift;
    my $map = (); 
    my $logger  = get_logger( $CLASSPATH );
    return;
}
=head2 buildrefIdMap ()

    if any of subelements has  metadataIdRef  then get a map of it in form of
    hashref to { element}{ metadataIdRef } = index in array and store in the idmap field

=cut

sub  buildRefIdMap {
    my $self = shift;
    my %map = (); 
    my $logger  = get_logger( $CLASSPATH );
    return;
}
=head2  asString()

   shortcut to get DOM and convert into the XML string
   returns XML string  representation of the  location object

=cut

sub asString {
    my $self = shift;
    my $dom = $self->getDOM();
    return $dom->toString('1');
}

=head2 registerNamespaces ()

   will parse all subelements and register all namepspaces within the location namespace

=cut

sub registerNamespaces {
    my $self = shift;
    my $logger  = get_logger( $CLASSPATH );
    my $nsids = shift;
    my $local_nss = {reverse %{$self->nsmap->mapname}};
    unless($nsids) {
        $nsids =  $local_nss;
    }  else {
        %{$nsids} = ( %{$local_nss},  %{$nsids});
    }
    return     $nsids;
}
=head2  fromDOM ($)
   
   accepts parent XML DOM   element   tree as parameter 
   returns location  object

=cut

sub fromDOM {
    my $self = shift;
    my $logger  = get_logger( $CLASSPATH ); 
    my $dom = shift;
     
    foreach my $childnode ($dom->childNodes) { 
        my  $getname  = $childnode->getName;
        my ($nsid, $tagname) = split $COLUMN_SEPARATOR,  $getname; 
        unless($nsid && $tagname) {   
            next;
        }
        if ($childnode->textContent && $self->can("$tagname")) { 
           $self->{$tagname} =  $childnode->textContent; ## text node 
        }       ###  $dom->removeChild($childnode); ##remove processed element from the current DOM so subclass can deal with remaining elements
    }
  $self->buildIdMap;
 $self->buildRefIdMap;
 $self->registerNamespaces;
  
 return $self;
}

 
 
=head1 AUTHORS

   Maxim Grigoriev (FNAL)  2007-2008, maxim@fnal.gov

=cut 

1;
 
