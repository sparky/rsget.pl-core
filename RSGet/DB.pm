package RSGet::DB;
# This file is an integral part of rsget.pl downloader.
#
# 2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
use RSGet::Common;
use RSGet::Config;

def_settings(
	db => {
		desc => "Place where rsget.pl can store all information."
			. " Must be DBI compatible name.",
		default => "dbi:SQLite:dbname=%{configdir}/rsget.db",
	},
	db_user => {
		desc => "Database user.",
		default => "",
	},
	db_pass => {
		desc => "Database password.",
		default => "",
	},
	db_prefix => {
		desc => "Table prefix, like schema (with prefix 'rsget.' tables will be"
			. "	called 'rsget.tablename').",
		default => "rsget_",
	},
);


my $dbh;
sub init
{
	$dbh = DBI->connect(
		setting( "db" ),
		setting( "db_user" ),
		setting( "db_pass" ),
	);
}

sub END
{
	$dbh->disconnect()
		if $dbh;
}

sub get
{
	my $table = shift;
	my $keys = shift;
	my $where = shift;

	return unless $dbh;

	# TODO
}

sub set
{
	my $table = shift;
	my $keys = shift;
	my $values = shift;
	my $where = shift;

	return unless $dbh;

	# TODO
}

sub del
{
	my $table = shift;
	my $where = shift;

	return unless $dbh;

	# TODO
}

1;

# vim: ts=4:sw=4:fdm=marker
