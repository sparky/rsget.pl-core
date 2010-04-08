package RSGet::AutoUpdate;
# This file is an integral part of rsget.pl downloader.
#
# 2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

# XXX: this file is a rough sketch, not functional

use strict;
use warnings;
use RSGet::Common;
use RSGet::DB;
use Digest::MD5 qw(md5_hex);
use URI::Escape;

def_settings(
	report_uri => {
		desc => "http path to rsget.pl report page.",
		default => 'http://rsget.pl/_auto/report.php',
		allowed => qr{https?://.{4,}|},
	},
);

sub report
{
	my %problem = @_;

	$problem{context} = join "&", map {
		uri_escape( $_ ) . "=" . md5_hex cat $INC{ $_ }
	} sort keys %INC;

	RSGet::Curl::new(
		setting( "report_uri" ),
		\&process,
		post => \%problem,
	);

}

sub process
{
	
}

1;

# vim: ts=4:sw=4
