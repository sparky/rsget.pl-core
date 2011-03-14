package RSGet::SCGI_Connection;
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
use RSGet::HTTP_Connection;

our @ISA;
@ISA = qw(RSGet::HTTP_Connection);


=head1 RSGet::SCGI_Connection -- simple scgi server connection

This package implements client connection handling and processing.
The connection never blocks.

RSGet::SCGI_Connection inherits most of its methods from
RSGet::HTTP_Connection.

=cut
use constant {
	# first word to send to client
	STATUS => 'Status:',
};


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
		if ( not defined $self->{head_length} ) {
			local $/ = ":";
			$_ = $io->readline();
			chomp;
			$self->{head_length} = 0 | $_;
		}
		if ( not defined $self->{h_in} ) {
			$_ = $io->read( $self->{head_length} + 1);
			throw 'malformed request'
				unless substr( $_, -1, 1, '' ) eq ',';
			my %head = split /\0/, $_;
			my %headers;
			while ( my ( $key, $value ) = each %head ) {
				if ( $key =~ /^HTTP_(.*)$/ ) {
					$headers{ $1 } = $value;
				} else {
					$self->{ $key } = $value;
				}
			}

			$self->{h_in} = \%headers;
		}
		if ( not defined $self->{post_data} ) {
			my $len = $self->{CONTENT_LENGTH};
			throw 'POST data too large'
				if $len > $self->MAX_POST_SIZE;
			$self->{post_data} = $io->read( $len );
			throw 'POST data incomplete'
				if length $self->{post_data} != $len;
		}
	};
	if ( $@ ) {
		return $self->read_error( $@ );
	} else {
		return $self->read_end();
	}
} # }}}


=head2 $self->write_end();

End data writing. Called either from process (if it was able to send all the
data at once) or from io_write (when it's done writing).

Will close the connection (SCGI does not allow persistent connections).

=cut
sub write_end($) # {{{
{
	my $self = shift;
	return $self->close();
} # }}}

1;

# vim: ts=4:sw=4:fdm=marker
