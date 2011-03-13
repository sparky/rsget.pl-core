package RSGet::HTTP_Server;
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
use IO::Socket::INET;
use RSGet::Common qw(throw);
use RSGet::IO_Event;


=head1 RSGet::HTTP_Server -- simple http server

This package implements non-blocking http server.

=head2 my $server = RSGet::HTTP_Server->create( PORT );

Create http server on tcp PORT.

=cut
sub create
{
	my $class = shift;
	my $port = shift;

	my $socket;
	if ( $port =~ m/^\d+$/ ) {
		require IO::Socket::INET;
		$socket = IO::Socket::INET->new(
			Listen => 1,
			LocalPort => $port,
			Proto => 'tcp',
			Listen => 32,
			Reuse => 1,
			Blocking => 0,
		);
	} else {
		if ( -e $port ) {
			throw 'file "%s" exists and it is not a socket', $port
				unless -S $port;
			unlink $port;
		}
		require IO::Socket::UNIX;
		$socket = IO::Socket::UNIX->new(
			Type => IO::Socket::UNIX::SOCK_STREAM(),
			Local => $port,
			Listen => 1,
			Blocking => 0,
		);
	}

	my $self = \$socket;
	bless $self, $class;

	RSGet::IO_Event->add_read( $socket, $self, "_client" );

	return $self;
}


# INTERNAL: accept new connection and create client
sub _client
{
	my $self = shift;
	my $time = shift;

	my $h = $$self;
	my $cli = $h->accept();
	return unless $cli;

	return $self->client( $cli );
}


=head2 $server->client( HANDLE );

Create http connection associated with HANDLE.

=cut
sub client
{
	my $self = shift;
	my $handle = shift;

	require RSGet::HTTP_Connection;
	RSGet::HTTP_Connection->create( $handle );
}


=head2 $server->delete();

Delete http server.

=cut
sub delete
{
	my $self = shift;
	RSGet::IO_Event->remove( $$self );
}

sub DESTROY
{
	my $self = shift;
	$self->delete();
}

1;

# vim: ts=4:sw=4:fdm=marker
