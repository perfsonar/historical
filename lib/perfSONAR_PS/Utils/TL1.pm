package perfSONAR_PS::Utils::TL1;

use Net::Telnet;
use Date::Calc qw(:all);
use Data::Dumper;

use strict;

sub new {
    
    my $caller = shift;
    my $class = ref($caller) || $caller;
    my $self = {
	        username => 'username',
		password => 'password',
		type => 'ons15454',
		host => 'hostname',
		port => '23',
		@_
    };
    
    bless($self, $class);

    $self->{'telnet'} = Net::Telnet->new(Timeout => 30, Errmode => 'return', Port => $self->{'port'}); 
    return $self;
}

sub connect {

    my ($self) = @_;

    my $host = $self->{'host'};
    my $test = $self->{'telnet'}->open($host);

    if ($test) {

	return $test;
    }
}

sub disconnect {
  
  my ($self) = @_;

  my $username = $self->{'username'};
  
  if ($self->{'type'} eq "ciena") {
    $self->send("CANC-USER::".$username.":1;");
  }
  $self->{'telnet'}->close();
}

sub login {
  
  my ($self) = @_;
  
  my $type = $self->{'type'};
  my $telnet = $self->{'telnet'};
  my $username = $self->{'username'};
  my $password = $self->{'password'};
  my $line;
  
  if ($type eq "hdxc") {
    
    getNumLines($telnet, 3);
    $telnet->print("ACT-USER::$username:1::$password;");
    $line = getNumLines($telnet, 10);
    
    # success
    if ($line =~ /.*COMPLD.*\n/) {
      
      $telnet->buffer_empty;
      return 1;
    }
    
    # failure
    else {
      
      $telnet->buffer_empty;
      return 0;
    }
  }
  
  elsif ($type eq "ome") {
    
    $telnet->waitfor('/<$/');
    $telnet->print("ACT-USER::$username:1::\"$password\";");
    
    while ($line = $telnet->getline) {
      
      # success
      if ($line =~ /.*COMPLD.*/) {
	
	return 1;
      }
    }
    
    # failure
    return 0;
  }
  
  elsif ($type eq "ons15454") {
    
    my $success = 0;
    # wait until newline before prompt
    while (($line = $telnet->getline) !~ /\n/) {}
    $telnet->print("ACT-USER::$username:1::$password;");
    
    # wait until prompt
    while (($line = $telnet->getline) !~ /> $/) {
      
      if ($line =~ /.*COMPLD.*\n/) {
	$success = 1;
      }
    }
    
    $telnet->buffer_empty;
    return $success;
  }
  
  elsif ($type eq "ciena") {
    
    my $success = 0;
    
    # wait for prompt
    $telnet->waitfor('/^;$/m');

    $telnet->print("ACT-USER::$username:1337::$password;");
    $telnet->getline;
    while ($line = $telnet->getline) {
      if ($line =~ /.*COMPLD.*\n/) {
	$success = 1;
	last;
      }
      elsif ($line =~ /.*DENY.*\n/) {
	$success = 0;
	last;
      }
    }
    
    $telnet->buffer_empty;
    return $success;
  }
  
  elsif ($type eq "infinera") {
    
    my $success = 0;
    
    $telnet->getline;
    $telnet->print("ACT-USER::$username:1::$password;");
    $telnet->getline;
    
    while ($line = $telnet->getline) {
      if ($line =~ /.*COMPLD.*\n/) {
	$success = 1;
	last;
      }
      elsif ($line =~ /.*DENY.*\n/) {
	$success = 0;
	last;
      }
    }
    
    # eat up all login messages
    my $numSemicolon = 0;
    while ($line = $telnet->getline) {

      # there will be 3 messages, each ending with ;
      $numSemicolon++ if ($line =~ /^;$/);
      if ($numSemicolon == 3) {

	# eat up prompt
	$telnet->waitfor(/TL1>>/);
	last;
      }
    }
    $telnet->buffer_empty;

    return $success;
  }
}

sub getNumLines {

    my $telnet = shift;
    my $num = shift;
    my $line;

    while ($num-- > 0) {

	$line = $telnet->getline;
    }

    return $line;
}

sub getIPInfo {

    my ($self) = @_;
    
    my $telnet = $self->{'telnet'};
    my $type = $self->{'type'};
    my $line;
    my @result;
    my $i = 0;

    if ($type eq "ome") {

	$telnet->print("RTRV-IP:::1;");
	$telnet->getline;
	$telnet->getline;

	while (($line = $telnet->getline) !~ /.*;.*\n/) {

	    if ($line =~ /.*"([^:]+)::IPADDR=([^,]*),NETMASK=([^,]*),BCASTADDR=([^,]*),DEFTTL=([^,]*),HOSTONLY=([^,]*),NONROUTING=([^,]*),.*$/) {

		$result[$i]->{'device'} = $1;
		$result[$i]->{'ip'} = $2;
		$result[$i]->{'netmask'} = $3;
		$result[$i]->{'bcast'} = $4;
		$result[$i]->{'ttl'} = $5;
		$result[$i]->{'hostOnly'} = $6;
		$result[$i]->{'noRoute'} = $7;

		$i++;
	    }
	}
    }

	 
    elsif ($type eq "hdxc") {

      $telnet->print("RTRV-IP:::1;");
      $telnet->getline;
      
      my $last = 0;
      
      while (($line = $telnet->getline) !~ /.*;.*\n/) {
	
	# if we hit a COMPLD then we know this is the last group of output
	if ($line =~ /^M\s+\d+\s+COMPLD$/) {
	  $last = 1;
	}
	
	# if we hit a ; on its own line, we are done displaying a group of output
	elsif ($line =~ /^;$/) {
	  
	  # if we hit a COMPLD earlier, we are done
	  last if ($last);
	}
	
	elsif ($line =~ /.*"([^:]+):NETMASK=([^,]*),GATEWAY=([^,]*),IPADDR=([^\"]*)"$/) {

	  $result[$i]->{'device'} = $1;
	  $result[$i]->{'netmask'} = $2;
	  $result[$i]->{'gateway'} = $3;
	  $result[$i]->{'ip'} = $4;
	  
	  $i++;
	}
      }
    }

    elsif ($type eq "ons15454") {

	$telnet->print("RTRV-NE-GEN:::1;");
	$telnet->getline;

	while (($line = $telnet->getline) !~ /.*>.*\n/) {

	    if ($line =~ /^\s*".*"$/) {

		$line =~ /.*IPADDR=([^,]+),.*/;
		$result[$i]->{'ip'} = $1;

		$line =~ /.*IPMASK=([^,]+),.*/;
		$result[$i]->{'netmask'} = $1;
		
		$line =~ /.*DEFRTR=([^,]+),.*/;
		$result[$i]->{'gateway'} = $1;
		
		$line =~ /.*NAME=([^,]+),.*/;
		$result[$i]->{'name'} = $1;
		$result[$i]->{'name'} =~ s/\\//g;
		$result[$i]->{'name'} =~ s/\"//g;

		$i++;
	    }
	}
    }

    return @result;
}

sub getFacilities {

    my ($self) = @_;

    my $telnet = $self->{'telnet'};
    my $type = $self->{'type'};
    my $line;
    my $i = 0;
    my @result;

    if ($type eq "ons15454") {

	$telnet->print("RTRV-FAC::ALL:1;");
	$telnet->getline;

	while (($line = $telnet->getline) !~ /.*>.*\n/) {
	    
	    if ($line =~ /^\s*"([^:]+)::PAYLOAD=([^:]+):([^,]+),.*"$/) {

		$result[$i]->{'fac'} = $1;
		$result[$i]->{'payload'} = $2;
		$result[$i]->{'prime'} = $3;

		$i++;
	    }
	}
    }

    return @result;
}

sub getCircuits {

    my ($self) = @_;

    my $telnet = $self->{'telnet'};
    my $type = $self->{'type'};
    my $line;
    my $i = 0;
    my @result;

    if ($type eq "ome") {

	$telnet->timeout(10);
	$telnet->print("RTRV-CRS-ALL:::1;");
	$telnet->getline;
	$telnet->getline;
	$telnet->getline;

	while (($line = $telnet->getline) !~ /.*;.*\n/) {

	    if ($line =~ /.*"([^,]*),([^:]*):([^:]*):.*:([^:]*):.*"/) {

		$result[$i]->{'inCircuit'} = $1;
		$result[$i]->{'outCircuit'} = $2;
		$result[$i]->{'direction'} = $3;
		$result[$i]->{'rate'} = $4;

		$i++;
	    }
	}
	$telnet->timeout(1);
    }
    
    elsif ($type eq "hdxc") {

      $telnet->print("RTRV-CRS-ALL:::1;");
      $telnet->getline;
      
      my $last = 0;
      
      while (($line = $telnet->getline)) {
	
	# if we hit a COMPLD then we know this is the last group of output
	if ($line =~ /^M\s+\d+\s+COMPLD$/) {
	  $last = 1;
	}

	# if we hit a ; on its on line, we are done displaying a group of output
	elsif ($line =~ /^;$/) {
	  
	  # if we hit a COMPLD earlier, we are done
	  last if ($last);
	}
	
	elsif ($line =~ /^\s*"([^,]+),([^:]+):([^,]+),([^:]+):LABEL=\\"(.*)\\",AST=(\w+),PRIME=(\w+),CONNID=(\d+):"$/) {
	  
	  ($result[$i]->{'inCircuit'}, $result[$i]->{'outCircuit'}, $result[$i]->{'direction'}, $result[$i]->{'rate'},
	   $result[$i]->{'label'}, $result[$i]->{'ast'}, $result[$i]->{'prime'}, $result[$i]->{'connid'}) = 
	     ($1, $2, $3, $4, $5, $6, $7, $8);
	  
	  if ($result[$i]->{'rate'} =~ /STS-(\d+)\w+/ ) {
	    
	    $result[$i]->{'rateNum'} = $1;
	  }
	  
	  my @in_ckt_arr = split /-/, $result[$i]->{'inCircuit'};
	  
	  $result[$i]->{'inCircuitType'} = $in_ckt_arr[0];
	  ($result[$i]->{'inChannels'}) = $in_ckt_arr[0] =~ /OC(\d+)\w+/;
	  $result[$i]->{'inShelf'} = $in_ckt_arr[1];
	  $result[$i]->{'inSlot'} = $in_ckt_arr[2];
	  $result[$i]->{'inPort'} = $in_ckt_arr[3];
	  $result[$i]->{'inStartChannel'} = $in_ckt_arr[5];
	  $result[$i]->{'inEndChannel'} = $result[$i]->{'rateNum'} + $result[$i]->{'inStartChannel'} - 1;
	  
	  my @out_ckt_arr = split /-/, $result[$i]->{'outCircuit'};
	  
	  $result[$i]->{'outCircuitType'} = $out_ckt_arr[0];
	  ($result[$i]->{'outChannels'}) = $out_ckt_arr[0] =~ /OC(\d+)\w+/;
	  $result[$i]->{'outShelf'} = $out_ckt_arr[1];
	  $result[$i]->{'outSlot'} = $out_ckt_arr[2];
	  $result[$i]->{'outPort'} = $out_ckt_arr[3];
	  $result[$i]->{'outStartChannel'} = $out_ckt_arr[5];
	  $result[$i]->{'outEndChannel'} = $result[$i]->{'rateNum'} + $result[$i]->{'outStartChannel'} - 1;
	  
	  $i++;
	}
      }
    }

    elsif ($type eq "ons15454") {

	$telnet->print("RTRV-CRS::ALL:1;");
	$telnet->getline;

	while (($line = $telnet->getline) !~ /.*>.*\n/) {

	    if ($line =~ /^\s*"([^,]+),([^:]+):([^,]+),([^:]+):([^:]*):([^,]+),([^\"]*)"$/) {

		$result[$i]->{'src'} = $1;		
		$result[$i]->{'dst'} = $2;		
		$result[$i]->{'cct'} = $3;
		$result[$i]->{'crstype'} = $4;
		$result[$i]->{'extra'} = $5;	
		$result[$i]->{'prime'} = $6;
		$result[$i]->{'second'} = $7;

		$result[$i]->{'src'} =~ s/&/ /g;
		$result[$i]->{'dst'} =~ s/&/ /g;
		$result[$i]->{'second'} =~ s/&/ /g;
		$result[$i]->{'extra'} =~ s/,/ /g;
		
		$result[$i]->{'extra'} =~ /.*CKTID=\\\"([^\\\"]*)\\\".*/;
		$result[$i]->{'id'} = $1;
		
		$i++;	
	    }
	}
    }

    elsif ($type eq "ciena") {
      
      $telnet->print("RTRV-CRS:::1;");
      $telnet->getline;
      
      # eat up any initial messages
      while (($line = $telnet->getline) !~ /M.*COMPLD/) {}

      # get entire output
      my ($buf) = $telnet->waitfor('/^;$/m');

      my @lines = split(/\n/, $buf);
      
      foreach $line (@lines) {
	
	if ($line =~ /.*\".*FROMENDPOINT.*\".*/) {
	  
	  $line =~ /.*FROMENDPOINT=([^,]*),.*/;
	  $result[$i]->{'from'} = $1;
	  
	  $line =~ /.*TOENDPOINT=([^:]*):.*/;
	  $result[$i]->{'to'} = $1;
	  
	  $line =~ /.*NAME=([^,]*),.*/;
	  $result[$i]->{'name'} = $1;
	  
	  $line =~ /.*FROMTYPE=([^,]*),.*/;
	  $result[$i]->{'fromType'} = $1;
	  
	  $line =~ /.*TOTYPE=([^,]*),.*/;
	  $result[$i]->{'toType'} = $1;
	  
	  $line =~ /.*ALIAS=([^,]*),.*/;
	  $result[$i]->{'alias'} = $1;
	  
	  $line =~ /.*SIZE=([^,]*),.*/;
	  $result[$i]->{'size'} = $1;
	  
	  $line =~ /.*PRIOR=([^,]*),.*/;
	  $result[$i]->{'priority'} = $1;
	  
	  $line =~ /.*CONNSTND=([^,]*),.*/;
	  $result[$i]->{'signalType'} = $1;
	  
	  $line =~ /.*PREEMPTING=([^,]*),.*/;
	  $result[$i]->{'preempting'} = $1;
	  
	  $line =~ /.*PST=([^,]*),.*/;
	  $result[$i]->{'primaryState'} = $1;
	  
	  if ($line =~ /.*SST=([^,]*),.*/) {
	    $result[$i]->{'secondaryState'} = $1;
	  }
	  
	  $i++;
	}
      }
    }
    
    return @result;
  }
		       

sub getAlarms {

    my ($self) = @_;

    my $telnet = $self->{'telnet'};
    my $type = $self->{'type'};
    my $line;
    my $i = 0;
    my @result;

    if ($type eq "ome") {

	$telnet->print("RTRV-ALM-ALL:::1::;");
	$telnet->getline;
	$telnet->getline;
	
	while (($line = $telnet->getline) !~ /.*;.*\n/) {

	    if ($line =~ /.*"([^,]*),([^:]*):([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^:]*):\\\"([^\\]*)\\\",[^:]*:([^-]*)-([^-]*)-([^,]*),:YEAR=([^,]*),MODE=([^\"]*)\"/) {

		$result[$i]->{'equipmentID'} = $1;
		$result[$i]->{'alarmType'} = $2;
		$result[$i]->{'notCode'} = $3;
		$result[$i]->{'condType'} = $4;
		$result[$i]->{'servAffect'} = $5;
		$result[$i]->{'monthDay'} = $6;
		$result[$i]->{'time'} = $7;
		$result[$i]->{'loc'} = $8;
		$result[$i]->{'dir'} = $9;
		$result[$i]->{'desc'} = $10;
		$result[$i]->{'id'} = $11;
		$result[$i]->{'probCause'} = $12;
		$result[$i]->{'docIndex'} = $13;
		$result[$i]->{'year'} = $14;
		$result[$i]->{'mode'} = $15;

		$result[$i]->{'notCode'} =~ s/CR/Critical/g;
		$result[$i]->{'notCode'} =~ s/MJ/Major/g;
		$result[$i]->{'notCode'} =~ s/MN/Minor/g;
		$result[$i]->{'notCode'} =~ s/CL/Clear/g;

		$result[$i]->{'servAffect'} =~ s/NSA/No/g;
		$result[$i]->{'servAffect'} =~ s/SA/Yes/g;

		$result[$i]->{'loc'} =~ s/NEND/Near End/g;
		$result[$i]->{'loc'} =~ s/FEND/Far End/g;
		
		$result[$i]->{'dir'} =~ s/AZ/Start => End/g;
		$result[$i]->{'dir'} =~ s/ZA/Start <= End/g;
		$result[$i]->{'dir'} =~ s/BTH/Both/g;
		$result[$i]->{'dir'} =~ s/NA/N\/A/g;
		$result[$i]->{'dir'} =~ s/RCV/Receive/g;
		$result[$i]->{'dir'} =~ s/TRMT/Transmit/g;

		my @two = split(/-/, $result[$i]->{'monthDay'});
		$result[$i]->{'month'} = $two[0];
		$result[$i]->{'day'} = $two[1];

		$result[$i]->{'time'} =~ s/-/:/g;

		$i++;
	    }    
	}
    }
    
    elsif ($type eq "hdxc") {
      
      $telnet->print("RTRV-ALM-ALL:::1::;");
      $telnet->getline;
      
      my $last = 0;
      
      while ($line = $telnet->getline) {
	
	# if we hit a COMPLD then we know this is the last group of output
	if ($line =~ /^M\s+\d+\s+COMPLD$/) {
	  $last = 1;
	}
	
	# if we hit a ; on its own line, we are done displaying a group of output
	elsif ($line =~ /^;$/) {
	  
	  # if we hit a COMPLD earlier, we are done
	  last if ($last);
	}
	
	elsif ($line =~ /.*"([^,]+),([^:]+):([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]*),([^:]+):\\\"([^\\]+)\\\",.*,\\\"([^\\]+)\\\".*:([^,]+),:YEAR=([^\"]+)"$/) {
	  
	  ($result[$i]->{'equipmentID'}, $result[$i]->{'alarmType'}, $result[$i]->{'notCode'}, $result[$i]->{'condType'},
	   $result[$i]->{'servAffect'}, $result[$i]->{'monthDay'}, $result[$i]->{'time'}, $result[$i]->{'loc'},
	   $result[$i]->{'dir'}, $result[$i]->{'desc'}, $result[$i]->{'aidFormat'}, $result[$i]->{'alarmIDs'}, $result[$i]->{'year'})
	    = ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13);
	  
	  $result[$i]->{'alarmType'} =~ s/COM/Common Equipment/g;
	  $result[$i]->{'alarmType'} =~ s/EQPT/Equipment/g;
	  $result[$i]->{'alarmType'} =~ s/FAC/Facility/g;
	  
	  $result[$i]->{'notCode'} =~ s/CR/Critical/g;
	  $result[$i]->{'notCode'} =~ s/MJ/Major/g;
	  $result[$i]->{'notCode'} =~ s/MN/Minor/g;
	  $result[$i]->{'notCode'} =~ s/CL/Clear/g;
	  
	  $result[$i]->{'condType'} =~ s/ACTLPBK/Active Loopback/g;
	  $result[$i]->{'condType'} =~ s/AIS/Alarm Indication/g;
	  $result[$i]->{'condType'} =~ s/APSB/Switching Byte/g;
	  $result[$i]->{'condType'} =~ s/APSC/Switching Channel/g;
	  $result[$i]->{'condType'} =~ s/APSCM/Switching Channel Match/g;
	  $result[$i]->{'condType'} =~ s/APSMM/Switching Mode Mismatch/g;
	  $result[$i]->{'condType'} =~ s/CONTCOM/Control Comm. Equipment/g;
	  $result[$i]->{'condType'} =~ s/CONTEQPT/Control Equipment/g;
	  $result[$i]->{'condType'} =~ s/EXTERR/External Error/g;
	  $result[$i]->{'condType'} =~ s/FACTERM/Facility\/Circuit Termination/g;
	  $result[$i]->{'condType'} =~ s/FAILTOSW/Failure to Switch/g;
	  $result[$i]->{'condType'} =~ s/FEPRFL/Far End Protection Line/g;
	  $result[$i]->{'condType'} =~ s/FERF/Far End Receive/g;
	  $result[$i]->{'condType'} =~ s/FRCDSW/Forced Switch/g;
	  $result[$i]->{'condType'} =~ s/GP/General Purpose/g;
	  $result[$i]->{'condType'} =~ s/HLDOVRSYNC/Hold Over Sync/g;
	  $result[$i]->{'condType'} =~ s/IMPROPRMVL/Improper Removal/g;
	  $result[$i]->{'condType'} =~ s/INCFAD/Incoming Fading/g;
	  $result[$i]->{'condType'} =~ s/INHSWPR/Protection Switch Inhibited/g;
	  $result[$i]->{'condType'} =~ s/INT-FT/File Transfer Fail/g;
	  $result[$i]->{'condType'} =~ s/INT-P/Internal Primary/g;
	  $result[$i]->{'condType'} =~ s/INT-S/Internal Secondary/g;
	  $result[$i]->{'condType'} =~ s/INTSFT/Software Fault/g;
	  $result[$i]->{'condType'} =~ s/INT/Internal Hardware/g;
	  $result[$i]->{'condType'} =~ s/LOA/Loss of Association/g;
	  $result[$i]->{'condType'} =~ s/LOCKOUT/Lockout/g;
	  $result[$i]->{'condType'} =~ s/LOF/Loss of Frame/g;
	  $result[$i]->{'condType'} =~ s/LOS/Loss of Signal/g;
	  $result[$i]->{'condType'} =~ s/MANAADDRDRP/Manual Area Addr Drop/g;
	  $result[$i]->{'condType'} =~ s/MANSW/Manual Switch/g;
	  $result[$i]->{'condType'} =~ s/MANWKSWPR/Manual Switch -> Protection/g;
	  $result[$i]->{'condType'} =~ s/MA/Multiple Access/g;
	  $result[$i]->{'condType'} =~ s/MISC/Misc./g;
	  $result[$i]->{'condType'} =~ s/PWR/Volt Power Supply/g;
	  $result[$i]->{'condType'} =~ s/SECBUFTHEX/Security Buffer Threshold/g;
	  $result[$i]->{'condType'} =~ s/SFI/Sync Failure/g;
	  $result[$i]->{'condType'} =~ s/SLMF/Signal Label Mismatch/g;
	  $result[$i]->{'condType'} =~ s/SWEX/Switch Equipment/g;
	  $result[$i]->{'condType'} =~ s/SYNC-CLK/Sync Unit/g;
	  $result[$i]->{'condType'} =~ s/SYNC-IN-PROC/Sync in Process/g;
	  $result[$i]->{'condType'} =~ s/SYNC-LCK-FAIL/Sync Lock/g;
	  $result[$i]->{'condType'} =~ s/SYNC/Oscillating Sync/g;
	  $result[$i]->{'condType'} =~ s/T-S/Threshold Crossing Alert/g;
	  $result[$i]->{'condType'} =~ s/T-T1S-NE-RX/T1 Recv TCA/g;
	  $result[$i]->{'condType'} =~ s/T-T1S-NE-TX/T1 Trans TCA/g;
	  $result[$i]->{'condType'} =~ s/T-T2S-NE-RX/T2 Recv TCA/g;
	  $result[$i]->{'condType'} =~ s/T-T2S-NE-TX/T2 Trans TCA/g;
	  $result[$i]->{'condType'} =~ s/WKSWPR/Working Equipment Switch -> Protection/g;
	  
	  $result[$i]->{'servAffect'} =~ s/NSA/No/g;
	  $result[$i]->{'servAffect'} =~ s/SA/Yes/g;
	  
	  my @two = split(/-/, $result[$i]->{'monthDay'});
	  $result[$i]->{'month'} = $two[0];
	  $result[$i]->{'day'} = $two[1];
	  
	  $result[$i]->{'time'} =~ s/-/:/g;
	  
	  $result[$i]->{'loc'} =~ s/NEND/Near End/g;
	  $result[$i]->{'loc'} =~ s/FEND/Far End/g;
	  
	  $result[$i]->{'dir'} =~ s/AZ/Start => End/g;
	  $result[$i]->{'dir'} =~ s/ZA/Start <= End/g;
	  $result[$i]->{'dir'} =~ s/BTH/Both/g;
	  $result[$i]->{'dir'} =~ s/NA/N\/A/g;
	  $result[$i]->{'dir'} =~ s/RCV/Receive/g;
	  $result[$i]->{'dir'} =~ s/TRMT/Transmit/g;
	  
	  my @three = split(/-/, $result[$i]->{'alarmIDs'});
	  $result[$i]->{'id'} = $three[0];
	  $result[$i]->{'probCause'} = $three[1];
	  $result[$i]->{'docIndex'} = $three[2];
	  
	  $i++;
	}
      }
    }

    elsif ($type eq "ons15454") {

	$telnet->print("RTRV-ALM-ALL:::1;");
	$telnet->getline;

	while (($line = $telnet->getline) !~ /.*>.*\n/) {
	  
	    if ($line =~ /.*"([^,]*),([^:]*):([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),,:([^,]*),([^\"]*)"$/) {
		
		($result[$i]->{'equipmentID'}, $result[$i]->{'alarmType'}, $result[$i]->{'notCode'}, $result[$i]->{'condType'},
		 $result[$i]->{'servAffect'}, $result[$i]->{'date'}, $result[$i]->{'time'}, $result[$i]->{'desc'}, $result[$i]->{'details'})
		    = ($1, $2, $3, $4, $5, $6, $7, $8, $9);
		
		$result[$i]->{'alarmType'} =~ s/1GFC/1 Gigabit Fiber Channel/g;
		$result[$i]->{'alarmType'} =~ s/1GFICON/1 Gigabit FICON/g;
		$result[$i]->{'alarmType'} =~ s/2GFC/2 Gigabit Fiber Channel/g;
		$result[$i]->{'alarmType'} =~ s/BITS/Building Integrated Timing Supply/g;
		$result[$i]->{'alarmType'} =~ s/CLNT/Client Facility MXP\/TXP/g;
		$result[$i]->{'alarmType'} =~ s/COM/Common/g;
		$result[$i]->{'alarmType'} =~ s/ENV/Environment/g;
		$result[$i]->{'alarmType'} =~ s/EQPT/Equipment/g;
		$result[$i]->{'alarmType'} =~ s/FSTE/Fast Ethernet Port/g;
		$result[$i]->{'alarmType'} =~ s/GIGE/Gigabit Ethernet Port/g;
		$result[$i]->{'alarmType'} =~ s/OCH/Optical Channel/g;
		$result[$i]->{'alarmType'} =~ s/OMS/Optical Multiplex Section/g;
		$result[$i]->{'alarmType'} =~ s/OTS/Optical Transport Section/g;
		$result[$i]->{'alarmType'} =~ s/POS/POS Port/g;
		$result[$i]->{'alarmType'} =~ s/SYNCN/Synchronization/g;
		$result[$i]->{'alarmType'} =~ s/TCC/TCC Card/g;
		
		$result[$i]->{'notCode'} =~ s/CR/Critical/g;
		$result[$i]->{'notCode'} =~ s/MJ/Major/g;
		$result[$i]->{'notCode'} =~ s/MN/Minor/g;
		$result[$i]->{'notCode'} =~ s/CL/Clear/g;
		$result[$i]->{'notCode'} =~ s/NA/Not Alarmed/g;
		$result[$i]->{'notCode'} =~ s/NR/Not Reported/g;
		
		$result[$i]->{'servAffect'} =~ s/NSA/No/g;
		$result[$i]->{'servAffect'} =~ s/SA/Yes/g;

		$result[$i]->{'desc'} =~ s/\\\"//g;

		my @two = split(/-/, $result[$i]->{'date'});
		$result[$i]->{'month'} = $two[0];
		$result[$i]->{'day'} = $two[1];

		$result[$i]->{'time'} =~ s/-/:/g;
	    
		$i++;
	    }
	}
    }

    elsif ($type eq "ciena") {

	$telnet->buffer_empty;
	$telnet->print("RTRV-ALM-ALL:::1;");
	$telnet->getline;

	# eat up any initial messages
	while (($line = $telnet->getline) !~ /M.*COMPLD/) {}
	
	# get entire output
	my ($buf) = $telnet->waitfor('/^;$/m');
	
	my @lines = split(/\n/, $buf);
	
	# aid aidType aisnc condType servEffect date time loc dir desc aidDetection
	foreach $line (@lines) {
	    
	    if ($line =~ /.*\"([^,]*),([^:]*):([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^:]*):\\\"([^\\\"]*)\\\",([^\"]*)\".*/) {

		$result[$i]->{'id'} = $1;
		$result[$i]->{'type'} = $2;
		$result[$i]->{'severity'} = $3;
		$result[$i]->{'condType'} = $4;
		$result[$i]->{'servAffect'} = $5;
		$result[$i]->{'date'} = $6;
		$result[$i]->{'time'} = $7;
		$result[$i]->{'location'} = $8;
		$result[$i]->{'direction'} = $9;
		$result[$i]->{'desc'} = $10;
		$result[$i]->{'info'} = $11;

		$result[$i]->{'severity'} =~ s/CL/Cleared/g;
		$result[$i]->{'severity'} =~ s/CR/Critical/g;
		$result[$i]->{'severity'} =~ s/MJ/Major/g;
		$result[$i]->{'severity'} =~ s/MN/Minor/g;
		$result[$i]->{'severity'} =~ s/NR/Not Reported/g;
		$result[$i]->{'severity'} =~ s/NA/Warning/g;

		$result[$i]->{'servAffect'} =~ s/NSA/No/g;
		$result[$i]->{'servAffect'} =~ s/SA/Yes/g;

		$i++;
	    }
	}
    }

    elsif ($type eq "infinera") {

      $telnet->print("RTRV-ALM-ALL:::1;");

      while ($line = $telnet->getline) {

	# done if you hit a ; on its own line
	last if ($line =~ /^;$/);

	if ($line =~ /\s+"([^,]*),([^:]*):([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^:]*):"*([^"]*)"/) {

	  $result[$i]->{'id'} = $1;
	  $result[$i]->{'type'} = $2;
	  $result[$i]->{'notificationCode'} = $3;
	  $result[$i]->{'conditionType'} = $4;
	  $result[$i]->{'serviceAffective'} = $5;
	  $result[$i]->{'date'} = $6;
	  $result[$i]->{'time'} = $7;
	  $result[$i]->{'location'} = $8;
	  $result[$i]->{'direction'} = $9;
	  $result[$i]->{'description'} = $10;
	  $i++;
	}
      }
    }

    return @result;
}

sub getInventory {

    my ($self) = @_;

    my $telnet = $self->{'telnet'};
    my $type = $self->{'type'};
    my $line;
    my $i = 0;
    my @result;
    
    if ($type eq "ome") {

	$telnet->print("RTRV-INVENTORY:::1;");
	$telnet->getline;
	$telnet->getline;
		
	while (($line = $telnet->getline) !~ /.*;.*\n/) {
	    
	    if ($line =~ /^\s*"([^:]*)::CTYPE=\\"([^\\]*)\\",PEC=([^,]*),REL=([^,]*),CLEI=([^,]*),SER=([^,|^\"]*)(.*)/) {
		
		$result[$i]->{'name'} = $1;
		$result[$i]->{'type'} = $2;
		$result[$i]->{'pec'} = $3;
		$result[$i]->{'release'} = $4;
		$result[$i]->{'clei'} = $5;
		$result[$i]->{'serial'} = $6;
		
		my $rest = $7;
		
		if ($rest =~ /,MDAT=([^,]*),AGE=([^,]*),ONSC=([^\"]*)"/) {
     
		    $result[$i]->{'date'} = $1;
		    $result[$i]->{'age'} = $2;
		    $result[$i]->{'onsc'} = $3;
		}

		if ($result[$i]->{'date'} ne "") {
		    
		    my @two = split(/-/, $result[$i]->{'date'});
		    
		    my $year = $two[0];
		    my $week = $two[1];
		    my $month;
		    my $day;
		    
		    ($year, $month, $day) = Monday_of_Week($week, $year);
		    
		    $month = Month_to_Text($month);
		    $result[$i]->{'date'} = "$month $year";
		}

		$i++;
	    }
	}
    }

    elsif ($type eq "hdxc") {
      
      $telnet->print("RTRV-INVENTORY:::1;");
      $telnet->getline;
      
      my $last = 0;
      
      while (($line = $telnet->getline) !~ /.*;.*\n/) {
	
	# if we hit a COMPLD then we know this is the last group of output
	if ($line =~ /^M\s+\d+\s+COMPLD$/) {
	  $last = 1;
	}
	
	# if we hit a ; on its own line, we are done displaying a group of output
	elsif ($line =~ /^;$/) {
	  
	  # if we hit a COMPLD earlier, we are done
	  last if ($last);
	}
	
	elsif ($line =~ /^\s*"([^:]*)::PEC=([^,]*),MDAT=([^,]*),CPTYPE=([^,]*),CPSUBTYPE=([^,]*),REL=([^,]*),SER=([^,]*),CLEI=([^\"]*)"$/) {
	  
	  if ($4 ne "FILLER") {
	    
	    ($result[$i]->{'name'}, $result[$i]->{'pec'}, $result[$i]->{'date'}, $result[$i]->{'type'}, $result[$i]->{'subtype'},
	     $result[$i]->{'release'}, $result[$i]->{'serial'}, $result[$i]->{'clei'}) = 
	       ($1, $2, $3, $4, $5, $6, $7, $8);
	    
	    if ($3 ne "") {
	      
	      $3 =~ /^\s*([^w]*)wk(.*).*$/;
	      
	      my $year = $1;
	      my $week = $2;
	      my $month;
	      my $day;
	      
	      ($year, $month, $day) = Monday_of_Week($week, $year);
	      
	      $month = Month_to_Text($month);
	      $result[$i]->{'date'} = "$month $year";
	    }
	    
	    $i++;
	  }
	}
      }
    }
    
    elsif ($type eq "ons15454") {

	$telnet->print("RTRV-INV::ALL:1;");
	$telnet->getline;

	while (($line = $telnet->getline) !~ /.*>.*\n/) {
	    
                              #aid   aidtype  ...
	    if ($line =~ /.*"([^,]+),([^:]+)::([^\"]*)"$/) {

		$result[$i]->{'name'} = $1;
		$result[$i]->{'type'} = $2;
		
		my $details = $3;

		$details =~ /.*PN=([^,]+),.*/;
		$result[$i]->{'partNum'} = $1;

		$details =~ /.*HWREV=([^,]+),.*/;
		$result[$i]->{'hwRev'} = $1;

		$details =~ /.*FWREV=([^,]+),.*/;
		$result[$i]->{'fwRev'} = $1;

		$details =~ /.*SN=([^,]+),.*/;
		$result[$i]->{'serial'} = $1;

		$details =~ /.*CLEI=([^,]+),.*/;
		$result[$i]->{'clei'} = $1;

		$i++;
	    }
	}
    }

    elsif ($type eq "ciena") {

      # first get the serial of the chassis (separate command)
      $telnet->print("RTRV-EQPT::1:1;");
      $telnet->getline;

      # eat up any initial messages
      while (($line = $telnet->getline) !~ /M.*COMPLD/) {}
      
      # get entire output
      my ($buf) = $telnet->waitfor('/^;$/m');
      
      my @lines = split(/\n/, $buf);
      
      foreach $line (@lines) {
	
	#if ($line =~ /.*\"([^,]*),EQPTNAME=([^,]*),.*TYPE=([^,]*),.*SRLNUM=([^,]*),.*(?:ICPKTYPE=([^,]*))?.*(?:CPKFW=([^,]*))?.*(?:CPKSW=([^,]*))?.*(?:CPKHW=([^,]*))?.*(?:CLEI=([^,]*))?.*/) 
	if ($line =~ /.*\".*\".*/ && $line !~ /.*TIME.*/) {
	  
	  if ($line =~ /.*\"([^,]*),.*/) {
	    $result[$i]->{'id'} = $1;
	  }
	  
	  if ($line =~ /.*EQPTNAME=([^,]*).*/) {
	    $result[$i]->{'name'} = $1;
	  }
	  
	  if ($line =~ /.*TYPE=([^,]*).*/) {
	    $result[$i]->{'type'} = $1;
	  }
	  
	  if ($line =~ /.*SRLNUM=([^,]*).*/) {
	    $result[$i]->{'serial'} = $1;
	  }
	  
	  if ($line =~ /.*ICPKTYPE=([^,]*).*/) {
	    $result[$i]->{'moduleType'} = $1;
	  }
	  
	  if ($line =~ /.*CPKFW=([^,]*).*/) {
	    $result[$i]->{'firmwareVersion'} = $1;
	  }

	  if ($line =~ /.*CPKSW=([^,]*).*/) {
	    $result[$i]->{'softwareVersion'} = $1;
	  }	    

	  if ($line =~ /.*CPKHW=([^,]*).*/) {
	    $result[$i]->{'hardwareVersion'} = $1;
	    $result[$i]->{'hardwareVersion'} =~ s/;//;
	    $result[$i]->{'hardwareVersion'} =~ s/ //;
	  }
	    
	  if ($line =~ /.*CLEI=([^,]*).*/) {
	    $result[$i]->{'clei'} = $1;
	  }
	  
	  if ($line =~ /.*LASERST=([^,]*).*/) {
	    $result[$i]->{'laser'} = $1;
	  }
	  
	  if ($line =~ /.*PORTCONFIGMODE=([^"]*)"/) {
	    
	    $result[$i]->{'configMode'} = $1;
	  }
	  
	  $i++;
	}
      }
      
      $telnet->print("RTRV-EQPT::ALL:1;");
      $telnet->getline;
      
      # eat up any initial messages
      while (($line = $telnet->getline) !~ /M.*COMPLD/) {}
      
      # get entire output
      my ($buf) = $telnet->waitfor('/^;$/m');
      
      my @lines = split(/\n/, $buf);
      
      foreach $line (@lines) {
	
	#if ($line =~ /.*\"([^,]*),EQPTNAME=([^,]*),.*TYPE=([^,]*),.*SRLNUM=([^,]*),.*(?:ICPKTYPE=([^,]*))?.*(?:CPKFW=([^,]*))?.*(?:CPKSW=([^,]*))?.*(?:CPKHW=([^,]*))?.*(?:CLEI=([^,]*))?.*/) 
	if ($line =~ /.*\".*\".*/ && $line !~ /.*TIME.*/) {
	  
	  $line =~ /.*\"([^,]*),.*/;
	  $result[$i]->{'id'} = $1;
	  
	  $line =~ /.*EQPTNAME=([^,]*).*/;
	  $result[$i]->{'name'} = $1;
	  
	  $line =~ /.*TYPE=([^,]*).*/;
	  $result[$i]->{'type'} = $1;
	  
	  $line =~ /.*SRLNUM=([^,]*).*/;
	  $result[$i]->{'serial'} = $1;
	  
	  $line =~ /.*ICPKTYPE=([^,]*).*/;
	  $result[$i]->{'moduleType'} = $1;
	  
	  $line =~ /.*CPKFW=([^,]*).*/;
	  $result[$i]->{'firmwareVersion'} = $1;
	  
	  $line =~ /.*CPKSW=([^,]*).*/;
	  $result[$i]->{'softwareVersion'} = $1;
	  
	  $line =~ /.*CPKHW=([^,]*).*/;
	  $result[$i]->{'hardwareVersion'} = $1;
	  $result[$i]->{'hardwareVersion'} =~ s/;//;
	  $result[$i]->{'hardwareVersion'} =~ s/ //;
	  
	  $line =~ /.*CLEI=([^,]*).*/;
	  $result[$i]->{'clei'} = $1;
	  
	  if ($line =~ /.*LASERST=([^,]*).*/) {
	    $result[$i]->{'laser'} = $1;
	  }
	  
	  if ($line =~ /.*PORTCONFIGMODE=([^"]*)"/) {
	    
	    $result[$i]->{'configMode'} = $1;
	  }
	  
	  $i++;
	}
      }
    }
    
    elsif ($type eq "infinera") {

      $telnet->print("RTRV-EQPT::ALL:1;");
      $telnet->getline;

      while ($line = $telnet->getline) {

	# done if you hit a ; on its own line
	last if ($line =~ /^;$/);

	if ($line =~ /^\s+".*"$/) {

	  ($result[$i]->{'id'}, $result[$i]->{'type'}) = $line =~ /^\s+"([^:]*):([^:]*):/;
	  $result[$i]->{'description'} = $1 if ($line =~ /LABEL=([^,]*),/);
	  $result[$i]->{'provisionedType'} = $1 if ($line =~ /PROVTYPE=([^,]*),/);
	  $result[$i]->{'installedType'} = $1 if ($line =~ /INSTTYPE=([^,]*),/);
	  $result[$i]->{'clei'} = $1 if ($line =~ /CLEI=([^,]*),/);
	  $result[$i]->{'partNumber'} = $1 if ($line =~ /PARTNO=([^,]*),/);
	  $result[$i]->{'serial'} = $1 if ($line =~ /SERNO=([^,]*),/);
	  $result[$i]->{'softwareVersion'} = $1 if ($line =~ /SWVERS=([^,]*),/);
	  $result[$i]->{'hardwareVersion'} = $1 if ($line =~ /HWVERS=([^,]*),/);
	  $result[$i]->{'firmwareVersion'} = $1 if ($line =~ /FWVERS=([^,]*),/);
	  $result[$i]->{'manufacturedDate'} = $1 if ($line =~ /MFGDATE=([^,]*),/);
	  $result[$i]->{'vendorId'} = $1 if ($line =~ /VENDID=([^,]*),/);
	  $result[$i]->{'bootDate'} = $1 if ($line =~ /BOOTDATE=([^,]*),/);
	  $result[$i]->{'bootTime'} = $1 if ($line =~ /BOOTTIME=([^,]*),/);
	  $result[$i]->{'bootReason'} = $1 if ($line =~ /BOOTREAS=([^,]*),/);
	  my ($pst, $sst) = $line =~ /:(IS|OOS)-([^"]*)"$/;
	  $result[$i]->{'state'} = "$pst-$sst";
	  $i++;
	}
      }
    }
    
    return @result;
}

# get optical transport systems on ONS15454
# also LINE / OCG on infinera
sub getOpticals {

  my ($self) = @_;
  
  my $telnet = $self->{'telnet'};
  my $type = $self->{'type'};
  my $line;
  my $i = 0;
  my @result;

  # only on ons15454/infinera!
  return undef if ($type != "ons15454" && $type != "infinera");

  if ($type eq "ons15454") {
    
    $telnet->print("RTRV-OTS::ALL:1;");
    $telnet->getline;
    
    while (($line = $telnet->getline) !~ /.*>.*\n/) {
      
      if ($line =~ /.*"([^:]*)::.*OPWR=([^,]*),.*"/) {
	
	$result[$i]->{'line'} = $1;
	$result[$i]->{'power'} = $2;
	$i++;
      }
    }
  }
  elsif ($type eq "infinera") {

    $telnet->print("RTRV-BAND::ALL:1;");
    $telnet->getline;

    while ($line = $telnet->getline) {

      last if ($line =~ /^;$/);

      if ($line =~ /.*"([^:]*):BAND:LABEL=([^,]*),MAXOCGS=([^,]*),CHANPLAN=([^,]*),HISTSTATS=([^:]*):([^"]*)"/) {

	$result[$i]->{'id'} = $1;
	$result[$i]->{'type'} = "BAND";
	$result[$i]->{'description'} = $2;
	$result[$i]->{'max'} = $3;
	$result[$i]->{'chanplan'} = $4;
	$result[$i]->{'histstats'} = $5;
	$result[$i]->{'state'} = $6;
	$i++;
      }
    }

    $telnet->print("RTRV-OCG::ALL:1;");
    $telnet->getline;

    while ($line = $telnet->getline) {

      last if ($line =~ /^;$/);

      if ($line =~ /.*"([^:]*):OCG:LABEL=([^,]*),.*"$/) {

	$result[$i]->{'id'} = $1;
	$result[$i]->{'type'} = "OCG";
	$result[$i]->{'description'} = $2;

	if ($line =~ /.*PROVDLM=([^,]*),.*/) {

	  $result[$i]->{'provisionedDLM'} = $1;
	}
	if ($line =~ /.*DISCDLM=([^,]*),.*/) {

	  $result[$i]->{'discoveredDLM'} = $1;
	}
	if ($line =~ /.*OCGNUM=([^,]*),.*/) {
  
	  $result[$i]->{'ocgnum'} = $1;
	}
	if ($line =~ /.*HISTSTATS=([^:]*):.*/) {
  
	  $result[$i]->{'histstats'} = $1;
	}
	if ($line =~ /.*RMTOCG=([^,]*),.*/) {

	  $result[$i]->{'rmtocg'} = $1;
	}
	if ($line =~ /.*TECTRL=([^,]*),.*/) {

	  $result[$i]->{'tectrl'} = $1;
	}
	if ($line =~ /.*AUTODISCSTATE=([^,]*),.*/) {
  
	  $result[$i]->{'autoDiscoveryState'} = $1;
	}
	$line =~ /.*:([^"]*)"/;
	$result[$i]->{'state'} = $1;
	$i++;
      }
    }
  }

  return @result;
}

# get ethernet 10x1G port on ciena
sub getEthernet1G {
  
  my ($self, $aid) = @_;
  
  my $telnet = $self->{'telnet'};
  my $type = $self->{'type'};
  my $line;
  my $result;
  
  # only on cienas!
  return undef if ($type != "ciena");
  
  $telnet->send("RTRV-GIGE::$aid:1;");
  $telnet->getline;
  
  # eat up any initial messages
  while (($line = $telnet->getline) !~ /M.*COMPLD/) {}
  
  # get entire output
  my ($buf) = $telnet->waitfor('/^;$/m');
  
  my @lines = split(/\n/, $buf);
  
  foreach $line (@lines) {
    
    if ($line =~ /.*\".*\".*/ && $line =~ /.*ALIAS.*/) {
      
      $line =~ /"([^,]*),/;
      $result->{'port'} = $1;
      
      if ($line =~ /ALIAS=([^,]*)/) {
	$result->{'alias'} = $1;
      }

      if ($line =~ /PST=([^,]*),/) {
	$result->{'state'} = $1;
      }

      if ($line =~ /ETHERPHY=([^,]*),/) {
	$result->{'ethernet'} = $1;
      }
    }
  }
  
  return $result;
}

# get ethernet ETTP ports on ciena
sub getEthernet {
  
  # THIS IS TOO DANGEROUS
  return undef;

  my ($self) = @_;
  
  my $telnet = $self->{'telnet'};
  my $type = $self->{'type'};
  my $line;
  my $i = 0;
  my @result;
  
  # only on cienas!
  return undef if ($type != "ciena");
  
  $telnet->send("RTRV-GIGE::ALL:1;");
  $telnet->getline;
  
  # eat up any initial messages
  while (($line = $telnet->getline) !~ /M.*COMPLD/) {}
  
  $telnet->timeout(2);
  
  while ($line = $telnet->getline) {
    
    if ($line =~ /.*\".*\".*/ && $line =~ /.*ALIAS.*/) {
      
      $line =~ /"([^,]*),/;
      $result[$i]->{'port'} = $1;
      
      $line =~ /ETHERPHY=([^,]*),/;
      $result[$i]->{'type'} = $1;
      
      if ($line =~ /ALIAS=([^,]*)/) {
	$result[$i]->{'alias'} = $1;
      }

      if ($line =~ /PST=([^,]*),/) {
	$result[$i]->{'state'} = $1;
      }
      
      $i++;
    }
  }
  
  return @result;
}

# get sonet ports on ciena
sub getSonet {

  my ($self) = @_;
  
  my $telnet = $self->{'telnet'};
  my $type = $self->{'type'};
  my $line;
  my $i = 0;
  my @result;

  # only on cienas!
  return undef if ($type ne "ciena");

  $telnet->send("RTRV-OCN::ALL:1;");
  $telnet->getline;
  
  # eat up any initial messages
  while (($line = $telnet->getline) !~ /M.*COMPLD/) {}
  
  # get entire output
  my ($buf) = $telnet->waitfor('/^;$/m');
  
  my @lines = split(/\n/, $buf);
  
  foreach $line (@lines) {
    
    if ($line =~ /.*\".*\".*/ && $line =~ /.*ITYPE.*/) {
      
      $line =~ /"([^,]*),/;
      $result[$i]->{'port'} = $1;
      
      $line =~ /RATE=([^,]*),/;
      $result[$i]->{'type'} = $1;
      
      if ($line =~ /ALIAS=([^,]*)/) {
	$result[$i]->{'alias'} = $1;
      }

      if ($line =~ /SIGNALST=([^,]*)/) {
	$result[$i]->{'signal'} = $1;
      }

      if ($line =~ /PST=([^,]*),/) {
	$result[$i]->{'state'} = $1;
      }
      
      $i++;
    }
  }
 
  return @result;
}

sub send {

    my $self = shift;
    my ($cmd) = @_;
    my $telnet = $self->{'telnet'};
    my $line;
    my $buf;

    # set longer timeout for ome
    if ($self->{'type'} eq "ome") {
	
	$telnet->timeout(5);
    }

    $telnet->print($cmd);
    
    if ($self->{'type'} eq "ons15454") {

	$telnet->getline;

	while (($line = $telnet->getline) !~ /.*>.*\n/) {
	    $buf .= $line;
	}
    }

    elsif ($self->{'type'} eq "hdxc") {

      $telnet->getline;
      
      my $last = 0;
      
      while (($line = $telnet->getline)) {

	$buf .= $line;
	
	# if we hit a COMPLD then we know this is the last group of output
	if ($line =~ /^M\s+\d+\s+COMPLD$/) {
	  $last = 1;
	}
	
	# if we hit a ; on its own line, we are done displaying a group of output
	elsif ($line =~ /^;$/) {
	  
	  # if we hit a COMPLD earlier, we are done
	  last if ($last);
	}
      }
    }

    elsif ($self->{'type'} eq "ome") {

	$telnet->getline;
	$telnet->getline;
	$telnet->getline;

	while (($line = $telnet->getline) !~ /.*;.*\n/) {
	    $buf .= $line;
	}
    }

    elsif ($self->{'type'} eq "ciena") {

      # eat up any initial messages
     while (($line = $telnet->getline) !~ /M.*COMPLD/) { }
      
    #  $buf .= $line;
      my ($result) = $telnet->waitfor('/^;$/m');
      $buf .= $result;
    }

    elsif ($self->{'type'} eq "infinera") {

      # the output is done when a ; on a line is reached
      while ($line = $telnet->getline) {
	
	$buf .= $line;
	last if ($line =~ /^;$/);
      }
    }
    
    return $buf;
}

1;
