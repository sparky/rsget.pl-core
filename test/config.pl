#!/usr/bin/perl
use strict;
use warnings;
use RSGet::Config;

RSGet::Config::register_settings(
	test => {
		default => 'foo',
	},
	num => {
		default => 5,
	},
	test_macro => {
		default => 'test: [%{test}]',
	},
	test_env => {
		default => 'test: [${HOME}]',
	},
	test_perl => {
		default => 'test: [%(3 + 2 + %{num})]',
	},
	test_cmd => {
		default => 'test: [$(ls -l)]',
	},
	test_l => {
		default => "3, 4",
	},
	test_list => {
		default => '1, 2, %{test_l}, %{num}, %(5+1), $(expr 5 + 2)',
	},
);
RSGet::Config::init();

{
	my $dynaconfig;

	if ( 0 ) {
		require RSGet::ConfigFile;
		$dynaconfig = new RSGet::ConfigFile;
	} else {
		# sqlite is awfully slow
		require RSGet::SQL;
		require RSGet::ConfigSQL;
		RSGet::SQL::init();
		$dynaconfig = new RSGet::ConfigSQL;
	}

	RSGet::Config::register_dynaconfig( $dynaconfig );
}

my @macros = qw(test_macro test_env test_perl test_cmd foo test_l);
foreach ( @macros ) {
	my $v = RSGet::Config::get( undef, $_ );
	print "$_: $v\n";
}

RSGet::Config::set( undef, "foo", 'test: %{p}{test}' . $$ );

my $e = RSGet::Config::expand( undef, "[ %{p} %{test} %{foo} %{something} ]" );
print "expand: $e\n";

my @l = RSGet::Config::get_list( undef, "test_list" );
print "list:\n- ";
print join "\n- ", @l;
print "\n.\n";

# speed test
foreach my $i ( 0..10000 ) {
	RSGet::Config::set( undef, "test", 'test: %{p}{test}b' . $i );
}

# vim:ts=4:sw=4
