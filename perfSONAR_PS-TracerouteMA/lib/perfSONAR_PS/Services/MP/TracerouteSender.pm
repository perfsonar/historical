package perfSONAR_PS::Services::MP::TracerouteSender;

use strict;
use warnings;

our $VERSION = 3.3;
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Common qw(makeEnvelope genuid);
use perfSONAR_PS::Transport;

use fields 'LOGGER','NETLOGGER', 'MA_URLS', 'SEND_INTERVAL', 'LAST_RUNTIME', 'DATADIR', 'MA_TIMEOUT', 'BATCH_SIZE', 'BATCH_COUNT';

use constant DEFAULT_TIMEOUT => 30;
use constant DEFAULT_BATCH_SIZE => 10;
use constant DEFAULT_BATCH_COUNT => 25;

sub new{
    my ( $class, $ma_urls, $send_int, $datadir, $ma_timeout, $batch_size, $batch_count ) = @_;
    my $self = fields::new( $class );
    $self->{LOGGER} = get_logger( "perfSONAR_PS::Services::MP::TracerouteSender" );
    $self->{NETLOGGER} = get_logger( "NetLogger" );
    
    if(defined $ma_urls && $ma_urls){
        $self->{'MA_URLS'} = $ma_urls;
    }
    
    if(defined $send_int && $send_int){
        $self->{'SEND_INTERVAL'} = $send_int;
    }
    
    if(defined $datadir && $datadir){
        $self->{'DATADIR'} = $datadir;
    }
    
    if(defined $ma_timeout && $ma_timeout){
        $self->{'MA_TIMEOUT'} = $ma_timeout;
    }else{
        $self->{'MA_TIMEOUT'} = DEFAULT_TIMEOUT;
    }
    
    if(defined $batch_size && $batch_size){
        $self->{'BATCH_SIZE'} = $batch_size;
    }else{
        $self->{'BATCH_SIZE'} = DEFAULT_BATCH_SIZE;
    }
    
    if(defined $batch_count && $batch_count){
        $self->{'BATCH_COUNT'} = $batch_count;
    }else{
        $self->{'BATCH_COUNT'} = DEFAULT_BATCH_COUNT;
    }
    
    return $self;
}

sub run {
    my $self = shift;
    
    #TODO acquire lock
    
    #open directory
    for(my $batch_num = 0; $batch_num < $self->{'BATCH_COUNT'} ; $batch_num++){
        my $msg_body = '';
        my @data_files = ();
        opendir(my $dh, $self->{'DATADIR'}) or die ("Unable to open directory " . $self->{'DATADIR'} . ": $!");
        
        while((@data_files < $self->{'BATCH_SIZE'} ) && (my $data_file = readdir $dh)){
            my $fname = $self->{'DATADIR'} . '/' . $data_file;
            if(-d $fname || $fname =~ /^\./){
                next;
            }        
            eval{
                open(DATAFILE, "< $fname") or die("unable to open file $fname: $!");
                while(my $line = <DATAFILE>){
                    $msg_body .= $line;
                }
                close DATAFILE;
            };
            if($@){
                $self->{LOGGER}->error($@);
            }else{
                #bad but perl complains about tainting even though directory and file exist
                $fname = $1 if($fname =~ /(.+)/);
                push @data_files, $fname;
            }
        }
        closedir $dh;
        
        #register data
        if(@data_files > 0 && $self->register($msg_body)){
            #cleanup files
            foreach my $df(@data_files){
                unlink $df or $self->{LOGGER}->error("Could not unlink $df: $!");
            }
        }else{
            last;
        }
    }
    
    #set last run
    $self->{'LAST_RUNTIME'} = time;
    
    return;
}

sub register {
    my ($self, $msg_body) = @_;
    
    my $success = 0;
    my $ps_message = '<nmwg:message type="RegisterDataRequest" id="message.' . genuid() . '" xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/">';
    $ps_message .= $msg_body;
    $ps_message .= '</nmwg:message>';
    
    foreach my $ma_url(@{$self->{'MA_URLS'}}){
        eval{
            my $error = '';
            my($host, $port, $endpoint) = perfSONAR_PS::Transport::splitURI($ma_url);
            my $ma_client = perfSONAR_PS::Transport->new($host, $port, $endpoint);
            $ma_client->sendReceive(makeEnvelope($ps_message), $self->{'MA_TIMEOUT'}, \$error);
            if($error){
                $self->{LOGGER}->error($error);
            }else{
                #consider success if no errors to at least one MA
                $success = 1;
            }
         };
         if($@){
            $self->{LOGGER}->error($@);
        }
    }
    
    return $success;
}
