#!/bin/sh

LIB=./lib
JDIR=/usr/lib/jvm/java-1.5.0-sun/bin
JAVA=$JDIR/java
JAVAC=$JDIR/javac
DOT=/usr/bin/dot
CP=.

for i in `ls $LIB | grep .jar$`
do
  CP=$CP:$LIB/$i
done

$JAVAC -cp $CP Convert.java
$JAVA -cp $CP Convert topo.xml convert.xsl > output.dot
$DOT output.dot -Tpng > output.png


