package RSGet::Curl;
# This file is an integral part of rsget.pl downloader.
#
# 2009-2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
use RSGet::Common;
use WWW::Curl::Easy 4.00;
use WWW::Curl::Multi;
use URI::Escape;

def_settings(
	user_agent => {
		desc => "User agent header string sent to server.",
		default => 'Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.9.0.10) Gecko/2009042316 Firefox/3.0.10',
	}
);

# Default headers sent to server.
my %curl_http_headers = (
	accept => 'text/xml,application/xml,application/xhtml+xml,text/html;q=0.9,text/plain;q=0.8,image/png,*/*;q=0.5',
	accept_charset => 'ISO-8859-1,utf-8;q=0.7,*;q=0.7',
	accept_language => 'en-us,en;q=0.5',
);

# values hardcoded because WWW::Curl::Easy does not export them
my %curl_proxy_type = (
	http => 0,		# CURLPROXY_HTTP
	http10 => 1,	# CURLPROXY_HTTP_1_0
	socks4 => 4,	# CURLPROXY_SOCKS4
	socks4a => 6,	# CURLPROXY_SOCKS4a
	socks5 => 5,	# CURLPROXY_SOCKS5
	socks5host => 7,	# CURLPROXY_SOCKS5_HOSTNAME
);

# *** TODO ***
# use mortal objects for storing curl containers
#
# list of ccs active right now
my %active_curl;

# we run everything through this object
my $curl_multi = new WWW::Curl::Multi;

# new {{{ start downloading new URI 
# options:
# - interface
# - referer
# - cookie_file
# - headers
# - post
# - head
# - file_handle
sub new
{
	my $uri = shift;
	my $callback = shift;
	my %opts = @_;

	my $curl = new WWW::Curl::Easy;

	my $id = 1;
	++$id while exists $active_curl{ $id };
	$active_curl{ $id } = 0;

	# curl container
	my $cc = {
		curl => $curl,
		id => $id,
		last_update => time,
		callback => $callback,
		head => "",
	};

	# we need this ID to track curl back to $cc ($active_curl{ $id })
	$curl->setopt( CURLOPT_PRIVATE, $id );

	if ( $opts{interface} ) {
		foreach my $if ( split /;+/, $opts{interface} ) {
			if ( $if =~ /^([a-z0-9]+)=(\S+)(:(\d+))?$/ ) {
				my ($tn, $host, $port) = ($1, $2, $4);
				if ( my $type = $curl_proxy_type{ $tn } ) {
					$curl->setopt( CURLOPT_PROXYTYPE, $type );
					$curl->setopt( CURLOPT_PROXY, $host );
					$curl->setopt( CURLOPT_PROXYPORT, $port )
						if $port;
				} else {
					warn "Unrecognized proxy type '$tn' in '$opts{interface}'\n";
				}
			} elsif ( $if =~ /^\S+\.\S+$/ ) {
				$curl->setopt( CURLOPT_INTERFACE, $if );
			} else {
				warn "Unrecognized interface string '$if' in '$opts{interface}'\n";
			}
		}
	}

	$curl->setopt( CURLOPT_URL, $uri );
	$curl->setopt( CURLOPT_REFERER, $opts{referer} )
		if defined $opts{referer};

	if ( my $cf = $opts{cookie_file} ) {
		$curl->setopt( CURLOPT_COOKIEJAR, $cf );
		$curl->setopt( CURLOPT_COOKIEFILE, $cf );
	}

	$curl->setopt( CURLOPT_MAXREDIRS, 10 );
	$curl->setopt( CURLOPT_FOLLOWLOCATION, 1 );

	$curl->setopt( CURLOPT_HTTPHEADER,
		_make_headers( $opts{headers} || {} )
	);
	$curl->setopt( CURLOPT_ENCODING, 'gzip,deflate' );
	$curl->setopt( CURLOPT_CONNECTTIMEOUT, 20 );
	$curl->setopt( CURLOPT_SSL_VERIFYPEER, 0 );

	if ( my $post = $opts{post} ) {
		$curl->setopt( CURLOPT_POST, 1 );
		if ( ref $post ) {
			if ( ref $post eq "HASH" ) {
				$post = join "&",
					map { uri_escape( $_ ) . "=" . uri_escape( $post->{$_} ) }
					sort keys %$post;
			} else {
				warn "POST is neither string nor HASH\n";
			}
		}
		$curl->setopt( CURLOPT_POSTFIELDS, $post );
		$curl->setopt( CURLOPT_POSTFIELDSIZE, length $post );
	}

	$curl->setopt( CURLOPT_HEADERFUNCTION, \&_write_head );
	$curl->setopt( CURLOPT_WRITEHEADER, $cc );

	if ( $opts{head} ) {
		$curl->setopt( CURLOPT_NOBODY, 1 );
	} else {
		$curl->setopt( CURLOPT_WRITEFUNCTION, \&_write_body );
		$curl->setopt( CURLOPT_WRITEDATA, $cc );
	}

	if ( my $fw = $opts{file_handle} ) {
		$cc->{file_handle} = $fw;
		if ( my $start = $fw->start_at() ) {
			$curl->setopt( CURLOPT_RANGE, "$start-" );
		}
	}

	$active_curl{ $id } = $cc;
	$curl_multi->add_handle( $curl );
}
# }}}

sub _make_headers # {{{
{
	my $add = shift;
	my %headers = %curl_http_headers;
	$headers{user_agent} = setting( "user_agent" );
	$headers{ keys %$add } = values %$add;

	my @headers;
	foreach my $h ( sort keys %headers ) {
		my $hout = join "-", map { ucfirst lc $_ } split /[_-]+/, $h;
		push @headers, $hout . ": " . $headers{ $h };
	}

	return \@headers;
}
# }}}

sub _write_head # {{{
{
	my ( $chunk, $cc ) = @_;
	$cc->{last_update} = time;
	$cc->{head} .= $chunk;
	return length $chunk;
}
# }}}

sub _write_body # {{{
{
	my ( $chunk, $cc ) = @_;
	$cc->{last_update} = time;
	if ( my $fw = $cc->{file_handle} ) {
		$fw->push( $chunk );
	} else {
		$cc->{body} = "" unless defined $cc->{body};
		$cc->{body} .= $chunk;
	}
	return length $chunk;
}
# }}}

sub finish # {{{
{
	my $id = shift;
	my $error_code = shift;

	my $cc = $active_curl{ $id };
	delete $active_curl{ $id };

	my $curl = $cc->{curl};
	delete $cc->{curl}; # remove circular dep

	$cc->{eurl} = $curl->getinfo( CURLINFO_EFFECTIVE_URL );
	$cc->{content_type} = $curl->getinfo( CURLINFO_CONTENT_TYPE );
	$cc->{error} = $curl->errbuf;

	# destroy curl before destroying getter
	$curl = undef;

	# TODO: fix this
	if ( $error_code ) {
		#warn "error($err): $error\n";
		warn "ERROR($error_code): $cc->{error}"
			if $error_code ne "aborted";
		if ( $cc->{error} =~ /Couldn't bind to '(.*)'/
				or $cc->{error} =~ /bind failed/ ) {
			#my $if = $get_obj->{_outif};
			#RSGet::Dispatch::remove_interface( $if, "Interface $if is dead" );
			#$get_obj->{_abort} = "Interface $if is dead";

			#RSGet::Hook::dispatch( "dead_interface", undef, interface => $if );
		} elsif ( $cc->{error} =~ /transfer closed with (\d+) bytes remaining to read/ ) {
			#RSGet::Dispatch::mark_used( $get_obj );
			#$get_obj->{_abort} = "PARTIAL " . donemsg( $supercurl );
		} elsif ( $error_code eq "aborted" ) {

		} else {
			#$get_obj->log( "ERROR($error_code): $error" );
		}
		#$get_obj->problem();
		#return undef;
	}

	my $cb = $cc->{callback};
	&$cb( $error_code, $cc );
}
# }}}

sub maybe_abort # {{{
{
	my $time = time;
	my $stall_time = $time - 120;
	foreach my $id ( keys %active_curl ) {
		my $cc = $active_curl{ $id };
		#my $get_obj = $supercurl->{get_obj};
		#if ( $get_obj->{_abort} ) {
		#	my $curl = $supercurl->{curl};
		#	$curl_multi->remove_handle( $curl );
		#	finish( $id, "aborted" );
		#}
		if ( $cc->{last_update} < $stall_time ) {
			my $curl = $cc->{curl};
			$curl_multi->remove_handle( $curl );
			finish( $id, "timeout" );
		}
	}
}
# }}}

sub perform # {{{
{
	my $running = scalar keys %active_curl;
	return unless $running;
	my $act = $curl_multi->perform();
	return if $act == $running;

	while ( my ($id, $rv) = $curl_multi->info_read() ) {
		next unless $id;

		finish( $id, $rv );
	}
}
# }}}

1;

# vim: ts=4:sw=4:fdm=marker
