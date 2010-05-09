#!/usr/bin/perl
use strict;
use warnings;
use RSGet::Mux;
use RSGet::Comm::Exchange;
use Data::Dumper;

use IO::Select;
use IO::Socket;

my $port = 7643;
my $sock = "socket";
unlink $sock;

END {
	unlink $sock;
}

my $select_serv = new IO::Select;
my $select_cli = new IO::Select;

my $unix = new IO::Socket::UNIX
	Type => SOCK_STREAM,
	Local => $sock,
	Listen => 1
	;

my $inet = new IO::Socket::INET
	Proto => 'tcp',
	LocalPort => $port,
	Listen => 5,
	Reuse => 1,
	Blocking => 0
	;

print "unix: $unix\ninet: $inet\n";

$select_serv->add( $unix, $inet );


sub io_check
{
	my @servs = $select_serv->can_read(0);
	print "Servers: @servs\n";
	while ( my $s = shift @servs ) {
		my $client = $s->accept();

		my $io = new RSGet::Comm::Exchange $client;
		$select_cli->add( [ $client, $io ] );
	}

	my @clis = $select_cli->can_read(0);
	print "Clients: @clis\n";
	while ( my $c = shift @clis ) {
		my ( $sock, $io ) = @$c;
		$io->socket_pull();
	}
}

=ble
	my $obj = $io->socket_pull();
	return unless defined $obj;
	my $o = $io->data2obj( $obj );
	print "pulled:\n", Dumper( $o );

	$io->socket_push( $io->obj2data( [ "hello", "o" ] ) );
}
=cut

RSGet::Mux::add_short( io => \&io_check );

RSGet::Mux::main_loop();

warn "Ended\n";

# vim:ts=4:sw=4
