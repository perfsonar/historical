package PingerUI::GraphIt;
use strict;
use warnings;
use English qw( -no_match_vars );
use version; our $VERSION = '0.09'; 


=head1 NAME

     
    PingerUI::GraphIt  -  creates graphs

=head1 DESCRIPTION

      GraphIt  -  creates various graphs by utilizing ChartDirector API
      
      
=head1 EXPORTED 

=cut
##use lib "$MYPATH/lib/PingerUI/ChartDirector/lib";

use perlchartdir; 
use Exporter (); 
use base qw(Exporter);
our @EXPORT = ();
our @EXPORT_OK = qw(graph_it2);

=head2 graph_it2
  
         creates graph 
	 accepts:
	     $gpr  - type of the graph ( area, lines ..etc)
	     $title - title of the graph 
	     $gtyp - type of the metric ( rtt, rtloss, etc)
	     $ox - arrayref ot the OX
	     $summs - arrayref to the OY
	     $x_l - OX label
	     $y_l - OY label
	     $fl_name  - base filename 
	 returns filename of the PNG graph
  
=cut

# legends fro different graphs


my %legends = (
               rt   =>  "Average RTT (ms)",
               loss =>  "Percentage of Packets Loss", 
	       wb   =>  "Calculated TCP troughput",
	       clp =>   "Conditional Packets Loss",
	       ipdv =>  "mean IPD delay",
	       iqr =>  "InterQuantile IPD",
	       dupl =>  "Indicator of reorderd/duplicated packets"     	        
	      );
 
#   number of pixels for OY dimension
my $GR_HEIGHT = 150;
# number of pixels for OX dimension
my $GR_WIDTH = 420;  
 
sub graph_it2 {
    my ( $req, $gpr, $title, $gtyp, $ox, $summs, $x_l, $y_l  ) = @_;

    my ( $y1_l, $y2_l ) = split(' ', $y_l);
    my $loss_max = $summs->{lossPercent}{max} * 1.2;
    $loss_max =  100 if $loss_max > 100;
 
    # Create a XYChart object of size 600 x 300 pixels, with a pale blue (eeeeff)
    # background, black border, 1 pixel 3D border effect and rounded corners.
    my $c; 
    if ( $gtyp eq 'rtloss' ) {
        $c = new XYChart(  $GR_WIDTH + 40,  $GR_HEIGHT + 55, 0xeeeeff, 0x000000,  1 );
        $c->setPlotArea( 30, 45,
                         $GR_WIDTH - 35,
                         $GR_HEIGHT - 28,
                         0xffffff, -1, -1, 0xcccccc, 0xcccccc );
    } else {
        $c = new XYChart(  $GR_WIDTH + 40,  $GR_HEIGHT + 55, 0xeeeeff, 0x000000, 1 );
        $c->setPlotArea( 46, 45,
                         $GR_WIDTH - 22,
                         $GR_HEIGHT - 28,
                         0xffffff, -1, -1, 0xcccccc, 0xcccccc );
    }
    $c->setRoundedFrame();
    $c->setDropShadow();

# Set the plotarea at (55, 55) and of size 520 x 195 pixels, with white (ffffff)
# background. Set horizontal and vertical grid lines to grey (cccccc).
   

# Add a title box to the chart using 15 pts Times Bold Italic font. The text is white
# (ffffff) on a deep blue (000088) background, with soft lighting effect from the
# right side.
    $c->addTitle( "<*block,valign=absmiddle*>  $title  <*/*>",
                  "italic", 10, 0xffffff )
        ->setBackground( 0x000088, -1,
                         perlchartdir::softLighting($perlchartdir::Right) );

################perlchartdir::softLighting($perlchartdir::Right)

    $c->addLegend( 40, 48, 0, "normal", 8)
        ->setBackground($perlchartdir::Transparent);

    # Add a title to the y axis

    $c->yAxis()->setColors(0x808fffff);
    $c->xAxis()->setLabels($ox);

    # Set the axes width to 2 pixels
    $c->xAxis()->setWidth(2);
    $c->yAxis()->setWidth(2);

    # Display 1 out of 6 labels on the x-axis.
    $c->xAxis()->setLabelStep(30);

    # Add a title to the x axis using CDML
    $c->xAxis()->setTitle("<*block,valign=absmiddle*> $x_l <*/*>");

    if ( $gtyp eq 'rtloss' ) {
       
        # Add a title to the y axis
        $c->yAxis()->setTitle($y1_l);
        $c->yAxis2()->setTitle($y2_l);
	$c->yAxis2()->setAutoScale(0.01,0.01);


    } else {
        $c->yAxis()->setTitle($y_l);
	$c->yAxis2()->setAutoScale(0.01,0.01);
    }

    my $layer       = undef;
    my $marker_size = 7;
    if ( $gpr eq 'area' ) {
        $layer = $c->addAreaLayer2(1);
        $layer->setBorderColor( $perlchartdir::Transparent,
                               perlchartdir::softLighting($perlchartdir::Top) );
        $layer->setLineWidth(1);
    } elsif ( $gpr eq 'lines' ) {
        $layer = $c->addLineLayer2($perlchartdir::Side);
        $layer->setLineWidth(2);
    } elsif ( $gpr eq 'points' ) {
        $layer = $c->addLineLayer();
        $layer->setLineWidth(0);

    } elsif ( $gpr eq 'bars' ) {
        $layer = $c->addBarLayer2($perlchartdir::Stack);
        $layer->setBorderColor( $perlchartdir::Transparent,
                               perlchartdir::softLighting($perlchartdir::Top) );
        $layer->setBarGap($perlchartdir::TouchBar);
        $layer->setLineWidth(0);
    }

    # Set the labels on the x axis.
    if ( $gtyp eq 'rtloss' ) {
        if ( $gpr eq 'points' ) {
            my $layer1 = $c->addLineLayer( $summs->{meanRtt}{count},
                                           0x808fffff, $legends{'rt'} );
            $layer1->setLineWidth(0);
            my $rt_dt = $layer1->getDataSet(0);
            $rt_dt->setDataSymbol( $perlchartdir::DiamondShape, $marker_size,
                                   -1 );

            $layer = $c->addLineLayer2($perlchartdir::Side);
            $layer->setLineWidth(0);
            my $dt1 = $layer->addDataSet( $summs->{lossPercent}{count},
                                          -1, $legends{'loss'} );
            $dt1->setUseYAxis2();
            $dt1->setDataSymbol( $perlchartdir::DiamondShape, $marker_size,
                                 -1 );

            my $dt2 = $layer->addDataSet( $summs->{clp}{count}, -1,
                                          $legends{'clp'} );
            $dt2->setUseYAxis2();
            $dt2->setDataSymbol( $perlchartdir::DiamondShape, $marker_size,
                                 -1 );
        } elsif ( $gpr eq 'bars' ) {
            my $layer1 = $c->addBarLayer2($perlchartdir::Side);
            $layer1->setBorderColor(
                                     $perlchartdir::Transparent,
                                     perlchartdir::softLighting(
                                                             $perlchartdir::Top)
            );
            $layer1->setBarGap($perlchartdir::TouchBar);
            $layer1->addDataSet( $summs->{meanRtt}{count},
                                 0x808fffff, $legends{'rt'} );
            $layer->addDataSet( $summs->{lossPercent}{count},
                                -1, $legends{'loss'} )->setUseYAxis2();
            $layer->addDataSet( $summs->{clp}{count}, -1, $legends{'clp'} )
                ->setUseYAxis2();
        } else {
            $layer = $c->addLineLayer2($perlchartdir::Side);
            $c->addAreaLayer( $summs->{meanRtt}{count},
                              0x808fffff, $legends{'rt'}, 0 );
            $layer->addDataSet( $summs->{lossPercent}{count},
                                -1, $legends{'loss'} )->setUseYAxis2();
            $layer->addDataSet( $summs->{clp}{count}, -1, $legends{'clp'} )
                ->setUseYAxis2();
        }
    } elsif ( $gtyp eq 'ipdv' ) {
        if ( $gpr eq 'points' ) {
            $layer->addDataSet( $summs->{minIpd}{count}, -1, "MIN delay" )
                ->setDataSymbol( $perlchartdir::DiamondShape, $marker_size,
                                 -1 );
            $layer->addDataSet( $summs->{meanIpd}{count}, -1, $legends{'ipdv'} )
                ->setDataSymbol( $perlchartdir::DiamondShape, $marker_size,
                                 -1 );
            $layer->addDataSet( $summs->{maxIpd}{count}, -1, "MAX delay" )
                ->setDataSymbol( $perlchartdir::DiamondShape, $marker_size,
                                 -1 );
            $layer->addDataSet( $summs->{iqrIpd}{count}, -1, $legends{'iqr'} )
                ->setDataSymbol( $perlchartdir::DiamondShape, $marker_size,
                                 -1 );
        } else {
            $layer->addDataSet( $summs->{minIpd}{count}, -1, "MIN delay" );
            $layer->addDataSet( $summs->{meanIpd}{count}, -1,
                                $legends{'ipdv'} );
            $layer->addDataSet( $summs->{maxIpd}{count}, -1, "MAX delay" );
            $layer->addDataSet( $summs->{iqrIpd}{count}, -1, $legends{'iqr'} );
        }
    } elsif ( $gtyp eq 'loss' ) {
        if ( $gpr eq 'points' ) {
            $layer->addDataSet( $summs->{lossPercent}{count},
                                -1, $legends{loss} )
                ->setDataSymbol( $perlchartdir::DiamondShape, $marker_size,
                                 -1 );
            $layer->addDataSet( $summs->{clp}{count}, -1, $legends{clp} )
                ->setDataSymbol( $perlchartdir::DiamondShape, $marker_size,
                                 -1 );
        } else {
            $layer->addDataSet( $summs->{lossPercent}{count},
                                -1, $legends{loss} );
            $layer->addDataSet( $summs->{clp}{count}, -1, $legends{clp} );
        }
    } elsif ( $gtyp eq 'rt' ) {
        if ( $gpr eq 'points' ) {
            $layer->addDataSet( $summs->{minRtt}{count}, -1, 'MIN RTT' )
                ->setDataSymbol( $perlchartdir::DiamondShape, $marker_size,
                                 -1 );
            $layer->addDataSet( $summs->{meanRtt}{count}, -1, $legends{'rt'} )
                ->setDataSymbol( $perlchartdir::DiamondShape, $marker_size,
                                 -1 );
            $layer->addDataSet( $summs->{maxRtt}{count}, -1, 'MAX RTT' )
                ->setDataSymbol( $perlchartdir::DiamondShape, $marker_size,
                                 -1 );
        } else {
            $layer->addDataSet( $summs->{minRtt}{count},  -1, 'MIN RTT' );
            $layer->addDataSet( $summs->{meanRtt}{count}, -1, $legends{'rt'} );
            $layer->addDataSet( $summs->{maxRtt}{count},  -1, 'MAX RTT' );
        }
    }
    return $c;
}

1;

__END__


=head1   AUTHOR

    Maxim Grigoriev,  2008, maxim@fnal.gov
    
=head1 COPYRIGHT

Copyright (c) 2008, Fermi Research Alliance (FRA)

=head1 LICENSE

You should have received a copy of the Fermitool license along with this software.
 

 

=cut
