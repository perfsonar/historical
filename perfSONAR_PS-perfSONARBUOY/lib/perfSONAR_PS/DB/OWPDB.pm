package perfSONAR_PS::DB::OWPDB;

use strict;
use warnings;

our $VERSION = 3.3;
use DBI;
use Log::Log4perl qw(get_logger);
use Params::Validate qw(:all);
use perfSONAR_PS::Config::OWP::Utils;
use perfSONAR_PS::Utils::NetLogger;

use constant {
    DEFAULT_NS => 'http://ggf.org/ns/nmwg/characteristic/delay/summary/20070921/',
    DEFAULT_NSPREFIX => 'summary'
};

sub new{
    my ($package, @args) = @_;
    my %args = validate(@args, {
					DBH => 1,
					XMLOUT => 1,
					NAMESPACE => 0,
					NSPREFIX => 0
				}
			);
			
	#Assign required arguments
    my $self = {
        'DBH' => $args{'DBH'},
        'XMLOUT' => $args{'XMLOUT'},
    };
    
    #setup NetLogger
    $self->{NETLOGGER} = get_logger("NetLogger");
    
    #Assign optional arguments
    if($args{'NAMESPACE'}){
        $self->{'NAMESPACE'} = $args{'NAMESPACE'};
    }else{
        $self->{'NAMESPACE'} = DEFAULT_NS;
    }
    
    if($args{'NSPREFIX'}){
        $self->{'NSPREFIX'} = $args{'NSPREFIX'};
    }else{
        $self->{'NSPREFIX'} = DEFAULT_NSPREFIX;
    }
    
    bless($self, $package);
    
    return $self;
}

sub fetchValueBuckets(){
    my($self, @args) = @_;
    my %args = validate(@args, {
                    start       => 1,
                    send_id     => 1,
                    recv_id     => 1,
                    si          => 1,
                    ei          => 1
				}
			);
    my ($basei, $i, $n);
    #my $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.DB.OWPDB.fetchValueBuckets.start");
    #$self->{NETLOGGER}->debug( $nlmsg );
    
    #prepare statement
    my $tableName = $self->generateTableName(table => 'DELAY', owptime => $args{'start'});
    my $stmt = $self->{'DBH'}->prepare("SELECT basei, i, n FROM $tableName WHERE send_id=? AND recv_id=? AND si=? AND ei =? ORDER BY i");
    $stmt->bind_param(1, $args{'send_id'});
    $stmt->bind_param(2, $args{'recv_id'});
    $stmt->bind_param(3, $args{'si'});
    $stmt->bind_param(4, $args{'ei'});
   
    #$nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.DB.OWPDB.fetchValueBuckets.queryDB.start");
    #$self->{NETLOGGER}->debug( $nlmsg ); 
    #query database
    $stmt->execute();
    $stmt->bind_columns(\$basei, \$i, \$n);
    #$nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.DB.OWPDB.fetchValueBuckets.queryDB.end");
    #$self->{NETLOGGER}->debug( $nlmsg );
  

      
    #build XML
    $self->{'XMLOUT'}->startElement(
        prefix      => $self->{'NSPREFIX'},
        namespace   => $self->{'NAMESPACE'},
        tag         => 'value_buckets',
    );

    
    while($stmt->fetch()){
        my %attrs = ();
        $attrs{"value"} = $basei + $i;
        $attrs{"count"} = $n;
        $self->{'XMLOUT'}->createElement(
            prefix      => $self->{'NSPREFIX'},
            namespace   => $self->{'NAMESPACE'},
            tag         => "value_bucket",
            attributes  => \%attrs
        );
    }
    $self->{'XMLOUT'}->endElement('value_buckets');
    #$nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.DB.OWPDB.fetchValueBuckets.end");
    #$self->{NETLOGGER}->debug( $nlmsg );
}

sub fetchTTLBuckets(){
    my($self, @args) = @_;
    my %args = validate(@args, {
                    start       => 1,
                    send_id     => 1,
                    recv_id     => 1,
                    si          => 1,
                    ei          => 1
				}
			);
    my ($basei, $i, $n);
    my $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.DB.OWPDB.fetchTTLBuckets.start");
    $self->{NETLOGGER}->debug( $nlmsg );
    
    #prepare statement
    my $tableName = $self->generateTableName(table => 'TTL', owptime => $args{'start'});
    my $stmt = $self->{'DBH'}->prepare("SELECT ittl, nttl FROM $tableName WHERE send_id=? AND recv_id=? AND si=? AND ei =? ORDER BY ittl");
    $stmt->bind_param(1, $args{'send_id'});
    $stmt->bind_param(2, $args{'recv_id'});
    $stmt->bind_param(3, $args{'si'});
    $stmt->bind_param(4, $args{'ei'});
    
    #query database
    $stmt->execute();
    $stmt->bind_columns(\$i, \$n);
    
    #build XML
    $self->{'XMLOUT'}->startElement(
        prefix      => $self->{'NSPREFIX'},
        namespace   => $self->{'NAMESPACE'},
        tag         => 'TTL_buckets',
    );
    while($stmt->fetch()){
        my %attrs = ();
        $attrs{"ttl"} = $i;
        $attrs{"count"} = $n;
        $self->{'XMLOUT'}->createElement(
            prefix      => $self->{'NSPREFIX'},
            namespace   => $self->{'NAMESPACE'},
            tag         => "TTL_bucket",
            attributes  => \%attrs
        );
    }
    $self->{'XMLOUT'}->endElement('TTL_buckets');
    $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.DB.OWPDB.fetchTTLBuckets.end");
    $self->{NETLOGGER}->debug( $nlmsg );
}

sub generateTableNames(){
    my($self, @args) = @_;
    my %args = validate(@args, {
                    table   => 1,
                    start   => 1,
                    end     => 1
				}
			);
    my $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.DB.OWPDB.generateTableNames.start");
    $self->{NETLOGGER}->debug( $nlmsg );
    my @tableNames = ();
    my $endName = $self->generateTableName(table => $args{'table'}, owptime => $args{'end'});
    
    my $curTime = owptime2exacttime($args{'start'});
    my $curName = "";
    while($curName ne $endName){
        $curName = $self->generateTableName(table => $args{'table'}, unixtime => $curTime);
        push @tableNames, $curTime;
        $curTime += 24*60*60;
    }
    
    $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.DB.OWPDB.generateTableNames.end");
    $self->{NETLOGGER}->debug( $nlmsg );
	return @tableNames;
}

sub generateTableName(){
    my($self, @args) = @_;
    my %args = validate(@args, {
                    table   => 1,
                    owptime     => 0,
                    unixtime    => 0
				}
			);
	my $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.DB.OWPDB.generateTableName.start");
	$self->{NETLOGGER}->debug( $nlmsg );
	my @time;
    if($args{'owptime'}){
        @time = gmtime(owptime2exacttime($args{'owptime'}));
    }else{
        @time = gmtime($args{'unixtime'});
    }
    
    $nlmsg = perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.DB.OWPDB.generateTableName.end");
    $self->{NETLOGGER}->debug( $nlmsg );
	return ($time[5] + 1900) . sprintf("%02d", $time[4]+1) . sprintf("%02d", $time[3]) . '_' . $args{'table'};
}

1;
