#!/usr/local/bin/perl -w
 use lib qw(../lib);
 use warnings;
 use strict; 
 use File::Path;
 use Config::Interactive;
 
 
 
 BEGIN {
    use Log::Log4perl qw(get_logger);   
    Log::Log4perl->init("../bin/logger.conf"); 
 };
 use   version;

 use   perfSONAR_PS::DataModels::PingER_Topology  2.0 qw($pingertopo);        
 use   perfSONAR_PS::DataModels::PingER_Model 2.0 qw($message);
 use   perfSONAR_PS::DataModels::APIBuilder   2.0 qw(&buildAPI  $API_ROOT $TOP_DIR $SCHEMA_VERSION $DATATYPES_ROOT $TEST_DIR);
    
   
   my $logger = get_logger("pinger_schema");
  
   my %CONF_PROMPTS = (   "METADATA_DB_TYPE" => "type of the internal metaData DB ( file| xmldb | sql ) ", 
                          "METADATA_DB_NAME" => " name of the internal   metaData  DB ", 
			  'TOP_DIR' =>    '  top directory   where to build API ',
			  'API_ROOT'=>   ' root package name for the API', 
			  'TEST_DIR' => ' top directory  where to build tests files ', 
			  'DATATYPES_ROOT' => ' top directory name where to place versioned datatypes API',  
			 
		      );

		# Read in configuration information
 
#
#   pinger configuration part is here
# 
  my $pingerMA_conf =  Config::Interactive->new( { file=> 'pingerMA_model.conf', 
                                                   prompts   => \%CONF_PROMPTS, 
						   dialog => '1'
						 }
					       );
  $pingerMA_conf->parse();  
  $pingerMA_conf->store;
  my $configh =$pingerMA_conf->getNormalizedData;
   
  #####  API root dir and root package name 
  $API_ROOT = $configh->{API_ROOT};
  #####  API root dir and root package name 
  $DATATYPES_ROOT =  $configh->{DATATYPES_ROOT};
  
  ##### schema version will be set as part of the built API pathname
  #
  $SCHEMA_VERSION =     perfSONAR_PS::DataModels::DataModel->VERSION; 
  #   to   format version as vX_XX 
  $SCHEMA_VERSION  =~ s/\./_/g;
  
  $TOP_DIR = $configh->{"TOP_DIR"}; 
  #   $TOP_DIR = "/tmp/API/"; 
  $TEST_DIR = $configh->{"TEST_DIR"};
  
  mkpath ([ "$TOP_DIR"  ], 1, 0755) ; 
  $TOP_DIR .=  $API_ROOT;  
  eval {
      buildAPI('message', $message,  '', '' )
  };
  if($@) {
       $logger->fatal(" Building API failed " . $@);
  }
  eval {
      buildAPI('topology', $pingertopo,  '', '', '' )
  };
   if($@) {
      $logger->fatal(" Building Topology API failed " . $@);
  }
