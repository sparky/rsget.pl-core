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
);
RSGet::Config::init();

RSGet::Config::set( undef, "foo", 'test: %{p}{test}' );

my @macros = qw(test_macro test_env test_perl test_cmd foo);
foreach ( @macros ) {
	my $v = RSGet::Config::get( undef, $_ );
	print "$_: $v\n";
}



# vim:ts=4:sw=4
