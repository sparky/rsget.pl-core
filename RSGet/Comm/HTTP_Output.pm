package RSGet::Comm::HTTP_Output;
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
use RSGet::IO_Event qw(IO_READ IO_WRITE IO_ANY);

=head1 RSGet::Comm::HTTP_Output -- base for http output

This package implements client connection handling and processing.
It never blocks.

=cut

use constant {
	# maximum post client is allowed to send to us
	MAX_POST_SIZE => 1 * 1024 * 1024,

	DNAME => [qw(Sun Mon Tue Wed Thu Fri Sat)],
	MNAME => [qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)],
};

# list of allowed return codes, with default message
my %codes = ( # {{{
	200 => 'OK',
	206 => 'Partial Content',
	401 => 'Authorization Required',
	404 => 'Not Found',
	416 => 'Requested Range Not Satisfiable',
	500 => 'Internal Server Error',
); # }}}

=head2 my $conn = RSGet::Comm::SOMETHING->open( HANDLE )

Open new connection associated with HANDLE.

=cut
sub open($$) # {{{
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


=head2 $self->read_start()

Start reading data.

=cut
sub read_start($) # {{{
{
	my $self = shift;

	# delete all but permanent data
	delete @$self{ grep !/^_/, keys %$self };

	# register io_read
	RSGet::IO_Event->add( IO_READ, $self->{_io}, $self, 'io_read' );
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
	RSGet::IO_Event->remove( IO_ANY, $self->{_io} );

	return $self->process();
} # }}}


=head2 if ( $self->method( TYPE ) ) { }

Return true if request method is TYPE.

=cut
sub method($$) # {{{
{
	my $self = shift;
	return uc $self->{REQUEST_METHOD} eq uc shift;
} # }}}


=head2 my $date = $self->http_time( [TIME] )

Format time as string suitable for http headers.

=cut
sub http_time($;$) # {{{
{
	my $self = shift;
	my @t = gmtime( shift || time );
	return sprintf '%s, %02d %s %04d %02d:%02d:%02d GMT',
		DNAME->[ $t[6] ], $t[3], MNAME->[ $t[4] ], 1900+$t[5],
		$t[2], $t[1], $t[0];
} # }}}

=head2 my $headers = $self->http_headers( PREAMBLE );

Format HTTP output headers. PREAMBLE is the first line to be sent.

=cut
sub http_headers($@) # {{{
{
	my $self = shift;
	my $h = $self->{h_out};

	return join "\r\n",
			@_, 
			( map { 
				( join '-', map ucfirst, split /[-_ ]+/, lc $_ )
				. ': ' . $h->{ $_ }
				} sort keys %$h ),
			'', '';
} # }}}


=head2 my $data = $self->handle();

Handle request. Dies if there are any problems.

=cut
sub handle($) # {{{
{
	my $self = shift;

	$self->{h_out} = {};


	require RSGet::Comm::Handler;
	my $handler = RSGet::Comm::Handler->get( $self->{PATH_INFO} );

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


=head2 $self->process();

Process request. Calls handle() and writes the response to client, if
possible, otherwise writes the error code.

=cut
sub process($) # {{{
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
	$self->{h_out}->{DATE} ||= $self->http_time();
	$self->{h_out}->{SERVER} = 'rsget.pl built-in server';
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


=head2 $self->write_start();

Start writing content to client. Called if request handles returned an iterator
or process couldn't send all the data at once.

=cut
sub write_start($) # {{{
{
	my $self = shift;

	# register io_write
	RSGet::IO_Event->add( IO_WRITE, $self->{_io}, $self, 'io_write' );
} # }}}


=head2 $self->io_write();

Write chunk of data to client. Will be called from IO_Event every time
socket is able to accept new data.

=cut
sub io_write($;$) # {{{
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


=head2 $self->write_end();

End data writing. Called either from process (if it was able to send all the
data at once) or from io_write (when it's done writing).

Will close the connection if requested, otherwise will prepare for receiving
more data.

=cut
sub write_end($) # {{{
{
	my $self = shift;
	RSGet::IO_Event->remove( IO_ANY, $self->{_io} );

	my $h = $self->{h_in};
	if ( exists $h->{CONNECTION} and lc $h->{CONNECTION} ne 'keep-alive' ) {
		return $self->close();
	}

	return $self->read_start();
} # }}}


=head2 $self->close();

Close the connection and remove event handlers.

=cut
sub close($) # {{{
{
	my $self = shift;
	RSGet::IO_Event->remove( IO_ANY, $self->{_io} );

	close $self->{_io}->handle();
	delete $self->{_io};
} # }}}


1;

# vim: ts=4:sw=4:fdm=marker
