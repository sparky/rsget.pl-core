package RSGet::Curl_Multi;
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

# use * {{{
use strict;
use warnings;
use WWW::Curl 4.19;
use WWW::Curl::Multi;
use WWW::Curl::Easy ();
use RSGet::Common qw(throw);
use RSGet::IO_Event qw(IO_READ IO_WRITE IO_EXCEPT IO_ANY);
use RSGet::Interval;

BEGIN {
	throw 'expected %s to be %d', 'CURL_CSELECT_IN', IO_READ
		unless CURL_CSELECT_IN == IO_READ;
	throw 'expected %s to be %d', 'CURL_CSELECT_OUT', IO_WRITE
		unless CURL_CSELECT_OUT == IO_WRITE;
	throw 'expected %s to be %d', 'CURL_CSELECT_ERR', IO_EXCEPT
		unless CURL_CSELECT_ERR == IO_EXCEPT;
}

# WWW::Curl::Multi object
my $multi = __PACKAGE__->new();

# list of registered easy-wrapper objects
my @easy;

# number of active connections
my $active_last = -1;

# }}}

=head1 package RSGet::Curl_Multi

WWW::Curl::Multi wrapper.

=head2 my $multi = RSGet::Curl_Multi->new(); # INTERNAL

Prepare new Multi object.

=cut
sub new()
{
	my $multi = WWW::Curl::Multi->new();
	$multi->setopt( CURLMOPT_SOCKETFUNCTION, \&on_socket );
	#$multi->setopt( CURLMOPT_TIMERFUNCTION, \&on_timer );

	return $multi;
}


=head2 RSGet::Curl_Multi->add( OBJECT );

Add easy-wrapper object to multi. The object must be a hashref with
{easy} key pointing to a valid WWW::Curl::Easy object. Wrapper object
must also have finish() method which will be called at the end.

=cut
sub add($$)
{
	my ( $class, $obj ) = @_;

	my $easy = $obj->{easy};
	foreach my $i ( 0..@easy ) {
		next unless $easy[ $i ];
		$easy[ $i ] = $obj;
		$easy->setopt( WWW::Curl::Easy::CURLOPT_PRIVATE, $i );
		last;
	}

	$active_last = -1;
	$multi->add_handle( $easy );
}


=head2 RSGet::Curl_Multi::on_socket( DATA, SOCKET, EVENT ); # INTERNAL

Used internally. Will be called by multi object any time some socket event
must be registered or removed.

=cut
sub on_socket
{
	my ( $user_data, $socket_fn, $what ) = @_;

	RSGet::IO_Event->remove( IO_ANY, $socket_fn );
	my $event = 0;

	if ( $what == CURL_POLL_IN ) {
		$event = IO_READ;
	} elsif ( $what == CURL_POLL_OUT ) {
		$event = IO_WRITE;
	} elsif ( $what == CURL_POLL_INOUT ) {
		$event = IO_READ | IO_WRITE;
	} else {
		return;
	}

	RSGet::IO_Event->add( $event, $socket_fn, __PACKAGE__, 'on_data' );
}


=head2 RSGet::Curl_Multi::on_timer( DATA, TIMEOUT ); # INTERNAL

Used internally. Will be called by multi object any time the timeout
must be updated.

=cut
sub on_timer
{
	#my ( $user_data, $timeout_ms ) = @_;
	#if ( $timeout_ms < 0 ) {
	#	$timeout = 1.0;
	#} else {
	#	$timeout = $timeout_ms / 1000;
	#}
}


=head2 RSGet::Curl_Multi::on_data( CLASS, EVENT, FILENO ); # INTERNAL

Used internally. Will be called by IO_Event any time there is some
activity on a socket.

=cut
sub on_data
{
	my ( $class, $event, $fn ) = @_;

	my $active_now = $multi->socket_action( $fn, $event );
	return if $active_now == $active_last;
	$active_last = $active_now;

	while ( my ( $id, $value ) = $multi->info_read ) {
		my $obj = $easy[ $id ];
		delete $easy[ $id ];

		$obj->finish( $value );
	}
}



RSGet::Interval::add
	curl => sub
	{
		return on_data( __PACKAGE__, CURL_SOCKET_TIMEOUT, 0 );
	};


1;

# vim: ts=4:sw=4:fdm=marker
