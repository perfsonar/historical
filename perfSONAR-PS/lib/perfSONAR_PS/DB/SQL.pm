#!/usr/bin/perl

package perfSONAR_PS::DB::SQL;
use DBI;
use perfSONAR_PS::Common;
@ISA = ('Exporter');
@EXPORT = ();
	   
our $VERSION = '0.03';

sub new {
  my ($package, $log, $name, $user, $pass, $schema, $debug) = @_;   
  my %hash = ();
  $hash{"FILENAME"} = "perfSONAR_PS::DB::SQL";
  $hash{"FUNCTION"} = "\"new\"";
  if(defined $log and $log ne "") {
    $hash{"LOGFILE"} = $log;
  }      
  if(defined $name and $name ne "") {
    $hash{"NAME"} = $name;
  }  
  if(defined $user and $user ne "") {
    $hash{"USER"} = $user;
  }  
  if(defined $pass and $pass ne "") {
    $hash{"PASS"} = $pass;
  }      
  if(defined $schema and $schema ne "") {
    @{$hash{"SCHEMA"}} = @{$schema};
  } 
  if(defined $debug and $debug ne "") {
    $hash{"DEBUG"} = $debug;  
  }   
  bless \%hash => $package;
}


sub setLog {
  my ($self, $log) = @_;  
  $self->{FUNCTION} = "\"setLog\"";  
  if(defined $log and $log ne "") {
    $self->{LOGFILE} = $log;
  }
  else {
    error("Missing argument", __LINE__);    
  }
  return;
}


sub setName {
  my ($self, $name) = @_;  
  $self->{FUNCTION} = "\"setName\"";  
  if(defined $name and $name ne "") {
    $self->{NAME} = $name;
  }
  else {
    error("Missing argument", __LINE__);
  }
  return;
}


sub setUser {
  my ($self, $user) = @_;  
  $self->{FUNCTION} = "\"setUser\"";  
  if(defined $user and $user ne "") {
    $self->{USER} = $user;
  }
  else {
    error("Missing argument", __LINE__);
  }
  return;
}


sub setPass {
  my ($self, $pass) = @_;  
  $self->{FUNCTION} = "\"setPass\"";  
  if(defined $pass and $pass ne "") {
    $self->{PASS} = $pass;
  }
  else {
    error("Missing argument", __LINE__);
  }
  return;
}


sub setSchema {
  my ($self, $schema) = @_;  
  $self->{FUNCTION} = "\"setSchema\"";  
  if(defined $schema and $schema ne "") {
    @{$self->{SCHEMA}} = @{$schema};
  } 
  else {
    error("Missing argument", __LINE__);
  }
  return;
}


sub setDebug {
  my ($self, $debug) = @_;  
  $self->{FUNCTION} = "\"setDebug\"";  
  if(defined $debug and $debug ne "") {
    $self->{DEBUG} = $debug;
  }
  else {
    error("Missing argument", __LINE__);    
  }
  return;
}


sub openDB {
  my ($self) = @_;
  $self->{FUNCTION} = "\"openDB\"";  
  eval {
    my %attr = (
      RaiseError => 1,
    );	   
    $self->{HANDLE} = DBI->connect(
      $self->{NAME},
      $self->{USER},
      $self->{PASS}, 
      \%attr
    ) or 
      error("Database ".$self->{NAME}." unavailable with user ".$self->{NAME}." and password ".$self->{PASS}, __LINE__);               
  };
  if($@) {
    error("Open error \"".$@."\"", __LINE__);
  }   
  return;
}


sub closeDB {
  my ($self) = @_;
  $self->{FUNCTION} = "\"closeDB\"";  
  eval {   
    $self->{HANDLE}->disconnect();
  };
  if($@) {
    error("Close error \"".$@."\"", __LINE__);
  }   
  return;
}


sub query {
  my ($self, $query) = @_;
  $self->{FUNCTION} = "\"query\"";  
  my $results = (); 
  if(defined $query and $query ne "") {  
    print $self->{FILENAME}.":\tquery \".$query.\" received in ".$self->{FUNCTION}."\n" if($self->{DEBUG});
    eval {
      my $sth = $self->{HANDLE}->prepare($query);
      $sth->execute() or 
        error("Query error on statement \"".$query."\"", __LINE__);      	      
      $results  = $sth->fetchall_arrayref;
    };
    if($@) {
      error("Query error \"".$@."\"", __LINE__);
      return -1;
    } 
  }
  else {
    error("Missing argument", __LINE__);
  } 
  return $results;
}


sub count {
  my ($self, $query) = @_;
  $self->{FUNCTION} = "\"count\"";  
  my $results = -2; 
  if(defined $query and $query ne "") { 
    print $self->{FILENAME}.":\tquery \".$query.\" received in ".$self->{FUNCTION}."\n" if($self->{DEBUG});   
    eval {
      my $sth = $self->{HANDLE}->prepare($query);
      $sth->execute() or 
        error("Query error on statement \"".$query."\"", __LINE__);	
      $results  = $sth->fetchall_arrayref;  
    };      
    if($@) {
      error("Query error \"".$@."\" on statement \"".$query."\"", __LINE__);
      return -1;
    } 
  } 
  else { 
    error("Missing argument", __LINE__);
  } 
  return $#{$results}+1;
}


sub insert {
  my ($self, $table, $argvalues) = @_;
  $self->{FUNCTION} = "\"insert\"";   
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
    
    print $self->{FILENAME}.":\tinsert \".$insert.\" prepared in ".$self->{FUNCTION}."\n" if($self->{DEBUG});
    eval {
      my $sth = $self->{HANDLE}->prepare($insert);
      for(my $x = 0; $x <= $#{$self->{SCHEMA}}; $x++) {   
        $sth->bind_param($x+1, $values{$self->{SCHEMA}->[$x]});
      }
      $sth->execute() or 
        error("Insert error on statement \"".$insert."\"", __LINE__);		      
    };
    if($@) {
      error("Insert error \"".$@."\" on statement \"".$insert."\"", __LINE__);
      return -1;
    }     
  }
  else {
    error("Missing argument", __LINE__);
  } 
  return 1;  
}


sub remove {
  my ($self, $delete) = @_;
  $self->{FUNCTION} = "\"remove\"";
  if(defined $delete and $delete ne "") {
    print $self->{FILENAME}.":\tdelete \".$delete.\" received in ".$self->{FUNCTION}."\n" if($self->{DEBUG});
    eval {     
      my $sth = $self->{HANDLE}->prepare($delete);
      $sth->execute() or 
        error("Remove error on statement \"".$delete."\"", __LINE__);		      
    };
    if($@) {	
      error("Remove error \"".$@."\" on statement \"".$delete."\"", __LINE__);
      return -1;
    }     
  }
  else {
    error("Missing argument", __LINE__);
  }    
  return 1;
}


sub error {
  my($msg, $line) = @_;  
  $line = "N/A" if(!defined $line or $line eq "");
  print $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}." at line ".$line.".\n" if($self->{"DEBUG"});
  printError($self->{"LOGFILE"}, $self->{FILENAME}.":\t".$msg." in ".$self->{FUNCTION}." at line ".$line.".") 
    if(defined $self->{"LOGFILE"} and $self->{"LOGFILE"} ne "");    
  return;
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
      "./error.log";
      "DBI:SQLite:dbname=/home/jason/Netradar/MP/SNMP/netradar.db", 
      "",
      "",
      \@dbSchema
    );

    # or also:
    # 
    # my $db = new perfSONAR_PS::DB::SQL;
    # $db->setLog("./error.log");
    # $db->setName("DBI:SQLite:dbname=/home/jason/netradar/MP/SNMP/netradar.db");
    # $db->setUser("");
    # $db->setPass("");    
    # $db->setSchema(\@dbSchema);
    # $db->setDebug($debug);     

    $db->openDB;

    my $count = $db->count("select * from data");
    if($count == -1) {
      print "Error executing count statement\n";
    }
    else {
      print "There are " , $db->count("select * from data") , " rows in the database.\n";
    }

    my $result = $db->query("select * from data where time < 1163968390 and time > 1163968360");
    if($result == -1) {
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

    $db->closeDB;
       

=head1 DETAILS

The DBI module itself offers a lot of choices, we have constructed this module to simplify the
amount of setup and handling that must be done when interacting with an SQL based database. 
The module is to be treated as an object, where each instance of the object represents a 
direct connection to an SQL database.  Each method may then be invoked on the object for the 
specific database.   

=head1 API

The API of perfSONAR_PS::DB::SQL is rather simple, and attempts to mirror the API of the other 
perfSONAR_PS::DB::* modules.  

=head2 new($log, $name, $user, $pass, $schema)

The 'log' argument is the name of the log file where error or warning information may be 
recorded.  The second argument is the 'name' of the database (written as a DBI connection 
string), and the forth arguments are the username and password (if any) used to connect to 
the database.  The final argument is the table 'schema' for the database.  At current time 
only a single table is supported.  The '$name' must be of the DBI connection format which 
specifies a 'type' of database (MySQL, SQLite, etc) as well as a path or other connection 
method.  It is important that you have the proper DBI modules installed for the specific 
database you will be attempting to access. 

=head2 setLog($log)

(Re-)Sets the name of the log file to be used.

=head2 setName($name)

(Re-)Sets the 'name' of the database (written as an DBI connection string).  The name must 
be of the DBI connection format which specifies a 'type' of database (MySQL, SQLite, etc) as 
well as a path or other connection method.  It is important that you have the proper DBI 
modules installed for the specific database you will be attempting to access. 

=head2 setUser($user)

(Re-)Sets the username and password (if any) used to connect to the database.

=head2 setPass($pass)

(Re-)Sets the password (if any) used to connect to the database.

=head2 setSchema($schema)

(Re-)Sets the table schema for the database.

=head2 setDebug($debug)

(Re-)Sets the value of the $debug switch.

=head2 openDB

Prepares a handle to the database.

=head2 closeDB

Closes the handle to the database.

=head2 query($query)

The '$query' string is an SQL statement to be sent to the database.  The statement must
of course use the proper database schema elements and be properly formed.  Will return
-1 on error.

The results of this command are an array of database 'rows'.  

=head2 count($query)

The '$query' string is an SQL statement to be sent to the database.  The statement must
of course use the proper database schema elements and be properly formed.  Will return
-1 on error.

The results of this command are the number of result rows that WOULD be returned. 

=head2 insert($table, $argvalues)

The first argument is the specific table to operate on within the database, the second 
argument deals with the column names (related to the schema) and the values to be 
inserted.  Will return 1 on success, -1 on failure.

=head2 remove($delete)

The '$delete' string is an SQL statement to be sent to the database.  The statement 
must of course use the proper database schema elements and be properly formed.  Will 
return 1 on success, -1 on failure.

=head2 error($msg, $line)	

A 'message' argument is used to print error information to the screen and log files 
(if present).  The 'line' argument can be attained through the __LINE__ compiler directive.  
Meant to be used internally.

=head1 SEE ALSO

L<DBI>, L<perfSONAR_PS::Common>, L<perfSONAR_PS::Transport>, L<perfSONAR_PS::DB::XMLDB>, 
L<perfSONAR_PS::DB::RRD>, L<perfSONAR_PS::DB::File>, L<perfSONAR_PS::MP::SNMP>, 
L<perfSONAR_PS::MP::Ping>, L<perfSONAR_PS::MA::General>, L<perfSONAR_PS::MA::SNMP>, 
L<perfSONAR_PS::MA::Ping>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS 
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 VERSION

$Id$

=head1 AUTHOR

Jason Zurawski, E<lt>zurawski@internet2.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Jason Zurawski

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.
