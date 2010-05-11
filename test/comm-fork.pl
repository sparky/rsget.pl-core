#!/usr/bin/perl
use strict;
use warnings;
use RSGet::Mux;
use RSGet::Forks;
use RSGet::Comm::PerlData;
use Data::Dumper;
use IPC::Open3;
use IO::Handle;
use Fcntl;

my $pid = open3( my $ch_in, my $ch_out, my $ch_err, "-" );

unless ( $pid ) {
	# kid
	my $flags = 0;
	fcntl \*STDIN, F_GETFL, $flags
			or die "Couldn't get flags for fh: $!";
	$flags |= O_NONBLOCK;
	fcntl \*STDIN, F_SETFL, $flags
			or die "Couldn't set flags for fh: $!";

	my $io = new RSGet::Comm::PerlData;
	
	#$io->socket_push( "ble" );
	sleep 1;

	print $io->obj2data( { a => 1, b => [ 0, 2 ] } );
	STDOUT->flush();
	sleep 1;

	print $io->obj2data( [1, 3] );
	STDOUT->flush();
	sleep 1;

	$_ = '';
	read STDIN, $_, 64 << 10;

	my $o = $io->data2obj( $_ );
	push @$o, "!";
	print $io->obj2data( $o );
	STDOUT->flush();

	#my $obj = $io->socket_pull();
	#return unless defined $obj;
	#my $o = $io->data2obj( $obj );
	#print "fork pulled:\n", Dumper( $o );

	sleep 1;

	exit;
}

# parent
RSGet::Forks::add( $pid,
	from_child => $ch_out,
	to_child => $ch_in,
	read => \&child_data,
	at_exit => sub {
		print "Child returned: @_\n";
	}
);

my $io = new RSGet::Comm::PerlData;

sub child_data
{
	my $pid = shift;
	my $data = shift;
	my $o = $io->data2obj( $data );
	unless ( $o ) {
		warn "No object this time\n";
	}
	print "pulled:\n", Dumper( $o );

	return $io->obj2data( [ "hell", "o" ] );
}

RSGet::Mux::main_loop();

warn "Ended\n";

# vim:ts=4:sw=4
