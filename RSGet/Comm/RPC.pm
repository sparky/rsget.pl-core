package RSGet::Comm::RPC;
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
use RSGet::Common qw(throw args REQUIRED);


=head1 RSGet::Comm::RPC -- sub definitions for RPC servers

=cut
use constant {
	L_GUEST => 0x01,
	L_USER => 0x02,
	L_SUPER => 0x04,
};

my %subs;
my $level;
sub rpc($&)
{
	my $name = shift;
	my $sub = shift;

	$subs{ $name } = $level;

	no strict 'refs';
	*$name = $sub;
}


$level = L_GUEST;

# test sub, return file contents
rpc file => sub
{
	my $class = shift;

	my %args = args {
		path => REQUIRED 'string',
	}, @_;

	my $path = $args{path};
	throw 'file "%s" not found', $path
		unless -r $path;

	my %ret;
	@ret{ qw(dev inode mode nlink uid gid rdev size atime mtime ctime blksize
		blocks) } = stat $path;

	open my $fin, '<', $path
		or throw 'cannot open file "%s": %s', $path, $!;
	sysread $fin, $ret{data}, 64 * 1024;

	return \%ret;
};

# return server information
rpc info => sub
{
	return {
		version => 'unknown',
		time => time(),
	};
};


# login using username and password
rpc login => sub
{
	my %args = args {
		user => REQUIRED 'string',
		pass => REQUIRED 'string',
	}, @_;

	throw 'unimplemented';
};


# relogin using cookie
rpc cookie => sub
{
	my %args = args {
		value => REQUIRED 'string',
	}, @_;

	throw 'unimplemented';
};


$level = L_USER;
rpc active => sub
{
	throw 'unimplemented';
};
rpc captcha_list => sub
{
	throw 'unimplemented';
};
rpc captcha_image => sub
{
	throw 'unimplemented';
};
rpc set => sub
{
	throw 'unimplemented';
};
rpc get => sub
{
	throw 'unimplemented';
};
rpc uri_list => sub
{
	throw 'unimplemented';
};
rpc uri_add => sub
{
	throw 'unimplemented';
};


1;

# vim: ts=4:sw=4:fdm=marker
