#!/usr/bin/perl -w
use strict;

use Data::Dumper;
$Data::Dumper::Useqq = 1;
use DBI;

my $dbh = DBI->connect(
	'dbi:SQLite:dbname=fantasy_f1.db',
	'', '',
	{ AutoCommit => 0, RaiseError => 1 },
);
die "couldn't connect to db" unless $dbh;

my $rd_sql = 'select max(round) - 1 from f1_2011';
my $rd = $dbh->selectrow_array( $rd_sql );
my %limit = ( P => 1, C => 2, E => 1, D => 4 );

my $sub_sql = 'select sum(prev_value) from f1_2011 where prev_value in ( select prev_value from f1_2011 where round = ? and position = ? order by growth desc limit ? )';
my $sth = $dbh->prepare( $sub_sql );

foreach my $pos ( sort keys %limit ) {
	$sth->execute( $rd, $pos, $limit{$pos} );
	my $sum = $sth->fetchrow_array;
	print "$pos sum: $sum\n";
}

$sth = undef;
$dbh->disconnect;

