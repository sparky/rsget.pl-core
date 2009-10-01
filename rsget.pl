#!/usr/bin/perl
#
# 2009 (c) Przemysław Iskra <sparky@pld-linux.org>
# Use/modify/distribute under GPL v2 or newer.
#
use strict;
use warnings;
my $rev = qq$Id$;

our $install_path = $ENV{PWD};
our $local_path = $install_path;

our %def_settings;
our %settings = (
	use_svn => [ "no", undef ]
);

unshift @INC, $install_path;

my $cdir = "$ENV{HOME}/.rsget.pl";
read_config( "$cdir/config" );

my @save_ARGV = @ARGV;
my $help;
my @ifs;
parse_args();

if ( $settings{use_svn}->[0] =~ /^(yes|update)$/ ) {
	$local_path = $cdir;
	unshift @INC, $local_path;

	eval {
		require RSGet::Main;
	};
	if ( $@ ) {
		shift @INC;
		warn "Cannot use components from SVN: $@\n";
		set( "use_svn", "no", "disabled because of errors" )
			if $settings{use_svn}->[0] eq "yes";
	}
}

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

sub read_config
{
	my $cfg = shift;
	return unless -r $cfg;
	my $line = 0;
	open F_IN, "<", $cfg;
	while ( <F_IN> ) {
		$line++;
		next if /^\s*(?:#.*)?$/;
		chomp;
		if ( s/^\s*([a-z_]+)\s*=\s*// ) {
			set( $1, $_, "config file, line $line" );
			next;
		}
		warn "Incorrect config line: $_\n";
	}
	close F_IN;
}

sub parse_args
{
	my $argnum = 0;
	while ( my $arg = shift @ARGV ) {
		$argnum++;
		if ( $arg =~ /^-?-h(elp)?$/ ) {
			$help = 1;
		} elsif ( $arg =~ s/^--(.*?)=// ) {
			set( $1, $arg, "command line, argument $argnum" );
		} elsif ( $arg =~ s/^--(.*)// ) {
			my $key = $1;
			my $var = shift @ARGV;
			die "value missing for '$key'" unless defined $var;
			my $a = $argnum++;
			set( $key, $var, "command line, argument $a-$argnum" );
		} else {
			set( "list_file", $arg, "command line, argument $argnum" );
		}
	}
}

# vim:ts=4:sw=4
