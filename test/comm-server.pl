#!/usr/bin/perl
use strict;
use warnings;
use RSGet::Mux;
use RSGet::Config;
use RSGet::Comm::Server;
use Data::Dumper;

RSGet::Config::init();
RSGet::Comm::Server::init();

RSGet::Mux::main_loop();

warn "Ended\n";

# vim:ts=4:sw=4
