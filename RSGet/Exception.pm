package RSGet::Exception;
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

use constant {
	ARG_FORMAT => 0,
	ARG_ARGS => 1,
	ARG_PKG => 2,
};

=head1 package RSGet::Exception

Handle and compare exceptions.

=head2 die RSGet::Exception->new( PARENT, MSGFMT, [ARGS] );

Create an exception object. PARENT can be set to 1 or more if using a
trampoline sub to throw the exception.

=cut
sub new
{
	my $class = shift;
	my $parent = shift || 0;
	my $format = shift;

	my $self = [ $format, [@_], caller $parent ];
	bless $self, $class;
	return $self;
}


=head2 $@->pkg( PKG ); if ($@ le PKG) {}

Return true if exception is from package PKG.

=cut
sub pkg
{
	return shift->[ ARG_PKG ] eq shift;
}
use overload 'le' => \&pkg;


=head2 $@->msg( MSG ); if ($@ ge MSG) {}

Return true if exception message format is MSG.

=cut
sub msg
{
	return shift->[ ARG_FORMAT ] eq shift;
}
use overload 'ge' => \&msg;


=head2 $@->is( PKG, MSG );

Return true if exception is from package PKG and message format is MSG.

=cut
sub is
{
	my $self = shift;
	return
		$self->pkg( shift )
			and
		$self->msg( shift );
}


=head2 print "$@"; print $@->str();

Return as string interpolating all arguments.

=cut
sub str
{
	my $self = shift;
	return $self->[ ARG_PKG ] . ": " . sprintf $self->[ ARG_FORMAT ], @{ $self->[ ARG_ARGS ] };
}
use overload '""' => \&str;


=head2 $@->eq( PKGMSG ); ($@ eq PKGMSG);

Return true if "PKG: MSGFMT" Exception equals PKGMSG.

E.g.

=cut
sub eq
{
	my $self = shift;
	return $self->[ ARG_PKG ] . ": " . $self->[ ARG_FORMAT ] eq shift;
}
use overload 'eq' => \&eq;

=head2 USAGE
	my $eggs = 1;
	eval {
		package Omlet;
		die RSGet::Exception->new( 0, 'I need %d eggs', 2 )
			if $eggs < 2;
	};
	print "$@\n"; # prints "Omlet: I need 2 eggs\n"
	if ( $@ eq "Omlet: I need %d eggs" ) { # true
		warn "Buy more eggs\n";
	}
	if ( $@ =~ /^Omlet: I need (\d+) eggs$/ ) { # true
		warn "Buy more eggs, need $1\n";
	}

=cut

1;

# vim: ts=4:sw=4
