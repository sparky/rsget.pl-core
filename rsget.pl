#!/usr/bin/perl
# $Id$
#  This file is the main executable of rsget.pl downloader.
#
# 2009-2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.
#
use strict;
use warnings;
my $rev = qq$Id$;

our $install_path = do { require Cwd; Cwd::getcwd(); };
our $local_path = $install_path;

our %def_settings;
our %settings;

unshift @INC, $install_path;

my $cdir = "$ENV{HOME}/.rsget.pl";
$cdir = $ENV{RSGET_DIR} if $ENV{RSGET_DIR};
$ENV{RSGET_DIR} = $cdir;
read_config( "$cdir/config" );

my @save_ARGV = @ARGV;
my $help;
my @ifs;
parse_args();

eval {
	require RSGet::Main;
};
if ( $@ ) {
	die "Cannot start rsget.pl: $@\n";
}

RSGet::Main::init( $help, $rev, \@save_ARGV, \@ifs );
die "init failed";

sub set
{
	my $name = shift;
	my $value = shift;
	my $where_defined = shift;
	$name =~ tr/-/_/;
	$settings{ $name } = [ $value, $where_defined ];
}



# vim:ts=4:sw=4
