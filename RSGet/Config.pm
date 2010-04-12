package RSGet::Config;
# This file is an integral part of rsget.pl downloader.
#
# 2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
#use RSGet::Common;

my %cache;

sub _get_raw
{
	my $user = shift;
	my $name = shift;

	my $macro = undef;
	if ( $user ) {
		my $mname = "$user.$name";
		$macro = $cache{ $mname } //=
			RSGet::DB::get( "config", "value", { name => $mname } )
			//
			configfile_get( $mname )
			//
			undef;
	}
	if ( not $macro ) {
		my $mname = ".$name";
		$macro = $cache{ $mname } //=
			RSGet::DB::get( "config", "value", { name => $mname } )
			//
			configfile_get( $mname )
			//
			undef;
	}

	return $macro;
}

sub _expand
{
	my $user = shift;
	my $local = shift;
	my $term = shift;

	while ( $term =~ /%{([a-zA-Z0-9\._-]+)}/ ) {
		my $name = $1;
		my $value = $local->{ $name } // _get_raw( $user, $name );
		unless ( defined $value ) {
			warn "RSGet::Config::expand: Macro $term is not defined.\n";
			$value = "";
		}
		$term =~ s#%{$name}#$value#;
	}

	return $term;
}

sub get
{
	my $user = shift;
	my $local = shift;
	my $name = shift;

	my $value = _get_raw( $user, $name );
	if ( wantarray ) {
		return () unless defined $value;
		my @out;
		foreach my $term ( split /\s+/, $value ) {
			push @out, _expand( $user, $local, $term );
		}
		return @out;
	} else {
		return undef unless defined $value;
		return _expand( $user, $local, $value );
	}
}

sub clear_cache
{
	%cache = ();
}

1;

# vim: ts=4:sw=4:fdm=marker
