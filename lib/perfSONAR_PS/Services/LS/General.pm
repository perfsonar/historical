package perfSONAR_PS::Services::LS::General;

our $VERSION = 0.02;

use warnings;
use Exporter;
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Common;

@ISA = ('Exporter');
@EXPORT = ('wrapStore', 'createControlKey', 'createLSKey', 'createLSData',
           'extractQuery', 'cleanLS');


sub wrapStore {
  my($content, $type) = @_;
  my $store = "<nmwg:store xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"";
  if(defined $type and $type ne "") {   
    $store = $store . " type=\"".$type."\" "; 
  }
  if(defined $content and $content ne "") {   
    $store = $store . ">\n";
    $store = $store . $content;
    $store = $store . "</nmwg:store>\n";
  }
  else {
    $store = $store . "/>\n";
  }
  return $store;
}


sub createControlKey {
  my($key, $time) = @_;
  my $keyElement = "  <nmwg:metadata id=\"".$key."-control\" metadataIdRef=\"".$key."\" xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\">\n";
  $keyElement = $keyElement . "    <nmwg:parameters id=\"control-parameters\">\n";
  $keyElement = $keyElement . "      <nmwg:parameter name=\"timestamp\">\n";
  $keyElement = $keyElement . "        <nmtm:time type=\"unix\" xmlns:nmtm=\"http://ggf.org/ns/nmwg/time/2.0/\">".$time."</nmtm:time>\n";
  $keyElement = $keyElement . "      </nmwg:parameter>\n";
  $keyElement = $keyElement . "    </nmwg:parameters>\n";
  $keyElement = $keyElement . "  </nmwg:metadata>\n";
  return wrapStore($keyElement, "LSStore-control");
}


sub createLSKey {
  my($key, $eventType) = @_;
  my $keyElement = "";
  $keyElement = $keyElement . "      <nmwg:key xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\" id=\"key.".genuid()."\">\n";
  $keyElement = $keyElement . "          <nmwg:parameters id=\"param.".genuid()."\">\n";
  $keyElement = $keyElement . "            <nmwg:parameter name=\"lsKey\">".$key."</nmwg:parameter>\n";
  $keyElement = $keyElement . "          </nmwg:parameters>\n";
  $keyElement = $keyElement . "        </nmwg:key>\n";
  $keyElement = $keyElement . "        <nmwg:eventType>".$eventType."</nmwg:eventType>\n";
  return $keyElement;
}


sub createLSData {
  my($dataId, $metadataId, $data) = @_;
  my $dataElement = "    <nmwg:data xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\" id=\"".$dataId."\" metadataIdRef=\"".$metadataId."\">\n";
  $dataElement = $dataElement . "      " . $data . "\n";
  $dataElement = $dataElement . "    </nmwg:data>\n";
  return wrapStore($dataElement, "LSStore");
}


sub extractQuery {
  my($node) = @_;
  my $query = "";
  if($node->hasChildNodes()) {
    foreach my $c ($node->childNodes) {
      if($c->nodeType == 3) {
        $query = $query . $c->textContent;
      }
      else {
        $query = $query . $c->toString;
      }
    }
  }
  return $query;
}


sub cleanLS {
  my($conf, $ns, $dirname) = @_;
  my $logger = get_logger("perfSONAR_PS::LS::LS");

  if(defined $dirname) {
    if(!($conf->{"METADATA_DB_NAME"} =~ "^/")) {
      $conf->{"METADATA_DB_NAME"} = $dirname."/".$conf->{"METADATA_DB_NAME"};
    }
  }

  my $error = "";
  my $metadatadb = new perfSONAR_PS::DB::XMLDB(
    $conf->{"METADATA_DB_NAME"}, 
    $conf->{"METADATA_DB_FILE"},
    \%{$ns}
  );    
  $metadatadb->openDB("", \$error); 
  $logger->error($error) if $error;
  if($error) {
    return;
  }

  my($sec, $frac) = Time::HiRes::gettimeofday;
  my $dbTr = $metadatadb->getTransaction(\$error);
  if($dbTr and !$error) {
    my $errorFlag = 0;
  
    my $dbError;
    my @resultsString = $metadatadb->query("/nmwg:store[\@type=\"LSStore-control\"]/nmwg:metadata", $dbTr, \$dbError);   
    $logger->error($error) and $errorFlag = 1 if $error;
    if($#resultsString != -1) {
      for(my $x = 0; $x <= $#resultsString; $x++) {  
        my $parser = XML::LibXML->new();
        my $doc = $parser->parse_string($resultsString[$x]);  

        my $time = extract(find($doc->getDocumentElement, "./nmwg:parameters/nmwg:parameter[\@name=\"timestamp\"]/nmtm:time[text()]", 1), 1);
        if($time =~ m/^\d+$/) {
          my $key = $doc->getDocumentElement->getAttribute("id");
          $key =~ s/-control$//;
          if($time and $key and $sec >= $time) {
            my @resultsString2 = $metadatadb->queryForName("/nmwg:store[\@type=\"LSStore\"]/nmwg:data[\@metadataIdRef=\"".$key."\"]", $dbTr, \$error);   
            $logger->error($error) and $errorFlag = 1 if $error;
            for(my $x = 0; $x <= $#resultsString2; $x++) {
              $logger->debug("Removing data \"".$resultsString2[$x]."\".");
              $metadatadb->remove($resultsString2[$x], $dbTr, \$error);
              $logger->error($error) and $errorFlag = 1 if $error;
            }      
            $logger->debug("Removing control info \"".$key."-control\".");
            $metadatadb->remove($key."-control", $dbTr, \$error);
            $logger->error($error) and $errorFlag = 1 if $error;
               
            $logger->debug("Removing service info \"".$key."\".");
            $metadatadb->remove($key, $dbTr, \$dbError);        
            $logger->error($error) and $errorFlag = 1 if $error;
          }
        }
        else {
          $logger->error("Time value not found in control metadata.");
        }
      } 
    }
    
    $metadatadb->commitTransaction($dbTr, \$error);
    undef $dbTr;
    if($errorFlag) {
      $logger->error("Database Error: \"" . $error . "\".");                
      $metadatadb->abortTransaction($dbTr, \$error) if $dbTr;
      undef $dbTr;
    }     
    else {
      $logger->debug("Finishing Reaper.");
    }
  }
  else { 
    $logger->error("Cound not start database transaction.");
    $metadatadb->abortTransaction($dbTr, \$error) if $dbTr;
    undef $dbTr;
  }  
  
  return;
}


1;


__END__
=head1 NAME

perfSONAR_PS::LS::General -  - A module that provides methods for general tasks that LSs need to 
perform.

=head1 DESCRIPTION

This module is a catch all for common methods (for now) of :Ss in the perfSONAR-PS framework.  
As such there is no 'common thread' that each method shares.  This module IS NOT an object, 
and the methods can be invoked directly (and sparingly). 

=head1 SYNOPSIS

    use perfSONAR_PS::LS::General;
    use Time::HiRes qw(gettimeofday tv_interval);
    
    my $type = "LSStore";
    my $store = wrapStore("<nmwg:data />", $type);

    my $t0 = [Time::HiRes::gettimeofday];  
    my $key = "http://localhost:8080/perfSONAR_PS/services/LS";
    my $controlKey = createControlKey($key, $t0->[0].".".$t0->[1]);

    my $lsKey = createLSKey($key, "success.ls.registration");

    my $lsData = createLSData($dataId, $metadataId, $data);
        
    # Let $node be an XML::LibXML Node:
    #
    #  <xquery:subject id="sub2">
    #    declare namespace nmwg="http://ggf.org/ns/nmwg/base/2.0/";
    #    declare namespace perfsonar="http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/";
    #    declare namespace psservice="http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/";
    #    declare namespace xquery="http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xquery/1.0/";
    #    for $metadata in /nmwg:store/nmwg:metadata
    #      let $metadata_id := $metadata/@id
    #      let $data := /nmwg:store/nmwg:data[@metadataIdRef=$metadata_id]
    #      where $metadata//psservice:accessPoint[
    #        text()="http://localhost:8181/axis/services/snmpMA" or
    #        @value="http://localhost:8181/axis/services/snmpMA"]
    #        return <nmwg:stuff>{$metadata} {$data}</nmwg:stuff>
    #  </xquery:subject>
    
    my $query = extractQuery($node);
    
    cleanLS(\%conf, \%ns);

=head1 DETAILS

The API for this module aims to be simple; note that this is not an object and 
each method does not have the 'self knowledge' of variables that may travel 
between functions.  

=head1 API

The offered API is basic for now, until more common features to LSs can be identified
and utilized in this module.

=head2 wrapStore($content, $type)

Adds 'store' tags around some content.  This is to mimic the way eXist deals
with storing XML data.  The 'type' argument is used to type the store file.

=head2 createControlKey($key, $time)

Creates a 'control' key for the control database that keeps track of time.

=head2 createLSKey($key, $eventType)

Creates the 'internals' of the metadata that will be returned w/ a key.

=head2 createLSData($dataId, $metadataId, $data)

Creates a 'data' block that is stored in the backend storage. 

=head2 extractQuery($node)

Pulls out the COMPLETE contents of an XQuery subject, this also includes sub elements. 

=head2 cleanLS($conf, $ns, $dirname)

Performs an LS cleaning.  

=head1 SEE ALSO

L<Exporter>, L<Log::Log4perl>, L<perfSONAR_PS::Common>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list.  Bugs,
feature requests, and improvements can be directed here:

  https://bugs.internet2.edu/jira/browse/PSPS

=head1 VERSION

$Id$

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework along 
with this software.  If not, see <http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2004-2007, Internet2 and the University of Delaware

All rights reserved.

=cut

