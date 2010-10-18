package RSGet::Plugin::Get::Rapidshare;
# Test plugin for new rsget.pl.
#
# 2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
use RSGet::Plugin v0.01;
use RSGet::Common;

plugin
	name => "RapidShare",
	short => "RS",
	web => "http://rapidshare.com/",
	tos => "http://rapidshare.com/#!rapidshare-ag/rapidshare-ag_agb";


uri qr{(?:rs[a-z0-9]+\.)?rapidshare\.com/files/\d+/.+};
uri qr{(?:rs[a-z0-9]+\.)?rapidshare\.com/?#!download\|\d+\|\d+\|.+?\|\d+};
uri qr{(?:rs[a-z0-9]+\.)?rapidshare\.de/files/\d+/.+};
uri qr{(?:rs[a-z0-9]+\.)?rapidshare\.de/?#!download\|\d+\|\d+\|.+?\|\d+};

unify {
	# don't change anything
 	return $_;
};
 
start {
	my $uri = shift;

	get $uri, \&main_page;
	sub main_page
	{
		error( file_not_found => $1 )
			if /^ERROR: (.*)/
				and substr( $1, 0, 16 ) ne "You need to wait"
				and substr( $1, 0, 17 ) ne "You need RapidPro";

		if ( m{<script type="text/javascript">location="(.*?)"} ) {
			$session->{_referer} = undef;
			get "http://rapidshare.com$1", \&main_page;
		}

		assert( my ( $id, $name, $size ) = $session->{_referer} =~ m{#!download\|\d+\|(\d+)\|(.+?)\|(\d+)} );
		info( name => $name, asize => $size."KB" );
	
		click "http://api.rapidshare.com/cgi-bin/rsapi.cgi?sub=download_v1&try=1&fileid=$id&filename=$name", sub
		{
			delay( 0, multidownload => $1 )
				if /^(ERROR: You need RapidPro.*)/;
			restart( $2, "free limit reached: $1" )
				if /^(ERROR: You need to wait (\d+) seconds.*)/;

			assert( my ( $host, $dlauth, $wait ) = m{DL:(.*?),([0-9A-F]+?),(\d+)} );

			wait $wait, "starting download", sub {
				download "http://$host/cgi-bin/rsapi.cgi?sub=download_v1&dlauth=$dlauth&bin=1&fileid=$id&filename=$name",
					\&handle_download_fail;
			};
		};
	};
};

# vim: filetype=perl:ts=4:sw=4
