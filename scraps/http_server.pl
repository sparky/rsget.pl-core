#!/usr/bin/perl
#
use strict;
use warnings;

package RSGet::HTTP::Server;

use IO::Socket::INET;
use RSGet::IO_Event;

sub create
{
	my $class = shift;
	my $port = shift;
	my $socket = IO::Socket::INET->new(
		Listen => 1,
		LocalPort => $port,
		Proto => 'tcp',
		Listen => 10,
		Reuse => 1,
		Blocking => 0,
	);

	my $self = \$socket;
	bless $self, $class;

	RSGet::IO_Event->add_read( $socket, $self, "_client" );

	return $self;
}

sub _client
{
	my $self = shift;
	my $time = shift;

	my $h = $$self;
	my $cli = $h->accept();
	return unless $cli;

	RSGet::HTTP::Client->create( $cli );
}

sub delete
{
	my $self = shift;
	RSGet::IO_Event->remove( $$self );
}

package RSGet::HTTP::Client;

use RSGet::IO;
use RSGet::IO_Event;
use constant
	MAX_POST_SIZE => 1 * 1024 * 1024; # 1 MB

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

	RSGet::IO_Event->add_read( $handle, $self, "_data" );

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

sub _data
{
	my $self = shift;
	my $time = shift;

	my $io = $self->{_io};

NEXT_REQUEST:
	eval {
		local $/ = "\r\n";
		local $_;
		if ( not defined $self->{method} ) {
			$_ = $io->readline();
			my @request = split /\s+/, $_;

			$self->{method} = uc shift @request;

			$_ = shift @request;
			s#^/+##;
			s#/+$##;
			s#//+#/#g;
			$self->{file} = $_;
		}
		if ( not defined $self->{h_in_done} ) {
			my $h = $self->{h_in} ||= {};
			while ( ( $_ = $io->readline() ) ne $/ ) {
				chomp;
				/^(\S+?):\s*(.*)$/
					or die "malformed request";
				$h->{ _lc_h( $1 ) } = $2;
			}
			$self->{h_in_done} = 1;
		}
		if ( $self->{method} eq "POST" ) {
			$_ = $self->{h_in}->{content_length};
			if ( defined $_ and /(\d+)/ ) {
				my $len = 0 | $1;
				die "POST data too large"
					if $len > MAX_POST_SIZE;
				$self->{post_data} = $io->read( $len );
				die "POST data incomplete"
					if length $self->{post_data} != $len;
			} else {
				$self->{post_data} = $io->read( MAX_POST_SIZE + 1);
				die "POST data too large"
					if length $self->{post_data} > MAX_POST_SIZE;
			}
		}
	};
	if ( $@ ) {
		if ( $@ =~ /^RSGet::IO: no data/ ) {
			# do nothing, wait for more data
			return;
		} else {
			$self->delete();
			if ( $@ =~ /^RSGet::IO: handle closed/ ) {
				$self->process( $time )
					if $self->{h_in_done};
				return;
			} else {
				die $@;
			}
		}
	} else {
		$self->process( $time );
		goto NEXT_REQUEST;
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

my @handlers = (
	[ "a", sub {
			my $self = shift;
			$self->{h_out}->{content_type} = "text/html";
			return join "<br/>", map "<iframe src='/a/$_'></iframe>", (1..99)
		} ],
	[ "big", sub { return "12345678" x ( 32 * 1024 * 1024 ) } ],
	[ qr#a/.*#, sub {
			my $self = shift;
			$self->{h_out}->{content_type} = "text/plain";
			return "file '$self->{file}'\n"
		} ],
);

sub process
{
	my $self = shift;

	$self->{post} = _post2hash( $self );
	$self->{code} = 200;
	$self->{h_out} = {
		content_type => "text/xml; charset=utf-8",
	};

	my $data = "";
	my $handler;
	foreach my $hdl ( @handlers ) {
		my $file = $hdl->[0];
		if ( ref $file eq "Regexp" ) {
			next unless $self->{file} =~ /^$file$/;
		} else {
			next unless $self->{file} eq $file;
		}
		$handler = $hdl;
		last;
	}
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

	$self->{code} = 500 if not exists $codes{ $self->{code} };
	if ( $self->{code} != 200 ) {
		$self->{h_out} = {
			content_type => "text/plain; charset=utf-8",
		};
		$data ||= $codes{ $self->{code} } . "\r\n";
	}
	$self->{h_out}->{connection} = "Keep-Alive";
	$self->{h_out}->{content_length} = length $data;

	my $h = $self->{_io};
	$h->write( "HTTP/1.1 $self->{code} $codes{ $self->{code} }\r\n" );
	foreach my $hdr ( sort keys %{ $self->{h_out} } ) {
		$h->write( _ucfirst_h( $hdr ) . ": " . $self->{h_out}->{ $hdr } . "\r\n" );
	}
	$h->write( "\r\n" );
	eval {
		$h->write( $data );
	};
	if ( $@ ) {
		if ( $@ =~ /^RSGet::IO: busy/ ) {
			RSGet::IO_Event->add_write( $h, $self );
		} elsif ( $@ =~ /^RSGet::IO: handle closed/ ) {
			$self->delete();
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
	eval {
		# flush
		$h->write();
	};
	if ( $@ ) {
		if ( $@ =~ /^RSGet::IO: busy/ ) {
			# do nothing
			return;
		} else {
			RSGet::IO_Event->remove_write( $h );
			if ( $@ =~ /^RSGet::IO: handle closed/ ) {
				$self->delete();
				return;
			} else {
				die $@;
			}
		}
	}
}

sub delete
{
	my $self = shift;
	RSGet::IO_Event->remove( $self->{_io} );
}

1;

package main;

my $server = RSGet::HTTP::Server->create( 8080 );

while ( 1 ) {
	eval {
		RSGet::IO_Event::_perform();
	};
	warn "_perform() $@" if $@;
	select undef, undef, undef, 0.05;
}

# vim: ts=4:sw=4
