#!/usr/bin/perl
use strict;
use warnings;
use RSGet::Curl;

use Data::Dumper;

my $uri = "http://rsget.pl/download/plugins";

sub d
{
	print Dumper \@_;
}

my $curl = new RSGet::Curl $uri, \&d,
	post => {
		"Link/YouTube" => "4fad0e233323b136787247d54a90d5d9",
	};

while ( RSGet::Curl::perform() ) {
	warn "Downloading...";
	select undef, undef, undef, 0.1;
}

warn "Downloaded\n";

# vim:ts=4:sw=4
