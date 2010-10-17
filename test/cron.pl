#!/usr/bin/perl
use strict;
use warnings;
use RSGet::Common;
use RSGet::Config;
use RSGet::Cron;
use RSGet::Mux;

RSGet::Config::load_config_file "test";

RSGet::Mux::main_loop();

# vim:ts=4:sw=4
