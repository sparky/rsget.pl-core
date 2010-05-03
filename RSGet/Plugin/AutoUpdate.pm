package RSGet::Plugin::AutoUpdate;
# This file is an integral part of rsget.pl downloader.
#
# 2009-2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
use RSGet::Config;
use RSGet::Curl;
use RSGet::SQL;
#use RSGet::Plugin::Plugin;
use Digest::MD5 qw(md5_hex);

RSGet::Config::register_settings(
	plugin_uri => {
		desc => "http path to rsget.pl plugins updater.",
		default => 'http://rsget.pl/download/plugins.php',
		allowed => qr{https?://.{4,}/.+},
	},
);

sub update
{
	my $arr = RSGet::SQL::dbh->selectall_arrayref(
		"SELECT name, md5 FROM ${RSGet::SQL::prefix}plugin"
	);
	my %plugins = map { $_->[0], $_->[1] } @$arr;

	new RSGet::Curl
		RSGet::Config::get( undef, "plugin_uri" ),
		\&_process,
		post => \%plugins;
	
	warn "Updating plugins.\n";
	
	return 1;
}

sub _process
{
	my $obj = shift;
	return if $obj->{error};

	my $time = time;

	local $_;
	$_ = $obj->{body};

	my $updated = 0;

	s/^\s*<!--.*?-->\s*//s;

	while ( s/\s*<plugin:([0-9a-f]+|missing)\s+name="(\S+)">//s ) {
		my $md5 = $1;
		my $name = $2;
		s#^(.*?)</plugin:$md5>##s;
		my $body = $1;

		if ( $md5 eq "missing" ) {
			RSGet::SQL::del( "plugin", { name => $name } );
		} else {
			my $m = md5_hex( $body );
			if ( $m ne $md5 ) {
				warn "Error while updating plugin $name: md5 does not match.\n";
			} else {
				#my @plugin = RSGet::Plugin::preprocess( $name, $body );
				RSGet::SQL::set( "plugin", { name => $name },
					{ md5 => $md5, body => $body, time => $time } );
				$updated++;
			}
		}
	}

	warn "Updated $updated plugins.\n";
	return;
}

1;

# vim: ts=4:sw=4:fdm=marker
