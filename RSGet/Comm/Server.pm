package RSGet::Comm::Server;
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
use RSGet::Common qw(throw args REQUIRED);
use RSGet::IO_Event;


=head1 RSGet::Comm::Server -- simple connection listener

This package implements non-blocking server.

=head2 my $server = RSGet::Comm::Server->create( %OPTIONS );

Create server on tcp port or unix socket. Options are:

	conn - class to call when new connection arrives (required)
	port - TCP port to listen on
	unix - UNIX socket file to listen on
	perm - file permissions for unix socket
	args - additional arguments to pass to conn->open()

=cut
sub create($%) # {{{
{
	my $class = shift;
	my %self = args {
		conn => REQUIRED 'string',
		port => qr/\d+/,
		unix => 'string',
		perm => qr/\d+/,
		args => 'ARRAY',
	}, @_;

	eval "require $self{conn}";
	throw 'cannot use "%s" as connection class: %s', $self{conn}, "$@"
		if $@;
	throw 'package %s is not a correct connection class', $self{conn}
		unless $self{conn}->can( 'open' );

	if ( exists $self{port} ) {
		require IO::Socket::INET;
		$self{socket} = IO::Socket::INET->new(
			Listen => 32,
			LocalPort => $self{port},
			Proto => 'tcp',
			Reuse => 1,
			Blocking => 0,
		);
		throw 'Cannot create INET socket: %s', $!
			unless $self{socket};

	} elsif ( exists $self{unix} ) {
		if ( -e $self{unix} ) {
			throw 'file "%s" exists and it is not a socket', $self{unix}
				unless -S $self{unix};
			unlink $self{unix};
		}

		require IO::Socket::UNIX;
		$self{socket} = IO::Socket::UNIX->new(
			Type => IO::Socket::UNIX::SOCK_STREAM(),
			Local => $self{unix},
			Listen => 1,
			Blocking => 0,
		);

		throw 'Cannot create UNIX socket: %s', $!
			unless $self{socket};

		chmod $self{perm}, $self{unix}
			if exists $self{perm};

	} else {
		throw 'Neither "port" nor "unix" specified';
	}

	my $self = \%self;
	bless $self, $class;

	RSGet::IO_Event->add_read( $self{socket}, $self );

	return $self;
} # }}}


=head2 $server->io_read( HANDLE );

Open new connection associated with HANDLE. Called automatically from IO_Event.

=cut
sub io_read($;$) # {{{
{
	my $self = shift;
	my $time = shift;

	my $h = $self->{socket};
	my $cli = $h->accept();
	return unless $cli;

	my $conn = $self->{conn};
	$conn->open( $cli, $self->{args} ? @{ $self->{args} } : () );
} # }}}


=head2 $server->delete();

Delete http server.

=cut
sub delete($)
{
	my $self = shift;
	RSGet::IO_Event->remove( $self->{socket} );
	unlink $self->{unix} if $self->{unix};

	return;
}

sub DESTROY($)
{
	my $self = shift;
	$self->delete();
}

1;

# vim: ts=4:sw=4:fdm=marker
