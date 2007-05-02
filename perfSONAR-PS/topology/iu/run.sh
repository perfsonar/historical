#!/bin/sh

BASE=./i2_net
RDF=$BASE.rdf
NMWG=$BASE.xml
DOT=$BASE.dot
PNG=$BASE.png

rm -f $RDF
wget -c http://dc-1.grnoc.iu.edu/ndl/$RDF

./rdf_to_nmwg.pl $RDF $NMWG
./nmwg_to_dot.pl $NMWG $DOT
fdp $DOT -Tpng -o $PNG

