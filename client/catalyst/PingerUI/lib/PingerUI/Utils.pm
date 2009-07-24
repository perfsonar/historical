package PingerUI::Utils;
use strict;
use warnings;
use English qw( -no_match_vars );
use version; our $VERSION = '3.2';

=head1 NAME

     
    PingerUI::Utils  - package with several auxiliary functions

=head1 DESCRIPTION

       
   Utils  module is supplemental for  pigner gui
      
=head1 EXPORTED 

=cut

use Exporter (); 
use base qw(Exporter);
our @EXPORT = ();
our @EXPORT_OK = qw(check_time isParam   updateNodeId updateDomainId get_links_ends get_params_obj %pinger_keys 
                    get_time_hash findNode max min URNBASE  validURL getURL csv2xml_landmarks fix_regexp);
use Time::Local; 
use POSIX qw(strftime);  
use Date::Manip;
use Data::Dumper;
use File::Slurp qw( slurp ) ;
use aliased 'perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::pingertopo::Topology';
use aliased 'perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::pingertopo::Topology::Domain';
use aliased 'perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::nmtb::Topology::Domain::Node::Description';
use aliased 'perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::pingertopo::Topology::Domain::Node';
use aliased 'perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::nmtb::Topology::Domain::Node::Name';
use aliased 'perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::nmtb::Topology::Domain::Node::HostName';
use aliased 'perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::nmwg::Topology::Domain::Node::Parameters';
use aliased 'perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::nmwg::Topology::Domain::Node::Parameters::Parameter';
use aliased 'perfSONAR_PS::PINGERTOPO_DATATYPES::v2_0::nmtl3::Topology::Domain::Node::Port';
use Text::CSV_XS;
use JSON::XS;
use perfSONAR_PS::Utils::DNS qw/reverse_dns resolve_address/;
use constant URNBASE => 'urn:ogf:network'; 

our %pinger_keys = (packetSize => '1000', count => '10',  packetInterval => '1', ttl => '255',
                       measurementPeriod => '60', measurementOffset => '0', project => 'USCMS');
our %dns_cache= ();
our %reverse_dns_cache = ();



=head2 get_links_ends 

    set $c->stash->{projects} and $c->stash->{project_table} with remote based on GLS pinger metadata
   returns arrray ref
   
=cut

sub get_links_ends {
    my $c = shift;
    my @tmp = ();
    if(-e  $c->config->{gls_cache}) {
        my $string =  slurp($c->config->{gls_cache}, err_mode => 'croak');
	return unless $string; 	 
	#$c->log->debug(" JSON:: $string ");
        my $data_struct = decode_json $string;
	foreach my $ma (@{$data_struct}) {
	    my $url;
   	    foreach my $key (keys %{$ma}) {
	        if($key !~ /^(name|type|desc|keywords)/) {
		   $url =  $key;
		   last;
		}
	    }
	    my ($domain) =  $url  =~ /http\:\/\/([^\/]+)\//xsm;
            $ma->{desc}  =~ s/^.+\ at\ (.+)$/$1/xsm;
            if($ma->{keywords} && ref $ma->{keywords} eq 'ARRAY') {
	         foreach my $keyword (@{$ma->{keywords}}) {
		      $keyword =~ s/^project\://;
		      $c->stash->{projects}{$url}{'ALL PROJECTS'}++;
                      $c->stash->{projects}{$url}{$keyword}++;
		      push @{$c->stash->{project_table}{$keyword}}, $url;
		      push @{$c->stash->{project_table}{'ALL PROJECTS'}}, $url; 
		 }
	     }
	     if(!$c->stash->{filter_project} ||
	         ($c->stash->{filter_project} && 
		  $c->stash->{project_table}{$c->stash->{filter_project}})) {
		  $c->stash->{remote_ma}{$url} = $ma->{$url} if exists $c->stash->{remote_ma}{$url} &&
		                                               $ma->{$url} && 
							       ref $ma->{$url} eq 'HASH' && 
							       %{$ma->{$url}};
   	        push  @tmp, {url => $url, url_label => $ma->{desc} . "($domain)"} if $url;
	     } 
        }
    }
    return \@tmp;
}

 
=head2 csv2xml_landmarks

   convert CSV landmarks file int othe XML

=cut

sub csv2xml_landmarks {
    my ($clog, $file) = @_;
    my  %options;
 
    ### parameter position in the row 
    my %lookup_row = (description => 4, packetSize => 5, count =>  6,  packetInterval => 7, ttl => 8,
                       measurementPeriod => 9, measurementOffset => 10, project => 11);
    my $io_file = IO::File->new($file);
    my $csv_obj = Text::CSV_XS->new ();  
    my $landmark_obj = Topology->new();
    (my $xml_file = $file) =~ s/\.csv$/\.xml/i;
    my $num = 1;
    while(my $row = $csv_obj->getline($io_file)) {
	unless($row->[0] && $row->[1] && ($row->[2] || $row->[3])) {
	   $clog->error(" Skipping Malformed row: domain=$row->[0]  node=$row->[1] hostname=$row->[2] ip=$row->[3]");
	   next;
	} 
	check_row($row, \%lookup_row ); 
	my $domain_id = URNBASE . ":domain=$row->[0]";
	my $domain_obj = $landmark_obj->getDomainById($domain_id);
	unless($domain_obj) {
    	    $domain_obj = Domain->new({id => $domain_id});
	    $landmark_obj->addDomain($domain_obj);		      
	}   
	my $node_id =  "$domain_id:node=$row->[1]";
	my $node_obj =  $domain_obj->getNodeById($node_id);
	$domain_obj->removeNodeById($node_id)  if($node_obj);
	eval {
     	     $node_obj = Node->new({
    				 id =>  $node_id,
				 name =>  Name->new(  { type => 'string', text =>  $row->[1]} ),
				 hostName =>  HostName->new( { text => $row->[2] } ),   
				 description => Description->new( { text => $row->[4] }),
    				 port =>  Port->new(
    					     { xml =>  qq{
    <nmtl3:port xmlns:nmtl3="http://ogf.org/schema/network/topology/l3/20070707/" id="$node_id:port=$row->[3]">
	<nmtl3:ipAddress type="IPv4">$row->[3]</nmtl3:ipAddress>
    </nmtl3:port>
    }
    					     }
    				       ),
    				parameters =>  get_params_obj({packetSize => $row->[5], 
				                               count =>$row->[6],
							       packetInterval=>$row->[7],
							       ttl=>$row->[8],
							       measurementPeriod=>$row->[9],
							       measurementOffset=>$row->[10],
							       project=>$row->[11]}, 
							       "paramid$num")
			    });
    	      $domain_obj->addNode($node_obj);
	      $num++;
	};
	if($EVAL_ERROR) {
    	    $clog->fatal(" Node create failed $EVAL_ERROR");
	}
    }
    my $fd  = new IO::File(">$xml_file")  or $clog->fatal( "Failed to open file $xml_file" . $! );
    eval {
        print $fd $landmark_obj->asString;
        $fd->close;   
    };
    if($EVAL_ERROR) {
        die $clog->fatal( "Failed to store $xml_file landmarks file  $EVAL_ERROR ");
    }
    return $xml_file;
}

=head2 get_params_obj
   
      build Parameters object and set defaults

=cut

sub get_params_obj {
    my ($params, $id) = @_;    
    my $obj = Parameters->new({ id =>  $id });
    foreach my $key (keys %pinger_keys){
        my $value = $params && $params->{$key}?$params->{$key}:$pinger_keys{$key};
        $obj->addParameter(Parameter->new({name => $key, value => $value}));
    }
    return $obj;
}
 
=head2 check_row 

     set missing values from defaults, resolve DNS name or IP address

=cut

sub check_row {
    my( $row,  $lookup_row_h) = @_;
    unless($row->[2]) {
        unless($reverse_dns_cache{$row->[3]}) {
            $row->[2] = reverse_dns($row->[3]);
	     $reverse_dns_cache{$row->[3]} =  $row->[2];
        } else {
	    $row->[2] = $reverse_dns_cache{$row->[3]}; 
	}
    }
    unless($row->[3]) {
        unless($dns_cache{$row->[2]}) {
            ($row->[3]) =  resolve_address($row->[2]);
            $dns_cache{$row->[2]} =  $row->[3];
        } else {
	    $row->[3] = $dns_cache{$row->[2]};
	}
    }
    foreach my $key (keys %{$lookup_row_h}) {
        $row->[$lookup_row_h->{$key}] = $pinger_keys{$key}  unless $row->[$lookup_row_h->{$key}];
    }
}

 

=head2 updateDomainId 

  updates domain id and everything inside of domain element ( nodes id , ports  id )

=cut

sub updateDomainId {
    my ( $domain_obj, $new_domain_urn ) = @_;
    my ($domain_part) = $new_domain_urn =~ /domain\=([^\:]+)/;
    $domain_obj->set_id($new_domain_urn);
    foreach my $in_node ( @{ $domain_obj->get_node } ) {
        my $node_id = $in_node->get_id;
        $node_id =~ s/domain\=([^\:]+)\:/domain\=$domain_part\:/;
        $in_node->set_id($node_id);
        my $port    = $in_node->get_port;
        my $port_id = $port->get_id;
        $port_id =~ s/domain\=([^\:]+)\:/domain\=$domain_part\:/;
        $port->set_id($port_id);
    }
    return $domain_obj;
}

=head2 updateNodeId 

  updates   node  id , port   id 

=cut

sub updateNodeId {
    my ( $node_obj, $new_node_urn ) = @_;
    my ($node_part) = $new_node_urn =~ /node\=([^\:]+)/;
    $node_obj->set_name( Name->new( { type => 'string', text => $node_part } ) );
    $node_obj->set_id($new_node_urn);
    my $port    = $node_obj->get_port;
    my $port_id = $port->get_id;
    $port_id =~ s/node\=([^\:]+)\:/node\=$node_part\:/;
    $port->set_id($port_id);
    ##$node_obj->port($port);
    return $node_obj;
}

=head2 findNode

   find node by domain urn and nodename or urn, returns $domain, $node pair
   
=cut

sub findNode {
    my ($topology, $params, $clog) = @_;
    if ( $params && ( ref $params ne 'HASH' || !( $params->{urn} || ( $params->{domain} && $params->{name} ) ) ) ) {
        $clog->fatal(" Failed, only hashref parmaeter is accepted and 'domain' and 'urn' or 'name' must be supplied" . Dumper $params);
    }
    my ( $domain_query, $node_query ) = ( $params->{domain}, $params->{name} );
    if ( $params->{urn} ) {
        ( $domain_query, $node_query ) = $params->{urn} =~ /^.+\:domain\=([^\:]+)\:node\=(.+)$/;
    }
    foreach my $domain ( @{ $topology->get_domain } ) {
        my $id =  $domain->get_id;
	$clog->debug(" FIND NODE: $domain_query = $node_query = $id  ");
        my ($domain_part) = $domain->get_id =~ /domain\=([^\:]+)$/;
        if ( $domain_part eq $domain_query ) {
            foreach my $node ( @{ $domain->get_node } ) {
                my ($node_part) = $node->get_id =~ /node\=([^\:]+)$/;
                $clog->debug(" quering for ::  $domain_query :: $node_query ---> $domain_part :: $node_part ");
                if ( $node_part eq $node_query ) {
                    $clog->debug(" Found node");
                    return ( $domain, $node );
                }
            }
            return;
        }
    }
    return;
}


=head2  isParam 

  returns true if argument string among supported pigner test parameters
  otherwise returns undef

=cut

sub  isParam  {
    my ($name) = @_;
    return 1 if $name =~ /^(packetSize|count|packetInterval|measurementPeriod|ttl|measurementOffset|ipAddress|type|hostName)/;
    return;
}
 


=head2 validURL 

    parse Ma url, return  1 if URL is valid and undef otherwise

=cut

sub validURL {
    my ($remote_ma) = @_;
    return 0 unless $remote_ma;
    my ($server,$port,$endpoint) = $remote_ma =~ m/http:\/\/([^:\/]+):?(\d+)?(\/.+)$/is;
    return 1 if($server && $endpoint);
    return 0;
}
  
=head2 fix_regexp
 
   fixing regular expression for link names from list_pars.txt file

=cut

sub fix_regexp {
  my $reg_exp = shift;
   unless($reg_exp) {
      return undef;
    }

    #escape all meta characters
    $reg_exp =~ s/([^A-Za-z0-9_])/\\$1/g;

    #except for *, translate it to .*
    $reg_exp =~ s/(\\\*)/\.\*/g;
    $reg_exp =~ s/(\\)([\^\$])/$2/g;
    
    return qr{$reg_exp};
}

=head2 getURL 
 
   get URL by the link ID from the stash

=cut
 
sub getURL {
   my ($stash, $link) = @_;
    # $c->log->debug(" Looking for MA URL:  $link  - \n", sub{Dumper($LINKS )});
   foreach my $url (keys %{$stash}) {
        return $url if($stash->{$url}{$link});
   }
   return;

}


=head2 get_time_hash

  accepts time start and time end in epoch
  and returns time hash:
    $tm_hash{start_month}
    $tm_hash{end_month}
    $tm_hash{start_year}
    $tm_hash{end_year}
    $tm_hash{start_day}
    $tm_hash{end_day} 

=cut

sub get_time_hash {
    my($tm_s, $tm_d) = @_;
    my %tm_hash;
    $tm_hash{start_month} =  strftime "%m", gmtime($tm_s);
    $tm_hash{end_month} = strftime "%m", gmtime($tm_d);
    $tm_hash{start_year} =  strftime "%Y", gmtime($tm_s);
    $tm_hash{end_year} =  strftime "%Y", gmtime($tm_d);
    $tm_hash{start_day} = strftime "%d", gmtime($tm_s);
    $tm_hash{end_day} = strftime "%d", gmtime($tm_d);
    return \%tm_hash;
    
}

=head2 check_time 

    accepts  time start and time end as trings and GMT offset as string
    returns time start , time end as epoch and gmt as positive/negative offset in seconds 
    and GMT label with sign 
   
=cut


sub check_time {
    my($clog, $start_time,  $end_time, $gmt_off) = @_;
        
    (my $ret_gmt = $gmt_off) =~ s/(curr)?//;
    if($ret_gmt && $ret_gmt > 0) {
        $ret_gmt = 'GMT+' . $ret_gmt ;
    } else {
        $ret_gmt = 'GMT' . $ret_gmt;
    }
    $gmt_off =~ s/(curr)?//g;
    $gmt_off = 0 unless $gmt_off;
    if($gmt_off) {
        $gmt_off *= 3600;
    }  
    my($tm_s, $tm_d);
    eval {
        $tm_s = UnixDate(ParseDate(" $start_time") , "%s");
        $tm_d = UnixDate(ParseDate("$end_time"), "%s");
    };
    if($EVAL_ERROR) {
        $clog->fatal("   ParseDate failed to parse: $start_time  $end_time". $EVAL_ERROR);
    }
   
    return ($tm_s, $tm_d,  $gmt_off, $ret_gmt);
}

=head2 max

    maximum function

=cut

sub max {
  return   $_[0] > $_[1] ? $_[0] : $_[1]; 
}

=head2 min

  minimum  function

=cut

sub min {
  return  $_[0] < $_[1] ? $_[0] : $_[1] ;

}
 
1;


__END__


=head1   AUTHOR

    Maxim Grigoriev, 2001-2009, maxim_at_fnal_dot_gov
         

=head1 COPYRIGHT

Copyright (c) 2009, Fermi Research Alliance (FRA)

=head1 LICENSE

You should have received a copy of the Fermitool license along with this software.
 
 
   

=cut

