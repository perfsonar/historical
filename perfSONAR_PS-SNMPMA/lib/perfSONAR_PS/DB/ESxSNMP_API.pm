package perfSONAR_PS::DB::ESxSNMP_API;

use LWP::UserAgent;
use JSON::XS;
use Data::Dumper;

sub new
{
     my($type) = $_[0];
     my($self) = {};
     $self->{'url'}    = $_[1]; #remember $_[0] was the Tree before the ->
     $self->{'ua'}     = LWP::UserAgent->new;
     $self->{'ua'}->agent("ESxSNMP_API/0.1 " . $self->{'ua'}->agent);
     $self->{'jcodec'} = JSON::XS->new->ascii->pretty->allow_nonref;
     bless($self, $type);
     return($self);
}

sub get_uri
{
    my($self)=$_[0];
    my($uri)=$_[1];

    $uri =~ s:^/::;

    return $self->_do_get($self->{'url'} . $uri);
}

sub _do_get
{
    my($self) = $_[0];
    my($url) = $_[1];

    my($req) = HTTP::Request->new(GET => $url);
    $req->header('Accept' => 'text/html');

    my($res) = $self->{'ua'}->request($req);

    if($res->is_success) {
        return $self->{'jcodec'}->decode($res->decoded_content);
    } else {
        print "Error: " . $res->status_line . "\n";
        return undef;
    }
}

sub get_routers
{
    my($self)=$_[0];

    return $self->_do_get($self->{'url'} . "snmp/");
}

sub get_interfaces
{
    my($self) = $_[0];
    my($rtr) = $_[1];

    return $self->_do_get($self->{'url'} . "snmp/" . $rtr . "/interface/");
}

sub get_interface_data
{
    my($self) = $_[0];
    my($rtr) = $_[1];
    my($iface) = $_[2];
    my($begin) = $_[3];
    my($end) = $_[4];
    my($dir) = $_[5];
    my($agg) = $_[6];
    
    my($q) = $self->{'url'} . 'snmp/' . $rtr . '/interface/' . $iface . '/';
    $q .= $dir . '?begin=' . $begin . '&end=' . $end;

    if(defined($agg))
    {
        $q .= '&agg=' . $agg;
    }

    return $self->_do_get($q);
}

sub get_bulk
{
    my($self) = $_[0];

    return undef;
}

1;
