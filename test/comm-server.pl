#!/usr/bin/perl
use strict;
use warnings;
use RSGet::Mux;
use RSGet::Comm::PerlData;
use Data::Dumper;
use Fcntl;

use IO::Select;
use IO::Socket;

my $port = 7643;
my $sock = "socket";
unlink $sock;

END {
	unlink $sock;
}

$SIG{PIPE} = sub {
	warn "PIPE: @_\n";
};

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
	print "Servers: @servs\n" if @servs;
	while ( my $s = shift @servs ) {
		my $io = $s->accept();
		$io->blocking( 0 );

		my $pd = new RSGet::Comm::PerlData;
		$select_cli->add( [ $io, $pd ] );
	}

	my @clis = $select_cli->can_read(0);
	print "Clients: @clis\n" if @clis;

	#my @clisw = $select_cli->can_write(0);
	#print "Clients write: @clisw\n" if @clisw;

	#my @clise = $select_cli->has_exception(0);
	#print "Clients exception: @clise\n" if @clise;


	while ( my $c = shift @clis ) {
		my ( $io, $pd ) = @$c;
		my $data = '';
		$io->recv( $data, 64 << 10 );
		unless ( length $data ) {
			warn "Client disconnected\n";
			$select_cli->remove( $c );
		}
		my $o = $pd->data2obj( $data );
		next unless defined $o;
		print "pulled:\n", Dumper( $o );

		$io->send( $pd->obj2data( [ "hell", "o" ] ) );
	}
}

=ble
	my $obj = $io->socket_pull();
	return unless defined $obj;
	my $o = $io->data2obj( $obj );
	print "pulled:\n", Dumper( $o );

}
=cut

RSGet::Mux::add_short( io => \&io_check );

RSGet::Mux::main_loop();

warn "Ended\n";

# vim:ts=4:sw=4
