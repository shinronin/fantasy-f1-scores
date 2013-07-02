package SportsBox;
use strict;
use warnings;

use Data::Dumper;
$Data::Dumper::Useqq = 1;
use DBI;
use Encode;
use HTML::TableExtract;
use HTTP::Request::Common;
use LWP::UserAgent;

my $host = 'http://espn.sportsbox.com';
my $uri = '/en/formula1-fantasy/statistics/';
my $sort = 'value';
my $debug = 1;
# TODO implement update
my( $rd_start, $rd_end ) = @ARGV[0, 1];
die "$0 <start rd> <end rd>" unless $rd_start;
die "$0 <start rd> <end rd>" unless $rd_end;

# AUS, MYS, CHN, TUR
foreach my $rd ( $rd_start .. $rd_end ) {
	print "[main] loading...\n";
	print "[main] rd: $rd\n" if $debug;
	foreach my $pos ( qw/pitcrew chassis engine driver/ ) {
		print "[main] pos: $pos\n";
		my $url = join '',
			$host, $uri, $rd, '?',
			"sort=$sort&direction=descending&team=&position=$pos&page=0";

		my $html = get_html( $url );
		die "couldn't get html from $url" unless $html;
		my $recs = [];
		my $rows = get_table_rows( {
			keep_html => $pos eq 'engine' || $pos eq 'driver' ? 1 : 0,
			depth => 0, count => 1,
		}, {
			rd => $rd, pos => $pos, html => $html
		} );

		push @$recs, parse_rows( $rd, $pos, $rows );
		# print '[main] recs: ', Dumper( $recs ),"\n" if $debug;

		insert_data( $recs );
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
        @rec{@opts} = ( '' ) x @opts;

		if ( $pos eq 'engine' || $pos eq 'driver' ) {
			# \s* for LIU driver record 'Liuzzi </a>'
			$rec{name} =~ />\b(.*)\b\s*</;
			my $name = $1;

			$rec{name} =~ /href="(.*)"/;
            my $uri = $1;

			# replace html string
			$rec{name} = $name;
            print "$f name: $name\n" if $debug;

			if ( $pos eq 'engine' ) {
				my @flds = qw/laps_completed laps_attempted overtakes/;
				@rec{@flds} = get_pos_data( $rd, $pos, $uri );
			}

			if ( $pos eq 'driver' ) {
				@rec{qw/laps_completed laps_attempted/} = get_pos_data( $rd, $pos, $uri );
			}
		}

		$rec{curr_value} = $rec{value};
        # print "$f curr_value: $rec{curr_value}\n" if $debug;

		$rec{prev_value} = $rec{curr_value} - $rec{growth};
        # print "$f prev_value: $rec{prev_value}\n" if $debug;

        my @del = delete @rec{qw/value laps/};
        die "value and laps fields not deleted" unless @del == 2;

		@rec{qw/name_short name_abbr/} = get_name_data( $pos, $rec{name} );
		# print "$f finished rec:\n", Dumper( %rec ), "\n" if $debug;

		push @recs, \%rec;
	}

	return @recs;
}

# -- required
# id INTEGER PRIMARY KEY AUTOINCREMENT,
# round INTEGER NOT NULL,
# name TEXT NOT NULL,
# team TEXT NOT NULL,
# position TEXT NOT NULL,
# -- deleted during parsing, replaced with curr_value, prev_value
# -- value INTEGER NOT NULL,
# growth INTEGER NOT NULL,
# total_growth INTEGER NOT NULL,
# points INTEGER,
# victories INTEGER,
# podiums INTEGER,
# poles INTEGER,
# -- deleted during parsing, replaced with laps_completed, laps_attempted
# -- laps TEXT NOT NULL,
# overtakes INTEGER,
# popularity INTEGER NOT NULL,
# trend INTEGER NOT NULL,
# value_idx INTEGER NOT NULL,
# -- optional
# laps_completed INTEGER,
# laps_attempted INTEGER,
# name_short TEXT,
# name_abbr TEXT,
# curr_value INTEGER NOT NULL,
# prev_value INTEGER NOT NULL
sub insert_data {
	my( $recs ) = @_;

    my $f = '[insert_data]';
	my $dbh = DBI->connect(
		'dbi:SQLite:dbname=fantasy_f1.db',
		'', '',
		{ AutoCommit => 0, RaiseError => 1 },
	);
	die "couldn't connect to db" unless $dbh;

	foreach my $rec ( @$recs ) {
		# $rec->{id} = '';

		my @flds = sort keys %$rec;
		# print '[insert_data] # flds: ', scalar @flds, "\n" if $debug;
        # print "$f flds: ", join( ', ', @flds ), "\n" if $debug;

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
    # set timeout to 60 secs. instead of 180
    $ua->timeout(60);
	my $res = undef;
	my $fetched = 0;

	until ( $fetched ) {
		$res = $ua->request( GET $url );
		$fetched = 1 if $res->is_success;
	}

	return decode_utf8( $res->content );
}

sub get_table_rows {
	my( $te_args, $args ) = @_;

    my $f = '[get_table_rows]';
	my $te = HTML::TableExtract->new( %$te_args );
	$te->parse( $args->{html} );

	my $table = $te->table( @$te_args{qw/depth count/} );
	my @rows = $table->rows;

	# kill headers
	shift @rows;

	foreach my $row ( @rows ) {
        # print "$f row: ", Dumper( $row ), "\n" if $debug;

		# overwrite row # col with round for all but subreq
		$row->[0] = $args->{rd} unless $args->{pos} eq 'subreq';

		$row = trim( $row );
        # print "$f trim row: ", Dumper( $row ), "\n" if $debug;

		$row = $args->{pos} eq 'subreq' ? $row : clean_row( $row );
        # print "$f clean row: ", Dumper( $row ), "\n" if $debug;
	}

	return \@rows;
}

sub get_pos_data {
	my( $rd, $pos, $uri ) = @_;

	my $f = '[get_pos_data]';
	my $url = $host . $uri;

	my $html = get_html( $url );
	die "couldn't get html from $url" unless $html;
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
		# print "$f rd: $row->[0]\n" if $debug;

		# engine & driver
		# laps_completed parsed differently for engine & driver
		$laps_a = ( split /\//, trim( $row->[4] ) )[1];

		if ( $pos eq 'driver' ) {
			$laps_c = ( split /\//, trim( $row->[4] ) )[0];
			last && return ( $laps_c, $laps_a );
		}

		# double for 2 drivers
		$e_laps_a = $laps_a * 2 if $pos eq 'engine';

		# capture laps x 2 & overtakes x 2
		for my $idx ( 1 .. 4 ) {
			my $next_row = $rows->[$i + $idx];
			my( $next_rd, $next_data ) = @$next_row[0, 1];

			# continue to next rd if lookahead hits it
			next RD if $next_rd && $next_rd == $rd + 1;
			# TODO correct?
            next unless $next_data;

			lc( $next_data ) =~ /(lap|overtake)s/i;
			my $type = $1;
			# print "$f type: '", lc $type, "'\n" if $debug;

            $next_data =~ /(\d+)/;
			my $val = $1;
			# print "$f val: $val\n" if $debug;

			$laps_c += $val if lc $type eq 'lap';
			# print "$f laps_c: $laps_c\n" if $laps_c && $debug;

			$ot += $val if lc $type eq 'overtake';
			# print "$f ot: $ot\n" if $ot && $debug;
		}
	}
	
	if ( $debug ) {
		print "$f engine laps_c: $laps_c\n";
		print "$f engine laps_a: $laps_a\n";
		print "$f engine ot: $ot\n";
	}

	return ( $laps_c, $e_laps_a, $ot );
}

sub get_name_data {
	my( $pos, $name ) = @_;

	my( $name_short, $name_abbr ) = ( '' ) x 2;
	my @n = split /\s/, $name;

	if ( $pos eq 'driver' ) {
		# L. Hamilton
		$name_short = join '',
			substr( $n[0], 0, 1 ),
			". $n[1]",
			( $n[2] ? $n[2] : '' );

		# HAM
		$name_abbr = uc substr $n[1], 0, 3;
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
        # replace commas
        s/,//g;
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

1;

