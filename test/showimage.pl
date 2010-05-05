#!/usr/bin/perl
#
# 2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#
# This code may be used to display captcha images on console.
#
# Requires: 256 color terminal with UTF-8 char coding.
#
use strict;
use warnings;
use RSGet::Term::Image;
use IO::Handle;
use Term::Size;

foreach my $file ( @ARGV ) {
	my ( $w, $h ) = Term::Size::chars();
	$h--;
	my $lines = RSGet::Term::Image::img2lines( $file, $w, $h, 0 );
	next unless $lines;

	print "\033[0;0f",
		( join "\033[0K\n", @$lines ),
		"\033[0K\n\033[0J$file";
	STDOUT->flush();

	sleep 1;
}
