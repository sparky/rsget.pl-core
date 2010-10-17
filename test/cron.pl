#!/usr/bin/perl
use strict;
use warnings;
use RSGet::Common;
use RSGet::Config;
use RSGet::Cron;

RSGet::Config::load_config_file "test";

foreach ( 0..100 ) {
	RSGet::Cron::tick();
	sleep 1;
}

# vim:ts=4:sw=4
