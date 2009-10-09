package RSGet::ListManager;

use strict;
use warnings;
#use diagnostics;
use RSGet::Tools;
use RSGet::FileList;
use RSGet::Dispatch;
use URI::Escape;
use POSIX qw(ceil floor);
set_rev qq$Id$;

# {{{ Comparators

# Compare two ranges in form:
# $r1 = [ $min1, $max1 ]
# Returns 0 if ranges intersect, -1 if first is smaller, 1 if first is larger
sub cmp_range
{
	my ($a, $b) = @_;
	return 0 unless defined $a and defined $b;
	@$a = reverse @$a if $a->[0] > $a->[1];
	@$b = reverse @$b if $b->[0] > $b->[1];
	return -1 if $a->[1] < $b->[0];
	return 1 if $b->[1] < $a->[0];
	return 0;
}

# Express aproximate file size as range of possible file sizes in bytes
# 1 kb = [512, 2048]
# 1.0 kb = [972, 1127]
sub size_to_range
{
	local $_ = lc shift;
	my $kilo = shift || 1024;

	s/\s*b(ytes?)?$//;
	return [+$1, +$1 + 1] if /^\s*(\d+)\s*$/;

	return undef unless /^(\d+)([\.,](\d+))?\s*([kmg])$/;
	my ($int, $frac, $mult) = ($1, $3, $4);
	my $one = 1;
	my $num = + $int;
	if ( defined $frac ) {
		$one = 10 ** (- length $frac);
		$num = + "$int.$frac";
	}
	my $mult_by = 1;
	if ( $mult eq "k" ) {
		$mult_by = $kilo;
	} elsif ( $mult eq "m" ) {
		$mult_by = $kilo * $kilo;
	} elsif ( $mult eq "g" ) {
		$mult_by = $kilo * $kilo * $kilo;
	}

	my $min = floor( ($num - $one / 2) * $mult_by );
	my $max = ceil( ($num + $one) * $mult_by );
	
	return [$min, $max];
}


# compare two strings where both may contain wildcards
my $wildcard = ord "\0";
sub eq_name
{
	my $a_string = shift;
	my $b_string = shift;

	my @a = map ord, split //, $a_string;
	my @b = map ord, split //, $b_string;

	my $shorter = scalar @a;
	$shorter = scalar @b if $shorter > scalar @b;

	my $found = 0;
	for ( my $i = 0; $i < $shorter; $i++ ) {
		my ( $a, $b ) = ( $a[ $i ], $b[ $i ] );
		if ( $a == $wildcard or $b == $wildcard ) {
			$found = 1;
			last;
		}
		return 0 unless $a == $b;
	}

	@a = reverse @a;
	@b = reverse @b;

	for ( my $i = 0; $i < $shorter; $i++ ) {
		my ( $a, $b ) = ( $a[ $i ], $b[ $i ] );
		if ( $a == $wildcard or $b == $wildcard ) {
			$found = 1;
			last;
		}
		return 0 unless $a == $b;
	}

	return 0 if not $found and scalar @a != scalar @b;
	return 1;
}

sub simplify_name
{
	local $_ = lc shift;
	s/(&[a-z0-9]*;|[^a-z0-9\0])//g;
	return $_;
}

# }}}

sub clone_data
{
	my $o = shift;

	my $n = $o->{fname} || $o->{name} || $o->{aname} || $o->{iname} || $o->{ainame};
	return () unless $n;
	my $sn = simplify_name( $n );

	my $s = $o->{fsize} || $o->{size} || $o->{asize};
	$s ||= -1 if $o->{quality};
	return () unless $s;
	my $sr = size_to_range( $s, $o->{kilo} );

	return ( $n, $sn, $s, $sr );
}

sub add_clone_info
{
	my $clist = shift;
	my $uris = shift;
	my $globals = shift;

	my @mcd;
	foreach my $uri ( keys %$uris ) {
		my ( $getter, $options ) = @{ $uris->{ $uri } };
		my $o = { %$options, %$globals };

		my @cd = clone_data( $o );
		next unless @cd;
		push @mcd, [ $uri, @cd ];
	}

	push @$clist, \@mcd if @mcd;
}

sub find_clones
{
	my $clist = shift;
	my $cd = shift;

	my $sn = $cd->[1];
	my $sr = $cd->[3];

	my @cl_all;
	my @cl_part;
	foreach my $mcd ( @$clist ) {
		my $clones = 0;
		foreach my $ucd ( @$mcd ) {
			my $cmp = cmp_range( $sr, $ucd->[4] );
			next if not defined $cmp or $cmp != 0;

			my $eq_name = eq_name( $sn, $ucd->[2] );
			next unless $eq_name;

			$clones++;
		}
		if ( $clones == @$mcd ) {
			push @cl_all, $mcd;
		} elsif ( $clones ) {
			warn "Partial clone for $cd->[0]\n";
			push @cl_part, $mcd;
		}
	}

	return @cl_all, @cl_part;
}

sub check_bad_clones
{
	my $globals = shift;
	my $uris = shift;

	return 0 unless scalar keys %$uris > 1;
	return 0 unless $globals->{fname};
	my $sname = simplify_name( $globals->{fname} );
	my $sizer = undef;
	$sizer = size_to_range( $globals->{fsize} ) if $globals->{fsize} > 0;

	my $got_bad = 0;
	foreach my $uri ( keys %$uris ) {
		my ( $getter, $o ) = @{ $uris->{ $uri } };

		my @cd = clone_data( $o );
		next unless @cd;

		my $eq_name = eq_name( $sname, $cd[1] );
		my $cmp = cmp_range( $sizer, $cd[3] );
		if ( not $eq_name or $cmp != 0 ) {
			warn "$uri is not a clone of $globals->{fname}\n";
			my $u = join " ", $uri, RSGet::FileList::h2a( $o );
			RSGet::FileList::save( $uri,
				delete => 1, links => [ $uri ] );
			RSGet::FileList::update();
			$got_bad = 1;
		}
	}
	return $got_bad;
}

my $act_clist;
sub autoadd
{
	my $getlist = shift;
	$act_clist = [];

	my $changed = 0;
	my @adds;

	foreach my $line ( @$getlist ) {
		next unless ref $line;

		my ( $cmd, $globals, $uris ) = @$line{ qw(cmd globals uris) };
		if ( $cmd eq "GET" ) {
			last if check_bad_clones( $globals, $uris );
		}

		if ( $cmd eq "ADD" ) {
			push @adds, $line;
			next;
		}

		add_clone_info( $act_clist, $uris, $globals );
	}

	foreach my $line ( @adds ) {
		my ( $cmd, $globals, $uris ) = @$line{ qw(cmd globals uris) };
		my $last = 0;
		foreach my $uri ( keys %$uris ) {
			my ( $getter, $options ) = @{ $uris->{ $uri } };
			my @cd = clone_data( { %$options, %$globals } );
			next unless @cd;
			$last = 1;
			my @clones = find_clones( $act_clist, \@cd );
			if ( @clones ) {
				my $curi = $clones[0]->[0]->[0];
				p "$uri is a clone of $curi";
				RSGet::FileList::save( $curi, clones => { $uri => [ $getter, $options ] } );
				RSGet::FileList::save( $uri, delete => 1 );
			} else {
				#p "Clone for $uri not found";
				RSGet::FileList::save( $uri, cmd => "GET" );
			}
			RSGet::FileList::update();
		}
		last if $last;
	}
}

1;

# vim: ts=4:sw=4:fdm=marker
