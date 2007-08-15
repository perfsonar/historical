#!/usr/bin/perl -w -I ../../lib

#################
# changeID.pl
#     This script allows you to change the link_id on a Link Status MA
#     database. If multiple new ids are specified, each datum in the set is
#     replaced with a new datum for each new id.
#################

use strict;
use Log::Log4perl qw(get_logger :levels);

use perfSONAR_PS::DB::SQL;
use Getopt::Long;

Log::Log4perl->init("logger.conf");
my $logger = get_logger("perfSONAR_PS");

my $DEBUGFLAG = '';
my $HELP = '';

my $DB_USER = '';
my $DB_PASS = '';
my $DB_HOST = '';
my $DB_TYPE = 'SQLite';
my $DB_NAME = 'status.db';
my $DB_TABLE = 'link_status';

my $status = GetOptions (
		'db_user=s' => \$DB_USER,
		'db_pass=s' => \$DB_PASS,
		'db_type=s' => \$DB_TYPE,
		'db_name=s' => \$DB_NAME,
		'db_host=s' => \$DB_HOST,
		'db_table=s' => \$DB_TABLE,
		'verbose' => \$DEBUGFLAG,
		'help' => \$HELP);

if(!$status or $HELP) {
	print "$0: renames one link in the status db to one or more other ids\n";
	print "\t$0 [--db_user=username] [--db_pass=password] [--db_type=type] [--db_name=name] [--db_host=host] [--db_table=table] [--verbose] [--help] old_id new_id [new_id ... ]\n";
	exit(1);
}


my $old_id = shift;
if (!defined $old_id or $old_id eq "") {
	print "Error: must specify an old id\n";
	exit(-1);
}

my @new_ids = ();
foreach my $id (@ARGV) {
	push @new_ids, $id;
}

if ($#new_ids == -1) {
	print "Error: must specify a new id\n";
	exit(-1);
}

my $dbi_string = "dbi:$DB_TYPE:dbname=$DB_NAME";
if (defined $DB_HOST and $DB_HOST ne "") {
	$dbi_string .= ":dbhost=$DB_HOST";
}

my @dbSchema = ("link_id", "link_knowledge", "start_time", "end_time", "oper_status", "admin_status"); 

my $db = new perfSONAR_PS::DB::SQL($dbi_string, $DB_USER, $DB_PASS, \@dbSchema);
if (!defined $db) {
	print "Error: couldn't create structure for specified database\n";
	exit(-1);
}

if ($db->openDB == -1) {
	print "Error: couldn't open specified database\n";
	exit(-1);
}

my $links = $db->query("select link_knowledge, start_time, end_time, oper_status, admin_status from $DB_TABLE where link_id='$old_id'");
if ($links == -1) {
	print "Error: couldn't get information on link: $old_id\n";
	exit(-1);
}

foreach my $link_ref (@{ $links }) {
	my @link = @{ $link_ref };

	my $do_replace = 1;
	my $i = 0;
	foreach my $new_id (@new_ids) {
		if ($i == $#new_ids and $do_replace != 0) {
			my %updateValues = (
						link_id => "'$new_id'",
					);
			my %where = (
					link_id => "'$old_id'",
					start_time => $link[1],
					end_time => $link[2],
				);

			if ($db->update($DB_TABLE, \%where, \%updateValues) == -1) {
				print "Couldn't insert link status for link $new_id\n";
				$do_replace = 0;
			}
		} else {
			my %insertValues = (
				link_id => $new_id,
				link_knowledge => $link[0],
				start_time => $link[1],
				end_time => $link[2],
				oper_status => $link[3],
				admin_status => $link[4],
			);

			if ($db->insert($DB_TABLE, \%insertValues) == -1) {
				print "Couldn't insert link status for link $new_id\n";
				$do_replace = 0;
			}
		}

		$i++;
	}
}
