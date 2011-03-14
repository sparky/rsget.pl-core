package RSGet::HTTP_Connection;
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

use constant {
	# maximum post client is allowed to send to us
	MAX_POST_SIZE => 1 * 1024 * 1024,

	# first word to send to
	STATUS => 'HTTP/1.1',
};

my %codes = ( # {{{
	200 => 'OK',
	206 => 'Partial Content',
	401 => 'Authorization Required',
	404 => 'Not Found',
	416 => 'Requested Range Not Satisfiable',
	500 => 'Internal Server Error',
); # }}}

sub open # {{{
{
	my $class = shift;
	my $handle = shift;

	my $io = RSGet::IO->new( $handle );
	my $self = {
		_io => $io,
	};

	bless $self, $class;

	$self->read_start();

	return $self;
} # }}}

sub read_start # {{{
{
	my $self = shift;

	# delete all but permanent data
	delete @$self{ grep !/^_/, keys %$self };

	# register io_read
	RSGet::IO_Event->add_read( $self->{_io}, $self );
} # }}}

sub read_end # {{{
{
	my $self = shift;
	RSGet::IO_Event->remove_read( $self->{_io} );

	return $self->process();
} # }}}

sub write_start # {{{
{
	my $self = shift;

	# register io_write
	RSGet::IO_Event->add_write( $self->{_io}, $self );
} # }}}

sub write_end # {{{
{
	my $self = shift;
	RSGet::IO_Event->remove_write( $self->{_io} );

	my $h = $self->{h_in};
	if ( exists $h->{CONNECTION} and lc $h->{CONNECTION} ne 'keep-alive' ) {
		return $self->close();
	}

	return $self->read_start();
} # }}}

sub close # {{{
{
	my $self = shift;
	RSGet::IO_Event->remove( $self->{_io} );

	close $self->{_io}->handle();
	delete $self->{_io};
} # }}}

sub io_read # {{{
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
					if $len > MAX_POST_SIZE;
				$self->{post_data} = $io->read( $len );
				my $got = length $self->{post_data};
				throw 'POST data incomplete (%d of %d bytes)', $got, $len
					if $got != $len;
			} else {
				$self->{post_data} = $io->read( MAX_POST_SIZE + 1);
				throw 'POST data too large'
					if length $self->{post_data} > MAX_POST_SIZE;
			}
		}
	};

	if ( $@ ) {
		return $self->read_error( $@ );
	} else {
		return $self->read_end();
	}
} # }}}

sub read_error # {{{
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

=head2 my $headers = $self->http_headers( PREAMBLE );

Returns:

	PREAMBLE \r\n
	Header-1: value1 \r\n
	Header-2: value2 \r\n
	\r\n

=cut
sub http_headers # {{{
{
	my $self = shift;
	my $h = $self->{h_out};

	return join '',
		map { $_ . "\r\n" } (
			@_, 
			( map { 
				( join '-', map ucfirst, split /[-_ ]+/, lc $_ )
				. ': ' . $h->{ $_ }
				} sort keys %$h ),
			''
		);
} # }}}

sub method
{
	my $self = shift;
	return uc $self->{REQUEST_METHOD} eq uc shift;
}

sub handle # {{{
{
	my $self = shift;

	$self->{h_out} = {};


	require RSGet::HTTP_Handler;
	my $handler = RSGet::HTTP_Handler->get( $self->{PATH_INFO} );

	throw '404: No handler for file "%s"', $self->{PATH_INFO}
		unless $handler;

	my @args = @$handler;
	shift @args; # file match
	my $func = shift @args;

	my $data = $func->( $self, @args );

	$self->{code} ||= 200;
	throw '500: Handler returned invalid code %d', $self->{code}
		unless exists $codes{ $self->{code} };

	throw '500: $data not defined'
		unless defined $data or $self->method( 'HEAD' );

	if ( ref $data ) {
		throw '500: $data must be a SCALAR or CODE ref, it is %s', ref $data
			unless ref $data eq 'CODE';
		throw 'CODE handler must set up CONTENT_LENGTH header'
			unless exists $self->{h_out}->{CONTENT_LENGTH};
	} elsif ( defined $data ) {
		$self->{h_out}->{CONTENT_LENGTH} = length $data;
	}

	return $data;
} # }}}

sub process # {{{
{
	my $self = shift;

	my $data;
	eval {
		$data = $self->handle();
	};
	if ( $@ ) {
		%{$self->{h_out}} = ();
		$data = "Server error: $@\n";
		if ( $@ =~ /: (\d{3}):\s+(.*)/ ) {
			$self->{code} = 0 | $1;
			( $self->{code_msg} = $2 ) =~ s#[^A-Za-z0-9/\. -]+#_#sg;
		} else {
			$self->{code} = 500;
			delete $self->{code_msg};
		}
	}
	$self->{h_out}->{CONTENT_TYPE} ||= 'text/plain; charset=utf-8';
	$self->{h_out}->{CONNECTION} = 'Keep-Alive';

	if ( $self->method( 'HEAD' ) ) {
		$data = '';
	}

	my $headers = $self->http_headers(
		join ( ' ',
			$self->STATUS,
			$self->{code},
			$self->{code_msg} || $codes{ $self->{code} }
		)
	);


	my $h = $self->{_io};
	{
		local $@;
		eval {
			$h->write( $headers );
		};
		# don't care about $@
	}

	if ( ref $data ) {
		$self->{iter} = $data;
		$self->{left} = $self->{h_out}->{CONTENT_LENGTH};
		return $self->write_start();
	}

	eval {
		$h->write( $data );
	};
	if ( $@ ) {
		if ( $@ eq 'RSGet::IO: busy' ) {
			$self->{iter} = sub { throw 'DONE' };
			return $self->write_start();
		}
		return $self->close();
	} else {
		return $self->write_end();
	}
} # }}}

sub io_write # {{{
{
	my $self = shift;
	my $time = shift;

	my $h = $self->{_io};
	my $i = $self->{iter};
	eval {
		# flush write buffer
		$h->write();

		# read more
		local $_;
		while ( defined ( $_ = $i->() ) ) {
			if ( length $_ > $self->{left} ) {
				throw 'size mismatch - tried to send more than declared';
			}
			$self->{left} -= length $_;
			$h->write( $_ );
		}
	};

	return unless $@; # busy
	return if $@ eq 'RSGet::IO: busy';
	return if $@ eq 'RSGet::IO: no data';

	if ( $@ ge 'done' or $@ ge 'read: handle closed' ) {
		# no more data
		if ( $self->{left} ) {
			# size mismatch - close the handle
			warn "size mismatch - not enough data sent (remaining $self->{left})\n";
			$self->close();
			return;
		}
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


1;

# vim: ts=4:sw=4:fdm=marker
