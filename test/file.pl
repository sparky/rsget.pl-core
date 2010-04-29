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

my $f1 = file( 0 );
my $f2 = file( 110_000_001 );
my $f3 = file( 220_000_002 );
my $f4 = file( 330_000_003 );

my $data1 = "\001" x 4001;
my $data2 = "\002" x 4002;
my $data3 = "\003" x 4003;
my $data4 = "\004" x 4004;
my $pos = 0;
while ( ++$pos < 27495 ) {
	$f1->push( $data1 );
	$f2->push( $data2 );
	$f3->push( $data3 );
	$f4->push( $data4 );

	print "1: $f1->{position}\n";
	print "2: $f2->{position}\n";
	print "3: $f3->{position}\n";
	print "4: $f4->{position}\n";
}


# vim: ts=4:sw=4:fdm=marker
