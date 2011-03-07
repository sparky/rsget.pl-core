package RSGet::IO_Event;
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

=head1 package RSGet::IO_Event

Automatically call methods on new data.

=cut

use strict;
use warnings;
use IO::Select;
use Time::HiRes ();

my $select = IO::Select->new();

=head2 RSGet::IO_Event->add( HANDLE, OBJECT, [METHOD] );

Add OBJECT with associated HANDLE to call list. If METHOD is not specified
io_data() will be used.

=cut
sub add
{
	my $class = shift;

	my $handle = shift;
	my $object = shift;

	my $func = shift || "io_data";

	die "object $object cannot $func\n"
		unless $object->can( $func );

	$handle = $handle->handle
		if $handle->isa( "RSGet::IO" );

	$select->add( [ $handle, $object, $func ] );

	return 1;
}

=head2 RSGet::IO_Event->remove( HANDLE );

Remove OBJECT associated with HANDLE from call list.

=cut
sub remove
{
	my $class = shift;
	my $handle = shift;

	$handle = $handle->handle
		if $handle->isa( "RSGet::IO" );

	$select->remove( $handle );
}

=head2 RSGet::IO_Event::_perform();

For each HANDLE ready to read call appropriate OBJECT->METHOD( $time ).

=cut
sub _perform
{
	my @io = $select->can_read( 0 );
	return 0 unless @io;

	my $time = Time::HiRes::time();
	foreach my $io ( @io ) {
		my ( $h, $obj, $func ) = @$io;
		eval {
			$obj->$func( $time );
		};
		warn $@ if $@;
	}

	return scalar @io;
}

1;

# vim: ts=4:sw=4
