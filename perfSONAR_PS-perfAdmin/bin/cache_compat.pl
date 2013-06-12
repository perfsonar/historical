#!/usr/bin/perl

use strict;

use Getopt::Long;
use Config::General;
use URI::URL;

use Data::Validate::IP qw(is_ipv4 is_ipv6 );
use Socket qw(inet_pton AF_INET AF_INET6);
use Net::DNS;
  
my $CONFIG_FILE;
my $LOGGER_CONF;
my $DEBUGFLAG;
my $HELP;

# Parse command-line options
my $status = GetOptions(
    'config=s'  => \$CONFIG_FILE,
    'logger=s'  => \$LOGGER_CONF,
    'verbose'   => \$DEBUGFLAG,
    'help'      => \$HELP
);


#Read config file
if( not $CONFIG_FILE ){
    print "Error: no configuration file specified\n";
    exit( -1 );
}
my %conf = Config::General->new( $CONFIG_FILE )->getall();

#Load logging configuration
my $logger;
if(not defined $LOGGER_CONF or $LOGGER_CONF eq q{}){
    use Log::Log4perl qw(:easy);
    my $output_level = $INFO;
    if ( $DEBUGFLAG ) {
        $output_level = $DEBUG;
    }
    my %logger_opts = (
        level  => $output_level,
        layout => '%d (%P) %p> %F{1}:%L %M - %m%n',
    );
    Log::Log4perl->easy_init( \%logger_opts );
    $logger = get_logger( "perfSONAR_PS" );
}else{
    use Log::Log4perl qw(get_logger :levels);
    my $output_level = $INFO;
    if ( $DEBUGFLAG ) {
        $output_level = $DEBUG;
    }
    Log::Log4perl->init( $LOGGER_CONF );
    $logger = get_logger( "perfSONAR_PS" );
    $logger->level( $output_level ) if $output_level;
}

#Verify options in config file
if(!$conf{output_file}){
    print "Error: no output_file option specified in $CONFIG_FILE\n";
    exit( -1 );
}

if(!$conf{cache}){
    print "Error: no cache block specified in $CONFIG_FILE\n";
    exit( -1 );
}

if(!$conf{cache}{directory}){
    print "Error: no directory specified in <cache> block of $CONFIG_FILE\n";
    exit( -1 );
}

my $service_confs = $conf{cache}{service};
if(!$service_confs){
    $logger->error( "No serviced defined in <cache> block of configuration file" );
    exit( -1 );
}

if( ref( $service_confs ) ne "ARRAY" ) {
    my @tmp = ();
    push @tmp, $service_confs;
    $service_confs = \@tmp;
}

my $ma_tests_confs = $conf{cache}{ma_tests};
if( !$ma_tests_confs || ref($ma_tests_confs ) ne "ARRAY" ) {
    my @tmp = ();
    push @tmp, $ma_tests_confs;
    $ma_tests_confs = \@tmp;
}

#initialize host list
my $hosts = {};

#Iterate through MA tests building new configuration file
my %ma_tests = ();
foreach my $ma_tests_conf(@{$ma_tests_confs}){
     if(!$ma_tests_conf->{filename}){
        print "Error: no filename specified in <ma_test> block of $CONFIG_FILE\n";
        exit( -1 );
    }
    
    my $abs_filename = $conf{cache}{directory} . '/' . $ma_tests_conf->{filename};
    open(my $fh, "<", "$abs_filename") or die("Unable to open $abs_filename: $!");
    print "$abs_filename\n";
    while(<$fh>){
        chomp;
        next unless($_);
        my @line = split('\|', $_);
        if(@line < 5){
            next;
        }
        if(!$ma_tests{$line[1]}){
            my @tmp = ();
            $ma_tests{$line[1]} = \@tmp;
        }
        my $source_host_obj = &find_host($line[2], $hosts);
        my $destination_host_obj = &find_host($line[3], $hosts);
        push @{$ma_tests{$line[1]}}, {
                event_type => $line[0],
                source => $source_host_obj->{interface}->{address},
                source_if_name => $source_host_obj->{interface}->{if_name},
                destination => $destination_host_obj->{interface}->{address},
                destination_if_name => $destination_host_obj->{interface}->{if_name},
            };
        
    }
}

#Iterate through services building new configuration file
my @sites = ();
foreach my $service_conf(@{$service_confs}){
    if(!$service_conf->{filename}){
        print "Error: no filename specified in <service> block of $CONFIG_FILE\n";
        exit( -1 );
    }
    if(!$service_conf->{type}){
        print "Error: no type specified in <service> block of $CONFIG_FILE\n";
        exit( -1 );
    }
    
    my $abs_filename = $conf{cache}{directory} . '/' . $service_conf->{filename};
    open(my $fh, "<", "$abs_filename") or die("Unable to open $abs_filename: $!");
    print "$abs_filename\n";
    while(<$fh>){
        chomp;
        next unless($_);
        
        #Format keywords by splitting on comma and removing "project" prefix
        my @line = split('\|', $_);
        my @keywords = ();
        if(@line >= 5){
            $line[4] =~ s/project://g;
            @keywords = split(',', $line[4]);
        }
        
        #format address by splitting out port 
        my $address = $line[0];
        my $host, my $port;
        #hack to make sure we can extract the host and port part.
        $address =~ s/^\w+:\/\///g; #remove any prefix
        if($address =~ /:.*:/){
            ($host, $port) = split (']:', $address);
            $host =~ s/\[//g;
        }else{
            ($host, $port) = split (':', $address);
        }
        $port = $1 if($port =~ /^(\d+)/);
        print "Looking at host $host\n";
        
        #Create site object which is how LS Registration Daemon organizes things
        # 1-to-1 mapping between sites and services currently
        my $host_obj = &find_host($host, $hosts);
        my %tmp_service = (
            type => $service_conf->{type},
            service_name => $service_conf->{type} . ":" . $host, 
            address => $host,
            host => $host_obj->{name},
        );
        $tmp_service{port} = $port if($port);
        if($service_conf->{type} eq 'ma' && $ma_tests{$line[0]}){
            foreach my $ma_test(@{$ma_tests{$line[0]}}){
                $tmp_service{test} = () if(!$tmp_service{test});
                push @{$tmp_service{test}},  $ma_test; 
            }
        }
        my %tmp_site = (
            site_project => \@keywords,
            service => \%tmp_service
        );
        push @sites, \%tmp_site;
    }
    close fh;
}

#add all the hosts to the config
my @host_obj_list = ();
foreach my $host_obj(keys %{$hosts}){
    push @host_obj_list, $hosts->{$host_obj};
}
my %tmp_site = (
    host => \@host_obj_list
);
unshift @sites, \%tmp_site;

#Output the new config file
my $output_hash = {
    site => \@sites
};
my $output_config = Config::General->new( $output_hash );
$output_config->save_file($conf{output_file});


##
# Adds a host to the map by looking up all the addresses
sub find_host {
    my($input_name, $hosts) = @_;
    my @addresses = ();
    
     #Create DNS resolver
    my $dnsRes = Net::DNS::Resolver->new(tcp_timeout => 5, udp_timeout => 5);
    
    my %addr_info = (dns => '' , ipv4 => '' , ipv6=> '', cnames => []);
    #Find hostname
    if( is_ipv4($input_name) ){
        $addr_info{ipv4} = $input_name;
        my $dnsResult = $dnsRes->query($input_name);
        if($dnsResult){
            my @dnsAnwer = $dnsResult->answer;
            foreach my $rr(@dnsAnwer){
                $addr_info{dns} = $rr->ptrdname if($rr->type eq 'PTR');
            }
        }
    }elsif( is_ipv6($input_name) ){
        $addr_info{ipv6} = $input_name;
        my $dnsResult = $dnsRes->query($input_name);
        if($dnsResult){
            my @dnsAnwer = $dnsResult->answer;
            foreach my $rr(@dnsAnwer){
                $addr_info{dns} = $rr->ptrdname if($rr->type eq 'PTR');
            }
        }
    }else{
        $addr_info{dns} = $input_name;
    }
    return $hosts->{$addr_info{dns}} if($addr_info{dns} && $hosts->{$addr_info{dns}});
    push @addresses, $addr_info{dns} if($addr_info{dns});

    #find ipv6 address
    if(!$addr_info{ipv6} && $addr_info{dns}){
        my $do_lookup = 1;
        while($do_lookup){
            $do_lookup = 0;
            my $dnsResult = $dnsRes->query($addr_info{dns}, 'AAAA');
            if($dnsResult){
                my @dnsAnwer = $dnsResult->answer;
                foreach my $rr(@dnsAnwer){
                    if($rr->type eq 'AAAA'){
                        $addr_info{ipv6} = $rr->address;
                    }elsif($rr->type eq 'CNAME'){
                        push @{$addr_info{cnames}}, $addr_info{dns};
                        $addr_info{dns} = $rr->cname;
                        $do_lookup = 1;
                    }
                }
            }
        }
    }
    return $hosts->{$addr_info{ipv6}} if($addr_info{ipv6} && $hosts->{$addr_info{ipv6}});
    push @addresses, $addr_info{ipv6} if($addr_info{ipv6});
    
    #find ipv4 address
    if(!$addr_info{ipv4} && $addr_info{dns}){
        my $do_lookup = 1;
        while($do_lookup){
            $do_lookup = 0;
            my $dnsResult = $dnsRes->query($addr_info{dns}, 'A');
            if($dnsResult){
                my @dnsAnwer = $dnsResult->answer;
                foreach my $rr(@dnsAnwer){
                    if($rr->type eq 'AAAA'){
                        $addr_info{ipv4} = $rr->address;
                    }elsif($rr->type eq 'CNAME'){
                        push @{$addr_info{cnames}}, $addr_info{dns};
                        $addr_info{dns} = $rr->cname;
                        $do_lookup = 1;
                    }
                }
            }
        }
    }
    return $hosts->{$addr_info{ipv4}} if($addr_info{ipv4} && $hosts->{$addr_info{ipv4}});
    push @addresses, $addr_info{ipv4} if($addr_info{ipv4});
    
    #add host
    $hosts->{$addresses[0]} = {
        name => $addresses[0],
        type => 'manual',
        interface => {
                if_name => $addresses[0],
                address => \@addresses,
            }
    };
    
    return $hosts->{$addresses[0]};
}
