package SimpleConfig;
########################################
#
#  maxim@fnal.gov 2007
#
##  Purpose: Provide a convenient way for loading
#          config values from a given file and
#          return it as a hash structure, allow interpolation for the simple perl scalars ( $xxxx ${xxx} )
#    Also, it can run interactive session with user, use predefined prompts, use validation patterns
#  and store back into the file, preserving the original comments 
#

use strict;
use warnings;
use Log::Log4perl qw(get_logger); 

# exported package globals go here
 
# intializing all of them 
 
 sub new{
  my $that = shift;
  my $class = ref($that) || $that;
  my @param = @_;
  my $self = { FILE => undef, DATA => undef, DIALOG => undef, VALIDKEYS => undef, PROMPTS => undef,  LOGGER => undef}; 
  bless $self, $class;
  $self->{LOGGER} = get_logger($that);
  my %conf = undef;
  if(@param) {
     if ($param[0] eq '-hash') { 
       %conf = %{$param[1]} 
     } else {
       %conf = @param;
     }
     foreach my $cf ( keys %conf ) {
        (my $stripped_cf = $cf) =~ s/\-//;
       if(exists $self->{$stripped_cf}) {
           $self->{$stripped_cf} = $conf{$cf};
        }  else {
            $self->{LOGGER}->warn("Unknown option: $cf - " . $conf{$cf}) ;
        }
     }
  } 
  return $self;
}

sub promptEnter{
   my $prompt = shift;
   print "$prompt\n";
   my $entered = <STDIN>;
   chomp $entered;
   $entered =~ s/\s+//g;
   return  $entered;  
} 
#
#
#
sub setDialog{
   my $self = shift;
   $self->{DIALOG} = shift;
}
#
#
sub setFile {
   my $self = shift;
   $self->{FILE} = shift;

}
#
#
#
sub setValidkeys {
   my $self = shift;
   $self->{VALIDKEYS} = shift;

}
#
#
sub setPrompts {
   my $self = shift;
   $self->{PROMPTS} = shift;

}
  
 
# 
#
sub getData {
   my $self = shift;
  
   return $self->{DATA};
   
}
 
#
sub setData {
   my $self = shift;
   $self->{DATA} = shift;

}
# 
#
 
#
#   store    config  in the file, preserve all comments from the original file
#
sub store {
  my  $self  = shift;
  my $filen = shift;
  my $file_to_store = (defined $filen && -e $filen)?$filen:$self->{FILE};
 
  open OUTF, "+>$file_to_store" or  $self->{LOGGER}->error(" Failed to store config file: $file_to_store") ;
  foreach my $key ( map {$_->[1]} sort { $a->[0] <=>  $b->[0]} map {[$self->{DATA}->{$_}{order}, $_]} keys %{$self->{DATA}}) { 
   my $comment = $self->{DATA}->{$key}{comment}?$self->{DATA}->{$key}{comment}:"#\n"; 
   print OUTF $comment .   $key . "=" . ($self->{DATA}->{$key}{pre}?$self->{DATA}->{$key}{pre}:$self->{DATA}->{$key}{value}) . "\n";
   $self->{LOGGER}->debug($comment  .    $key . "=" .  ($self->{DATA}->{$key}{pre}?$self->{DATA}->{$key}{pre}:$self->{DATA}->{$key}{value}));
  } 
  close OUTF;
}
#
#   parse  simple config with interpolation and comments preservation 
#
sub parse {
  my $self = shift;
  my $filen = shift;
  my $file_to_open = (defined $filen && -e $filen)?$filen:$self->{FILE};
  
  open INF, "<$file_to_open"  or $self->{LOGGER}->error( " Failed to open config file: $file_to_open");
  $self->{LOGGER}->debug( "File $file_to_open opened for parsing " ); 
  my %config = ();
  my $comment = undef;
  my $order = 0;
  
  while(<INF>) {
    chomp;
     s/^\s+?//;
    if(m/^\#/) {
       $comment .= "$_\n";
    } else {
       s/\s+//g;
       if(m/^([\w\.\-]+)\=(.+)/) {
          my $key = $1;
	  my $value = $2;
	  my $vpattern = $self->{VALIDKEYS}?$self->{VALIDKEYS}->{$key}:undef; 
	  my $pkey = $self->{PROMPTS}?$self->{PROMPTS}->{$key}:undef; 
	  $vpattern = qr/$vpattern/ if $vpattern;
	  if($self->{DIALOG} &&   $pkey) {
	      my $entered =  promptEnter("  Please enter the value for the $pkey (Default is $value)>");
	      while($entered && ( $vpattern  && $entered !~ $vpattern  )) {
	         $entered =  promptEnter("!!! Entered value is  not valid according to regexp: $vpattern , please re-enter>");
	      }
	      $value = $entered?$entered:$value;
	  }  
	  if( $vpattern   && $value !~  $vpattern ) {
	      $self->{LOGGER}->error( "Parser failed, value:$value for $key is NOT VALID according to pattern:  $vpattern" );
	  }
	   
	  $config{$key}{value} = $value;
 	  $config{$key}{order}=$order++;
	  $order++;
	  if ($comment) {
	      $config{$key}{comment} = $comment ;
	      $comment = '';
	  }
       }
    }
  }
  close INF;
  $self->{LOGGER}->debug(" interpolating ...\n");
  #  interpolate all values 
  foreach my $key (keys %config) {
     my (  @tmp_keys) =  $config{$key}{value} =~ /[^\\]?\$\{?([a-zA-Z]+(?:\w+)?)\}?/g; 
     foreach my $sub_key (@tmp_keys) {
       $self->{LOGGER}->debug(" CHECK  $config{$key}{value} -> $sub_key  \n");	
        if ( $sub_key  && $config{"$sub_key"} ) { 
           my $subst = $config{"$sub_key"}{value} ;
	   $config{$key}{pre} =  $config{$key}{pre}?$config{$key}{pre}:$config{$key}{value};
	   $config{$key}{value}  =~ s/\$\{?$sub_key\}?/$subst/g; 
	   $self->{LOGGER}->debug(" interpolated $config{$key}{value} -> $sub_key -> $subst \n");	
        }
      }
  }
  $self->{DATA}=\%config;
  
  return \%config;
}
 
 

1;

 __END__
 
=head1 NAME

SimpleConfig -   Config parser Module with comment preservation, order preservation, simple variable interpolation
                and user's dialog functionality. User can set prompts and validation patterns

=head1 SYNOPSIS

   
 use SimpleConfig;
 #  create new object
 $conf = new SimpleConfig(-FILE => "my.conf");
 #
 #   set interactive mode
 $conf->setDialog(1);
 #
 #   use dialog prompts from this hashref
 $conf->setPrompts(\%prompts_hash); 
 #  
  #   use validation patterns from this hashref
 $conf->setValidkeys(\%validkeys_hash); 
 #   parse and have a "chat" with user at the same time
 $config_hashref = $conf->parse;
 --or--
 $conf->parse;
 $config_hashref  =  $conf->getData;
 # store into the different config file with all comments and in the same order
 $conf->store("my_another.config");

  
=head1 DESCRIPTION

This module opens a config file and parses it's contents for you. The B<new> method
accepts several parameters. The method B<parse> returns a hash reference
which contains all options and it's associated values of your config file as well as comments above.
If the -dialog mode is set then at the moment of parsing user will be prompted to enter different value and
if validation pattern for this particular key was defined then it will be validated and user could be asked to
enter different value if it fail.

The format of config files supported by B<SimpleConfig> is   simple
<name>=<value> pairs and comments are any line which starts with #. Also, it will interpolate any perl variable 
which looks as ${?[A-Za-z]\w+}?. The order of appearance of such variables in the config file is not important.




=head1 DETAILS


=over


=item new() 
  
 
Possible ways to call B<new()>:
 
 $conf = new SimpleConfig(); 
 
 $conf = new SimpleConfig(-FILE => "my.conf"); # create object and will parse/store it within the my.conf file

 
 $conf = new SimpleConfig(-FILE => "my.conf", -DATA => $hashref);  # use current hash ref with options
 
 $conf = new SimpleConfig(-FILE => "my.conf", -DIALOG => 'yes', -PROMPTS => \%promts_hash); # prompt user to enter new value for every -key- which held inside of  %prompts_hash
 $conf = new SimpleConfig(-FILE => "my.conf", -DIALOG => 'yes', 
                          -PROMPTS => \%promts_hash, -VALIDKEYS => \%validation_patterns); # ... and validate every new value against the validation pattern
 

This method returns a B<SimpleConfig> object (a hash blessed into "SimpleConfig" namespace.
All further methods must be used from that returned object. see below.
Please note that setting -DIALOG option into the "true" is not enough, because the method will look only for the keys defined in the %prompts_hash 
An alternative way to call B<new()> is supplying an option -HASH with  hash reference to the set of  the options.

=item B<-FILE>

A filename 

 -FILE => "my.conf",  the dash '-' is optional

 
=item B<-DATA>

A hash reference, which will be used as the config, i.e.:

 -DATA => \%somehash,  the dash '-' is optional

where %somehash should be formatted as     ( $key1 => ('comment' => "#some comment\n#more comments\n", 
                                                       'value' => $value1),
					    $key2 => ('comment' => "#some comment\n#more comments\n", 
                                                      'value' => $value2), ) 

=item B<-DIALOG>

Set up an interactive mode, Please note that setting -DIALOG option into the "true" is not enough,
because this method will look only for the keys defined in the %prompts_hash ,  the dash '-' is optional

=item B<-PROMPTS>

Hash ref with prompt text for  particular -key- ,  the dash '-' is optional 

=item B<-VALIDKEYS>

Hash ref with  validation patterns  for  particular -key- ,  the dash '-' is optional
=back


=head1 METHODS


=head2 B<parse()>


Parse config file, return hash ref ( optional)

Possible ways to call B<parse()>:

 $config_hashref = $conf->parse("my.conf"); # parse  my.conf file, if -FILE was defined at the object creation time, then this will overwrite -FILE option
 
  $config_hashref = $conf->parse();  
  
This method returns a  a hash ref.


=head2   B<store()>


Store into the config file 

Possible ways to call B<store()>:

  $conf->store("my.conf"); #store into the my.conf file, if -FILE was defined at the object creation time, then this will overwrite it
 
  $conf->store();  



=head2  B<setFile()>


=head2  B<getData()>


=head2   B<setData()>
 
 
=head2   B<setValidkeys()>


=head2   B<setPrompts()>
 
 
=head2   B<setDialog()>
 
 

=head1 DEPENDENCIES

None


=head1 EXAMPLES 


For example the config file for SNMP MA could  be written as:

 METADATA_DB_TYPE=file
 METADATA_DB_NAME=
 SNMP_BASE = /home/jason/convert/perfSONAR-PS/MP/SNMP
 METADATA_DB_FILE=$SNMP_BASE/store.xml
 
 PORT=8080
 ENDPOINT=/axis/services/snmpMA
 RRDTOOL=/usr/local/rrdtool/bin/rrdtool

=head1 SEE ALSO

L<Log::Log4perl>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 AUTHOR

Maxim Grigoriev <maxim |AT| fnal.gov>

=head1 VERSION

$Id:$

=cut
