#!/bin/sh

rm -f $SCHEMA_DIR/*xsd $SCHEMA_DIR/*rng

JAVA=/usr/lib/jvm/java-1.6.0-openjdk-1.6.0.0/jre/bin/java

TRANG=/home/zurawski/nmwg-schema/verify/trang.jar
JING=/home/zurawski/nmwg-schema/verify/jing.jar
MSV=/home/zurawski/nmwg-schema/verify/msv.jar

SCHEMA_DIR=/home/zurawski/trunk/perfSONAR_PS-SNMPMA/etc/schema
INSTANCE_DIR=/home/zurawski/trunk/perfSONAR_PS-SNMPMA/etc/requests

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/MetadataKeyRequest-utilization.rnc $SCHEMA_DIR/MetadataKeyRequest-utilization.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/MetadataKeyRequest-utilization.rng $SCHEMA_DIR/MetadataKeyRequest-utilization.xsd

for i in 1 2 3 4 5
do
    $JAVA -jar $MSV -warning $SCHEMA_DIR/MetadataKeyRequest-utilization.rng $INSTANCE_DIR/MetadataKeyRequest-utilization-$i.xml
    $JAVA -jar $JING $SCHEMA_DIR/MetadataKeyRequest-utilization.rng $INSTANCE_DIR/MetadataKeyRequest-utilization-$i.xml
done

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/MetadataKeyRequest-errors.rnc $SCHEMA_DIR/MetadataKeyRequest-errors.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/MetadataKeyRequest-errors.rng $SCHEMA_DIR/MetadataKeyRequest-errors.xsd

for i in 1 2 3 4 5
do
    $JAVA -jar $MSV -warning $SCHEMA_DIR/MetadataKeyRequest-errors.rng $INSTANCE_DIR/MetadataKeyRequest-errors-$i.xml
    $JAVA -jar $JING $SCHEMA_DIR/MetadataKeyRequest-errors.rng $INSTANCE_DIR/MetadataKeyRequest-errors-$i.xml
done

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/MetadataKeyRequest-discards.rnc $SCHEMA_DIR/MetadataKeyRequest-discards.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/MetadataKeyRequest-discards.rng $SCHEMA_DIR/MetadataKeyRequest-discards.xsd

for i in 1 2 3 4 5
do
    $JAVA -jar $MSV -warning $SCHEMA_DIR/MetadataKeyRequest-discards.rng $INSTANCE_DIR/MetadataKeyRequest-discards-$i.xml
    $JAVA -jar $JING $SCHEMA_DIR/MetadataKeyRequest-discards.rng $INSTANCE_DIR/MetadataKeyRequest-discards-$i.xml
done

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/MetadataKeyRequest-snmp.rnc $SCHEMA_DIR/MetadataKeyRequest-snmp.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/MetadataKeyRequest-snmp.rng $SCHEMA_DIR/MetadataKeyRequest-snmp.xsd

for i in 1 2 3 4 5
do
    $JAVA -jar $MSV -warning $SCHEMA_DIR/MetadataKeyRequest-snmp.rng $INSTANCE_DIR/MetadataKeyRequest-snmp-$i.xml
    $JAVA -jar $JING $SCHEMA_DIR/MetadataKeyRequest-snmp.rng $INSTANCE_DIR/MetadataKeyRequest-snmp-$i.xml
done

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/MetadataKeyRequest-ganglia.rnc $SCHEMA_DIR/MetadataKeyRequest-ganglia.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/MetadataKeyRequest-ganglia.rng $SCHEMA_DIR/MetadataKeyRequest-ganglia.xsd

for i in 1 2 3 4 5
do
    $JAVA -jar $MSV -warning $SCHEMA_DIR/MetadataKeyRequest-ganglia.rng $INSTANCE_DIR/MetadataKeyRequest-Ganglia-$i.xml
    $JAVA -jar $JING $SCHEMA_DIR/MetadataKeyRequest-ganglia.rng $INSTANCE_DIR/MetadataKeyRequest-Ganglia-$i.xml
done

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/MetadataKeyResponse-utilization.rnc $SCHEMA_DIR/MetadataKeyResponse-utilization.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/MetadataKeyResponse-utilization.rng $SCHEMA_DIR/MetadataKeyResponse-utilization.xsd

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/MetadataKeyResponse-errors.rnc $SCHEMA_DIR/MetadataKeyResponse-errors.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/MetadataKeyResponse-errors.rng $SCHEMA_DIR/MetadataKeyReesponse-errors.xsd

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/MetadataKeyResponse-discards.rnc $SCHEMA_DIR/MetadataKeyResponse-discards.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/MetadataKeyResponse-discards.rng $SCHEMA_DIR/MetadataKeyReesponse-discards.xsd

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/MetadataKeyResponse-snmp.rnc $SCHEMA_DIR/MetadataKeyResponse-snmp.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/MetadataKeyResponse-snmp.rng $SCHEMA_DIR/MetadataKeyReesponse-snmp.xsd

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/MetadataKeyResponse-ganglia.rnc $SCHEMA_DIR/MetadataKeyResponse-ganglia.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/MetadataKeyResponse-ganglia.rng $SCHEMA_DIR/MetadataKeyReesponse-ganglia.xsd

# ----

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/SetupDataRequest-utilization.rnc $SCHEMA_DIR/SetupDataRequest-utilization.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/SetupDataRequest-utilization.rng $SCHEMA_DIR/SetupDataRequest-utilization.xsd

for i in 1 2 3 4 5
do
    $JAVA -jar $MSV -warning $SCHEMA_DIR/SetupDataRequest-utilization.rng $INSTANCE_DIR/SetupDataRequest-utilization-$i.xml
    $JAVA -jar $JING $SCHEMA_DIR/SetupDataRequest-utilization.rng $INSTANCE_DIR/SetupDataRequest-utilization-$i.xml
done

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/SetupDataRequest-errors.rnc $SCHEMA_DIR/SetupDataRequest-errors.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/SetupDataRequest-errors.rng $SCHEMA_DIR/SetupDataRequest-errors.xsd

for i in 1 2 3 4 5
do
    $JAVA -jar $MSV -warning $SCHEMA_DIR/SetupDataRequest-errors.rng $INSTANCE_DIR/SetupDataRequest-errors-$i.xml
    $JAVA -jar $JING $SCHEMA_DIR/SetupDataRequest-errors.rng $INSTANCE_DIR/SetupDataRequest-errors-$i.xml
done

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/SetupDataRequest-discards.rnc $SCHEMA_DIR/SetupDataRequest-discards.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/SetupDataRequest-discards.rng $SCHEMA_DIR/SetupDataRequest-discards.xsd

for i in 1 2 3 4 5
do
    $JAVA -jar $MSV -warning $SCHEMA_DIR/SetupDataRequest-discards.rng $INSTANCE_DIR/SetupDataRequest-discards-$i.xml
    $JAVA -jar $JING $SCHEMA_DIR/SetupDataRequest-discards.rng $INSTANCE_DIR/SetupDataRequest-discards-$i.xml
done

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/SetupDataRequest-snmp.rnc $SCHEMA_DIR/SetupDataRequest-snmp.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/SetupDataRequest-snmp.rng $SCHEMA_DIR/SetupDataRequest-snmp.xsd

for i in 1 2 3 4 5
do
    $JAVA -jar $MSV -warning $SCHEMA_DIR/SetupDataRequest-snmp.rng $INSTANCE_DIR/SetupDataRequest-snmp-$i.xml
    $JAVA -jar $JING $SCHEMA_DIR/SetupDataRequest-snmp.rng $INSTANCE_DIR/SetupDataRequest-snmp-$i.xml
done

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/SetupDataRequest-ganglia.rnc $SCHEMA_DIR/SetupDataRequest-ganglia.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/SetupDataRequest-ganglia.rng $SCHEMA_DIR/SetupDataRequest-ganglia.xsd

for i in 1 2 3 4 5
do
    $JAVA -jar $MSV -warning $SCHEMA_DIR/SetupDataRequest-ganglia.rng $INSTANCE_DIR/SetupDataRequest-Ganglia-$i.xml
    $JAVA -jar $JING $SCHEMA_DIR/SetupDataRequest-ganglia.rng $INSTANCE_DIR/SetupDataRequest-Ganglia-$i.xml
done

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/SetupDataResponse-utilization.rnc $SCHEMA_DIR/SetupDataResponse-utilization.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/SetupDataResponse-utilization.rng $SCHEMA_DIR/SetupDataResponse-utilization.xsd

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/SetupDataResponse-errors.rnc $SCHEMA_DIR/SetupDataResponse-errors.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/SetupDataResponse-errors.rng $SCHEMA_DIR/SetupDataReesponse-errors.xsd

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/SetupDataResponse-discards.rnc $SCHEMA_DIR/SetupDataResponse-discards.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/SetupDataResponse-discards.rng $SCHEMA_DIR/SetupDataReesponse-discards.xsd

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/SetupDataResponse-snmp.rnc $SCHEMA_DIR/SetupDataResponse-snmp.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/SetupDataResponse-snmp.rng $SCHEMA_DIR/SetupDataReesponse-snmp.xsd

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/SetupDataResponse-ganglia.rnc $SCHEMA_DIR/SetupDataResponse-ganglia.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/SetupDataResponse-ganglia.rng $SCHEMA_DIR/SetupDataReesponse-ganglia.xsd


# -----

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/DataInfoRequest-utilization.rnc $SCHEMA_DIR/DataInfoRequest-utilization.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/DataInfoRequest-utilization.rng $SCHEMA_DIR/DataInfoRequest-utilization.xsd

for i in 1 2
do
    $JAVA -jar $MSV -warning $SCHEMA_DIR/DataInfoRequest-utilization.rng $INSTANCE_DIR/DataInfoRequest-utilization-$i.xml
    $JAVA -jar $JING $SCHEMA_DIR/DataInfoRequest-utilization.rng $INSTANCE_DIR/DataInfoRequest-utilization-$i.xml
done

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/DataInfoRequest-errors.rnc $SCHEMA_DIR/DataInfoRequest-errors.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/DataInfoRequest-errors.rng $SCHEMA_DIR/DataInfoRequest-errors.xsd

for i in 1 2
do
    $JAVA -jar $MSV -warning $SCHEMA_DIR/DataInfoRequest-errors.rng $INSTANCE_DIR/DataInfoRequest-errors-$i.xml
    $JAVA -jar $JING $SCHEMA_DIR/DataInfoRequest-errors.rng $INSTANCE_DIR/DataInfoRequest-errors-$i.xml
done

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/DataInfoRequest-discards.rnc $SCHEMA_DIR/DataInfoRequest-discards.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/DataInfoRequest-discards.rng $SCHEMA_DIR/DataInfoRequest-discards.xsd

for i in 1 2
do
    $JAVA -jar $MSV -warning $SCHEMA_DIR/DataInfoRequest-discards.rng $INSTANCE_DIR/DataInfoRequest-discards-$i.xml
    $JAVA -jar $JING $SCHEMA_DIR/DataInfoRequest-discards.rng $INSTANCE_DIR/DataInfoRequest-discards-$i.xml
done

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/DataInfoRequest-snmp.rnc $SCHEMA_DIR/DataInfoRequest-snmp.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/DataInfoRequest-snmp.rng $SCHEMA_DIR/DataInfoRequest-snmp.xsd

for i in 1 2
do
    $JAVA -jar $MSV -warning $SCHEMA_DIR/DataInfoRequest-snmp.rng $INSTANCE_DIR/DataInfoRequest-snmp-$i.xml
    $JAVA -jar $JING $SCHEMA_DIR/DataInfoRequest-snmp.rng $INSTANCE_DIR/DataInfoRequest-snmp-$i.xml
done

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/DataInfoRequest-ganglia.rnc $SCHEMA_DIR/DataInfoRequest-ganglia.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/DataInfoRequest-ganglia.rng $SCHEMA_DIR/DataInfoRequest-ganglia.xsd

for i in 1 2
do
    $JAVA -jar $MSV -warning $SCHEMA_DIR/DataInfoRequest-ganglia.rng $INSTANCE_DIR/DataInfoRequest-Ganglia-$i.xml
    $JAVA -jar $JING $SCHEMA_DIR/DataInfoRequest-ganglia.rng $INSTANCE_DIR/DataInfoRequest-Ganglia-$i.xml
done

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/DataInfoResponse-utilization.rnc $SCHEMA_DIR/DataInfoResponse-utilization.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/DataInfoResponse-utilization.rng $SCHEMA_DIR/DataInfoResponse-utilization.xsd

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/DataInfoResponse-errors.rnc $SCHEMA_DIR/DataInfoResponse-errors.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/DataInfoResponse-errors.rng $SCHEMA_DIR/DataInfoReesponse-errors.xsd

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/DataInfoResponse-discards.rnc $SCHEMA_DIR/DataInfoResponse-discards.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/DataInfoResponse-discards.rng $SCHEMA_DIR/DataInfoReesponse-discards.xsd

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/DataInfoResponse-snmp.rnc $SCHEMA_DIR/DataInfoResponse-snmp.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/DataInfoResponse-snmp.rng $SCHEMA_DIR/DataInfoReesponse-snmp.xsd

$JAVA -jar $TRANG -I rnc -O rng $SCHEMA_DIR/DataInfoResponse-ganglia.rnc $SCHEMA_DIR/DataInfoResponse-ganglia.rng
$JAVA -jar $TRANG -I rng -O xsd $SCHEMA_DIR/DataInfoResponse-ganglia.rng $SCHEMA_DIR/DataInfoReesponse-ganglia.xsd

rm -f $SCHEMA_DIR/*xsd $SCHEMA_DIR/*rng
