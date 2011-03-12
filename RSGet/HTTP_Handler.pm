package RSGet::HTTP_Handler;
# This file is an integral part of rsget.pl downloader.
#
# Copyright (C) 2011	Przemysław Iskra <sparky@pld-linux.org>
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
use RSGet::Cnt;
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
		throw '404: File "%s" not found', $file;
	}


	my $skip = 0;
	my $size = -s $file;
	my $end = $size - 1;

	my $h = $req->{h_in};
	if ( exists $h->{range} and $h->{range} =~ /bytes=(\d+)-(\d+)?/ ) {
		$skip = 0+$1;
		$end = $2 || $size - 1;
		my $cr = sprintf "bytes %d-%d/%d", $skip, $end, $size;
		$size = $end - $skip + 1;
		$req->{h_out}->{content_range} = $cr;
		$req->{code} = 206; # partial content
	}

	$req->{h_out}->{content_length} = $size;
	$req->{h_out}->{content_type} = $ct;
	return _readfile( $file, $skip, $end + 1 );
}

sub _readfile
{
	my $path = shift;
	my $skip = shift || 0;

	throw '500: cannot read file %s', $path
		unless -r $path;
	
	my $size = -s $path;
	my $end = shift || $size;
	throw '416: cannot seek past end of file'
		if $skip >= $size;

	throw '416: cannot read past end of file'
		if $end > $size;

	throw '416: cannot end before start position'
		if $end <= $skip;

	my $toread = $end - $skip;

	# if file is small we read it directly and return the data
	if ( $toread <= BLOCK_SIZE ) {
		open my $fin, "<", $path;
		sysseek $fin, $skip, RSGet::Cnt::SEEK_SET
			if $skip;

		sysread $fin, my ( $buf ), $toread;
		return $buf;
	}

	# for large files we create a file-reading sub process
	# and return an iterator
	# NOTE: sub process is required because reading files always blocks,
	#       but we don't want it to block

	pipe my $rh, my $wh;
	my $pid = fork();
	unless ( defined $pid ) {
		throw '500: cannot fork';
	}

	if ( $pid ) {
		# parent
		close $wh;

		my $io = RSGet::IO->new( $rh );
		return sub {
			return $io->read( BLOCK_SIZE );
		};
	}

	# child
	# TODO: maybe ionice ?

	close $rh;
	local $SIG{__DIE__} = sub {
		exec "false"
			or 1;

		require POSIX;
		POSIX::_exit( 0 );
	};

	open my $fin, "<", $path;
	sysseek $fin, $skip, RSGet::Cnt::SEEK_SET
		if $skip;

	my $buf;
	while ( $toread > BLOCK_SIZE ) {
		sysread $fin, $buf, BLOCK_SIZE;
		syswrite $wh, $buf;
		$toread -= BLOCK_SIZE;
	}
	sysread $fin, $buf, $toread;
	syswrite $wh, $buf;

	# must exit without calling any destructors
	exec "true"
		or die;
}

1;

# vim: ts=4:sw=4:fdm=marker
