#!/usr/bin/perl
use strict;
use warnings;
use RSGet::Mux;
use RSGet::Forks;

{
	my $pid = open my $in, "-|", "ls", "-l";
	RSGet::Forks::add( $pid,
		from_child => $in,
		readline => \&on_line,
		at_exit => \&bye,
	);
}

{
	my $pid = open my $in, 'for F in *; do echo "$F"; sleep 1; done |';
	RSGet::Forks::add( $pid,
		from_child => $in,
		readline => \&on_line,
		at_exit => \&bye,
	);
}

sub on_line
{
	my $pid = shift;
	my $line = shift;

	print "$pid: $line\n";
}

sub bye
{
	my $pid = shift;
	my $code = shift;

	print "Kid exited $pid: $code\n";
}

RSGet::Mux::main_loop();

warn "Ended\n";

# vim:ts=4:sw=4
