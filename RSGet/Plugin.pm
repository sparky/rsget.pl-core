package RSGet::Plugin;
# This file is an integral part of rsget.pl downloader.
#
# 2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;

our ( @ISA, @EXPORT, @EXPORT_OK );
our $VERSION = v0.01;

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(plugin uri unify start get click wait error assert info restart);
@EXPORT_OK = qw();

sub plugin(@)
{
}

sub uri($)
{
}

sub unify(&)
{
}

sub start(&)
{
}

sub get($;@)
{
}

sub click($;@)
{
}

sub wait($;@)
{
}

sub info(@)
{
}

sub error($$)
{
}

sub restart($$)
{
}


sub assert
{
}

1;

# vim: ts=4:sw=4:fdm=marker
