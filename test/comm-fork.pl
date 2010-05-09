#!/usr/bin/perl
use strict;
use warnings;
use RSGet::Mux;
use RSGet::Forks;
use RSGet::Comm::Exchange;
use Data::Dumper;

pipe my $parent_in, my $child_out;
pipe my $child_in, my $parent_out;

my $pid = fork;


unless ( $pid ) {
	# kid
	close $parent_in;
	close $parent_out;

	my $io = new RSGet::Comm::Exchange $child_in, $child_out;
	
	#$io->socket_push( "ble" );
	sleep 1;

	$io->socket_push( $io->obj2data( { a => 1, b => [ 0, 2 ] } ) );
	sleep 1;

	my $obj = $io->socket_pull();
	return unless defined $obj;
	my $o = $io->data2obj( $obj );
	print "fork pulled:\n", Dumper( $o );

	sleep 1;

	exit;
}

# parent
RSGet::Forks::add( $pid,
	at_exit => sub {
		RSGet::Mux::remove_short( "io" );
	}
);
close $child_in;
close $child_out;

my $io = new RSGet::Comm::Exchange $parent_in, $parent_out;

sub io_check
{
	my $obj = $io->socket_pull();
	return unless defined $obj;
	my $o = $io->data2obj( $obj );
	print "pulled:\n", Dumper( $o );

	$io->socket_push( $io->obj2data( [ "hello", "o" ] ) );
}

RSGet::Mux::add_short( io => \&io_check );

RSGet::Mux::main_loop();

warn "Ended\n";

# vim:ts=4:sw=4
