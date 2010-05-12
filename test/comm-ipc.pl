#!/usr/bin/perl
use strict;
use warnings;
use RSGet::Mux;
use RSGet::Comm::IPC;
use Data::Dumper;

my $server = new RSGet::Comm::IPC;

$server->hello( "a" );

$server->bye( { 3 => [ 3, 2 ] }, 1, 4, 2 );

# vim:ts=4:sw=4
