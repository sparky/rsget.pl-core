package RSGet::HTTP_Handler;
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
use RSGet::Common qw(throw);
use RSGet::IO;

use constant {
	BLOCK_SIZE => 32 * 1024,
};

my @handlers = (
	[ qr#/file/.*#, \&_send_file ],
);

sub get
{
	my $class = shift;
	my $filename = shift;

	foreach my $hdl ( @handlers ) {
		my $file = $hdl->[0];
		if ( ref $file eq "Regexp" ) {
			next unless $filename =~ /^$file$/;
		} else {
			next unless $filename eq $file;
		}
		return $hdl;
	}

	return undef;
}

sub _send_file
{
	my $req = shift;
	my $ct = shift || 'application/octet-stream';

	my $file = $req->{file};
	$file =~ s#^/file/##;

	unless ( -r $file and -f $file ) {
		$req->{code} = 404;
		return "File '$file' not found\n";
	}

	$req->{h_out}->{content_length} = -s $file;
	$req->{h_out}->{content_type} = $ct;
	return _readfile( $file );
}

sub _readfile
{
	my $path = shift;
	my $skip = shift || 0;

	throw 'cannot read file %s', $path
		unless -r $path;
	
	my $size = -s $path;
	my $end = shift || $size;
	throw 'cannot skip %d bytes', $skip
		if $skip >= $size;

	throw 'cannot end after file end'
		if $end > $size;

	throw 'cannot end before skip'
		if $end < $skip;

	my $skipblocks = int ( $skip / BLOCK_SIZE );
	my $skipread = $skip - $skipblocks * BLOCK_SIZE;
	my $countblocks = int ( ($end - $skip) / BLOCK_SIZE ) + 1;

	open DEV_NULL, ">", "/dev/null";

	require IPC::Open3;
	my $pid = IPC::Open3::open3( "<&DEV_NULL", my $chout, ">&DEV_NULL",
			"dd",
				"if=$path",
				"bs=" . BLOCK_SIZE,
				"skip=" . $skipblocks,
				"count=" . $countblocks
		);
	throw 'cannot run dd command' unless $pid;
	close CHIN;
	close CHERR;

	my $io = RSGet::IO->new( $chout );

	if ( not $skipread and $end == $size ) {
		return _readfile_simple( $io );
	} else {
		return _readfile_advanced( $io, $skipread, $end - $skip );
	}
}

sub _readfile_simple
{
	my $io = shift;
	return sub {
		return $io->read( BLOCK_SIZE );
	};
}

sub _readfile_advanced
{
	my ( $io, $skipread, $toread ) = @_;
	return sub {
		local $_ = $io->read( BLOCK_SIZE );
		if ( $skipread ) {
			my $s = $skipread;
			$skipread = 0;
			return substr $_, $s;
		}
		return $_;
	};
}


1;

# vim: ts=4:sw=4:fdm=marker
