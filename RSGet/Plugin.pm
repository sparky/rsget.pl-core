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
our $VERSION = v0.01;

my @session = qw(plugin uri start get click wait error assert info restart download);

# micro exporter
sub import
{
	my $callpkg = caller 0;
	my $pkg = "RSGet::Plugin";

	no strict 'refs';
	*{"$callpkg\::$_"} = \&{"$pkg\::$_"} foreach @session;
}

sub plugin(@)
{
}

sub uri($)
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

sub download($;@)
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
