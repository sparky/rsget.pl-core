package RSGet::SQL;
# This file is an integral part of rsget.pl downloader.
#
# 2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
use DBI;
use RSGet::Config;

RSGet::Config::register_settings(
	sql_type => {
		desc => "Place where rsget.pl can store all information."
			. " Must be DBI compatible name.",
		default => "dbi:SQLite:dbname=%{config_dir}/sqlite.db",
	},
	sql_user => {
		desc => "Database user.",
		default => "",
	},
	sql_pass => {
		desc => "Database password.",
		default => "",
	},
	sql_prefix => {
		desc => "Table prefix, like schema (with prefix 'rsget.' tables will be"
			. "	called 'rsget.tablename').",
		default => "",
		novalue => "rsget_",
	},
	sql_precommand => {
		desc => "Command executed just after connecting to database.",
		default => "",
	},
);

my $dbh;
my $table_prefix;
sub init
{
	$dbh = DBI->connect(
		RSGet::Config::get( undef, "sql_type" ),
		RSGet::Config::get( undef, "sql_user" ),
		RSGet::Config::get( undef, "sql_pass" ),
		{ AutoCommit => 0 }
	);

	my $pre = RSGet::Config::get( undef, "sql_precommand" );
	$dbh->do( $pre )
		if defined $pre and length $pre;

	$table_prefix = RSGet::Config::get( undef, "sql_prefix" );
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
	return ( "" )
		unless $cond;

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
# my $ret = RSGet::DB::get( "table", { cond => "ble" }, "key" );
#  -> prep: SELECT key FROM table WHERE cond = ? LIMIT 1
#  -> exec: "ble"
#
# my $ret = RSGet::DB::get( "table", { cond => undef }, "key" );
#  -> prep: SELECT key FROM table WHERE cond IS NULL LIMIT 1
#  -> exec: ()
#
# my ($ret1, $ret2) = RSGet::DB::get( "table",
#		{ cond1 => "one", cond2 => "two"  }, "key1, key2" );
#  -> prep: SELECT key1, key2 FROM table WHERE cond1 = ? AND cond2 = ? LIMIT 1
#  -> exec: "one", "two"
#
# my %ret = RSGet::DB::get( "table", { [conditions] }, "*" )
#  -> prep: SELECT * FROM table WHERE [conditions] LIMIT 1
#  -> exec: [conditions]
#
sub get
{
	my $table = $table_prefix . shift;
	my $condition = shift;
	my $keys = shift;

	return unless $dbh;

	my ( $where, @where_param ) = _make_where( $condition );

	$keys = join ", ", @$keys if ref $keys;
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


# my $ret = RSGet::DB::set( "table", { key => "k" }, { value => "v", value2 => "v2" } );
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
	my $table = $table_prefix . shift;
	my $condition = shift;
	my $values = shift;

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
		my $sth = $dbh->prepare( "UPDATE $table SET $values $where" );
		$sth->execute( @values_values, @where_param );
		$dbh->commit();
	} else {
		my @keys = ( @values_keys, keys %$condition );
		my @values = ( @values_values, values %$condition );

		my $keys = join ", ", @keys;
		my $holders = join ", ", ("?") x scalar @keys;

		my $sth = $dbh->prepare( "INSERT INTO $table( $keys ) VALUES ($holders)" );
		$sth->execute( @values );
		$dbh->commit();
	}
}

# delete something

sub del
{
	my $table = $table_prefix . shift;
	my $condition = shift;

	return unless $dbh;

	my ( $where, @where_param ) = _make_where( $condition );

	my $sth = $dbh->prepare( "DELETE FROM $table $where" );
	$sth->execute( @where_param );
	$dbh->commit();
}

sub dbh
{
	return $dbh;
}

sub prepare
{
	return unless $dbh;
	return $dbh->prepare( shift );
}

1;

# vim: ts=4:sw=4:fdm=marker
