package RSGet::HTTP_Client;
# This file is an integral part of rsget.pl downloader.
#
# Copyright (C) 2010	Przemysław Iskra <sparky@pld-linux.org>
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
	401 => "Authorization Required",
	404 => "Not Found",
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

	RSGet::IO_Event->add_read( $handle, $self );

	return $self;
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
			$self->delete();
			if ( $@ eq "RSGet::IO: handle closed" ) {
				$self->process( $time )
					if $self->{h_in_done};
				return;
			} else {
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
		foreach ( split /&/, $self->{post_data} ) {
			s/^(.*?)=//;
			my $key = $1;
			tr/+/ /;
			s/%(..)/chr hex $1/eg;
			$post{ $key } = $_;
		}
	} elsif ( $self->{file} =~ s/\?(.*)// ) {
		my $get = $1;
		%post = map {
				/^(.*?)=(.*)/;
				(uri_unescape( $1 ), uri_unescape( $2 ) )
			} split /[;&]+/, $get;
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

	require RSGet::HTTP_Request;
	my $handler = RSGet::HTTP_Request->get_handler( $self->{file} );

	if ( $handler ) {
		my @args = @$handler;
		shift @args; # file match
		my $func = shift @args;
		eval {
			$data = $func->( $self, @args );
		};
		if ( $@ ) {
			$self->{code} = 500;
			$data = "Server error: $@\n";
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
	} else {
		$self->{h_out}->{content_length} = length $data;
	}

	my $headers = "HTTP/1.1 $self->{code} $codes{ $self->{code} }\r\n";
	foreach my $hdr ( sort keys %{ $self->{h_out} } ) {
		$headers .= _ucfirst_h( $hdr ) . ": " . $self->{h_out}->{ $hdr } . "\r\n";
	}
	$headers .= "\r\n";


	my $h = $self->{_io};
	eval {
		$h->write( $headers );
	};
	if ( ref $data ) {
		$self->{_iter} = $data;
		RSGet::IO_Event->add_write( $h, $self );
	} else {
		eval {
			$h->write( $data );
		};
		if ( $@ ) {
			if ( $@ eq "RSGet::IO: busy" ) {
				$self->{_iter} = sub { throw 'no data' };
				RSGet::IO_Event->add_write( $h, $self );
			} elsif ( $@ eq "RSGet::IO: handle closed" ) {
				$self->delete();
			}
		}
	}

	foreach ( keys %$self ) {
		next if /^_/;
		delete $self->{$_};
	}
}

sub io_write
{
	my $self = shift;
	my $time = shift;

	my $h = $self->{_io};
	my $i = $self->{_iter};
	eval {
		$h->write();
		while ( defined ( $_ = $i->() ) ) {
			$h->write( $_ );
		}
	};
	if ( $@ ) {
		if ( $@ eq "RSGet::IO: busy" ) {
			# do nothing
			return;
		} else {
			RSGet::IO_Event->remove_write( $h );
			if ( $@ eq "RSGet::IO: handle closed" ) {
				$self->delete();
				return;
			} else {
				die $@;
			}
		}
	} else {
		RSGet::IO_Event->remove_write( $h );
		delete $self->{_iter};
	}
}


sub delete
{
	my $self = shift;
	RSGet::IO_Event->remove( $self->{_io} );
}

1;

# vim: ts=4:sw=4:fdm=marker
