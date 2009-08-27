package RSGet::Dispatch;

use strict;
use warnings;
use RSGet::Tools;

our %downloading;
our %downloaded;
our %checking;
our %checked; # HASH for valid, SCALAR if error
our %resolving;
our %resolved;

my %working = (
	get => \%downloading,
	check => \%checking,
	link => \%resolving,
);
my %finished = (
	get => \%downloaded,
	check => \%checked,
	link => \%resolved,
);

my @interfaces;
sub add_interface
{
	my $newifs = shift;
	NEW_IP: foreach my $new_if ( split /[ ,]+/, $newifs ) {
		foreach my $old_if ( @interfaces ) {
			if ( $new_if eq $old_if ) {
				print "Address $new_if already on the list\n";
				next NEW_IP;
			}
		}
		print "Adding $new_if interface/address\n";
		push @interfaces, $new_if;
	}
}

sub remove_interface
{
	my $if = shift;
	my $reason = shift;
	for ( my $i = 0; $i < @interfaces; $i++ ) {
		next unless $interfaces[ $i ] eq $if;
		my $removed = splice @interfaces, $i, 1;
		warn "Removed interface '$removed': $reason\n";
	}

	die "No working interfaces left\n" unless @interfaces;
}

my %last_used;

sub find_free_if
{
	my $pkg = shift;
	my $working = shift;
	my $slots = shift;

	unless ( scalar @interfaces ) {
		my $running = 0;
		foreach ( values %$working ) {
			$running++ if $_->{_pkg} eq $pkg
		}
		#p "running: $running / $slots";
		return undef if $running >= $slots;
		return "";
	}

	my %by_pos = map { $interfaces[ $_ ] => $_ } (0..$#interfaces);
	my %by_if = map { $_ => 0 } @interfaces;
	foreach ( values %$working ) {
		next unless $_->{_pkg} eq $pkg;
		$by_if{ $_->{_outif} }++;
	}

	my $min = $slots;
	grep { $min = $_ if $_ < $min } values %by_if;
	return undef if $min >= $slots;

	my $lu = $last_used{$pkg} ||= {};
	my @min_if = sort {
		my $_a = $lu->{ $a } || $by_pos{ $a };
		my $_b = $lu->{ $b } || $by_pos{ $b };
		$_a <=> $_b
	} grep { $by_if{ $_ } <= $min } keys %by_if;
	return $min_if[ 0 ];
}

sub mark_used
{
	my $obj = shift;
	my $if = $obj->{_outif};
	return unless $if;
	my $pkg = $obj->{_pkg};
	my $lu = $last_used{$pkg} ||= {};
	$lu->{$if} = time;
}

sub is_error
{
	my $uri = shift;
	my $c = $checked{ $uri };
	return undef unless defined $c;
	if ( $c and not ref $c ) {
		return $c;
	}
	return 0;
}
sub is_ok
{
	my $uri = shift;
	my $c = $checked{ $uri };
	return undef unless defined $c;
	if ( $c and ref $c and ref $c eq "HASH" ) {
		return $c;
	}
	return 0;
}

sub finished
{
	my $obj = shift;
	my $status = shift;

	my ( $uri, $cmd ) = @$obj{ qw(_uri _cmd) };
	my $working = $working{ $cmd };
	delete $working->{ $uri };

	if ( $status ) {
		my $finished = $finished{ $cmd };
		$finished->{ $uri } = $status;
	}

	$RSGet::FileList::reread = 1;
}

sub run
{
	my ( $cmd, $uri, $getter, $options ) = @_;
	my $class = $getter->{class};
	$cmd = "link" if $class eq "Link";
	#p "run( $cmd, $uri, ... )";

	my $finished = $finished{ $cmd };
	my $f = $finished->{ $uri };
	return $f if defined $f;
	#p "-> not finished";

	my $working = $working{ $cmd };
	my $w = $working->{ $uri };
	return $w if defined $w;
	#p "-> not working";

	my $pkg = $getter->{pkg};
	my $outif = find_free_if( $pkg, $working, ($cmd eq "get" ? ($getter->{slots} || 1) : 5) );
	return unless defined $outif;
	#p "-> got if";

	my $obj = RSGet::Get::new( $pkg, $cmd, $uri, $options, $outif );
	$working->{ $uri } = $obj if $obj;
	#p "run( $cmd, $uri, ... ) -> $obj" if $obj;
	
	$RSGet::FileList::reread = 1;

	return $obj;
}

sub process
{
	my $getlist = shift;

	my %num_by_pkg;
	my %all_uris;
	foreach my $line ( @$getlist ) {
		my ( $uris, $options ) = @$line;
		foreach my $uri ( keys %$uris ) {
			my $getter = $uris->{ $uri };
			$all_uris{ $uri } = 1;
			my $pkg = $getter->{pkg};
			$num_by_pkg{ $pkg } ||= 0;
			$num_by_pkg{ $pkg }++;
		}
	}
	abort_missing( \%all_uris, $_ ) foreach values %working;
	RSGet::Line::status(
		'to download' => scalar @$getlist,
		'downloading' => scalar keys %downloading,
		'resolving links' => scalar keys %resolving,
		'checking URIs' => scalar keys %checking,
	);

	my $all_valid = 1;
	foreach my $line ( @$getlist ) {
		my ( $uris, $options ) = @$line;
		foreach my $uri ( keys %$uris ) {
			my $getter = $uris->{ $uri };
			my $ok = is_ok( $uri );
			#p "$uri - $ok";
			if ( not defined $ok ) {
				run( "check", $uri, $getter, $options );
				$all_valid = 0;
			} elsif ( not $ok ) {
				$all_valid = 0;
			}
		}

		next unless $all_valid;

		foreach my $uri ( sort {
					my $a_pkg = $uris->{ $a }->{pkg};
					my $b_pkg = $uris->{ $b }->{pkg};
					$num_by_pkg{ $a_pkg } <=> $num_by_pkg{ $b_pkg }
				} keys %$uris ) {
			my $getter = $uris->{ $uri };
			last if run( "get", $uri, $getter, $options );
		}
	}
}

sub abort_missing
{
	my $all = shift;
	my $running = shift;
	foreach ( keys %$running ) {
		next if exists $all->{$_};
		my $obj = $running->{$_};
		$obj->{_abort} = "Removed from the list!";
	}
}

sub done
{
	my $uri = shift;
	my $getter = shift;

	my $class = $getter->{class};
	my $cmd = $class eq "Link" ? "link" : "get";

	my $f = $finished{ $cmd }->{ $uri };
	return $f if defined $f;
	return undef;
}

1;

# vim:ts=4:sw=4
