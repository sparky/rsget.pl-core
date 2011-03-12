package RSGet::HTTP_Client;
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
	MAX_POST_SIZE => 1 * 1024 * 1024, # 1 MB
};

my %codes = (
	200 => "OK",
	206 => "Partial Content",
	401 => "Authorization Required",
	404 => "Not Found",
	416 => "Requested Range Not Satisfiable",
	500 => "Internal Server Error",
);

sub create
{
	my $class = shift;
	my $handle = shift;

	my $io = RSGet::IO->new( $handle );
	my $self = {
		_io => $io,
	};

	bless $self, $class;

	$self->state( "read" );

	return $self;
}

sub state
{
	my $self = shift;
	my $write = shift eq "write";

	my $h = $self->{_io}->handle();
	RSGet::IO_Event->remove( $h );
	if ( $write ) {
		RSGet::IO_Event->add_write( $h, $self );
	} else {
		foreach ( keys %$self ) {
			next if /^_/;
			delete $self->{$_};
		}
		RSGet::IO_Event->add_read( $h, $self );
	}
}

sub _lc_h
{
	local $_ = lc shift;
	tr/-/_/;
	return $_;
}

sub _ucfirst_h
{
	return join "-", map ucfirst, split /[-_ ]+/, lc shift;
}

sub io_read
{
	my $self = shift;
	my $time = shift;

	my $io = $self->{_io};

	eval {
		local $/ = "\r\n";
		local $_;
		if ( not defined $self->{method} ) {
			my @request = split /\s+/, $io->readline();

			$self->{method} = uc shift @request;
			$self->{file} = shift @request;
		}
		if ( not defined $self->{h_in_done} ) {
			my $h = $self->{h_in} ||= {};
			while ( ( $_ = $io->readline() ) ne $/ ) {
				chomp;
				/^(\S+?):\s*(.*)$/
					or throw "malformed request";
				$h->{ _lc_h( $1 ) } = $2;
			}
			$self->{h_in_done} = 1;
		}
		if ( $self->{method} eq "POST" ) {
			$_ = $self->{h_in}->{content_length};
			if ( defined $_ and /(\d+)/ ) {
				my $len = 0 | $1;
				throw "POST data too large"
					if $len > MAX_POST_SIZE;
				$self->{post_data} = $io->read( $len );
				throw "POST data incomplete"
					if length $self->{post_data} != $len;
			} else {
				$self->{post_data} = $io->read( MAX_POST_SIZE + 1);
				throw "POST data too large"
					if length $self->{post_data} > MAX_POST_SIZE;
			}
		}
	};
	if ( $@ ) {
		if ( $@ eq "RSGet::IO: no data" ) {
			# do nothing, wait for more data
			return;
		} else {
			if ( $@ eq "RSGet::IO: read: handle closed" ) {
				$self->process( $time )
					if $self->{h_in_done};
				return;
			} else {
				$self->delete();
				die $@;
			}
		}
	} else {
		$self->process( $time );
	}
}

sub _post2hash
{
	my $self = shift;

	my %post;
	if ( $self->{method} eq "POST" ) {
		%post =
			grep { tr/+/ /; s/%(..)/chr hex $1/eg; 1 }
			map { split /=/, $_, 2 }
			split /&/, $self->{post_data};
	} elsif ( $self->{file} =~ s/\?(.*)// ) {
		%post =
			grep { s/%(..)/chr hex $1/eg; 1 }
			map { split /=/, $_, 2 }
			split /[;&]+/, $1;
	}

	return \%post;
}

sub process
{
	my $self = shift;

	$self->{post} = _post2hash( $self );
	$self->{code} = 200;
	$self->{h_out} = {
		content_type => "text/xml; charset=utf-8",
	};

	my $data;

	require RSGet::HTTP_Handler;
	my $handler = RSGet::HTTP_Handler->get( $self->{file} );

	if ( $handler ) {
		my @args = @$handler;
		shift @args; # file match
		my $func = shift @args;
		eval {
			$data = $func->( $self, @args );
		};
		if ( $@ ) {
			$self->{h_out} = {
				content_type => "text/plain; charset=utf-8",
			};
			if ( $@ =~ /^RSGet::HTTP_Handler: (\d{3}):\s*(.*)/ ) {
				$self->{code} = $1;
				( $self->{code_msg} = $2 ) =~ s/[^A-Za-z0-9 ]+//;
				$data = "Server error: $@\n";
			} else {
				$self->{code} = 500;
				$data = "Server error: $@\n";
			}
		}
	} else {
		$self->{code} = 404;
		$data = "No handler for file '$self->{file}'\n";
	}

	$self->{h_out}->{connection} = "Keep-Alive";

	$self->{code} = 500 if not exists $codes{ $self->{code} };
	unless ( defined $data ) {
		$self->{h_out} = {
			content_type => "text/plain; charset=utf-8",
		};
		$data = $codes{ $self->{code} } . "\n"
	}
	if ( ref $data ) {
		throw '$data must be a SCALAR or CODE ref, it is %s', ref $data
			unless ref $data eq 'CODE';
		throw 'CODE handler must set up content_length header'
			unless exists $self->{h_out}->{content_length};
		$self->{left} = $self->{h_out}->{content_length};
	} else {
		$self->{h_out}->{content_length} = length $data;
	}

	$self->{code_msg} ||= $codes{ $self->{code} };
	my $headers = "HTTP/1.1 $self->{code} $self->{code_msg}\r\n";
	foreach my $hdr ( sort keys %{ $self->{h_out} } ) {
		$headers .= _ucfirst_h( $hdr ) . ": " . $self->{h_out}->{ $hdr } . "\r\n";
	}
	$headers .= "\r\n";


	my $h = $self->{_io};
	eval {
		$h->write( $headers );
	};
	if ( ref $data ) {
		$self->{iter} = $data;
		$self->state( "write" );
	} else {
		eval {
			$h->write( $data );
		};
		if ( $@ ) {
			if ( $@ eq "RSGet::IO: busy" ) {
				$self->{iter} = sub { throw 'DONE' };
				$self->state( "write" );
			} elsif ( $@ eq "RSGet::IO: write: handle closed" ) {
				$self->delete();
			}
		}
	}

}

sub io_write
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
			$self->delete();
			return;
		}
		$self->state( "read" );
		return;
	}

	# there was some problem
	$self->delete();
	if ( $@ eq "RSGet::IO: write: handle closed" ) {
		warn "$@\n";
		return;
	} else {
		die $@;
	}
}


sub delete
{
	my $self = shift;
	RSGet::IO_Event->remove( $self->{_io} );

	my $h = $self->{_io};
	delete $self->{_io};

	$h = $h->handle();
	close $h;
}

1;

# vim: ts=4:sw=4:fdm=marker
