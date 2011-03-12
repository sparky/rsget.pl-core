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

# use * {{{
use strict;
use warnings;
use IO::Select;
use Time::HiRes ();
use RSGet::Common;
use RSGet::Mux;

my $select_read = IO::Select->new();
my $select_write = IO::Select->new();
# }}}

=head1 package RSGet::IO_Event

Automatically call methods on read and write events.

=head2 RSGet::IO_Event->add( HANDLE, OBJECT, [METHOD] );

Add OBJECT with associated HANDLE to both call lists. If METHOD is not specified
io_read() will be used for reading and io_write() for writing.

=cut
sub add # {{{
{
	my ( $class, $handle, $object, $func ) = @_;
	_add( $select_read, $handle, $object, $func || 'io_read' );
	_add( $select_write, $handle, $object, $func || 'io_write' );
	return 1;
} # }}}


=head2 RSGet::IO_Event->add_read( HANDLE, OBJECT, [METHOD] );

Add OBJECT with associated HANDLE to read call list. If METHOD is not specified
io_read() will be used.

=cut
sub add_read # {{{
{
	my ( $class, $handle, $object, $func ) = @_;
	return _add( $select_read, $handle, $object, $func || 'io_read' );
} # }}}


=head2 RSGet::IO_Event->add_write( HANDLE, OBJECT, [METHOD] );

Add OBJECT with associated HANDLE to write call list. If METHOD is not specified
io_write() will be used.

=cut
sub add_write # {{{
{
	my ( $class, $handle, $object, $func ) = @_;
	return _add( $select_write, $handle, $object, $func || 'io_write' );
} # }}}


# INTERNAL, actually does the job
sub _add # {{{
{
	my $select = shift;

	my $handle = shift;
	my $object = shift;

	my $func = shift || 'io_data';

	RSGet::Common::throw "object $object cannot $func"
		unless $object->can( $func );

	$handle = $handle->handle
		if $handle->isa( 'RSGet::IO' );

	$select->add( [ $handle, $object, $func ] );

	return 1;
} # }}}


=head2 RSGet::IO_Event->remove( HANDLE );

Remove OBJECT associated with HANDLE from both call lists.

=cut
sub remove # {{{
{
	my ( $class, $handle ) = @_;
	_remove( $select_read, $handle );
	_remove( $select_write, $handle );
} # }}}

=head2 RSGet::IO_Event->remove_read( HANDLE );

Remove OBJECT associated with HANDLE from read call list.

=cut
sub remove_read # {{{
{
	my ( $class, $handle ) = @_;
	_remove( $select_read, $handle );
} # }}}

=head2 RSGet::IO_Event->remove_write( HANDLE );

Remove OBJECT associated with HANDLE from write call list.

=cut
sub remove_write # {{{
{
	my ( $class, $handle ) = @_;
	_remove( $select_write, $handle );
} # }}}

# INTERNAL, actually does the job
sub _remove # {{{
{
	my $select = shift;
	my $handle = shift;

	$handle = $handle->handle
		if $handle->isa( 'RSGet::IO' );

	$select->remove( $handle );
} # }}}


=head2 RSGet::IO_Event::_perform_read(); _perform_write();

For each HANDLE in read list ready to read call appropriate
OBJECT->METHOD( $time ). Afterwards do the same for write list.

Those functions are called automatically from Mux.

=cut

sub _perform_read # {{{
{
	my @io = $select_read->can_read( 0 );
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
} # }}}


sub _perform_write # {{{
{
	my @io = $select_write->can_write( 0 );
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
} # }}}

RSGet::Mux::add_short
	_1io_read => \&_perform_read,
	_2io_write => \&_perform_write;

1;

# vim: ts=4:sw=4:fdm=marker
