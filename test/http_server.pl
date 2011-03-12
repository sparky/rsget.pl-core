#!/usr/bin/perl
#
use strict;
use warnings;
use RSGet::Cnt;
use RSGet::HTTP_Server;
use RSGet::Mux;

$SIG{CHLD} = sub {
	my $kid;
	do {
		$kid = waitpid -1, RSGet::Cnt::WNOHANG;
		#print "\rChild $kid exited: $?\n" if $kid > 0;
	} while ( $kid > 0 );
};

my $server = RSGet::HTTP_Server->create( 8080 );

my @c = qw(\ | / -);
my $i = 0;

RSGet::Mux::add_short
	_fly => sub {
		print "\r" . $c[ $i = ( $i + 1 ) % 4 ];
		STDOUT->flush();
	};
RSGet::Mux::main_loop();

# vim: ts=4:sw=4
