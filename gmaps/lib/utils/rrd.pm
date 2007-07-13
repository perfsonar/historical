#!/bin/env perl

#######################################################################
# quick hack to create rrd graphs
#######################################################################

use Log::Log4perl qw( get_logger :levels );

use RRDs;
package utils::rrd;


use strict;

our $logger = Log::Log4perl->get_logger("utils::rrd" );

sub new {
    my $class = shift;
    
    my $self  = { };
    bless( $self, $class );

	$self->{filename} = shift;    
    $self->{startTime} = shift;
    $self->{entries} = shift;
    
    # args
    my @args = ();
    push @args, "--start=" . $self->{startTime};
    push @args, "DS:in:GAUGE:500:0:U";
    push @args, "DS:out:GAUGE:500:0:U";
    push @args, "RRA:AVERAGE:0:1:" . $self->{entries};
    
    # create the rrd here
    RRDs::create $self->{filename}, @args;
 	my $ans = RRDs::error;
	die( "Error creating rrd " . $self->{filename} .  ": $ans.\n\n" )
		if $ans ne undef || $ans ne '';   
    
    return $self;
}


sub DESTROY
{
	my $self = shift;
	unlink $self->{'filename'};
	unlink $self->{'png'};
	return;
}




sub add
{
	my $self = shift;
	my $time = shift;
	my $template = shift;
	my @values = @_;

	# run the update
	
	RRDs::update(	$self->{filename},
					'--template=' . $template,
				 	$time . ':' . join( ':', @values) );
				 	
	my $ans = RRDs::error;
	if( defined $ans || $ans ne '' ) {
		return undef if $ans =~ /illegal attempt to update using time/;
		warn( "Error updating " . $self->{filename} . " $ans.\n" );
	}
	return undef;
}


sub getGraph
{
	my $self = shift;
	my $png = shift;
	my $start = shift;
	my $end = shift;
	
	my @args = ();
	push @args, '--end=' . $end;
	push @args, '--start=' . $start;
	push @args, '--vertical-label=bits/sec';
	push @args, 'DEF:in=' . $self->{filename} . ':in:AVERAGE';
	push @args, 'DEF:out=' . $self->{filename} . ':out:AVERAGE';
	push @args, 'CDEF:inBits=in,8,*';
	push @args, 'CDEF:outBits=out,8,*';
	
	# graph sepcs
	push @args, 'AREA:inBits#00FF00:in';
	push @args, 'LINE2:outBits#0000FF:out';

	$logger->info( "args: @args" );

	$self->{'png'} = $png;
	RRDs::graph $png, @args;
	
	my $ans = RRDs::error;
	warn( "Error graphing " . $self->{filename} . " $ans.\n" )
		if $ans ne undef || $ans ne '';

	# cat out the png to a variable
	open( PNG, "<$png") or die "Could not fetch graph: $!\n";
	my $out = undef;
	while( <PNG> ) {
		$out .= $_;
	}
	close PNG;
	# remove temp file
#	unlink $png;

	return \$out;
}

1;



