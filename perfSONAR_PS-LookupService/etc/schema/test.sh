#!/bin/sh

rm -f $SCHEMA_DIR/*xsd $SCHEMA_DIR/*rng

JAVA=/usr/lib/jvm/java-1.6.0-openjdk-1.6.0.0/jre/bin/java

TRANG=/home/zurawski/nmwg-schema/verify/trang.jar
JING=/home/zurawski/nmwg-schema/verify/jing.jar
MSV=/home/zurawski/nmwg-schema/verify/msv.jar

SCHEMA_DIR=/home/zurawski/trunk/perfSONAR_PS-LookupService/etc/schema
INSTANCE_DIR=/home/zurawski/trunk/perfSONAR_PS-LookupService/etc/requests

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/LSRegisterRequest.rnc $SCHEMA_DIR/LSRegisterRequest.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/LSRegisterRequest.rng $SCHEMA_DIR/LSRegisterRequest.xsd

$JAVA -jar $MSV -warning $SCHEMA_DIR/LSRegisterRequest.rng $INSTANCE_DIR/hLS/LSRegisterRequest.xml
$JAVA -jar $JING $SCHEMA_DIR/LSRegisterRequest.rng $INSTANCE_DIR/hLS/LSRegisterRequest.xml

$JAVA -jar $MSV -warning $SCHEMA_DIR/LSRegisterRequest.rng $INSTANCE_DIR/hLS/LSRegisterRequest-key.xml
$JAVA -jar $JING $SCHEMA_DIR/LSRegisterRequest.rng $INSTANCE_DIR/hLS/LSRegisterRequest-key.xml

$JAVA -jar $MSV -warning $SCHEMA_DIR/LSRegisterRequest.rng $INSTANCE_DIR/hLS/LSRegisterRequest-update.xml
$JAVA -jar $JING $SCHEMA_DIR/LSRegisterRequest.rng $INSTANCE_DIR/hLS/LSRegisterRequest-update.xml

# ------

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/LSDeregisterRequest.rnc $SCHEMA_DIR/LSDeregisterRequest.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/LSDeregisterRequest.rng $SCHEMA_DIR/LSDeregisterRequest.xsd

$JAVA -jar $MSV -warning $SCHEMA_DIR/LSDeregisterRequest.rng $INSTANCE_DIR/hLS/LSDeregisterRequest.xml
$JAVA -jar $JING $SCHEMA_DIR/LSDeregisterRequest.rng $INSTANCE_DIR/hLS/LSDeregisterRequest.xml

# ------

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/LSKeepaliveRequest.rnc $SCHEMA_DIR/LSKeepaliveRequest.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/LSKeepaliveRequest.rng $SCHEMA_DIR/LSKeepaliveRequest.xsd

$JAVA -jar $MSV -warning $SCHEMA_DIR/LSKeepaliveRequest.rng $INSTANCE_DIR/hLS/LSKeepaliveRequest.xml
$JAVA -jar $JING $SCHEMA_DIR/LSKeepaliveRequest.rng $INSTANCE_DIR/hLS/LSKeepaliveRequest.xml

# ------

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/LSQueryRequest.rnc $SCHEMA_DIR/LSQueryRequest.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/LSQueryRequest.rng $SCHEMA_DIR/LSQueryRequest.xsd

$JAVA -jar $MSV -warning $SCHEMA_DIR/LSQueryRequest.rng $INSTANCE_DIR/hLS/LSQueryRequest.xml
$JAVA -jar $JING $SCHEMA_DIR/LSQueryRequest.rng $INSTANCE_DIR/hLS/LSQueryRequest.xml

# ------

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/LSKeyRequest.rnc $SCHEMA_DIR/LSKeyRequest.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/LSKeyRequest.rng $SCHEMA_DIR/LSKeyRequest.xsd

$JAVA -jar $MSV -warning $SCHEMA_DIR/LSKeyRequest.rng $INSTANCE_DIR/hLS/LSKeyRequest.xml
$JAVA -jar $JING $SCHEMA_DIR/LSKeyRequest.rng $INSTANCE_DIR/hLS/LSKeyRequest.xml

# ------

# ------

rm -f $SCHEMA_DIR/*xsd $SCHEMA_DIR/*rng
