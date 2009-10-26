package RSGet::AutoUpdate;
# This file is an integral part of rsget.pl downloader.
#
# 2009 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
use RSGet::Tools;
use Cwd;

set_rev qq$Id$;

def_settings(
	use_svn => {
		desc => "Set to 'update' to automatically update rsget.pl components from SVN. " .
			"Set to 'yes' to use downloaded components without updating first.",
		default => "no",
		allowed => qr{no|yes|update},
	},
	svn_uri => {
		desc => "SVN path to rsget.pl source code.",
		default => 'http://svn.pld-linux.org/svn/toys/rsget.pl',
		allowed => qr{(svn|https?)://.{4,}},
	},
);

my @update_dirs = qw(data RSGet Get Link Video);

sub update
{
	unless ( require_prog( "svn" ) ) {
		warn "SVN client required\n";
		return 0;
	}
	my $start_dir = getcwd();
	my $svn_dir = $main::local_path;
	mkdir $svn_dir unless -d $svn_dir;
	chdir $svn_dir or die "Can't chdir to '$svn_dir'\n";

	print "Updating from SVN:\n";
	local $ENV{LC_ALL} = "C";
	my $svn_uri = setting("svn_uri");
	my $updated = 0;
	foreach my $dir ( @update_dirs ) {
		my $last;
		print "  $dir:\n";
		open SVN, "-|", "svn", "co", "$svn_uri/$dir";
		while ( <SVN> ) {
			print "    " . $_;
			chomp;
			$updated++;
			$last = $_;
		}
		close SVN;
		unless ( $last =~ /Checked out revision \d+/ ) {
			warn "Update failed ?\n";
		}
	}
	chdir $start_dir;

	$updated -= scalar @update_dirs;
	return undef unless $updated >= 0;
	return $updated;
}

1;

# vim: ts=4:sw=4
