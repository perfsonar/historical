#!/bin/bash
java -Xmx256m -Djava.net.preferIPv4Stack=true -jar target/TSJavaClient-0.0.1-SNAPSHOT.one-jar.jar  $*
