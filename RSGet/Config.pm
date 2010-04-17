package RSGet::Config;
# This file is an integral part of rsget.pl downloader.
#
# 2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
#use RSGet::Common;

my %cmdline_options;
my %database_options;
my %cfile_options;

my %cache;

sub _get_raw
{
	my $name = shift;
	my $user = shift;

	my $macro = undef;
	if ( $user ) {
		my $mname = "$user.$name";
		$macro = $cache{ $mname } //=
			$cmdline_options{ $mname }
			//
			$database_options{ $mname }
			//
			$cfile_options{ $mname }
			//
			undef;
	}
	if ( not $macro ) {
		my $mname = $name;
		$macro = $cache{ $mname } //=
			$cmdline_options{ $mname }
			//
			$database_options{ $mname }
			//
			$cfile_options{ $mname }
			//
			undef;
	}

	return $macro;
}

sub _expand
{
	my $term = shift;
	my $user = shift;
	my $local = shift;

	$term =~ s/%{([a-zA-Z0-9_-]+)}/get( $1, $user, $local )/eg;

	return $term;
}

sub get
{
	my $name = shift;
	my $user = shift;
	my $local = shift;

	if ( $local ) {
		my $value = $local->{ $name } // _get_raw( $name, $user );
		if ( wantarray ) {
			return () unless defined $value;
			my @out;
			foreach my $term ( split /\s+/, $value ) {
				push @out, _expand( $term, $user, $local );
			}
			return @out;
		} else {
			return undef unless defined $value;
			return _expand( $value, $user, $local );
		}
	}
}

sub clear_cache
{
	%cache = ();
}




sub parse_args
{
	my $argnum = 0;
	my $help;
	while ( my $arg = shift @ARGV ) {
		$argnum++;
		if ( $arg =~ /^-?-h(elp)?$/ ) {
			$help = 1;
		} elsif ( $arg =~ s/^--(.*?)=// ) {
			set( $1, $arg, "command line, argument $argnum" );
		} elsif ( $arg =~ s/^--(.*)// ) {
			my $key = $1;
			my $var = shift @ARGV;
			die "value missing for '$key'" unless defined $var;
			my $a = $argnum++;
			set( $key, $var, "command line, argument $a-$argnum" );
		} else {
			set( "list_file", $arg, "command line, argument $argnum" );
		}
	}
}

sub read_config
{
	my $cfg = shift;
	return unless -r $cfg;
	my $line = 0;
	open F_IN, "<", $cfg;
	while ( <F_IN> ) {
		$line++;
		next if /^\s*(?:#.*)?$/;
		chomp;
		if ( my ( $key, $value ) = /^\s*([a-z_]+)\s*=\s*(.*?)\s*$/ ) {
			$value =~ s/\${([a-zA-Z0-9_]+)}/$ENV{$1} || ""/eg;
			set( $key, $value, "config file, line $line" );
			next;
		}
		warn "Incorrect config line: $_\n";
	}
	close F_IN;
}

1;

# vim: ts=4:sw=4:fdm=marker
