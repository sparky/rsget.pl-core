package RSGet::Common;
# This file is an integral part of rsget.pl downloader.
#
# Copyright (C) 2010	Przemysław Iskra <sparky@pld-linux.org>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use strict;
use warnings;

=head1 RSGet::Common -- common functions

This package implements some very common functions.

=head2 use RSGet::Common qw(FUNCTIONS);

Package is able to export all of its functions, but they must be listed
explicitly.

=cut

# micro exporter
sub import
{
	my $callpkg = caller 0;
	my $pkg = shift || "RSGet::Common";

	no strict 'refs';
	foreach ( @_ ) {
		die "$pkg: has no sub named '$_'\n"
			unless $pkg->can( $_ );

		# export sub
		*{"$callpkg\::$_"} = \&{"$pkg\::$_"};
	}
}


=head2 my $val = irand( [MIN], MAX );

Returns an integer in [MIN, MAX) interval. MIN is zero if ommited.

=cut
sub irand($;$)
{
	my $arg = shift;
	return int rand $arg unless @_;

	return int ( $arg + rand ( (shift) - $arg ) );
}

1;

# vim: ts=4:sw=4:fdm=marker
