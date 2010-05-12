package RSGet::Comm::IPC;
# This file is an integral part of rsget.pl downloader.
#
# 2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
#use RSGet::Mux;
#use RSGet::Comm::Client;
our $AUTOLOAD;

=head1 RSGet::Comm::IPC

Easyly call functions from server.

=cut

sub new
{
	my $class = shift;
	my $my = "";
	my $self = \$my;
	return bless $self, $class;
}

sub AUTOLOAD
{
	my $server = shift;

	(my $name = $AUTOLOAD) =~ s/.*:://;
	unshift @_, $name;
	$server->{io}->send( $server->obj2data( \@_ ) );

	my $o;
	do {
		my $data;
		$server->{io}->recv( $data, 1 << 10 );
		$o = $server->data2obj( $data );
	} until ( $o );
	print "pulled:\n", Dumper( $o );


	return;
}

1;

# vim: ts=4:sw=4:fdm=marker
