#!/usr/bin/perl -w
use strict;

use Data::Dumper;
use DBI;
use Encode;
use HTML::TableExtract;
use HTTP::Request::Common;
use LWP::UserAgent;

my $host = 'http://espn.sportsbox.com';
my $uri = '/en/formula1-fantasy/statistics/';
my $sort = 'value';
my $debug = 1;

# AUS, MYS, CHN, TUR
foreach my $rd ( 1 .. 1 ) {
	print "[main] loading...\n";
	print "[main] rd: $rd\n" if $debug;
	# foreach my $pos ( qw/pitcrew chassis engine driver/ ) {
	foreach my $pos ( qw/driver/ ) {
		print "[main] pos: $pos\n";
		my $url = join '',
			$host, $uri, $rd, '?',
			"sort=$sort&direction=descending&team=&position=$pos&page=0";

		unless ( my $html = get_html( $url ) ) {
			die "couldn't get html from $url";
		}
		else {
			my $recs = [];
			my $rows = get_table_rows( {
				keep_html => $pos eq 'engine' || $pos eq 'driver' ? 1 : 0,
				depth => 0, count => 1,
			}, {
				rd => $rd, pos => $pos, html => $html
			} );

			push @$recs, parse_rows( $rd, $pos, $rows );
			print '[main] recs: ', Dumper( $recs ),"\n" if $debug;

			insert_data( $recs );
		}
	}

	print "[main] finished.\n";
}

sub parse_rows {
	my( $rd, $pos, $rows ) = @_;

	my $f = '[parse_rows]';
	my @recs = ();
	my @flds = qw/round name team position value growth total_growth points
	victories podiums poles laps overtakes popularity trend value_idx
	/;
	my @opts = qw/laps_completed laps_attempted name_short name_abbr curr_value
	prev_value/;

	foreach my $row ( @$rows ) {
		my %rec = ();
		@rec{@flds} = @$row;
		print "$f rec flds from row:\n", Dumper( %rec ), "\n" if $debug;
		@rec{@opts} = ( '' ) x @opts;
		print "$f rec opts:\n", Dumper( %rec ), "\n" if $debug;

		if ( $pos eq 'engine' || $pos eq 'driver' ) {
			# print "$f raw row->[1]: '$row->[1]'\n" if $debug;
			# print "$f raw rec name: '$rec{name}'\n" if $debug;
			my( $name, $uri );

			# \s+ for LIU driver record 'Liuzzi </a>'
			if ( $rec{name} =~ />\b(.*)\b\s+</ ) {
				$name = $1;
				print "$f name: $name\n" if $debug;
			}
			else {
				die "$f couldn't parse name";
			}

			if ( $rec{name} =~ /href="(.*)"/ ) {
				$uri = $1;
				print "$f uri: $uri\n" if $debug;
			}
			else {
				die "$f couldn't parse uri";
			}

			# replace html string
			$rec{name} = $name;

			if ( $pos eq 'engine' ) {
				my @flds = qw/laps_completed laps_attempted overtakes/;
				@rec{@flds} = get_pos_data( $rd, $pos, $uri );
			}

			if ( $pos eq 'driver' ) {
				$rec{laps_completed} = ( split /\//, $rec{laps} )[0];
				$rec{laps_attempted} = get_pos_data( $rd, $pos, $uri );
			}

			$rec{curr_value} = delete $rec{value};
			$rec{prev_value} = $rec{curr_value} - $rec{growth};
			delete $rec{laps};
		}

		@rec{qw/name_short name_abbr/} = get_name_data( $pos, $rec{name} );
		print "$f finished rec:\n", Dumper( %rec ), "\n" if $debug;

		push @recs, \%rec;
	}

	return @recs;
}

# id integer primary key,
# round integer,
# name text,
# name_short text,
# name_abbr text,
# team text,
# position text,
# value integer,
# growth integer,
# total_growth integer,
# points integer,
# victories integer,
# podiums integer,
# poles integer,
# laps_completed integer
# laps_attempted integer,
# overtakes integer,
# popularity integer,
# trend integer,
# value_idx integer

sub insert_data {
	my( $recs ) = @_;

	my $dbh = DBI->connect(
		'dbi:SQLite:dbname=fantasy_f1.db',
		'', '',
		{ AutoCommit => 0, RaiseError => 1 },
	);
	die "couldn't connect to db!" unless $dbh;

	foreach my $rec ( @$recs ) {
		# $rec->{id} = '';

		my @flds = sort keys %$rec;
		# print '[insert_data] # flds: ', scalar @flds, "\n" if $debug;

		# my @binds = map { $_ eq '' ? 'NULL' : "'$_'" } @$rec{@flds};
		my @binds = @$rec{@flds};
		# print '[insert_data] # binds: ', scalar @binds, "\n" if $debug;
		# print '[insert_data] binds: ', join( ', ', @binds ), "\n" if $debug;

		my $sql = 'INSERT INTO f1_2011 (';
		$sql .= join ', ', @flds;
		$sql .=  ') VALUES (';
		$sql .= join ', ', ( '?' ) x @binds;
		$sql .=  ')';
		# print "[insert_data] sql: $sql\n" if $debug;

		eval { $dbh->do( $sql, undef, @binds ); };
		die $dbh->err if $@;
	}

	$dbh->commit;
	$dbh->disconnect;
}

sub get_html {
	my( $url ) = @_;

	my $ua = LWP::UserAgent->new;
	my $res = $ua->request( GET $url );

	return $res->is_success ? decode_utf8( $res->content ) : undef;
}

sub get_table_rows {
	my( $te_args, $args ) = @_;

	my $te = HTML::TableExtract->new( %$te_args );
	$te->parse( $args->{html} );

	my $table = $te->table( @$te_args{qw/depth count/} );
	my @rows = $table->rows;

	# kill headers
	shift @rows;

	foreach my $row ( @rows ) {
		$row = trim( $row );
		$row = $args->{pos} eq 'subreq' ? $row : clean_row( $row );

		# overwrite row # col with round for all but subreq
		$row->[0] = $args->{rd} unless $args->{pos} eq 'subreq';
	}

	return \@rows;
}

sub get_pos_data {
	my( $rd, $pos, $uri ) = @_;

	my $f = '[get_pos_data]';
	my $url = $host . $uri;

	unless ( my $html = get_html( $url ) ) {
		die "couldn't get html from $url";
	}
	else {
		my $rows = get_table_rows( {
			depth => 0, count => 1
		}, {
			rd => $rd, pos => 'subreq', html => $html
		} );
		my( $laps_c, $laps_a, $ot ) = ( 0 ) x 3;
		# laps attempted per engine
		my $e_laps_a = 0;
	
		RD: for ( my $i = 0; $i < @$rows; $i++ ) {
			my $row = $rows->[$i];

			# skip all but rd row
			next unless $row->[0];
			next unless $row->[0] == $rd;
			print "$f rd: $row->[0]\n" if $debug;

			# get race laps attempted
			$laps_a = ( split /\//, trim( $row->[4] ) )[1];
			# job done for driver
			return $laps_a if $pos eq 'driver';

			# double for 2 drivers
			$e_laps_a = $laps_a * 2 if $pos eq 'engine';

			# capture laps x 2 & overtakes x 2
			for my $idx ( 1 .. 4 ) {
				my $next_row = $rows->[$i + $idx];
				my( $next_rd, $next_data ) = @$next_row[0, 1];

				# continue to next rd if lookahead hits it
				next RD if $next_rd && $next_rd == $rd + 1;

				if ( lc $next_data =~ /(lap|overtake)s/i ) {
					my $type = $1;
					# print "$f type: '", lc $type, "'\n" if $debug;

					if ( $next_data =~ /(\d+)/ ) {
						my $val = $1;
						# print "$f val: $val\n" if $debug;

						$laps_c += $val if lc $type eq 'lap';
						print "$f laps_c: $laps_c\n"
							if $laps_c && $debug;

						$ot	 += $val if lc $type eq 'overtake';
						print "$f ot: $ot\n"
							if $ot && $debug;
					}
				}
			}
		}
	
		if ( $debug ) {
			print "$f laps_c: $laps_c\n";
			print "$f laps_a: $laps_a\n";
			print "$f     ot: $ot\n";
		}

		return ( $laps_c, $e_laps_a, $ot );
	}
}

sub get_name_data {
	my( $pos, $name ) = @_;

	my( $name_short, $name_abbr ) = ( '' ) x 2;
	my @n = split /\s/, $name; # TODO wtf?

	if ( $pos eq 'driver' ) {
		# L. Hamilton
		$name_short = join '', # TODO wtf?
			substr( $n[0], 0, 1 ),
			". $n[1]",
			( $n[2] ? $n[2] : '' );

		# HAM
		$name_abbr = uc substr $n[1], 0, 3; # TODO wtf?
		$name_abbr = 'MSC' if lc $n[1] eq 'schumacher';
		$name_abbr = 'DIR' if lc $n[1] eq 'di';
		$name_abbr = 'DAM' if lc $n[1] eq "d'ambrosio";
	}
	elsif ( $pos eq 'chassis' ) {
		# RB7
		$name_short = $n[$#n];
	}

	return ( $name_short, $name_abbr );
}

sub trim {
	my( $arg ) = @_;

	if ( ref $arg eq 'ARRAY' ) {
		my @trim = ();

		foreach my $elem ( @$arg ) {
			$elem = '' unless $elem;
			$elem =~ s/[\r\n]/ /g;
			$elem =~ s/\s{2,}/ /g;
			$elem =~ s/^\s+//g;
			$elem =~ s/\s+$//g;
			push @trim, $elem;
		}

		return \@trim;
	}
	else {
		$arg =~ s/[\r\n]/ /g;
		$arg =~ s/\s{2,}/ /g;
		$arg =~ s/^\s+//g;
		$arg =~ s/\s+$//g;

		return $arg;
	}
}

sub clean_row {
	my( $arg ) = @_;

	return [ map {
		# kill british pound
		s/\xa3//g;
		# kill percent
		s/\s\%//g;
		# kill ' p.' from driver points
		s/\sp.//g;
		# kill space between '/'
		s/\s+\/\s+/\//;
		# make null
		$_ = '' if $_ eq '-';
		$_;
	} @$arg ];
}

