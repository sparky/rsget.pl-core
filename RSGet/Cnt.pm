package RSGet::Cnt;
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

use Fcntl ();
use constant {
	SEEK_CUR => Fcntl::SEEK_CUR(),
	SEEK_SET => Fcntl::SEEK_SET(),
	SEEK_END => Fcntl::SEEK_END(),
};

use POSIX ();
use constant {
	WNOHANG => POSIX::WNOHANG(),
};

1;

# vim: ts=4:sw=4:fdm=marker
