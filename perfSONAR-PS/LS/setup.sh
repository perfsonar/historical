#!/bin/sh

rm -frd xmldb
mkdir xmldb

../util/loadXMLDB.pl --verbose --environment=./xmldb/ --container=store.dbxml --filename=./store.xml 

../util/loadXMLDB.pl --verbose --environment=./xmldb/ --container=control.dbxml --filename=./control.xml 

