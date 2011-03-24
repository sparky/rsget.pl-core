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

# use * {{{
use strict;
use warnings;
use IO (); # HANDLE->blocking( 0 )
use RSGet::Common qw(throw);
use constant {
	IO_HANDLEIN => 0,
	IO_VECTORIN => 1,
	IO_BUFFERIN => 2,
	IO_HANDLEOUT => 3,
	IO_VECTOROUT => 4,
	IO_BUFFEROUT => 5,
};
# }}}

=head1 package RSGet::IO

IO wrapper. Allows exact reads without blocking.

=head2 my $io = RSGet::IO->new( HANDLEIO, [HANDLEOUT] );

Mark HANDLE as non-blocking and return a wrapper.

=cut
sub new($$;$) # {{{
{
	my $class = shift;
	my $handlein = shift;
	my $handleout = @_ ? shift : $handlein;

	$handlein->blocking( 0 );
	$handleout->blocking( 0 );

	my $self = [
		$handlein,	# IO_HANDLEIN
		'',			# IO_VECTORIN
		'',			# IO_BUFFERIN
		$handleout,	# IO_HANDLEOUT
		'',			# IO_VECTOROUT
		'',			# IO_BUFFEROUT
	];

	vec( $self->[ IO_VECTORIN ], (fileno $handlein), 1 ) = 1;
	vec( $self->[ IO_VECTOROUT ], (fileno $handleout), 1 ) = 1;

	bless $self, $class;
	return $self;
} # }}}


=head2 my $handle = $io->handle();

Return file handle.

=cut
sub handle($) # {{{
{
	my $self = shift;
	if ( wantarray ) {
		return ( $self->[ IO_HANDLEIN ], $self->[ IO_HANDLEOUT ] );
	} else {
		return $self->[ IO_HANDLEIN ];
	}
} # }}}


=head2 my $data = $input->read( BYTES );

Read exactly BYTES from input and return it.

If there aren't enough bytes and handle is still open - read will die with
"RSGet::IO: no data" error. If handle was closed it returns remaining data.
Subsequent reads will die with "RSGet::IO: handle closed" error.

=cut
sub read($$) # {{{
{
	my $self = shift;
	my $size = shift;

	my $missing = $size - length $self->[ IO_BUFFERIN ];
	if ( $missing > 0 ) {
		my $nread = sysread $self->[ IO_HANDLEIN ], my ( $buf ), $missing;

		return _read_end( $self )
			unless $nread;

		$self->[ IO_BUFFERIN ] .= $buf;

		return _read_end( $self )
			unless $missing <= $nread;
	}

	return substr $self->[ IO_BUFFERIN ], 0, $size, '';
} # }}}


=head2 my $line = $input->readline();

Read exactly one line from input and return it.

If there aren't enough data and handle is still open - readline will die with
"RSGet::IO: no data" error. If handle was closed it returns remaining line.
Subsequent reads will die with "RSGet::IO: handle closed" error.

=cut
sub readline($) # {{{
{
	my $self = shift;

	my $idx;
	until ( ( $idx = index $self->[ IO_BUFFERIN ], $/ ) >= 0 ) {
		my $nread = sysread $self->[ IO_HANDLEIN ], my $buf, 32;

		return _read_end( $self )
			unless $nread;

		$self->[ IO_BUFFERIN ] .= $buf;
	}

	return substr $self->[ IO_BUFFERIN ], 0, ($idx + length $/), '';
} # }}}


sub _read_end($) # {{{
{
	my $self = shift;
	my $active = 1;

	my $r = $self->[ IO_VECTORIN ];
	my $nfound = select $r, undef, undef, 0;

	if ( $nfound > 0 ) {
		my $nread = sysread $self->[ IO_HANDLEIN ], my $buf, 1;
		if ( $nread ) {
			$self->[ IO_BUFFERIN ] .= $buf;
		} else {
			$active = 0;
		}
	}

	if ( $active ) {
		throw 'no data';
	} elsif ( length $self->[ IO_BUFFERIN ] ) {
		my $ret = $self->[ IO_BUFFERIN ];
		$self->[ IO_BUFFERIN ] = '';
		return $ret;
	} else {
		throw 'read: handle closed';
	}
} # }}}

=head2 $output->write( [DATA] );

Try to write buffered data and DATA to output.

Returns true on success. If the DATA could not be written completely, write()
stores remaining data and dies with "RSGET::IO: busy" error. If handle is
closed write() will die with "RSGet::IO: handle closed" error.

=cut
sub write($@) # {{{
{
	my $self = shift;
	while ( @_ ) {
		$self->[ IO_BUFFEROUT ] .= shift;
	}

	return 0 unless length $self->[ IO_BUFFEROUT ];

	my $w = $self->[ IO_VECTOROUT ];
	my $nfound = select undef, $w, undef, 0;

	throw 'busy'
		unless $nfound;

	my $nwritten;
	{
		# disable "syswrite() on closed filehandle" warning
		no warnings 'closed';
		local $SIG{PIPE} = 'IGNORE';
		$nwritten = syswrite $self->[ IO_HANDLEOUT ], $self->[ IO_BUFFEROUT ];
	}

	throw 'write: handle closed'
		unless defined $nwritten;

	if ( $nwritten == length $self->[ IO_BUFFEROUT ] ) {
		$self->[ IO_BUFFEROUT ] = '';
		return $nwritten;
	} else {
		substr ( $self->[ IO_BUFFEROUT ], 0, $nwritten ) = '';
		throw 'busy';
	}
} # }}}


sub DESTROY($) # {{{
{
	my $self = shift;
	eval {
		$self->write();
	};
	if ( $@ and $@ eq 'RSGet::IO: busy' ) {
		warn "RSGet::IO: Could not flush buffer on DESTROY, some data will be lost\n";
	}
} # }}}

1;

# vim: ts=4:sw=4:fdm=marker
