package RSGet::Comm::PerlData;
# This file is an integral part of rsget.pl downloader.
#
# 2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
use Carp;
use Storable qw(nfreeze thaw);
use Compress::Zlib qw(compress uncompress);

=head1 RSGet::Comm::PerlData

Few functions to exchange perl data types between multiple processes.

It should be used as base for server, clients and communicating with our
own forks.

=cut

use constant intsize => length pack "N", 0;

=head2 my $s = new RSGet::Comm::PerlData

Create data serialization and deserialization object.

=cut
sub new # {{{
{
	my $class = shift;

	my $self = {
		max_size => 64 << 10,
		@_,
		read_buf => '',
		get_size => undef,
	};

	return bless $self, $class;
}
# }}}

# Read $size data from buffer if there is enough data.
# Returns undef if there isn't enough.
sub _shift_data # {{{
{
	my $self = shift;
	my $size = shift;

	return undef if $size > length $self->{read_buf};

	my $ret = substr $self->{read_buf}, 0, $size;
	substr ( $self->{read_buf}, 0, $size ) = '';

	return \$ret;
}
# }}}

=head2 my $obj = $s->data2obj( [DATA] )

Add new data to buffer. Retrieve object if enough data exists in the
buffer for reconstruction.

=cut
sub data2obj # {{{
{
	my $self = shift;
	if ( defined $_[0] ) {
		$self->{read_buf} .= shift;
	}

	while ( not $self->{get_size} ) {
		my $r = _shift_data( $self, intsize );

		return undef
			unless defined $r;

		$self->{get_size} = unpack "N", $$r;

		die "RSGet::Comm::PerlData::obj_get: Message size to big " .
			"($self->{get_size} > $self->{max_size})\n"
				if $self->{get_size} > $self->{max_size};
	}

	my $dataref = _shift_data( $self, $self->{get_size} );

	return undef
		unless defined $dataref;

	undef $self->{get_size};

	return _data2obj( $self, $dataref );
}
# }}}

# deserialize data
sub _data2obj # {{{
{
	my $self = shift;
	my $data = shift;
	
	if ( "c" eq substr $data, 0, 1 ) {
		my $encrypted_data = substr $data, 1;
		my $cipher = $self->{cipher}
			or die "Data encrypted but cipher not specified.";
		my $block_size = $cipher->blocksize;
		$data = '';
		for ( my $i = 0; $i < length $encrypted_data; $i += $block_size ) {
			$data .= $cipher->decrypt( substr $encrypted_data, $i, $block_size );
		}
	} else {
		if ( $self->{cipher} ) {
			die "Received not-encoded data\n";
		}
	}

	if ( "x" eq substr $data, 0, 1 ) {
		$data = uncompress( $data );
	}

	return thaw( $data );
}
# }}}

=head2 my $data = $s->obj2data( OBJ )

Serialize one object.

=cut
sub obj2data # {{{
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
		$data = $encrypted;
	}

	my $len = pack "N", length $data;

	return $len . $data;
}
# }}}

1;

# vim: ts=4:sw=4:fdm=marker
