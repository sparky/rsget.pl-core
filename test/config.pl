#!/usr/bin/perl
use strict;
use warnings;
use RSGet::Common;
use RSGet::Config test => "does nothing";

RSGet::Config::load_config_file "test";


print @{ RSGet::Config->test };
sleep 2;
print @{ RSGet::Config->test() };

my $ctxt = RSGet::Context->new( user => 'root' );

sub print_glob
{
	print "args: @_\n";
	print RSGet::Config->glob, "\n";
}

print_glob( "as noone" );
$ctxt->wrap( \&print_glob, "as root" );
print_glob( "as noone" );

# $ctxt->child( users => 'some_user' );

# vim:ts=4:sw=4
