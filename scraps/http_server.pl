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

	RSGet::IO_Event->add( $socket, $self, "_client" );

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
	MAX_POST_SIZE => 2 * 1024 * 1024; # 2 MB

sub create
{
	my $class = shift;
	my $handle = shift;

	my $io = RSGet::IO->new( $handle );
	my $self = {
		_io => $io,
	};

	bless $self, $class;

	RSGet::IO_Event->add( $handle, $self, "_data" );

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
	return join "-", map ucfirst, split /[-_]+/, lc shift;
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
		if ( not defined $self->{request} ) {
			$_ = $io->readline();
			$self->{request} = [ split /\s+/, $_ ];
		}
		if ( not defined $self->{headers_done} ) {
			my $h = $self->{headers} ||= {};
			while ( ( $_ = $io->readline() ) ne $/ ) {
				chomp;
				/^(\S+?):\s*(.*)$/
					or die "malformed request";
				$h->{ _lc_h( $1 ) } = $2;
			}
			$self->{headers_done} = 1;
		}
		if ( uc $self->{request}->[0] eq "POST" ) {
			$_ = $self->{headers}->{content_length};
			if ( defined $_ ) {
				/(\d+)/;
				my $len = 0 | $1;
				die "POST data too large"
					if $len > MAX_POST_SIZE;
				$self->{post} = $io->read( $len );
				die "POST data incomplete"
					if length $self->{post} != $len;
			} else {
				$self->{post} = $io->read( MAX_POST_SIZE + 1);
				die "POST data too large"
					if length $self->{post} > MAX_POST_SIZE;
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
				$self->process( $time );
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

sub process
{
	my $self = shift;

	foreach ( keys %$self ) {
		print "found $_: [ $self->{ $_ } ]\n";
		#delete $self->{$_};
	}

	$self->{_io}->handle()->print( "HTTP/1.1 404 Not found\r\nConnection: Keep-Alive\r\nContent-Length: 0\r\n\r\n" );
	foreach ( keys %$self ) {
		next if /^_/;
		print "del $_\n";
		delete $self->{$_};
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
	select undef, undef, undef, 0.1;
}

# vim: ts=4:sw=4
