package RSGet::IO;
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
use IO::Handle ();

=head1 package RSGet::IO

IO wrapper. Allows exact reads without blocking.

=cut

use constant {
	IO_HANDLE => 0,
	IO_VECTOR => 1,
	IO_BUFFER => 2,
};

=head2 my $input = RSGet::IO->new( HANDLE );

Mark HANDLE as non-blocking and return a wrapper.

=cut
sub new
{
	my $class = shift;
	my $handle = shift;

	# IO::Handle ?
	$handle->blocking( 0 );

	my $self = [
		$handle,	# IO_HANDLE
		chr( 0 ),		# IO_VECTOR
		"",			# IO_BUFFER
	];

	my $fn = fileno $handle;
	vec( $self->[ IO_VECTOR ], fileno( $handle ), 1 ) = 1;

	bless $self, $class;
	return $self;
}

sub _read_end
{
	my $self = shift;
	my $active = 1;

	my $r = $self->[ IO_VECTOR ];
	my $nfound = select ( $r, undef, undef, 0 );

	if ( $nfound > 0 ) {
		my $nread = sysread $self->[ IO_HANDLE ], my $buf, 1;
		if ( $nread ) {
			$self->[ IO_BUFFER ] .= $buf;
		} else {
			$active = 0;
		}
	}

	if ( $active ) {
		return undef;
	} elsif ( length $self->[ IO_BUFFER ] ) {
		my $ret = $self->[ IO_BUFFER ];
		$self->[ IO_BUFFER ] = '';
		return $ret;
	} else {
		die "handle closed\n";
	}
}

=head2 my $data = $input->read( BYTES );

Read exactly BYTES from input and return it.

If there aren't enough bytes and handle is still open - read will return undef.
If handle was closed return remaining data. Subsequent reads will die with
"handle closed" error.

=cut
sub read
{
	my $self = shift;
	my $size = shift;

	my $missing = $size - length $self->[ IO_BUFFER ];
	if ( $missing > 0 ) {
		my $nread = sysread $self->[ IO_HANDLE ], my ( $buf ), $missing;

		return _read_end( $self )
			unless $nread;

		$self->[ IO_BUFFER ] .= $buf;

		return _read_end( $self )
			unless $missing <= $nread;
	}

	return substr $self->[ IO_BUFFER ], 0, $size, '';
}

=head2 my $line = $input->readline();

Read exactly one line from input and return it.

If there aren't enough data and handle is still open - readline will return
undef. If handle was closed return remaining data. Subsequent reads will die
with "handle closed" error.

=cut
sub readline
{
	my $self = shift;

	my $idx;
	until ( ( $idx = index $self->[ IO_BUFFER ], "\n" ) >= 0 ) {
		my $nread = sysread $self->[ IO_HANDLE ], my $buf, 32;

		return _read_end( $self )
			unless $nread;

		$self->[ IO_BUFFER ] .= $buf;
	}

	return substr $self->[ IO_BUFFER ], 0, $idx + 1, '';
}

=head2 my $handle = $input->handle();

Return file handle.

=cut
sub handle
{
	my $self = shift;
	return $self->[ IO_HANDLE ];
}


1;

# vim: ts=4:sw=4
