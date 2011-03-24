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

=head1 RSGet::Common -- common functions

This package implements some very common functions.

=head2 use RSGet::Common qw(FUNCTIONS);

Package is able to export all of its functions, but they must be listed
explicitly.

=cut
sub import
{
	my $callpkg = caller 0;
	my $pkg = shift || __PACKAGE__;

	no strict 'refs';
	foreach ( @_ ) {
		die "$pkg: has no sub named '$_'\n"
			unless $pkg->can( $_ );

		# export sub
		*{"$callpkg\::$_"} = \&{"$pkg\::$_"};
	}
}


=head2 if ( DEBUG ) { ... }

Return true if debugging.

=cut
use constant DEBUG => 1;


=head2 my $val = irand( [MIN], MAX );

Returns an integer in [MIN, MAX) interval. MIN is zero if ommited.

=cut
sub irand($;$)
{
	my $arg = shift;
	return int rand $arg unless @_;

	return int ( $arg + rand ( (shift) - $arg ) );
}


=head2 confess( "message" );

Die babbling.

=cut
sub confess($)
{
	eval {
		require Carp;
	};
	if ( $@ ) {
		my $msg = shift;
		die "Died because: $msg\n" .
			"Moreover, Carp cannot be loaded to display full backtrace.\n";
	} else {
		goto \&Carp::confess;
	}
}


=head2 throw( MSGFMT, [ARGS] );

Die generating an exception object, which will look like
"CALLER_PACKAGE: formatted message".

=cut
sub throw($@)
{
	require RSGet::Exception;
	my $e = RSGet::Exception->new( 1, @_ );
	warn "$e\n" if DEBUG;
	die $e;
}


=head2 my $val = ref_check TYPE => $argument, 'Option "name"';

Make sure argument is a ref to TYPE. Die if it isn't.

	my $val = ref_check undef => $argument;

Die if argument is a ref.

=cut
sub ref_check($$;$)
{
	my $type = shift || "";
	$type = "" if $type eq "undef";
	my $var = shift;
	my $name = shift || "Argument";

	my $ref = ref $var;
	unless ( $ref eq $type ) {
		@_ = ( "$name should contain a '$type' ref, but it is '$ref'\n" );
		goto \&throw;
	}

	return $var;
}


=head2 my $val = val_check qr/PATTERN/ => $argument;

Make sure argument matches PATTERN. Die if it doesn't.

=cut
sub val_check($$;$)
{
	my $match = shift;
	my $var = shift;
	my $name = shift || "Argument";

	my $ref = ref $var;
	unless ( $ref eq "" ) {
		@_ = ( "$name should be a scalar, but it is a ref to '$ref'\n" );
		goto \&throw;
	}

	unless ( $var =~ m/^$match$/ ) {
		@_ = ( "$name '$var' does not match pattern: $match\n" );
		goto \&throw;
	}
}


=head2 my %opts = args { name => REQUIRED 'ARRAY', bar => qr/\d+/ }, @_;

Make sure all arguments are of correct type. REQUIRED marks argument that must
be set. Arguments that are not on the list are not allowed.

Usage:

	my %opts = args {
		some_arrayref => REQUIRED 'ARRAY',
		some_scalarref => 'SCALAR',
		scalar_not_ref => 'string',
		hashref => 'HASH',
		subref => 'CODE',
		handle => 'GLOB',
		refref => 'REF',
		regexp => 'Regexp',
		number => REQUIRED qr/\d+/,
		name => qr/\S+/,
		}, @_;

=cut
sub args($@)
{
	my $defs = shift;

	my @error_fmt;
	my @error_data;

	push @error_fmt, 'odd number of arguments'
		if scalar @_ % 2;

	my %opts;
	while ( my ( $key, $value ) = splice @_, 0, 2 ) {

		# add to output options
		$opts{ $key } = $value;

		# is it on our list ?
		unless ( exists $defs->{ $key } ) {
			push @error_fmt, 'argument "%s" is not allowed';
			push @error_data, $key;
			next;
		}
		my $type = $defs->{ $key };
		if ( ref $type and ref $type eq 'REQUIRED' ) {
			$type = $$type;
		}
		if ( ref $type ) {
			if ( ref $type eq 'Regexp' ) {
				if ( ref $value ) {
					push @error_fmt, 'argument "%s" should be a scalar, but is %sref';
					push @error_data, $key, ref $value;
					next;
				} else {
					unless ( $value =~ m/^$type$/ ) {
						push @error_fmt, 'argument "%s" should match /^%s$/, but is "%s"';
						push @error_data, $key, $type, $value;
						next;
					}
				}
			} else {
				throw 'cannot handle argument of type %s', ref $type;
			}
		} else {
			$type = '' unless defined $type;
			$type = '' if $type eq 'string';
			if ( $type ne ref $value ) {
				if ( ref $value ) {
					push @error_fmt, 'argument "%s" should be a %sref, not a %sref';
					push @error_data, $key, $type, ref $value;
				} else {
					push @error_fmt, 'argument "%s" should be a %sref, not a scalar';
					push @error_data, $key, $type;
				}
				next;
			}
		}
	}
	while ( my ( $key, $type ) = each %$defs ) {
		my $required = 0;
		if ( ref $type and ref $type eq 'REQUIRED' ) {
			unless ( exists $opts{ $key } ) {
				push @error_fmt, 'required argument "%s" is missing';
				push @error_data, $key;
				next;
			}
		}
	}

	if ( @error_fmt ) {
		local $" = ', ';
		@_ = ( "argument parsing failed: @error_fmt", @error_data );
		goto \&throw;
	}

	return %opts;
}

sub REQUIRED($)
{
	my $self = \shift;
	bless $self, 'REQUIRED';
}


1;

# vim: ts=4:sw=4:fdm=marker
