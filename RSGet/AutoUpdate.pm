package RSGet::AutoUpdate;

use strict;
use warnings;
use RSGet::Tools;
use Cwd;

set_rev qq$Id$;

def_settings(
	use_svn => [ "Set to 'update' to automatically update rsget.pl components from SVN. " .
		"Set to 'yes' to use downloaded components without updating first.",
		"no", qr{no|yes|update} ],
	svn_uri => [ "SVN path to rsget.pl source code.",
		'http://svn.pld-linux.org/svn/toys/rsget.pl',
		qr{(svn|http)://\.{4,}} ],
);

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
	my $svn_uri = setting("svn_uri");
	my $updated = 0;
	foreach my $dir ( qw(data RSGet Get Link) ) {
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

	$updated -= 4;
	return undef unless $updated >= 0;
	return $updated;
}

1;
# vim:ts=4:sw=4
