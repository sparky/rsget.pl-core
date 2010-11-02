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
use RSGet::Context;
our $VERSION = v0.01;

my @session = qw(
	downloader
	this
	get download
	sleep click
	error info restart delay
	assert expect
);

my %plugins;

sub import
{
	my $callpkg = caller 0;
	my $pkg = shift || "RSGet::Plugin";

	# register plugin
	my $plugin = { uri => [] };
	while ( my ( $key, $value ) = splice @_, 0, 2 ) {
		if ( $key eq "uri" ) {
			push @{ $plugin->{ $key } }, $value;
		} else {
			$plugin->{ $key } = $value;
		}
	}
	$plugins{ $callpkg } = $plugin;

	# export all session methods
	no strict 'refs';
	*{"$callpkg\::$_"} = \&{"$pkg\::$_"} foreach @session;
}


# register new downloader
sub downloader(&)
{
	my $callpkg = caller 0;
	my $code = shift;

	$plugins{ $callpkg }->{downloader} = $code;
}


# return current session
sub this()
{
	# XXX: correct but slow, replace with internal session ref
	return RSGet::Context->session();
}


# get/post uri, download to memory
sub get($$@)
{
	_coverage();

	my $uri = shift;
	my $code = pop;

	...
}

# get file, download to disk
sub download($@)
{
	_coverage();

	my $uri = shift;
	my $fallback;
	if ( @_ & 1 ) {
		$fallback = pop;
	}

	...
}

# wait some time before next step
sub sleep($)
{
	_coverage();

	this->{sleep} = shift;
}

# return small random number
sub click()
{
	return RSGet::Common::irand( 2, 5 );
}


# file information, or links
sub info(@)
{
	_coverage();

	my %info = @_;

	this->{info} = \%info;

	_abort() if this->{info_only} or $info{links};
}

# die with an error
sub error($$)
{
	_coverage();

	this->{error} = [ @_ ];
	_abort();
}

# restart download
sub restart($$$)
{
	_coverage();

	my $time = shift;

	...;

	_abort();
}

# make sure operation was successfull
sub assert
{
	my $success = @_ > 0 && $_[ $#_ ] || undef;

	unless ( $success ) {
		# fake coverage information
		my @c = caller 0;
		@_ = (assertion_failed => "at $c[1], line $c[2]");
		goto &error;
	}

	_coverage();
}

# log operation and its value
sub expect
{
	my $success = 0;
	$success = 1 if wantarray ? @_ : $_[ $#_ ];

	_coverage( @_ );

	return wantarray ? @_ : $_[ $#_ ];
}

sub _coverage
{
	my @c = caller 1;
	my $func = $c[3];
	$func =~ s/^RSGet::Plugin:://;
	print "coverage: '$func' called from '$c[1]:$c[2]'\n";
}

sub _abort
{
	die [ abort => shift ];
}

1;

# vim: ts=4:sw=4:fdm=marker
