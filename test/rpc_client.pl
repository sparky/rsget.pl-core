#!/usr/bin/perl
#
use strict;
use warnings;
use RSGet::Cnt;
use RSGet::Comm::PerlRPC;
use RSGet::Interval;
use Crypt::Rijndael;

my $aes = Crypt::Rijndael->new( "a" x 32, Crypt::Rijndael::MODE_CBC() );

my $peer = shift @ARGV || 'localhost:7676';

use IO::Socket::INET;
my $socket = IO::Socket::INET->new(
	PeerAddr => $peer,
	Proto => 'tcp',
);

my $cli = RSGet::Comm::PerlRPC->open( $socket, compress => 1, cipher => $aes );
$cli->read_end();

my @c = split //, ' .:.';
my $i = -1;

RSGet::Interval::add
	fly => sub {
		syswrite STDOUT, "\r" . $c[ $i = ( $i + 1 ) % scalar @c ] . "\r";
	};
RSGet::Interval::main_loop();

package RSGet::Comm::PerlRPC;

use Data::Dumper;

sub handle($)
{
	my $self = shift;

	my $obj = $self->data2obj( $self->{DATA} );
	print Dumper( $obj );

	#exit if $obj;
	return { func => "file", args => [ path => "test/rpc_client.pl" ] };
}


# vim: ts=4:sw=4
