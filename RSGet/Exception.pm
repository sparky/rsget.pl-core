package RSGet::Exception;
# This file is an integral part of rsget.pl downloader.
#
# Copyright (C) 2011	Przemysław Iskra <sparky@pld-linux.org>
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

=head1 package RSGet::Exception

Handle and compare exceptions.

=head2 die RSGet::Exception->new( MSG, [PARENT] );

Create an exception object. PARENT can be set to 1 or more if a parent
subroutine generated the exception.

=cut
sub new
{
	my $class = shift;
	my $msg = shift;
	my $parent = shift || 0;

	my $self = [ $msg, (caller $parent) ];
	bless $self, $class;
	return $self;
}


=head2 $@->pkg( PKG ); ($@ > PKG)

Return true if exception is from package PKG.

=cut
sub pkg
{
	$"=", ";
	print "PKG: @_\n";
	return shift->[ 1 ] eq shift;
}
use overload '>' => \&pkg;
use overload '<' => \&pkg;


=head2 $@->msg( MSG ); ($@ == MSG)

Return true if exception message is MSG.

=cut
sub msg
{
	return shift->[ 0 ] eq shift;
}
use overload '==' => \&msg;


=head2 $@->is( PKG, MSG );

Return true if exception is from package PKG.

=cut
sub is
{
	my $self = shift;
	return
		$self->[ 1 ] eq shift
			and
		$self->[ 0 ] eq shift;
}


=head2 print "$@"; print $@->str()

Return as string.

=cut
sub str
{
	my $self = shift;
	return $self->[ 1 ] . ": " . $self->[ 0 ];
}
use overload '""' => \&str;


=head2 $@->eq( MSG ); ($@ eq MSG);

Return true if stringified Exception equals MSG.

=cut
sub eq
{
	my $self = shift;
	return $self->[ 1 ] . ": " . $self->[ 0 ] eq shift;
}
use overload 'eq' => \&eq;


1;

# vim: ts=4:sw=4
