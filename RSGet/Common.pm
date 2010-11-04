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


=head2 if ( DEBUG ) { ... }

Return true if debugging.

=cut
use constant DEBUG => 1;


=head2 my $val = irand( [MIN], MAX );

Returns an integer in [MIN, MAX) interval. MIN is zero if ommited.

=cut
sub irand($;$)
{
	my $arg = shift;
	return int rand $arg unless @_;

	return int ( $arg + rand ( (shift) - $arg ) );
}


=head2 confess( "message" );

Die babbling.

=cut
sub confess($)
{
	eval {
		require Carp;
	};
	if ( $@ ) {
		my $msg = shift;
		die "Died because: $msg\n" .
			"Moreover, Carp cannot be loaded to display full backtrace.\n";
	} else {
		goto \&Carp::confess;
	}
}


=head2 my $val = ref_check TYPE => $argument, 'Option "name"';

Make sure argument is a ref to TYPE. Die if it isn't.

	my $val = ref_check undef => $argument;

Die if argument is a ref.

=cut
sub ref_check($$;$)
{
	my $type = shift || "";
	$type = "" if $type eq "undef";
	my $var = shift;
	my $name = shift || "Argument";

	my $ref = ref $var;
	unless ( $ref eq $type ) {
		@_ = ( "$name should contain a '$type' ref, but it is '$ref'\n" );
		goto \&RSGet::Common::confess;
	}

	return $var;
}


=head2 my $val = val_check qr/PATTERN/ => $argument;

Make sure argument matches PATTERN. Die if it doesn't.

=cut
sub val_check($$;$)
{
	my $match = shift;
	my $var = shift;
	my $name = shift || "Argument";

	my $ref = ref $var;
	unless ( $ref eq "" ) {
		@_ = ( "$name should be a scalar, but it is a ref to '$ref'\n" );
		goto \&RSGet::Common::confess;
	}

	unless ( $var =~ m/^$match$/ ) {
		@_ = ( "$name '$var' does not match pattern: $match\n" );
		goto \&RSGet::Common::confess;
	}
}


1;

# vim: ts=4:sw=4:fdm=marker
