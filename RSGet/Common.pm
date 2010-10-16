package RSGet::Common;
# This file is an integral part of rsget.pl downloader.
#
# 2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
use vars qw(@ISA @EXPORT @EXPORT_OK);

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw($user $file $plugin $session $interface);
@EXPORT_OK = qw();

# user that is actually downloading; $session/$file owner
our $user;

# destination file
our $file;

# getter information
our $plugin;

# download session
our $session;

# user network interface
our $interface;

1;

# vim: ts=4:sw=4:fdm=marker
