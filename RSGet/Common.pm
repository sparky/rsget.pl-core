package RSGet::Common;
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

1;
__END__

use vars qw(@ISA @EXPORT @EXPORT_OK);

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(user file plugin session interface);
@EXPORT_OK = qw();

# user that is actually downloading; session/file owner
sub Cuser()
{
	require RSGet::User;
	return $RSGet::User::current;
}

# destination file
sub Cfile()
{
	require RSGet::File;
	return $RSGet::File::current;
}

# getter information
sub Cplugin()
{
	require RSGet::Plugin;
	return $RSGet::Plugin::current;
}

# download session
sub Csession()
{
	require RSGet::Session;
	return $RSGet::Session::current;
}

# user network interface
sub Cinterface()
{
	require RSGet::Interface;
	return $RSGet::Interface::current;
}

1;

# vim: ts=4:sw=4:fdm=marker
