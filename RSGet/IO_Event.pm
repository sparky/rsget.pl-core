package RSGet::IO_Event;
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

# use * and constants {{{
use strict;
use warnings;
use Scalar::Util ();
use Time::HiRes qw(time);
use RSGet::Common qw(import throw);

use constant {
	IO_READ => 1,
	IO_WRITE => 2,
	IO_EXCEPT => 4,
};
use constant
	IO_ANY => IO_READ | IO_WRITE | IO_EXCEPT;

my @_vec = ('', '', '', '');
use constant {
	_VEC_READ => 0,
	_VEC_WRITE => 1,
	_VEC_EXCEPT => 2,
	_VEC_ANY => 3,
};

my @_callbacks;
use constant {
	_CB_BITS => 0, # RWE
	_CB_OBJECT => 1,
	_CB_METHOD => 2,
};
# }}}

=head1 package RSGet::IO_Event

Automatically call methods on read and write events.

=head2 RSGet::IO_Event->add( EVENT, HANDLE, OBJECT, METHOD );

Add OBJECT with associated HANDLE to io event call list. EVENT is a bitmask
consisting of IO_READ | IO_WRITE | IO_EXCEPT.

On any io event that has been registered the method will be called as follows:

	OBJECT->METHOD( EVENT, FILENO );

Class name can be used instead of an object. EVENT is a bitmask of events
that ocurred on the registered handle. FILENO is the file number used by the
handle.

=cut
sub add($$$$$) # {{{
{
	my ( $class, $event_bits, $handle, $object, $method ) = @_;

	throw 'object %s has no method "%s"', $object, $method
		unless $object->can( $method );

	# fileno
	my $fn = Scalar::Util::looks_like_number( $handle )
		? $handle
		: $handle->fileno();

	# what should we listen for
	my $bits = $_callbacks[ $fn ] ? $_callbacks[ $fn ]->[ _CB_BITS ] : 0;
	$bits |= $event_bits;

	# add to callbacks list
	$_callbacks[ $fn ] = [ $bits, $object, $method ];

	# update select vectors
	my $select_bit = '';
	vec ( $select_bit, $fn, 1 ) = 1;
	$_vec[ _VEC_READ   ] |= $select_bit if $event_bits & IO_READ;
	$_vec[ _VEC_WRITE  ] |= $select_bit if $event_bits & IO_WRITE;
	$_vec[ _VEC_EXCEPT ] |= $select_bit if $event_bits & IO_EXCEPT;
	$_vec[ _VEC_ANY ] = $_vec[ _VEC_READ ]
		| $_vec[ _VEC_WRITE ] | $_vec[ _VEC_EXCEPT ];

	return $bits;
} # }}}


=head2 RSGet::IO_Event->remove( EVENT, HANDLE );

Remove OBJECT associated with HANDLE from call list. EVENT will normally
be IO_ANY, it removes all the events.

=cut
sub remove($$$) # {{{
{
	my ( $class, $event_bits, $handle ) = @_;

	# fileno
	my $fn = Scalar::Util::looks_like_number( $handle )
		? $handle
		: $handle->fileno();

	return 0 unless $_callbacks[ $fn ];

	my $bits = 0;
	if ( $event_bits == IO_ANY ) {
		delete $_callbacks[ $fn ];
	} else {
		$bits = $_callbacks[ $fn ]->[ _CB_BITS ] &= ~$event_bits;
		unless ( $bits ) {
			delete $_callbacks[ $fn ];
		}
	}

	my $select_bit = $_vec[ _VEC_ANY ];
	vec ( $select_bit, $fn, 1 ) = 0;
	$_vec[ _VEC_READ   ] &= $select_bit if $event_bits & IO_READ;
	$_vec[ _VEC_WRITE  ] &= $select_bit if $event_bits & IO_WRITE;
	$_vec[ _VEC_EXCEPT ] &= $select_bit if $event_bits & IO_EXCEPT;
	$_vec[ _VEC_ANY ] = $_vec[ _VEC_READ ]
		| $_vec[ _VEC_WRITE ] | $_vec[ _VEC_EXCEPT ];

	return $bits;
} # }}}


=head2 RSGet::IO_Event::perform( TIMEOUT );

Perform io select on all registered handles, blocking for TIMEOUT
seconds. Will call OBJECT->METHOD() for each active HANDLE.

Process will repeat until TIMEOUT (fractional) seconds have passed.

=cut
sub perform($) # {{{
{
	my $t_wait = shift;
	my $t_end = $t_wait + time();

	do {
		my ($r, $w, $e);

		my $n = select
			$r = $_vec[ _VEC_READ ],
			$w = $_vec[ _VEC_WRITE ],
			$e = $_vec[ _VEC_ANY ],
			$t_wait;

		# finish quickly if there were no events
		return unless $n;

		my $any = $r | $w | $e;
		foreach my $fn ( 1..(scalar @_callbacks) ) {
			next unless vec ( $any, $fn, 1 );
			my $cb = $_callbacks[ $fn ]
				or next;

			my $bits = 0;
			$bits |= IO_READ   if vec ( $r, $fn, 1 );
			$bits |= IO_WRITE  if vec ( $w, $fn, 1 );
			$bits |= IO_EXCEPT if vec ( $e, $fn, 1 );

			eval {
				my $func = $cb->[ _CB_METHOD ];
				$cb->[ _CB_OBJECT ]->$func( $bits, $fn );
			};
			warn $@ if $@;
		}

		$t_wait = $t_end - time;
	} while ( $t_wait > 0 );

	return;
} # }}}

1;

# vim: ts=4:sw=4:fdm=marker
