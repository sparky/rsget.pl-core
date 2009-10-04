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

sub arr_exists
{
	my $arr = shift;
	my $scalar = shift;
	foreach my $v ( @$arr ) {
		return 1 if $v eq $scalar;
	}
	return 0;
}

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


my %all_lists;
sub add_list
{
	my $text = shift;
	my $id = shift;

	unless ( $id ) {
		do {
			$id = sprintf "%.6x", int rand ( 1 << 24 );
		} while ( exists $all_lists{$id} );
	}
	my $list = $all_lists{$id} ||= {};
	return unless ref $list;

	$list->{comment} ||= [];
	my $lines = $list->{lines} ||= [];

	my %list_uris;
	foreach my $mcd ( @$act_clist ) {
		foreach my $ucd ( @$mcd ) {
			my $uri = $ucd->[0];
			$list_uris{ $uri } = 1;
		}
	}

	my %all_uris;
	foreach my $line ( @$lines ) {
		next unless ref $line;
		my $uris = $line->{uris};
		foreach my $uri ( keys %$uris ) {
			if ( $all_uris{ $uri } ) {
				warn "$uri repeated!";
				delete $uris->{ $uri };
			} else {
				$all_uris{ $uri } = 1;
			}
		}
	}

	my $u = qr/[a-z0-9_-]+/;
	my $tld = qr/[a-z]{2,8}/;
	foreach ( split /\s+/s, $text ) {
		next unless m{^(.*?)(https?://)?((?:$u\.)*$u\.$tld/.+)$};
		my $pre = $1;
		my $proto = $2 || "http://";
		my $uri = $proto . $3;
		if ( $pre ) {
			if ( $pre =~ /%([0-9A-F]{2})$/ ) {
				my $l = chr hex $1;
				$l =~ tr/[](){}<>/][)(}{></;
				$l = sprintf "%.2X", ord $l;
				$uri =~ s/%$l.*//i;
			} elsif ( $pre =~ m{.*([^a-zA-Z0-9_/])$} ) {
				my $l = $1;
				$l =~ tr/[](){}<>/][)(}{></;
				$uri =~ s/\Q$l\E.*//;
			}
		}
		my $getter = RSGet::Dispatch::getter( $uri );
		next unless $getter;
		next if exists $all_uris{ $uri };
		$all_uris{ $uri } = 1;
		my $options = {};
		$options->{error} = "Already on the list" if $list_uris{ $uri };
		my $line = { cmd => "ADD", globals => {}, uris => { $uri => [ $getter, $options ] } };
		push @$lines, $line;
	}
	$list->{id} = $id;

	return $list;
}

sub add_list_find
{
	my $id = shift;

	my $list = $all_lists{ $id };
	return () unless $list;
}

sub add_list_comment
{
	my $text = shift;
	my $id = shift;

	my $list = add_list_find( $id ) || return;
	return $list unless ref $list;

	my $c = $list->{comment};

	foreach ( split /[\r\n]+/s, $text ) {
		s/^\s*#\s*//;
		push @$c, "# " . $_;
	}

	return $list;
}


sub add_list_update
{
	my $id = shift;

	my $list = add_list_find( $id ) || return;
	return $list unless ref $list;

	my $lines = $list->{lines};
	$list->{select_clone} = 1;
	my @used_save;
	for ( my $i = 0; $i < scalar @$lines; $i++ ) {
		my $line = $lines->[$i];
		next unless ref $line;
		my $globals = $line->{globals};
		my $uris = $line->{uris};
		unless ( keys %$uris ) {
			my $l = splice @$lines, $i, 1;
			redo;
		}

		foreach my $uri ( keys %$uris ) {
			my ( $getter, $options ) = @{ $uris->{ $uri } };
			
			if ( my $save = $RSGet::FileList::save{ $uri } ) {
				push @used_save, $uri;
				$list->{select_clone} = 0;
			
				$line->{cmd} = $save->{cmd} if $save->{cmd};
				hadd $globals, %{$save->{globals}} if $save->{globals};
				hadd $options, %{$save->{options}} if $save->{options};

				if ( my $links = $save->{links} ) {
					my @new;
					foreach my $uri ( @$links ) {
						my $getter = RSGet::Dispatch::getter( $uri );
						if ( $getter ) {
							push @new, { cmd => "ADD", globals => {}, uris => { $uri => [ $getter, {} ] } };
						} else {
							push @new, "# unsupported uri: $uri";
						}
					}
					splice @$lines, $i+1, 0, @new;
				}
				if ( my $clones = $save->{clones} ) {
					hadd $uris, %$clones;
					# will check new ones next time
				}
				if ( $save->{delete} ) {
					delete $uris->{ $uri };
					next;
				}
			}

			my $chk = RSGet::Dispatch::check( $uri, $getter, $options );
			$list->{select_clone} = 0 unless $chk;
		}
	}

	foreach my $uri ( @used_save ) {
		delete $RSGet::FileList::save{ $uri };
	}

	return $list;
}

sub add_list_clones
{
	my $id = shift;

	my $list = add_list_find( $id ) || return;
	return $list unless ref $list;

	$list->{select_clone} = 1;
	my $lines = $list->{lines};
	my $own_clist = [ @$act_clist ];
	my $active = 0;

	my $clone_select;

	foreach my $line ( @$lines ) {
		next unless ref $line;
		my ( $cmd, $globals, $uris ) = @$line{ qw(cmd globals uris) };

		foreach my $uri ( keys %$uris ) {
			my ( $getter, $options ) = @{ $uris->{ $uri } };

			my @cd = clone_data( { %$options, %$globals } );
			unless ( @cd ) {
				$line->{cmd} = "STOP" if $options->{error};
				next;
			}

			if ( $line->{cmd} ne "ADD" ) {
				$active++;
				push @$own_clist, [ [ $uri, @cd ] ];
				next;
			}

			my @clones = find_clones( $own_clist, \@cd );
			if ( @clones ) {
				$clone_select = [ $uri, $options, \@clones ];
			} else {
				$line->{cmd} = "GET";
				push @$own_clist, [ [ $uri, @cd ] ];
			}
		}
		last if $clone_select;
	}
	$list->{active} = $active;

	return ( $list, $clone_select );
}

sub add_list_find_uri
{
	my $list = shift;
	my $furi = shift;

	my $lines = $list->{lines};
	foreach my $line ( @$lines ) {
		next unless ref $line;
		my ( $cmd, $globals, $uris ) = @$line{ qw(cmd globals uris) };

		foreach my $uri ( keys %$uris ) {
			if ( $uri eq $furi ) {
				return $line;
			}
		}
	}
	return;
}

sub add_list_add
{
	my $id = shift;
	my $list = add_list_find( $id );

	my @new;
	my $comment = $list->{comment};
	foreach my $line ( @$comment ) {
		push @new, $line . "\n";
	}

	my $lines = $list->{lines};
	foreach my $line ( @$lines ) {
		next unless ref $line;
		my ( $cmd, $globals, $uris ) = @$line{ qw(cmd globals uris) };

		foreach my $uri ( sort keys %$uris ) {
			my $o = $uris->{ $uri }->[1];
			delete $uris->{ $uri } unless $o->{size} or $o->{asize} or $o->{quality};
		}

		next unless keys %$uris;

		{
			my @out = ( "$cmd:", RSGet::FileList::h2a( $globals ) );
			push @new, (join " ", @out) . "\n";
		}
		foreach my $uri ( sort keys %$uris ) {
			my @out = ( $uri, RSGet::FileList::h2a( $uris->{ $uri }->[1] ) );
			push @new, (join " ", '+', @out) . "\n";
		}
	}
	push @RSGet::FileList::added, @new;
	RSGet::FileList::update();

	$all_lists{ $id } = "Sources added";
}

sub add_command
{
	my $lastid = shift;
	my $id = shift;
	my $exec = shift;
	unless ( $exec =~ s/^(.*?):(.*?_.*?)_// ) {
		warn "Invalid command: $exec\n";
		return;
	}
	my $cmd = $1;
	my $grp = $2;

	my $idgrp = $lastid->{$grp};
	my $data = $idgrp->{ $exec };
	unless ( $data ) {
		warn "Invalid ID: $cmd, $grp, $exec\n";
		return undef;
	}

	my $list = add_list_find( $id ) || return;
	return $list unless ref $list;

	if ( $grp =~ s/addclone_// ) {
		my @save;
		if ( $cmd ne "SELECT" ) {
			warn "Invalid command: $cmd, $grp, $exec\n";
			return;
		}
		my $newuri = $idgrp->{uri};
		my $newline = add_list_find_uri( $list, $newuri );
		if ( $data eq "NEW SOURCE" ) {
			my $line = add_list_find_uri( $list, $newuri );
			$line->{cmd} = "GET";
		} elsif ( my $line = add_list_find_uri( $list, $data ) ) {
			$line->{uris}->{ $newuri } = $newline->{uris}->{ $newuri };
			delete $newline->{uris}->{ $newuri };
		} else {
			RSGet::FileList::save( $data, clones =>
				{ $newuri => $newline->{uris}->{ $newuri } } );
			delete $newline->{uris}->{ $newuri };
			RSGet::FileList::update();
		}
	} elsif ( $grp =~ s/adduri_// ) {
		my $target = add_list_find_uri( $list, $data );
		if ( $cmd eq "CLEAN ERROR" ) {
			delete $target->{uris}->{ $data }->[1]->{error};
		} elsif ( $cmd eq "DISABLE" ) {
			$target->{uris}->{ $data }->[1]->{error} = "disabled";
		} elsif ( $cmd eq "REMOVE" ) {
			delete $target->{uris}->{ $data };
		} else {
			warn "Invalid command: $cmd, $grp, $exec\n";
			return;
		}
	} elsif ( $grp =~ s/addlist_// ) {
		if ( $cmd eq "CONFIRM" ) {
			add_list_add( $id );
		}
	} else {
		warn "Invalid command group: $cmd, $grp, $exec\n";
		return;
	}
}

1;

# vim: ts=4:sw=4:fdm=marker
