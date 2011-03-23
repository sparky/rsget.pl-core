package RSGet::Comm::PerlRPC;
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
use RSGet::Common qw(throw);
use RSGet::IO;
use RSGet::IO_Event;
use Storable ();
use Compress::Raw::Zlib qw(Z_OK Z_STREAM_END);


=head1 RSGet::Comm::PerlRPC -- simple RPC server with perl-encoded data

This package implements client connection handling and processing.
It never blocks.

=cut

use constant {
	# maximum post client is allowed to send to us
	MAX_SIZE => 64 * 1024,

	SIZE_LENGTH => (length pack 'N', 0),
};

=head2 my $conn = RSGet::Comm::PerlRPC->open( HANDLE, OPTIONS )

Open new connection associated with HANDLE.

=cut
sub open($$) # {{{
{
	my $class = shift;
	my $handle = shift;
	my %opts = @_;

	my $self = {};
	@$self{ map "_$_", keys %opts } = values %opts;

	$self->{_compress_min} ||= 512;
	$self->{_io} = RSGet::IO->new( $handle );

	bless $self, $class;

	$self->read_start();

	return $self;
} # }}}


=head2 $self->read_start()

Start reading data.

=cut
sub read_start($) # {{{
{
	my $self = shift;

	# delete all but permanent data
	delete @$self{ grep !/^_/, keys %$self };

	# register io_read
	RSGet::IO_Event->add_read( $self->{_io}, $self );
} # }}}


=head2 $self->io_read(),

Read data from client and process/decode it. Will be called from IO_Event
every time there is some data to read.

=cut
sub io_read($;$) # {{{
{
	my $self = shift;
	my $time = shift;

	my $io = $self->{_io};

	eval {
		local $_;
		if ( not defined $self->{SIZE} ) {
			$_ = $io->read( $self->SIZE_LENGTH );
			throw 'no more data'
				unless length $_ == $self->SIZE_LENGTH;

			$self->{SIZE} = unpack 'N', $_;
		}

		throw 'data chunk too large'
			if $self->{SIZE} > $self->MAX_SIZE;

		$self->{DATA} = \( $io->read( $self->{SIZE} ) );
	};

	if ( $@ ) {
		return $self->read_error( $@ );
	} else {
		return $self->read_end();
	}
} # }}}


=head2 $self->read_error( $@ )

Handle read error. Closes connection on unrecoverable errors

=cut
sub read_error($$) # {{{
{
	my $self = shift;
	my $err = shift;

	if ( $err eq 'RSGet::IO: no data' ) {
		# do nothing, wait for more data
		return;
	}

	$self->close();
	return if $err eq 'RSGet::IO: read: handle closed';

	die $err;
} # }}}


=head2 $self->read_end();

Finish data reading. Start data processing.

=cut
sub read_end($) # {{{
{
	my $self = shift;
	RSGet::IO_Event->remove_read( $self->{_io} );

	return $self->process();
} # }}}



=head2 my $data = $self->handle();

Handle request. Dies if there are any problems.

=cut
sub handle($) # {{{
{
	my $self = shift;

	my $obj = $self->data2obj( $self->{DATA} );
	throw 'data sent should be a HASHref, not "%s"', ref $obj
		unless 'HASH' eq ref $obj;
	throw '"func" not specified'
		unless exists $obj->{func};

	my $func = $obj->{func};
	my $args = $obj->{args} || [];

	require RSGet::Comm::RPC;
	return RSGet::Comm::RPC->$func( @$args );
} # }}}


=head2 $self->process();

Process request. Calls handle() and writes the response to client, if
possible, otherwise writes the error code.

=cut
sub process($) # {{{
{
	my $self = shift;

	my $obj;
	eval {
		$obj = $self->handle();
	};
	if ( $@ ) {
		$obj = {
			fatal => "$@"
		};
	}

	my $dataref = $self->obj2data( $obj );

	my $h = $self->{_io};
	eval {
		$h->write( pack 'N', length $$dataref );
	};
	eval {
		$h->write( $$dataref );
	};
	if ( $@ ) {
		if ( $@ eq 'RSGet::IO: busy' ) {
			return $self->write_start();
		}
		return $self->close();
	} else {
		return $self->write_end();
	}
} # }}}


=head2 $self->write_start();

Start writing content to client. Called if request handles returned an iterator
or process couldn't send all the data at once.

=cut
sub write_start($) # {{{
{
	my $self = shift;

	# register io_write
	RSGet::IO_Event->add_write( $self->{_io}, $self );
} # }}}


=head2 $self->io_write();

Write chunk of data to client. Will be called from IO_Event every time
socket is able to accept new data.

=cut
sub io_write($;$) # {{{
{
	my $self = shift;
	my $time = shift;

	eval {
		# flush write buffer
		$self->{_io}->write();
	};

	return if $@ eq 'RSGet::IO: busy';

	unless ( $@ ) {
		# no more data
		$self->write_end();
		return;
	}

	# there was some problem
	$self->close();
	if ( $@ eq 'RSGet::IO: write: handle closed' ) {
		# warn "$@\n";
		return;
	} else {
		die $@;
	}
} # }}}


=head2 $self->write_end();

End data writing. Called either from process (if it was able to send all the
data at once) or from io_write (when it's done writing).

Will close the connection if requested, otherwise will prepare for receiving
more data.

=cut
sub write_end($) # {{{
{
	my $self = shift;
	RSGet::IO_Event->remove_write( $self->{_io} );

	return $self->read_start();
} # }}}


=head2 $self->close();

Close the connection and remove event handlers.

=cut
sub close($) # {{{
{
	my $self = shift;
	RSGet::IO_Event->remove( $self->{_io} );

	close $self->{_io}->handle();
	delete $self->{_io};
} # }}}


=head2 my $obj = $s->data2obj( DATAREF )

Deserialize data.

=cut
sub data2obj # {{{
{
	my $self = shift;
	my $dataref = ref $_[0] ? shift : \$_[0];

	if ( 'c' eq substr $$dataref, 0, 1 ) {
		my $cipher = $self->{_cipher}
			or throw 'data encrypted but cipher not specified';
		my $block_size = $cipher->blocksize;
		my $data = '';
		for ( my $i = 1; $i < length $$dataref; $i += $block_size ) {
			$data .= $cipher->decrypt( substr $$dataref, $i, $block_size );
		}
		$dataref = \$data;
	} else {
		if ( $self->{_cipher} ) {
			throw 'received not-encrypted data';
		}
	}

	if ( "x" eq substr $$dataref, 0, 1 ) {
		my $uncmp = Compress::Raw::Zlib::Inflate->new( -ConsumeInput => 0 );
		my $data;
		my $err = $uncmp->inflate( $dataref, $data );
		throw 'bad compressed data'
			unless $err == Z_STREAM_END;

		$dataref = \$data;
	}

	return Storable::thaw( $$dataref );
}
# }}}


=head2 my $data = $s->obj2data( OBJ )

Serialize one object.

=cut
sub obj2data # {{{
{
	my $self = shift;
	my $obj = shift;

	my $dataref = \Storable::nfreeze( $obj );
	if ( $self->{_compress} and length $$dataref > $self->{_compress_min} ) {
		my $out = '';
		my $cmp = Compress::Raw::Zlib::Deflate->new( -AppendOutput => 1 );
		throw 'cannot compress data'
			unless $cmp->deflate( $dataref, $out ) == Z_OK;
		throw 'cannot compress data'
			unless $cmp->flush( $out ) == Z_OK;
		$dataref = \$out;
	}

    if ( my $cipher = $self->{_cipher} ) {
		my $block_size = $cipher->blocksize;
		if ( my $tail_size = ( length $$dataref ) % $block_size ) {
			$$dataref .= "\0" x ( $block_size - $tail_size);
		}
		# mark data as encrypted
		my $encrypted = 'c';
		for ( my $i = 0; $i < length $$dataref; $i += $block_size ) {
			$encrypted .= $cipher->encrypt( substr $$dataref, $i, $block_size );
		}
		$dataref = \$encrypted;
	}

	return $dataref;
}
# }}}


1;

# vim: ts=4:sw=4:fdm=marker
