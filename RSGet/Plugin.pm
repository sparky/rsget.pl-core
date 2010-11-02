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
our $VERSION = v0.1.0;

=head1 RSGet::Plugin -- interface for rsget.pl plugins

This module must be imported by all rsget.pl plugins. It rsgisters the plugin
and defines an interface for connection with the core.

=cut

my @session = qw(
	downloader
	this
	get download
	sleep click
	error info restart delay
	assert expect
);

my %plugins;

# INTERNAL: my $val = _ref_check TYPE => $argument;
#
# Make sure argument is a ref to TYPE. Die if it isn't.
#
# my $val = _ref_check $argument;
#
# Die if argument is a ref.
#
sub _ref_check($;$)
{
	my $var = pop;
	my $type = shift || "";

	my $ref = ref $var;
	unless ( $ref eq $type ) {
		RSGet::Common::confess( "Argument should contain a '$type' ref, but it is '$ref'\n" );
	}

	return $var;
}

# INTERNAL: my $val = _val_check qr/PATTERN/ => $argument;
#
# Make sure argument matches PATTERN. Die if it doesn't.
#
sub _val_check($$)
{
	my $var = pop;
	my $match = shift;

	my $ref = ref $var;
	unless ( $ref eq "" ) {
		RSGet::Common::confess( "Argument should be a scalar, but it is a ref to '$ref'\n" );
	}

	unless ( $var =~ m/^$match$/ ) {
		RSGet::Common::confess( "Argument '$var' does not match pattern: $match\n" );
	}
}


=head2 use RSGet::Common VERSION [OPTIONS];

Register new plugin.

 use RSGet::Plugin v0.1.0
 	name => "Service name",
	web => "http://main_page.com/",
	tos => "http://main_page.com/terms_of_service",
	uri => qr{main_page\.com/supported_uris/.*},
	uri => qr{secong_page\.com/supported_uris/.*};

=cut

# INTERNAL: _register_plugin( PKG, [OPTIONS] )
#
sub _register_plugin
{
	my $callpkg = shift;

	# register plugin
	my $plugin = $plugins{ $callpkg } ||= {};
	$plugin->{uri} ||= [];

	while ( my ( $key, $value ) = splice @_, 0, 2 ) {
		if ( $key eq "uri" ) {
			push @{ $plugin->{ $key } }, $value;
		} else {
			$plugin->{ $key } = $value;
		}
	}
}

# Save required version number. Later we'll be able to whether plugin
# requires interface new-enough for it to work.
sub VERSION
{
	_register_plugin( scalar caller 0, plugin_version => $_[1] );

	# actually check the version
	goto \&UNIVERSAL::VERSION;
}

# Register plugin and export all methods.
sub import
{
	my $callpkg = caller 0;
	my $pkg = shift || "RSGet::Plugin";

	_register_plugin( $callpkg, @_ );

	# export all session methods
	no strict 'refs';
	*{"$callpkg\::$_"} = \&{"$pkg\::$_"} foreach @session;
}


=head2 downloader SUB;

Register new downloader.

	downloader {
		ALL CODE GOES HERE;
	};

=cut
sub downloader(&)
{
	my $callpkg = caller 0;
	my $code = _ref_check CODE => shift;

	$plugins{ $callpkg }->{downloader} = $code;
}


=head2 my $val = this()->{ VAR };

Return current session.

	my $uri = this->{uri};
	this->{referer} = undef;

=cut
sub this()
{
	# XXX: correct but slow, replace with internal session ref
	return RSGet::Context->session();
}


=head2 get( URI, [OPTIONS], CALLBACK_SUB );

Send request to server (either GET or POST). Save data to memory.

	get $uri, post => { data => "to post" }, sub
	{
		EXECUTED ON SUCCESS;
		DATA IN $_;
	}

=cut
sub get($$@)
{
	_coverage();

	my $uri = _ref_check shift;
	my $code = _ref_check CODE => pop;

	...
}


=head2 download( URI, [OPTIONS], [FAIL_CALLBACK_SUB] );

Send request to server (either GET or POST). Save data to file.

	download $file_uri, post => { data => "to post" }, sub
	{
		EXECUTED ON FAILURE;
		# i.e. content type was text/*
	}

=cut
sub download($@)
{
	_coverage();

	my $uri = _ref_check shift;
	my $fallback;
	if ( @_ & 1 ) {
		$fallback = _ref_check CODE => pop;
	}

	...
}


=head2 sleep( SECONDS );

Set sleep timeout. Session will wait that many SECONDS before next
get/download request.

	sleep $wait_time;
	get $uri, sub { ... };

=cut
sub sleep($)
{
	_coverage();

	this->{sleep} = _val_check qr/-?\d+/ => shift;
}

=head2 click();

Return small random number. Used to simulate user clicking.

	sleep click;
	get $uri, sub { ... };

	sleep $wait_time + click;
	download $file_uri;

=cut
sub click()
{
	return RSGet::Common::irand( 2, 5 );
}


=head2 info( OPTIONS );

Save information about this download.
Will interrupt current session if only file information was requested.

	info
		# file name, in order of preference
		name => "exact file name",
		aname => "aproximate file name", # chars other than [A-Za-z0-9] may differ
		iname => "incomplete file name", # \0 denotes missing fragment
		ainame => "aproximate incomplete file name",

		# file size, in order of preference
		size => EXACT_SIZE, # in bytes
		asize => "aproximate size", # e.g. 100KB

		kilo => 1000, # if K/M/G are multiples of 1000, not 1024
		;

	info
		links => [ LIST, OF, LINKS ];

=cut
sub info(@)
{
	_coverage();

	my %info = @_;

	this->{info} = \%info;

	_abort() if this->{info_only} or $info{links};
}


=head2 error( TYPE => MESSAGE );

Die because of some error.

	error file_not_found => $1
		if />(File is missing: .*?)</;

=cut
sub error($$)
{
	_coverage();

	this->{error} = [ @_ ];
	_abort();
}


=head2 restart( SECONDS, REASON => MESSAGE );

Restart current session after SECONDS.

	restart( $2, free_limit => $1 )
		if /(Free limit reached.*must wait (\d+) seconds)/;

=cut
sub restart($$$)
{
	_coverage();

	my $time = _val_check qr/-?\d+/ => shift;

	...;

	_abort();
}


=head2 assert( SOMETHING );

Make sure operation was successfull.

	assert( /wait: (\d+)/ );
	my $wait = $1;

=cut
sub assert(@)
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


=head2 expect( SOMETHING )

Log operation and its value.

	if ( expect( CONDITION_1 )
			or expect( CONDITION_2 ) ) {
		...
	}

=cut
sub expect(@)
{
	my $success = 0;
	$success = 1 if wantarray ? @_ : $_[ $#_ ];

	_coverage( @_ );

	return wantarray ? @_ : $_[ $#_ ];
}


# INTERNAL: save session coverage information
sub _coverage
{
	my @c = caller 1;
	my $func = $c[3];
	$func =~ s/^RSGet::Plugin:://;
	print "coverage: '$func' called from '$c[1]:$c[2]'\n";
}


# INTERNAL: abort current session
sub _abort
{
	die [ abort => shift ];
}

1;

# vim: ts=4:sw=4:fdm=marker
