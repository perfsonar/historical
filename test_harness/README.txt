
This directory contains programs and configuration files to test your perfSONAR
installation using a set of test data.

Instructions

Test snmpMA and LS

  setenv PSHOME /path/to/perfSONAR
  build fake data and store file
     cd test-MS-LS
     perl store_gen.pl 1000   # store file with 1000 entries
  start perfSONAR
     edit the line for metadata_db_name for your install location in perfSONAR.conf
     ./start-perfSONAR

  run test
     edit requestDir in  ps-test-config.xml for your installation location
     ./test_PS.py


Test perfSONARBUOY
     coming soon



Test pingERMA
     coming soon
