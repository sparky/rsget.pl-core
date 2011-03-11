package RSGet::HTTP_Request;
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

sub _readfile
{
	my $path = shift;
	my $skip = shift || 0;

	throw 'cannot read file %s', $path
		unless -r $path;
	
	throw 'cannot skip %d bytes', $skip
		if $skip >= -s $path;

	my $skipblocks = int ( $skip / BLOCK_SIZE );
	my $skipread = $skip - $skipblocks * BLOCK_SIZE;

	open my $fin, "-|", "dd", "if=$path", "bs=" . BLOCK_SIZE, "skip=" . $skipblocks
		or throw 'cannot run dd command';

	my $io = RSGet::IO->new( $fin );

	if ( not $skipread ) {
		return sub {
			return $io->read( BLOCK_SIZE );
		};
	}
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
