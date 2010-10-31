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

=head1 RSGet::Context -- context sensitive information

This is used to set and restrict context information (like user - owner
of the download).

=head2 used context variables

=over

=item user

user that is actually downloading; session/file owner

=item file

destination file

=item plugin

getter information

=item session

download session

=item interface

user network interface

=back

=cut

my @context_variables = qw(user file plugin session interface);


# current context stack
my @current;

=head2 my $ctxt = RSGet::Context->new( [OPTIONS] );

Create new context.

=cut
sub new
{
	my $class = shift;

}

=head2 my $child_ctxt = $parent_ctxt->child( [OPTIONS] );

Clone context and restrict some options.

=cut
sub child
{
	my $parent = shift;

}

=head2 $ctxt->set( OPTIONS );

Set some context options.

=cut
sub set
{
	my $self = shift;

}

=head2 my $ctxt = RSGet::Context->top();

returns topmost context

=cut
sub top
{
	return unless @current;
	return $current[ $#current ];
}

=head2 $ctxt->wrap( SUB. [ARGUMENTS] );

Push $ctxt on top of context stack.
Execute SUB.
Pop context from the stack.

=cut
sub wrap
{
	my $self = shift;
	my $func = shift;

	my @ret;

	push @current, $self;
	eval {
		if ( wantarray ) {
			@ret = &$func;
		} else {
			@ret = scalar &$func;
		}
	};
	if ( $@ ) {
		warn "RSGet::Context::wrap function eval failed: $@\n";
	}
	pop @current;

	return @ret;
}

=head2 RSGet::Context->is_context( NAME );

Return true if NAME is a correct context variable.

=cut
sub is_context
{
	my $class = shift;
	my $var = shift or return undef;

	return List::Util::first { $var eq $_ } @context_variables;
}

=head2 my $value = RSGet::Context->get( NAME );

Get topmost context information.

=cut
sub get
{
	my $class = shift;
	my $var = shift;

	return unless @current;
	return $current[ $#current ]->{ $var };
}

=head2 my $value = RSGet::Context->NAME();

Shortcut for my $value = RSGet::Context->get( NAME );

=cut
foreach ( @context_variables ) {
	eval "sub $_ { splice \@_, 1, 0, '$_'; goto \\&get; }";
}


1;

# vim: ts=4:sw=4:fdm=marker
