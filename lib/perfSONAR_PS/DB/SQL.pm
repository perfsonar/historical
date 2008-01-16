package perfSONAR_PS::DB::SQL;

use fields 'NAME', 'USER', 'PASS', 'SCHEMA', 'HANDLE';

our $VERSION = 0.02;

use DBI;
use Log::Log4perl qw(get_logger);
use perfSONAR_PS::Common;

sub new {
  my ($package, $name, $user, $pass, $schema) = @_;   

  my $self = fields::new($package);

  if(defined $name and $name ne "") {
    $self->{NAME} = $name;
  }  
  if(defined $user and $user ne "") {
    $self->{USER} = $user;
  }  
  if(defined $pass and $pass ne "") {
    $self->{PASS} = $pass;
  }      
  if(defined $schema and $schema ne "") {
    @{$self->{SCHEMA}} = @{$schema};
  } 
  return $self;
}


sub setName {
  my ($self, $name) = @_;  
  my $logger = get_logger("perfSONAR_PS::DB::SQL");
  if(defined $name and $name ne "") {
    $self->{NAME} = $name;
  }
  else {
    $logger->error("Missing argument.");
  }
  return;
}


sub setUser {
  my ($self, $user) = @_;  
  my $logger = get_logger("perfSONAR_PS::DB::SQL");
  if(defined $user and $user ne "") {
    $self->{USER} = $user;
  }
  else {
    $logger->error("Missing argument.");
  }
  return;
}


sub setPass {
  my ($self, $pass) = @_;  
  my $logger = get_logger("perfSONAR_PS::DB::SQL");
  if(defined $pass and $pass ne "") {
    $self->{PASS} = $pass;
  }
  else {
    $logger->error("Missing argument.");
  }
  return;
}


sub setSchema {
  my ($self, $schema) = @_;  
  my $logger = get_logger("perfSONAR_PS::DB::SQL");
  if(defined $schema and $schema ne "") {
    @{$self->{SCHEMA}} = @{$schema};
  } 
  else {
    $logger->error("Missing argument.");
  }
  return;
}


sub openDB {
  my ($self) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::SQL");
  my $retval;

  eval {
    my %attr = (
      RaiseError => 1,
    );	   
    $self->{HANDLE} = DBI->connect(
      $self->{NAME},
      $self->{USER},
      $self->{PASS}, 
      \%attr
    ) or $logger->error("Database \"".$self->{NAME}."\" unavailable with user \"".$self->{NAME}."\" and password \"".$self->{PASS}."\".");
  };
  if($@) {
    $logger->error("Open error \"".$@."\".");
    $retval = -1;
  } else {
    $retval = 0;
  }

  return $retval;
}


sub closeDB {
  my ($self) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::SQL");
  eval {   
    $self->{HANDLE}->disconnect();
  };
  if($@) {
    $logger->error("Close error \"".$@."\".");
    $retval = -1;
  } else {
    $retval = 0;
  }
  return $retval;
}


sub query {
  my ($self, $query) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::SQL");
  my $results = (); 
  if(defined $query and $query ne "") {  
    $logger->debug("Query \"".$query."\" received.");
    eval {
      my $sth = $self->{HANDLE}->prepare($query);
      $sth->execute() or $logger->error("Query error on statement \"".$query."\".");      	      
      $results  = $sth->fetchall_arrayref;
    };
    if($@) {
      $logger->error("Query error \"".$@."\".");
      $results = -1;
    } 
  }
  else {
    $logger->error("Missing argument.");
    $results = -1;
  } 
  return $results;
}


sub count {
  my ($self, $query) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::SQL");
  my $results; 
  if(defined $query and $query ne "") { 
    $logger->debug("Query \"".$query."\" received.");   
    eval {
      my $sth = $self->{HANDLE}->prepare($query);
      $sth->execute() or $logger->error("Query error on statement \"".$query."\".");	
      $results = $sth->fetchall_arrayref;  
    };      
    if($@) {
      $logger->error("Query error \"".$@."\" on statement \"".$query."\".");
      return -1;
    } 
  } 
  else { 
    $logger->error("Missing argument.");
    return -1;
  } 
  return $#{$results}+1;
}


sub insert {
  my ($self, $table, $argvalues) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::SQL");
  if((defined $table and $table ne "") and 
     (defined $argvalues and $argvalues ne "")) {
    my %values = %{$argvalues};
    my $insert = "insert into " . $table . " (";
    for(my $x = 0; $x <= $#{$self->{SCHEMA}}; $x++) {
      if($x == 0) {
        $insert = $insert.$self->{SCHEMA}->[$x];
      }
      else {
        $insert = $insert.", ".$self->{SCHEMA}->[$x];
      }
    }
    $insert = $insert.") values (";
    for(my $x = 0; $x <= $#{$self->{SCHEMA}}; $x++) {
      if($x == 0) {
        $insert = $insert."?";
      }
      else {
        $insert = $insert.", ?";
      }
    }  
    $insert = $insert.")";
    $logger->debug("Insert \"".$insert."\" prepared.");
    eval {
      my $sth = $self->{HANDLE}->prepare($insert);
      for(my $x = 0; $x <= $#{$self->{SCHEMA}}; $x++) {   
        $sth->bind_param($x+1, $values{$self->{SCHEMA}->[$x]});
      }
      $sth->execute() or $logger->error("Insert error on statement \"".$insert."\".");		      
    };
    if($@) {
      $logger->error("Insert error \"".$@."\" on statement \"".$insert."\".");
      return -1;
    }     
  }
  else {
    $logger->error("Missing argument.");
    return -1;
  } 
  return 1;  
}

sub update {
  my ($self, $table, $wherevalues, $updatevalues) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::SQL");
  if((defined $table and $table ne "") and
     (defined $wherevalues and $wherevalues ne "") and
     (defined $updatevalues and $updatevalues ne "")) {
    my $first;
    my %where = %{$wherevalues};
    my %values = %{$updatevalues};

    my $where = "";
    foreach $var (keys %where) {
      $where .= " and " if ($where ne "");
      $where .= $var." = ".$where{$var};
    }
 
    my $values = "";
    foreach $var (keys %values) {
      $values .= ", " if ($values ne "");
      $values .= $var." = ".$values{$var};
    }

    my $sql = "update " . $table . " set " . $values . " where " . $where;

    $logger->debug("Update \"".$sql."\" prepared.");
    eval {
      my $sth = $self->{HANDLE}->prepare($sql);
      $sth->execute() or $logger->error("Update error on statement \"".$sql."\".");
    };
    if($@) {
      $logger->error("Update error \"".$@."\" on statement \"".$sql."\".");
      return -1;
    }
  }
  else {
    $logger->error("Missing argument.");
    return -1;
  } 
  return 1;
}

sub remove {
  my ($self, $delete) = @_;
  my $logger = get_logger("perfSONAR_PS::DB::SQL");
  if(defined $delete and $delete ne "") {
    $logger->debug("Delete \"".$delete."\" received.");
    eval {     
      my $sth = $self->{HANDLE}->prepare($delete);
      $sth->execute() or $logger->error("Remove error on statement \"".$delete."\".");		      
    };
    if($@) {	
      $logger->error("Remove error \"".$@."\" on statement \"".$delete."\".");
      return -1;
    }     
  }
  else {
    $logger->error("Missing argument.");
    return -1;
  }    
  return 1;
}


1;


__END__
=head1 NAME

perfSONAR_PS::DB::SQL - A module that provides methods for dealing with common SQL databases.

=head1 DESCRIPTION

This module creates common use cases with the helpf of the DBI module.  The module is to 
be treated as an object, where each instance of the object represents a direct connection 
to a single database and collection.  Each method may then be invoked on the object for 
the specific database.  

=head1 SYNOPSIS

    use perfSONAR_PS::DB::SQL;

    my @dbSchema = ("id", "time", "value", "eventtype", "misc");
    my $db = new perfSONAR_PS::DB::SQL(
      "DBI:SQLite:dbname=/home/jason/Netradar/MP/SNMP/netradar.db", 
      "",
      "",
      \@dbSchema
    );

    # or also:
    # 
    # my $db = new perfSONAR_PS::DB::SQL;
    # $db->setName("DBI:SQLite:dbname=/home/jason/netradar/MP/SNMP/netradar.db");
    # $db->setUser("");
    # $db->setPass("");    
    # $db->setSchema(\@dbSchema);     

    if ($db->openDB == -1) {
      print "Error opening database\n";
    }

    my $count = $db->count("select * from data");
    if($count == -1) {
      print "Error executing count statement\n";
    }
    else {
      print "There are " , $db->count("select * from data") , " rows in the database.\n";
    }

    my $result = $db->query("select * from data where time < 1163968390 and time > 1163968360");
    if($#result == -1) {
      print "Error executing query statement\n";
    }   
    else { 
      for(my $a = 0; $a <= $#{$result}; $a++) {
        for(my $b = 0; $b <= $#{$result->[$a]}; $b++) {
          print "-->" , $result->[$a][$b] , "\n";
        }
        print "\n";
      }
    }

    my $delete = "delete from data where id = '192.168.1.4-snmp.1.3.6.1.2.1.2.2.1.16-5'";
    $delete = $delete . " and time = '1163968370'";
    my $status = $db->remove($delete);
    if($status == -1) {
      print "Error executing remove statement\n";
    }

    my %dbSchemaValues = (
      id => "192.168.1.4-snmp.1.3.6.1.2.1.2.2.1.16-5", 
      time => 1163968370, 
      value => 9724592, 
      eventtype => "ifOutOctets",  
      misc => ""
    );	
    $status = $db->insert("data", \%dbSchemaValues);
    if($status == -1) {
      print "Error executing insert statement\n";
    }

    if ($db->closeDB == -1) {
      print "Error closing database\n";
    }
       

=head1 DETAILS

The DBI module itself offers a lot of choices, we have constructed this module to simplify the
amount of setup and handling that must be done when interacting with an SQL based database. 
The module is to be treated as an object, where each instance of the object represents a 
direct connection to an SQL database.  Each method may then be invoked on the object for the 
specific database.   

=head1 API

The API of perfSONAR_PS::DB::SQL is rather simple, and attempts to mirror the API of the other 
perfSONAR_PS::DB::* modules.  

=head2 new($package, $name, $user, $pass, $schema)

The first argument is the 'name' of the database (written as a DBI connection string), and 
the second and third arguments are the username and password (if any) used to connect to 
the database.  The final argument is the table 'schema' for the database.  At current 
time only a single table is supported.  The '$name' must be of the DBI connection 
format which specifies a 'type' of database (MySQL, SQLite, etc) as well as a path or 
other connection method.  It is important that you have the proper DBI modules installed 
for the specific database you will be attempting to access. 

=head2 setName($self, $name)

Sets the name of the database (write as a DBI connection string).  

=head2 setUser($self, $user)

Sets the user of the database.

=head2 setPass($self, $pass)

Sets the password for the database.

=head2 setSchema($self, $schema)

Sets the schema of the database (as a table).  

=head2 openDB($self)

Opens the dabatase.

=head2 closeDB($self)

Closes the database.

=head2 query($self, $query)

Queries the database.

=head2 count($self, $query)

Counts the number of results of a query in the database.

=head2 insert($self, $table, $argvalues)

Inserts items in the database.

=head2 remove($self, $delete)

Removes items from the database.

=head1 SEE ALSO

L<DBI>, L<perfSONAR_PS::Common>, L<Log::Log4perl>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 VERSION

$Id: SNMP.pm 227 2007-06-13 12:25:52Z zurawski $

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework along 
with this software.  If not, see <http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2004-2007, Internet2 and the University of Delaware

All rights reserved.

=cut
