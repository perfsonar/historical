#!/bin/env perl

#######################################################################
# creates kml markup
#######################################################################

use gmaps::gmap;
use Template;

package gmaps::KML;

use strict;


sub new {
    my $class = shift;
    my $include = shift;
    
    my $self  = { };
    bless( $self, $class );
    
    @{$self->{PLACEMARKS}} = ();
	if ( -d $include ) {
	    $self->{INCLUDE} = $include;
	} else {
		$self->{INCLUDE} = ${gmaps::gmap::templatePath};
	}
	
    return $self;
}


sub addPlacemark
{
	my $self = shift;
	my $name = shift;
	my $long = shift;
	my $lat = shift;
	my $desc = shift;

	if ( $desc eq '' ) {
		$desc = &gmaps::utils::gmap::getDescr( $name );
	}

	my %mark = (
				'name' => $name,
				'lat'  => $lat,
				'long' => $long,
				'desc' => $desc,
			);

	push @{$self->{PLACEMARKS}}, \%mark;

	return \%mark;
}


sub getKML
{
	my $self = shift;
	
	my $tt = Template->new( { 'ABSOLUTE' => 1 } );	
	my $vars = {
			'marks' => \@{$self->{PLACEMARKS}}	
		};
	my $file = $self->{INCLUDE} . '/kml_placemarks.tt2';

	my $out = '';
	$tt->process( $file, $vars, \$out )
        || die $tt->error;

	return \$out;

}





1;