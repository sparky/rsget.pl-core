#!/usr/bin/perl
#
use strict;
use warnings;
use RSGet::Cnt;
use RSGet::HTTP_Server;

$SIG{CHLD} = sub {
	my $kid;
	do {
		$kid = waitpid -1, RSGet::Cnt::WNOHANG;
		print "\rChild $kid exited: $?\n" if $kid > 0;
	} while ( $kid > 0 );
};

my $server = RSGet::HTTP_Server->create( 8080 );

my @c = qw(\ | / -);
my $i = 0;
while ( 1 ) {
	eval {
		RSGet::IO_Event::_perform();
	};
	warn "_perform() died: $@" if $@;
	select undef, undef, undef, 0.05;
	print "\r" . $c[ $i = ( $i + 1) % 4 ];
	STDOUT->flush();
}

# vim: ts=4:sw=4
