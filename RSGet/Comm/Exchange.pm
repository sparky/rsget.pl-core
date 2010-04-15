package RSGet::Comm::Exchange;
# This file is an integral part of rsget.pl downloader.
#
# 2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
use Carp;
use IO::Socket;

# {{{ sub new -- create new socket handler
sub new
{
	my $class = shift;
	my $socket = shift;
	my $self = {
		read_buf => '',
		@_
	};

	# TODO: make sure $socket is of type IO::Socket.*
	$socket->blocking( 0 );

	$self->{socket} = $socket;

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
	my $fh = $self->{socket};

	if ( $size > length $self->{read_buf} ) {
		my $read_size = $size - length $self->{read_buf};
		my $msg = '';
		$fh->recv( $msg, $read_size );

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
	# my $data = shift; -- don't copy, for speed

	my $fh = $self->{socket};

	eval {
		$fh->send( pack ("N", length $_[0]) . $_[0] );
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
	$self->{socket}->close();
}
# }}}

1;

# vim: ts=4:sw=4:fdm=marker
