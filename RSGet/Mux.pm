package RSGet::Mux;
# This file is an integral part of rsget.pl downloader.
#
# 2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
use Time::HiRes qw(time sleep);

=head1 RSGet::Mux -- time division multiplexing

This package implements time multiplexing functions.

During initialization functions may be added to short or long interval call
list. After initialization program should call main_loop() which will be
calling all those functions in order. It never returns.

Functions in short interval will be called every 200ms (unless they require
more time to execute).

Functions in long interval are called every 2 seconds, more under heavy load.
=cut


# function list, called every 200ms
my %interval_short;
my $time_short = 0.2;

# function list, called once every 10 times short list is called
my %interval_long;

=head2 $RSGet::Mux::start_short, $RSGet::Mux::start_long

Initialization time of short and long bursts. May be used to keep different
functions in sync.
=cut
our $start_short;
our $start_long;


# Run all short functions.
sub _run_short
{
	foreach my $fname ( sort keys %interval_short ) {
		my $func = $interval_short{ $fname };

		# something may have removed that function
		next unless $func;

		# run !
		eval {
			&$func();
		};
		if ( $@ ) {
			warn "RSGet::Mux::_run_short: Function $fname died\n";
		}
	}
}

# Run one long function from @run_long list
my @run_long;
sub _run_long
{
	my $fname = shift @run_long;
	# list may be empty already
	return unless $fname;

	my $func = $interval_long{ $fname };
	# something may have removed that function
	return unless $func;

	# run !
	eval {
		&$func();
	};
	if ( $@ ) {
		warn "RSGet::Mux::_run_long: Function $fname died\n";
		return 0;
	}

	# success
	return 1;
}


=head2 RSGet::Mux::main_loop( )

Main loop function, must be called after initialization.
=cut
sub main_loop
{
	my $count = 10;
	while (1) {
		$start_short = time;
		if ( not %interval_short and not %interval_long ) {
			warn "RSGet::Mux::main_loop: nothing to call, returning\n";
			return;
		}
		if ( ++$count > 10 and not @run_long ) {
			$count = 0;
			@run_long = sort keys %interval_long;
			$start_long = $start_short;
		}

		_run_short();

		# run one long job, and see whether we have got time to run more
		my $time_left;
		my $job;
		do {
			$job = _run_long();
			my $stop = time;
			$time_left = $time_short - ( $stop - $start_short );
		} while ( $job and $time_left > $time_short / 4 );

		sleep $time_left if $time_left > 0;
	}
}

=head2 RSGet::Mux::add_short( name1 => CODE1, name2 => CODE2, ... )

Add name => CODE pairs to short interval list.

 RSGet::Mux::add_short
 	0early_func1 => sub { ... },
 	9late_func2 => \&function;
=cut
sub add_short
{
	my %func = @_;
	@interval_short{ keys %func } = values %func;
}

=head2 RSGet::Mux::add_long( name1 => CODE1, name2 => CODE2, ... )

Add name => CODE pairs to long interval list.
=cut
sub add_long
{
	my %func = @_;
	@interval_long{ keys %func } = values %func;
}

=head2 RSGet::Mux::remove_short( "name1", "name2", ... )

Remove functions with specified names from short interval list.

 RSGet::Mux::remove_short "0early_func1", "9late_func2";
=cut
sub remove_short
{
	delete @interval_short{ @_ };
}

=head2 RSGet::Mux::remove_long( "name1", "name2", ... )

Remove functions with specified names from long interval list.

=cut
sub remove_long
{
	delete @interval_long{ @_ };
}

1;

# vim: ts=4:sw=4:fdm=marker
