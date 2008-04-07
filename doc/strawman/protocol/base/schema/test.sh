#!/bin/sh

rm -f *.rng *.xsd

JAVA=/usr/lib/jvm/java-1.5.0-sun/jre/bin/java
TRANG=../../../util/trang.jar
JING=../../../util/jing.jar
MSV=../../../util/msv.jar

SCHEMA_DIR=.
INSTANCE_DIR=.

rm -f *rng *xsd

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/request.rnc $SCHEMA_DIR/request.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/request.rng $SCHEMA_DIR/request.xsd
#$JAVA -jar $MSV -warning $SCHEMA_DIR/request.rng $INSTANCE_DIR/request.xml
#$JAVA -jar $JING $SCHEMA_DIR/request.rng $INSTANCE_DIR/request.xml

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/response.rnc $SCHEMA_DIR/response.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/response.rng $SCHEMA_DIR/response.xsd
#$JAVA -jar $MSV -warning $SCHEMA_DIR/response.rng $INSTANCE_DIR/response.xml
#$JAVA -jar $JING $SCHEMA_DIR/response.rng $INSTANCE_DIR/response.xml
