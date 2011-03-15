package RSGet::Cron;
# This file is an integral part of rsget.pl downloader.
#
# Copyright (C) 2010-2011	Przemysław Iskra <sparky@pld-linux.org>
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
use RSGet::Interval;

# registered cron jobs
my @registered;

# last cron tick;
my $tick = time;

=head1 package RSGet::Cron

Handles periodical jobs. Does not guarantee exact execution time.
Guarantees execution even unver heavy load.

=head2 add SUB, PERIOD, [DELAY];

Register a function executed periodically.

=cut
sub add(&$;$)
{
	my $code = shift;
	my $period = int shift;
	my $delay = int ( shift || 0 );

	#warn "Adding $code to cron, run every $period, with $delay delay\n";
	die "RSGet::Cron::add: first argument must be coderef\n"
		unless ref $code eq "CODE";
	die "RSGet::Cron::add: period must be an integer > 0\n"
		unless $period > 0;
	if ( $delay >= $period or $delay < 0 ) {
		warn "RSGet::Cron::add: delay $delay is outside of [0,$period) range.\n";
		$delay %= $period;
		warn "RSGet::Cron::add: delay value clipped to $delay.\n";
	}

	push @registered, [ $code, $period, $delay ];

}

# execute a job in protected environment
sub _execute($)
{
	my $code = shift;

	local $@ = undef;
	local $_ = "RSGet::Config::File";

	eval {
		$code->();
	};
	if ( $@ ) {
		warn "Cron job returned an error: $@\n";
	}
}


=head2 _tick();

Give cron a chance to run its jobs. Ideally would be run once every second.

=cut
RSGet::Interval::add X_cron => \&_tick;
sub _tick()
{
	my $now = time;

	# do nothing if tick() is called to early
	return unless $now > $tick;

	my @to_run;

	# tick() may have been called more than 1 second ago.
	# Check all possible time values until now, to make sure
	# we don't miss anything.
	for ( my $time = $tick + 1; $time <= $now; $time++ ) {
		foreach my $job ( @registered ) {
			# $time % $period == $delay
			if ( $time % $job->[1] == $job->[2] ) {
				my $code = $job->[0];

				# execute only once
				push @to_run, $code
					unless grep { $_ eq $code } @to_run;
			}
		}
	}
	$tick = $now;

	_execute( $_ ) foreach @to_run;
}

1;

# vim: ts=4:sw=4:fdm=marker
