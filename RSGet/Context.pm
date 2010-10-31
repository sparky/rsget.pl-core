package RSGet::Context;
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
use List::Util ();

# current context stack
my @current;

# create new context
sub new
{
	my $class = shift;

}

# clone context and restrict some options
sub child
{
	my $parent = shift;

}

# set some context
sub set
{
	my $self = shift;

}

# return topmost context
sub top
{
	my $class = shift;

	return unless @current;
	return $current[ $#current ];
}

# push context, execute function, pop context
sub wrap
{
	my $self = shift;
	my $func = shift;

	push @current, $self;
	eval {
		&$func;
	};
	if ( $@ ) {
		warn "RSGet::Context::wrap function eval failed: $@\n";
	}
	pop @current;
}

# allowed context variables
#
# user - user that is actually downloading; session/file owner
# file - destination file
# plugin - getter information
# session - download session
# interface - user network interface
my @context_variables = qw(user file plugin session interface);

sub is_context
{
	my $class = shift;
	my $var = shift or return undef;

	return List::Util::first { $var eq $_ } @context_variables;
}

sub get
{
	my $class = shift;
	my $var = shift;

	return unless @current;
	return $current[ $#current ]->{ $var };
}

# create shortcuts
foreach ( @context_variables ) {
	eval "sub $_ { splice \@_, 1, 0, '$_'; goto \\&get; }";
}


1;

# vim: ts=4:sw=4:fdm=marker
