package RSGet::Comm::Exchange;
# This file is an integral part of rsget.pl downloader.
#
# 2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
use Carp;
use IO::Handle;
use IO::Socket;
use Storable qw(nfreeze thaw);
use Compress::Zlib qw(compress uncompress);

=head1 RSGet::Comm::Exchange

Few functions to exchange perl data types between multiple processes.

Unfinished. I don't even like the name.

=cut

# {{{ sub new -- create new socket handler
sub new
{
	my $class = shift;
	my $handle_in = shift or die "No handle\n";
	my $handle_out = shift;
	$handle_out = $handle_in unless $handle_out;
	$handle_in->blocking( 0 );
	$handle_in->binmode();
	$handle_out->binmode();

	my $self = {
		max_size => 64 << 10,
		@_,
		read_buf => '',
		handle_in => $handle_in,
		handle_out => $handle_out,
		use_recv => $handle_in->can( "recv" ),
		use_send => $handle_out->can( "send" ),
	};

	return bless $self, $class;
}
# }}}

# {{{ sub _socket_read (internal)
# Read $size data from the other end if there is enough data.
# Returns undef if there isn't enough. Does not block.
sub _socket_read
{
	my $self = shift;
	my $size = shift;
	my $fh = $self->{handle_in};

	if ( $size > length $self->{read_buf} ) {
		my $read_size = $size - length $self->{read_buf};
		my $msg = '';
		if ( $self->{use_recv} ) {
			warn "Receiving $read_size bytes of data";
			$fh->recv( $msg, $read_size );
		} else {
			warn "Reading $read_size bytes of data";
			$fh->read( $msg, $read_size );
		}

		$self->{read_buf} .= $msg;

		return undef
			unless length $self->{read_buf} >= $size;
	}

	my $ret = substr $self->{read_buf}, 0, $size;
	substr ( $self->{read_buf}, 0, $size ) = '';

	return $ret;
}
# }}}

# {{{ sub socket_pull -- Get one data object.
use constant intsize => length pack "N", 0;
sub socket_pull
{
	my $self = shift;

	while ( not $self->{get_size} ) {
		my $r = $self->_socket_read( intsize );

		return undef
			unless defined $r;

		$self->{get_size} = unpack "N", $r;

		croak "Message size to big\n"
			if $self->{get_size} > $self->{max_size};
	}

	my $r = $self->_socket_read( $self->{get_size} );

	return undef
		unless defined $r;

	delete $self->{get_size};

	return $r;
}
# }}}

# {{{ sub socket_push -- Send one data object.
sub socket_push
{
	my $self = shift;

	my $fh = $self->{handle_out};

	eval {
		my $len = pack "N", length $_[0];
		if ( $self->{use_send} ) {
			# must use send for sockets, because using print could kill us
			$fh->send( $len );
			$fh->send( $_[0] );
		} else {
			$fh->print( $len );
			$fh->print( $_[0] );
		}
		$fh->flush();
	};
	if ( $@ ) {
		$fh->close();
		croak "Cannot send data\n";
	}
}
# }}}

sub DESTROY # {{{
{
	my $self = shift;
	my $in = $self->{handle_in};
	my $out = $self->{handle_out};
	$in->close();
	$out->close() if $in != $out;
}
# }}}

# {{{ sub obj2data -- convert object into sendable data
sub obj2data
{
	my $self = shift;
	my $obj = shift;

	my $data = nfreeze( $obj );
	$data = compress( $data, 9 )
		if $self->{compress};

    if ( my $cipher = $self->{cipher} ) {
		my $block_size = $cipher->blocksize;
		if ( my $tail_size = ( length $data ) % $block_size ) {
			$data .= "\0" x ( $block_size - $tail_size);
		}
		# mark data as encrypted
		my $encrypted = 'c';
		for ( my $i = 0; $i < length $data; $i += $block_size ) {
			$encrypted .= $cipher->encrypt( substr $data, $i, $block_size );
		}
		return $encrypted;
    } else {
		return $data;
	}
}
# }}}

# {{{ sub data2obj -- extract object from received data
sub data2obj
{
	my $self = shift;
	my $data = shift;
	
	if ( "c" eq substr $data, 0, 1 ) {
		my $encrypted_data = substr $data, 1;
		my $cipher = $self->{cipher}
			or croak "Data encrypted but cipher not specified.";
		my $block_size = $cipher->blocksize;
		$data = '';
		for ( my $i = 0; $i < length $encrypted_data; $i += $block_size ) {
			$data .= $cipher->decrypt( substr $encrypted_data, $i, $block_size );
		}
	}

	if ( "x" eq substr $data, 0, 1 ) {
		$data = uncompress( $data );
	}

	return thaw( $data );
}
# }}}

1;

# vim: ts=4:sw=4:fdm=marker
