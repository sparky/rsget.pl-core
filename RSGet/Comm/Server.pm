package RSGet::Comm::Server;
# This file is an integral part of rsget.pl downloader.
#
# 2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
use RSGet::Mux;
use RSGet::Comm::Client;
use RSGet::Config;
use Fcntl;
use IO::Select;
use IO::Socket;

=head1 RSGet::Comm::Server

Few functions to exchange perl data types between multiple processes.

It should be used as base for server, clients and communicating with our
own forks.

=cut

RSGet::Config::register_settings(
	server_port => {
		desc => "Start TCP server on this port.",
		default => 0,
		allowed => sub { /^\d+$/ && ( $_ < (64 << 10) ) },
	},
	server_socket => {
		desc => "Start server on this unix socket.",
		default => "",
	},
);

$SIG{PIPE} = 'IGNORE';

my $select_server;
my $select_clients;
my $socketfile;

sub init
{
	my @socks;
	if ( $socketfile = RSGet::Config::get( undef, "server_socket" ) ) {
		my $unix = new IO::Socket::UNIX
			Type => SOCK_STREAM,
			Local => $socketfile,
			Listen => 1
			;
		if ( $unix ) {
			warn "Started server on socket $socketfile.\n";
		} else {
			die "Could not start server on socket $socketfile.\n";
		}
		push @socks, $unix;
	}
	if ( my $port = RSGet::Config::get( undef, "server_port" ) ) {
		my $inet = new IO::Socket::INET
			Proto => 'tcp',
			LocalPort => $port,
			Listen => 5,
			Reuse => 1
		;
		if ( $inet ) {
			warn "Started server on port $port.\n";
		} else {
			die "Could not start server on port $port.\n";
		}
		push @socks, $inet;
	}

	return unless @socks;

	$select_server = new IO::Select;
	$select_clients = new IO::Select;
	warn "Select: $select_server, $select_clients\n";

	$select_server->add( @socks );

	RSGet::Mux::add_short( z_comm_server => \&_perform );
}

END {
	unlink $socketfile if $socketfile;
}

sub _perform
{
	my @servers = $select_server->can_read( 0 );
	while ( my $s = shift @servers ) {
		my $io = $s->accept();
		$io->blocking( 0 );

		my $cli = new RSGet::Comm::Client;
		$select_clients->add( [ $io, $cli ] );
	}

	my @clients = $select_clients->can_read( 0 );
	while ( my $c = shift @clients ) {
		eval {
			_process_client( @$c )
		};
		if ( $@ ) {
			warn $@;
			$select_clients->remove( $c );
			$c->[0]->close();
		}
	}
}

sub _process_client
{
	my $io = shift;
	my $client = shift;

	my $data = '';
	$io->recv( $data, 64 << 10 );
	die "RSGet::Comm::Server::_process_client: Client disconnected\n"
		unless length $data;

	while ( my $o = $client->data2obj( $data ) ) {
		$data = '';
		my $out = $client->process( $o );
		if ( $out ) {
			$io->send( $client->obj2data( $out ) );
		}
	}
}

1;

# vim: ts=4:sw=4:fdm=marker
