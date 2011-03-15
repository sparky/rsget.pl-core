#!/usr/bin/perl
#
use strict;
use warnings;
use RSGet::Cnt;
use RSGet::SCGI_Server;
use RSGet::Interval;

$SIG{CHLD} = sub {
	my $kid;
	do {
		$kid = waitpid -1, RSGet::Cnt::WNOHANG;
		#print "\rChild $kid exited: $?\n" if $kid > 0;
	} while ( $kid > 0 );
};

my $port = shift @ARGV || 4040;
my $server = RSGet::SCGI_Server->create( $port );

my @c = qw(\ | / -);
my $i = 0;

RSGet::Interval::add
	fly => sub {
		syswrite STDOUT, "\r" . $c[ $i = ( $i + 1 ) % scalar @c ];
	};
RSGet::Interval::main_loop();

# vim: ts=4:sw=4
