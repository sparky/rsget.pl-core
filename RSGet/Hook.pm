package RSGet::Hook;
# This file is an integral part of rsget.pl downloader.
#
# 2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
use RSGet::Common;
use RSGet::Config;

sub dispatch
{
	my $name = shift;
	my $user = shift;
	my %opts = @_;
	$opts{name} = $name;
	$opts{user} = $user;

	my @hook = RSGet::Config::get( "hook-$name", $user, \%opts );
	return unless @hook;

	# TODO: don't block
	open my $hookin, "-|", @hook;
	while ( <$hookin> ) {
		# TODO: interpret orders from hook
	}
	close $hookin;
}

1;

# vim: ts=4:sw=4:fdm=marker
