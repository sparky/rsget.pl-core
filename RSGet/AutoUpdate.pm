package RSGet::AutoUpdate;

use strict;
use warnings;
use RSGet::Tools;
use Cwd;

set_rev qq$Id$;

sub update
{
	unless ( require_prog( "svn" ) ) {
		warn "SVN client required\n";
		return 0;
	}
	my $start_dir = getcwd();
	chdir $main::configdir or die "Can't chdir to '$main::configdir'\n";

	warn "Updating from SVN\n";
	my $updated = 0;
	foreach my $dir ( qw(data RSGet Get Link) ) {
		my $last;
		open SVN, "-|", "svn", "co", "$settings{svn_uri}/$dir";
		while ( <SVN> ) {
			chomp;
			$updated++ if /^.{4}\s+$dir/;
			$last = $_;
		}
		close SVN;
		unless ( $last =~ /Checked out revision \d+/ ) {
			warn "Update failed ?\n";
		}
	}
	chdir $start_dir;

	return $updated;
}

1;
# vim:ts=4:sw=4
