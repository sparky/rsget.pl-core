package RSGet::SCGI_Server;
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
use RSGet::IO_Event;
use RSGet::HTTP_Server;

our @ISA;
@ISA = qw(RSGet::HTTP_Server);


=head1 RSGet::SCGI_Server -- simple scgi server

This package implements non-blocking scgi server.

=head2 my $server = RSGet::SCGI_Server->create( WHERE );

If WHERE is a number creates scgi server on tcp port WHERE, otherwise
creates scgi server on unix socket named WHERE.

Inherited from HTTP_Server.

=head2 $server->client( HANDLE );

Create scgi connection associated with HANDLE.

=cut
sub client
{
	my $self = shift;
	my $handle = shift;

	require RSGet::SCGI_Connection;
	RSGet::SCGI_Connection->open( $handle );
}

=head2 $server->delete();

Delete http server.

Inherited from HTTP_Server.

=cut

1;

# vim: ts=4:sw=4:fdm=marker
