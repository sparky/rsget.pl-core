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

=head1 External interface - can be used in config file.

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
# Context with largest index is on top. Only this one is used.
my @current;


=head2 my $value = RSGet::Context->get( NAME );

Get context information. NAME is one of context variables.

=cut
sub get
{
	my $class = shift;
	my $key = shift;

	die "RSGet::Context::get: '$key' is not a valid context variable\n"
		unless RSGet::Context->is_context( $key );

	return unless @current;
	return $current[ $#current ]->{ $key };
}


=head2 my $value = RSGet::Context->NAME();

Shortcut for my $value = RSGet::Context->get( NAME );

=cut
foreach ( @context_variables ) {
	eval "sub $_ { splice \@_, 1, 0, '$_'; goto \\&get; }";
}



=head1 Internal interface.

=head2 RSGet::Context->is_context( NAME );

Return true if NAME is a correct context variable.

=cut
sub is_context
{
	my $class = shift;
	my $var = shift or return;

	return List::Util::first { $var eq $_ } @context_variables;
}


=head2 my $ctxt = RSGet::Context->new( [OPTIONS] );

Create new context.

=cut
sub new
{
	my $class = shift;

	my $self = {};
	bless $self, $class;

	return $self->set( @_ );
}


=head2 my $child_ctxt = $parent_ctxt->child( [OPTIONS] );

Clone context and restrict some options.

=cut
sub child
{
	my $parent = shift;

	my $child = RSGet::Context->new( %$parent );
	return $child->set( @_ );
}


=head2 $ctxt->set( OPTIONS );

Set some context options.

=cut
sub set
{
	my $self = shift;

	while ( my ( $key, $value ) = splice @_, 0, 2 ) {
		die "RSGet::Context::set: '$key' is not a valid context variable\n"
			unless RSGet::Context->is_context( $key );

		die "RSGet::Context::set: context already defines '$key' with different value\n"
			if exists $self->{$key} and $self->{$key} ne $value;

		$self->{$key} = $value;
	}

	return $self;
}


=head2 my $ctxt = RSGet::Context->top();

returns topmost context

=cut
sub top
{
	return unless @current;
	return $current[ $#current ];
}


=head2 $ctxt->wrap( SUB, [ARGUMENTS] );

Push $ctxt on top of context stack.
Execute SUB( ARGUMENTS ).
Pop context from the stack.

=cut
sub wrap
{
	my $self = shift;
	my $func = shift;

	my @ret;

	push @current, $self;

	# wrapped in eval to make sure we pop the context
	eval {
		if ( wantarray ) {
			@ret = &$func;
		} else {
			$ret[0] = &$func;
		}
	};

	pop @current;

	if ( $@ ) {
		# Do not handle $@ here because we don't know how to handle it.
		# Just transmit the last words.
		die $@;
	}

	return @ret;
}

1;

# vim: ts=4:sw=4:fdm=marker
