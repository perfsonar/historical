#!/bin/bash
java -Xmx256m -Djava.net.preferIPv4Stack=true -jar target/psTopoPuller-0.0.1-SNAPSHOT.one-jar.jar  $*
