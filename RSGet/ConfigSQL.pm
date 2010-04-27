package RSGet::ConfigSQL;
# This file is an integral part of rsget.pl downloader.
#
# 2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
use RSGet::Config;
use RSGet::SQL;

#RSGet::Config::register_settings(
#);

# initalized ?
my $init = 0;

sub new
{
	my $class = shift;
	my $self = \"config";

	return bless $self, $class;
}

sub set
{
	my $self = shift;
	my ( $user, $key, $value ) = @_;

	RSGet::SQL::set(
		$$self,
		{ user => $user, key => $key },
		{ value => $value }
	);
}

sub getall
{
	my $self = shift;

	return RSGet::SQL::dbh->selectall_arrayref(
	(
		"SELECT user, key, value, 'database' FROM $$self"
	);
}

sub init
{
	return if $init;
	RSGet::Config::register_dynaconfig(
		new RSGet::ConfigSQL
	);

	$init = 1;
}

1;

# vim: ts=4:sw=4:fdm=marker
