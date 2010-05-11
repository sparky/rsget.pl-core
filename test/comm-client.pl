#!/usr/bin/perl
use strict;
use warnings;
use RSGet::Mux;
use RSGet::Comm::PerlData;
use Data::Dumper;

use IO::Socket;

my $port = 7643;
my $sock = "socket";

my $socket;
if ( 0 ) {
	$socket = new IO::Socket::UNIX
		Type => SOCK_STREAM,
		Remote => $sock
	;
} else {
	$socket = new IO::Socket::INET
		Proto => 'tcp',
		PeerAddr => "localhost:$port"
		#	Reuse => 1,
		#	Blocking => 0
	;
}

print "socket: $socket\n";
$socket->blocking( 0 );

my $pd = new RSGet::Comm::PerlData;

#sleep 1;

$socket->send( $pd->obj2data( [ 1, 2, 6, 2 ] ) );

#sleep 1;

my $o;
do {
	my $data;
	$socket->recv( $data, 64 << 10 );
	$o = $pd->data2obj( $data );
} until ( $o );
print "pulled:\n", Dumper( $o );

#sleep 1;

$socket->send( $pd->obj2data( { o => 2 } ) );

# vim:ts=4:sw=4
