#!/usr/bin/perl
use strict;
use warnings;
use RSGet::Mux;
use RSGet::Forks;

sub start0
{
	my $pid = open my $in, "-|", "ls", "-l";
	RSGet::Forks::add( $pid,
		from_child => $in,
		readline => \&on_line,
		at_exit => \&bye,
	);
}

sub start1
{
	my $pid = open my $in, 'for F in *; do echo "$F"; usleep 100000; done |';
	RSGet::Forks::add( $pid,
		from_child => $in,
		readline => \&on_line,
		at_exit => \&bye,
	);
}

sub start2
{
	my $pid = open my $in, 'for F in *; do echo -n "$F"; usleep 300000; done |';
	RSGet::Forks::add( $pid,
		from_child => $in,
		readline => \&on_line,
		at_exit => \&bye,
	);
}

sub start3
{
	my $pid = open my $in, 'for F in *; do echo -n "$F"; usleep 300000; done |';
	RSGet::Forks::add( $pid,
		from_child => $in,
		read => \&on_line,
		at_exit => \&bye,
	);
}

sub start4
{
	my $pid = open my $in, 'ls -l |';
	RSGet::Forks::add( $pid,
		from_child => $in,
		at_exit => \&bye,
	);
}

my @tests = (
	\&start1,
	\&start2,
	\&start3,
	\&start4,
);


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
	my $text = shift;

	print "Kid exited $pid: $code";
	if ( defined $text ) {
		print " [[[\n$text]]]";
	}
	print "\n";

	my $start = shift @tests;
	return unless $start;
	&$start();
}

start0();

RSGet::Mux::main_loop();

warn "Ended\n";

# vim:ts=4:sw=4
