package RSGet::Plugin;
# This file is an integral part of rsget.pl downloader.
#
# Copyright (C) 2010	Przemysław Iskra <sparky@pld-linux.org>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

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
