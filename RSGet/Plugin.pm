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
use RSGet::Common;
our $VERSION = v0.01;

my @session = qw(
	downloader
	this
	get download
	sleep click
	error info restart delay
	assert expect
);

# micro exporter
sub import
{
	my $callpkg = caller 0;
	my $pkg = shift || "RSGet::Plugin";

	no strict 'refs';
	*{"$callpkg\::$_"} = \&{"$pkg\::$_"} foreach @session;
}


# register new downloader
sub downloader(&)
{
}


# return current session
sub this()
{
	#require RSGet::Session;
	#return $RSGet::Session::current;
	return {};
}


# get/post uri, download to memory
sub get($@)
{
}

# get file, download to disk
sub download($@)
{
}

# wait some time before next step
sub sleep($)
{
}

# return small random number
sub click()
{
	return RSGet::Common::irand( 2, 5 );
}


# file information, or links
sub info(@)
{
}

# die with an error
sub error($$)
{
}

# restart download
sub restart($$$)
{
}

# make sure operation was successfull
sub assert
{
}

# log operation and its value
sub expect
{
}

1;

# vim: ts=4:sw=4:fdm=marker
