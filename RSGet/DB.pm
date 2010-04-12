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
	database => {
		desc => "Place where rsget.pl can store all information.",
		default => "dbi:SQLite:dbname=rsget.db",
	}
);


my $dbh;
sub init
{
	$dbh = DBI->connect( setting( "database" ), "", "" );
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
