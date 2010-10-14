#!/usr/bin/perl
use strict;
use warnings;
use RSGet::Config test => "does nothing";

RSGet::Config::load_config_file "test";

print RSGet::Config->test();

# vim:ts=4:sw=4
