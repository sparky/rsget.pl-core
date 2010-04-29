#!/usr/bin/perl
# This file is an integral part of rsget.pl downloader.
#
# 2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
use RSGet::Control::FileWriter;


my $file_name = "file.out";
my $file_size = 453_564_234;


sub file
{
	my $pos = shift;
	my $file = RSGet::Control::FileWriter::file_get( $file_name, $file_size );

	return new RSGet::Control::FileWriter $file, $pos;
}

my @files;
push @files, file( 0 );
push @files, file( 110_000_001 );
push @files, file( 220_000_002 );
push @files, file( 330_000_003 );

my $data = "\001" x 4000;
my $pos = 0;
while ( ++$pos < 27000 ) {
	foreach my $f ( @files ) {
		$f->push( $data );
	}
}


# vim: ts=4:sw=4:fdm=marker
