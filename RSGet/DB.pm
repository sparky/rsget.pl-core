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
		{ AutoCommit => 0 }
	);
}

sub END
{
	if ( $dbh ) {
		$dbh->commit();
		$dbh->disconnect();
	}
}

sub _make_where($)
{
	my $cond = shift;

	my @param;
	my @where;
	foreach my $k ( keys %$cond ) {
		my $val = $cond->{ $k };
		if ( defined $val ) {
			push @where, "$k = ?";
			push @param, $val;
		} else {
			push @where, "$k IS NULL";
		}
	}

	return ( "" )
		unless @where;

	my $where = "WHERE " . join " AND ", @where;
	return $where, @param;
}

# simple database get, gets exactly 1 object
#
# my $ret = RSGet::DB::get( "table", "key", { cond => "ble" } );
#  -> prep: SELECT key FROM table WHERE cond = ? LIMIT 1
#  -> exec: "ble"
#
# my $ret = RSGet::DB::get( "table", "key", { cond => undef } );
#  -> prep: SELECT key FROM table WHERE cond IS NULL LIMIT 1
#  -> exec: ()
#
# my ($ret1, $ret2) = RSGet::DB::get( "table", "key1, key2", {
# 			cond1 => "one", cond2 => "two"  } );
#  -> prep: SELECT key1, key2 FROM table WHERE cond1 = ? AND cond2 = ? LIMIT 1
#  -> exec: "one", "two"
#
# my %ret = RSGet::DB::get( "table", "*", { conditions } )
#  -> prep: SELECT * FROM table WHERE conditions LIMIT 1
#  -> exec: conditions
#
sub get
{
	my $table = shift;
	my $keys = shift;
	my $condition = shift;

	return unless $dbh;

	my ( $where, @where_param ) = _make_where( $condition );

	my $sth = $dbh->prepare( "SELECT $keys FROM $table $where LIMIT 1" );
	$sth->execute( @where_param );

	if ( $keys eq "*" ) {
		my $hash = $sth->fetchrow_hashref();
		return %$hash
			if wantarray;
		return $hash;
	} elsif ( $keys =~ /,/ ) {
		my $array = $sth->fetchrow_arrayref();
		return @$array
			if wantarray;
		return $array;
	} else {
		my @array = $sth->fetchrow_array();
		return @array
			if wantarray;
		return $array[0];
	}
}


# my $ret = RSGet::DB::set( "table", { value => "v", value2 => "v2" }, { key => "k" } );
#  -> prep: SELECT value FROM table WHERE key = ?
#  -> exec: "k"
#  -> value == "v" and value2 == "v2" ? return
#  -> exists ?
#  ->   prep: UPDATE table SET value = ?, value2 = ? WHERE key = ?
#  ->   exec: "v", "v2", "k"
#  -> else
#  ->   prep: INSERT INTO table( value, value2, key ) VALUES ( ?, ?, ? )
#  ->   exec: "v", "v2", "k",
#
sub set
{
	my $table = shift;
	my $values = shift;
	my $condition = shift;

	return unless $dbh;

	my @values_keys = keys %$values;
	my @values_values = values %$values;

	my ( $where, @where_param ) = _make_where( $condition );

	my $row;
	{
		my $keys = join ", ", @values_keys;
		my $sth = $dbh->prepare( "SELECT $keys FROM $table $where LIMIT 1" );
		$sth->execute( @where_param );
		$row = $sth->fetchrow_hashref();
	}

	if ( $row ) {
		my $all_eq = 1;
		foreach my $k ( keys %$values ) {
			if ( not $row or $values->{$k} ne $row->{$k} ) {
				$all_eq = 0;
				last;
			}
		}
		return if $all_eq;
		
		my $values = join ", ", map "$_ = ?", @values_keys;
		$dbh->begin_work();
		my $sth = $dbh->prepare( "UPDATE $table SET $values $where" );
		$sth->execute( @values_values, @where_param );
		$dbh->commit();
	} else {
		my @keys = ( @values_keys, keys %$condition );
		my @values = ( @values_values, values %$condition );

		my $keys = join ", ", @keys;
		my $holders = join ", ", ("?") x scalar @keys;

		$dbh->begin_work();
		my $sth = $dbh->prepare( "INSERT INTO $table( $keys ) VALUES ($holders)" );
		$sth->execute( @values );
		$dbh->commit();
	}
}

# delete something

sub del
{
	my $table = shift;
	my $condition = shift;

	return unless $dbh;

	my ( $where, @where_param ) = _make_where( $condition );

	$dbh->begin_work();
	my $sth = $dbh->prepare( "DELETE FROM $table $where" );
	$sth->execute( @where_param );
	$dbh->commit();
}

1;

# vim: ts=4:sw=4:fdm=marker