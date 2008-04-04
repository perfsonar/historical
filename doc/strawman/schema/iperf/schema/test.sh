#!/bin/sh

rm -f *.rng *.xsd

JAVA=/usr/lib/jvm/java-1.5.0-sun/jre/bin/java
TRANG=../../../util/trang.jar
JING=../../../util/jing.jar
MSV=../../../util/msv.jar

SCHEMA_DIR=.
INSTANCE_DIR=.

rm -f *rng *xsd

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/iperf.rnc $SCHEMA_DIR/iperf.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/iperf.rng $SCHEMA_DIR/iperf.xsd
#$JAVA -jar $MSV -warning $SCHEMA_DIR/iperf.rng $INSTANCE_DIR/iperf.xml
#$JAVA -jar $JING $SCHEMA_DIR/iperf.rng $INSTANCE_DIR/iperf.xml
