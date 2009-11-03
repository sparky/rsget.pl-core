package RSGet::MortalObject;
# This file is an integral part of rsget.pl downloader.
#
# 2009 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
use RSGet::Tools;
set_rev qq$Id: Wait.pm 10652 2009-10-02 15:28:26Z sparky $;

# This is object holder, which will destroy the object if it doesn't
# receive heartbeat for some amount of time. It is used to prevent leaking
# memory, expecially in http interface.

my %holders;
my $last_id = 0;

sub new
{
	my $class = shift;
	my $obj = shift;
	my %opts = @_;

	my $time = time;

	my $id = ++$last_id . "_" . randid();

	my $holder = {
		obj => $obj,
		start => $time,
		last => $time,
		die_after => $opts{die_after} || 10,
	};
	$holder->{kill_after} = $time + $opts{kill_after} if $opts{kill_after};
	$holders{ $id } = $holder;

	my $self = \$id;
	bless $self, $class;

	return $self;
}

sub from_id
{
	my $class = shift;
	my $id = shift;

	return undef unless exists $holders{ $id };
	my $self = \$id;
	bless $self, $class;
	return $self;
}

sub obj
{
	my $self = shift;
	my $id = $$self;

	my $h = $holders{ $id } or return undef;
	$h->{last} = time;
	return $h->{obj};
}

sub id
{
	my $self = shift;
	my $id = $$self;

	return undef unless $holders{ $id };
	return $id;
}

sub time_to_kill
{
	my $self = shift;
	my $id = $$self;

	my $h = $holders{ $id } or return undef;
	return undef unless $h->{kill_after};
	return $h->{kill_after} - time;
}

sub heartbeat
{
	my $self = shift;
	my $id = $$self;

	my $h = $holders{ $id } or return undef;
	$h->{last} = time;

	return 1;
}

sub update
{
	my $time = time;

	foreach my $id ( keys %holders ) {
		my $h = $holders{ $id };
		if ( $h->{last} + $h->{die_after} < $time ) {
			p "Mortal $id died\n" if verbose( 4 );
			delete $h->{obj};
			delete $holders{ $id };
		} elsif ( $h->{kill_after} and $h->{kill_after} < $time ) {
			p "Mortal $id killed\n" if verbose( 4 );
			delete $h->{obj};
			delete $holders{ $id };
		}
	}
	RSGet::Line::status( 'mortals' => scalar keys %holders );
}

1;

# vim: ts=4:sw=4
