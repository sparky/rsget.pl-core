package RSGet::Interval;
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
use RSGet::IO_Event;
use Time::HiRes qw(time);

=head1 RSGet::Interval -- implements main loop and periodical callbacks

This package implements time multiplexing functions.

Functions may be added to interval call list. After initialization
program should call main_loop() which will be
calling all those functions in order. It never returns.

Functions are called every 1 second.

=cut

# how much time each iteration should take
my $time_loop = 1.0;

# minimum time for IO_Event
my $time_iomin = 0.5;

# function list
my %callbacks;

=head2 $RSGet::Interval::time_start

Initialization time. May be used to keep different functions in sync.

=cut
our $time_start;


# Run all callback functions.
sub _run_callbacks() # {{{
{
	foreach my $fname ( sort keys %callbacks ) {
		my $func = $callbacks{ $fname };

		# func may not be in the %callbacks list any more
		next unless $func;

		# run !
		eval {
			&$func();
		};
		if ( $@ ) {
			warn "RSGet::Interval::_run_callbacks: Function $fname died: $@\n";
		}
	}
} # }}}


=head2 RSGet::Interval::main_loop( )

Main loop function, must be called after initialization.

=cut
sub main_loop() # {{{
{
	while (1) {
		$time_start = time;

		_run_callbacks();

		my $time_left = $time_loop + $time_start - time;

		RSGet::IO_Event::perform(
			$time_left > $time_iomin ? $time_left : $time_iomin
		);
	}
} # }}}


=head2 RSGet::Interval::add( name1 => CODE1, name2 => CODE2, ... )

Add name => CODE pairs to callback list.

	RSGet::Interval::add
		0early_func1 => sub { ... },
		9late_func2 => \&function;
=cut
sub add(%) # {{{
{
	my %func = @_;
	@callbacks{ keys %func } = values %func;
} # }}}


=head2 RSGet::Interval::remove( "name1", "name2", ... )

Remove functions with specified names from callback list.

	RSGet::Interval::remove "0early_func1", "9late_func2";

=cut
sub remove(@) # {{{
{
	delete @callbacks{ @_ };
} # }}}


1;

# vim: ts=4:sw=4:fdm=marker
