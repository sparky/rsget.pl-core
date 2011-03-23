#!/usr/bin/perl
#
use strict;
use warnings;
use RSGet::Cnt;
use RSGet::Comm::Server;
use RSGet::Interval;
use Crypt::Rijndael;

my $aes = Crypt::Rijndael->new( "a" x 32, Crypt::Rijndael::MODE_CBC() );

my $port = shift @ARGV || 7676;
my $server = RSGet::Comm::Server->create(
	port => $port,
	conn => "RSGet::Comm::PerlRPC",
	args => [ compress => 1, cipher => $aes ],
);

my @c = split //, ' .:.';
my $i = -1;

RSGet::Interval::add
	fly => sub {
		syswrite STDOUT, "\r" . $c[ $i = ( $i + 1 ) % scalar @c ];
	};
RSGet::Interval::main_loop();

# vim: ts=4:sw=4
