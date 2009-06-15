
This directory contains programs and configuration files to test your perfSONAR
installation using a set of test data.

You can run this test harness against an existing service, or you can start
  the test services included in the "test-services" directory.

See instructions below for starting the test services

Sample use with existing services:
    setenv PSHOME /path/to/perfSONAR-PS
    test_PS.py -u http://mea1.es.net:8080/perfSONAR_PS/services/snmpMA -c snpmMA-test-config.xml
    test_PS.py -u http://dc200.internet2.edu:8081/perfSONAR_PS/services/LS -c LS-test-config.xml
    test_PS.py -u http://dc211.internet2.edu:8080/perfSONAR_PS/services/perfSONARBOUY -c psBOUY-test-config.xml
    test_PS.py -u http://stats.geant2.net/perfsonar/RRDMA-access/MeasurementArchiveService -c snpmMA-test-config.xml
    test_PS.py -u http://fnal-owamp.es.net:8075/perfSONAR_PS/services/pinger/ma -c pinger-test-config.xml



See snpmMA-test-config.xml for notes on how to build the test config file

-----------------------------------------------------------

To start the sample services

  setenv PSHOME /path/to/perfSONAR
  build fake data and store file
     cd test-MS-LS
     perl store_gen.pl 1000   # store file with 1000 entries
  depending on installation location, link PSHOME to test_harness
  ln -s $PSHOME /path/to/test_harness
  make directory to store LS db
     mkdir $PSHOME/db
  start perfSONAR
     ./start-perfSONAR.sh


Test perfSONARBUOY service
     coming soon


Test pingER-MA service
     coming soon
