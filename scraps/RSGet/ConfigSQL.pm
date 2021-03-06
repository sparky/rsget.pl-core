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

sub new
{
	my $class = shift;
	my $table = shift || "config";
	my $self = \$table;

	return bless $self, $class;
}

sub set
{
	my $self = shift;
	my ( $user, $key, $value ) = @_;

	RSGet::SQL::set(
		$$self,
		{ user => $user, name => $key },
		{ value => $value }
	);
}

sub get
{
	my $self = shift;
	my ( $user, $key ) = @_;

	return RSGet::SQL::get(
		$$self,
		{ user => $user, name => $key },
		"value"
	);
}

sub getall
{
	my $self = shift;

	return RSGet::SQL::dbh->selectall_arrayref(
		"SELECT user, name, value, 'database' FROM $RSGet::SQL::prefix$$self"
	);
}

1;

# vim: ts=4:sw=4:fdm=marker
