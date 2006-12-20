#!/usr/bin/perl

package Netradar::DB::SQL;
use Carp;
use DBI;
@ISA = ('Exporter');
@EXPORT = ('new', 'setName', 'setUser', 'setPass', 'openDB', 
           'closeDB', 'query', 'count', 'insert', 'remove');
	   
our $VERSION = '0.02';

sub new {
  my ($package, $name, $user, $pass) = @_;   
  my %hash = ();
  $hash{"FILENAME"} = "Netradar::DB::SQL";
  $hash{"FUNCTION"} = "\"new\"";
  if(defined $name) {
    $hash{"NAME"} = $name;
  }  
  if(defined $user) {
    $hash{"USER"} = $user;
  }  
  if(defined $pass) {
    $hash{"PASS"} = $pass;
  }      
  bless \%hash => $package;
}


sub setName {
  my ($self, $name) = @_;  
  $self->{FUNCTION} = "\"setName\"";  
  if(defined $name) {
    $self->{NAME} = $name;
  }
  else {
    croak($self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION});
  }
  return;
}


sub setUser {
  my ($self, $user) = @_;  
  $self->{FUNCTION} = "\"setUser\"";  
  if(defined $user) {
    $self->{USER} = $user;
  }
  else {
    croak($self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION});
  }
  return;
}


sub setPass {
  my ($self, $pass) = @_;  
  $self->{FUNCTION} = "\"setPass\"";  
  if(defined $pass) {
    $self->{PASS} = $pass;
  }
  else {
    croak($self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION});
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
      $self->{PASSWORD}, 
      \%attr
    ) || croak($self->{FILENAME}.":\t Database ".$self->{NAME}." unavailable with user ".
               $self->{NAME}." and password ".$self->{PASSWORD}." in function ".
	       $self->{FUNCTION});
  };
  if($@) {
    croak($self->{FILENAME}.":\tError in ".$self->{FUNCTION}." function: \"".$@."\"");
    exit(-1);
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
    croak($self->{FILENAME}.":\tError in ".$self->{FUNCTION}." function: \"".$@."\"");
    exit(-1);
  }   
  return;
}


sub query {
  my ($self, $query) = @_;
  $self->{FUNCTION} = "\"query\"";  
  my $results = (); 
  if(defined $query) {  
    eval {
      my $sth = $self->{HANDLE}->prepare($query);
      $sth->execute() || 
        croak($self->{FILENAME}.":\t query error in function ".$self->{FUNCTION}.
	      ": ".$sth->errstr."\n");
      $results  = $sth->fetchall_arrayref;
    };
    if($@) {
      croak($self->{FILENAME}.":\tError in ".$self->{FUNCTION}." function: \"".$@."\"");
      exit(-1);
    } 
  }
  else {
    croak($self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION});
  } 
  return $results;
}


sub count {
  my ($self, $query) = @_;
  $self->{FUNCTION} = "\"count\"";  
  my $results = -2; 
  if(defined $query) {    
    eval {
      my $sth = $self->{HANDLE}->prepare($query);
      $sth->execute() || 
        croak($self->{FILENAME}.":\t query error in function ".$self->{FUNCTION}.
	      ": ".$sth->errstr."\n");   
      $results  = $sth->fetchall_arrayref;  
    };      
    if($@) {
      croak($self->{FILENAME}.":\tError in ".$self->{FUNCTION}." function: \"".$@."\"");
      exit(-1);
    } 
  } 
  else { 
    croak($self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION});
  } 
  return $#{$results}+1;
}


sub insert {
  my ($self, $table, $arglist, $argvalues) = @_;
  $self->{FUNCTION} = "\"insert\"";   
  if(defined $table && defined $arglist && defined $argvalues) {
    my @list = @{$arglist};
    my %values = %{$argvalues};

    my $insert = "insert into " . $table . " (";
    for(my $x = 0; $x <= $#list; $x++) {
      if($x == 0) {
        $insert = $insert.$list[$x];
      }
      else {
        $insert = $insert.", ".$list[$x];
      }
    }
    $insert = $insert.") values (";
    for(my $x = 0; $x <= $#list; $x++) {
      if($x == 0) {
        $insert = $insert."?";
      }
      else {
        $insert = $insert.", ?";
      }
    }  
    $insert = $insert.")";

    eval {
      my $sth = $self->{HANDLE}->prepare($insert);
      for(my $x = 0; $x <= $#list; $x++) {
        $sth->bind_param($x+1, $values{$list[$x]});
      }
      $sth->execute() || 
        croak($self->{FILENAME}.":\t insert error in function ".$self->{FUNCTION}.
	      ": ".$sth->errstr."\n"); 
    };
    if($@) {
      croak($self->{FILENAME}.":\tError in ".$self->{FUNCTION}." function: \"".$@."\"");
      exit(-1);
    }     
  }
  else {
    croak($self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION});
  } 
  return;  
}


sub remove {
  my ($self, $delete) = @_;
  $self->{FUNCTION} = "\"remove\"";
  if(defined $delete) {
    eval {     
      my $sth = $self->{HANDLE}->prepare($delete);
      $sth->execute() || 
        croak($self->{FILENAME}.":\t delete error in function ".$self->{FUNCTION}.
	      ": ".$sth->errstr."\n"); 
    };
    if($@) {
      croak($self->{FILENAME}.":\tError in ".$self->{FUNCTION}." function: \"".$@."\"");
      exit(-1);
    }     
  }
  else {
    croak($self->{FILENAME}.":\tMissing argument to ".$self->{FUNCTION});
  }    
  return;
}


1;

__END__
=head1 NAME

Netradar::DB::SQL - A module that provides methods for dealing with common SQL databases.

=head1 DESCRIPTION

This module creates common use cases with the helpf of the DBI module.  The module is to 
be treated as an object, where each instance of the object represents a direct connection 
to a single database and collection.  Each method may then be invoked on the object for 
the specific database.  

=head1 SYNOPSIS

    use Netradar::DB::SQL;

    my $db = new Netradar::DB::SQL(
      "DBI:SQLite:dbname=/home/jason/Netradar/MP/SNMP/netradar.db", 
      "",
      ""
    );

    # or also:
    # 
    # my $db = new Netradar::DB::SQL;
    # $db->setName("DBI:SQLite:dbname=/home/jason/netradar/MP/SNMP/netradar.db");
    # $db->setUser("");
    # $db->setPass("");    

    my @dbSchema = ("id", "time", "value", "eventtype", "misc");

    $db->openDB;

    print "There are " , $db->count("select * from data") , " rows in the database.\n";

    my $result = $db->query("select * from data where time < 1163968390 and time > 1163968360");
    for(my $a = 0; $a <= $#{$result}; $a++) {
      for(my $b = 0; $b <= $#{$result->[$a]}; $b++) {
        print "-->" , $result->[$a][$b] , "\n";
      }
      print "\n";
    }

    my $delete = "delete from data where id = '192.168.1.4-snmp.1.3.6.1.2.1.2.2.1.16-5'";
    $delete = $delete . " and time = '1163968370'";
    $db->remove($delete);

    my %dbSchemaValues = (
      id => "192.168.1.4-snmp.1.3.6.1.2.1.2.2.1.16-5", 
      time => 1163968370, 
      value => 9724592, 
      eventtype => "ifOutOctets",  
      misc => ""
    );	
    $db->insert("data", \@dbSchema, \%dbSchemaValues);

    $db->closeDB;
       

=head1 DETAILS

The DBI module itself offers a lot of choices, we have constructed this module to simplify the
amount of setup and handling that must be done when interacting with an SQL based database. 
The module is to be treated as an object, where each instance of the object represents a 
direct connection to an SQL database.  Each method may then be invoked on the object for the 
specific database.   

=head1 API

The API of Netradar::DB::SQL is rather simple, and attempts to mirror the API of the other 
Netradar::DB::* modules.  

=head2 new($name, $user, $pass)

The constructor requires 3 arguments, the first being the 'name' of the database (written as
an DBI connection string), and the username and password (if any) used to connect to the 
database.  The '$name' must be of the DBI connection format which specifies a 'type' of 
database (MySQL, SQLite, etc) as well as a path or other connection method.  It is important
that you have the proper DBI modules installed for the specific database you will be 
attempting to access. 

=head2 setName($name)

(Re-)Sets the 'name' of the database (written as an DBI connection string).  The name must 
be of the DBI connection format which specifies a 'type' of database (MySQL, SQLite, etc) as 
well as a path or other connection method.  It is important that you have the proper DBI 
modules installed for the specific database you will be attempting to access. 

=head2 setUser($user)

(Re-)Sets the username and password (if any) used to connect to the database.

=head2 setPass($pass)

(Re-)Sets the password (if any) used to connect to the database.

=head2 openDB

Prepares a handle to the database.

=head2 closeDB

Closes the handle to the database.

=head2 query($query)

The '$query' string is an SQL statement to be sent to the database.  The statement must
of course use the proper database schema elements and be properly formed.  

The results of this command are an array of database 'rows'.  

=head2 count($query)

The '$query' string is an SQL statement to be sent to the database.  The statement must
of course use the proper database schema elements and be properly formed.  

The results of this command are the number of result rows that WOULD be returned. 

=head2 insert($table, $arglist, $argvalues)

The first argument is the specific table to operate on within the database, the second and
third arguments deal with the column names, and the values to be inserted.  

=head2 remove($delete)

The '$delete' string is an SQL statement to be sent to the database.  The statement 
must of course use the proper database schema elements and be properly formed.  

=head1 SEE ALSO

L<Netradar::Common>, L<Netradar::DB::XMLDB>, L<Netradar::DB::RRD>, L<Netradar::DB::File>

To join the 'netradar' mailing list, please visit:

  http://moonshine.pc.cis.udel.edu/mailman/listinfo/netradar

The netradar subversion repository is located at:

  https://damsl.cis.udel.edu/svn/netradar/
  
Questions and comments can be directed to the author, or the mailing list. 

=head1 AUTHOR

Jason Zurawski, E<lt>zurawski@eecis.udel.eduE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2006 by Jason Zurawski

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.
