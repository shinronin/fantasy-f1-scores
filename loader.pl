#!/usr/local/bin/perl -w
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
my $debug = 0;

# AUS, MYS, CHN, TUR
foreach my $rd ( 1 .. 1 ) {
    print "[main] loading...\n";
    print "[main] rd: $rd\n" if $debug;
    foreach my $pos ( qw/pitcrew chassis engine driver/ ) {
    # foreach my $pos ( qw/engine/ ) {
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
                keep_html => $pos eq 'engine' ? 1 : 0,
                depth => 0, count => 1,
            }, {
                rd => $rd, pos => $pos, html => $html
            } );

            push @$recs, parse_rows( $rd, $pos, $rows );

            insert_data( $recs );
        }
    }

    print "[main] finished.\n";
}

sub parse_rows {
    my( $rd, $pos, $rows ) = @_;

    my @flds = qw/round name team position value growth total_growth points
    victories podiums poles laps_completed laps_attempted overtakes popularity
    trend value_idx name_short name_abbr/;
    my @recs = ();

    foreach my $row ( @$rows ) {
        my %rec = ();
        # scoped here to ensure size of %rec identical for all $pos
        my( $laps_c, $laps_a, $ot ) = ( '' ) x 3;

        if ( $pos eq 'driver' ) {
            # TODO get laps_a per race instead of sum
            ( $laps_c, $laps_a ) = split /\//, $row->[11];
        }
        elsif ( $pos eq 'engine' ) {
            my $name = $1 if $row->[1] =~ />\b(.*)\b</;
            # print "[parse_rows] name: '$1'\n" if $debug;

            my $uri = $1 if $row->[1] =~ /href="(.*)"/;
            # print "[parse_rows] uri: '$1'\n" if $debug;

            # assign name to replace uri string
            $row->[1] = $name;
            print "[parse_rows] engine name: $row->[1]\n" if $debug;

            ( $laps_c, $laps_a, $ot ) = get_engine_data( $rd, $uri );
            if ( $debug ) {
                print "[parse_rows] laps_c: $laps_c\n";
                print "[parse_rows] laps_a: $laps_c\n";
                print "[parse_rows] ot    : $ot\n";
            }

            $row->[12] = $ot;
        }

        # replace laps with laps completed & laps attempted
        splice @$row, 11, 1, $laps_c, $laps_a;

        push @$row, get_name_data( $pos, $row->[1] );

        # print '[parse_rows] row: ', join( ', ', @$row ), "\n"
            # if $debug;

        @rec{@flds} = @$row;
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

    # foreach my $t ( $te->tables ) {
        # print '[get_table_rows] table found: ', join( ', ', $t->coords ), # "\n";
    # }

    my $table = $te->table( @$te_args{qw/depth count/} );
    my @rows = $table->rows;

    # kill headers
    shift @rows;

    foreach my $row ( @rows ) {
        $row = trim( $row );
        # print '[get_table_rows] trim:  ', join( ', ', @$row ), "\n" if $debug;

        $row = $args->{pos} eq 'subreq' ? $row : clean_row( $row );
        # overwrite row # col with round for all but subreq
        $row->[0] = $args->{rd} unless $args->{pos} eq 'subreq';
        # print '[get_table_rows] clean: ', join( ', ', @$row ), "\n" if $debug;
        # print 'row: ', Dumper( $row ), "\n";
    }

    return \@rows;
}

sub get_engine_data {
    my( $rd, $uri ) = @_;

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
        # print '[get_engine_data] rows: ', Dumper( $rows ), "\n";
        my( $laps_c, $laps_a, $ot ) = ( 0 ) x 3;
        my $e_laps_a = 0;
	
	    RD: for ( my $i = 0; $i < @$rows; $i++ ) {
	    # for ( my $i = 0; $i < @$rows; $i++ ) {
            print "[get_engine_data] i: $i\n" if $debug;
	        my $row = $rows->[$i];

            next unless $row->[0];
            next unless $row->[0] == $rd;

            print "[get_engine_data] rd: $row->[0]\n" if $debug;

            # get round #
	        # if ( $row->[0] =~ /^(\d)$/ && $row->[0] == $rd ) {
                # my $curr_rd = $1;
                # print "[get_engine_data] curr_rd: '$curr_rd'\n" if $debug;

                # get race laps
                $laps_a = ( split /\//, trim( $row->[4] ) )[1];
                print "[get_engine_data] laps_a: $laps_a\n" if $debug;

                # double for 2 drivers
                $e_laps_a = $laps_a * 2;
                print "[get_engine_data] e_laps_a: $e_laps_a\n" if $debug;

                for my $idx ( 1 .. 4 ) {
                    my $next_row = $rows->[$i + $idx];
                    my( $next_rd, $next_data ) = @$next_row[0, 1];
                    next RD if $next_rd && $next_rd == $rd + 1;
                    # if ( $next_rd && $next_rd == $rd + 1 ) {
	                    # return ( $laps_c, $e_laps_a, $ot ); # }

                    if ( lc $next_data =~ /(lap|overtake)s/i) {
                        my $type = $1;
                        print "[get_engine_data] type: '", lc $type, "'\n" if $debug;

                        if ( $next_data =~ /(\d+)/ ) {
                            my $val = $1;
                            print "[get_engine_data] val: $val\n" if $debug;

                            $laps_c += $val if lc $type eq 'lap';
                            print "[get_engine_data] laps_c: $laps_c\n"
                                if $laps_c && $debug;

                            $ot     += $val if lc $type eq 'overtake';
                            print "[get_engine_data] ot: $ot\n"
                                if $ot && $debug;
                        }
                    }
                }
            # }
	    }
	
	    return ( $laps_c, $e_laps_a, $ot );
    }
}

sub get_name_data {
    my( $pos, $name ) = @_;

    my( $name_short, $name_abbr ) = ( '' ) x 2;
    my @n = split( /\s/, $name );

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

