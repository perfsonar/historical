#!/usr/bin/perl -w

use strict;
use warnings;

=head1 NAME

ipTree.pl - Utility to demonstrate the effectivness of CIDR summarizations of
IP addresses as well as a potential solution to finding dominating values
when used in a Radix Tree (Patricia Trie) data structure.

=head1 DESCRIPTION

The perfSONAR dLS and gLS require a way to summarize large amounts of
topological data (namely IP addresses of type IPv4 and IPv6).  Using the
well known CIDR way of specificying IP address ranges, this simple script aims
to combine the 'dominating' (i.e. greatest available CIDR summaries) for some
set of source IP addresses.

The output is placed into a graphviz dot file for display.

=cut

use Net::CIDR ':all';
use Net::IPTrie;
use Data::Dumper;

# IP Trie Data Structure (similar to Net::Patricia)
my $tr = Net::IPTrie->new( version => 4 );

# I need to be able to do my own manipulations
my %tree = ();

# Ensure that each child only has one parent (IPTrie data structure
# uses a strange internal representation).
my %claim = ();

# starting list of IPs [UDel addresses from all over the domain]

my @map = ("128.175.13.92",
           "128.175.13.74",
           "128.4.40.10",
           "128.4.40.12",
           "128.4.40.17",
           "128.4.131.23",
           "128.4.133.167",
           "128.4.133.163",
           "128.4.133.164");

my $vote = getCDIRSummaries(\@map);
$tr = makePatriciaTrie(\@map, $vote, $tr);
manipulatePatriciaTrie($tr);
genGraph(\%tree);

exit(1);

=head2 getCDIRSummaries($map)

Given a list of IP addresses, gather the CIDR representations then 
group this by a popularity ranking (i.e. if there are 9 hosts, and 9
have a set grouping of CIDR values in common, this is a dominator).

=cut

sub getCDIRSummaries {
  my($map) = @_;
  
  # We can get ALL applicable CIDR summaries for each (in order of least to
  # greatest).  Then vote on what is popular, skip 0.0.0.0/0 though...

  my %vote = ();
  foreach my $host (@{$map}) {
    my @list = Net::CIDR::addr2cidr($host);
    foreach my $range (@list) {
      next if $range eq "0.0.0.0/0"; 
      $vote{$range}++ if defined $vote{$range};
      $vote{$range} = 1 if not defined $vote{$range};
    }
  }

  # organize the votes into popularity groups

  my %tally = ();
  foreach my $range (sort keys %vote) {
    if(defined $tally{$vote{$range}}) {
      push @{$tally{$vote{$range}}}, $range;
    }
    else {
      my @temp = ();
      push @temp, $range;
      $tally{$vote{$range}} = \@temp;
    }  
  }
  return \%tally;
}

=head2 makePatriciaTrie($map, $votes, $tr)

Creates the initial IPTrie structure using the list of 
available hosts (e.g. $map) and the CIDR values for
each (ranked into popularity groups).  The end result is
the IPTrie.

=cut

sub makePatriciaTrie {
  my($map, $votes, $tr) = @_;
  
  # Start to make the IPTrie data structure.  First we add in all
  # of the 'base' addresses

  foreach my $host (@{$map}) {
    $tr->add( address => $host, prefix => "32" );
  }

  # Now we add in the summaries.  We should try to find the 
  # dominators in each 'vote' group first.  This will ensure
  # we are closer to a minimal set

  foreach my $t (keys %{$votes}) {
    my @total = ();
    foreach my $addr (@{$votes->{$t}}) {
      @total = Net::CIDR::cidradd($addr, @total);
    }
    foreach my $t2 (@total) {
      my @parts = split(/\//,$t2);
      $tr->add( address => $parts[0], prefix => $parts[1] );
    }
  } 

  return $tr;
}

=head2 manipulatePatriciaTrie($tr)

Given the IPTrie structure, we need to manually manipulate the nodes into
our own format.

=cut

sub manipulatePatriciaTrie {
  my($tr) = @_;
  
  my $list = ();
  my $code = sub { push @$list, shift @_; };
  my $count = $tr->traverse( code => $code );

  # we need to go backwards when looking at the IPTrie print out, this is 
  # is really to be sure children aren't all claimed by the root (the internal
  # structure is a little strange) so this ensures we hit the root last.
  
  foreach my $node (reverse @{$list}) {
    my $me = "";
    $me = $node->[3]."/".$node->[5] if defined $node->[3] and defined $node->[5];
    next unless $me;

    # each one of our node-keys has some location information
    my @temp = ();
    $tree{$me}{"C"} = \@temp;
    $tree{$me}{"U"} = "";
  
    # recursively search the tree, stop after you find a left and right
    # child though (N.B. this creates problems unfortunately, so we need
    # to manually manipulate...)
    my %status = (
      "L" => 0, 
      "R" => 0
    );
    extract($me, $node, \%status, "");
  }

  # link all the parent information
  foreach my $item (keys %tree) {
    foreach my $c (@{$tree{$item}{"C"}}) {
      $tree{$c}{"U"} = $item if $c and $item;
    }  
  }

  # No we get to do some manual mainpulation of the tree we just created, 
  # there are two cases we should watch out for:
  #
  # 1) Node with only one child, child has children
  # 2) Node with only one child, child is a terminal
  #
  # Based on these two cases we will search the tree searching for 
  # candidates.  When we find one, be sure to move all the 'pointers'
  # around, and mark the node for deletion

  my @delete = ();
  foreach my $item (keys %tree) {
    if($#{$tree{$item}{"C"}} == 0 and $#{$tree{$tree{$item}{"C"}->[0]}{"C"}} >= -1) {
      my @size = ($#{$tree{$item}{"C"}}, $#{$tree{$tree{$item}{"C"}->[0]}{"C"}});

      # we either look at the node and child, or node and parent as the
      # candidates for replacement.
      my @items = ();
      if($size[1] == -1) {
        @items = ($tree{$item}{"U"}, $item);
      }
      else {
        @items = ($item, $tree{$item}{"C"}->[0]); 
      }

      # We are assuming this will give us the most dominant
      # node (and that there will only be one).  
      my @total = ();
      @total = Net::CIDR::cidradd($items[0], @total);
      @total = Net::CIDR::cidradd($items[1], @total);

      # move the children 
      if($size[1] == -1) {
        push @{$tree{$items[0]}{"C"}}, @{$tree{$items[1]}{"C"}};    
        my $counter = 0;
        foreach my $c (@{$tree{$items[0]}{"C"}}) {
          if($c eq $items[1]) {
            splice(@{$tree{$items[0]}{"C"}}, $counter, 1);
            last;
          }
          $counter++;
        }
      }
      else {
        $tree{$items[0]}{"C"} = $tree{$items[1]}{"C"};
      }

      # mark the node for deletion
      push @delete, $items[1];        
 
      # Re-map the children (if any) to the new parent
      foreach my $c (@{$tree{$items[0]}{"C"}}) {
        $tree{$c}{"U"} = $items[0] if $c and $items[0];
      }  
    }
  }

  # Get rid of dead nodes identified above (perl doesn't like you deleting from
  # and 'in use' data structure so deleting needs to be done out of the
  # above loop)
  
  foreach my $d (@delete) {
    delete $tree{$d};
  }

  return;
}

=head2 extract($parent, $node, $status, $side)

This aux function recursively walks the nodes of the IPTrie structure
and creates a more usefriendly tree that we will use for manipulation
and final display.

=cut

sub extract {
  my($parent, $node, $status, $side) = @_;
  my $me = "";
  $me = $node->[3]."/".$node->[5] if defined $node->[3] and defined $node->[5];
  if($me and $side and (not $claim{$me})) {
    push @{$tree{$parent}{"C"}}, $me;
    $claim{$me} = 1;
  }
  $status = extract($parent, $node->[1], $status, "L") if $node->[1] and (not $status->{"L"});
  $status = extract($parent, $node->[2], $status, "R") if $node->[2] and (not $status->{"R"});
  return $status;  
}

=head2 genGraph

Outputs the contents of the tree structure into a "Graphviz" formated
DAG file.  

=cut

sub genGraph {
  print "digraph g {\n";

  foreach my $item (keys %tree) {
    next unless $item;
    my @array = ();
    @array =split(/\//, $item);
    
    # color the terminal elements so we know they are not dominators
    if($array[1] eq "32") {
      print "\t\"" , $item , "\"[ color=crimson, style=filled ];\n";
    }
    else {
      print "\t\"" , $item , "\";\n";
    }
  }

  foreach my $item (keys %tree) {
    next unless $item;
    foreach my $c (@{$tree{$item}{"C"}}) {
      next unless $c;
      print "\t\"" , $item , "\" -> \"" , $c , "\";\n";
    }
  }

  print "}\n";
}

__END__

=head1 SEE ALSO

L<Net::CIDR>, L<Net::IPTrie>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS

Questions and comments can be directed to the author, or the mailing list.
Bugs, feature requests, and improvements can be directed here:

  https://bugs.internet2.edu/jira/browse/PSPS

=head1 VERSION

$Id$

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework
along with this software.  If not, see
<http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2008, Internet2

All rights reserved.

=cut

