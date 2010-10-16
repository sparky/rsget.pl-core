package RSGet::Cron;
# This file is an integral part of rsget.pl downloader.
#
# 2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;

# registered cron jobs
my @registered;

# last cron tick;
my $tick = time;

=head1 package RSGet::Cron

Handles periodical jobs. Long period (over 1 sec). Assures execution.

=head2 add SUB, PERIOD, [DELAY];

Register a function executed periodically.

=cut
sub add(&$;$)
{
	my $code = shift;
	my $period = int shift;
	my $delay = int ( shift || 0 );

	warn "Adding $code to cron, run every $period, with $delay delay\n";
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
	eval {
		$code->();
	};
	if ( $@ ) {
		warn "Cron job returned an error: $@\n";
	}
}


=head2 tick;

Give cron a chance to run its jobs. Ideally would be run once every second.

=cut
sub tick()
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
