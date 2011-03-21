#!/usr/bin/perl
#
use strict;
use warnings;
use RSGet::Cnt;
use RSGet::Comm::Server;
use RSGet::Interval;

$SIG{CHLD} = sub {
	my $kid;
	do {
		$kid = waitpid -1, RSGet::Cnt::WNOHANG;
		#print "\rChild $kid exited: $?\n" if $kid > 0;
	} while ( $kid > 0 );
};

my $port = shift @ARGV || 8080;
my $server = RSGet::Comm::Server->create(
	port => $port,
	conn => "RSGet::Comm::HTTP"
);

my @c = qw(. o 8 º ' º 8 o);
my $i = -1;

RSGet::Interval::add
	fly => sub {
		syswrite STDOUT, "\r" . $c[ $i = ( $i + 1 ) % scalar @c ];
	};
RSGet::Interval::main_loop();

# vim: ts=4:sw=4
