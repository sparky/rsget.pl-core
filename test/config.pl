#!/usr/bin/perl
use strict;
use warnings;
use RSGet::Config test => "does nothing";

RSGet::Config::load_config_file "test";


print @{ RSGet::Config->test };
sleep 2;
print @{ RSGet::Config->test() };

our $global = "root";
print RSGet::Config->glob, "\n";
$global = "notroot";
print RSGet::Config->glob, "\n";

# vim:ts=4:sw=4
