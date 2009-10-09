package RSGet::Dispatch;

use strict;
use warnings;
use RSGet::Tools;
set_rev qq$Id$;

def_settings(
	max_slots => [ "Number of slots (per IP) to use if getter has no limitation.", 8, qr/0*[1-9]\d*/ ],
);

our %downloading;
our %checking;
our %resolving;

my %working = (
	get => \%downloading,
	check => \%checking,
	link => \%resolving,
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
		p "Adding $new_if interface/address\n";
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

sub finished
{
	my $obj = shift;
	my $status = shift;

	my ( $uri, $cmd ) = @$obj{ qw(_uri _cmd) };
	my $working = $working{ $cmd };
	delete $working->{ $uri };


	RSGet::FileList::update();
}

sub get_slots
{
	my $cmd = shift;
	my $suggested = shift;
	return setting( "max_slots" ) if $cmd eq "check";
	unless ( defined $suggested ) {
		return $cmd eq "get" ? 1 : 5;
	}
	return 0 + $suggested if $suggested =~ /^\d+$/;
	return setting( "max_slots" ) if lc $suggested eq "max";
	warn "Invalid slots declaration: $suggested\n" if verbose( 1 );
	return 1;
}

sub run
{
	my ( $cmd, $uri, $getter, $options ) = @_;
	my $class = $getter->{class};
	$cmd = "link" if $class eq "Link";

	return if $options->{error};

	my $working = $working{ $cmd };
	my $w = $working->{ $uri };
	return $w if defined $w;

	my $pkg = $getter->{pkg};
	my $outif = find_free_if( $pkg, $working, get_slots( $cmd, $getter->{slots} ) );
	return unless defined $outif;

	my $obj = RSGet::Get::new( $pkg, $cmd, $uri, $options, $outif );
	$working->{ $uri } = $obj if $obj;
	
	return $obj;
}

sub check
{
	my $uri = shift;
	my $getter = shift;
	my $options = shift;

	return $options if $options->{error};
	if ( $getter->{class} eq "Link" ) {
		return $options if $options->{link1};
	} else {
		return $options if $options->{size} or $options->{asize};
		return $options if $options->{quality};
		return $options if $options->{link1};
	}

	run( "check", $uri, $getter, $options );
	return undef;
}

sub process
{
	my $getlist = shift;

	my %num_by_pkg;
	my %all_uris;
	my $to_dl = 0;
	foreach my $line ( @$getlist ) {
		next unless ref $line;
		my $uris = $line->{uris};
		my $cmd = $line->{cmd};

		if ( $cmd eq "STOP" ) {
			foreach my $uri ( keys %$uris ) {
				if ( my $obj = $downloading{$uri} ) {
					$obj->{_abort} = "Stopped";
				}
			}
			next;
		}
		next unless $cmd eq "GET";

		$to_dl++;
		foreach my $uri ( keys %$uris ) {
			my ( $getter, $opts ) = @{ $uris->{ $uri } };
			if ( $opts->{error} ) {
				if ( my $obj = $downloading{$uri} ) {
					$obj->{_abort} = "Stopped";
				}
				next;
			}
			$all_uris{ $uri } = 1;
			my $pkg = $getter->{pkg};
			$num_by_pkg{ $pkg } ||= 0;
			$num_by_pkg{ $pkg }++;
		}
	}

	abort_missing( \%all_uris, \%downloading );
	RSGet::Line::status(
		'to download' => $to_dl,
		'downloading' => scalar keys %downloading,
		'resolving links' => scalar keys %resolving,
		'checking URIs' => scalar keys %checking,
	);

	my $all_checked = 1;
	EACH_LINE: foreach my $line ( @$getlist ) {
		next unless ref $line;

		my ( $cmd, $globals, $uris ) = @$line{ qw(cmd globals uris) };
		next if $cmd eq "DONE";

		my %pkg_by_uri;

		foreach my $uri ( keys %$uris ) {
			my ( $getter, $options ) = @{ $uris->{ $uri } };
			$pkg_by_uri{ $uri } = $getter->{pkg};
			my $chk = check( $uri, $getter, { %$options, %$globals } );
			$all_checked = 0 unless $chk;
		}

		next unless $all_checked;
		next unless $cmd eq "GET";

		# is it running already ?
		foreach my $uri ( keys %$uris ) {
			next EACH_LINE if $working{get}->{ $uri };
		}

		foreach my $uri ( sort {
					( $num_by_pkg{ $pkg_by_uri{ $a } } || 0 )
						<=>
					( $num_by_pkg{ $pkg_by_uri{ $b } } || 0 )
				} keys %$uris ) {
			my ( $getter, $options ) = @{ $uris->{ $uri } };
			next EACH_LINE if run( "get", $uri, $getter, { %$options, %$globals } );
		}
	}

	return $all_checked;
}

sub abort_missing
{
	my $all = shift;
	my $running = shift;
	foreach ( keys %$running ) {
		next if $all->{$_};
		my $obj = $running->{$_};
		$obj->{_abort} = "Stopped or removed from the list!";
	}
}

sub getter
{
	my $uri = shift;
	foreach my $getter ( values %getters ) {
		foreach my $re ( @{ $getter->{uri} } ) {
			return $getter
				if $uri =~ m{^http://(?:www\.)?$re};
		}
	}
	return undef;
}

sub unigetter
{
	my $uri = shift;
	my $getter = getter( $uri );
	if ( $getter ) {
		my $unify = $getter->{unify};
		$uri = &$unify( $uri );
		return $getter, $uri;
	}
	return undef, $uri;
}


1;

# vim:ts=4:sw=4
