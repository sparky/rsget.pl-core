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

use constant {
	IO_HANDLE => 0,
	IO_VECTOR => 1,
	IO_BUFFER => 2,
};

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

	my $r = my $w = my $e = $self->[ IO_VECTOR ];
	my $nfound = select ( $r, $w, $e, 0 );

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

1;

# vim: ts=4:sw=4
