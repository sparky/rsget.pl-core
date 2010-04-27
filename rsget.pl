#!/usr/bin/perl
#  This file is the main executable of rsget.pl downloader.
#
# 2009-2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.
#
use strict;
use warnings;

BEGIN {
	our $install_path = do { require Cwd; Cwd::getcwd(); };
	unshift @INC, $install_path;
}

my $args = sort_args( @ARGV );

eval {
	require RSGet::Config;
};
if ( $@ ) {
	die "Cannot start rsget.pl: $@\n";
}

if ( $args->{core} ) {
	eval {
		require RSGet::Core;
	};
	if ( $@ ) {
		die "Cannot start rsget.pl: $@\n";
	}
	RSGet::Config::init( @{ $args->{_opts} }, @{ $args->{core}->{opts} } );
}

#RSGet::Main::init( $help, $rev, \@save_ARGV, \@ifs );
die "init failed";


sub sort_args
{
	my %organized;

	my $opts = $organized{_opts} = [];
	my $args;

	local $_;

	my $argn = 0;
	my $nextcmd = 0;
	while ( $_ = shift @_ ) {
		$argn++;
		if ( $_ eq "--" ) {
			$opts = $organized{_opts};
			$args = undef;
			$nextcmd = 1;
		} elsif ( s/^--(\S+)=// ) {
			push @$opts, [ $1, $_, "Command line argument $argn" ];
			$nextcmd = 0;
		} elsif ( s/^--// ) {
			push @$opts, [ $_, undef, "Command line argument $argn" ];
			$nextcmd = 0;
		} elsif ( $args and not $nextcmd ) {
			push @$args, $_;
		} else {
			my $cmd = $organized{ $_ } = {};
			$opts = $cmd->{opts} = [];
			$args = $cmd->{args} = [];
			$nextcmd = 0;
		}
	}

	return \%organized;
}

# vim: ts=4:sw=4:fdm=marker
