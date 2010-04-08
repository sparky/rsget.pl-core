package RSGet::AutoUpdate;
# This file is an integral part of rsget.pl downloader.
#
# 2009-2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

# XXX: this file is a rough sketch, not functional

use strict;
use warnings;
use RSGet::Tools;
use RSGet::DB;
use RSGet::Plugin;
use Digest::MD5 qw(md5_hex);

def_settings(
	plugin_uri => {
		desc => "http path to rsget.pl plugins updater.",
		default => 'http://rsget.pl/download/plugins.php',
		allowed => qr{https?)://.{4,}},
	},
);

sub update
{
	my %plugins = RSGet::DB::get( "plugins", [qw(name md5)] );

	RSGet::Curl::new(
		setting( "plugin_uri" ),
		\&process,
		post => \%plugins,
	);

}

sub process
{
	s/^\s*<!--.*?-->\s*//s;

	while ( s/\s*<plugin:([0-9a-f]+|missing)\s+name="(\S+)">//s ) {
		my $md5 = $1;
		my $name = $2;
		s#^(.*?)</plugin:$md5>##s;
		my $body = $1;

		if ( $md5 eq "missing" ) {
			RSGet::DB::del( "plugins", { name => $name } );
		} else {
			my $m = md5_hex( $body );
			if ( $m ne $md5 ) {
				print "$name Error\n";
				# do nothing
			} else {
				print "$name OK\n";
				my @plugin = RSGet::Plugin::preprocess( $name, $body );
				RSGet::DB::set( "plugins", [qw(name md5 body)], \@plugin );
			}
		}
	}

}

1;

# vim: ts=4:sw=4
