package RSGet::Comm::HTTP;
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
use base qw(RSGet::Comm::HTTP_Output);

=head1 RSGet::Comm::HTTP -- simple http server connection

This package implements client connection handling and processing.
It never blocks.

=cut

use constant {
	# first word to send to client
	STATUS => 'HTTP/1.1',
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
		local $/ = "\r\n";
		local $_;
		if ( not defined $self->{REQUEST_METHOD} ) {
			@$self{ qw(REQUEST_METHOD PATH_INFO SERVER_PROTOCOL) } =
				split /\s+/, $io->readline();

			$self->{QUERY_STRING} = $1
				if $self->{PATH_INFO} =~ s/\?(.*)//;

			my $h = $self->{h_in} ||= {};
			$h->{CONNECTION} = 'Close'
				if $self->{SERVER_PROTOCOL} ne 'HTTP/1.1';
		}
		if ( not defined $self->{h_in_done} ) {
			my $h = $self->{h_in} ||= {};
			while ( ( $_ = $io->readline() ) ne $/ ) {
				chomp;
				/^(\S+?):\s*(.*)$/
					or throw 'malformed request';
				$_ = uc $1;
				tr/-/_/;
				$h->{ $_ } = $2;
			}
			$self->{h_in_done} = 1;
		}
		if ( $self->method( 'POST' ) ) {
			$_ = $self->{CONTENT_LENGTH} = $self->{h_in}->{CONTENT_LENGTH};
			if ( defined $_ ) {
				my $len = 0 | $_;
				throw 'POST data too large (%d bytes)', $len
					if $len > $self->MAX_POST_SIZE;
				$self->{post_data} = $io->read( $len );
				my $got = length $self->{post_data};
				throw 'POST data incomplete (%d of %d bytes)', $got, $len
					if $got != $len;
			} else {
				$self->{post_data} = $io->read( $self->MAX_POST_SIZE + 1);
				throw 'POST data too large'
					if length $self->{post_data} > $self->MAX_POST_SIZE;
			}
		}
	};

	if ( $@ ) {
		return $self->read_error( $@ );
	} else {
		return $self->read_end();
	}
} # }}}


1;

# vim: ts=4:sw=4:fdm=marker
