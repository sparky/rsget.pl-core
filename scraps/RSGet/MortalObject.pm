package RSGet::MortalObject;
# This file is an integral part of rsget.pl downloader.
#
# 2009-2010 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under GPL v2 or newer.

use strict;
use warnings;
use RSGet::Common;
use RSGet::Mux;

# This is object holder, which will destroy the object if it doesn't
# receive heartbeat for some amount of time. It is used to prevent leaking
# memory, expecially in http interface.

my %group;

# create new MO group
# accepts default values
sub new
{
	my $class = shift;
	my %opts = @_;

	my $gid;
	do {
		$gid = irand 1 << 32;
	} while ( exists $group{ $gid } );

	my $group = $group{ $gid } = {};

	my $self = \%opts;
	$self->{gid} = $gid;
	$self->{group} = $group;

	return bless $self, $class;
}

# free all objects belonging to this group
sub DESTROY
{
	my $self = shift;

	delete $group{ $self->{gid} };
}

# add new object to mortal group
sub add
{
	my $self = shift;
	my $obj = shift;
	my %opts = @_;

	my $group = $self->{group};

	my $id;
	do {
		$id = irand 1 << 31;
	} while ( exists $group->{ $id } );

	my $time = time;
	
	my $holder = {
		obj => $obj,
		start => $time,
		last => $time,
		die_after => defined $opts{die_after} ? $opts{die_after} :
			defined $self->{die_after} ? $self->{die_after} :
			10,
	};
	my $ka = $self->{kill_after};
	$ka = $opts{kill_after}
		if exists $opts{kill_after};
	$holder->{kill_at} = $time + $ka
		if defined $ka;

	if ( $opts{warn_after} ) {
		if ( $obj->can( "_warn_inactive" ) ) {
			$holder->{warn_after} = $opts{warn_after};
		} else {
			warn "Object $obj does not accept inactivity warnings\n";
		}
	}

	$group->{ $id } = $holder;

	RSGet::Mux::add_long( mo => \&_update );

	return $id;
}

# ping and return object
# my $obj = $group->get( $id );
# returns undef if object not found
sub get
{
	my $self = shift;
	my $id = shift;

	# make it perl-like number
	$id |= 0;

	my $h = $self->{group}->{ $id };
	return undef
		unless $h;

	$h->{last} = time;
	return $h->{obj};
}

# remove and return object
# my $obj = $group->del( $id );
# returns undef if object not found
sub del
{
	my $self = shift;
	my $id = shift;

	# make it perl-like number
	$id |= 0;

	my $h = $self->{group}->{ $id };
	return undef
		unless $h;
	delete $self->{group}->{ $id };

	return $h->{obj};
}

# return ids of all objects in group
# my $ids = $group->ids();
# my @ids = $group->ids();
# returns undef or empty list if there are none
sub ids
{
	my $self = shift;

	my @ids = keys %{ $self->{group} };
	return unless @ids;
	return @ids
		if wantarray;
	return \@ids;
}

# return all objects in group
# my $objs = $group->all();
# my @objs = $group->all();
# returns undef or empty list if there are none
sub all
{
	my $self = shift;

	my @all = map { $_->{obj} } values %{ $self->{group} };
	return unless @all;
	return @all
		if wantarray;
	return \@all;
}

# return all id => object pairs in group
# my $hash = $group->hash();
# my %hash = $group->hash();
# returns undef or empty hash if there are none
sub hash
{
	my $self = shift;

	my $group = $self->{group};
	my %hash = map { $_ => $group->{$_}->{obj} } keys %$group;
	return unless %hash;
	return %hash
		if wantarray;
	return \%hash;
}

# update objects
# should be called once every second
sub _update
{
	my $time = time;

	my $alive = 0;
	foreach my $group ( values %group ) {
		foreach my $id ( keys %$group ) {
			my $h = $group->{ $id };
			my $inactive = $time - $h->{last};
			if ( $inactive > $h->{die_after} ) {
				p "Mortal $id died\n" if verbose( 4 );
				delete $group->{ $id };
			} elsif ( $h->{kill_at} and $h->{kill_at} < $time ) {
				p "Mortal $id killed\n" if verbose( 4 );
				delete $group->{ $id };
			} elsif ( $h->{warn_after} and $inactive > $h->{warn_after} ) {
				$h->_warn_inactive( $inactive );
			} else {
				$alive = 1;
			}
		}
	}

	RSGet::Mux::remove_long( "mo" ) unless $alive;
	#RSGet::Line::status( 'mortals' => scalar keys %holders );
}

1;

# vim: ts=4:sw=4:fdm=marker
