#!/usr/bin/perl
use strict;
use warnings;
use RSGet::Curl;
use RSGet::Config;
use RSGet::SQL;
use RSGet::Plugin::AutoUpdate;
use RSGet::Mux;

use Data::Dumper;

RSGet::Config::init();
RSGet::SQL::init();

my $uri = "http://rsget.pl/download/plugins";

sub d
{
	print Dumper \@_;
}

my $curl = new RSGet::Curl $uri, \&d,
	post => {
		"Link/YouTube" => "4fad0e233323b136787247d54a90d5d9",
	}
	if 1;

RSGet::Plugin::AutoUpdate::update();
RSGet::Mux::main_loop();

warn "Downloaded\n";

# vim:ts=4:sw=4
